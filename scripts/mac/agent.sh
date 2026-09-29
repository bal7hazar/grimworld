#!/opt/homebrew/bin/bash
# Grim World launcher of track CV, on the owner's Mac: start, resume, watch and stop a sub-agent in
# its task worktree. The port of scripts/agent.sh (frozen, systemd-only) to macOS: the same contract
# (OPERATIONS.md §3–§4, docs/briefs/CV-01-mac-launcher.md), other mechanics.
#
# - Shell: bash 5, /opt/homebrew/bin/bash (the shebang; checked below). macOS's /bin/bash 3.2 has no
#   `{fd}` redirections, which the slot probes use: it is refused.
# - Detached: every agent, claude or codex, is a launchd job of the user's GUI domain
#   (`launchctl bootstrap gui/<uid> <plist>`), never a child of the calling session, so that closing
#   the desktop app does not stop it. RunAtLoad true, KeepAlive false: it runs once and is never
#   restarted (a restart would be a relaunch from scratch; `launchctl submit` is never used). Its label
#   is recorded in logs/<task>.label and every later act on it (stop, bootout) names that exact label.
# - Environment built from nothing: the job starts `/usr/bin/env -i` with a whitelist (build_env),
#   whatever the caller or launchd hold. The desktop app's sessions carry the Sepolia account, the
#   Atlantic key, the registry token and the app's own tokens: none reaches an agent.
# - Budget of 2 agents at a time on the Mac, audits included (ORCH-client-visual §3), counted by
#   kernel locks on the slot files ~/orchestrator/slots/cv-1 and cv-2, never by reading processes.
# - Account: claude agents run on claude-b7r (CLAUDE_CONFIG_DIR=~/.claude-b7r), checked before
#   every launch and resume; the owner's own configuration (~/.claude, bal7hazar) is never used.
# Agents never run with --dangerously-skip-permissions: each launch passes a profile of
# scripts/profiles/ (read as scripts/agent.sh reads it) plus the Mac deny rules below.
#
# usage:
#   scripts/mac/agent.sh [options] <task> <claude|codex> <model> <new|resume> "<prompt>" [profile] [sid] [effort]
#   scripts/mac/agent.sh status              one line per known task, then the slots
#   scripts/mac/agent.sh wait <task>         block until the job of <task> has exited, then boot it out
#   scripts/mac/agent.sh sid <task>          codex session id of <task> (for `resume`)
#   scripts/mac/agent.sh model <task>        the model that actually ran, as the CLI recorded it
#   scripts/mac/agent.sh thresholds          may an agent start now? (load, memory, a free slot; exit 4 if not)
#   scripts/mac/agent.sh slots               who holds each slot
#   scripts/mac/agent.sh slots-init          create missing slot files (never replaces one); directory read-only
#   scripts/mac/agent.sh stop <task>         stop the task's own job, by its recorded label
# options:
#   --dry-run            print what would be launched, launch nothing, check nothing on the machine
#   --with-assets        initialise the `assets` submodule in the task worktree before launching
#   --branch <name>      create the worktree from origin/main on branch <name> if it is missing
#   (--with-sepolia is refused: no task of track CV holds the Sepolia account)
# arguments: as scripts/agent.sh (model: sonnet | opus | fable or their full ids, claude-sonnet-5 to
#   resume only; codex: gpt-6-astra | gpt-6-sol | gpt-6-luna. profile: research | implement | audit,
#   default research for claude new, audit for codex, the recorded one on resume).
# exit codes: 0 done; 2 refused (usage, record, model, profile, launch failure); 4 thresholds or
#   budget; 5 account.
# files, under <main checkout>/.claude/worktrees/:
#   cli-<task>/            the task worktree
#   logs/<task>.log        the agent's output; each run starts with a `--- …` header and ends with
#                          `model=<what ran>` and `exit=<status> <utc>`
#   logs/<task>.label      the launchd label of the last launch (status, wait, stop; never the budget)
#   logs/<label>.plist     the job's definition, written by the launcher
#   logs/<task>.profile    the profile of the launch, kept by `resume`
#   logs/<task>.cli        the CLI and the model id asked for, checked against the one that ran
#   logs/<task>.run        the inner shell's record: slot-refused, slots-acquired, ended
#   logs/<task>.start      the log's size when the run started (its header's offset)
#   logs/<task>.last.md    codex only: its last message, the audit report
#   logs/tmp-<task>/       the agent's TMPDIR

# The shell first, in syntax bash 3.2 reads: nothing below runs under another bash.
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 5 ]; then
  echo "scripts/mac/agent.sh: needs bash 5 (/opt/homebrew/bin/bash), not ${BASH_VERSION:-this shell}" >&2
  exit 2
fi
set -euo pipefail

die() { echo "mac/agent.sh: $*" >&2; exit 2; }
[ "$(uname -s)" = Darwin ] || die "this launcher is for macOS; on the VPS use scripts/agent.sh"
for x in /usr/bin/lockf /usr/bin/caffeinate /bin/launchctl /usr/bin/plutil /usr/bin/perl /opt/homebrew/bin/jq; do
  [ -x "$x" ] || die "$x is missing"
