#!/usr/bin/env python3
"""SPK-14: write src/tables.cairo, the constants of the hexagonal chunk, its window and its
generation, computed on the plain model (geometry.py, generation.py).

    python3 spikes/SPK-14/gen_tables.py && scripts/lock.sh scarb --manifest-path spikes/SPK-14/Scarb.toml fmt
"""
import os

from geometry import AREA, ROWS, STARTS, hi, index, lo, tile

HERE = os.path.dirname(os.path.abspath(__file__))
P = 2**251 + 17 * 2**192 + 1
LIMB = 2**128


def felt(v):
    return hex(v % P)


def array(name, kind, values, doc):
    body = ", ".join(felt(v) if kind == "felt252" else hex(v) for v in values)
    return f"/// {doc}\npub const {name}: [{kind}; {len(values)}] = [{body}];\n"


def const(name, kind, value, doc):
    return f"/// {doc}\npub const {name}: {kind} = {felt(value) if kind == 'felt252' else hex(value)};\n"


def window_tables():
    out = []
    out.append(array("FIRST", "u8", STARTS, "The first bit of each row of a hexagonal chunk."))
    out.append(array("QLO", "u8", [lo(r) for r in range(ROWS)], "The lowest axial `q` of each row."))
    out.append(array("QHI", "u8", [hi(r) for r in range(ROWS)], "The highest axial `q` of each row."))
    out.append(array("TILE", "u16", [q + 32 * r for q, r in (tile(i) for i in range(AREA))],
                     "The tile of each bit: `q + 32 r`."))
    rows = ", ".join(f"({STARTS[r]}, {hi(r)}, {lo(r)})" for r in range(ROWS))
    out.append("/// Per row of a chunk, one lookup: `(FIRST[r], QHI[r], QLO[r])`.\n"
               f"pub const ROW: [(u8, u8, u8); {ROWS}] = [{rows}];\n")
    out.append(array("BELOW128", "u128", [(1 << k) - 1 for k in range(129)],
                     "`2^k - 1` in one limb, `k` in `0..=128`."))
    below = [(1 << k) - 1 for k in range(AREA + 1)]
    out.append(array("BELOW_LOW", "u128", [b % LIMB for b in below],
                     "The low limb of `2^k - 1`, the bits below `k`, for `k` in `0..=251`."))
    out.append(array("BELOW_HIGH", "u128", [b // LIMB for b in below],
                     "The high limb of `2^k - 1`."))
    interior = sum(1 << (15 * y + x) for y in range(1, 15) for x in range(1, 14))
    out.append(const("WINDOW_INTERIOR_LOW", "u128", interior % LIMB,
                     "The interior of the 15 x 16 window, low limb (its ring is wall)."))
    out.append(const("WINDOW_INTERIOR_HIGH", "u128", interior // LIMB,
                     "The interior of the 15 x 16 window, high limb."))
    return out


def piece_tables():
    """The window's pieces precomputed for every origin class (the table-driven variant): per
    class `(offset, count)` into one list of `(slot, kind, mask_low, mask_high, shift)`; kind 0
    the low limb, 1 the high limb (2^128 folded into the shift), 2 both."""
    from geometry import plan

    at, pieces = [], []
    for i in range(AREA):
        found = plan(*tile(i))
        at.append((len(pieces), len(found)))
        for (da, db), start, n, target in found:
            slot = 4 * da + db + 1
            end = start + n
            run = ((1 << n) - 1) << start
            if end <= 128:
                pieces.append((slot, 0, run, 0, pow(2, target - start, P)))
            elif start >= 128:
                pieces.append((slot, 1, 0, run >> 128, pow(2, target - start + 128, P)))
            else:
                pieces.append((slot, 2, run % LIMB, run >> 128, pow(2, target - start, P)))
    # One const of all 7,824 pieces (39,120 felts), the monolithic table attempted, does not
    # compile: Scarb 2.19.4 stops on "Type size computation failed ... size overflow". Only the
    # benchmark's classes are written
    out = []
    for bit in BENCH_CLASSES:
        offset, count = at[bit]
        out.append(piece_const(f"PIECES_{bit}", f"The window's row runs of origin class {bit}",
                               pieces[offset:offset + count]))
    # Fix loop 1 (audit finding 1): runs of one chunk moved by the same shift share one piece,
    # their masks joined (the grouping of the audit of PR 202)
    counts = []
    for i in range(AREA):
        grouped = grouped_pieces(plan(*tile(i)))
        counts.append(len(grouped))
        if i in GROUPED_CLASSES:
            out.append(piece_const(f"GROUPED_{i}", f"The window's grouped pieces of origin class {i}",
                                   grouped))
    print(f"grouped pieces per class: max {max(counts)} (class {counts.index(max(counts))}),"
          f" min {min(counts)}, classes 25 and 185: {counts[25]}, {counts[185]};"
          f" distribution {dict(sorted((c, counts.count(c)) for c in set(counts)))}")
    return out, len(pieces)


def grouped_pieces(found):
    """The runs of one chunk moved by the same shift joined into one piece, in first-seen order."""
    groups = {}
    for (da, db), start, n, target in found:
        key = (4 * da + db + 1, target - start)
        groups[key] = groups.get(key, 0) | (((1 << n) - 1) << start)
    out = []
    for (slot, delta), run in groups.items():
        if run < LIMB:
            out.append((slot, 0, run, 0, pow(2, delta, P)))
        elif run % LIMB == 0:
            out.append((slot, 1, 0, run >> 128, pow(2, delta + 128, P)))
        else:
            out.append((slot, 2, run % LIMB, run >> 128, pow(2, delta, P)))
    return out


def piece_const(name, doc, rows):
    return (f"/// {doc}: `(slot, kind, mask_low, mask_high, shift)`.\n"
            f"pub const {name}: [(u8, u8, u128, u128, felt252); {len(rows)}] = [\n"
            + "".join(f"    ({s}, {k}, {hex(ml)}, {hex(mh)}, {felt(sh)}),\n"
                      for s, k, ml, mh, sh in rows)
            + "];\n")


# The benchmark's classes: the most pieces (bit 25), the most chunks (bit 185)
BENCH_CLASSES = (25, 185)
# Grouped: the same two, and the class with the most grouped pieces (65: 26)
GROUPED_CLASSES = (25, 65, 185)


def main():
    out = ["//! Generated by gen_tables.py: do not edit by hand.\n"]
    out += window_tables()
    pieces, count = piece_tables()
    # The pieces are their own module, left out of `scarb fmt` (`.cairofmtignore`): the
    # formatter ran out of memory on the table of all 7,824 tuples
    with open(os.path.join(HERE, "src", "pieces.cairo"), "w") as f:
        f.write("//! Generated by gen_tables.py: do not edit by hand.\n\n" + "\n".join(pieces))
    print(f"pieces over the {AREA} classes: {count}")
    from generation import tables as generation_tables

    out += generation_tables(array, const)
    path = os.path.join(HERE, "src", "tables.cairo")
    with open(path, "w") as f:
        f.write("\n".join(out))
    print(f"wrote {path}")


if __name__ == "__main__":
    assert index(*tile(250)) == 250
    main()
