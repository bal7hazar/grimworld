#!/usr/bin/env python3
"""SPK-13b: which measures of each artefact change between the build paths of build_at.sh.

    paths_table.py <rows.tsv> [<kept dir>]

For every artefact, compares the rows of the series `path:<label>` and prints the artefacts with
any difference, and per measure whether it varies: file sha256, Sierra text sha256, size (felts of
a class, statements of a program), withdraw_gas, CASM felts, CASM sha256, class hash, and, when
the kept dir of collect.py is given, the file's bytes (the first file kept per text).
"""
import collections
import csv
import glob
import os
import sys

MEASURES = ["sha256", "text_sha256", "size", "withdraw_gas", "casm_felts", "casm_sha256", "class_hash"]


def file_bytes(kept, artefact, text):
    if not kept:
        return None
    for d in glob.glob(os.path.join(kept, "contracts", f"{artefact}.{text[:12]}")):
        for f in os.listdir(d):
            if f.endswith(".contract_class.json") or f.endswith(".sierra.json"):
                return os.path.getsize(os.path.join(d, f))
    return None


def main():
    rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
    kept = sys.argv[2] if len(sys.argv) > 2 else None
    series = sorted({r["series"] for r in rows if r["series"].startswith("path:")})
    by = collections.defaultdict(dict)
    for r in rows:
        if r["series"] in series:
            r["bytes"] = file_bytes(kept, r["artefact"], r["text_sha256"])
            by[r["artefact"]][r["series"]] = r
    measures = MEASURES + (["bytes"] if kept else [])
    print("paths: " + ", ".join(series))
    print("| artefact | " + " | ".join(measures) + " |")
    print("|---" * (len(measures) + 1) + "|")
    same = 0
    for artefact in sorted(by):
        got = by[artefact]
        varies = {m: len({str(got[s][m]) for s in got}) > 1 for m in measures}
        if not any(varies.values()):
            same += 1
            continue
        cells = []
        for m in measures:
            vals = [str(got[s][m]) for s in series if s in got]
            if m in ("sha256", "text_sha256", "casm_sha256", "class_hash"):
                vals = [v[:12] if v != "-" else v for v in vals]
            cells.append(("varies: " + " / ".join(vals)) if varies[m] else ("same " + vals[0]))
        print(f"| {artefact} | " + " | ".join(cells) + " |")
    print(f"\n{same} artefacts identical in every measure at every path; "
          f"{len(by) - same} differ (listed).")


if __name__ == "__main__":
    main()
