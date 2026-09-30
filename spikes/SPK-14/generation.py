#!/usr/bin/env python3
"""SPK-14: the constants of chunk generation with margins, for the rectangle (SPK-7's generator,
its formulas copied from spikes/SPK-7/gen_tables.py) and for the hexagon. Imported by
gen_tables.py.

The hexagon is generated on two half-boards in axial coordinates with the stride 19, where every
neighbour is a constant shift (no parity flag): S holds rows 0-9 at `19 r + q`, N rows 7-16 at
`19 (r - 7) + q`. S is right on rows 0-8, N on rows 8-16; after each step S's row 9 is copied from
N and N's rows 7-8 from S (`sync`: one piece each way, the stride being shared). No layout with a
constant stride holds the hexagon in one felt (307 bits at least, geometry.py): the two halves are
how the automaton and the flood stay bit-parallel. The chunk is packed into its 251 bits at the
end, one piece a row.
"""
from geometry import AREA, ROWS, STARTS, hi, index, inside, lo

P = 2**251 + 17 * 2**192 + 1
LIMB = 2**128
W = 15
STRIDE = 19
OVERLAP = 7  # the first row of N


def inv2(k):
    return pow(2, -k, P)


# --- rectangle (SPK-7) ----------------------------------------------------------------------

def rect(cols, rows):
    return sum(1 << (y * W + x) for y in rows for x in cols)


def even_rows(height, flip):
    return sum(rect(range(W), [y]) for y in range(height) if (y % 2 == 0) != flip)


def rect_tables(array, const):
    out = []
    out.append(const("RECT_INTERIOR", "felt252", rect(range(1, 14), range(1, 14)),
                     "Interior of a 15 x 15 chunk, 13 x 13."))
    out.append(const("RECT_SPINE", "felt252", rect(range(1, 14), [7]) | rect([7], range(1, 14)),
                     "Row 7 and column 7 of the interior."))
    out.append(const("RECT_COL_EAST", "felt252", rect([0], range(1, 14)), "Ring column x = 0, corners excluded."))
    out.append(const("RECT_COL_WEST", "felt252", rect([14], range(1, 14)), "Ring column x = 14, corners excluded."))
    out.append(const("RECT_ROW_SOUTH", "felt252", rect(range(1, 14), [0]), "Ring row y = 0, corners excluded."))
    out.append(const("RECT_ROW_NORTH", "felt252", rect(range(1, 14), [14]), "Ring row y = 14, corners excluded."))
    out.append(array("RECT_EVEN", "felt252", [even_rows(15, False), even_rows(15, True)],
                     "Rows of a chunk on even global rows: `[0]` even start, `[1]` odd (the parity flag)."))
    out.append(const("RECT_LOW30", "u128", 2**30 - 1, "Rows 0 and 1 of a chunk."))
    out.append(const("RECT_UP", "felt252", 1 << (W - 1), "2^(W - 1)."))
    out.append(const("RECT_DOWN", "felt252", inv2(W + 1), "2^-(W + 1)."))
    out.append(const("RECT_LINE_EAST", "felt252", sum(1 << k for k in range(1, 7)),
                     "From an opening at x = 0 to x = 1..6 of its row."))
    out.append(const("RECT_LINE_WEST", "felt252", sum(inv2(k) for k in range(1, 7)) % P,
                     "From an opening at x = 14 to x = 8..13 of its row."))
    out.append(const("RECT_LINE_SOUTH", "felt252", sum(1 << (W * k) for k in range(1, 7)),
                     "From an opening at y = 0 to y = 1..6 of its column."))
    out.append(const("RECT_LINE_NORTH", "felt252", sum(inv2(W * k) for k in range(1, 7)) % P,
                     "From an opening at y = 14 to y = 8..13 of its column."))
    return out


# --- hexagon ------------------------------------------------------------------------------------

def s_bit(q, r):
    assert 0 <= r <= 9
    return STRIDE * r + q


def n_bit(q, r):
    assert 7 <= r <= 16
    return STRIDE * (r - OVERLAP) + q


def tiles():
    return [(q, r) for r in range(ROWS) for q in range(lo(r), hi(r) + 1)]


def corners():
    return {(lo(0), 0), (hi(0), 0), (lo(8), 8), (hi(8), 8), (lo(16), 16), (hi(16), 16)}


def is_ring(q, r):
    return r in (0, 16) or q in (0, 18) or q + r in (8, 26)


