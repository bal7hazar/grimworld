#!/usr/bin/env bash
# SPK-14: regenerate the tables, format, and run the package's tests into an output file.
#   spikes/SPK-14/test.sh <output file under spikes/SPK-14/> [snforge filter]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$1"
shift
cd "$here"
python3 gen_tables.py > /dev/null
scarb fmt
snforge test "$@" > "$out" 2>&1 || true
grep -cE "^\[PASS\]" "$out" | sed 's/^/passed: /'
grep -E "^\[FAIL\]|error|Tests:" "$out" || true