done

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
UID_N=$(id -u)
UNAME=$(id -un)
DOMAIN=gui/$UID_N
# The user's home and login shell come from the user database, not from the caller's environment.
REAL_HOME=$(/usr/bin/perl -e 'print((getpwuid($<))[7])')
LOGIN_SHELL=$(/usr/bin/perl -e 'print((getpwuid($<))[8])')
ACCOUNT=claude-b7r@proton.me

# Test mode (scripts/mac/test.sh). The launcher runs with the user's real home, or refuses; the only
# other home it accepts is a test home: a folder scripts/mac/test/run.<id> of this checkout, owned by
# the user, holding the marker .grimworld-mac-test. Every test-only behaviour below is keyed on that
# home and on nothing else (no variable of the caller turns it on), and a test home cannot reach
# anything real: its slots, launch lock, repository and claude configuration are inside it, the CLIs
# must resolve to its stubs ($HOME/bin), and its labels are grimworld.cv.test.*.
TEST=0
if [ "$HOME" != "$REAL_HOME" ]; then
  h=$(cd "$HOME" 2> /dev/null && pwd -P) || h=""
  rest=${h#"$root/scripts/mac/test/run."}
  if [ -n "$h" ] && [ "$rest" != "$h" ] && [ -n "$rest" ] && [[ $rest =~ ^[A-Za-z0-9]+$ ]] &&
    [ -f "$h/.grimworld-mac-test" ] && [ "$(stat -f %u "$h")" = "$UID_N" ]; then
    TEST=1 HOME=$h
  else
    die "HOME is '$HOME', not the user's home $REAL_HOME: refused"
  fi
fi

if [ "$TEST" = 1 ]; then
  main=$HOME/repo
  LABEL_PREFIX=grimworld.cv.test.
else
  main=$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")
  LABEL_PREFIX=grimworld.cv.
fi
W=$main/.claude/worktrees
L=$W/logs
P=$root/scripts/profiles
ORCH=$HOME/orchestrator
SLOTS=$ORCH/slots
LAUNCH_LOCK=$ORCH/agent-launch.lock
# The agents' PATH, fixed: the node install that holds the claude CLI (a native binary installed by
# npm under node 22.22.2), asdf's shims (a worktree's pinned tools) and asdf itself (~/go/bin),
# ~/.local/bin (codex), Homebrew, the system. In test mode the stubs come first.
PATH_FIXED="$HOME/.asdf/installs/nodejs/22.22.2/bin:$HOME/.asdf/shims:$HOME/go/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
[ "$TEST" = 0 ] || PATH_FIXED="$HOME/bin:$PATH_FIXED"

# The title tag of every job, log line and session: the model's display name, never guessed
# (the table of scripts/agent.sh).
tag() { # <cli> <model> -> "<full id>|<display name>"
  case "$1:$2" in
    claude:sonnet | claude:claude-sonnet-5-5) echo "claude-sonnet-5-5|Sonnet 5.5" ;;
    claude:claude-sonnet-5) echo "claude-sonnet-5|Sonnet 5" ;;   # only to resume agents started on it
    claude:opus | claude:claude-opus-5-5) echo "claude-opus-5-5|Opus 5.5" ;;
    claude:fable | claude:claude-fable-5-1) echo "claude-fable-5-1|Fable 5.1" ;;
    codex:gpt-6-astra) echo "gpt-6-astra|GPT-6-Astra" ;;
    codex:gpt-6-sol) echo "gpt-6-sol|GPT-6-Sol" ;;
    codex:gpt-6-luna) echo "gpt-6-luna|GPT-6-Luna" ;;
    *) die "unknown model '$2' for $1 (claude: sonnet|opus|fable, claude-sonnet-5 to resume; codex: gpt-6-astra|gpt-6-sol|gpt-6-luna)" ;;
  esac
}

# Profile file, read exactly as scripts/agent.sh reads it: one permission rule per line; `!rule` is
# a deny rule; `@name` includes the profile `name`; `#` starts a comment.
read_profile() { # <profile> <depth>: appends to the arrays allow and deny
  local f=$P/$1.txt line
  case "$1" in research | audit | implement) ;; *) die "unknown profile '$1' (research | audit | implement)" ;; esac
  [ -f "$f" ] || die "no profile $f"
  [ "$2" -lt 4 ] || die "profile includes nested too deep at $1"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$line" in
      "") ;;
      @*) read_profile "${line:1}" $(($2 + 1)) ;;
      !*) deny+=("${line:1}") ;;
      *) allow+=("$line") ;;
    esac
  done < "$f"
}
load_profile() { # <profile> -> fills the arrays allow and deny
  allow=() deny=()
  read_profile "$1" 0
  [ "${#allow[@]}" -gt 0 ] || die "profile $1 grants nothing"
}
# The profiles were written for the VPS. On the Mac the launcher appends these deny rules: no
# launchd, no opening apps or scripting them, no sleep assertion, no keychain, no launcher of this
# track, and no reading of the agents' own credentials (claude-b7r, codex, gh), by `~`, `$HOME` and
# the absolute path of the home (the profiles name /home/claude, the VPS's home, only).
# shellcheck disable=SC2016 # `$HOME` is literal text of the rules
MAC_DENY=('Bash(launchctl*)' 'Bash(* launchctl*)' 'Bash(open *)' 'Bash(osascript*)' 'Bash(caffeinate*)'
  'Bash(security *)' 'Bash(scripts/mac/agent.sh*)' 'Bash(./scripts/mac/agent.sh*)'
  'Bash(bash scripts/mac/agent.sh*)' 'Read(~/.claude-b7r/**)' 'Read(~/.codex/**)' 'Read(~/.config/gh/**)'
  'Bash(* ~/.claude-b7r*)' 'Bash(* $HOME/.claude-b7r*)'
  "Read(/$HOME/.claude-b7r/**)" "Read(/$HOME/.claude/**)" "Read(/$HOME/.codex/**)" "Read(/$HOME/.config/gh/**)"
  "Bash(* $HOME/.claude-b7r*)" "Bash(* $HOME/.claude/*)" "Bash(* $HOME/orchestrator*)")