# The six sides, non-corner tiles, in order of increasing r then q, with the lattice step of the
# neighbour they face and the neighbour's facing tile (its own frame) for each tile
SIDES = {
    "minus_u": ([(q, 0) for q in range(9, 18)], lambda q, r: (q - 8, 16)),
    "plus_u": ([(q, 16) for q in range(1, 10)], lambda q, r: (q + 8, 0)),
    "plus_r": ([(18, r) for r in range(1, 8)], lambda q, r: (0, r + 8)),
    "minus_r": ([(0, r) for r in range(9, 16)], lambda q, r: (18, r - 8)),
    "plus_ur": ([(26 - r, r) for r in range(9, 16)], lambda q, r: (16 - r, r - 8)),
    "minus_ur": ([(8 - r, r) for r in range(1, 8)], lambda q, r: (18 - r, r + 8)),
}
# Which half holds each side's tiles
HALF = {"minus_u": "S", "plus_r": "S", "minus_ur": "S", "plus_u": "N", "minus_r": "N", "plus_ur": "N"}


def half_bit(side, q, r):
    return s_bit(q, r) if HALF[side] == "S" else n_bit(q, r)


def check_sides():
    for side, (ts, facing) in SIDES.items():
        for q, r in ts:
            assert inside(q, r) and is_ring(q, r) and (q, r) not in corners(), (side, q, r)
            fq, fr = facing(q, r)
            assert inside(fq, fr) and is_ring(fq, fr) and (fq, fr) not in corners(), (side, fq, fr)
    ring = {t for t in tiles() if is_ring(*t)} - corners()
    assert ring == {t for ts, _ in SIDES.values() for t in ts}
    # The facing side of each side is a side: minus_u <-> plus_u, plus_r <-> minus_r, plus_ur <->
    # minus_ur, and the maps are inverse
    pairs = {"minus_u": "plus_u", "plus_u": "minus_u", "plus_r": "minus_r", "minus_r": "plus_r",
             "plus_ur": "minus_ur", "minus_ur": "plus_ur"}
    for side, (ts, facing) in SIDES.items():
        other_tiles, other_facing = SIDES[pairs[side]]
        assert sorted(facing(*t) for t in ts) == sorted(other_tiles), side
        assert all(other_facing(*facing(*t)) == t for t in ts), side


def mask(bits):
    return sum(1 << b for b in bits)


def wide(name, value, doc):
    """A u256 constant, its limbs given (no conversion at run time)."""
    return (f"/// {doc}\npub const {name}: u256 = u256 {{ low: {hex(value % LIMB)}, "
            f"high: {hex(value // LIMB)} }};\n")


