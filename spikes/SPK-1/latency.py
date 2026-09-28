#!/usr/bin/env python3
"""SPK-1: latency of the first positive receipt response, from measure-output.txt.

Each receipt was polled every `poll_ms` on a fixed schedule from the submission (the clock starts
just before `starknet_addInvokeTransaction`). A status is timed at the ARRIVAL of the first receipt
response that showed it: the "first positive receipt response" latency, as the client saw it.
Percentiles are nearest-rank.

What this can and cannot say (fix loop 1):
- It is an upper bound on when the RPC first reported the status: the RPC evaluated it at some
  moment inside that request, before the response arrived.
- There is no valid lower bound in this run. The run recorded the arrival of the previous,
  negative response, but the RPC evaluated that response at an unknown moment inside its own
  request, not at its arrival. The fields `*_after` of the 2026-09-28 run are not used.
- A figure within about one poll interval plus a round trip of a threshold (250 ms + about
  160 ms here) cannot be called a pass or a miss of that threshold.
- A later run must record every poll as [request start, response arrival, status] (lib.mjs does
  so since fix loop 1). The status became true after the last negative request's start and before
  the first positive response's arrival.

    python3 spikes/SPK-1/latency.py > spikes/SPK-1/latency-output.txt
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TICK = "capped worst-case tick (15 layers, 8 goblins reached), one felt per goblin, checked"
UNCERTAINTY_MS = 250 + 160  # one poll interval + the median round trip of a submission

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

print(f"First positive receipt response latency. Polling: every {start['poll_ms']} ms from the submission; "
      f"tip {int(start['tip']) / 1e9} Gfri (starknet.js recommended tip); one transaction at a time, each sent "
      f"after the previous one was accepted on L2. {len(txs)} transactions, {txs[0]['submitted_at']} to "
      f"{txs[-1]['submitted_at']}. Upper bounds on when the RPC first reported each status; no lower bound "
      f"was recorded.")
print()
print("| Set | n | Pre-confirmed p50 | p95 | max | Accepted on L2 p50 | p95 | max | Pre-confirmed never seen "
      "| Submission answered, p50 |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
for name, rows in GROUPS:
    if not rows:
        continue
    pre = [r["latency_ms"]["pre_confirmed"] for r in rows if "pre_confirmed" in r["latency_ms"]]
    acc = [r["latency_ms"]["accepted"] for r in rows]
    ack = [r["latency_ms"]["submit_ack"] for r in rows]
    missed = sum(1 for r in rows if r["latency_ms"].get("pre_confirmed_missed"))
    p, a = stats(pre), stats(acc)
    print(f"| {name} | {len(rows)} | {p[0]:,} | {p[1]:,} | {p[2]:,} | {a[0]:,} | {a[1]:,} | {a[2]:,} | {missed} | "
          f"{rank(ack, 50):,} |")
print()
print(f"ADR-0001's thresholds, to pre-confirmed: p50 <= 1,000 ms, p95 <= 3,000 ms. The observed figures are "
      f"upper bounds; a figure within {UNCERTAINTY_MS} ms above a threshold is not decided by this sampling")


def verdict(value, threshold):
    if value <= threshold:
        return "met (the observed upper bound is within the threshold)"
    if value - threshold <= UNCERTAINTY_MS:
        return f"not decided ({value - threshold:,} ms above, within the sampling uncertainty)"
    return "missed"


for name, rows in GROUPS[:2] + GROUPS[4:5]:
    pre = [r["latency_ms"]["pre_confirmed"] for r in rows]
    p50, p95, _ = stats(pre)
    print(f"  {name}: p50 {p50:,} ms, {verdict(p50, 1000)}; p95 {p95:,} ms, {verdict(p95, 3000)}")
print()

print("First positive pre-confirmed response, histogram in 250 ms bins, the 70 measured transactions")
bins = {}
for r in GROUPS[4][1]:
    b = r["latency_ms"]["pre_confirmed"] // 250 * 250
    bins[b] = bins.get(b, 0) + 1
for b in sorted(bins):
    print(f"  {b:>5}-{b + 249:<5} ms {'#' * bins[b]} {bins[b]}")
print()
blocks = sorted({r["block_number"] for r in txs})
print(f"Blocks: {blocks[0]} to {blocks[-1]} ({blocks[-1] - blocks[0]} blocks for {len(txs)} sequential transactions)")
