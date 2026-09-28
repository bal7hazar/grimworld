#!/usr/bin/env python3
"""SPK-7: the table of the local node's receipts, from one or more outputs of devnet.py.

    python3 spikes/SPK-7/summarize.py spikes/SPK-7/devnet-output*.txt

One row per measured transaction: L2 gas and L1 data gas of each run (min-max when they differ),
then the differences that answer the brief: A - S (what the chunked map adds to SPK-2's tick), B - A
(stored against assembled), and the most expensive biome of each reveal.
"""
import json
import sys


def load(path):
    rows = {}
    for line in open(path):
        d = json.loads(line)
        if d.get("measured"):
            assert d["status"] == "SUCCEEDED", d
            rows[d["label"]] = (d["l2_gas"], d["l1_data_gas"])
    return rows


def span(values):
    low, high = min(values), max(values)
    return f"{low:,}" if low == high else f"{low:,}–{high:,}"


def main():
    runs = [load(p) for p in sys.argv[1:]]
    labels = list(runs[0])
    print(f"runs: {len(runs)}\n")
    print("| Transaction | L2 gas | L1 data gas |")
    print("|---|---:|---:|")
    for label in labels:
        l2 = [r[label][0] for r in runs]
        da = [r[label][1] for r in runs]
        print(f"| {label} | {span(l2)} | {span(da)} |")
    first = runs[0]

    def gas(prefix):
        return [r[k][0] for r in runs for k in r if k.startswith(prefix)]

    print("\n| Difference | L2 gas |")
    print("|---|---:|")
    for what in ("waits", "moves"):
        a = gas(f"worst-case tick, A (assembled), adventurer {what}")[0]
        s = gas(f"worst-case tick, S (SPK-2's stand-in), adventurer {what}")[0]
        b = [first[k][0] for k in first if k.startswith("worst-case tick, B (") and k.endswith(what)][0]
        d = max(first[k][0] for k in first if k.startswith("worst-case tick, B' (") and k.endswith(what))
        print(f"| A − S, adventurer {what} (the chunked map's part of the tick) | {a - s:,} |")
        print(f"| B − A, adventurer {what} (stored, chunks kept in sync, against assembled) | {b - a:,} |")
        print(f"| B′ − A, adventurer {what} (stored, occupancy deferred, its costliest case, against assembled) | {d - a:,} |")
    print("\n| Reveal | Most expensive biome | L2 gas (max over runs) |")
    print("|---|---|---:|")
    for case in ("reveal 1 chunk, no neighbour known", "reveal 1 chunk, 4 neighbours known",
                 "reveal 3 chunks, no neighbour known", "reveal 3 chunks, 7 neighbours known"):
        costs = {k.split(", ")[-1]: max(r[k][0] for r in runs) for k in first if k.startswith(case)}
        top = max(costs.values())
        names = ", ".join(sorted(b for b, v in costs.items() if v == top))
        print(f"| {case} | {names} | {top:,} |")


if __name__ == "__main__":
    main()
