#!/usr/bin/env python3
"""Fix loop 1: copy the native sources (../native/src, unchanged) here and build them with this
folder's Cairo 2.13 (Sierra 1.7.0). From this folder: python3 build.py"""
import json
import os
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
shutil.rmtree(os.path.join(HERE, "src"), ignore_errors=True)
shutil.copytree(os.path.join(HERE, "..", "native", "src"), os.path.join(HERE, "src"))
subprocess.run(["scarb", "build"], cwd=HERE, check=True)
for name in ("Hub", "Instances"):
    path = os.path.join(HERE, "target", "dev", f"spk2n_{name}.contract_class.json")
    head = [int(x, 16) for x in json.load(open(path))["sierra_program"][:6]]
    print(name, "sierra", ".".join(map(str, head[:3])), "compiler", ".".join(map(str, head[3:])))
