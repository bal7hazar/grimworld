#!/usr/bin/env python3
"""SPK-1: latency from submission to pre-confirmed and to accepted on L2, from measure-output.txt.

Each receipt was polled every `poll_ms` on a fixed schedule from the submission (the clock starts
just before `starknet_addInvokeTransaction`). A status is timed at the arrival of the first answer
that showed it: an upper bound; the previous answer's arrival is the lower bound. Percentiles are
nearest-rank.

    python3 spikes/SPK-1/latency.py > spikes/SPK-1/latency-output.txt
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TICK = "capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked"

records = [json.loads(line) for line in open(os.path.join(HERE, "measure-output.txt"))]
start = records[0]
txs = [r for r in records if "latency_ms" in r]


def rank(values, p):
    s = sorted(values)
    return s[max(0, math.ceil(p / 100 * len(s)) - 1)]


def stats(values):
    return rank(values, 50), rank(values, 95), max(values)


GROUPS = [
    ("Worst tick under D-127 (attack)", [r for r in txs if r["label"] == TICK]),
    ("Cheap action: enter and leave, alternating", [r for r in txs if r["label"] in ("enter", "leave")]),
    ("  of which enter", [r for r in txs if r["label"] == "enter"]),
    ("  of which leave", [r for r in txs if r["label"] == "leave"]),
    ("Both measured sets (70)", [r for r in txs if r["label"] in (TICK, "enter", "leave")]),
    ("Setups and queues (not latency samples)", [r for r in txs if r["label"] not in (TICK, "enter", "leave")]),
]

print(f"Polling: every {start['poll_ms']} ms from the submission; tip {int(start['tip']) / 1e9} Gfri "
      f"(starknet.js recommended tip); one transaction at a time, each sent after the previous one "
      f"was accepted on L2. {len(txs)} transactions, {txs[0]['submitted_at']} to {txs[-1]['submitted_at']}.")
print()
print("| Set | n | Pre-confirmed p50 | p95 | max | Pre-confirmed p50, lower bound | Accepted on L2 p50 | p95 | max "
      "| Missed pre-confirmed | Submission answered, p50 |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
for name, rows in GROUPS:
    if not rows:
        continue
    pre = [r["latency_ms"]["pre_confirmed"] for r in rows if "pre_confirmed" in r["latency_ms"]]
    low = [r["latency_ms"]["pre_confirmed_after"] for r in rows if "pre_confirmed" in r["latency_ms"]]
    acc = [r["latency_ms"]["accepted"] for r in rows]
    ack = [r["latency_ms"]["submit_ack"] for r in rows]
    missed = sum(1 for r in rows if r["latency_ms"].get("pre_confirmed_missed"))
    p = stats(pre)
    a = stats(acc)
    print(f"| {name} | {len(rows)} | {p[0]:,} | {p[1]:,} | {p[2]:,} | {rank(low, 50):,} | {a[0]:,} | {a[1]:,} | "
          f"{a[2]:,} | {missed} | {rank(ack, 50):,} |")
print()
print("ADR-0001's thresholds, to pre-confirmed: p50 <= 1,000 ms, p95 <= 3,000 ms")
for name, rows in GROUPS[:2] + GROUPS[4:5]:
    pre = [r["latency_ms"]["pre_confirmed"] for r in rows]
    low = [r["latency_ms"]["pre_confirmed_after"] for r in rows]
    p50, p95, _ = stats(pre)
    print(f"  {name}: p50 {p50:,} ms ({'meets' if p50 <= 1000 else 'misses'}; lower bound {rank(low, 50):,}), "
          f"p95 {p95:,} ms ({'meets' if p95 <= 3000 else 'misses'}; lower bound {rank(low, 95):,})")
print()

# Distribution, to show the polling grid
print("Pre-confirmed, histogram in 250 ms bins (upper bounds), the 70 measured transactions")
measured = GROUPS[4][1]
bins = {}
for r in measured:
    b = r["latency_ms"]["pre_confirmed"] // 250 * 250
    bins[b] = bins.get(b, 0) + 1
for b in sorted(bins):
    print(f"  {b:>5}-{b + 249:<5} ms {'#' * bins[b]} {bins[b]}")
print()
blocks = sorted({r["block_number"] for r in txs})
span = (blocks[-1] - blocks[0])
print(f"Blocks: {blocks[0]} to {blocks[-1]} ({span} blocks for {len(txs)} sequential transactions)")
