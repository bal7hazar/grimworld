#!/usr/bin/env python3
"""SPK-13: what differs between builds of one Sierra program, function by function.

    diff_sierra.py <a.json> <b.json> [<c.json>...]

Each file is a Starknet class (`*.contract_class.json`) or a compiled Sierra program
(`*.sierra.json`), printed as text by sierra-dump (cargo build --release --manifest-path
spikes/SPK-13/sierra-dump/Cargo.toml). It compares, against the first file:
  - the declarations: types, libfuncs (by their long id) and functions (by name and signature);
  - per function (by its name, or its index when the class has no debug names): the number of
    statements, of `withdraw_gas` statements, the index of the first one in the function, and
    the functions it calls;
  - the CASM, when a `*.compiled_contract_class.json` sits beside a class: its length and
    whether the bytecode is equal.
"""
import collections
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, "sierra-dump", "target", "release", "sierra-dump")


def dump(path):
    kind = "class" if path.endswith(".contract_class.json") else "test"
    out = subprocess.run([DUMP, kind, path], capture_output=True, text=True, check=True)
    return out.stdout.splitlines()


def parse(lines):
    types, libfuncs, funcs, bodies = {}, {}, [], collections.OrderedDict()
    current = None
    for line in lines:
        m = re.match(r"^type (\S+) = (.*);$", line)
        if m:
            types[m[1]] = m[2]
            continue
        m = re.match(r"^libfunc (\S+) = (.*);$", line)
        if m:
            libfuncs[m[1]] = m[2]
            continue
        m = re.match(r"^(.+?)@(F\d+)\((.*)$", line)
        if m:
            funcs.append((m[1], m[2], m[3]))
            continue
        m = re.match(r"^(F\d+):$", line)
        if m:
            current = m[1]
            bodies[current] = []
            continue
        if re.match(r"^F\d+_B\d+:$", line) or not line:
            continue
        if current is not None:
            bodies[current].append(line)
    return types, libfuncs, funcs, bodies


def summary(path):
    types, libfuncs, funcs, bodies = parse(dump(path))
    wg = {i for i, l in libfuncs.items() if l == "withdraw_gas"}
    calls = {i: re.match(r"function_call<user@(.*)>", l)[1]
             for i, l in libfuncs.items() if l.startswith("function_call<user@")}
    label_name = {label: name for name, label, _ in funcs}
    per = collections.OrderedDict()
    for label, body in bodies.items():
        heads = [re.match(r"^([^(\s]+)\(", s)[1] if re.match(r"^([^(\s]+)\(", s) else "" for s in body]
        per[label_name.get(label, label)] = {
            "statements": len(body),
            "withdraw_gas": sum(h in wg for h in heads),
            "first_withdraw_gas_at": next((i for i, h in enumerate(heads) if h in wg), None),
            "calls": sorted({calls[h] for h in heads if h in calls}),
        }
    return {
        "types": sorted(types.values()), "libfuncs": sorted(libfuncs.values()),
        "funcs": [(n, sig) for n, _, sig in funcs], "per": per,
        "statements": sum(len(b) for b in bodies.values()),
    }


def casm(path):
    other = path.replace(".contract_class.json", ".compiled_contract_class.json")
    if other == path or not os.path.exists(other):
        return None
    return json.load(open(other))["bytecode"]


def main():
    files = sys.argv[1:]
    if len(files) < 2:
        sys.exit(__doc__)
    base = summary(files[0])
    base_casm = casm(files[0])
    print(f"A = {files[0]}: {base['statements']} statements, {len(base['funcs'])} functions")
    for path in files[1:]:
        s = summary(path)
        print(f"\nB = {path}: {s['statements']} statements, {len(s['funcs'])} functions")
        for key in ("types", "libfuncs"):
            a, b = collections.Counter(base[key]), collections.Counter(s[key])
            only_a, only_b = sorted((a - b).elements()), sorted((b - a).elements())
            print(f"  {key}: {'equal sets' if not only_a and not only_b else ''}")
            for x in only_a:
                print(f"    only in A: {x}")
            for x in only_b:
                print(f"    only in B: {x}")
        same_funcs = base["funcs"] == s["funcs"]
        print(f"  function declarations (names, signatures, order): "
              f"{'equal' if same_funcs else 'DIFFERENT'}")
        for name in base["per"].keys() | s["per"].keys():
            fa, fb = base["per"].get(name), s["per"].get(name)
            if fa != fb:
                print(f"  function {name}:\n    A {fa}\n    B {fb}")
        ca, cb = base_casm, casm(path)
        if ca is not None and cb is not None:
            diff = sum(x != y for x, y in zip(ca, cb)) + abs(len(ca) - len(cb))
            print(f"  CASM: A {len(ca)} felts, B {len(cb)} felts, "
                  f"{'equal' if ca == cb else f'{diff} felts differ'}")


if __name__ == "__main__":
    main()
