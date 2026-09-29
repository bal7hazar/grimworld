#!/usr/bin/env python3
"""A sample of the vectors run by `scarb execute` through the `step` executable itself, one run per
case, with its resource usage: the reference the WebAssembly run's outputs and Cairo steps are
compared with (vm/js/bench-core.mjs, part 3). The vectors themselves came from `batch`.

Writes spikes/SPK-4/out/scarb-sample.jsonl: {"id", "ok" | "panic", "steps" (ok runs), "gas"}.

  python3 spikes/SPK-4/vm/scarb_sample.py [--count 200] [--seed 4]
"""

import argparse
import json
import os
import random
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SPIKE = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(SPIKE))
MANIFEST = "spikes/SPK-4/exec/Scarb.exec.toml"
ARGS = os.path.join(SPIKE, "out", "sample-args.json")
HEX = re.compile(r"0x[0-9a-fA-F]+")
P = 2**251 + 17 * 2**192 + 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--seed", type=int, default=4)
    a = ap.parse_args()
    with open(os.path.join(SPIKE, "vectors", "vectors.jsonl"), encoding="utf-8") as f:
        vectors = [json.loads(l) for l in f if l.strip()]
    ids = sorted(random.Random(a.seed).sample(range(len(vectors)), a.count))
    out = []
    agree = 0
    for i in ids:
        v = vectors[i]
        with open(ARGS, "w", encoding="utf-8") as f:
            json.dump([hex(len(v["case"]))] + v["case"], f)
        p = subprocess.run(
            ["scarb", "--manifest-path", MANIFEST, "execute", "--no-build", "--executable-name", "step",
             "--arguments-file", ARGS, "--print-program-output", "--print-resource-usage", "--output", "none"],
            cwd=ROOT, capture_output=True, text=True,
        )
        text = p.stdout + p.stderr
        row = {"id": i}
        if p.returncode == 0:
            lines = text.split("Program output:", 1)[1].split("Resources:", 1)[0].split()
            # scarb prints a felt above P/2 as a negative number: back to [0, P).
            row["ok"] = [hex(int(x) % P) for x in lines]
            row["steps"] = int(re.search(r"steps: ([\d,]+)", text).group(1).replace(",", ""))
            agree += "ok" in v and row["ok"][1:] == v["ok"]
        else:
            m = re.search(r"Panicked with (.*)$", text, re.M)
            row["panic"] = [hex(int(h, 16)) for h in HEX.findall(re.sub(r"\('[^']*'\)", "", m.group(1)))]
            agree += "panic" in v and row["panic"] == v["panic"]
        out.append(row)
    os.remove(ARGS)
    with open(os.path.join(SPIKE, "out", "scarb-sample.jsonl"), "w", encoding="utf-8") as f:
        for row in out:
            f.write(json.dumps(row) + "\n")
    steps = [r["steps"] for r in out if "steps" in r]
    print(f"{len(out)} cases through `step`; {agree} agree with the vectors from `batch`; "
          f"steps of the ok runs: min {min(steps)}, mean {sum(steps) / len(steps):.1f}, max {max(steps)}")


if __name__ == "__main__":
    main()
