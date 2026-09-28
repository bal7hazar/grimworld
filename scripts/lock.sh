#!/usr/bin/env bash
# Build lock of Grim World. The VPS (8 vCPU, 31 GB) is shared with the owner's other programmes:
# two concurrent Cairo test builds can be OOM-killed, and a sustained 100 % CPU makes the
# hypervisor throttle the machine. Two locks, always taken in this order:
#   * the PROJECT lock ($GRIMWORLD_BUILD_LOCK, default /tmp/grimworld-build.lock): at most one
#     heavy Grim World command at a time, whichever agent runs it;
#   * the machine-wide HEAVY lock ($HEAVY_BUILD_LOCK, default ~/orchestrator/heavy-build.lock),
#     shared with every other programme. `scarb` and `snforge` on PATH are the machine's shims
#     (~/.local/bin), which take it by themselves; this script takes it for `--heavy` and for the
#     `sozo` commands that compile, since sozo does not go through those shims.
# Nested calls inherit the locks. Commands run under `nice -n 10` with capped parallelism.
#
#   scripts/lock.sh [--heavy] <scarb|snforge|sozo|pnpm> [args...]
set -euo pipefail

usage() {
  echo "usage: scripts/lock.sh [--heavy] <scarb|snforge|sozo|pnpm> [args...]" >&2
  exit 2
}
heavy=0
if [ "${1:-}" = --heavy ]; then heavy=1; shift; fi
[ $# -gt 0 ] || usage
case "$1" in
  scarb | snforge | sozo | pnpm) ;;
  *) echo "scripts/lock.sh wraps scarb, snforge, sozo and pnpm only, not '$1'" >&2; exit 2 ;;
esac
case "$1:${2:-}" in sozo:build | sozo:test | sozo:migrate) heavy=1 ;; esac

project_lock=${GRIMWORLD_BUILD_LOCK:-/tmp/grimworld-build.lock}
heavy_lock=${HEAVY_BUILD_LOCK:-$HOME/orchestrator/heavy-build.lock}
export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-4}" CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"

if [ -n "${GRIMWORLD_BUILD_LOCK_HELD:-}" ]; then
  exec "$@"
fi
export GRIMWORLD_BUILD_LOCK_HELD=1
if [ "$heavy" = 1 ] && [ -z "${HEAVY_BUILD_LOCK_HELD:-}" ]; then
  mkdir -p "$(dirname "$heavy_lock")"
  export HEAVY_BUILD_LOCK_HELD=1
  exec nice -n 10 flock "$project_lock" flock "$heavy_lock" "$@"
fi
exec nice -n 10 flock "$project_lock" "$@"
