#!/usr/bin/env python3
"""SPK-16: every pair's difference from snforge's outputs (D-154: two clean builds, each run once).

    python3 pairs.py snforge-test-output-1.txt snforge-test-output-2.txt

A pair `test_pair_<group>_<what>` is measured against its base, `test_base_<group>` for the longest
group of a base that prefixes it (`test_base_reveal_worst_fixture` is the base of
`test_pair_reveal_worst`). Prints each pair's difference in each run and whether the runs agree.
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

SPECIAL = {"test_pair_reveal_worst": "test_base_reveal_worst_fixture"}


def base_of(name, names):
    if name in SPECIAL:
        return SPECIAL[name]
    rest = name[len("test_pair_"):]
    groups = [n[len("test_base_"):] for n in names if n.startswith("test_base_")]
    best = max((g for g in groups if rest.startswith(g + "_")), key=len, default=None)
    return f"test_base_{best}" if best else None


names = sorted(runs[0])
for name in (n for n in names if n.startswith("test_pair_")):
    base = base_of(name, names)
    diffs = [run[name] - run[base] for run in runs]
    agree = "same" if len(set(diffs)) == 1 else "differ"
    print(f"{name:42} {' / '.join(f'{d:>12,}' for d in diffs)}  ({agree}; base {base})")
