#!/usr/bin/env bash
# Build lock of Grim World. The VPS (8 vCPU, 31 GB) is shared with the owner's other programmes:
# two concurrent Cairo test builds can be OOM-killed, and a sustained 100 % CPU makes the
# hypervisor throttle the machine. Two locks, always taken in this order:
#   * the PROJECT lock ($GRIMWORLD_BUILD_LOCK, default /tmp/grimworld-build.lock): at most one
#     heavy Grim World command at a time, whichever agent runs it;
#   * the machine-wide HEAVY lock ($HEAVY_BUILD_LOCK, default ~/orchestrator/heavy-build.lock),
#     shared with every other programme. `scarb` and `snforge` on PATH are the machine's shims
#     (~/.local/bin), which take it by themselves only when the subcommand is their first argument
#     (`scarb build`, not `scarb --manifest-path X build`); this script takes it for `--heavy` and, FND-15,
#     for every scarb or snforge build, test, check, lint or execute, wherever the subcommand sits.
#     `scarb fmt` and `scarb metadata`, and pnpm, take the project lock only (`--heavy` still adds it).
# Nested calls inherit the locks already held and take only the ones they miss, in the same
# order. Commands run under `nice -n 10` with capped parallelism.
#
# --wait <s> (or GRIMWORLD_LOCK_WAIT=<s>) bounds the wait for the locks, both together, to <s> seconds:
# past it the command does not run, the script prints "build lock busy for <s> s" and exits 75. The
# command still runs only under the locks, never around them (FND-13: the pre-push check waits 90 s).
#
# Only build and test commands are wrapped: the audit profile allows `scripts/lock.sh …`, so
# this script must not become a way to run anything else.
#
#   scripts/lock.sh [--heavy] [--wait <s>] scarb [--manifest-path <path>] <build|test|lint|fmt|check|metadata|execute> [args...]
#   scripts/lock.sh [--heavy] [--wait <s>] snforge test [args...]
#   scripts/lock.sh [--heavy] [--wait <s>] pnpm <install|build|test|lint|typecheck> [args...]
set -euo pipefail

refuse() {
  echo "scripts/lock.sh: $*" >&2
  echo "usage: scripts/lock.sh [--heavy] [--wait <s>] <scarb|snforge|pnpm> <build or test subcommand> [args...]" >&2
  exit 2
}
heavy=0
wait=${GRIMWORLD_LOCK_WAIT:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --heavy)
      heavy=1
      shift
      ;;
    --wait)
      [ $# -ge 2 ] || refuse "--wait needs a number of seconds"
      wait=$2
      shift 2
      ;;
    *) break ;;
  esac
done
case "$wait" in
  "") ;;
  *[!0-9]* | 0*) refuse "--wait needs a whole number of seconds, at least 1 (got '$wait')" ;;
esac
[ $# -ge 2 ] || refuse "missing command"
# The subcommand must come right after the tool, so that no global option can hide it. The one
# exception: Scarb 2.19 takes --manifest-path as a global option before its subcommand
# (`scarb --manifest-path <path> build`), so that single option, with its value, may sit between.
sub=$2
if [ "$1" = scarb ] && [ "$2" = --manifest-path ]; then
  [ $# -ge 4 ] || refuse "scarb --manifest-path needs a path and a subcommand"
  case "$3" in -*) refuse "scarb --manifest-path needs a path, not '$3'" ;; esac
  sub=$4
fi
case "$1:$sub" in
  scarb:build | scarb:test | scarb:lint | scarb:fmt | scarb:check | scarb:metadata | scarb:execute) ;;
  snforge:test) ;;
  pnpm:install | pnpm:build | pnpm:test | pnpm:lint | pnpm:typecheck) ;;
  *) refuse "does not wrap '$1 $sub'" ;;
esac
# A scarb or snforge build, test, check, lint or execute runs the compiler: it takes the heavy lock
# as `--heavy` does (FND-15), also after `--manifest-path`, which the machine shim does not see.
case "$1:$sub" in
  scarb:build | scarb:test | scarb:lint | scarb:check | scarb:execute | snforge:test) heavy=1 ;;
esac

project_lock=${GRIMWORLD_BUILD_LOCK:-/tmp/grimworld-build.lock}
heavy_lock=${HEAVY_BUILD_LOCK:-$HOME/orchestrator/heavy-build.lock}
# RAYON_NUM_THREADS defaults to 1, like CI: the compiler's `withdraw_gas` placement follows rayon's
# thread order (SPK-13), so D-176 requires local builds to be single-threaded to match CI. A
# RAYON_NUM_THREADS already in the caller's environment still wins (`:-`).
export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-1}" CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"

cmd=("$@")
# Called by something that already holds the heavy lock (a machine shim) without the project
# lock: taking the project lock now would reverse the order and could deadlock, and skipping it
# would break the one-build-at-a-time guarantee. Refused: take the locks through this script.
if [ -n "${HEAVY_BUILD_LOCK_HELD:-}" ] && [ -z "${GRIMWORLD_BUILD_LOCK_HELD:-}" ]; then
  echo "scripts/lock.sh: called under the heavy lock without the project lock (wrong order);" \
    "run the outer command through scripts/lock.sh" >&2
  exit 3
fi
# With a wait, the project lock is taken first for at most <s> s, and the heavy lock for what remains of
# the same deadline (flock -E 75: the exit status of a lock that stayed busy).
deadline=
[ -z "$wait" ] || deadline=$(($(date +%s) + wait))
if [ "$heavy" = 1 ] && [ -z "${HEAVY_BUILD_LOCK_HELD:-}" ]; then
  mkdir -p "$(dirname "$heavy_lock")"
  export HEAVY_BUILD_LOCK_HELD=1
  if [ -n "$wait" ]; then
    # shellcheck disable=SC2016 # the single-quoted script is expanded by the inner shell, on purpose
    cmd=(bash -c 'rem=$(($1 - $(date +%s))); [ "$rem" -ge 1 ] || rem=1; lock=$2; shift 2; exec flock -w "$rem" -E 75 "$lock" "$@"' _ "$deadline" "$heavy_lock" "${cmd[@]}")
  else
    cmd=(flock "$heavy_lock" "${cmd[@]}")
  fi
fi
if [ -z "${GRIMWORLD_BUILD_LOCK_HELD:-}" ]; then
  export GRIMWORLD_BUILD_LOCK_HELD=1
  if [ -n "$wait" ]; then
    cmd=(flock -w "$wait" -E 75 "$project_lock" "${cmd[@]}")
  else
    cmd=(flock "$project_lock" "${cmd[@]}")
  fi
fi
if [ -n "$wait" ]; then
  rc=0
  nice -n 10 "${cmd[@]}" || rc=$?
  if [ "$rc" = 75 ]; then echo "scripts/lock.sh: build lock busy for $wait s" >&2; fi
  exit "$rc"
fi
exec nice -n 10 "${cmd[@]}"
