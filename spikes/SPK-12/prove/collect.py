#!/usr/bin/env python3
"""SPK-12: gathers the proving runs' tables (prove/out/<run>/results.txt) with the command of each
into spikes/SPK-12/prove-output.txt, and prints, per case, the program hashes and whether the two
runs wrote the same proof bytes.

  python3 spikes/SPK-12/prove/collect.py
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
PARAMS_LARGE = "--params spikes/SPK-12/prove/params.canonical_without_pedersen.json"
# The runs of 2026-10-01, in order, with the arguments they were given.
RUNS = [
    ("run1", "--runs 2 --case representative:1 --case worst:1 --case representative:10 --case busy:10"),
    ("run2", "--runs 2 --case busy:40 --case representative:100 --case representative:1000 "
             "--case representative:2000"),
    ("run3", "--runs 2 --case representative:2600"),
    ("run4", "--runs 2 --case representative:2700"),
    ("run5", f"--runs 2 {PARAMS_LARGE} --case representative:2700"),
    ("run6a", f"--runs 1 {PARAMS_LARGE} --case representative:4500"),
    ("run6b", f"--runs 1 {PARAMS_LARGE} --case representative:4500"),
    ("run7", "--runs 2 --threads 6 --case representative:1 --case busy:40 --case representative:1000"),
    ("run8", "--runs 2 --threads 1 --case representative:1 --case busy:40"),
]


def main() -> None:
    lines = [
        "# SPK-12 proving runs on the Mac, 2026-10-01 (prove/prove.py). Proofs stay in the ignored",
        "# prove/out/, never committed. stwo-cairo 467d5c6 with slingfall's two patches, built by",
        "# prove/setup.sh --native (nightly-2025-06-23). Peak RSS is the child's ru_maxrss (bytes on",
        "# macOS). Steps are scarb execute's (run_and_prove prints no step count at this rev).",
        "",
    ]
    for name, args in RUNS:
        lines.append(f"## {name}: python3 spikes/SPK-12/prove/prove.py "
                     f"--out spikes/SPK-12/prove/out/{name} {args}\n")
        lines.append((OUT / name / "results.txt").read_text())
        for e in json.loads((OUT / name / "results.json").read_text())["results"]:
            proved = [r for r in e["runs"] if r.get("proof_sha256")]
            hashes = sorted({r["program_hash"] for r in proved if r.get("program_hash")})
            same = len({r["proof_sha256"] for r in proved}) <= 1
            lines.append(f"{e['case']}: program hash {', '.join(map(str, hashes)) or '-'}; "
                         f"proofs of the runs identical: {same if proved else '-'}")
        lines.append("")
    text = "\n".join(lines)
    (HERE.parent / "prove-output.txt").write_text(text)
    print(text)


if __name__ == "__main__":
    main()
