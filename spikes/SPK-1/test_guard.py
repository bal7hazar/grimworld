#!/usr/bin/env python3
"""SPK-1 fix loop 1, finding 2: the repeat-run guard of measure.mjs and deploy.mjs refuses before
reading the variables or calling the network. The STARKNET_* variables are forced empty here, so
a script that got past its guard would stop in `configure()` with exit 2 ("is not set"); a guard
refusal is exit 4 with its own message. Temporary folders stand for the output folder
(SPK1_OUT_DIR); the committed measure-output.txt is only hashed, never moved.

    python3 spikes/SPK-1/test_guard.py
"""
import hashlib
import os
import subprocess
import sys
import tempfile

EMPTY = {n: "" for n in ("STARKNET_NETWORK", "STARKNET_RPC_URL", "STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY")}
failures = 0


def run(command, out_dir=None):
    env = dict(os.environ, **EMPTY)
    env.pop("SPK1_OUT_DIR", None)
    if out_dir:
        env["SPK1_OUT_DIR"] = out_dir
    return subprocess.run(command, capture_output=True, text=True, env=env)


def check(name, ok, r):
    global failures
    failures += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}: exit {r.returncode}")
    for line in (r.stdout + r.stderr).strip().splitlines():
        print(f"    {line[:200]}")


def digest(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]


MEASURE = ["node", "spikes/SPK-1/measure.mjs"]
DEPLOY = ["node", "spikes/SPK-1/deploy.mjs"]

# 1. The committed run: a second invocation refuses from the guard; the file is untouched
real = "spikes/SPK-1/measure-output.txt"
before = digest(real)
r = run(MEASURE)
check(f"measure.mjs, second invocation on the committed output (sha256 {before} before, {digest(real)} after)",
      r.returncode == 4 and "measure-output.txt exists" in r.stderr and digest(real) == before, r)

with tempfile.TemporaryDirectory() as tmp:
    # 2. The old failure mode: `> measure-output.txt` had truncated the file to empty before Node
    # started. An empty file (an incomplete run) now refuses as well
    open(os.path.join(tmp, "measure-output.txt"), "w").close()
    r = run(MEASURE, tmp)
    check("measure.mjs, empty output of an incomplete run", r.returncode == 4 and "exists" in r.stderr, r)

    # 3. --recover-incomplete keeps the evidence (renamed), then goes on to configure(), which
    # refuses on the empty variables (exit 2): no new output file, no network call
    r = run(MEASURE + ["--recover-incomplete"], tmp)
    kept = [f for f in os.listdir(tmp) if f.startswith("measure-output.txt.incomplete-")]
    check(f"measure.mjs --recover-incomplete: kept {kept}, new output created: "
          f"{os.path.exists(os.path.join(tmp, 'measure-output.txt'))}",
          r.returncode == 2 and len(kept) == 1 and not os.path.exists(os.path.join(tmp, "measure-output.txt"))
          and "is not set" in r.stderr, r)

    # 4. No output file: the guard passes and configure() refuses (the variables are empty)
    r = run(MEASURE, tmp)
    check("measure.mjs, fresh folder: past the guard, stopped by configure()",
          r.returncode == 2 and "is not set" in r.stderr, r)

    # 5. deploy.mjs: an existing deploy-output.txt refuses; so does sepolia.json
    open(os.path.join(tmp, "deploy-output.txt"), "w").close()
    r = run(DEPLOY, tmp)
    check("deploy.mjs, existing deploy-output.txt", r.returncode == 4 and "deploy-output.txt exists" in r.stderr, r)
    r = run(DEPLOY)
    check("deploy.mjs, committed sepolia.json", r.returncode == 4 and "sepolia.json exists" in r.stderr, r)

print("all passed" if failures == 0 else f"{failures} failed")
sys.exit(1 if failures else 0)