# launchd: the state of a job, by its exact label.
job_print() { launchctl print "$DOMAIN/$1" 2> /dev/null; }
job_state() { # <label> -> running | not-running | absent
  local out
  out=$(job_print "$1") || { echo absent; return; }
  if grep -qE $'^\tstate = running$' <<< "$out"; then echo running; else echo not-running; fi
}
job_pid() { # <label> -> the pid launchd reports for it, or nothing
  local out
  out=$(job_print "$1") || return 0
  sed -nE $'/^\tpid = [0-9]+$/{s/^\tpid = //p;q;}' <<< "$out"
}
task_label() { cat "$L/$1.label" 2> /dev/null || true; }
running() { # <task>
  local label
  label=$(task_label "$1")
  [ -n "$label" ] && [ "$(job_state "$label")" = running ]
}
# A job that has exited stays loaded in launchd (KeepAlive false: it is never restarted) until it is
# booted out, by its exact label: by `wait`, `status`, `stop`, or the next launch of the task.
reap() { # <task>: boot out the task's job if it has exited; never one that runs
  local label
  label=$(task_label "$1")
  [ -n "$label" ] || return 0
  [ "$(job_state "$label")" = not-running ] || return 0
  launchctl bootout "$DOMAIN/$label" 2> /dev/null || true
}

