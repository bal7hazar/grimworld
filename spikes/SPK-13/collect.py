#!/usr/bin/env python3
"""SPK-13: records what one build produced, one row per artefact, appended to a TSV (builds.sh).

    collect.py rows <profile dir> <rows.tsv> <target> <series> <run> <threads> [--keep DIR]
    collect.py table <rows.tsv> <env file>...     the table of builds-<machine>.txt, to stdout

An artefact is a Starknet class (from `*.starknet_artifacts.json`: its Sierra class and its CASM),
or a compiled Sierra program (`*.sierra.json`, the compiled test files `*.test.sierra.json`
included). Per artefact:
  sha256       of the JSON file as written
  size         Sierra felts of a class (`sierra_program`); statements of a program
  withdraw_gas the number of `withdraw_gas` statements of the Sierra program (the libfunc the
               compiler adds to the functions of the feedback set of each call-graph cycle)
  casm         CASM felts (`bytecode`) of a class, and the sha256 of that bytecode
  class_hash   of a class: `starkli class-hash` if starkli is on the PATH, else class_hash.py
               (pure Python, checked against starkli on the Mac; the column says which)
With --keep, the first file of every distinct sha256 of an artefact is copied to DIR.
"""
import collections
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import class_hash  # noqa: E402

COLUMNS = ["target", "series", "run", "threads", "artefact", "kind", "sha256", "size",
           "withdraw_gas", "casm_felts", "casm_sha256", "class_hash", "hash_tool"]
DUMP = os.path.join(HERE, "sierra-dump", "target", "release", "sierra-dump")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def withdraw_gas_in_text(text):
    """`withdraw_gas` statements of a Sierra program printed by sierra-dump."""
    ids = set(re.findall(r"^libfunc (\S+) = withdraw_gas;$", text, re.M))
    return sum(1 for line in text.splitlines()
               if any(line.startswith(i + "(") for i in ids))


def class_withdraw_gas(path):
    if not os.access(DUMP, os.X_OK):
        return "-"
    out = subprocess.run([DUMP, "class", path], capture_output=True, text=True)
    return str(withdraw_gas_in_text(out.stdout)) if out.returncode == 0 else "-"


def program_stats(path):
    """(statements, withdraw_gas statements) of a compiled Sierra program (JSON artefact)."""
    program = json.load(open(path))
    ids = {d["id"]["id"] for d in program["libfunc_declarations"]
           if d["long_id"]["generic_id"] == "withdraw_gas"}
    count = sum(1 for s in program["statements"]
                if "Invocation" in s and s["Invocation"]["libfunc_id"]["id"] in ids)
    return len(program["statements"]), count


def hash_of(path, digest, cache_file):
    """The class hash, from the cache of earlier builds when the file is byte-identical."""
    cache = json.load(open(cache_file)) if os.path.exists(cache_file) else {}
    if digest not in cache:
        theirs = class_hash.starkli_hash(path)
        cache[digest] = [theirs, "starkli"] if theirs is not None \
            else [class_hash.python_hash(path), "class_hash.py"]
        json.dump(cache, open(cache_file, "w"))
    return cache[digest]


def keep(keep_dir, target, artefact, digest, *paths):
    if not keep_dir:
        return
    dest = os.path.join(keep_dir, target, f"{artefact}.{digest[:12]}")
    if os.path.isdir(dest):
        return
    os.makedirs(dest)
    for p in paths:
        shutil.copy2(p, dest)


