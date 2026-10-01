#!/usr/bin/env python3
"""SPK-15: set every test's budget to ceil(1.05 x measured) (docs/CAIRO.md §2), measured being the
higher of the runs given (D-154: two builds, measured twice). Inserts the attribute under `#[test]`
or replaces the one there.

    python3 spikes/SPK-15/set_budgets.py spikes/SPK-15/snforge-test-output-1.txt [...-2.txt]
"""
import glob
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
measured = {}
for path in sys.argv[1:]:
    for line in open(path):
        m = re.match(r"\[PASS\] \S+::(\w+) \(.*l2_gas: ~(\d+)\)", line)
        if m:
            measured[m.group(1)] = max(measured.get(m.group(1), 0), int(m.group(2)))

done = set()
paths = glob.glob(os.path.join(HERE, "tests", "*.cairo")) + glob.glob(os.path.join(HERE, "src", "*.cairo"))
for path in sorted(paths):
    source = open(path).read()

    def budget(match):
        indent, attributes, name = match.group(1), match.group(2), match.group(3)
        if name not in measured:
            return match.group(0)
        done.add(name)
        value = measured[name]
        kept = "".join(line + "\n" for line in attributes.splitlines() if "available_gas" not in line)
        return (f"{indent}#[test]\n{kept}{indent}#[available_gas(l2_gas: {math.ceil(1.05 * value)})]"
                f" // ceil(1.05 × {value} measured)\n{indent}fn {name}(")

    source = re.sub(r"( *)#\[test\]\n((?: *(?:#\[|//)[^\n]*\n)*) *fn (\w+)\(", budget, source)
    open(path, "w").write(source)

missing = sorted(set(measured) - done)
print(f"budgets set: {len(done)}; measured without a declaration found: {missing}")
