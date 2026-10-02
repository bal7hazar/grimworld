#!/usr/bin/env python3
"""The committed vector tables against what the code computes (ENG-02 fix loop 1, note 5).

Each table is printed by a test of `grimworld_logic` (`vectors/README.md`); the test holds a digest
of its cases, so a change to a rule fails it until the table and the digest are regenerated. This
script closes the other side: it runs the test, takes the lines it prints and compares them with
the committed file, line by line, so that a new digest without the regenerated file fails too.

    python3 contracts/logic/vectors/check.py           # exit 1 on any difference
    python3 contracts/logic/vectors/check.py --write   # regenerate the files

snforge cannot read a JSON-lines file from a test (`read_txt` takes one felt a line, `read_json`
one JSON document), hence a script; it runs `snforge` from the package's folder.
"""

import os
import subprocess
import sys

PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The file of each table and the tests that print it, in order (a table too long for snforge's
# step limit is printed in parts).
TABLES = {
    "window.jsonl": [
        "grimworld_logic::types::window::tests::test_vectors",
        "grimworld_logic::types::window::tests::test_vectors_1",
    ],
    "hit.jsonl": [
        "grimworld_logic::types::hit::tests::test_vectors",
    ],
    "fate.jsonl": [
        "grimworld_logic::fate::tests::test_vectors",
    ],
    "packing.jsonl": [
        "grimworld_logic::packing::tests::test_vectors",
    ],
}


def printed(test, write):
    """The lines the test prints; it must pass, except when regenerating (the digest is then the
    one to set)."""
    run = subprocess.run(
        ["snforge", "test", test, "--exact"], cwd=PACKAGE, capture_output=True, text=True,
    )
    out = run.stdout.splitlines()
    lines = [line for line in out if line.startswith('{"id"')]
    digest = next((line.split()[1] for line in out if line.startswith("digest ")), None)
    if not lines or (not write and (run.returncode != 0 or "[PASS]" not in run.stdout)):
        sys.exit(f"{test} did not pass:\n{run.stdout[-2000:]}{run.stderr[-2000:]}")
    return lines, digest


def main():
    write = "--write" in sys.argv[1:]
    failed = False
    for name, tests in TABLES.items():
        path = os.path.join(PACKAGE, "vectors", name)
        lines = []
        for test in tests:
            part, digest = printed(test, write)
            if write:
                print(f"{test}: {len(part)} cases from id {len(lines)}, digest {digest}")
            lines += part
        if write:
            with open(path, "w") as out:
                out.write("".join(line + "\n" for line in lines))
            print(f"wrote vectors/{name}: {len(lines)} cases")
            continue
        with open(path) as committed:
            kept = committed.read().splitlines()
        if kept != lines:
            failed = True
            first = next(
                (i for i, (a, b) in enumerate(zip(kept, lines)) if a != b), min(len(kept), len(lines))
            )
            print(f"vectors/{name}: stale ({len(kept)} lines kept, {len(lines)} computed; first "
                  f"difference at line {first + 1}); regenerate with --write")
        else:
            print(f"vectors/{name}: {len(lines)} cases, as computed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
