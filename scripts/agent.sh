#!/usr/bin/env bash
# Grim World launcher: start or resume a sub-agent in its task worktree, as a transient systemd
# user unit, outside the process tree and the cgroup of the calling session (a restart of the
# desktop app must not kill it). Falls back to `setsid nohup` where there is no systemd user
# manager. Ported from the owner's glam-cairo launcher, with one deliberate difference: agents
# never run with --dangerously-skip-permissions. Each launch uses a committed profile
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
# options:
#   --dry-run            print what would be launched, launch nothing, need no worktree
#   --with-assets        initialise the `assets` submodule in the task worktree before launching
#   --branch <name>      create the worktree from origin/main on branch <name> if it is missing
# arguments:
#   model     claude: sonnet | opus | fable or their full ids; codex: gpt-6-astra | gpt-6-sol | gpt-6-luna
#   profile   research | implement | audit (default: research for claude new, audit for codex;
#             on resume, the profile the task was launched with)
#   sid       codex session id, for `codex … resume` (see `sid`); ignored by claude
#   effort    reasoning effort (codex default: high; claude: the model's default)
# files, under <main checkout>/.claude/worktrees/:
#   cli-<task>/            the task worktree
#   logs/<task>.log        the agent's output; each run ends with a line `exit=<status> <date>`
#   logs/<task>.unit       the systemd unit (or <task>.pid for the fallback)
#   logs/<task>.profile    the profile of the launch, reused by `resume`
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
    claude:sonnet | claude:claude-sonnet-5) echo "claude-sonnet-5|Sonnet 5" ;;
    claude:opus | claude:claude-opus-5-5) echo "claude-opus-5-5|Opus 5.5" ;;
    claude:fable | claude:claude-fable-5-1) echo "claude-fable-5-1|Fable 5.1" ;;
    codex:gpt-6-astra) echo "gpt-6-astra|GPT-6-Astra" ;;
    codex:gpt-6-sol) echo "gpt-6-sol|GPT-6-Sol" ;;
    codex:gpt-6-luna) echo "gpt-6-luna|GPT-6-Luna" ;;
    *) die "unknown model '$2' for $1 (claude: sonnet|opus|fable; codex: gpt-6-astra|gpt-6-sol|gpt-6-luna)" ;;
  esac
}

# Profile file: one permission rule per line; `!rule` is a deny rule; `@name` includes the
# profile `name`; `#` starts a comment.
read_profile() { # <profile> <depth>: appends to the arrays allow and deny
  local f=$P/$1.txt line
  [ -f "$f" ] || die "no profile $f (research | implement | audit)"
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

case "${1:-}" in
  status)
    mkdir -p "$L"
    shopt -s nullglob
    for f in "$L"/*.log; do
      t=$(basename "$f" .log)
      printf '%-24s %-8s %-11s last write %s  %s\n' "$t" \
        "$(running "$t" && echo running || echo stopped)" \
        "$(cat "$L/$t.profile" 2> /dev/null || echo -)" \
        "$(date -u -r "$f" +%FT%TZ)" \
        "$(grep -E '^(--- |exit=)' "$f" | tail -1)"
    done
    exit 0 ;;
  wait)
    [ -n "${2:-}" ] || die "usage: agent.sh wait <task>"
    while running "$2"; do sleep 20; done
    grep -E '^exit=' "$L/$2.log" 2> /dev/null | tail -1 || true
    exit 0 ;;
  sid)
    [ -n "${2:-}" ] || die "usage: agent.sh sid <task>"
    wt=$W/cli-$2
    grep -l -F "\"cwd\":\"$wt\"" "$HOME"/.codex/sessions/*/*/*/rollout-*.jsonl 2> /dev/null |
      xargs -r ls -t | head -1 | sed -E 's/.*rollout-.{19}-(.*)\.jsonl$/\1/'
    exit 0 ;;
esac

dry=0 assets=0 branch=""
while [ "${1:-}" != "${1#--}" ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --with-assets) assets=1 ;;
    --branch) branch=${2:-}; [ -n "$branch" ] || die "--branch needs a name"; shift ;;
    *) die "unknown option $1" ;;
  esac
  shift
done
[ $# -ge 5 ] || die "usage: agent.sh [--dry-run] [--with-assets] [--branch <b>] <task> <claude|codex> <model> <new|resume> \"<prompt>\" [profile] [sid] [effort]"
task=$1 cli=$2 model=$3 mode=$4 prompt=$5 profile=${6:-} sid=${7:-} effort=${8:-}
case "$task" in *[!A-Za-z0-9._-]* | "") die "task name '$task': letters, digits, . _ - only" ;; esac
case "$mode" in new | resume) ;; *) die "mode must be new or resume" ;; esac
t=$(tag "$cli" "$model")
model_id=${t%%|*} label=${t#*|}
wt=$W/cli-$task

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

case "$cli:$mode" in
  claude:new)
    cmd=(claude -p "$prompt" --model "$model_id" --name "[$label] $task") ;;
  claude:resume)
    cmd=(claude --continue -p "$prompt" --model "$model_id") ;;
  codex:new)
    cmd=(codex exec -C "$wt" -m "$model_id" -c "model_reasoning_effort=${effort:-high}" -s read-only
      -o "$L/$task.last.md" "$prompt") ;;
  codex:resume)
    [ -n "$sid" ] || die "codex resume needs the session id (scripts/agent.sh sid $task)"
    cmd=(codex exec resume "$sid" -m "$model_id" -c "model_reasoning_effort=${effort:-high}"
      -c 'sandbox_mode="read-only"' -o "$L/$task.last.md" "$prompt") ;;
  *) die "cli must be claude or codex" ;;
esac
if [ "$cli" = claude ]; then
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
  --setenv=BASH_DEFAULT_TIMEOUT_MS=1800000 --setenv=BASH_MAX_TIMEOUT_MS=3600000)
# $0 of the inner shell is the log file, "$@" the agent command line.
inner='"$@" < /dev/null >> "$0" 2>&1; echo "exit=$? $(date -u +%FT%TZ)" >> "$0"'

if [ "$dry" = 1 ]; then
  echo "# $desc"
  echo "# worktree $wt  log $L/$task.log  unit $unit  with-assets=$assets"
  printf '%q ' "${cmd[@]}"
  echo
  exit 0
fi

if [ ! -d "$wt" ]; then
  [ -n "$branch" ] || die "no worktree $wt (create it, or pass --branch <type>/<task-id>-<slug>)"
  git -C "$main" fetch -q origin main
  git -C "$main" worktree add -q "$wt" -b "$branch" origin/main
fi
command -v "$cli" > /dev/null || die "$cli is not on PATH"
mkdir -p "$L"
if running "$task"; then die "$task: already running"; fi
if [ "$assets" = 1 ]; then
  git -C "$wt" submodule update --init assets
fi

echo "$profile" > "$L/$task.profile"
echo "--- $(date -u +%FT%TZ) $desc $cli $model_id unit=$unit" >> "$L/$task.log"
rm -f "$L/$task.unit" "$L/$task.pid"
if systemctl --user list-units > /dev/null 2>&1; then
  "${run[@]}" bash -c "$inner" "$L/$task.log" "${cmd[@]}"
  echo "$unit" > "$L/$task.unit"
  echo "$task: started [$label] as systemd user unit $unit, log $L/$task.log"
else
  cd "$wt"
  PATH=$path setsid nohup bash -c "$inner" "$L/$task.log" "${cmd[@]}" > /dev/null 2>&1 &
  echo "$!" > "$L/$task.pid"
  echo "$task: started [$label] detached (no systemd user manager), pid $!, log $L/$task.log"
fi
