#!/usr/bin/env python3
"""SPK-14: the 9-9-11 hexagonal chunk (D-165) on the game's pointy-top odd-r tiles, in plain Python.

    python3 spikes/SPK-14/geometry.py

NOT RUN by the lot that wrote it: its launch profile refused `python3 <file>` (REPORT.md,
Escalations). Every figure it prints was derived by hand in docs/research/SPK-14-hexagonal-chunks.md;
this script is how the next run checks them. Each check is an `assert` next to the figure the note
states, so a wrong hand derivation fails loudly.

Conventions (origami_hexmap, docs/needs/hexmap.md point 3): odd-r offset `(x, y)`, axial
`q = x - (y >> 1)`, `r = y`; `+y` is North. Axial neighbours: (q±1, r), (q, r±1), (q+1, r-1),
(q-1, r+1).

The chunk H0, axial, anchored at (0, 0) on an even global row:
    0 <= r <= 16,  0 <= q <= 18,  8 <= q + r <= 26
Rows 0 (South) and 16 (North) are the long sides of 11; 17 rows; 19 tiles at the widest (row 8).
Its tiling lattice: T_U = (-9, 17) (across the long sides), T_R = (19, -8), T_U + T_R = (10, 9);
|det| = 251.
"""
from itertools import product

ROWS = 17
T_U = (-9, 17)
T_R = (19, -8)
AREA = 251


def lo(r):
    return max(0, 8 - r)


def hi(r):
    return min(18, 26 - r)


def inside(q, r):
    return 0 <= r <= 16 and 0 <= q <= 18 and 8 <= q + r <= 26


WIDTHS = [hi(r) - lo(r) + 1 for r in range(ROWS)]
STARTS = [sum(WIDTHS[:r]) for r in range(ROWS)]


def index(q, r):
    """Tile -> bit: rows South to North, each row West to East in the index (increasing q)."""
    assert inside(q, r)
    return STARTS[r] + q - lo(r)


def tile(i):
    """Bit -> tile, the inverse of `index`."""
    r = max(k for k in range(ROWS) if STARTS[k] <= i)
    return lo(r) + i - STARTS[r], r


def axial(x, y):
    return x - (y >> 1), y


def offset(q, r):
    return q + (r >> 1), r


def neighbours(q, r):
    return [(q + 1, r), (q - 1, r), (q, r + 1), (q, r - 1), (q + 1, r - 1), (q - 1, r + 1)]


def chunk_of(q, r):
    """The lattice coordinates (a, b) of the chunk holding axial (q, r): the chunk anchored at
    a T_U + b T_R. Rounded from the inverse matrix about the chunk's centre (9, 8), then fixed up."""
    dq, dr = q - 9, r - 8
    a0 = round((8 * dq + 19 * dr) / AREA)
    b0 = round((17 * dq + 9 * dr) / AREA)
    found = []
    for da, db in product(range(-2, 3), repeat=2):
        a, b = a0 + da, b0 + db
        lq = q - a * T_U[0] - b * T_R[0]
        lr = r - a * T_U[1] - b * T_R[1]
        if inside(lq, lr):
            found.append((a, b, index(lq, lr)))
    assert len(found) == 1, (q, r, found)
    return found[0]


def check_shape():
    assert WIDTHS == [11, 12, 13, 14, 15, 16, 17, 18, 19, 18, 17, 16, 15, 14, 13, 12, 11], WIDTHS
    assert sum(WIDTHS) == AREA
    # The bounding box in offset coordinates, for a chunk on an even row: 19 x 17 (not 27 wide)
    xs = [offset(q, r)[0] for r in range(ROWS) for q in range(lo(r), hi(r) + 1)]
    assert max(xs) - min(xs) + 1 == 19, (min(xs), max(xs))
    # Bijection onto 0..250
    seen = {index(q, r) for r in range(ROWS) for q in range(lo(r), hi(r) + 1)}
    assert seen == set(range(AREA))
    assert all(index(*tile(i)) == i for i in range(AREA))
    # Corners: the ends of rows 0, 8 and 16; bit 0 and bit 250 are corners
    corners = [(lo(0), 0), (hi(0), 0), (lo(8), 8), (hi(8), 8), (lo(16), 16), (hi(16), 16)]
    bits = sorted(index(*c) for c in corners)
    assert bits == [0, 10, 116, 134, 240, 250], bits
    # Sides, corners included: 11, 9, 9, 11, 9, 9
    sides = {
        "south (row 0)": [(q, 0) for q in range(lo(0), hi(0) + 1)],
        "q = 18 (rows 0-8)": [(18, r) for r in range(0, 9)],
        "q + r = 26 (rows 8-16)": [(26 - r, r) for r in range(8, 17)],
        "north (row 16)": [(q, 16) for q in range(lo(16), hi(16) + 1)],
        "q = 0 (rows 8-16)": [(0, r) for r in range(8, 17)],
        "q + r = 8 (rows 0-8)": [(8 - r, r) for r in range(0, 9)],
    }
    assert [len(s) for s in sides.values()] == [11, 9, 9, 11, 9, 9]
    # Interior (not on a side): 251 - (11 + 9 + 9 + 11 + 9 + 9 - 6) = 199
    ring = {t for s in sides.values() for t in s}
    assert len(ring) == 52 and AREA - len(ring) == 199
    print("shape: 17 rows, widths", WIDTHS, "- bijection onto 0..250 checked")
    print("corners at bits", bits, "- sides 11, 9, 9, 11, 9, 9; ring 52 tiles, interior 199")
    return sides


