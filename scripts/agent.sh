#!/usr/bin/env bash
# Grim World launcher: start or resume a sub-agent in its task worktree. claude agents run as
# transient systemd user units, outside the process tree and the cgroup of the calling session
# (a restart of the desktop app must not kill them); codex auditors are always detached with setsid (see the note at
# the launch below). Ported from the owner's glam-cairo launcher, with one deliberate
# difference: agents never run with --dangerously-skip-permissions. Each launch uses a committed profile
# (scripts/profiles/<profile>.txt) that becomes
# `--permission-mode acceptEdits --allowedTools … --disallowedTools …`; codex always runs in its
# read-only sandbox (codex audits, it never implements). See OPERATIONS.md §4 and
# docs/briefs/COMMON.md.
#
# usage:
#   scripts/agent.sh [options] <task> <claude|codex> <model> <new|resume> "<prompt>" [profile] [sid] [effort]
#   scripts/agent.sh status              one line per known task
#   scripts/agent.sh wait <task>         block until the agent of <task> has exited
#   scripts/agent.sh sid <task>          codex session id of <task> (for `resume`)
#   scripts/agent.sh model <task>        the model that actually ran, as the CLI recorded it
#   scripts/agent.sh thresholds          may an agent start now? (load, memory, a free total slot and
#                                        a free slot of this track, the waiting marker; exit 4 if not)
#   scripts/agent.sh slots               who holds each slot (~/orchestrator/slots)
#   scripts/agent.sh slots-init          create missing slot files (never replaces one); directory read-only
#   scripts/agent.sh run-in-slots …      the inner shell of a launch, for the tests
# options:
#   --dry-run            print what would be launched, launch nothing, need no worktree
#   --with-assets        initialise the `assets` submodule in the task worktree before launching
#   --with-sepolia       leave the Sepolia account variables to the agent (claude only; the brief
#                        must grant it). Without it they are emptied, like the registry token
#   --branch <name>      create the worktree from origin/main on branch <name> if it is missing
# arguments:
#   model     claude: sonnet (Sonnet 5.5) | opus | fable or their full ids (claude-sonnet-5 only to
#             resume an agent started on it); codex: gpt-6-astra | gpt-6-sol | gpt-6-luna
#   profile   research | implement | audit (default: research for claude new, audit for codex;
#             on resume, the profile the task was launched with)
#   sid       codex session id, for `codex … resume` (see `sid`); ignored by claude
#   effort    reasoning effort (codex default: high; claude: the model's default)
# files, under <main checkout>/.claude/worktrees/:
#   cli-<task>/            the task worktree
#   logs/<task>.log        the agent's output; each run ends with a line `exit=<status> <date>`
#   logs/<task>.unit       the systemd unit (or <task>.pid when detached with setsid), for status and
#                          wait only: the budget is counted by the slots' locks, never from these
#   logs/<task>.profile    the profile of the launch, reused by `resume`
#   logs/<task>.cli        the CLI and the model id asked for, checked against the one that ran
#   logs/<task>.sepolia    present while the last launch had --with-sepolia (the brief grants it)
#   logs/<task>.last.md    codex only: its last message, i.e. the audit report
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
main=$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")
W=$main/.claude/worktrees
L=$W/logs
P=$root/scripts/profiles
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

die() { echo "agent.sh: $*" >&2; exit 2; }

running() { # <task>
  if [ -f "$L/$1.unit" ]; then
    systemctl --user is-active -q "$(cat "$L/$1.unit")" 2> /dev/null
  elif [ -f "$L/$1.pid" ]; then
    kill -0 "$(cat "$L/$1.pid")" 2> /dev/null
  else
    return 1
  fi
}

# The title tag of every unit, log line and session: the model's display name, never guessed.
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

# Profile file: one permission rule per line; `!rule` is a deny rule; `@name` includes the
# profile `name`; `#` starts a comment.
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