# The model that actually ran, as the CLI itself recorded it (never the one that was asked for):
# claude writes it on every assistant message of its transcript (under ~/.claude-b7r, the agents'
# configuration), codex prints `model:` at the start of each run.
reported_model() { # <task>
  local cli expected wt dir f
  read -r cli expected < "$L/$1.cli" 2> /dev/null || { echo unknown; return; }
  if [ "$cli" = codex ]; then
    f=$(tail -c +$(($(cat "$L/$1.start" 2> /dev/null || echo 0) + 1)) "$L/$1.log" 2> /dev/null |
      grep -m1 -E '^model: ' || true)   # grep -m1 closes the pipe early: tail's SIGPIPE is fine
    f=${f#model: }
    echo "${f:-unknown}"
    return
  fi
  wt=$W/cli-$1
  dir=$HOME/.claude-b7r/projects/$(printf '%s' "$wt" | sed 's#[/.]#-#g')
  f=""
  if [ -d "$dir" ]; then
    f=$(find "$dir" -maxdepth 1 -name '*.jsonl' -exec stat -f '%m %N' {} + 2> /dev/null | sort -n |
      tail -1 | cut -d' ' -f2-)
  fi
  [ -n "$f" ] || { echo unknown; return; }
  grep -ho '"model":"[^"]*"' "$f" | cut -d'"' -f4 | grep -v '^<synthetic>$' | sort -u |
    paste -sd, - | grep . || echo unknown
}

# Machine thresholds, fixed here on purpose (no variable relaxes them): no agent starts or resumes
# while the 5-minute load average (sysctl vm.loadavg) is above 10 or less than 8 GB of memory is
# available. Available memory is free + inactive + speculative pages of vm_stat (the pages the
# kernel hands out without swapping; memory_pressure prints the same counters, more slowly). A
# running agent is never stopped for load.
MAX_LOAD5=10 MIN_MEM_GB=8
# The budget: 2 agents at a time on the Mac, audits included, as two slot files the agents hold by
# kernel locks. The slots are opened read-only (a missing one is an error, never a new slot) in a
# read-only directory (mode 555), so that a held slot cannot be removed or replaced by a new inode (a
# lock protects an inode, not a name); `slots-init` creates missing ones, only while every slot is
# free. Locks are flock(2) locks taken by /usr/bin/lockf on a descriptor (`lockf -s -t <s> <fd>`,
# macOS's own tool; there is no flock(1)): the lock belongs to the open file, which the inner shell
# and every child it starts share, so the kernel frees it when the last of them has ended, however it
# ends. lockf exits 75 when the lock is held.
SLOT_NAMES=(cv-1 cv-2)
slot_state() { # <slot> -> free | held | missing | unreadable | unlockable
  local f=$SLOTS/$1 fd rc=0
  if [ ! -f "$f" ]; then echo missing; return; fi
  if ! exec {fd}< "$f"; then echo unreadable; return; fi
  /usr/bin/lockf -s -t 0 "$fd" || rc=$?
  exec {fd}<&-
  case $rc in 0) echo free ;; 75) echo held ;; *) echo "unlockable (lockf exit $rc)" ;; esac
}
# The first free slot. Every slot is inspected first: one in error refuses, even if another is free.
first_free() {
  local x st first=""
  for x in "${SLOT_NAMES[@]}"; do
    st=$(slot_state "$x" 2> /dev/null)
    case $st in
      free) [ -n "$first" ] || first=$x ;;
      held) ;;
      *) echo "error: slot $x is $st"; return 2 ;;
    esac
  done
  [ -n "$first" ] || return 1
  echo "$first"
}
slots_ready() { # the slot directory exists, is read-only, and holds every slot file
  if [ ! -d "$SLOTS" ]; then echo "mac/agent.sh: no slot directory $SLOTS: run scripts/mac/agent.sh slots-init once" >&2; return 1; fi
  if [ -w "$SLOTS" ]; then chmod 555 "$SLOTS" 2> /dev/null || { echo "mac/agent.sh: $SLOTS cannot be made read-only: check it" >&2; return 1; }; fi
  local x
  for x in "${SLOT_NAMES[@]}"; do
    [ -f "$SLOTS/$x" ] || { echo "mac/agent.sh: the slot file $SLOTS/$x is missing: run scripts/mac/agent.sh slots-init" >&2; return 1; }
  done
}
take_launch_lock() { # holds the launch lock on descriptor LOCK_FD until this launcher exits
  mkdir -p "$ORCH"
  exec {LOCK_FD}>> "$LAUNCH_LOCK"
  /usr/bin/lockf -s -t 600 "$LOCK_FD" || die "the launch lock $LAUNCH_LOCK is held: try again"
}
init_slots() { # creates the missing slot files only (never replaces one), then makes the directory read-only
  take_launch_lock
  if [ -d "$SLOTS" ]; then
    local y st
    for y in "${SLOT_NAMES[@]}"; do
      [ -e "$SLOTS/$y" ] || continue
      st=$(slot_state "$y" 2> /dev/null)
      [ "$st" = free ] || { echo "mac/agent.sh: slot $y is $st: slots-init runs only while every slot is free" >&2; return 1; }
    done
  fi
  mkdir -p "$SLOTS" && chmod 755 "$SLOTS" || return 1
  local x
  for x in "${SLOT_NAMES[@]}"; do [ -e "$SLOTS/$x" ] || : > "$SLOTS/$x" || { chmod 555 "$SLOTS"; return 1; }; done
  chmod 555 "$SLOTS"
}
measure() { # sets LOAD5 and MEM_GB
  LOAD5=$(sysctl -n vm.loadavg | awk '{ print $3 }')
  MEM_GB=$(vm_stat | awk '
    /page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i + 1) }
    /^Pages (free|inactive|speculative):/ { gsub(/\./, "", $NF); n += $NF }
    END { if (ps > 0) printf "%d", n * ps / 1073741824; else print "?" }')
  if [ "$TEST" = 1 ]; then   # test-only: forced values, read from files of the test home
    [ ! -f "$HOME/test-load5" ] || LOAD5=$(cat "$HOME/test-load5")
    [ ! -f "$HOME/test-mem-gb" ] || MEM_GB=$(cat "$HOME/test-mem-gb")
  fi
}
thresholds_ok() { # prints the reason and returns 1 when a launch must wait; sets FREE_SLOT
  measure
  if ! [[ $LOAD5 =~ ^[0-9]+(\.[0-9]+)?$ && $MEM_GB =~ ^[0-9]+$ ]]; then
    echo "mac/agent.sh: cannot read load ('$LOAD5') or memory ('$MEM_GB'): wait and check again" >&2
    return 1
  fi
  if awk -v l="$LOAD5" -v m="$MAX_LOAD5" 'BEGIN { exit !(l > m) }'; then
    echo "mac/agent.sh: 5-minute load average $LOAD5 is above $MAX_LOAD5: wait and check again" >&2
    return 1
  fi
  if [ "$MEM_GB" -lt "$MIN_MEM_GB" ]; then
    echo "mac/agent.sh: $MEM_GB GB of memory available, under $MIN_MEM_GB: wait and check again" >&2
    return 1
  fi
  slots_ready || return 1
  local rc=0
  FREE_SLOT=$(first_free) || rc=$?
  if [ "$rc" = 2 ]; then echo "mac/agent.sh: $FREE_SLOT: the slots cannot be read, check them" >&2; return 1; fi
  if [ "$rc" != 0 ]; then
    echo "mac/agent.sh: the budget of ${#SLOT_NAMES[@]} agents on the Mac is in use (${SLOT_NAMES[*]} held): wait and check again" >&2
    return 1
  fi
  echo "mac/agent.sh: load $LOAD5, $MEM_GB GB available, slot $FREE_SLOT free: a launch may proceed"
}

