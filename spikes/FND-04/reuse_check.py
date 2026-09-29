#!/usr/bin/env python3
"""Fix loop 1, finding 2: do the enters write new keys, and does any new write revisit a key an
earlier transaction had zeroed? Reads traces.jsonl only.

    python3 spikes/FND-04/reuse_check.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
rows = [json.loads(line) for line in open(os.path.join(HERE, "traces.jsonl"))]
rows.sort(key=lambda d: d["block"])  # SPK-1 then SPK-1b, in chain order
zeroed, enter_new = set(), []
revisits = 0
for d in rows:
    for c in d["state_diff"]["storage"]:
        if c["contract"] not in ("Hub", "Instances"):
            continue
        for e in c["entries"]:
            key = (c["contract"], e["key"])
            if e["prev_zero"] and key in zeroed:
                revisits += 1
            if e["value_zero"]:
                zeroed.add(key)
            if e["prev_zero"] and d["label"].split(":")[-1].strip() == "enter":
                enter_new.append(key)
enters = sum(1 for d in rows if d["label"].split(":")[-1].strip() == "enter")
print(f"enter transactions: {enters}; new game slots they wrote: {len(enter_new)}; distinct: {len(set(enter_new))}")
print(f"game keys zeroed by some transaction: {len(zeroed)}; new writes to a key zeroed earlier: {revisits}")
