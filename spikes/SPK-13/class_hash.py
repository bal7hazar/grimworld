#!/usr/bin/env python3
"""SPK-13: the class hash of a Sierra class (`*.contract_class.json` of Scarb), in pure Python.

builds.sh uses `starkli class-hash` when starkli is on the PATH and this file otherwise; `--check`
computes both on the given files and fails when they disagree (run on the Mac, where starkli is
present, so that the fallback the VPS may use is a checked one).

The hash (Starknet's `compute_sierra_class_hash`, SNIP of class version 0.1.0):
    poseidon_many([ "CONTRACT_CLASS_V0.1.0", h(EXTERNAL), h(L1_HANDLER), h(CONSTRUCTOR),
                    starknet_keccak(abi as a JSON string), poseidon_many(sierra_program) ])
    h(entry points) = poseidon_many([selector_0, function_idx_0, selector_1, ...])
Poseidon: the Hades permutation of Starknet (width 3, 8 full and 83 partial rounds, MDS
[[3,1,1],[1,-1,1],[1,1,-2]], round constants sha256("Hades<i>") mod p, cairo-lang's
poseidon_utils). Keccak-256 as Ethereum's (not SHA3), masked to 250 bits.

    python3 spikes/SPK-13/class_hash.py <x.contract_class.json>...
    python3 spikes/SPK-13/class_hash.py --check <x.contract_class.json>...
"""
import hashlib
import json
import shutil
import subprocess
import sys

P = 2**251 + 17 * 2**192 + 1
FULL, PARTIAL = 8, 83
RC = [int.from_bytes(hashlib.sha256(f"Hades{i}".encode()).digest(), "big") % P
      for i in range(3 * (FULL + PARTIAL))]


def _mix(s):
    a, b, c = s
    t = a + b + c
    return [(t + 2 * a) % P, (t - 2 * b) % P, (t - 3 * c) % P]


def permute(s):
    k = 0
    for r in range(FULL + PARTIAL):
        s = [(x + RC[k + i]) % P for i, x in enumerate(s)]
        k += 3
        if r < FULL // 2 or r >= FULL // 2 + PARTIAL:
            s = [pow(x, 3, P) for x in s]
        else:
            s[2] = pow(s[2], 3, P)
        s = _mix(s)
    return s


def poseidon_many(values):
    values = list(values) + [1]
    if len(values) % 2:
        values.append(0)
    s = [0, 0, 0]
    for i in range(0, len(values), 2):
        s = permute([(s[0] + values[i]) % P, (s[1] + values[i + 1]) % P, s[2]])
    return s[0]


_KECCAK_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]
_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56],
        [27, 20, 39, 8, 14]]
_M = 2**64 - 1


def _keccak_f(a):
    for rc in _KECCAK_RC:
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ (((c[(x + 1) % 5] << 1) | (c[(x + 1) % 5] >> 63)) & _M)
             for x in range(5)]
        a = [[a[x][y] ^ d[x] for y in range(5)] for x in range(5)]
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                r = _ROT[x][y]
                b[y][(2 * x + 3 * y) % 5] = ((a[x][y] << r) | (a[x][y] >> (64 - r))) & _M if r \
                    else a[x][y]
        a = [[b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y]) for y in range(5)]
             for x in range(5)]
        a[0][0] ^= rc
    return a


def keccak256(data: bytes) -> bytes:
    rate = 136
    data = bytearray(data) + b"\x01"
    data += b"\x00" * (-len(data) % rate)
    data[-1] |= 0x80
    a = [[0] * 5 for _ in range(5)]
    for off in range(0, len(data), rate):
        block = data[off:off + rate]
        for i in range(rate // 8):
            a[i % 5][i // 5] ^= int.from_bytes(block[8 * i:8 * i + 8], "little")
        a = _keccak_f(a)
    return b"".join(a[i % 5][i // 5].to_bytes(8, "little") for i in range(4))


def starknet_keccak(data: bytes) -> int:
    return int.from_bytes(keccak256(data), "big") & (2**250 - 1)


def _entry_points(points):
    flat = []
    for p in points:
        flat += [int(p["selector"], 16), p["function_idx"]]
    return poseidon_many(flat)


def class_hash(cls) -> int:
    eps = cls["entry_points_by_type"]
    # The ABI as the string starkli hashes for a Scarb artefact: Python's default JSON separators
    # (", " and ": "), keys in file order (checked against starkli with --check).
    abi = cls["abi"] if isinstance(cls["abi"], str) else json.dumps(cls["abi"])
    version = int.from_bytes(b"CONTRACT_CLASS_V" + cls["contract_class_version"].encode(), "big")
    return poseidon_many([
        version, _entry_points(eps["EXTERNAL"]), _entry_points(eps["L1_HANDLER"]),
        _entry_points(eps["CONSTRUCTOR"]), starknet_keccak(abi.encode()),
        poseidon_many(int(f, 16) for f in cls["sierra_program"])])


def python_hash(path: str) -> str:
    return f"{class_hash(json.load(open(path))):#066x}"


def starkli_hash(path: str) -> str | None:
    if not shutil.which("starkli"):
        return None
    out = subprocess.run(["starkli", "class-hash", path], capture_output=True, text=True)
    return f"{int(out.stdout.strip(), 16):#066x}" if out.returncode == 0 else None


def main() -> int:
    args = sys.argv[1:]
    check = bool(args) and args[0] == "--check"
    files = args[1:] if check else args
    if not files:
        sys.exit(__doc__)
    bad = 0
    for path in files:
        mine = python_hash(path)
        if check:
            theirs = starkli_hash(path)
            if theirs is None:
                sys.exit("class_hash: --check needs starkli on the PATH")
            same = mine == theirs
            bad += not same
            print(f"{'same' if same else 'DIFFERENT'} {mine} {theirs} {path}")
        else:
            print(f"{mine} {path}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
