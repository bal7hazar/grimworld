#!/usr/bin/env python3
"""Summarise an snforge trace of the native tests (`--trace-components contract-name gas`): for
each test, the L2 gas of each top-level call to a measured entrypoint, and of the calls it makes
to the other contract (hub → instances on `enter`, instances → hub on `leave`).

    snforge test test_systems --trace-components contract-name gas > snforge-trace.txt
    python3 summarize_trace.py snforge-trace.txt > snforge-summary.md
"""
import re
import sys

MEASURED = {
    "attack", "attack_felt", "attack_packed", "walk", "walk_packed", "brew", "brew_unsigned",
    "accept_quest", "claim_quest", "enter", "leave",
}

test = None
rows = []
current = None
lines = open(sys.argv[1]).read().splitlines()
i = 0
while i < len(lines):
    line = lines[i]
    m = re.match(r"\[test name\] \S+::(\w+)$", line)
    if m:
        test = m.group(1)
        i += 1
        continue
    m = re.match(r"^([│ ]*)[├└]─ \[selector\] (\w+)$", line)
    if m:
        depth = len(m.group(1)) // 3
        selector = m.group(2)
        contract = re.search(r"\[contract name\] (\w+)", lines[i + 1]).group(1)
        gas = int(re.search(r"\[L2 gas\] (\d+)", lines[i + 2]).group(1))
        if depth == 0:
            current = None
            if selector in MEASURED:
                current = {"test": test, "call": f"{contract}.{selector}", "gas": gas, "sub": 0}
                rows.append(current)
        elif depth == 1 and current is not None:
            current["sub"] += gas
        i += 3
        continue
    i += 1

print("| Test | Call | L2 gas | of which calls to the other contract |")
print("|---|---|---:|---:|")
for r in rows:
    print(f"| {r['test']} | {r['call']} | {r['gas']:,} | {r['sub']:,} |")