def check_tiling():
    """Every tile of a large region lies in exactly one translate of H0 (chunk_of asserts it), and
    each chunk's six neighbours are +-T_U, +-T_R, +-(T_U + T_R)."""
    count = {}
    for r in range(-40, 60):
        for q in range(-60, 60):
            a, b, _ = chunk_of(q, r)
            count[(a, b)] = count.get((a, b), 0) + 1
    full = [n for n in count.values() if n == AREA]
    assert len(full) > 10
    touching = set()
    for r in range(ROWS):
        for q in range(lo(r), hi(r) + 1):
            for n in neighbours(q, r):
                a, b, _ = chunk_of(*n)
                if (a, b) != (0, 0):
                    touching.add((a, b))
    assert touching == {(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)}, touching
    print("tiling: lattice T_U = (-9, 17), T_R = (19, -8); six neighbours checked")


def window_cells(ox, oy):
    return [(ox + i, oy + j) for j in range(16) for i in range(15)]


def check_window():
    """The 15 x 16 window (D-120, origin on an even global row): how many chunks it overlaps, and
    how many row segments (one piece each for a mask-and-shift assembly) it takes."""
    classes = set()
    worst_chunks, worst_pieces, at = 0, 0, None
    histogram = {}
    for oy in range(40, 120, 2):
        for ox in range(0, 70):
            a, b, i = chunk_of(*axial(ox, oy))
            classes.add((i, a % 2))
            chunks = set()
            pieces = 0
            for j in range(16):
                previous = None
                for k in range(15):
                    c = chunk_of(*axial(ox + k, oy + j))[:2]
                    chunks.add(c)
                    if c != previous:
                        pieces += 1
                        previous = c
            histogram[len(chunks)] = histogram.get(len(chunks), 0) + 1
            if len(chunks) > worst_chunks:
                worst_chunks, at = len(chunks), (ox, oy)
            worst_pieces = max(worst_pieces, pieces)
    # The origin's global row is even, so its local row fixes the anchor's parity: 251 classes
    assert len(classes) == AREA, len(classes)
    print(f"window: at most {worst_chunks} chunks (first at origin {at}); histogram {histogram}")
    print(f"window: at most {worst_pieces} row segments per layer (rectangles: 4 pieces)")
    # The hand-derived instance of the note: origin (6, 2) relative to H0 anchored at (0, 0)
    hand = {chunk_of(*axial(x, y))[:2] for x, y in window_cells(6, 2)}
    assert len(hand) == 6, hand
    return worst_chunks, worst_pieces


def check_sight():
    """How many chunks a sight of radius 6 touches at most (ADR-0006 §5)."""
    worst = 0
    for r in range(ROWS):
        for q in range(lo(r), hi(r) + 1):
            touched = set()
            for dq in range(-6, 7):
                for dr in range(-6, 7):
                    if max(abs(dq), abs(dr), abs(dq + dr)) <= 6:
                        touched.add(chunk_of(q + dq, r + dr)[:2])
            worst = max(worst, len(touched))
    print(f"sight radius 6: touches at most {worst} chunks")
    return worst


def check_linear_layouts():
    """No layout `bit = s r + f(q, r)` with f affine (axial q, or q + r) fits the hexagon in 251 bits
    without collisions: the uniform neighbour shifts of the library need one."""
    best = None
    for name, f in (("q", lambda q, r: q), ("q + r", lambda q, r: q + r)):
        for s in range(11, 40):
            bits = [s * r + f(q, r) for r in range(ROWS) for q in range(lo(r), hi(r) + 1)]
            if len(set(bits)) == AREA:
                span = max(bits) - min(bits) + 1
                if best is None or span < best[0]:
                    best = (span, name, s)
    assert best[0] > 251, best
    print(f"linear layouts: the smallest span is {best[0]} bits ({best[1]}, stride {best[2]})")


def check_shift_steps():
    """Rows of one chunk that move into the window by the same shift can share a piece: the shift
    changes between rows r and r + 1 by 15 - width(r) + L(r + 1) - L(r), L the offset left end."""
    left = [offset(lo(r), r)[0] for r in range(ROWS)]
    steps = [15 - WIDTHS[r] + left[r + 1] - left[r] for r in range(ROWS - 1)]
    print("shift step between consecutive rows (0 = shared piece):", steps)


def main():
    check_shape()
    check_tiling()
    check_window()
    check_sight()
    check_linear_layouts()
    check_shift_steps()


if __name__ == "__main__":
    main()
