#!/usr/bin/env bash
# SPK-5: runs a heavy sozo command of the Dojo baseline under the build locks, since scripts/lock.sh
# no longer wraps sozo (ADR-0007; docs/briefs/COMMON.md §3, OPERATIONS.md §3). The same two locks
# as scripts/lock.sh, always taken in this order:
#   1. the PROJECT lock ($GRIMWORLD_BUILD_LOCK, default /tmp/grimworld-build.lock);
#   2. the machine-wide HEAVY lock ($HEAVY_BUILD_LOCK, default ~/orchestrator/heavy-build.lock),
#      which sozo does not take by itself (it does not go through the machine's shims).
# Locks already held by a caller (GRIMWORLD_BUILD_LOCK_HELD, HEAVY_BUILD_LOCK_HELD set by
# scripts/lock.sh or by this script) are not taken again. The command runs under `nice -n 10` with
# capped parallelism, like scripts/lock.sh, and waits silently while another build holds a lock.
#
#   spikes/SPK-5/locked.sh sozo <build|test|migrate> [args...]
set -euo pipefail

refuse() {
  echo "spikes/SPK-5/locked.sh: $*" >&2
  echo "usage: spikes/SPK-5/locked.sh sozo <build|test|migrate> [args...]" >&2
  exit 2
}
[ $# -ge 2 ] || refuse "missing command"
case "$1:$2" in
  sozo:build | sozo:test | sozo:migrate) ;;
  *) refuse "does not wrap '$1 $2'" ;;
esac

project_lock=${GRIMWORLD_BUILD_LOCK:-/tmp/grimworld-build.lock}
heavy_lock=${HEAVY_BUILD_LOCK:-$HOME/orchestrator/heavy-build.lock}
export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-4}" CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"

cmd=("$@")
# Called under the heavy lock without the project lock: taking the project lock now would reverse
# the order and could deadlock (as scripts/lock.sh, which refuses the same case).
if [ -n "${HEAVY_BUILD_LOCK_HELD:-}" ] && [ -z "${GRIMWORLD_BUILD_LOCK_HELD:-}" ]; then
  refuse "called under the heavy lock without the project lock (wrong order)"
fi
# Built inside out: the heavy lock wraps the command, the project lock wraps that, so the project
# lock is taken first.
if [ -z "${HEAVY_BUILD_LOCK_HELD:-}" ]; then
  mkdir -p "$(dirname "$heavy_lock")"
  export HEAVY_BUILD_LOCK_HELD=1
  cmd=(flock "$heavy_lock" "${cmd[@]}")
fi
if [ -z "${GRIMWORLD_BUILD_LOCK_HELD:-}" ]; then
  export GRIMWORLD_BUILD_LOCK_HELD=1
  cmd=(flock "$project_lock" "${cmd[@]}")
fi
exec nice -n 10 "${cmd[@]}"
