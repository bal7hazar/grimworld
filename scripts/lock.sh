#!/usr/bin/env bash
# Build lock of Grim World. The VPS (8 vCPU, 31 GB) is shared with the owner's other programmes:
# two concurrent Cairo test builds can be OOM-killed, and a sustained 100 % CPU makes the
# hypervisor throttle the machine. Two locks, always taken in this order:
#   * the PROJECT lock ($GRIMWORLD_BUILD_LOCK, default /tmp/grimworld-build.lock): at most one
#     heavy Grim World command at a time, whichever agent runs it;
#   * the machine-wide HEAVY lock ($HEAVY_BUILD_LOCK, default ~/orchestrator/heavy-build.lock),
#     shared with every other programme. `scarb` and `snforge` on PATH are the machine's shims
#     (~/.local/bin), which take it by themselves; this script takes it for `--heavy`.
# Nested calls inherit the locks already held and take only the ones they miss, in the same
# order. Commands run under `nice -n 10` with capped parallelism.
#
# Only build and test commands are wrapped: the audit profile allows `scripts/lock.sh …`, so
# this script must not become a way to run anything else.
#
#   scripts/lock.sh [--heavy] scarb [--manifest-path <path>] <build|test|lint|fmt|check|metadata|execute> [args...]
#   scripts/lock.sh [--heavy] snforge test [args...]
#   scripts/lock.sh [--heavy] pnpm <install|build|test|lint|typecheck> [args...]
set -euo pipefail

refuse() {
  echo "scripts/lock.sh: $*" >&2
  echo "usage: scripts/lock.sh [--heavy] <scarb|snforge|pnpm> <build or test subcommand> [args...]" >&2
  exit 2
}
heavy=0
if [ "${1:-}" = --heavy ]; then heavy=1; shift; fi
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

project_lock=${GRIMWORLD_BUILD_LOCK:-/tmp/grimworld-build.lock}
heavy_lock=${HEAVY_BUILD_LOCK:-$HOME/orchestrator/heavy-build.lock}
export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-4}" CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"

cmd=("$@")
# Called by something that already holds the heavy lock (a machine shim) without the project
# lock: taking the project lock now would reverse the order and could deadlock, and skipping it
# would break the one-build-at-a-time guarantee. Refused: take the locks through this script.
if [ -n "${HEAVY_BUILD_LOCK_HELD:-}" ] && [ -z "${GRIMWORLD_BUILD_LOCK_HELD:-}" ]; then
  echo "scripts/lock.sh: called under the heavy lock without the project lock (wrong order);" \
    "run the outer command through scripts/lock.sh" >&2
  exit 3
fi
if [ "$heavy" = 1 ] && [ -z "${HEAVY_BUILD_LOCK_HELD:-}" ]; then
  mkdir -p "$(dirname "$heavy_lock")"
  export HEAVY_BUILD_LOCK_HELD=1
  cmd=(flock "$heavy_lock" "${cmd[@]}")
fi
if [ -z "${GRIMWORLD_BUILD_LOCK_HELD:-}" ]; then
  export GRIMWORLD_BUILD_LOCK_HELD=1
  cmd=(flock "$project_lock" "${cmd[@]}")
fi
exec nice -n 10 "${cmd[@]}"
