#!/usr/bin/env python3
"""SPK-1b: prints the invocation tree (contract, selector name, L2 gas) of the first receipt with
a given label, for reading the attribution by hand. Reads only committed, redacted outputs.

    python3 spikes/SPK-1b/tree.py "<label>" [output files...]
"""
import json
import sys

# sn_keccak of the entry points met in these traces (computed with starknet.js hash.getSelectorFromName)
NAMES = json.load(open(__file__.replace("tree.py", "selectors.json")))


def show(node, depth=0):
    if not node:
        return
    name = NAMES.get(hex(int(node["selector"], 16)), node["selector"][:12])
    print(f"{'  ' * depth}{node['to'][:10]}… {name}: {node['l2_gas']:,}")
    for c in node["calls"]:
        show(c, depth + 1)


label = sys.argv[1]
for path in sys.argv[2:]:
    for line in open(path):
        r = json.loads(line)
        if r.get("label") == label and r.get("trace"):
            t = r["trace"]
            print(f"{label}: receipt {r['l2_gas']:,}, trace total {t['trace_resources']['l2_gas']:,}")
            for part in ("validate", "execute", "constructor", "fee_transfer"):
                if t["tree"][part]:
                    print(f"[{part}]")
                    show(t["tree"][part], 1)
            sys.exit(0)
