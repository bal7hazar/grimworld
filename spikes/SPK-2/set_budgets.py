#!/usr/bin/env python3
"""Set every test's budget to ceil(1.05 x measured) from an snforge run (docs/CAIRO.md §2).

    snforge test > run.txt; python3 set_budgets.py run.txt
"""
import glob
import math
import re
import sys

measured = {}
last_fail = None
for line in open(sys.argv[1]):
    m = re.match(r"\[PASS\] \S+::(\w+) \(.*l2_gas: ~(\d+)\)", line)
    if m:
        measured[m.group(1)] = int(m.group(2))
    m = re.match(r"\s*Test cost exceeded the available gas\. Consumed .*l2_gas: ~(\d+)", line)
    if m and last_fail:
        measured[last_fail] = int(m.group(1))
    f = re.match(r"\[FAIL\] \S+::(\w+)", line)
    last_fail = f.group(1) if f else (last_fail if not line.startswith("[") else None)

done = set()
for path in sorted(glob.glob("tests/*.cairo")):
    source = open(path).read()

    def budget(match):
        name = match.group(2)
        if name not in measured:
            return match.group(0)
        done.add(name)
        value = measured[name]
        return (
            f"#[available_gas(l2_gas: {math.ceil(1.05 * value)})] // ceil(1.05 × {value} measured)\n"
            f"{match.group(1)}fn {name}("
        )

    source = re.sub(
        r"#\[available_gas\(l2_gas: \d+\)\][^\n]*\n((?:#\[[^\n]*\n)*)fn (\w+)\(", budget, source
    )
    open(path, "w").write(source)
print("set:", len(done), "missing:", sorted(set(measured) - done))
