#!/usr/bin/env python3
"""SPK-14: the figures of one or more snforge runs, each benchmark `X_twice - X_once` (one call),
and each micro-benchmark against its baseline (per iteration, 100 iterations).

    python3 spikes/SPK-14/summarize.py spikes/SPK-14/snforge-test-output-1.txt [...-2.txt]
"""
import re
import sys

LINE = re.compile(r"\[PASS\] spk14_tests::(\w+)::(\w+) \(.*l2_gas: ~(\d+)\)")


def read(path):
    gas = {}
    for line in open(path):
        m = LINE.search(line)
        if m:
            gas[m.group(2)] = int(m.group(3))
    return gas


def main():
    runs = [read(p) for p in sys.argv[1:]]
    names = sorted({n[: -len("_twice")] for n in runs[0] if n.endswith("_twice")})
    header = " | ".join(f"run {i + 1}" for i in range(len(runs)))
    print(f"| Benchmark (twice - once) | {header} |")
    print("|---|" + "---:|" * len(runs))
    for name in names:
        cells = " | ".join(f"{r[name + '_twice'] - r[name + '_once']:,}" for r in runs)
        print(f"| `{name}` | {cells} |")
    micro = [("table lookup, `ROW` (a 3-tuple)", "micro_row_lookup", "micro_mod_baseline"),
             ("table lookup, a slot of 12", "micro_slot_lookup", "micro_mod_baseline"),
             ("table lookup, `Bits::pow`", "micro_pow_lookup", "micro_loop_baseline"),
             ("loop iteration (with an addition)", "micro_loop_baseline", None)]
    print()
    print(f"| Unit cost, per iteration | {header} |")
    print("|---|" + "---:|" * len(runs))
    for label, test, base in micro:
        cells = " | ".join(
            f"{(r[test] - (r[base] if base else 0)) / 100:,.0f}" for r in runs)
        print(f"| {label} | {cells} |")


if __name__ == "__main__":
    main()
