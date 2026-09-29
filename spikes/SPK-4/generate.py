#!/usr/bin/env python3
"""The vectors of SPK-4: inputs chosen here, outputs computed by the Cairo code under `scarb execute`.

Python only picks inputs and schedules runs; every expected output, and every panic, is what
`scarb execute` printed for the `batch` executable of spikes/SPK-4/exec. A batch prints each
result as soon as it is computed; a panic ends the run, so the case after the last printed result
is the one that panicked, its panic data is read from scarb's error, and the next run starts after it.

Output: spikes/SPK-4/vectors/vectors.jsonl, one case per line,
  {"id": n, "case": ["0x..", ...], "ok": ["0x..", ...]}   or   {"id": n, "case": [...], "panic": ["0x..", ...]}
Felts are written in hex; the field prime P is the Stark prime; a negative i16 is the felt P - x.

  python3 spikes/SPK-4/generate.py [--count 10000] [--seed 4]
"""

import argparse
import json
import os
import random
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
P = 2**251 + 17 * 2**192 + 1
MANIFEST = "spikes/SPK-4/exec/Scarb.toml"
ARGS = os.path.join(HERE, "out", "batch-args.json")
BATCH = 500
U16 = [0, 1, 2, 39, 40, 41, 79, 80, 81, 159, 160, 161, 239, 240, 241, 255, 256, 1000, 32767, 32768, 65534, 65535]
MODIFIERS = [0, 0, 0, 40, -33, 7, -1, -99, -100, -101, 100, 32767, -32768, 7 + 40, 40 - 33]


def felt(x):
    return x % P


def pick_u16(r):
    """A u16 argument: boundaries often, small values mostly, anything sometimes."""
    k = r.random()
    if k < 0.25:
        return r.choice(U16)
    if k < 0.85:
        return r.randrange(0, 300)
    return r.randrange(0, 65536)


def damage_case(r):
    base = r.choice([0, 1, 7, 100, 16383, 16384, 16385, 65535]) if r.random() < 0.2 else r.randrange(0, 2000)
    if r.random() < 0.03:
        base = r.randrange(2000, 65536)
    strength = pick_u16(r)
    armor = pick_u16(r)
    bonus = r.choice([0, 0, 0, 10, 20, 40]) if r.random() < 0.8 else pick_u16(r)
    # Penetration mostly below armor + bonus; above it (an underflow panic) in about 5% of cases.
    if r.random() < 0.05:
        penetration = min(65535, armor + bonus + r.randrange(1, 50))
    else:
        penetration = r.randrange(0, max(1, min(armor + bonus, 65535)) + 1) if r.random() < 0.5 else 0
        penetration = min(penetration, armor + bonus, 65535)
    modifier = r.choice(MODIFIERS) if r.random() < 0.5 else r.randrange(-60, 120)
    return [0, base, strength, armor, bonus, penetration, felt(modifier)]


def layer(r, density):
    """A window layer: each of the 240 tiles set with probability `density`, and now and then
    bits above the window (a felt below P)."""
    v = 0
    for i in range(240):
        if r.random() < density:
            v |= 1 << i
    if r.random() < 0.05:
        v |= r.randrange(0, 2**251) & ~((1 << 240) - 1)
        v %= P
    return v


def tile(r):
    k = r.random()
    if k < 0.15:
        return r.choice([0, 1, 13, 14, 15, 29, 105, 119, 120, 224, 225, 238, 239])
    return r.randrange(0, 240)


def goblin_case(r):
    walkable = layer(r, r.choice([1.0, 0.95, 0.85, 0.7, 0.5]))
    occupied = layer(r, r.choice([0.0, 0.02, 0.05, 0.15]))
    goblin = tile(r)
    k = r.random()
    if k < 0.1:
        target = min(239, goblin + r.choice([1, 14, 15, 16]))  # often a neighbour
    else:
        target = tile(r)
    if r.random() < 0.9:
        occupied |= 1 << goblin  # the goblin's own tile, as the chain marks it
    else:
        occupied &= ~(1 << goblin)  # unmarked: the layer update wraps modulo P
    occupied %= P
    if r.random() < 0.02:
        # Outside the window: a panic, or an argument outside u8 (a decoding panic).
        if r.random() < 0.5:
            goblin = r.choice([240, 241, 255, 256])
        else:
            target = r.choice([240, 255, 256, 70000])
    return [1, walkable, occupied, goblin, target]


