#!/usr/bin/env python3
"""Fixtures of SPK-4's negative checks (fix loop 1), derived from the vectors and the scarb sample:

  fixtures/sample-vectors.jsonl     the vectors of the 200 sampled ids, unchanged: a supplied file
                                    that every checker must read instead of the default one
  fixtures/wrong-expectation.jsonl  the same, with ONE expectation deliberately wrong (the first
                                    returning vector's last felt + 1): every checker must fail
  fixtures/empty.jsonl              no line: a verification that verifies nothing must fail

  python3 spikes/SPK-4/make_fixtures.py
"""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ids = {json.loads(l)["id"] for l in open(os.path.join(HERE, "vectors", "scarb-sample.jsonl"), encoding="utf-8")}
    vectors = [json.loads(l) for l in open(os.path.join(HERE, "vectors", "vectors.jsonl"), encoding="utf-8")]
    chosen = [v for v in vectors if v["id"] in ids]
    os.makedirs(os.path.join(HERE, "fixtures"), exist_ok=True)

    def write(name, rows):
        with open(os.path.join(HERE, "fixtures", name), "w", encoding="utf-8") as f:
            for v in rows:
                f.write(json.dumps(v, separators=(",", ":")) + "\n")

    write("sample-vectors.jsonl", chosen)
    wrong = [dict(v) for v in chosen]
    k = next(i for i, v in enumerate(wrong) if "ok" in v)
    wrong[k]["ok"] = wrong[k]["ok"][:-1] + [hex(int(wrong[k]["ok"][-1], 16) + 1)]
    write("wrong-expectation.jsonl", wrong)
    write("empty.jsonl", [])
    print(f"{len(chosen)} sampled vectors; wrong expectation on vector id {wrong[k]['id']}: "
          f"{chosen[k]['ok']} -> {wrong[k]['ok']}")


if __name__ == "__main__":
    main()
