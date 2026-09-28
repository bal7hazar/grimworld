#!/usr/bin/env bash
# SPK-5b: runs a command and prints its wall time and the peak resident memory of its largest
# process (getrusage, RUSAGE_CHILDREN), to fill the cost figures of the research file.
#   spikes/SPK-5b/measure.sh scripts/lock.sh scarb build
# Run from the repository root. The time includes any wait on the build lock: measure on a quiet
# lock (the figure is printed with the wait NOT separated).
set -euo pipefail
exec python3 - "$@" <<'PY'
import resource, subprocess, sys, time

cmd = sys.argv[1:]
start = time.monotonic()
rc = subprocess.run(cmd).returncode
wall = time.monotonic() - start
peak_mb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024
print(f"measure: {' '.join(cmd)} -> exit {rc}, wall {wall:.1f} s, peak RSS of the largest process {peak_mb:.0f} MB", file=sys.stderr)
sys.exit(rc)
PY