# The model that actually ran, as the CLI itself recorded it (never the one that was asked for):
# claude writes it on every assistant message of its session transcript, codex prints `model:`
# at the start of each run.
reported_model() { # <task>
  local cli expected wt dir f
  read -r cli expected < "$L/$1.cli" 2> /dev/null || { echo unknown; return; }
  if [ "$cli" = codex ]; then
    # The first `model:` line of the current run, read from the offset where the launcher
    # started it (<task>.start): codex prints its header before any agent output, and agent
    # output can contain anything, launcher headers included.
    f=$(tail -c +$(($(cat "$L/$1.start" 2> /dev/null || echo 0) + 1)) "$L/$1.log" 2> /dev/null |
      grep -m1 -E '^model: ' || true)   # grep -m1 closes the pipe early: tail's SIGPIPE is fine
    f=${f#model: }
    echo "${f:-unknown}"
    return
  fi
  wt=$W/cli-$1
  dir=$HOME/.claude/projects/$(printf '%s' "$wt" | sed 's#[/.]#-#g')
  f=$(find "$dir" -maxdepth 1 -name '*.jsonl' -printf '%T@ %p\n' 2> /dev/null | sort -n |
    tail -1 | cut -d' ' -f2-)
  [ -n "$f" ] || { echo unknown; return; }
  grep -ho '"model":"[^"]*"' "$f" | cut -d'"' -f4 | grep -v '^<synthetic>$' | sort -u |
    paste -sd, - | grep . || echo unknown
}

# Machine thresholds (OPERATIONS §3): no agent starts or resumes while the 5-minute load
# average is above 12 or less than 8 GB of memory is available. Fixed here on purpose: no
# variable can relax them. Running agents are never stopped for load.
MAX_LOAD5=12 MIN_MEM_GB=8
# The budget (D-118, OPERATIONS §3) is a set of slots, and a slot is a file an agent holds by a
# kernel lock for as long as it lives: ~/orchestrator/slots/total-1..3 for the budget of 3, and per
# track game-1, game-2 (the game's cap of 2), lib-1, quiver-1. A launch takes one free total slot
# and one free slot of its track, or refuses; the agent's inner shell takes the two locks itself
# (`flock -w 5`, then `slots-acquired` in its log) on descriptors its children inherit, so the kernel frees them when that shell and the
# CLI it waits for have ended (and any process keeping the descriptors), however they end. Nothing is
# counted by reading processes. The slot names are protected by a read-only directory against
# anything but a deliberate chmod by the same Unix user (OPERATIONS §3, accepted residual). TRACK is this launcher's own track:
# the copies of the map library and quiver set theirs (hexmap, quiver) and match this file
# otherwise. While the game waits (the marker ~/orchestrator/waiting/game, less than 30 minutes
# old), the other tracks launch nothing new.
TRACK=grimworld
SLOTS=$HOME/orchestrator/slots
TOTAL_SLOTS=(total-1 total-2 total-3)
case $TRACK in
  grimworld) TRACK_SLOTS=(game-1 game-2) ;;
  hexmap) TRACK_SLOTS=(lib-1) ;;
  quiver) TRACK_SLOTS=(quiver-1) ;;
  *) TRACK_SLOTS=() ;;
