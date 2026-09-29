#!/usr/bin/env python3
"""SPK-1b: one line per record of the measurement outputs (label, type, status, block, L2 gas,
L1 data gas, fee, and the trace's validate, execute and fee transfer). Reads only committed,
redacted outputs.

    python3 spikes/SPK-1b/summary.py spikes/SPK-1b/measure-output.txt [...]
"""
import json
import sys

for path in sys.argv[1:]:
    for line in open(path):
        r = json.loads(line)
        if "l2_gas" not in r:
            print("  ", json.dumps(r)[:300])
            continue
        t = r.get("trace") or {}
        print(f"{r['label'][:42]:42} {r['type']:14} {r['status']:9} {r['block_number']} "
              f"l2={r['l2_gas']:>10,} da={r['l1_data_gas']:>5} fee={int(r['fee']) / 1e18:.4f} "
              f"validate={t.get('validate')} execute={t.get('execute_total')} fee_transfer={t.get('fee_transfer')}")