# The job's environment, built from nothing (the brief's requirement 3): these names and nothing
# else. `/usr/bin/env -i` drops what launchd itself would pass. The shells add PWD, SHLVL and `_`,
# and caffeinate __CF_USER_TEXT_ENCODING (the text encoding of the user); none of them carries a
# value of the caller.
build_env() { # <cli> <tmpdir> -> fills the array envv
  envv=(HOME="$HOME" USER="$UNAME" LOGNAME="$UNAME" SHELL="$LOGIN_SHELL" LANG=en_US.UTF-8
    TMPDIR="$2" PATH="$PATH_FIXED" BASH_DEFAULT_TIMEOUT_MS=1800000 BASH_MAX_TIMEOUT_MS=3600000)
  [ "$1" != claude ] || envv+=(CLAUDE_CONFIG_DIR="$HOME/.claude-b7r")
}
# The account, before anything is created: claude must report, as JSON, one object with
# "loggedIn": true and the email of claude-b7r, in the agents' configuration; codex must report a
# login, of which only the kind is recorded (never the text, which may show part of a key).
check_account() { # <cli> <bin> -> sets ACCOUNT_DESC, or exits 5
  local out rc=0
  build_env "$1" "$(getconf DARWIN_USER_TEMP_DIR)"
  if [ "$1" = claude ]; then
    out=$(cd / && /usr/bin/env -i "${envv[@]}" "$2" auth status 2> /dev/null) || rc=$?
    if [ "$rc" != 0 ] || ! printf '%s' "$out" |
      /opt/homebrew/bin/jq -e -s --arg e "$ACCOUNT" \
        'length == 1 and (.[0] | type == "object" and .loggedIn == true and .email == $e)' > /dev/null 2>&1; then
      echo "mac/agent.sh: claude (CLAUDE_CONFIG_DIR=$HOME/.claude-b7r) is not logged in as $ACCOUNT (claude auth status, exit $rc): nothing launched" >&2
      exit 5
    fi
    ACCOUNT_DESC=$ACCOUNT
  else
    out=$(cd / && /usr/bin/env -i "${envv[@]}" "$2" login status 2>&1) || rc=$?
    if [ "$rc" != 0 ] || ! grep -q '^Logged in' <<< "$out"; then
      echo "mac/agent.sh: codex reports no login (codex login status, exit $rc): nothing launched" >&2
      exit 5
    fi
    case $out in
      *ChatGPT*) ACCOUNT_DESC=codex-chatgpt ;;
      *"API key"*) ACCOUNT_DESC=codex-api-key ;;
      *) ACCOUNT_DESC=codex-logged-in ;;
    esac
  fi
}

# $0 of the inner shell is the log file, "$@" the agent command line. It takes its slot ($GW_SLOT,
# opened read-only on descriptor 7, which the CLI and its children inherit) with `lockf -t 5` (a
# probe of the slots takes a lock for an instant: the wait absorbs it), writes `slots-acquired` to
# the run file, which the launcher waits for, then runs the agent. After the agent, it records the
# model that ran (`model=`) and the exit status. GW_TEST_HANG exists only in the environment of a
# test-mode job (the launcher sets it only there): it stands for a job that never reports.
# Single quotes on purpose: the inner shell expands them.
# shellcheck disable=SC2016
inner='exec 7< "$GW_SLOT" || exit 75
if [ "${GW_TEST_HANG:-}" = 1 ]; then sleep 600; fi
if ! /usr/bin/lockf -s -t 5 7; then echo "slot-refused $(date -u +%FT%TZ)" >> "$GW_RUN_FILE"; exit 75; fi
echo "slots-acquired $(date -u +%FT%TZ)" >> "$GW_RUN_FILE" || exit 75   # no marker, no agent: the launcher would report a failure
printf "%s\n" "$GW_SLOT_NAME" > "$GW_SLOT"
"$@" < /dev/null >> "$0" 2>&1; s=$?
echo "model=$("$GW_AGENT_SH" model "$GW_TASK" 2> /dev/null)" >> "$0"
echo "exit=$s $(date -u +%FT%TZ)" >> "$0"
echo "ended exit=$s $(date -u +%FT%TZ)" >> "$GW_RUN_FILE"'

# Stop a job by its exact label: its process group first (AbandonProcessGroup is true, so a bootout
# signals the main process only, and the agent's CLI would survive it), then the bootout. launchd
# starts a job as the leader of its own group (pgid = its pid); the group is signalled only when that
# holds, else the pid alone. Returns 0 when the stop is verified: the label is gone from launchd, the
# group is gone, and the slot (if named) is free again.
stop_job() { # <label> [slot]
  local label=$1 slot=${2:-} pid pgid=""
  alive() { kill -0 "$pid" 2> /dev/null || { [ -n "$pgid" ] && kill -0 -- "-$pgid" 2> /dev/null; }; }
  pid=$(job_pid "$label")
  if [ -n "$pid" ]; then
    pgid=$(ps -o pgid= -p "$pid" 2> /dev/null | tr -d ' ' || true)
    [ "$pgid" = "$pid" ] || pgid=""
    if [ -n "$pgid" ]; then kill -TERM -- "-$pgid" 2> /dev/null || true; else kill -TERM "$pid" 2> /dev/null || true; fi
    for _ in $(seq 1 50); do alive || break; sleep 0.1; done
    if alive; then
      if [ -n "$pgid" ]; then kill -KILL -- "-$pgid" 2> /dev/null || true; else kill -KILL "$pid" 2> /dev/null || true; fi
    fi
  fi
  launchctl bootout "$DOMAIN/$label" 2> /dev/null || true
  for _ in $(seq 1 30); do
    [ "$(job_state "$label")" = absent ] && break
    sleep 0.1
  done
  [ "$(job_state "$label")" = absent ] || return 1
  if [ -n "$pid" ] && alive; then return 1; fi
  if [ -n "$slot" ]; then
    for _ in $(seq 1 20); do
      [ "$(slot_state "$slot" 2> /dev/null)" = free ] && return 0
      sleep 0.1
    done
    return 1
  fi
  return 0
}

