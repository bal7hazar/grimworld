#!/usr/bin/env bash
# SPK-5b: runs a command and prints its wall time and the peak resident memory of its largest
# process (getrusage, RUSAGE_CHILDREN), to fill the cost figures of the research file.
#   spikes/SPK-5b/measure.sh scripts/lock.sh scarb --manifest-path spikes/SPK-5b/Scarb.toml build
#   spikes/SPK-5b/measure.sh --cd spikes/SPK-5b snforge test
# Run from the repository root. --cd runs the command from that folder (snforge selects the
# package by the working directory). The time includes any wait on the build lock: measure on a
# quiet lock (the wait is NOT separated).
set -euo pipefail
exec python3 - "$@" <<'PY'
import os, resource, subprocess, sys, time

args = sys.argv[1:]
cwd = None
if args[:1] == ["--cd"]:
    cwd, args = args[1], args[2:]
start = time.monotonic()
rc = subprocess.run(args, cwd=cwd).returncode
wall = time.monotonic() - start
peak_mb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024
print(f"measure: {' '.join(args)} -> exit {rc}, wall {wall:.1f} s, peak RSS of the largest process {peak_mb:.0f} MB", file=sys.stderr)
sys.exit(rc)
PY
