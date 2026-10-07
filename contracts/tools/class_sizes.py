#!/usr/bin/env python3
"""ENG-01: the size of every contract class of the workspace against Starknet's limits (ADR-0007,
*Class size*; docs/architecture/ENG-01-interfaces.md, *Class size*).

Reads the artifacts of `scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build` (which takes the heavy lock; the
`*.starknet_artifacts.json` of `contracts/target/dev/`) and prints, per contract, the Sierra class
(its JSON, the size the network limits) and the CASM bytecode, with the share of each limit. Exits 1
when a class passes a limit, or the warning share given by `--warn` (default 50 %: a class that
reaches half its limit with interfaces only, or at any later lot, is split before it grows).

Limits (docs.starknet.io, *Chain info*, read 2026-09-29): 4,089,446 bytes of Sierra class,
81,920 felts of CASM bytecode.

Two named exceptions to the 50 % (ENG-01 §1.3; decided by the project manager, 2026-10-02,
D-200), each its own threshold, nothing else loosened: `ExecutorLibrary` at most 80,420 CASM felts
(the limit less 1,500 of margin), `TickLibrary` at most 75 % (61,440 felts), its room kept for
CBT-05b's resolution parts and ENG-07's act hook; raised to 88 % (72,090 felts) for the action
phase (the project manager, 2026-10-07, D-222); `TrapLibrary`, a trap's trigger, at most 78 %
(63,900 felts; D-222 amended). D-209's two (`RevealLibrary` at most 50.5 %, `Instances` at most
51 %, for ENG-05's zone quota hosts) were removed by ENG-05b, which brought both back under 50 %.

    python3 contracts/tools/class_sizes.py [--warn PERCENT]
"""
import argparse
import glob
import json
import os
import sys

SIERRA_LIMIT = 4_089_446
BYTECODE_LIMIT = 81_920
# D-200: (package, contract) -> its warning share, in percent of the nearer limit.
EXCEPTIONS = {
    ("grimworld_logic", "ExecutorLibrary"): 100 * 80_420 / BYTECODE_LIMIT,
    # D-222 (CBT-05b): the action phase joins it.
    ("grimworld_logic", "TickLibrary"): 88.0,
    # D-222 amended (CBT-05b): a trap's trigger in its own class, nothing cut.
    ("grimworld_logic", "TrapLibrary"): 78.0,
}
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
            warn = EXCEPTIONS.get(key, args.warn)
            # An exception's own threshold is a ceiling it may reach (`at most`); the default is a
            # share a class stays below.
            over = share > warn if key in EXCEPTIONS else share >= warn
            flag = "OVER" if over else ("ok" if key not in EXCEPTIONS else f"ok (D-200, {warn:.2f} %)")
            failed |= over
            rows.append((contract["package_name"], contract["contract_name"], sierra_bytes,
                         sierra_felts, bytecode, share, flag))
    print("| Package | Contract | Sierra class, bytes | Sierra program, felts | CASM bytecode, felts "
          "| Share of the nearer limit | |")
    print("|---|---|---:|---:|---:|---:|---|")
    for package, name, sierra_bytes, felts, bytecode, share, flag in rows:
        print(f"| {package} | `{name}` | {sierra_bytes:,} | {felts:,} | {bytecode:,} | {share:.2f} % "
              f"| {flag} |")
    print(f"\nLimits: {SIERRA_LIMIT:,} bytes of Sierra class, {BYTECODE_LIMIT:,} felts of CASM "
          f"bytecode; warning at {args.warn:g} %, but the exceptions of D-200 at their own "
          f"thresholds.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
