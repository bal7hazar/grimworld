#!/usr/bin/env python3
"""Set every test's budget to ceil(1.05 x measured) from an snforge run (docs/CAIRO.md §2), in the
package's `tests/` and in the unit tests of its `src/` (spikes/SPK-2/set_budgets.py, which reads
`tests/` only). Run from a package's folder:

    snforge test 2>&1 | python3 ../tools/set_budgets.py /dev/stdin

A test run with a budget too low still reports what it consumed; that figure is used.
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
for path in sorted(glob.glob("tests/*.cairo") + glob.glob("src/**/*.cairo", recursive=True)):
    source = open(path).read()

    def budget(match):
        indent, attributes, name = match.group(1), match.group(2), match.group(3)
        if name not in measured:
            return match.group(0)
        done.add(name)
        value = measured[name]
        return (
            f"{indent}#[available_gas(l2_gas: {math.ceil(1.05 * value)})] // ceil(1.05 × {value} "
            f"measured)\n{attributes}{indent}fn {name}("
        )

    updated = re.sub(
        r"([ \t]*)#\[available_gas\(l2_gas: \d+\)\][^\n]*\n((?:[ \t]*#\[[^\n]*\n)*)[ \t]*fn (\w+)\(",
        budget,
        source,
    )
    if updated != source:
        open(path, "w").write(updated)
print("set:", len(done), "missing:", sorted(set(measured) - done))