xml() { # XML text of a plist <string> (replacements quoted: bash 5.2 reads a bare & as the match)
  local s=$1
  s=${s//'&'/'&amp;'}; s=${s//'<'/'&lt;'}; s=${s//'>'/'&gt;'}
  printf '%s' "$s"
}
write_plist() { # <file> <label> <workdir> <log> <argv…>
  local f=$1 label=$2 wd=$3 log=$4 a
  shift 4
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
      '<plist version="1.0">' '<dict>'
    printf '<key>Label</key><string>%s</string>\n' "$(xml "$label")"
    printf '<key>ProgramArguments</key>\n<array>\n'
    for a in "$@"; do printf '<string>%s</string>\n' "$(xml "$a")"; done
    printf '</array>\n'
    printf '<key>RunAtLoad</key><true/>\n<key>KeepAlive</key><false/>\n<key>AbandonProcessGroup</key><true/>\n'
    printf '<key>Nice</key><integer>10</integer>\n'
    printf '<key>WorkingDirectory</key><string>%s</string>\n' "$(xml "$wd")"
    printf '<key>StandardOutPath</key><string>%s</string>\n' "$(xml "$log")"
    printf '<key>StandardErrorPath</key><string>%s</string>\n' "$(xml "$log")"
    printf '</dict>\n</plist>\n'
  } > "$f"
  plutil -lint -s "$f" > /dev/null || die "the job definition $f is not a valid plist"
}

