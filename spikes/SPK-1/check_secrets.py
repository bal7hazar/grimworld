#!/usr/bin/env python3
"""SPK-1, AC-4: no value of the Sepolia variables anywhere in the branch's history, the working
tree of spikes/SPK-1 and the report. Prints only counts, never a value.

    python3 spikes/SPK-1/check_secrets.py [extra files...]
"""
import os
import re
import subprocess
import sys
from urllib.parse import urlparse

NAMES = ["STARKNET_RPC_URL", "STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY"]
patterns = {}
for name in NAMES:
    value = os.environ.get(name)
    if not value:
        print(f"{name}: not set, cannot check")
        sys.exit(2)
    if name == "STARKNET_RPC_URL":
        patterns[name] = [re.escape(value), re.escape(urlparse(value).netloc)]
    else:
        n = int(value, 16)
        patterns[name] = [f"0x0*{n:x}", str(n)]

history = subprocess.run(["git", "log", "-p", "origin/main..HEAD"], capture_output=True, text=True).stdout
texts = {"git log -p origin/main..HEAD": history}
for root, _, files in os.walk("spikes/SPK-1"):
    if "node_modules" in root:
        continue
    for f in files:
        path = os.path.join(root, f)
        texts[path] = open(path, errors="replace").read()
for path in sys.argv[1:] + ["docs/research/SPK-1-sepolia.md", "REPORT.md"]:
    if os.path.exists(path):
        texts[path] = open(path, errors="replace").read()

found = 0
for name, forms in patterns.items():
    for where, text in texts.items():
        hits = sum(len(re.findall(p, text, re.I)) for p in forms)
        if hits:
            found += hits
            print(f"FOUND {name} in {where}: {hits}")
print(f"checked {len(texts)} texts for {len(patterns)} variables: {found} occurrences")
sys.exit(1 if found else 0)
