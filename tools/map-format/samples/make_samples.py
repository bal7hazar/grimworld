#!/usr/bin/env python3
"""Writes the spike's sample exports (ENG-08): the test region's zone drawn as an authored 3 × 2
zone (`contracts/seed/test-region.json`'s chunk set, masks, entry and gates), a town and a set
piece, and the content manifest that names their records. Deterministic: run it again, the same
files. The samples are what an editor writes; they are committed, this script is how they were
drawn.

    python3 samples/make_samples.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "map-format"))
import records as R  # noqa: E402

# The editor's plane: the fitted map's global (0, 0) at (-20, -14), an even row (D-216).
OX, OY = -20, -14


def ed(g):
    """A global tile on the editor's plane."""
    return [g[0] + OX, g[1] + OY]


def chunk_tiles(c, mask=R.BOARD):
    cy, cx = divmod(c, 15)
    return {(15 * cx + t % 15, 15 * cy + t // 15) for t in range(225) if R.has(mask, t)}


def spans(cells):
    """`{(x, y): (terrain, ground, outline)}` on the editor's plane -> format 2's row spans."""
    rows = []
    for y in sorted({y for _, y in cells}):
        xs = sorted(x for x, yy in cells if yy == y)
        t = g = o = ""
        for x in range(xs[0], xs[-1] + 1):
            cell = cells.get((x, y))
            if cell is None:
                t, g, o = t + " ", g + " ", o + " "
            else:
                t, g, o = t + cell[0], g + cell[1], o + cell[2]
        rows.append({"y": y, "x": xs[0], "terrain": t, "ground": g, "outline": o})
    return rows


def zone():
    # The seed's outline: chunks 0, 1, 2, 15, 16; chunk 2 columns 0-11; chunk 16 rows 0-9 and
    # columns 0-9 of rows 10-14.
    mask2 = sum(((1 << 12) - 1) << (15 * r) for r in range(15))
    mask16 = sum(((1 << 15) - 1) << (15 * r) for r in range(10)) + \
        sum(((1 << 10) - 1) << (15 * r) for r in range(10, 15))
    inside = chunk_tiles(0) | chunk_tiles(1) | chunk_tiles(2, mask2) | chunk_tiles(15) | \
        chunk_tiles(16, mask16)
    entry = (0, 7)  # chunk 0, tile 105
    floor_gate = (20, 22)  # chunk 16, tile 110 (row 7, column 5)
    wall, water = set(), set()
    for g in inside:
        if g != entry and any(n not in inside for n in R.neighbours(*g)):
            wall.add(g)
    for g in inside:  # a pond in chunk 1
        if (g[0] - 22) ** 2 + 2 * (g[1] - 7) ** 2 <= 6:
            water.add(g)
    for y in range(16, 26):  # a stream in chunk 15, forded below row 26
        water.add((8, y))
    rocks = {(5, 3), (12, 11), (27, 4), (33, 9), (4, 20), (17, 18)}
    cells = {}
    for g in inside | {(x, y) for x in range(45) for y in range(30)
                       if (x, y) not in inside and any(n in inside for n in R.neighbours(x, y))}:
        if g not in inside:
            cells[tuple(ed(g))] = ("#", "g", "0")
        elif g in water:
            cells[tuple(ed(g))] = ("#", "w", "1")
        elif g in wall or g in rocks:
            cells[tuple(ed(g))] = ("#", "e", "1")
        else:
            cells[tuple(ed(g))] = (".", "g", "1")
    hut = [(25, 12), (26, 12), (25, 13)]
    return {
        "format": "grimworld-export", "version": 1, "editor": "spike", "kind": "zone",
        "name": "Meadow Edge", "location": "meadow_edge", "region": "test_region",
        "biome": "meadow", "level_min": 1, "level_max": 3, "rank": 0, "spawn_table": "meadow",
        "origin": {"x": OX, "y": OY}, "size": {"width": 3, "height": 2}, "rows": spans(cells),
        "entry": dict(zip("xy", ed(entry))),
        "quotas": [{"kind": "collector", "param": "camp", "count": 1},
                   {"kind": "vein", "param": None, "count": 1},
                   {"kind": "heart", "param": "raiders", "count": 1}],
        "candidates": [
            {"quota": 0, **dict(zip("xy", ed((21, 3))))},
            {"quota": 0, **dict(zip("xy", ed((18, 20))))},
            {"quota": 1, **dict(zip("xy", ed((36, 5))))},
            {"quota": 1, **dict(zip("xy", ed((3, 25))))},
            {"quota": 2, **dict(zip("xy", ed((38, 10))))},
            {"quota": 2, **dict(zip("xy", ed((24, 19))))}],
        "spawns": [{"template": "raiders", **dict(zip("xy", ed((19, 10))))},
                   {"template": "cubs", **dict(zip("xy", ed((33, 3))))},
                   {"template": "cubs", **dict(zip("xy", ed((12, 24))))},
                   {"template": "raiders", **dict(zip("xy", ed((27, 21))))}],
        "features": [{"feature": "landmark", "param": "old_oak", **dict(zip("xy", ed((9, 9))))},
                     {"feature": "chest", "param": None, **dict(zip("xy", ed((40, 12))))},
                     {"feature": "lever", "param": None, **dict(zip("xy", ed((16, 26))))}],
        "gates": [
            {"gate": "to_town", "to": "test_town", "kind": "hub", "rank": 0, "quest": 0,
             "entry_chunk": 0, "entry_tile": 0, **dict(zip("xy", ed(entry)))},
            {"gate": "to_floor", "to": "floor_1", "kind": "link", "rank": 0, "quest": 0,
             "entry_chunk": 112, "entry_tile": 112, **dict(zip("xy", ed(floor_gate)))}],
        "npcs": [{"kind": "sheep", **dict(zip("xy", ed((6, 12)))), "facing": 3}],
        "buildings": [{"kind": "hut", "footprint": [ed(h) for h in hut], "anchor": ed(hut[0]),
                       "door": ed(hut[0]), "depth": 1, "mirror": False}],
        "props": [{"kind": "tree", **dict(zip("xy", ed((10, 4)))), "variant": 2},
                  {"kind": "bush", **dict(zip("xy", ed((11, 4)))), "variant": 0, "flip": True}],
        "bridges": [{"kind": "stone_bridge", "deck": [ed((8, 20))],
                     "ends": [ed((7, 20)), ed((9, 20))]}],
    }


def town():
    cells = {}
    for y in range(8):
        for x in range(12):
            edge = x in (0, 11) or y in (0, 7)
            cells[(x + 100, y + 40)] = ("#" if edge else ".", "e" if edge else "g", "1")
    rows = [{k: v for k, v in r.items() if k != "outline"} for r in spans(cells)]
    return {"format": "grimworld-export", "version": 1, "editor": "spike", "kind": "town",
            "name": "Test Town", "location": "test_town", "region": "test_region",
            "origin": {"x": 100, "y": 40}, "size": {"width": 1, "height": 1}, "rows": rows,
            "npcs": [{"kind": "pawn", "x": 104, "y": 43, "facing": 0}],
            "buildings": [{"kind": "forge", "footprint": [[106, 44], [107, 44], [106, 45]],
                           "anchor": [106, 44], "door": [106, 44], "depth": 1}],
            "props": [{"kind": "rock", "x": 102, "y": 42, "variant": 1}]}


def set_piece():
    cells = {}
    for y in range(15):
        for x in range(15):
            wall = x in (0, 14) or y in (0, 14) or (x in (5, 9) and 4 <= y <= 10 and y != 7)
            cells[(x, y)] = ("#" if wall else ".", "e", "1")
    rows = [{k: v for k, v in r.items() if k != "outline"} for r in spans(cells)]
    return {"format": "grimworld-export", "version": 1, "editor": "spike", "kind": "set_piece",
            "name": "boss_arena", "origin": {"x": 0, "y": 0}, "size": {"width": 1, "height": 1},
            "rows": rows, "spawns": [{"template": "raiders", "x": 7, "y": 7}],
            "features": [{"feature": "chest", "param": None, "x": 2, "y": 2},
                         {"feature": "lever", "param": None, "x": 12, "y": 12}]}


MANIFEST = {
    "$comment": "A content manifest: the registry ids of the names an export uses (OPS-01 writes it).",
    "regions": {"test_region": 1},
    "locations": {"test_town": 1, "meadow_edge": 2, "floor_1": 3},
    "gates": {"to_town": 2, "to_floor": 3},
    "packs": {"raiders": 1, "cubs": 2},
    "pack_bounds": {"raiders": [2, 5], "cubs": [1, 3]},
    "collectors": {"camp": 1}, "landmarks": {"old_oak": 1}, "skills": {},
    "spawn_tables": {"meadow": 1}, "set_pieces": {"boss_arena": 1},
}


def write(name, value):
    with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
        json.dump(value, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    write("zone.json", zone())
    write("town.json", town())
    write("set_piece.json", set_piece())
    write("manifest.json", MANIFEST)
