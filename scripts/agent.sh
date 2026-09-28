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
#   scripts/agent.sh thresholds          may an agent start now? (load and memory; exit 4 if not)
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
#   logs/<task>.unit       the systemd unit (or <task>.pid when detached with setsid)
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
MAX_LOAD5=12 MIN_MEM_GB=8 MAX_AGENTS=3
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
  # The concurrency budget of OPERATIONS §3: Grim World agents of the three tracks, whoever
  # launched them. A count that cannot be made refuses the launch (fails closed).
  local units ulist plist dirs detached agents
  if ! ulist=$(systemctl --user list-units --type=service --no-legend --plain \
      --state=active,activating,deactivating,reloading 'grimworld-*' 'hexmap-*' 'quiver-*' 2>&1); then
    echo "agent.sh: cannot list the systemd user units, so the agents cannot be counted: wait and check again" >&2
    return 1
  fi
  units=$(grep -c . <<< "$ulist" || true)
  # Detached agents (codex audits), one per working directory under the three repositories (a
  # codex audit runs several processes): the live pids recorded by the launchers, checked to be
  # the launch they record (their command line holds the task's log, so a reused pid is not
  # counted), and codex `exec` processes started another way. A pid whose directory cannot be read
  # counts as an agent. The unit prefixes are reserved to the launchers. Without a systemd user
  # manager the agents cannot be counted and no launch happens.
  local rc=0
  plist=$(pgrep -f '^/usr/bin/node .*codex[^ ]* exec( |$)') || rc=$?
  if [ "$rc" -gt 1 ]; then   # 1: no process matched
    echo "agent.sh: pgrep failed, so the agents cannot be counted: wait and check again" >&2
    return 1
  fi
  for f in "$HOME"/projects/{grimworld,hexx-cairo,quiver}/.claude/worktrees/logs/*.pid; do
    [ -f "$f" ] || continue
    local pid; pid=$(cat "$f" 2> /dev/null || true)
    if ! [[ $pid =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2> /dev/null; then continue; fi
    tr '\0' '\n' < "/proc/$pid/cmdline" 2> /dev/null | grep -qxF -- "${f%.pid}.log" || continue
    plist+=$'\n'"$pid"
  done
  dirs=$(while read -r p; do
      [ -n "$p" ] || continue
      readlink "/proc/$p/cwd" 2> /dev/null || echo "/projects/grimworld/unreadable-$p"
    done <<< "$plist" | grep -E '/projects/(grimworld|hexx-cairo|quiver)(/|$)' | sort -u || true)
  detached=$(grep -c . <<< "$dirs" || true)
  agents=$((units + detached))
  if [ "$agents" -ge "$MAX_AGENTS" ]; then
    echo "agent.sh: $agents Grim World agents running ($units units, $detached detached), the budget is $MAX_AGENTS: wait and check again" >&2
    return 1
  fi
  echo "agent.sh: load $load5, $((mem_kb / 1048576)) GB available, $agents of $MAX_AGENTS agents: a launch may proceed"
}

case "${1:-}" in
  thresholds)
    thresholds_ok || exit 4
    exit 0 ;;
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
ref=${GW_BRIEF_REF:-origin/main}   # CI checks a pull request's own briefs with GW_BRIEF_REF=HEAD
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

unit="grimworld-$task-$(date -u +%H%M%S)"
desc="[$label] $task $mode ($profile)"
# Unit environment: the machine-wide scarb/snforge shims (~/.local/bin) come first on PATH, so
# every Cairo build takes the shared heavy-build lock; long builds may run in the foreground.
path="$HOME/.local/bin:$HOME/.asdf/shims:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
run=(systemd-run --user --unit="$unit" --description="$desc" --collect --quiet
  --working-directory="$wt" -p OOMPolicy=continue -p Nice=10 -p OOMScoreAdjust=500
  -p MemoryMax=20G --setenv=HOME="$HOME" --setenv=PATH="$path"
  --setenv=BASH_DEFAULT_TIMEOUT_MS=1800000 --setenv=BASH_MAX_TIMEOUT_MS=3600000
  --setenv=GW_AGENT_SH="$root/scripts/agent.sh" --setenv=GW_TASK="$task")
# $0 of the inner shell is the log file, "$@" the agent command line. After the agent, it
# records the model that actually ran (`model=`), then the exit status. Single quotes on
# purpose: the inner shell of the unit expands them, not this one.
# shellcheck disable=SC2016
inner='"$@" < /dev/null >> "$0" 2>&1; s=$?
echo "model=$("$GW_AGENT_SH" model "$GW_TASK" 2> /dev/null)" >> "$0"
echo "exit=$s $(date -u +%FT%TZ)" >> "$0"'

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
thresholds_ok || exit 4
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
if [ "$cli" = claude ] && systemctl --user list-units > /dev/null 2>&1; then use_unit=1; fi

echo "$profile" > "$L/$task.profile"
echo "$cli $model_id" > "$L/$task.cli"
stat -c %s "$L/$task.log" 2> /dev/null > "$L/$task.start" || echo 0 > "$L/$task.start"
echo "--- $(date -u +%FT%TZ) $desc $cli $model_id $([ "$use_unit" = 1 ] && echo "unit=$unit" || echo setsid)" >> "$L/$task.log"
rm -f "$L/$task.unit" "$L/$task.pid"
if [ "$sepolia" = 1 ]; then date -u +%FT%TZ > "$L/$task.sepolia"; else rm -f "$L/$task.sepolia"; fi
if [ "$use_unit" = 1 ]; then
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
    GW_AGENT_SH="$root/scripts/agent.sh" GW_TASK="$task" nice -n 10 setsid nohup bash -c "$inner" "$L/$task.log" "${cmd[@]}" > /dev/null 2>&1 9>&- &
  echo "$!" > "$L/$task.pid"
  echo "$task: started [$label] detached with setsid, pid $!, log $L/$task.log"
fi