esac
ALL_SLOTS=(total-1 total-2 total-3 game-1 game-2 lib-1 quiver-1)
# The slot files are never created by a probe or an agent: they are opened read-only (a missing one
# is an error, not a new slot), and their directory is read-only (mode 555) so that no slot can be
# removed, renamed or replaced by a new inode while it is held (flock protects an inode, not a name).
# `slots-init` creates missing ones, and only those. The state of a slot: free (a non-blocking lock can
# be taken, and is released at once), held, or an error (missing, unreadable, no flock), which refuses.
slot_state() { # <slot> -> free | held | missing | unreadable
  local f=$SLOTS/$1 fd
  if [ ! -f "$f" ]; then echo missing; return; fi
  if ! exec {fd}< "$f"; then echo unreadable; return; fi
  local rc=0
  flock -n "$fd" || rc=$?
  exec {fd}<&-
  case $rc in 0) echo free ;; 1) echo held ;; *) echo "unlockable (flock exit $rc)" ;; esac
}
slot_free() { [ "$(slot_state "$1" 2> /dev/null)" = free ]; }
# The first free slot of a list. Every slot of the list is inspected first: one in error (missing,
# unreadable, not lockable) refuses, even if another is free (fails closed).
first_free() {
  local x st first=""
  for x in "$@"; do
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
  command -v flock > /dev/null || { echo "agent.sh: flock is missing, so the slots cannot be read: wait and check again" >&2; return 1; }
  if [ ! -d "$SLOTS" ]; then echo "agent.sh: no slot directory $SLOTS: run scripts/agent.sh slots-init once" >&2; return 1; fi
  if [ -w "$SLOTS" ]; then chmod 555 "$SLOTS" 2> /dev/null || { echo "agent.sh: $SLOTS cannot be made read-only: check it" >&2; return 1; }; fi
  local x
  for x in "${ALL_SLOTS[@]}"; do
    [ -f "$SLOTS/$x" ] || { echo "agent.sh: the slot file $SLOTS/$x is missing: run scripts/agent.sh slots-init" >&2; return 1; }
  done
}
init_slots() { # creates the missing slot files only (never replaces one), then makes the directory read-only
  # The directory is writable only in here, under the launch lock and with no slot held, so no held
  # slot can be removed or replaced while it is open (audit of PR 60, A1).
  mkdir -p "$HOME/orchestrator" || return 1
  exec 9>> "$HOME/orchestrator/agent-launch.lock"
  flock -w 600 9 || { echo "agent.sh: the launch lock is held: try again" >&2; return 1; }
  if [ -d "$SLOTS" ]; then
    local y st
    for y in "${ALL_SLOTS[@]}"; do
      [ -e "$SLOTS/$y" ] || continue
      st=$(slot_state "$y" 2> /dev/null)
      [ "$st" = free ] || { echo "agent.sh: slot $y is $st: slots-init runs only while every slot is free" >&2; return 1; }
    done
  fi
  mkdir -p "$SLOTS" && chmod 755 "$SLOTS" || return 1
  local x
  for x in "${ALL_SLOTS[@]}"; do [ -e "$SLOTS/$x" ] || : > "$SLOTS/$x" || { chmod 555 "$SLOTS"; return 1; }; done
  chmod 555 "$SLOTS"
}
# $0 of the inner shell is the log file, "$@" the agent command line. The inner shell first takes
# its two slots (GW_SLOT_TOTAL, GW_SLOT_TRACK) with `flock -w 5`, waiting at most 5 s for each (a
# probe of the slots takes a lock for an instant: without the wait, a probe at the wrong moment made
# the agent refuse), then writes `slots-acquired` to its log, which the launcher waits for,
# on file descriptors 7 and 8 opened
# read-only (a missing slot file is never created): the slots are held while the inner shell lives,
# that is while the agent's CLI runs, and by any process of the agent that keeps those descriptors.
# A process the CLI leaves behind after it exits and that closed them is not counted (COMMON forbids
# leaving processes). If either slot is taken it writes `slot-refused` and stops. After the agent, it records the model that actually ran
# (`model=`), then the exit status. Single quotes on purpose: the inner shell expands them.
# shellcheck disable=SC2016
inner='exec 7< "$GW_SLOT_TOTAL" 8< "$GW_SLOT_TRACK" || exit 75
if ! flock -w 5 7 || ! flock -w 5 8; then echo "slot-refused $(date -u +%FT%TZ)" >> "$0"; exit 75; fi
echo "slots-acquired $(date -u +%FT%TZ)" >> "$0"
printf "%s\n" "$GW_SLOT_NAME" > "$GW_SLOT_TOTAL"; printf "%s\n" "$GW_SLOT_NAME" > "$GW_SLOT_TRACK"
"$@" < /dev/null >> "$0" 2>&1; s=$?
echo "model=$("$GW_AGENT_SH" model "$GW_TASK" 2> /dev/null)" >> "$0"
echo "exit=$s $(date -u +%FT%TZ)" >> "$0"'
thresholds_ok() { # prints the reason and returns 1 when a launch must wait
  local load5 mem_kb
  load5=$(cut -d' ' -f2 /proc/loadavg)
  mem_kb=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
  if ! [[ $load5 =~ ^[0-9]+(\.[0-9]+)?$ && $mem_kb =~ ^[0-9]+$ ]]; then
    echo "agent.sh: cannot read load ('$load5') or memory ('$mem_kb'): wait and check again" >&2
    return 1
  fi
  if awk -v l="$load5" -v m="$MAX_LOAD5" 'BEGIN { exit !(l > m) }'; then
    echo "agent.sh: 5-minute load average $load5 is above $MAX_LOAD5: wait and check again" >&2
    return 1
  fi
  if [ "$((mem_kb / 1048576))" -lt "$MIN_MEM_GB" ]; then
    echo "agent.sh: $((mem_kb / 1048576)) GB of memory available, under $MIN_MEM_GB: wait and check again" >&2
    return 1
  fi
  if [ "$TRACK" != grimworld ] && [ -n "$(find "$HOME/orchestrator/waiting/game" -mmin -30 2> /dev/null)" ]; then
    echo "agent.sh: the game is waiting for a slot (~/orchestrator/waiting/game): wait and check again" >&2
    return 1
  fi
  slots_ready || return 1
  local rc=0
  FREE_TOTAL=$(first_free "${TOTAL_SLOTS[@]}") || rc=$?
  if [ "$rc" = 2 ]; then echo "agent.sh: $FREE_TOTAL: the slots cannot be read, check them" >&2; return 1; fi
  if [ "$rc" != 0 ]; then
    echo "agent.sh: the budget of 3 agents is in use (${TOTAL_SLOTS[*]} held): wait and check again" >&2
    return 1
  fi
  [ "${#TRACK_SLOTS[@]}" -gt 0 ] || { echo "agent.sh: the track $TRACK has no slot: check TRACK" >&2; return 1; }
  rc=0
  FREE_TRACK=$(first_free "${TRACK_SLOTS[@]}") || rc=$?
  if [ "$rc" = 2 ]; then echo "agent.sh: $FREE_TRACK: the slots cannot be read, check them" >&2; return 1; fi
  if [ "$rc" != 0 ]; then
    echo "agent.sh: the $TRACK track is at its cap (${TRACK_SLOTS[*]} held): wait and check again" >&2
    return 1
  fi
  echo "agent.sh: load $load5, $((mem_kb / 1048576)) GB available, slots $FREE_TOTAL and $FREE_TRACK free: a launch may proceed"
}

