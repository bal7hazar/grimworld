#!/usr/bin/env python3
"""What each option ships to the client: raw, gzip -9 and (if the module is present) brotli sizes.

  python3 spikes/SPK-4/sizes.py
"""

import gzip
import os

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = {
    "(a) mirror: ts/logic.ts": "ts/logic.ts",
    "(a) mirror: ts/cairo.ts": "ts/cairo.ts",
    "(a) mirror: ts/table.ts": "ts/table.ts",
    "(b) VM: spk4_runner_bg.wasm": "vm/pkg-web/spk4_runner_bg.wasm",
    "(b) VM: spk4_runner.js (bindings)": "vm/pkg-web/spk4_runner.js",
    "(b) logic: step.executable.json": "exec/target/dev/step.executable.json",
}

try:
    import brotli  # type: ignore
except ImportError:
    brotli = None

print("| File | Raw | gzip -9 | brotli |\n|---|---:|---:|---:|")
for name, rel in FILES.items():
    data = open(os.path.join(HERE, rel), "rb").read()
    br = f"{len(brotli.compress(data)):,}" if brotli else "not measured"
    print(f"| {name} | {len(data):,} | {len(gzip.compress(data, 9)):,} | {br} |")
