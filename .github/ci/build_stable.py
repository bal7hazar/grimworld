#!/usr/bin/env python3
"""D-176 / SPK-13: three clean builds of the workspace give one result (FND-11).

Runs `scarb clean` and `scarb build --workspace` three times (the caller sets RAYON_NUM_THREADS=1,
the build pin) and compares, per contract class, the CASM (the compiled class, byte for byte) and
the length of the Sierra program in felts. A mismatch fails.

It does NOT compare a class hash or a Sierra file hash: both depend on the absolute build path
(closure type names), so they differ between a worktree and CI even on Linux (SPK-13b, #283). The
CASM and the Sierra felt counts do not. Run from the workspace folder (`contracts/`).

    python3 ../.github/ci/build_stable.py [--builds N]
"""
import argparse
import glob
import hashlib
import json
import os
import subprocess
import sys


def snapshot():
    out = {}
    for casm in sorted(glob.glob("target/dev/*.compiled_contract_class.json")):
        sierra = casm.replace(".compiled_contract_class.json", ".contract_class.json")
        with open(casm, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        with open(sierra) as f:
            felts = len(json.load(f)["sierra_program"])
        out[os.path.basename(casm)] = (digest, felts)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--builds", type=int, default=3)
    args = parser.parse_args()
    if os.environ.get("RAYON_NUM_THREADS") != "1":
        sys.exit("build_stable: RAYON_NUM_THREADS=1 is the build pin (D-176); it is not set")
    runs = []
    for n in range(1, args.builds + 1):
        subprocess.run(["scarb", "clean"], check=True)
        subprocess.run(["scarb", "build", "--workspace"], check=True)
        runs.append(snapshot())
        print(f"build {n}: {len(runs[-1])} classes")
    if not runs[0]:
        sys.exit("build_stable: no compiled class found under target/dev")
    bad = [k for k in runs[0] if any(r.get(k) != runs[0][k] for r in runs[1:])]
    for k in sorted(runs[0]):
        digest, felts = runs[0][k]
        print(f"{'DIFFERS' if k in bad else 'same   '} {k}: CASM sha256 {digest[:16]}, Sierra {felts} felts")
    if bad or any(set(r) != set(runs[0]) for r in runs[1:]):
        sys.exit(f"build_stable: {args.builds} clean builds did not give one result")
    print(f"build_stable: {args.builds} clean builds, one CASM and one Sierra size per class")


main()