case "${1:-}" in
  thresholds)
    thresholds_ok || exit 4
    exit 0 ;;
  slots)   # who holds each slot: the lock decides; the name written inside is for display only
    for x in "${ALL_SLOTS[@]}"; do
      st=$(slot_state "$x" 2> /dev/null)
      case $st in
        held) printf '%-9s held  %s\n' "$x" "$(head -1 "$SLOTS/$x" 2> /dev/null)" ;;
        *) printf '%-9s %s\n' "$x" "$st" ;;
      esac
    done
    exit 0 ;;
  slots-init)   # create the missing slot files (never replace one), and make their directory read-only
    init_slots || die "cannot create the slots in $SLOTS"
    exit 0 ;;
  run-in-slots)   # run-in-slots <total slot> <track slot> <log> <command…>: the inner shell of a launch (tests)
    [ $# -ge 5 ] || die "usage: agent.sh run-in-slots <total slot> <track slot> <log> <command…>"
    slots_ready || exit 4
    GW_SLOT_TOTAL=$SLOTS/$2 GW_SLOT_TRACK=$SLOTS/$3 GW_SLOT_NAME="run-in-slots $$" GW_AGENT_SH=$0 GW_TASK=none \
      exec bash -c "$inner" "$4" "${@:5}" ;;
  status)
    mkdir -p "$L"
    shopt -s nullglob
    for f in "$L"/*.log; do
      t=$(basename "$f" .log)
      expected=$(cut -d' ' -f2 "$L/$t.cli" 2> /dev/null || echo -)
      ran=$(reported_model "$t")
      [ "$ran" = "$expected" ] || [ "$ran" = unknown ] || ran="$ran MISMATCH(expected $expected)"
      # While running: the launcher's header of this run (at its recorded offset). Stopped: the
      # last line of the log, which the unit writes after the agent's output (`exit=…`).
      if running "$t"; then state=running
        # head closes the pipe early: tail's SIGPIPE is expected.
        last=$(tail -c +$(($(cat "$L/$t.start" 2> /dev/null || echo 0) + 1)) "$f" 2> /dev/null |
          head -1 || true)
      else state=stopped last=$(tail -1 "$f"); fi
      printf '%-24s %-8s %-10s ran=%-18s last write %s  %s\n' "$t" "$state" \
        "$(cat "$L/$t.profile" 2> /dev/null || echo -)" "$ran" \
        "$(date -u -r "$f" +%FT%TZ)" "$last"
    done
    # The slots: held or free by their locks; the name inside is for display only.
    for x in "${ALL_SLOTS[@]}"; do
      st=$(slot_state "$x" 2> /dev/null)
      if [ "$st" = held ]; then echo "slot $x held $(head -1 "$SLOTS/$x" 2> /dev/null)"; else echo "slot $x $st"; fi
    done
    exit 0 ;;
  model)
    [ -n "${2:-}" ] || die "usage: agent.sh model <task>"
    reported_model "$2"
    exit 0 ;;
  wait)
    [ -n "${2:-}" ] || die "usage: agent.sh wait <task>"
    while running "$2"; do sleep 20; done
    grep -E '^exit=[0-9]+ [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$L/$2.log" 2> /dev/null | tail -1 || true
    echo "model=$(reported_model "$2")"
    exit 0 ;;
  sid)
    [ -n "${2:-}" ] || die "usage: agent.sh sid <task>"
    wt=$W/cli-$2
    grep -l -F "\"cwd\":\"$wt\"" "$HOME"/.codex/sessions/*/*/*/rollout-*.jsonl 2> /dev/null |
      sort | tail -1 | sed -E 's/.*rollout-.{19}-(.*)\.jsonl$/\1/'   # names start with the date
    exit 0 ;;
esac

dry=0 assets=0 sepolia=0 branch=""
while [ "${1:-}" != "${1#--}" ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --with-assets) assets=1 ;;
    --with-sepolia) sepolia=1 ;;
    --branch) branch=${2:-}; [ -n "$branch" ] || die "--branch needs a name"; shift ;;
    *) die "unknown option $1" ;;
  esac
  shift
done
[ $# -ge 5 ] || die "usage: agent.sh [--dry-run] [--with-assets] [--with-sepolia] [--branch <b>] <task> <claude|codex> <model> <new|resume> \"<prompt>\" [profile] [sid] [effort]"
task=$1 cli=$2 model=$3 mode=$4 prompt=$5 profile=${6:-} sid=${7:-} effort=${8:-}
case "$task" in *[!A-Za-z0-9._-]* | "") die "task name '$task': letters, digits, . _ - only" ;; esac
case "$mode" in new | resume) ;; *) die "mode must be new or resume" ;; esac
t=$(tag "$cli" "$model")
model_id=${t%%|*} label=${t#*|}
wt=$W/cli-$task
# A resumed agent keeps the model it started on until its task closes (OPERATIONS §2): a resume
# needs the launch record and the same model. A new launch uses a current model and a fresh
# task: while the task's worktree exists (the task is not closed), its record is kept.
if [ "$mode" = resume ]; then
  [ -f "$L/$task.cli" ] || die "$task has no launch record ($L/$task.cli): nothing to resume"
  recorded=$(cut -d' ' -f2 "$L/$task.cli")
  [ "$recorded" = "$model_id" ] || die "$task started on $recorded: resume it with that model, not $model_id"
else
  [ "$model_id" != claude-sonnet-5 ] || die "claude-sonnet-5 only resumes agents started on it; new launches use sonnet (Sonnet 5.5)"
  if [ -f "$L/$task.cli" ] && [ -d "$wt" ]; then
    die "$task is not closed (its worktree exists): resume it, or close it before a new launch"
  fi
fi

if [ -z "$profile" ]; then
  if [ "$mode" = resume ] && [ -f "$L/$task.profile" ]; then profile=$(cat "$L/$task.profile")
  elif [ "$cli" = codex ]; then profile=audit
  else profile=research; fi
fi
[ "$cli" = claude ] || [ "$profile" = audit ] || die "codex audits only: profile must be audit"
load_profile "$profile"

# Every launch prompt carries the foreground rule (OPERATIONS §3), whatever the brief says.
if [ "$cli" = claude ]; then end="Your turn ends when REPORT.md is written."
else end="You cannot write files: your final message is your report."; fi
prompt="$prompt

Foreground only: never run a command in the background and never end your turn waiting for one; in headless mode that ends the session. $end"

# codex's entry point is a Node script: start it with the system `node` explicitly, so that an
# asdf `node` shim without a version (docs/reports/INC-2026-09-28-asdf-node-shims.md) cannot
# stop it, while the commands it runs keep the normal PATH and a worktree's pinned tools.
codex=(/usr/bin/node "$(readlink -f "$(command -v codex 2> /dev/null || echo /usr/bin/codex)")")
case "$cli:$mode" in
  claude:new)
    cmd=(claude -p "$prompt" --model "$model_id" --name "[$label] $task") ;;
  claude:resume)
    cmd=(claude --continue -p "$prompt" --model "$model_id") ;;
  codex:new)
    cmd=("${codex[@]}" exec -C "$wt" -m "$model_id" -c "model_reasoning_effort=${effort:-high}" -s read-only
      -o "$L/$task.last.md" "$prompt") ;;
  codex:resume)
    [ -n "$sid" ] || die "codex resume needs the session id (scripts/agent.sh sid $task)"
    cmd=("${codex[@]}" exec resume "$sid" -m "$model_id" -c "model_reasoning_effort=${effort:-high}"
      -c 'sandbox_mode="read-only"' -o "$L/$task.last.md" "$prompt") ;;
  *) die "cli must be claude or codex" ;;
esac
[ "$sepolia" = 0 ] || [ "$cli" = claude ] || die "--with-sepolia is for claude agents only"
# The Sepolia account goes only to a task whose brief, as committed on origin/main, grants it
# (OPERATIONS §7): exactly one brief docs/briefs/<task>-*.md, holding the grant line below and the
# profile of the launch. The grant is recorded; a resume without the option says it runs without
# the account.
# shellcheck disable=SC2016 # the backquotes are literal text of the brief
GRANT='> Sepolia account: granted (launch with `--with-sepolia`).'
ref=origin/main   # a real launch reads the grant from origin/main, whatever the environment says
if [ "$dry" = 1 ]; then ref=${GW_BRIEF_REF:-origin/main}; fi   # CI's dry runs: GW_BRIEF_REF=HEAD
if [ "$sepolia" = 1 ]; then
  briefs=()
  while read -r b; do
    [[ $b == "docs/briefs/$task-"*.md ]] && briefs+=("$b")
  done < <(git -C "$main" ls-tree --name-only "$ref" docs/briefs/ 2> /dev/null)
  [ "${#briefs[@]}" = 1 ] || die "--with-sepolia: no single brief docs/briefs/$task-*.md on $ref"
  body=$(git -C "$main" show "$ref:${briefs[0]}") || die "--with-sepolia: cannot read ${briefs[0]} on $ref"
  grep -qxF -- "$GRANT" <<< "$body" || die "--with-sepolia: ${briefs[0]} on $ref does not grant the Sepolia account"
  grep -qE -- "Profile: $profile( |$)" <<< "$body" || die "--with-sepolia: ${briefs[0]} does not name the profile $profile"
elif [ "$mode" = resume ] && [ -f "$L/$task.sepolia" ]; then
  echo "agent.sh: note: $task was launched with --with-sepolia; this resume runs without the Sepolia account" >&2
fi
if [ "$cli" = claude ]; then
  # Secrets out of agents: the machine's user-level Claude settings define the Scarb registry
  # token for every claude process; --settings takes precedence over them, so every agent runs
  # with it empty, and the profiles deny typed publishing (an interpreter an agent runs could
  # still read the settings file: OPERATIONS §4). Codex runs in a whitelisted environment.
  # The same settings hold the Sepolia account (OPERATIONS §7): emptied too, unless the task's
  # brief grants it and it is launched with --with-sepolia.
  if [ "$sepolia" = 1 ]; then
    cmd+=(--settings '{"env":{"SCARB_REGISTRY_AUTH_TOKEN":""}}')
  else
    cmd+=(--settings '{"env":{"SCARB_REGISTRY_AUTH_TOKEN":"","STARKNET_NETWORK":"","STARKNET_RPC_URL":"","STARKNET_RPC":"","STARKNET_ACCOUNT_ADDRESS":"","STARKNET_PRIVATE_KEY":""}}')
  fi
  cmd+=(--permission-mode acceptEdits --allowedTools "${allow[@]}")
  [ "${#deny[@]}" -eq 0 ] || cmd+=(--disallowedTools "${deny[@]}")
  cmd+=(--max-turns 400 --output-format text)
  [ -z "$effort" ] || cmd+=(--effort "$effort")
fi

unit="$TRACK-$task-$(date -u +%H%M%S)"
desc="[$label] $task $mode ($profile)"
# Unit environment: the machine-wide scarb/snforge shims (~/.local/bin) come first on PATH, so
# every Cairo build takes the shared heavy-build lock; long builds may run in the foreground.
path="$HOME/.local/bin:$HOME/.asdf/shims:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
run=(systemd-run --user --unit="$unit" --description="$desc" --collect --quiet
  --working-directory="$wt" -p OOMPolicy=continue -p Nice=10 -p OOMScoreAdjust=500
  -p MemoryMax=20G --setenv=HOME="$HOME" --setenv=PATH="$path"
  --setenv=BASH_DEFAULT_TIMEOUT_MS=1800000 --setenv=BASH_MAX_TIMEOUT_MS=3600000
  --setenv=GW_AGENT_SH="$root/scripts/agent.sh" --setenv=GW_TASK="$task")

if [ "$dry" = 1 ]; then
  echo "# $desc"
  echo "# worktree $wt  log $L/$task.log  $([ "$cli" = claude ] && echo "unit $unit" || echo "setsid")  with-assets=$assets with-sepolia=$sepolia"
  printf '%q ' "${cmd[@]}"
  echo
  exit 0
fi

# One launch at a time across the orchestrators (OPERATIONS §3): the count and the start happen
# under a shared lock, so two launchers cannot both take the last slot. The agent does not inherit
# the lock (9>&- below).
mkdir -p "$HOME/orchestrator"
exec 9>> "$HOME/orchestrator/agent-launch.lock"
flock -w 600 9 || die "the launch lock $HOME/orchestrator/agent-launch.lock is held: try again"
thresholds_ok || exit 4   # sets FREE_TOTAL and FREE_TRACK
slot_total=$SLOTS/$FREE_TOTAL slot_track=$SLOTS/$FREE_TRACK
if [ ! -d "$wt" ]; then
  [ -n "$branch" ] || die "no worktree $wt (create it, or pass --branch <type>/<task-id>-<slug>)"
  git -C "$main" fetch -q origin main
  git -C "$main" worktree add -q --no-track "$wt" -b "$branch" origin/main
fi
command -v "$cli" > /dev/null || die "$cli is not on PATH"
mkdir -p "$L"
if running "$task"; then die "$task: already running"; fi
if [ "$assets" = 1 ]; then
  git -C "$wt" submodule update --init assets
fi

# codex never runs as a unit: its read-only sandbox (bubblewrap) needs an unprivileged user
# namespace, which this kernel refuses to systemd user units (apparmor_restrict_unprivileged_userns)
# and allows to the desktop app's own processes. codex is therefore detached with setsid from the
# calling session and keeps its sandbox; a restart of the desktop app kills it, and it is then
# resumed (`codex exec resume`). An agent without sandbox is never the answer.
use_unit=0
if [ "$cli" = claude ]; then
  systemctl --user list-units > /dev/null 2>&1 || die "no systemd user manager: a claude agent is never detached (OPERATIONS §3)"
  use_unit=1
fi

echo "$profile" > "$L/$task.profile"
echo "$cli $model_id" > "$L/$task.cli"
stat -c %s "$L/$task.log" 2> /dev/null > "$L/$task.start" || echo 0 > "$L/$task.start"
echo "--- $(date -u +%FT%TZ) $desc $cli $model_id $([ "$use_unit" = 1 ] && echo "unit=$unit" || echo setsid)" >> "$L/$task.log"
rm -f "$L/$task.unit" "$L/$task.pid"
if [ "$sepolia" = 1 ]; then date -u +%FT%TZ > "$L/$task.sepolia"; else rm -f "$L/$task.sepolia"; fi
slot_name="$task ($([ "$use_unit" = 1 ] && echo "unit $unit" || echo setsid), $(date -u +%FT%TZ))"
if [ "$use_unit" = 1 ]; then
  run+=(--setenv=GW_SLOT_TOTAL="$slot_total" --setenv=GW_SLOT_TRACK="$slot_track" --setenv=GW_SLOT_NAME="$slot_name")
  "${run[@]}" bash -c "$inner" "$L/$task.log" "${cmd[@]}" 9>&-
  echo "$unit" > "$L/$task.unit"
  echo "$task: started [$label] as systemd user unit $unit, log $L/$task.log"
else
  cd "$wt"
  # A clean environment, as a systemd unit would get: the calling session's variables hold
  # tokens (registry, messaging) that an agent must not inherit.
  env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-$(id -un)}" SHELL=/bin/bash \
    LANG="${LANG:-C.UTF-8}" PATH="$path" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    BASH_DEFAULT_TIMEOUT_MS=1800000 BASH_MAX_TIMEOUT_MS=3600000 \
    GW_SLOT_TOTAL="$slot_total" GW_SLOT_TRACK="$slot_track" GW_SLOT_NAME="$slot_name" \
    GW_AGENT_SH="$root/scripts/agent.sh" GW_TASK="$task" nice -n 10 setsid nohup bash -c "$inner" "$L/$task.log" "${cmd[@]}" > /dev/null 2>&1 9>&- &
  echo "$!" > "$L/$task.pid"
  echo "$task: started [$label] detached with setsid, pid $!, log $L/$task.log"
fi
# The launch lock is held until this launch's inner shell reports, in its own log (from this run's
# offset), that it holds both slots (`slots-acquired`) or could not take them (`slot-refused`). The
# deadline covers both waits (2 × 5 s) and the start; past it the agent is stopped and the launch
# reported as failed, so a launch never reports what it did not do (audit of PR 74, A1, A2).
start=$(cat "$L/$task.start")
for _ in $(seq 1 200); do
  run_log=$(tail -c +$((start + 1)) "$L/$task.log" 2> /dev/null || true)
  if grep -q '^slots-acquired' <<< "$run_log"; then
    echo "$task: holds slots $FREE_TOTAL and $FREE_TRACK"; exit 0
  fi
  if grep -q '^slot-refused' <<< "$run_log"; then
    die "$task could not take its slots ($FREE_TOTAL, $FREE_TRACK) and did not start"
  fi
  sleep 0.1
done
if [ "$use_unit" = 1 ]; then systemctl --user stop "$unit" 2> /dev/null || true
else kill -TERM -- -"$(cat "$L/$task.pid")" 2> /dev/null || true; fi
die "$task did not report its slots within 20 s: stopped; check $L/$task.log and the slots (agent.sh status)"
