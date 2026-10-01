#!/usr/bin/env python3
"""ENG-01: the size of every contract class of the workspace against Starknet's limits (ADR-0007,
*Class size*; docs/architecture/ENG-01-interfaces.md, *Class size*).

Reads the artifacts of `scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build` (the
`*.starknet_artifacts.json` of `contracts/target/dev/`) and prints, per contract, the Sierra class
(its JSON, the size the network limits) and the CASM bytecode, with the share of each limit. Exits 1
when a class passes a limit, or the warning share given by `--warn` (default 50 %: a class that
reaches half its limit with interfaces only, or at any later lot, is split before it grows).

Limits (docs.starknet.io, *Chain info*, read 2026-09-29): 4,089,446 bytes of Sierra class,
81,920 felts of CASM bytecode.

    python3 contracts/tools/class_sizes.py [--warn PERCENT]
"""
import argparse
import glob
import json
import os
import sys

SIERRA_LIMIT = 4_089_446
BYTECODE_LIMIT = 81_920
HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = os.path.join(os.path.dirname(HERE), "target", "dev")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--warn", type=float, default=50.0)
    args = parser.parse_args()
    manifests = sorted(m for m in glob.glob(os.path.join(TARGET, "*.starknet_artifacts.json"))
                       if not m.endswith(".test.starknet_artifacts.json"))
    if not manifests:
        sys.exit("class_sizes: no artifacts; build the workspace first")
    rows, failed, seen = [], False, set()
    for manifest in manifests:
        for contract in json.load(open(manifest))["contracts"]:
            # A library class a package's tests declare (`build-external-contracts`: `Hub`'s
            # `FlattenLibrary`, CBT-02e) is in that package's artifacts too: listed once.
            key = (contract["package_name"], contract["contract_name"])
            if key in seen:
                continue
            seen.add(key)
            artifacts = contract["artifacts"]
            sierra_path = os.path.join(TARGET, artifacts["sierra"])
            casm_path = os.path.join(TARGET, artifacts["casm"])
            sierra_bytes = os.path.getsize(sierra_path)
            sierra_felts = len(json.load(open(sierra_path))["sierra_program"])
            bytecode = len(json.load(open(casm_path))["bytecode"])
            share = max(100 * sierra_bytes / SIERRA_LIMIT, 100 * bytecode / BYTECODE_LIMIT)
            flag = "ok" if share < args.warn else "OVER"
            failed |= share >= args.warn
            rows.append((contract["package_name"], contract["contract_name"], sierra_bytes,
                         sierra_felts, bytecode, share, flag))
    print("| Package | Contract | Sierra class, bytes | Sierra program, felts | CASM bytecode, felts "
          "| Share of the nearer limit | |")
    print("|---|---|---:|---:|---:|---:|---|")
    for package, name, sierra_bytes, felts, bytecode, share, flag in rows:
        print(f"| {package} | `{name}` | {sierra_bytes:,} | {felts:,} | {bytecode:,} | {share:.2f} % "
              f"| {flag} |")
    print(f"\nLimits: {SIERRA_LIMIT:,} bytes of Sierra class, {BYTECODE_LIMIT:,} felts of CASM "
          f"bytecode; warning at {args.warn:g} %.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
