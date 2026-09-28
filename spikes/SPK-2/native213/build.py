#!/usr/bin/env python3
"""Fix loop 1: the native contracts' sources (../native/src, unchanged) built with Cairo 2.13
(Sierra 1.7.0) instead of 2.19 (Sierra 1.9.3), to see whether the node meters a class by its Sierra
version (it does not: docs/research/SPK-2-cost.md §8.2).

The manifest, the pins and the sources are written here at each run and not tracked: this folder
is not a package of the game, and CI (which builds every tracked Scarb.toml) has nothing to build.
From this folder: python3 build.py
"""
import json
import os
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = """[package]
name = "spk2n"
version = "0.1.0"
edition = "2024_07"
cairo-version = "2.13"

[cairo]
sierra-replace-ids = true

[dependencies]
starknet = "2.13"

[[target.starknet-contract]]
sierra = true
casm = true
"""
# Scarb 2.13 builds; sncast 0.61 (the root's) declares what it built
TOOLS = "scarb 2.13.1\nstarknet-foundry 0.61.0\n"

with open(os.path.join(HERE, "Scarb.toml"), "w") as f:
    f.write(MANIFEST)
with open(os.path.join(HERE, ".tool-versions"), "w") as f:
    f.write(TOOLS)
shutil.rmtree(os.path.join(HERE, "src"), ignore_errors=True)
shutil.copytree(os.path.join(HERE, "..", "native", "src"), os.path.join(HERE, "src"))
subprocess.run(["scarb", "build"], cwd=HERE, check=True)
for name in ("Hub", "Instances"):
    path = os.path.join(HERE, "target", "dev", f"spk2n_{name}.contract_class.json")
    head = [int(x, 16) for x in json.load(open(path))["sierra_program"][:6]]
    print(name, "sierra", ".".join(map(str, head[:3])), "compiler", ".".join(map(str, head[3:])))
