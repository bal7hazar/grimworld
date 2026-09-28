#!/usr/bin/env python3
"""Fix loop 1: which meter does devnet apply to the native calls? Traces the native tick tests in
snforge's two modes (Sierra gas, Cairo steps) so their per-call figures can be set against the
devnet traces' `game_calls`. The budgets are lifted for the run (Cairo-steps figures exceed the
Sierra-gas budgets) and restored after it. From this folder:

    python3 meter_check.py > meter-check-output.txt
"""
import re
import subprocess
import sys

# From part 1's folder (the Dojo baseline, its own pins), the same check runs on its tests with
# its own summariser: python3 native/meter_check.py part1 > meter-check-output.txt
PART1 = sys.argv[1:] == ["part1"]
PATH = "tests/test_systems.cairo"
SUMMARY = "summarize_trace.py"
original = open(PATH).read()
try:
    open(PATH, "w").write(
        re.sub(r"#\[available_gas\(l2_gas: \d+\)\]", "#[available_gas(l2_gas: 4000000000)]", original)
    )
    for mode, extra in (("sierra-gas", []), ("cairo-steps", ["--tracked-resource", "cairo-steps"])):
        out = subprocess.run(
            ["snforge", "test", "test_tick", *extra, "--trace-components", "contract-name", "gas"],
            capture_output=True, text=True,
        )
        with open(f"/tmp/spk2-meter-{mode}.txt", "w") as f:
            f.write(out.stdout)
        summary = subprocess.run(
            ["python3", SUMMARY, f"/tmp/spk2-meter-{mode}.txt"], capture_output=True, text=True
        ).stdout
        print(f"## {mode}\n{summary}")
finally:
    open(PATH, "w").write(original)
