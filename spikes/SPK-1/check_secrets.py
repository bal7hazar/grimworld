#!/usr/bin/env python3
"""SPK-1, AC-4: count occurrences of the Sepolia account's values in the repository's history, the
spike folder, the research note, the report and the agent's log. Prints only counts and the list
of inputs checked, never a value.

    python3 spikes/SPK-1/check_secrets.py --log <agent log> [--report REPORT.md] [extra files...]

- Values: STARKNET_RPC_URL (whole value and host), STARKNET_ACCOUNT_ADDRESS and
  STARKNET_PRIVATE_KEY (every hex form with or without leading zeros, and decimal). A malformed
  value stops the check with a value-free message.
- History: `git log -p --all` (every ref). A git failure fails the check. Git shows binary files as
  "Binary files differ": their content is not scanned (this spike commits none).
- Required inputs: the history, the log, the report, the research note. A missing one fails the
  check. Exit 0 only if every required input was read and no occurrence was found.
"""
import argparse
import os
import re
import subprocess
import sys
from urllib.parse import urlparse

FELT = re.compile(r"0x[0-9a-fA-F]{1,64}")
NAMES = ["STARKNET_RPC_URL", "STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY"]


def fail(message, code=2):
    print(message)
    sys.exit(code)


parser = argparse.ArgumentParser()
parser.add_argument("--log", required=True, help="the agent's log (required for AC-4)")
parser.add_argument("--report", default="REPORT.md")
parser.add_argument("extra", nargs="*")
args = parser.parse_args()

patterns = {}
for name in NAMES:
    value = os.environ.get(name, "")
    if not value:
        fail(f"{name}: not set, cannot check (value-free: nothing to compare against)")
    if name == "STARKNET_RPC_URL":
        try:
            parsed = urlparse(value)
            host = parsed.netloc if parsed.scheme in ("http", "https") else ""
        except ValueError:
            host = ""
        if not host:
            fail(f"{name}: not an http(s) URL (value not shown)")
        patterns[name] = [re.escape(value), re.escape(host)]
    else:
        if not FELT.fullmatch(value):
            fail(f"{name}: not a 0x-prefixed hex felt (value not shown)")
        n = int(value, 16)
        patterns[name] = [f"0x0*{n:x}", rf"(?<![0-9]){n}(?![0-9])"]

texts, missing = {}, []
git = subprocess.run(["git", "log", "-p", "--all"], capture_output=True, text=True, errors="replace")
if git.returncode != 0:
    fail(f"git log -p --all failed (exit {git.returncode}): {git.stderr.strip()[:300]}", 1)
texts["git log -p --all"] = git.stdout

required = [args.log, args.report, "docs/research/SPK-1-sepolia.md"]
for path in required + args.extra:
    if os.path.exists(path):
        texts[path] = open(path, errors="replace").read()
    elif path in required:
        missing.append(path)
for root, _, files in os.walk("spikes/SPK-1"):
    if "node_modules" in root:
        continue
    for f in files:
        path = os.path.join(root, f)
        texts[path] = open(path, errors="replace").read()

found = 0
for name, forms in patterns.items():
    for where, text in texts.items():
        hits = sum(len(re.findall(p, text, re.I)) for p in forms)
        if hits:
            found += hits
            print(f"FOUND {name} in {where}: {hits}")
print("coverage:")
for where, text in texts.items():
    print(f"  read {where} ({len(text):,} characters)")
for path in missing:
    print(f"  MISSING required input {path}")
print(f"checked {len(texts)} texts for {len(patterns)} variables: {found} occurrences; "
      f"{len(missing)} required inputs missing")
sys.exit(1 if found or missing else 0)
