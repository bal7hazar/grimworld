#!/usr/bin/env python3
"""Summarise an snforge trace (`--trace-components contract-name gas`): for each test, the L2 gas
of each top-level call to a measured system, and how much of it the world's storage calls took.

    snforge test test_systems --trace-components contract-name gas > snforge-trace.txt
    python3 summarize_trace.py snforge-trace.txt
"""
import re
import sys

MEASURED = {"tick_worst_case", "queue_moves", "brew", "hub"}

test = None
rows = []
# stack of (depth, selector, contract, gas, world_gas)
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
            if contract in MEASURED:
                current = {"test": test, "call": f"{contract}.{selector}", "gas": gas,
                           "world": 0, "calls": 0}
                rows.append(current)
        elif depth == 1 and current is not None and contract == "world":
            current["world"] += gas
            current["calls"] += 1
        i += 3
        continue
    i += 1

print(f"| Test | Call | L2 gas | of which world calls | world calls | rest |")
print(f"|---|---|---:|---:|---:|---:|")
for r in rows:
    print(f"| {r['test']} | {r['call']} | {r['gas']:,} | {r['world']:,} | {r['calls']} | "
          f"{r['gas'] - r['world']:,} |")
