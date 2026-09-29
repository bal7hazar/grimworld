#!/usr/bin/env python3
"""A sample of the vectors run by `scarb execute` through the `step` executable itself, one run per
case, with its resource usage: the reference the WebAssembly run's outputs and Cairo steps are
compared with (vm/js/bench-core.mjs, part 3). The vectors themselves came from `batch`.

Writes (default) spikes/SPK-4/vectors/scarb-sample.jsonl, committed:
{"id", "ok" | "panic", "steps" (successful runs only: scarb prints no resources for a panic)}.

Exits 1 when a sampled case disagrees with its vector (or its vector has no expectation), and on
any run that neither returns nor panics; 2 on a usage error.

  python3 spikes/SPK-4/vm/scarb_sample.py [--count 200] [--seed 4] [--vectors FILE] [--out FILE]
"""

import argparse
import json
import os
import random
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SPIKE = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(SPIKE))
MANIFEST = "spikes/SPK-4/exec/Scarb.exec.toml"
HEX = re.compile(r"0x[0-9a-fA-F]+")
P = 2**251 + 17 * 2**192 + 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--seed", type=int, default=4)
    ap.add_argument("--vectors", default=os.path.join(SPIKE, "vectors", "vectors.jsonl"))
    ap.add_argument("--out", default=os.path.join(SPIKE, "vectors", "scarb-sample.jsonl"))
    a = ap.parse_args()
    with open(a.vectors, encoding="utf-8") as f:
        vectors = [json.loads(l) for l in f if l.strip()]
    if not 0 < a.count <= len(vectors):
        print(f"scarb_sample: --count {a.count} is outside 1..{len(vectors)}", file=sys.stderr)
        sys.exit(2)
    ids = sorted(random.Random(a.seed).sample(range(len(vectors)), a.count))
    os.makedirs(os.path.join(SPIKE, "out"), exist_ok=True)
    fd, args_path = tempfile.mkstemp(prefix="sample-args-", suffix=".json", dir=os.path.join(SPIKE, "out"))
    os.close(fd)
    out, agree, disagree = [], 0, []
    try:
        for i in ids:
            v = vectors[i]
            with open(args_path, "w", encoding="utf-8") as f:
                json.dump([hex(len(v["case"]))] + v["case"], f)
            p = subprocess.run(
                ["scarb", "--manifest-path", MANIFEST, "execute", "--no-build", "--executable-name", "step",
                 "--arguments-file", args_path, "--print-program-output", "--print-resource-usage",
                 "--output", "none"],
                cwd=ROOT, capture_output=True, text=True,
            )
            text = p.stdout + p.stderr
            row = {"id": v["id"]}
            if p.returncode == 0:
                lines = text.split("Program output:", 1)[1].split("Resources:", 1)[0].split()
                # scarb prints a felt above P/2 as a negative number: back to [0, P).
                row["ok"] = [hex(int(x) % P) for x in lines]
                row["steps"] = int(re.search(r"steps: ([\d,]+)", text).group(1).replace(",", ""))
                same = "ok" in v and row["ok"][1:] == v["ok"]
            else:
                m = re.search(r"Panicked with (.*)$", text, re.M)
                if not m:
                    print(f"scarb_sample: vector {v['id']}: run failed without a panic:\n{text}", file=sys.stderr)
                    sys.exit(1)
                row["panic"] = [hex(int(h, 16)) for h in HEX.findall(re.sub(r"\('[^']*'\)", "", m.group(1)))]
                same = "panic" in v and row["panic"] == v["panic"]
            agree += same
            if not same:
                disagree.append(v["id"])
            out.append(row)
    finally:
        os.remove(args_path)
    with open(a.out, "w", encoding="utf-8") as f:
        for row in out:
            f.write(json.dumps(row) + "\n")
    steps = [r["steps"] for r in out if "steps" in r]
    print(f"{len(out)} cases through `step` ({len(steps)} returned, {len(out) - len(steps)} panicked); "
          f"{agree} agree with the vectors of {os.path.relpath(a.vectors, ROOT)}; steps of the successful runs: "
          f"min {min(steps, default=0)}, mean {sum(steps) / max(1, len(steps)):.1f}, max {max(steps, default=0)}")
    if disagree:
        print(f"FAIL: {len(disagree)} case(s) disagree: {disagree[:10]}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
