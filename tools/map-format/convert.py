#!/usr/bin/env python3
"""The converter (ENG-08 deliverable 5, promoted from SPK-16 by ENG-09, D-215 ruling 9): an editor's
export (`grimworld-export`, version 1, `schema.json`) to the on-chain records of its map, in the
order of their writes, and to the seed's rows. Python 3, the standard library only.

It refuses exactly what the Registry's checks refuse (`records.py`, the same codes as
`RegistryAssert`'s and `ZoneAssert`'s in `contracts/persistent/src/systems/registry.cairo`), and
checks itself what no record holds alone, the content pipeline's rules: every walkable tile of the
zone reachable from its entry, the records re-assembled across their seams equal to the painted
map, each bridge's deck connected. Only the hexes inside the fitted rectangle (`size` chunks from
the origin, D-216) are exported; a painted hex outside it is refused (`export: hex outside the
size`).

    python3 tools/map-format/convert.py samples/zone.json --manifest samples/manifest.json \\
        --out samples/zone.records.json [--golden samples/zone.golden.json] [--seed out.json]

Exit 0 and the records written; exit 1 and one line `refused: <code>: <detail>` otherwise.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import records as R  # noqa: E402
from schema_check import validate  # noqa: E402

FORMAT = "grimworld-export"
VERSION = 1
RECORDS_FORMAT = "grimworld-records"
# What a kind needs beyond the schema's required keys (JSON Schema's `if`/`then`, kept here).
ZONE_FIELDS = ("location", "region", "biome", "level_min", "level_max", "entry")
HUB_FIELDS = ("location", "region")


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def kinds():
    return load_json(os.path.join(HERE, "kinds.json"))


# The width of the field each manifest table's ids are packed into: 16 bits for all (`records.py`:
# location region, spawn table, gate source, destination and id, spawn template, quota param, object
# param; a set piece's id is a u16 for the game: `Location.set_pieces` is `Lanes16`).
ID_BITS = 16
GATE_QUEST_BITS = 32  # `Gate.quest: u32`, authored in the export, not named in the manifest


def resolve(manifest, table, name, what):
    ids = manifest.get(table, {})
    if name not in ids:
        raise R.Refused("export: unknown name", f"{what} {name!r} not in the manifest's {table}")
    return R.assert_id(f"{what} {name!r}", ids[name], ID_BITS)


class Plane:
    """The painted hexes moved to the map's global coordinates: `(x, y)` = the editor's `(x, y)`
    less the origin, the origin's row even so that every row keeps its parity (D-216)."""

    def __init__(self, export):
        origin = export["origin"]
        if origin["y"] % 2:
            raise R.Refused("export: origin row odd", "the origin's y must be even (D-216)")
        self.ox, self.oy = origin["x"], origin["y"]
        self.width, self.height = export["size"]["width"], export["size"]["height"]
        self.cells = {}
        for span in export["rows"]:
            for layer in ("ground", "outline"):
                if layer in span and len(span[layer]) != len(span["terrain"]):
                    raise R.Refused("export: row lengths differ",
                                    f"row y={span['y']}: {layer} {len(span[layer])}, "
                                    f"terrain {len(span['terrain'])}")
            for i, t in enumerate(span["terrain"]):
                if t == " ":
                    continue
                g = self.glob(span["x"] + i, span["y"])
                outline = span.get("outline")
                inside = outline is None or outline[i] == "1"
                self.cells[g] = {"walk": t == ".", "inside": inside}
        for (x, y) in self.cells:
            if not (0 <= x < 15 * self.width and 0 <= y < 15 * self.height):
                raise R.Refused("export: hex outside the size", f"({x}, {y})")

    def glob(self, x, y):
        return (x - self.ox, y - self.oy)

    @staticmethod
    def chunk_tile(g):
        x, y = g
        return (15 * (y // 15) + x // 15, 15 * (y % 15) + x % 15)

    @staticmethod
    def of(chunk, tile):
        cy, cx = divmod(chunk, 15)
        row, col = divmod(tile, 15)
        return (15 * cx + col, 15 * cy + row)


def hexes(export, items, plane):
    return [plane.glob(h[0], h[1]) for h in items]


def build_zone(export, manifest):
    """The records of an authored zone, as a dict `records.check_zone` reads, and the walkable plane
    the pipeline's rules read."""
    table = kinds()
    sizes = R.assert_sizes(manifest.get("location_sizes", {}))
    plane = Plane(export)
    blocked, footprints = set(), []
    # [Compute] What the client-only objects make unwalkable: a building's footprint but its door,
    # a blocking prop's hex (track game, 2026-10-05; CLI-09e §4)
    for b in export.get("buildings", []):
        if b["kind"] not in table["buildings"]:
            raise R.Refused("export: unknown kind", f"building {b['kind']!r}")
        foot = {plane.glob(*h) for h in b["footprint"]}
        door = plane.glob(*b["door"])
        if door not in foot or all(n in foot for n in R.neighbours(*door)):
            raise R.Refused("export: door not on the border", f"building {b['kind']!r}")
        footprints.append((b["kind"], foot, door))
        blocked |= foot - {door}
    for p in export.get("props", []):
        kind = table["props"].get(p["kind"])
        if kind is None:
            raise R.Refused("export: unknown kind", f"prop {p['kind']!r}")
        if kind["blocks"]:
            blocked.add(plane.glob(p["x"], p["y"]))
    for n in export.get("npcs", []):
        if n["kind"] not in table["npcs"]:
            raise R.Refused("export: unknown kind", f"npc {n['kind']!r}")
    zone = {g for g, c in plane.cells.items() if c["inside"]}
    # [Compute] Each building's footprint, authored per building (the kind table's is the editor's
    # default): in the zone and in one piece, its door walkable (track CV, 2026-10-07)
    for kind, foot, door in footprints:
        if foot - zone:
            raise R.Refused("export: footprint outside the set", f"building {kind!r}")
        if connected(foot, door) != foot:
            raise R.Refused("export: footprint not connected", f"building {kind!r}")
        if not plane.cells[door]["walk"]:
            raise R.Refused("export: door not walkable", f"building {kind!r}")
    # [Compute] The bridges' decks: walkable ground over water (D-227, ADR-0008 rule 1), refused
    # outside the zone or on a blocked hex, then written walkable before the walls
    decks = set()
    for b in export.get("bridges", []):
        if b["kind"] not in table["bridges"]:
            raise R.Refused("export: unknown kind", f"bridge {b['kind']!r}")
        decks |= {plane.glob(*h) for h in b["deck"]}
    if decks - zone:
        raise R.Refused("export: deck outside the zone", f"{sorted(decks - zone)[:3]}")
    if decks & blocked:
        raise R.Refused("export: deck blocked", f"{sorted(decks & blocked)[:3]}")
    walk = {g for g in zone if plane.cells[g]["walk"] and g not in blocked} | decks
    # [Compute] The chunk set and the border chunks' masks
    chunk_set, masks, tiles_of = 0, {}, {}
    for g in zone:
        c, t = plane.chunk_tile(g)
        chunk_set |= 1 << c
        tiles_of.setdefault(c, 0)
        tiles_of[c] |= 1 << t
    for c, m in tiles_of.items():
        if m != R.BOARD:
            masks[c] = m
    chunks = {}
    for c in tiles_of:
        walls = R.BOARD
        for t in range(225):
            if plane.of(c, t) in walk:
                walls &= ~(1 << t)
        chunks[c] = {"walls": walls, "spawns": [], "objects": [], "tiles": [0] * 6, "bridges": 0,
                     "gates": [0, 0]}

    def chunk_of(x, y, what):
        g = plane.glob(x, y)
        c, t = plane.chunk_tile(g)
        if c not in chunks:
            raise R.Refused("zone: chunk not in the set", f"{what} at ({x}, {y})")
        return c, t

    for s in export.get("spawns", []):
        c, t = chunk_of(s["x"], s["y"], "spawn point")
        chunks[c]["spawns"].append(
            {"tile": t, "template": resolve(manifest, "packs", s["template"], "pack")})
    for f in export.get("features", []):
        c, t = chunk_of(f["x"], f["y"], "feature")
        param = 0
        if f["feature"] == "landmark":
            param = resolve(manifest, "landmarks", f["param"], "landmark")
        elif f["feature"] == "trap":
            param = resolve(manifest, "skills", f["param"], "trap skill")
        chunks[c]["objects"].append({"tile": t, "kind": R.OBJECTS[f["feature"]], "state": 0,
                                     "param": param})
    quotas, hearts = [], {}
    for i, q in enumerate(export.get("quotas", [])):
        kind = R.QUOTA_KINDS[q["kind"]]
        param = 0
        if q["kind"] == "heart":
            param = resolve(manifest, "packs", q["param"], "pack")
            template = manifest.get("pack_bounds", {}).get(q["param"])
            hearts[i] = tuple(template) if template else None
        elif q["kind"] == "collector":
            param = resolve(manifest, "collectors", q["param"], "collector")
        elif q["kind"] == "landmark":
            param = resolve(manifest, "landmarks", q["param"], "landmark")
        elif q["kind"] == "exit":
            param = resolve(manifest, "gates", q["param"], "gate")
        quotas.append((kind, param, q["count"]))
    candidates = [0] * len(quotas)
    for cand in export.get("candidates", []):
        i = cand["quota"]
        if not 0 <= i < len(quotas):
            raise R.Refused("export: candidate of no quota", f"quota {i}")
        c, t = chunk_of(cand["x"], cand["y"], "candidate")
        if R.has(candidates[i], c):
            raise R.Refused("export: two candidates in a chunk", f"quota {i}, chunk {c}")
        candidates[i] |= 1 << c
        chunks[c]["tiles"][i] = t
    gates, destinations = {}, {}
    for gt in export.get("gates", []):
        c, t = chunk_of(gt["x"], gt["y"], "gate")
        gid = resolve(manifest, "gates", gt["gate"], "gate")
        # E-5: a gate to another location anchors on the outline (a zone hex with a neighbour
        # outside the zone); a dungeon's entrance (its destination a dungeon) may stand inside
        g = plane.glob(gt["x"], gt["y"])
        destination = manifest.get("location_kinds", {}).get(gt["to"])
        if destination != "dungeon" and all(n in zone for n in R.neighbours(*g)):
            raise R.Refused("export: gate not on the outline", f"gate {gt['gate']!r}")
        slot = chunks[c]["gates"]
        if 0 not in slot:
            raise R.Refused("export: three gates in a chunk", f"chunk {c}")
        slot[slot.index(0)] = gid
        gates[gid] = {"source": resolve(manifest, "locations", export["location"], "location"),
                      "destination": resolve(manifest, "locations", gt["to"], "location"),
                      "anchor_chunk": c, "anchor_tile": t, "entry_chunk": gt["entry_chunk"],
                      "entry_tile": gt["entry_tile"], "kind": R.GATE_KINDS[gt["kind"]],
                      "rank": gt.get("rank", 0),
                      "quest": R.assert_id(f"gate {gt['gate']!r} quest", gt.get("quest", 0),
                                           GATE_QUEST_BITS)}
        # R-41: the destination's rectangle, when the manifest gives it (`location_sizes`) and
        # the destination has a map (a hub has none)
        size = sizes.get(gt["to"])
        if size is not None and destination not in ("town", "outpost"):
            destinations[gates[gid]["destination"]] = size
    bridges = {}
    for b in export.get("bridges", []):
        deck = [plane.chunk_tile(plane.glob(*h)) for h in b["deck"]]
        ends = [plane.chunk_tile(plane.glob(*h)) for h in b["ends"]]
        c = deck[0][0]
        if any(d[0] != c for d in deck + ends):
            raise R.Refused("export: bridge across chunks", "format 1: a bridge lies in one chunk")
        if c not in chunks:
            raise R.Refused("zone: chunk not in the set", "a bridge")
        deck_bits = sum(1 << t for _, t in set(deck))
        bridges.setdefault(c, []).append({"deck": deck_bits, "ends": (ends[0][1], ends[1][1])})
        chunks[c]["bridges"] += 1
        decks = {plane.glob(*h) for h in b["deck"]}
        if not connected(decks, next(iter(decks))) == decks:
            raise R.Refused("pipeline: deck not connected")
    entry_c, entry_t = plane.chunk_tile(plane.glob(export["entry"]["x"], export["entry"]["y"]))
    location = {"kind": R.LOCATION_KINDS["zone"],
                "region": resolve(manifest, "regions", export["region"], "region"),
                "biome": R.BIOMES[export["biome"]], "level_min": export["level_min"],
                "level_max": export["level_max"], "rank": export.get("rank", 0),
                "width": plane.width, "height": plane.height, "target": 0, "floors": 0,
                "next_floor": 0,
                "spawn_table": resolve(manifest, "spawn_tables", export["spawn_table"], "spawn table")
                if export.get("spawn_table") else 0,
                "sealed": False, "entry_chunk": entry_c, "entry_tile": entry_t, "map": R.AUTHORED}
    return {"id": resolve(manifest, "locations", export["location"], "location"),
            "location": location, "chunk_set": chunk_set, "masks": masks, "chunks": chunks,
            "quotas": quotas, "candidates": candidates, "hearts": hearts, "gates": gates,
            "destinations": destinations, "bridges": bridges, "walk": walk, "zone": zone, "plane": plane}


def connected(tiles, start):
    seen, todo = {start}, [start]
    while todo:
        for n in R.neighbours(*todo.pop()):
            if n in tiles and n not in seen:
                seen.add(n)
                todo.append(n)
    return seen


def pipeline(z):
    """The content pipeline's rules (no record holds them alone)."""
    plane = z["plane"]
    # P-2: the records, re-assembled across their seams, give the painted walkable plane back
    assembled = set()
    for c, rec in z["chunks"].items():
        for t in range(225):
            if not R.has(rec["walls"], t):
                assembled.add(plane.of(c, t))
    if assembled != z["walk"]:
        diff = sorted(assembled ^ z["walk"])[:3]
        raise R.Refused("pipeline: seam", f"records and map differ at {diff}")
    # P-1: every walkable tile reachable from the entry
    loc = z["location"]
    start = plane.of(loc["entry_chunk"], loc["entry_tile"])
    if start in assembled:
        reach = connected(assembled, start)
        if reach != assembled:
            raise R.Refused("pipeline: unreachable tile", f"{sorted(assembled - reach)[:3]}")


def zone_writes(z):
    """The records of a zone in the order the converter writes them (README, *Registration*)."""
    lid = z["id"]
    out = [(R.LOCATION, lid, R.pack_location(z["location"]), "LOCATION, the marker set"),
           (R.OUTLINE, lid * 256 + R.CHUNK_SET, R.pack_outline(z["chunk_set"]), "the chunk set")]
    cands = z["candidates"] + [0] * (6 - len(z["candidates"]))
    for k in range(2):
        if any(cands[3 * k: 3 * k + 3]):
            out.append((R.CANDIDATES, lid * 2 + k, R.pack_candidates(cands[3 * k: 3 * k + 3]),
                        f"quotas {3 * k}-{3 * k + 2}'s candidates"))
    if z["quotas"]:
        out.append((R.QUOTAS, lid, R.pack_quotas(z["quotas"]), "the quotas"))
    for c in sorted(z["masks"]):
        out.append((R.OUTLINE, lid * 256 + c, R.pack_outline(z["masks"][c]), f"chunk {c}'s mask"))
    for c in sorted(z["chunks"]):
        out.append((R.ZONE_CHUNK, lid * 256 + c, R.pack_zone_chunk(z["chunks"][c]), f"chunk {c}"))
        for k, b in enumerate(z["bridges"].get(c, [])):
            out.append((R.BRIDGE, lid * 4096 + c * 16 + k, R.pack_bridge(b), f"chunk {c} bridge {k}"))
    for gid in sorted(z["gates"]):
        out.append((R.GATE, gid, R.pack_gate(z["gates"][gid]), f"gate {gid}"))
    return out


def set_piece_writes(export, manifest):
    """A set piece (one chunk, ADR-0006 *Set pieces*): one `SET_PIECE`, `SetPieceAssert`'s rules."""
    plane = Plane(export)
    if (plane.width, plane.height) != (1, 1):
        raise R.Refused("export: set piece size", "a set piece is one chunk")
    walls = R.BOARD
    for g, c in plane.cells.items():
        if c["walk"]:
            walls &= ~(1 << Plane.chunk_tile(g)[1])
    corners = 1 | 1 << 14 | 1 << 210 | 1 << 224
    if walls & corners != corners:
        raise R.Refused("set piece: corner not wall")

    def interior(t):
        row, col = divmod(t, 15)
        if not (0 < row < 14 and 0 < col < 14) or R.has(walls, t):
            raise R.Refused("set piece: tile not floor", f"tile {t}")
        return t

    spawns = [{"tile": interior(Plane.chunk_tile(plane.glob(s["x"], s["y"]))[1]),
               "template": resolve(manifest, "packs", s["template"], "pack")}
              for s in export.get("spawns", [])]
    objects = [{"tile": interior(Plane.chunk_tile(plane.glob(f["x"], f["y"]))[1]),
                "kind": R.OBJECTS[f["feature"]], "param": 0} for f in export.get("features", [])]
    if len(spawns) > 2 or len(objects) > 3:
        raise R.Refused("set piece: over its caps")
    pid = resolve(manifest, "set_pieces", export["name"], "set piece")
    return [(R.SET_PIECE, pid, R.pack_set_piece({"walls": walls, "spawns": spawns,
                                                  "objects": objects}), "the set piece")]


def town_writes(export, manifest):
    """A town or an outpost: client-only (D-03, D-202). Only `LOCATION` (no map: 0 × 0, entry 0)."""
    lid = resolve(manifest, "locations", export["location"], "location")
    loc = {"kind": R.LOCATION_KINDS[export["kind"]],
           "region": resolve(manifest, "regions", export["region"], "region"), "biome": 0,
           "level_min": 0, "level_max": 0, "rank": 0, "width": 0, "height": 0, "target": 0,
           "floors": 0, "next_floor": 0, "spawn_table": 0, "sealed": False, "entry_chunk": 0,
           "entry_tile": 0}
    return [(R.LOCATION, lid, R.pack_location(loc), "LOCATION (a hub: no map)")]


def convert(export, manifest):
    """`(writes, zone)`: the records in their order, and the zone's dict (None but for a zone)."""
    # The format and its version first, so that a newer file is told as such, not as a schema error
    if not isinstance(export, dict) or export.get("format") != FORMAT:
        raise R.Refused("export: format", "not a grimworld-export file")
    if export.get("version") != VERSION:
        raise R.Refused("export: version", f"{export.get('version')} (this converter reads {VERSION})")
    validate(export, load_json(os.path.join(HERE, "schema.json")))
    needed = {"zone": ZONE_FIELDS, "town": HUB_FIELDS, "outpost": HUB_FIELDS}.get(export["kind"], ())
    missing = [key for key in needed if key not in export]
    if missing:
        raise R.Refused("export: field missing", f"a {export['kind']} needs {', '.join(missing)}")
    if export["kind"] in ("town", "outpost"):
        return town_writes(export, manifest), None
    if export["kind"] == "set_piece":
        return set_piece_writes(export, manifest), None
    z = build_zone(export, manifest)
    R.check_zone(z)
    pipeline(z)
    return zone_writes(z), z


def limbs32(felt):
    return [(felt >> (32 * i)) & 0xffffffff for i in range(8)]


def golden(z, writes):
    """A small file snforge's `read_json` reads (flat arrays of numbers, keys sorted): each chunk's
    fields and its two parts as 32-bit limbs, for the Cairo test that decodes them."""
    fields, parts = [], []
    for kind, rid, felts, _ in writes:
        if kind != R.ZONE_CHUNK:
            continue
        c = rid % 256
        rec = R.unpack_zone_chunk(felts)
        sp = rec["spawns"] + [{"tile": 0, "template": 0}] * (2 - len(rec["spawns"]))
        ob = rec["objects"] + [{"tile": 0, "kind": 0, "state": 0, "param": 0}] * (3 - len(rec["objects"]))
        fields += [c] + limbs32(rec["walls"])
        fields += [v for s in sp for v in (s["tile"], s["template"])]
        fields += [v for o in ob for v in (o["tile"], o["kind"], o["param"])]
        fields += rec["tiles"] + [rec["bridges"]] + rec["gates"]
        parts += [c] + limbs32(felts[0]) + limbs32(felts[1])
    others = []
    for kind, rid, felts, _ in writes:
        if kind in (R.LOCATION, R.OUTLINE, R.CANDIDATES, R.QUOTAS, R.BRIDGE, R.GATE):
            for f in felts:
                others += [kind, rid] + limbs32(f)
    return {"chunk_fields": fields, "chunk_parts": parts, "records": others,
            "chunk_count": len(parts) // 17}


def seed_rows(z):
    """The zone in the seed's shape (contracts/seed/README.md): flat rows by kind, plus the
    proposed kinds' rows; snforge's `read_json` rules (no empty array)."""
    loc = z["location"]
    rows = {"location": [z["id"], loc["kind"], loc["region"], loc["biome"], loc["level_min"],
                         loc["level_max"], loc["rank"], loc["width"], loc["height"], loc["target"],
                         loc["floors"], loc["next_floor"], loc["spawn_table"], 0,
                         loc["entry_chunk"], loc["entry_tile"], loc["map"]]}
    outline = []
    for c, bits in [(R.CHUNK_SET, z["chunk_set"])] + sorted(z["masks"].items()):
        outline += [z["id"], c] + [(bits >> (15 * r)) & 0x7fff for r in range(15)]
    rows["outlines"] = outline
    chunk_rows = []
    for c, rec in sorted(z["chunks"].items()):
        chunk_rows += [z["id"], c] + [(rec["walls"] >> (15 * r)) & 0x7fff for r in range(15)]
    rows["zone_chunks"] = chunk_rows
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("export")
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--golden")
    ap.add_argument("--seed")
    args = ap.parse_args(argv)
    try:
        writes, z = convert(load_json(args.export), load_json(args.manifest))
    except R.Refused as refusal:
        print(f"refused: {refusal}")
        return 1
    except (KeyError, IndexError, TypeError, ValueError) as error:
        # A file no check above names: still a refusal line, never a traceback (review t-0084)
        print(f"refused: export: malformed: {type(error).__name__}: {error}")
        return 1
    out = {"format": RECORDS_FORMAT, "version": VERSION, "source": os.path.basename(args.export),
           "writes": [{"order": i, "kind": R.KIND_NAMES[k], "kind_id": k, "id": rid,
                       "parts": [hex(f) for f in felts], "what": what}
                      for i, (k, rid, felts, what) in enumerate(writes)]}
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    if args.golden and z is not None:
        with open(args.golden, "w", encoding="utf-8") as f:
            json.dump(golden(z, writes), f, sort_keys=True)
            f.write("\n")
    if args.seed and z is not None:
        with open(args.seed, "w", encoding="utf-8") as f:
            json.dump(seed_rows(z), f, indent=1)
            f.write("\n")
    print(f"{len(writes)} records -> {os.path.basename(args.out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
