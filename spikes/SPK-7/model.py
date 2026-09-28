#!/usr/bin/env python3
"""SPK-7: a plain Python model of the map rules the Cairo package implements, tile by tile.

Used by gen_tables.py (constants and line-of-sight tables), boards.py (winding boards and the
worst-case fixture) and tune.py (biome parameters). Nothing here is fast; everything is obvious.

Conventions (origami_hexmap, docs/needs/hexmap.md point 3): pointy-top, odd-r, row-major bit
`i = y * W + x`, `+1` is West, `+W` is North. A row is "odd" by its GLOBAL parity: in a window
(origin on an even global row) the local and global parities agree; in a chunk starting on an odd
global row they are swapped (the parity flag, point 2).
"""
from fractions import Fraction

W = 15  # chunk and window width
CHUNK_H = 15
WINDOW_H = 16


def neighbours(x, y, width, height, flip=False):
    """Neighbours (x, y) inside a width x height board; flip: local row 0 is a global odd row."""
    odd = (y % 2 == 1) != flip
    out = [(x - 1, y), (x + 1, y)]
    xs = (x, x + 1) if odd else (x - 1, x)
    for ny in (y - 1, y + 1):
        for nx in xs:
            out.append((nx, ny))
    return [(a, b) for a, b in out if 0 <= a < width and 0 <= b < height]


def bits_to_set(value, width, height):
    return {(i % width, i // width) for i in range(width * height) if value >> i & 1}


def set_to_bits(tiles, width):
    value = 0
    for x, y in tiles:
        value |= 1 << (y * width + x)
    return value


def bfs(free, start, width, height, flip=False):
    """Distances from start over the set `free` (start included implicitly)."""
    dist = {start: 0}
    queue = [start]
    for tile in queue:
        for n in neighbours(*tile, width, height, flip):
            if n in free and n not in dist:
                dist[n] = dist[tile] + 1
                queue.append(n)
    return dist


# --- window ---------------------------------------------------------------------------------------

def interior(width, height):
    return {(x, y) for x in range(1, width - 1) for y in range(1, height - 1)}


def window_origin(x, y):
    """ADR-0006 §4: adventurer on local column 7, local row 7 (odd global row) or 8 (even)."""
    return (x - 7, y - 7) if y % 2 == 1 else (x - 7, y - 8)


def shared_flood(terrain, occupied, start, goblins, limit):
    """Rule (a) of docs/needs/hexmap.md point 5 with the cap of D-127: one flood from the
    adventurer on the occupancy frozen at the start of the tick, goblins in ascending id order
    step to their free neighbour closest to the adventurer, lowest tile index on ties, fallback to
    the same layer, else hold. Returns (layers, distances, moves, final occupancy); a layer list
    holds the start as layer 0. `limit` None is unlimited. `terrain` has the ring as wall."""
    width, height = W, WINDOW_H
    free = terrain - occupied - {start}
    layers = [{start}]
    seen = {start}
    pending = set(goblins)
    dist = {}
    d = 0
    while layers[-1] and (limit is None or d < limit):
        d += 1
        around = set()
        for t in layers[-1]:
            around.update(neighbours(*t, width, height))
        nxt = {t for t in around if t in free and t not in seen}
        seen |= nxt
        layers.append(nxt)
        hits = pending & around
        for g in hits:
            dist[g] = d
        pending -= hits
        if not pending:
            break
    moves = []
    current = set(occupied)
    for g in goblins:
        dg = dist.get(g, 0)
        if dg <= 1:
            moves.append(None)
            continue
        near = set(neighbours(*g, width, height))
        choice = None
        for want in (dg - 1, dg):
            if want >= len(layers):
                continue
            cands = [t for t in near & layers[want] if t not in current]
            if cands:
                choice = min(cands, key=lambda t: t[1] * width + t[0])
                break
        moves.append(choice)
        if choice is not None:
            current.discard(g)
            current.add(choice)
    return layers, [dist.get(g, 0) for g in goblins], moves, current


# --- line of sight (design/04 Ranges, docs/needs/hexmap.md point 6, D-24) -----------------------

def axial(x, y):
    return x - (y >> 1), y


def offset(q, r):
    return q + (r >> 1), r


def hex_distance(a, b):
    (q1, r1), (q2, r2) = axial(*a), axial(*b)
    dq, dr = q2 - q1, r2 - r1
    return max(abs(dq), abs(dr), abs(dq + dr))


def between(a, b, width=W):
    """Tiles strictly between a and b on the game's integer line: N = hex distance samples, each
    rounded to the nearest hex centre (exact rationals), ties to the lower tile index."""
    n = hex_distance(a, b)
    (q1, r1), (q2, r2) = axial(*a), axial(*b)
    out = []
    for i in range(1, n):
        q = Fraction(q1 * (n - i) + q2 * i, n)
        r = Fraction(r1 * (n - i) + r2 * i, n)
        best = None
        for cq in (q.numerator // q.denominator, -((-q.numerator) // q.denominator)):
            for cr in (r.numerator // r.denominator, -((-r.numerator) // r.denominator)):
                dq, dr = q - cq, r - cr
                d2 = dq * dq + dr * dr + (dq + dr) * (dq + dr)
                x, y = offset(cq, cr)
                key = (d2, y * width + x)
                if best is None or key < best[0]:
                    best = (key, (x, y))
        out.append(best[1])
    return out


def line_of_sight(a, b, terrain):
    return all(t in terrain for t in between(a, b))
