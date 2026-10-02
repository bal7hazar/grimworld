#!/usr/bin/env python3
"""SPK-13b: where the build path enters a Sierra program, and what is left once it is taken out.

    closures.py names <file.json>...           the closure types of each file, with their user-type id
    closures.py compare <a.json> <b.json>      the two texts with the path of contracts/ normalised
    closures.py predict <file.json> <root>...  the text sha256 this file would have if built at <root>

A closure's type is a struct whose debug name is `{closure@<absolute file path>:<line>:<col>: ...}`.
Its long id is `ut@[<id>]`; `names` checks that <id> is starknet_keccak of that name (the id the
compiler derives from the debug name), so the absolute path reaches the program itself, and with
it the class hash. `compare` replaces every `<anything>/contracts/` inside a closure name by
`<ROOT>/contracts/`, recomputes each closure's id from the normalised name, and reports whether
the two texts are then equal: equal means the path explains the whole difference. `predict`
puts another root (the folder that holds contracts/) in place of the build's and prints the text
sha256 a build there would give, if the path is all that changes.
Each file is a Starknet class (`*.contract_class.json`) or a compiled Sierra program, printed by
SPK-13's sierra-dump.
"""
import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPK13 = os.path.join(HERE, "..", "SPK-13")
sys.path.insert(0, SPK13)
import class_hash  # noqa: E402

DUMP = os.path.join(SPK13, "sierra-dump", "target", "release", "sierra-dump")
CLOSURE = re.compile(r"type (\{closure@[^}]*\}) = Struct<ut@\[(\d+)\]")
NAME_PATH = re.compile(r"(\{closure@)[^}]*?(/contracts/)")


def dump(path):
    kind = "class" if path.endswith(".contract_class.json") else "test"
    return subprocess.run([DUMP, kind, path], capture_output=True, text=True, check=True).stdout


def ut_id(name):
    return class_hash.starknet_keccak(name.encode())


def normalise(text, root="<ROOT>"):
    """The text with the path before contracts/ replaced by root, and each closure id recomputed."""
    sub = lambda t: NAME_PATH.sub(lambda m: m.group(1) + root + m.group(2), t)  # noqa: E731
    ids = {}
    for name, uid in CLOSURE.findall(text):
        ids[uid] = str(ut_id(sub(name)))
    text = sub(text)
    return re.sub(r"ut@\[(\d+)\]", lambda m: f"ut@[{ids.get(m.group(1), m.group(1))}]", text)


def names(paths):
    for p in paths:
        found = CLOSURE.findall(dump(p))
        print(f"{p}: {len(found)} closure type(s)")
        for name, uid in found:
            ok = "id = starknet_keccak(name)" if str(ut_id(name)) == uid else "id NOT keccak(name)"
            print(f"  {name}\n    ut@[{uid}]  {ok}")


def compare(a, b):
    ta, tb = dump(a), dump(b)
    na, nb = normalise(ta), normalise(tb)
    for label, x, y in (("as built", ta, tb), ("path normalised", na, nb)):
        ha, hb = (hashlib.sha256(t.encode()).hexdigest()[:12] for t in (x, y))
        print(f"{label:16} {ha} {hb} {'equal' if x == y else 'DIFFERENT'}")
    if na != nb:
        la, lb = na.splitlines(), nb.splitlines()
        diff = [i for i in range(min(len(la), len(lb))) if la[i] != lb[i]]
        print(f"lines {len(la)} / {len(lb)}; {len(diff)} differ; first: {diff[:5]}")
        for i in diff[:3]:
            print(f"  a {i}: {la[i][:200]}\n  b {i}: {lb[i][:200]}")
    return 0 if na == nb else 1


def predict(path, roots):
    text = dump(path)
    for root in roots:
        print(f"{hashlib.sha256(normalise(text, root).encode()).hexdigest()[:12]}  {root}")


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "names":
        names(sys.argv[2:])
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "compare":
        return compare(sys.argv[2], sys.argv[3])
    if len(sys.argv) >= 4 and sys.argv[1] == "predict":
        predict(sys.argv[2], sys.argv[3:])
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