def rows(profile_dir, out, target, series, run, threads, keep_dir):
    found = []
    seen = set()
    for name in sorted(os.listdir(profile_dir)):
        if not name.endswith(".starknet_artifacts.json"):
            continue
        for c in json.load(open(os.path.join(profile_dir, name)))["contracts"]:
            sierra = os.path.join(profile_dir, c["artifacts"]["sierra"])
            if sierra in seen:
                continue
            seen.add(sierra)
            casm = os.path.join(profile_dir, c["artifacts"]["casm"]) if c["artifacts"].get("casm") \
                else None
            cls = json.load(open(sierra))
            digest = sha256_file(sierra)
            casm_felts, casm_sha = "-", "-"
            if casm:
                bytecode = json.load(open(casm))["bytecode"]
                casm_felts = str(len(bytecode))
                casm_sha = hashlib.sha256(json.dumps(bytecode).encode()).hexdigest()
            h, tool = hash_of(sierra, digest, out + ".hashes.json")
            artefact = os.path.basename(sierra).removesuffix(".contract_class.json")
            found.append([artefact, "class", digest, str(len(cls["sierra_program"])),
                          class_withdraw_gas(sierra), casm_felts, casm_sha, h, tool])
            keep(keep_dir, target, artefact, digest, *(p for p in (sierra, casm) if p))
    for name in sorted(os.listdir(profile_dir)):
        if not name.endswith(".sierra.json"):
            continue
        path = os.path.join(profile_dir, name)
        digest = sha256_file(path)
        statements, wg = program_stats(path)
        artefact = name.removesuffix(".sierra.json")
        kind = "test" if artefact.endswith(".test") else "program"
        found.append([artefact, kind, digest, str(statements), str(wg), "-", "-", "-", "-"])
        keep(keep_dir, target, artefact, digest, path)
    if not found:
        sys.exit(f"collect: no artefact in {profile_dir}")
    new = not os.path.exists(out)
    with open(out, "a") as f:
        if new:
            f.write("\t".join(COLUMNS) + "\n")
        for r in found:
            f.write("\t".join([target, series, str(run), threads] + r) + "\n")
    print(f"collect: {len(found)} artefacts of {target}/{series}/{run}")


def text_sha256(kept_dir, cache, r):
    """sha256 of the program as text with its debug names (sierra-dump), from the kept copy of
    the artefact: equal for two files that differ only by the numbers of their ids."""
    key = r["sha256"]
    if key not in cache:
        folder = os.path.join(kept_dir, r["target"], f"{r['artefact']}.{key[:12]}")
        kind = "class" if r["kind"] == "class" else "test"
        name = r["artefact"] + (".contract_class.json" if kind == "class" else ".sierra.json")
        path = os.path.join(folder, name)
        if not (os.access(DUMP, os.X_OK) and os.path.exists(path)):
            return "-"
        out = subprocess.run([DUMP, kind, path], capture_output=True, check=True)
        cache[key] = hashlib.sha256(out.stdout).hexdigest()
    return cache[key]


def table(path, env_files):
    lines = [l.rstrip("\n").split("\t") for l in open(path)]
    head, data = lines[0], [dict(zip(lines[0], l)) for l in lines[1:]]
    kept_dir = os.path.join(os.path.dirname(path), "kept")
    cache_file = path + ".texts.json"
    cache = json.load(open(cache_file)) if os.path.exists(cache_file) else {}
    for e in env_files:
        print(open(e).read().rstrip() + "\n")
    print("## Distinct values per artefact (count of builds per value)\n")
    print("`text sha256`: of the program printed with its debug names by sierra-dump; two files "
          "with one text and two file hashes differ only by the numbers of their ids.\n")
    print("| target | series | threads | artefact | kind | builds | size | withdraw_gas | CASM felts "
          "| sha256 (12) | text sha256 (12) | CASM sha256 (12) | class hash (12) |")
    print("|---|---|---|---|---|--:|--:|--:|--:|---|---|---|---|")
    groups = collections.OrderedDict()
    for r in data:
        key = (r["target"], r["series"], r["threads"], r["artefact"], r["kind"])
        val = (r["size"], r["withdraw_gas"], r["casm_felts"], r["sha256"][:12],
               text_sha256(kept_dir, cache, r)[:12], r["casm_sha256"][:12], r["class_hash"][:14])
        groups.setdefault(key, collections.Counter())[val] += 1
    for key, values in groups.items():
        for val, n in values.most_common():
            print("| " + " | ".join(key[:5]) + f" | {n} | " + " | ".join(val) + " |")
    json.dump(cache, open(cache_file, "w"))
    print("\n## Every build\n")
    print("| " + " | ".join(head) + " |")
    print("|" + "---|" * len(head))
    for l in lines[1:]:
        print("| " + " | ".join(l) + " |")


def main():
    a = sys.argv[1:]
    if a[:1] == ["rows"] and len(a) >= 7:
        keep_dir = a[a.index("--keep") + 1] if "--keep" in a else None
        rows(a[1], a[2], a[3], a[4], a[5], a[6], keep_dir)
    elif a[:1] == ["table"] and len(a) >= 2:
        table(a[1], a[2:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
