#!/usr/bin/env python3
"""SPK-17: the CASM felts of the spike's classes and of ENG-05's, from one build's artifacts
(`contracts/tools/class_sizes.py`'s measure, on the spike's `target/dev`).

    python3 sizes.py
"""
import glob
import json
import os

BYTECODE_LIMIT = 81_920
TARGET = os.path.join(os.path.dirname(os.path.abspath(__file__)), "target", "dev")

for manifest in sorted(glob.glob(os.path.join(TARGET, "*.starknet_artifacts.json"))):
    if manifest.endswith(".test.starknet_artifacts.json"):
        continue
    for contract in json.load(open(manifest))["contracts"]:
        casm = os.path.join(TARGET, contract["artifacts"]["casm"])
        bytecode = len(json.load(open(casm))["bytecode"])
        print(f"| `{contract['contract_name']}` | {bytecode:,} | {100 * bytecode / BYTECODE_LIMIT:.2f} % |")