case "${1:-}" in
  thresholds)
    thresholds_ok || exit 4
    exit 0 ;;
  slots)   # who holds each slot: the lock decides; the name written inside is for display only
    for x in "${SLOT_NAMES[@]}"; do
      st=$(slot_state "$x" 2> /dev/null)
      case $st in
        held) printf '%-5s held  %s\n' "$x" "$(head -1 "$SLOTS/$x" 2> /dev/null)" ;;
        *) printf '%-5s %s\n' "$x" "$st" ;;
      esac
    done
    exit 0 ;;
  slots-init)
    init_slots || die "cannot create the slots in $SLOTS"
    exit 0 ;;
  status)
    shopt -s nullglob
    for f in "$L"/*.log; do
      t=$(basename "$f" .log)
      expected=$(cut -d' ' -f2 "$L/$t.cli" 2> /dev/null || echo -)
      ran=$(reported_model "$t")
      [ "$ran" = "$expected" ] || [ "$ran" = unknown ] || ran="$ran MISMATCH(expected $expected)"
      # While running: the header of this run (at its recorded offset). Stopped: the last line of
      # the log, the inner shell's `exit=…`.
      if running "$t"; then state=running
        last=$(tail -c +$(($(cat "$L/$t.start" 2> /dev/null || echo 0) + 1)) "$f" 2> /dev/null | head -1 || true)
      else reap "$t"; state=stopped last=$(tail -1 "$f"); fi
      printf '%-24s %-8s %-10s ran=%-18s last write %s  %s\n' "$t" "$state" \
        "$(cat "$L/$t.profile" 2> /dev/null || echo -)" "$ran" "$(date -u -r "$f" +%FT%TZ)" "$last"
    done
    for x in "${SLOT_NAMES[@]}"; do
      st=$(slot_state "$x" 2> /dev/null)
      if [ "$st" = held ]; then echo "slot $x held $(head -1 "$SLOTS/$x" 2> /dev/null)"; else echo "slot $x $st"; fi
    done
    exit 0 ;;
  model)
    [ -n "${2:-}" ] || die "usage: mac/agent.sh model <task>"
    reported_model "$2"
    exit 0 ;;
  wait)
    [ -n "${2:-}" ] || die "usage: mac/agent.sh wait <task>"
    poll=5; [ "$TEST" = 0 ] || poll=0.5
    while running "$2"; do sleep "$poll"; done
    reap "$2"
    grep -E '^exit=[0-9a-z]+ [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$L/$2.log" 2> /dev/null | tail -1 || true
    echo "model=$(reported_model "$2")"
    exit 0 ;;
  sid)
    [ -n "${2:-}" ] || die "usage: mac/agent.sh sid <task>"
    wt=$W/cli-$2
    grep -l -F "\"cwd\":\"$wt\"" "$HOME"/.codex/sessions/*/*/*/rollout-*.jsonl 2> /dev/null |
      sort | tail -1 | sed -E 's/.*rollout-.{19}-(.*)\.jsonl$/\1/'   # names start with the date
    exit 0 ;;
  stop)   # the task's own job, by its recorded label, and nothing else
    [ -n "${2:-}" ] || die "usage: mac/agent.sh stop <task>"
    label=$(task_label "$2")
    [ -n "$label" ] || die "$2 has no recorded label ($L/$2.label): nothing to stop"
    if [ "$(job_state "$label")" = absent ]; then echo "$2: its job $label is not loaded"; exit 0; fi
    was=$(job_state "$label")
    if stop_job "$label"; then
      if [ "$was" = running ]; then
        echo "exit=stopped $(date -u +%FT%TZ)" >> "$L/$2.log"
        echo "ended stopped $(date -u +%FT%TZ)" >> "$L/$2.run"
      fi
      echo "$2: job $label stopped and booted out (verified)"; exit 0
    fi
    echo "mac/agent.sh: $2: job $label was signalled and booted out, but the stop is not verified: check it by hand (launchctl print $DOMAIN/$label)" >&2
    exit 1 ;;
esac

dry=0 assets=0 branch=""
while [ "${1:-}" != "${1#--}" ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --with-assets) assets=1 ;;
    --with-sepolia) die "--with-sepolia is refused on the Mac: no task of track CV holds the Sepolia account" ;;
    --branch) branch=${2:-}; [ -n "$branch" ] || die "--branch needs a name"; shift ;;
    *) die "unknown option $1" ;;
  esac
  shift
done
[ $# -ge 5 ] || die "usage: mac/agent.sh [--dry-run] [--with-assets] [--branch <b>] <task> <claude|codex> <model> <new|resume> \"<prompt>\" [profile] [sid] [effort]"
task=$1 cli=$2 model=$3 mode=$4 prompt=$5 profile=${6:-} sid=${7:-} effort=${8:-}
case "$task" in *[!A-Za-z0-9._-]* | "" | .*) die "task name '$task': letters, digits, . _ - only, not starting with a dot" ;; esac
case "$cli" in claude | codex) ;; *) die "cli must be claude or codex" ;; esac
case "$mode" in new | resume) ;; *) die "mode must be new or resume" ;; esac
t=$(tag "$cli" "$model")
model_id=${t%%|*} mtag=${t#*|}
wt=$W/cli-$task
# A resumed agent keeps the model and the profile it started with (OPERATIONS §2, §4): a resume
# needs the launch record, the same model, and no other profile. A new launch uses a current model
# and a fresh task: while the task's worktree exists with a record, the task is not closed.
if [ "$mode" = resume ]; then
  [ -f "$L/$task.cli" ] || die "$task has no launch record ($L/$task.cli): nothing to resume"
  read -r rcli recorded < "$L/$task.cli" || true
  [ "$rcli" = "$cli" ] || die "$task started on $rcli: resume it with $rcli"
  [ "$recorded" = "$model_id" ] || die "$task started on $recorded: resume it with that model, not $model_id"
  [ -f "$L/$task.profile" ] || die "$task has no recorded profile ($L/$task.profile)"
  rprofile=$(cat "$L/$task.profile")
  [ -z "$profile" ] || [ "$profile" = "$rprofile" ] || die "$task was launched with the profile $rprofile: a resume keeps it (not $profile)"
  profile=$rprofile
  [ -d "$wt" ] || die "$task has no worktree $wt: nothing to resume"
else
  [ "$model_id" != claude-sonnet-5 ] || die "claude-sonnet-5 only resumes agents started on it; new launches use sonnet (Sonnet 5.5)"
  if [ -f "$L/$task.cli" ] && [ -d "$wt" ]; then
    die "$task is not closed (its worktree exists): resume it, or close it before a new launch"
  fi
fi
if [ -z "$profile" ]; then
  if [ "$cli" = codex ]; then profile=audit; else profile=research; fi
fi
[ "$cli" = claude ] || [ "$profile" = audit ] || die "codex audits only: profile must be audit"
load_profile "$profile"
case $prompt in *[$'\001'-$'\010'$'\013'$'\014'$'\016'-$'\037']*) die "the prompt holds control characters" ;; esac

# Every launch prompt carries the foreground rule (OPERATIONS §3), word for word as scripts/agent.sh.
if [ "$cli" = claude ]; then end="Your turn ends when REPORT.md is written."
else end="You cannot write files: your final message is your report."; fi
prompt="$prompt

Foreground only: never run a command in the background and never end your turn waiting for one; in headless mode that ends the session. $end"

# The CLI, resolved once on the agents' PATH, so that the account check and the job run the same
# binary. In test mode it must be a stub of the test home.
bin=$(PATH=$PATH_FIXED command -v "$cli" 2> /dev/null || true)
if [ "$dry" = 1 ] && [ -z "$bin" ]; then bin=$cli; fi
[ -n "$bin" ] || die "$cli is not on the agents' PATH ($PATH_FIXED)"
if [ "$TEST" = 1 ] && [ "$bin" != "$HOME/bin/$cli" ]; then die "test mode: $cli resolves to $bin, not to the stub $HOME/bin/$cli"; fi

case "$cli:$mode" in
  claude:new)
    cmd=("$bin" -p "$prompt" --model "$model_id" --name "[$mtag] $task") ;;
  claude:resume)
    cmd=("$bin" --continue -p "$prompt" --model "$model_id") ;;
  codex:new)
    cmd=("$bin" exec -C "$wt" -m "$model_id" -c "model_reasoning_effort=${effort:-high}" -s read-only
      -o "$L/$task.last.md" "$prompt") ;;
  codex:resume)
    [ -n "$sid" ] || die "codex resume needs the session id (scripts/mac/agent.sh sid $task)"
    cmd=("$bin" exec resume "$sid" -m "$model_id" -c "model_reasoning_effort=${effort:-high}"
      -c 'sandbox_mode="read-only"' -o "$L/$task.last.md" "$prompt") ;;
esac
if [ "$cli" = claude ]; then
  # Defence in depth, as on the VPS: the user-level settings of a claude configuration may define
  # the registry token or the Sepolia account; --settings takes precedence and empties them.
  cmd+=(--settings '{"env":{"SCARB_REGISTRY_AUTH_TOKEN":"","STARKNET_NETWORK":"","STARKNET_RPC_URL":"","STARKNET_RPC":"","STARKNET_ACCOUNT_ADDRESS":"","STARKNET_PRIVATE_KEY":"","ATLANTIC_API_KEY":""}}')
  cmd+=(--permission-mode acceptEdits --allowedTools "${allow[@]}")
  cmd+=(--disallowedTools "${deny[@]}" "${MAC_DENY[@]}")
  cmd+=(--max-turns 400 --output-format text)
  [ -z "$effort" ] || cmd+=(--effort "$effort")
fi

label="$LABEL_PREFIX$task.$(date -u +%H%M%S)"
desc="[$mtag] $task $mode ($profile)"
tmp=$L/tmp-$task

if [ "$dry" = 1 ]; then
  echo "# $desc"
  echo "# worktree $wt  log $L/$task.log  launchd job $DOMAIN/$label  with-assets=$assets"
  printf '%q ' "${cmd[@]}"
  echo
  exit 0
fi

# Nothing is created before the account is checked.
check_account "$cli" "$bin"

# One launch at a time (the lock is held until this launcher exits, after `slots-acquired`), so two
# launchers cannot both take the last slot. A launchd job inherits no descriptor from here.
take_launch_lock
reap "$task"
if running "$task"; then die "$task: already running (job $(task_label "$task"))"; fi
thresholds_ok || exit 4   # sets FREE_SLOT
slot=$SLOTS/$FREE_SLOT
if [ ! -d "$wt" ]; then
  [ -n "$branch" ] || die "no worktree $wt (create it, or pass --branch cv/<task-id>-<slug>)"
  git -C "$main" fetch -q origin main
  git -C "$main" worktree add -q --no-track "$wt" -b "$branch" origin/main
fi
if [ "$assets" = 1 ]; then
  git -C "$wt" submodule update --init assets
fi
mkdir -p "$L" "$tmp"
[ "$(job_state "$label")" = absent ] || die "a job $label is already loaded: launch again in a second"

echo "$profile" > "$L/$task.profile"
echo "$cli $model_id" > "$L/$task.cli"
stat -f %z "$L/$task.log" 2> /dev/null > "$L/$task.start" || echo 0 > "$L/$task.start"
echo "--- $(date -u +%FT%TZ) $desc $cli $model_id label=$label account=$ACCOUNT_DESC" >> "$L/$task.log"
echo "$label" > "$L/$task.label"
run_file=$L/$task.run
: > "$run_file"
build_env "$cli" "$tmp/"
envv+=(GW_AGENT_SH="$root/scripts/mac/agent.sh" GW_TASK="$task" GW_SLOT="$slot"
  GW_SLOT_NAME="$task (job $label, $(date -u +%FT%TZ))" GW_RUN_FILE="$run_file")
if [ "$TEST" = 1 ] && [ -f "$HOME/test-hang" ]; then envv+=(GW_TEST_HANG=1); fi
plist=$L/$label.plist
write_plist "$plist" "$label" "$wt" "$L/$task.log" \
  /usr/bin/env -i "${envv[@]}" /usr/bin/caffeinate -i /opt/homebrew/bin/bash -c "$inner" "$L/$task.log" "${cmd[@]}"
launchctl bootstrap "$DOMAIN" "$plist" || die "launchctl bootstrap of $plist failed: nothing started"
echo "$task: started [$mtag] as launchd job $DOMAIN/$label, log $L/$task.log"

# The launch lock is held until the inner shell reports, in its run file, that it holds its slot
# (`slots-acquired`) or could not take it (`slot-refused`). Past the deadline the job is stopped by
# its label, and the stop is reported as verified only when the job is gone and its slot is free.
deadline=200   # tenths of a second: the slot's wait (5 s) and the start
if [ "$TEST" = 1 ] && [ -f "$HOME/test-deadline" ]; then deadline=$(($(cat "$HOME/test-deadline") * 10)); fi
for _ in $(seq 1 "$deadline"); do
  run_state=$(cat "$run_file" 2> /dev/null || true)
  if grep -q '^slots-acquired' <<< "$run_state"; then
    if grep -q '^ended' <<< "$run_state"; then
      reap "$task"
      echo "$task: took slot $FREE_SLOT, ran and has ended ($(grep '^ended' <<< "$run_state" | tail -1))"
    else
      echo "$task: holds slot $FREE_SLOT (at $(date -u +%T))"
    fi
    exit 0
  fi
  if grep -q '^slot-refused' <<< "$run_state"; then
    stop_job "$label" || true
    die "$task could not take its slot $FREE_SLOT and did not start"
  fi
  sleep 0.1
done
if stop_job "$label" "$FREE_SLOT"; then
  echo "exit=stopped $(date -u +%FT%TZ)" >> "$L/$task.log"
  die "$task did not report its slot within $((deadline / 10)) s: its job $label is stopped and booted out, and slot $FREE_SLOT is free (verified)"
fi
die "$task did not report its slot within $((deadline / 10)) s: its job $label was signalled and booted out, but the stop is NOT verified (launchctl print $DOMAIN/$label, scripts/mac/agent.sh slots): check it by hand"