def malformed_case(r):
    """Decoding errors: an argument outside its type, a wrong argument count, an unknown op."""
    k = r.randrange(5)
    if k == 0:
        c = damage_case(r)
        c[r.randrange(1, 6)] = r.choice([65536, 70000, P - 1])
        return c
    if k == 1:
        c = damage_case(r)
        c[6] = felt(r.choice([32768, -32769, 40000, 2**64]))
        return c
    if k == 2:
        return damage_case(r)[: r.randrange(1, 7)]
    if k == 3:
        return goblin_case(r) + [0]
    return [r.choice([2, 3, P - 1])] + [0] * 6


def cases(count, seed):
    r = random.Random(seed)
    out = []
    for _ in range(count):
        k = r.random()
        if k < 0.495:
            out.append(damage_case(r))
        elif k < 0.99:
            out.append(goblin_case(r))
        else:
            out.append(malformed_case(r))
    return out


RESULT = re.compile(r"^r \[(.*)\]$")
PANIC = re.compile(r"Panicked with (.*)$")
HEX = re.compile(r"0x[0-9a-fA-F]+")


def run_batch(batch):
    flat = []
    for c in batch:
        flat.append(len(c))
        flat.extend(c)
    with open(ARGS, "w", encoding="utf-8") as f:
        json.dump([hex(len(flat))] + [hex(x) for x in flat], f)
    proc = subprocess.run(
        ["scarb", "--manifest-path", MANIFEST, "execute", "--no-build", "--executable-name", "batch",
         "--arguments-file", ARGS, "--print-program-output", "--output", "none"],
        cwd=ROOT, capture_output=True, text=True,
    )
    results = []
    for line in proc.stdout.splitlines():
        m = RESULT.match(line.strip())
        if m:
            body = m.group(1).strip()
            results.append([int(x.strip()) for x in body.split(",")] if body else [])
    if proc.returncode == 0:
        if len(results) != len(batch):
            sys.exit(f"batch of {len(batch)} printed {len(results)} results:\n{proc.stdout}\n{proc.stderr}")
        return results, None
    text = proc.stdout + proc.stderr
    m = PANIC.search(text)
    if not m:
        sys.exit(f"run failed without a panic:\n{text}")
    # `Panicked with 0x.. ('text').` or `Panicked with (0x.. ('text'), 0x..).`: the felts, without
    # the decoded short strings.
    return results, [int(h, 16) for h in HEX.findall(re.sub(r"\('[^']*'\)", "", m.group(1)))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=10000)
    ap.add_argument("--seed", type=int, default=4)
    a = ap.parse_args()
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    os.makedirs(os.path.join(HERE, "vectors"), exist_ok=True)
    all_cases = cases(a.count, a.seed)
    vectors = []
    i, runs, t0 = 0, 0, time.time()
    while i < len(all_cases):
        batch = all_cases[i : i + BATCH]
        results, panic = run_batch(batch)
        runs += 1
        for c, res in zip(batch, results):
            vectors.append({"id": len(vectors), "case": [hex(x) for x in c], "ok": [hex(x) for x in res]})
        i += len(results)
        if panic is not None:
            vectors.append({"id": len(vectors), "case": [hex(x) for x in all_cases[i]], "panic": [hex(x) for x in panic]})
            i += 1
        if runs % 50 == 0:
            print(f"  {i} cases after {runs} runs, {time.time() - t0:.0f} s", flush=True)
    path = os.path.join(HERE, "vectors", "vectors.jsonl")
    with open(path, "w", encoding="utf-8") as f:
        for v in vectors:
            f.write(json.dumps(v, separators=(",", ":")) + "\n")
    os.remove(ARGS)
    panics = sum(1 for v in vectors if "panic" in v)
    by_op = {}
    for v in vectors:
        key = ("damage" if v["case"][0] == "0x0" else "goblin" if v["case"][0] == "0x1" else "other") + (
            " panic" if "panic" in v else " ok")
        by_op[key] = by_op.get(key, 0) + 1
    print(f"{len(vectors)} vectors, {panics} panics, {runs} runs of scarb execute, {time.time() - t0:.0f} s")
    print(json.dumps(by_op, sort_keys=True))


if __name__ == "__main__":
    main()
