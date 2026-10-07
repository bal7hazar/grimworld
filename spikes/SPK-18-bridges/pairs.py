#!/usr/bin/env python3
"""SPK-18: one call's cost, `test_twice_<what>` less `test_once_<what>`, in each snforge output
(D-154: two clean builds, each run once), and whether the runs agree.

    python3 pairs.py snforge-test-output-1.txt snforge-test-output-2.txt
"""
import re
import sys

runs = []
for path in sys.argv[1:]:
    gas = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\[PASS\] \S+::(\w+) \(.*l2_gas: ~(\d+)\)", line)
            if m:
                gas[m.group(1)] = int(m.group(2))
    runs.append(gas)

for name in sorted(n[len("test_once_"):] for n in runs[0] if n.startswith("test_once_")):
    diffs = [run[f"test_twice_{name}"] - run[f"test_once_{name}"] for run in runs]
    agree = "same" if len(set(diffs)) == 1 else "differ"
    print(f"{name:24} {' / '.join(f'{d:>8,}' for d in diffs)}  ({agree})")