def hex_tables(array, const):
    check_sides()
    out = []
    interior = [t for t in tiles() if not is_ring(*t)]
    out.append(wide("S_INTERIOR", mask(s_bit(q, r) for q, r in interior if r <= 9),
                    "Interior tiles of half S (rows 0-9)."))
    out.append(wide("N_INTERIOR", mask(n_bit(q, r) for q, r in interior if r >= 7),
                    "Interior tiles of half N (rows 7-16)."))
    spine = [(q, r) for q, r in interior if r == 8 or q == 9 or q + r == 17]
    out.append(wide("S_SPINE", mask(s_bit(q, r) for q, r in spine if r <= 9),
                    "The spine in S: row 8, q = 9 and q + r = 17 through the centre (9, 8)."))
    out.append(wide("N_SPINE", mask(n_bit(q, r) for q, r in spine if r >= 7),
                    "The spine in N."))
    out.append(const("INV_18", "felt252", inv2(18), "2^-18."))
    out.append(const("INV_19", "felt252", inv2(19), "2^-19."))
    out.append(const("S_CENTRE", "u8", s_bit(9, 8), "The centre (9, 8) in S."))
    out.append(const("N_CENTRE", "u8", n_bit(9, 8), "The centre (9, 8) in N."))
    out.append(const("LOW19", "u128", 2**STRIDE - 1, "The first row of a half."))
    # Lines from an opening to the spine: constant lengths
    out.append(const("LINE_UP", "felt252", sum(1 << (STRIDE * k) for k in range(1, 8)),
                     "From (q, 0) to (q, 1..7): up 7 rows."))
    out.append(const("LINE_DOWN", "felt252", sum(inv2(STRIDE * k) for k in range(1, 8)) % P,
                     "From (q, 16) to (q, 15..9): down 7 rows."))
    out.append(const("LINE_LOWER_Q", "felt252", sum(inv2(k) for k in range(1, 9)) % P,
                     "From q = 18 or q + r = 26 to the 8 tiles of lower q, to the spine."))
    out.append(const("LINE_HIGHER_Q", "felt252", sum(1 << k for k in range(1, 9)),
                     "From q = 0 or q + r = 8 to the 8 tiles of higher q, to the spine."))
    # Sync: rows 7-8 of S into N, row 9 of N into S: the same shift of 7 rows
    out.append(wide("S_ROWS78", mask(range(s_bit(0, 7), s_bit(0, 9))), "Rows 7-8 of S."))
    out.append(wide("N_ROWS78", mask(range(n_bit(0, 7), n_bit(0, 9))), "Rows 7-8 of N."))
    out.append(wide("S_ROW9", mask(range(s_bit(0, 9), s_bit(0, 9) + STRIDE)), "Row 9 of S."))
    out.append(wide("N_ROW9", mask(range(n_bit(0, 9), n_bit(0, 9) + STRIDE)), "Row 9 of N."))
    out.append(const("SYNC_UP", "felt252", 1 << (STRIDE * OVERLAP), "2^133: N to S."))
    out.append(const("SYNC_DOWN", "felt252", inv2(STRIDE * OVERLAP), "2^-133: S to N."))
    # Drawn openings: the half bits of each side's non-corner tiles, by index
    for side, (ts, _) in SIDES.items():
        out.append(array(f"SIDE_{side.upper()}", "u8", [half_bit(side, q, r) for q, r in ts],
                         f"Side {side}: the half bits of its non-corner tiles."))
    # Copies: the long sides are one piece of the neighbour's dense felt
    out.append(wide("COPY_MINUS_U_MASK", mask(index(*SIDES["plus_u"][0][i]) for i in range(9)),
                    "The neighbour -T_U's facing side (its row 16), dense."))
    out.append(const("COPY_MINUS_U_SHIFT", "felt252",
                     inv2(index(1, 16) - s_bit(9, 0)), "Its row 16 onto our row 0 in S."))
    out.append(wide("COPY_PLUS_U_MASK", mask(index(*SIDES["minus_u"][0][i]) for i in range(9)),
                    "The neighbour +T_U's facing side (its row 0), dense."))
    out.append(const("COPY_PLUS_U_SHIFT", "felt252",
                     1 << (n_bit(1, 16) - index(9, 0)), "Its row 0 onto our row 16 in N."))
    # The short sides are gathers: (the neighbour's dense bit, our half bit), 7 each
    for side in ("plus_r", "minus_r", "plus_ur", "minus_ur"):
        ts, facing = SIDES[side]
        pairs = [(index(*facing(q, r)), half_bit(side, q, r)) for q, r in ts]
        out.append(f"/// Side {side} copied: (the neighbour's dense bit, our half bit).\n"
                   f"pub const GATHER_{side.upper()}: [(u8, u8); {len(pairs)}] = ["
                   + ", ".join(f"({a}, {b})" for a, b in pairs) + "];\n")
    # Packing: per row, its half's mask (limbs) and the shift to its dense bits
    pack = []
    for r in range(ROWS):
        bits = [s_bit(q, r) if r <= 8 else n_bit(q, r) for q in range(lo(r), hi(r) + 1)]
        m = mask(bits)
        shift = STARTS[r] - bits[0]
        pack.append((m % LIMB, m // LIMB, pow(2, shift, P)))
    out.append(f"/// Packing: per row `(mask_low, mask_high, shift)` from its half (S rows 0-8, N 9-16).\n"
               f"pub const PACK: [(u128, u128, felt252); {ROWS}] = ["
               + ", ".join(f"({hex(a)}, {hex(b)}, {hex(c)})" for a, b, c in pack) + "];\n")
    # For the tests: each side's non-corner dense bits, and the facing dense bits
    for side, (ts, facing) in SIDES.items():
        out.append(array(f"DENSE_{side.upper()}", "u8", [index(q, r) for q, r in ts],
                         f"Side {side}: its non-corner tiles, dense."))
        out.append(array(f"FACING_{side.upper()}", "u8", [index(*facing(q, r)) for q, r in ts],
                         f"Side {side}: the neighbour's facing tiles, dense (its frame)."))
    return out


def tables(array, const):
    return rect_tables(array, const) + hex_tables(array, const)


if __name__ == "__main__":
    check_sides()
    print("sides: six sides of 9, 9, 7, 7, 7, 7 non-corner tiles; facing maps are bijections")
