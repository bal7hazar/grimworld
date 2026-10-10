"""The on-chain records of a map, packed exactly as the Cairo models pack them (ENG-01 §3.5;
`contracts/logic/src/models/{location,zone_chunk,bridge,candidates}.cairo`), and the Registry's
content checks of an authored zone's records (`ZoneAssert` in
`contracts/persistent/src/systems/registry.cairo` and the models' `...Assert`), with the same
refusal codes.

A record is a list of felts (Python ints); every part carries `LIVE` (bit 250), as `join` writes it.
Tiles are `15 row + column` in their chunk, chunks `15 cy + cx` in the location (ADR-0006 §4).
"""

LIVE = 1 << 250
BOARD = (1 << 225) - 1

# Kinds (`content.cairo`; 26-28 ENG-08's, built by ENG-09).
LOCATION, OUTLINE, GATE, QUOTAS, PACK, SET_PIECE = 2, 3, 4, 5, 7, 24
ZONE_CHUNK, BRIDGE, CANDIDATES = 26, 27, 28
KIND_NAMES = {LOCATION: "LOCATION", OUTLINE: "OUTLINE", GATE: "GATE", QUOTAS: "QUOTAS",
              PACK: "PACK", SET_PIECE: "SET_PIECE", ZONE_CHUNK: "ZONE_CHUNK", BRIDGE: "BRIDGE",
              CANDIDATES: "CANDIDATES"}
CHUNK_SET = 255

# `models::location::kind`, `biome`; `models::quotas::kind`; `models::chunk::object`.
LOCATION_KINDS = {"town": 1, "outpost": 2, "zone": 3, "dungeon": 4}
BIOMES = {"meadow": 1, "forest": 2, "cave": 3, "ruin": 4}
QUOTA_KINDS = {"exit": 1, "heart": 2, "vein": 3, "collector": 4, "landmark": 5, "setPiece": 6}
HEART, EXIT, VEIN_Q, COLLECTOR_Q, LANDMARK_Q, SET_PIECE_Q = 2, 1, 3, 4, 5, 6
OBJECTS = {"chest": 1, "vein": 2, "node": 3, "trap": 4, "collector": 5, "landmark": 6, "lever": 7,
           "exit": 8}
AUTHORED_OBJECTS = {1, 3, 4, 6, 7}
GATE_KINDS = {"hub": 1, "link": 2, "floor": 3, "rift": 4}
GENERATED, AUTHORED = 0, 1
MAX_DRAWS = 640


class Refused(Exception):
    """A record or an export refused, with the code the Cairo check panics with."""

    def __init__(self, code, detail=""):
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code = code
        self.detail = detail


def fits(value, bits, code):
    if not 0 <= value < (1 << bits):
        raise Refused(code, f"{value} does not fit {bits} bits")
    return value


def assert_id(what, value, bits):
    """A manifest id fits the field the record packs it into: neither negative nor `bits` wide or more
    (`pack_*` would shift it into its neighbour's bits, or write a negative felt)."""
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < (1 << bits):
        raise Refused("export: id does not fit", f"{what}: id {value!r} does not fit {bits} bits")
    return value


def has(bits, i):
    return (bits >> i) & 1 == 1


def count(bits):
    return bin(bits).count("1")


# --- packers ------------------------------------------------------------------------------------

def pack_location(f):
    """`LocationRecord::pack`, and the marker at 144-151 (ENG-08)."""
    low = (f["kind"] | f["region"] << 8 | f["biome"] << 24 | f["level_min"] << 32
           | f["level_max"] << 40 | f["rank"] << 48 | f["width"] << 56 | f["height"] << 64
           | f["target"] << 72 | f["floors"] << 80 | f["next_floor"] << 88 | f["spawn_table"] << 104
           | int(f["sealed"]) << 120)
    high = f["entry_chunk"] | f["entry_tile"] << 8 | f.get("map", GENERATED) << 16
    lanes = f.get("set_pieces", [0] * 15)
    p1 = sum(v << (16 * i) for i, v in enumerate(lanes[:8])) \
        | sum(v << (16 * i) for i, v in enumerate(lanes[8:])) << 128
    return [low | high << 128 | LIVE, p1 | LIVE]


def pack_outline(bits):
    return [fits(bits, 225, "outline: above bit 224") | LIVE]


def pack_gate(f):
    low = (f["source"] | f["destination"] << 16 | f["anchor_chunk"] << 32 | f["anchor_tile"] << 40
           | f["entry_chunk"] << 48 | f["entry_tile"] << 56 | f["kind"] << 64 | f["rank"] << 72
           | f["quest"] << 80)
    return [low | LIVE]


def pack_quotas(quotas):
    """Six `(kind, param, count)`, quota `i` at `32 i` (low limb) and `128 + 32 (i - 4)`."""
    quotas = list(quotas) + [(0, 0, 0)] * (6 - len(quotas))
    word = 0
    for i, (kind, param, n) in enumerate(quotas):
        bits = kind | param << 8 | n << 24
        word |= bits << (32 * i if i < 4 else 128 + 32 * (i - 4))
    return [word | LIVE]


def object_bits(o):
    return o["tile"] | o["kind"] << 8 | o.get("state", 0) << 12 | o["param"] << 16


def pack_zone_chunk(c):
    """`ZoneChunkRecord::pack` (src/zone_chunk.cairo)."""
    walls = fits(c["walls"], 225, "zone chunk: walls above 224")
    if len(c["spawns"]) > 2 or len(c["objects"]) > 3:
        raise Refused("zone chunk: over its caps", "more than the layout holds")
    spawns = c["spawns"] + [{"tile": 0, "template": 0}] * (2 - len(c["spawns"]))
    objects = c["objects"] + [{"tile": 0, "kind": 0, "param": 0}] * (3 - len(c["objects"]))
    low = (spawns[0]["tile"] | spawns[0]["template"] << 8 | spawns[1]["tile"] << 24
           | spawns[1]["template"] << 32 | object_bits(objects[0]) << 48
           | object_bits(objects[1]) << 80)
    high = object_bits(objects[2])
    for i, tile in enumerate(c["tiles"]):
        high |= tile << (32 + 8 * i)
    high |= fits(c["bridges"], 4, "zone chunk: bridges above 15") << 80
    high |= c["gates"][0] << 84 | c["gates"][1] << 100
    return [walls | LIVE, low | high << 128 | LIVE]


def unpack_zone_chunk(parts):
    walls = parts[0] - LIVE
    word = parts[1] - LIVE
    low, high = word & ((1 << 128) - 1), word >> 128

    def obj(bits):
        return {"tile": bits & 0xff, "kind": bits >> 8 & 0xf, "state": bits >> 12 & 0xf,
                "param": bits >> 16 & 0xffff}

    spawns = [{"tile": low & 0xff, "template": low >> 8 & 0xffff},
              {"tile": low >> 24 & 0xff, "template": low >> 32 & 0xffff}]
    objects = [obj(low >> 48 & 0xffffffff), obj(low >> 80 & 0xffffffff), obj(high & 0xffffffff)]
    return {"walls": walls,
            "spawns": [s for s in spawns if s["template"]],
            "objects": [o for o in objects if o["kind"]],
            "tiles": [high >> (32 + 8 * i) & 0xff for i in range(6)],
            "bridges": high >> 80 & 0xf, "gates": [high >> 84 & 0xffff, high >> 100 & 0xffff]}


def pack_bridge(b):
    deck = fits(b["deck"], 225, "bridge: deck above bit 224")
    a, e = b["ends"]
    return [deck | a << 225 | e << 233 | LIVE]


def pack_candidates(sets):
    sets = list(sets) + [0] * (3 - len(sets))
    return [fits(s, 225, "candidates: above bit 224") | LIVE for s in sets]


def pack_set_piece(p):
    """`SetPieceRecord::pack`: walls, then 2 packs and 3 objects."""
    spawns = p["spawns"] + [{"tile": 0, "template": 0}] * (2 - len(p["spawns"]))
    objects = p["objects"] + [{"tile": 0, "kind": 0, "param": 0}] * (3 - len(p["objects"]))
    low = (spawns[0]["tile"] | spawns[0]["template"] << 8 | spawns[1]["tile"] << 24
           | spawns[1]["template"] << 32 | object_bits(objects[0]) << 48
           | object_bits(objects[1]) << 80)
    return [fits(p["walls"], 225, "set piece: walls") | LIVE,
            low | object_bits(objects[2]) << 128 | LIVE]


# --- hexes --------------------------------------------------------------------------------------

def rectangle(width, height):
    row = (1 << width) - 1
    return sum(row << (15 * cy) for cy in range(height))


def neighbours(x, y):
    """Odd-r, `x` growing West as `hexx`'s `+1`: an even row's North and South neighbours are
    `x - 1` and `x`, an odd row's `x` and `x + 1` (`board.cairo`, `dilate`)."""
    d = 0 if y % 2 == 1 else -1
    return [(x - 1, y), (x + 1, y), (x + d, y - 1), (x + d + 1, y - 1), (x + d, y + 1),
            (x + d + 1, y + 1)]


def dilate(tiles, chunk):
    """`BoardTrait::dilate` on one chunk: the tiles and their neighbours within it."""
    cy = chunk // 15
    out = tiles
    for t in range(225):
        if has(tiles, t):
            row, col = divmod(t, 15)
            for nx, ny in neighbours(col, 15 * cy + row):
                nrow = ny - 15 * cy
                if 0 <= nx < 15 and 0 <= nrow < 15:
                    out |= 1 << (15 * nrow + nx)
    return out


# --- the Registry's checks (src/checks.cairo) -----------------------------------------------------

def _floor(walls, tile):
    return tile < 225 and not has(walls, tile)


def assert_set(chunk_set, width, height):
    if chunk_set & ~rectangle(width, height):
        raise Refused("zone: set outside rectangle")


def assert_outline(chunk, walls, chunk_set, mask):
    if not has(chunk_set, chunk):
        raise Refused("zone: chunk not in the set", f"chunk {chunk}")
    if mask and (BOARD & ~mask) & ~walls:
        raise Refused("zone: mask disagrees", f"chunk {chunk}")


def assert_chunk(record, chunk, candidates, quotas):
    walls, taken = record["walls"], set()
    packs = objects = 0

    def take(tile):
        # Walkable and in the interior (rows and columns 1-13): a pack's goblins stand within 2
        # of its tile (`Placement::near`'s precondition, ENG-09)
        row, col = divmod(tile, 15)
        if not (_floor(walls, tile) and 0 < row < 14 and 0 < col < 14):
            raise Refused("zone chunk: tile not floor", f"chunk {chunk} tile {tile}")
        if tile in taken:
            raise Refused("zone chunk: tile taken", f"chunk {chunk} tile {tile}")
        taken.add(tile)

    for s in record["spawns"]:
        if s["template"] == 0:
            if s["tile"]:
                raise Refused("zone chunk: empty with a value")
        else:
            take(s["tile"])
            packs += 1
    for o in record["objects"]:
        if o["kind"] == 0:
            if o["tile"] or o.get("state", 0) or o["param"]:
                raise Refused("zone chunk: empty with a value")
        else:
            if o["kind"] not in AUTHORED_OBJECTS or o.get("state", 0):
                raise Refused("zone chunk: object", f"kind {o['kind']}")
            take(o["tile"])
            objects += 1
    for i in range(6):
        tile = record["tiles"][i]
        if i < len(candidates) and has(candidates[i], chunk):
            take(tile)
            if quotas[i][0] == HEART:
                packs += 1
            else:
                objects += 1
        elif tile:
            raise Refused("zone chunk: empty with a value", f"quota {i}")
    if packs > 2 or objects > 3:
        raise Refused("zone chunk: over its caps", f"chunk {chunk}")


def assert_entry(entry_tile, entry_walls):
    if not _floor(entry_walls, entry_tile):
        raise Refused("zone: entry not floor")


def assert_gate(gate_id, gate, anchor):
    if not _floor(anchor["walls"], gate["anchor_tile"]):
        raise Refused("zone: gate anchor not floor", f"gate {gate_id}")
    if gate_id not in anchor["gates"]:
        raise Refused("zone: gate not indexed", f"gate {gate_id}")


def assert_candidates(sets, chunk_set):
    for s in sets:
        if s & ~chunk_set:
            raise Refused("candidates: outside the set")


def draws(n, left):
    if n >= left:
        return 0
    return left - n if 2 * n > left else n


def assert_quotas(quotas, chunk_set, candidates, hearts):
    """`hearts[i]`: the Heart's template `(min, max)`, or None when it is not in the registry."""
    members = count(chunk_set)
    total = 0
    for i, (kind, _param, n) in enumerate(quotas):
        if kind == 0:
            continue
        if kind in (EXIT, SET_PIECE_Q):
            raise Refused("zone: quota kind", f"quota {i}")
        if n > members:
            raise Refused("zone: count above members", f"quota {i}")
        left = count(candidates[i]) if i < len(candidates) else 0
        if n > left:
            raise Refused("zone: count above candidates", f"quota {i}")
        total += draws(n, left)
        if kind == HEART:
            bounds = hearts.get(i)
            if bounds is None or bounds[0] < 1 or bounds[1] < 1:
                raise Refused("zone: heart template", f"quota {i}")
    if total > MAX_DRAWS:
        raise Refused("zone: quota draws", f"{total} draws")


def assert_band(location):
    """R-39 (audit t-0131): an authored zone's band at most 255 levels (0 to 255 refused)."""
    if location["level_min"] == 0 and location["level_max"] == 255:
        raise Refused("zone: level band")


def assert_floor_rectangle(location):
    if location["kind"] == LOCATION_KINDS["dungeon"] and \
            location["width"] * location["height"] <= location["target"]:
        raise Refused("location: floor rectangle")


def assert_bridge(bridge, k, chunk, record):
    deck = bridge["deck"]
    if deck == 0:
        raise Refused("bridge: deck empty")
    a, b = bridge["ends"]
    if not (a < 225 and b < 225 and a != b and not has(deck, a) and not has(deck, b)):
        raise Refused("bridge: end")
    if k >= record["bridges"]:
        raise Refused("bridge: index")
    if not (_floor(record["walls"], a) and _floor(record["walls"], b)):
        raise Refused("bridge: end not floor")
    near = dilate(deck, chunk)
    if not (has(near, a) and has(near, b)):
        raise Refused("bridge: end not by the deck")
    # R-34 extended (ADR-0008 rule 1): every deck tile walkable in the chunk's plane
    if deck & record["walls"]:
        raise Refused("bridge: deck not floor")


def content(record):
    """The tiles a chunk's authored content stands on: spawn points, objects, candidate tiles."""
    tiles = {s["tile"] for s in record["spawns"] if s["template"]}
    tiles |= {o["tile"] for o in record["objects"] if o["kind"]}
    tiles |= {t for t in record["tiles"] if t}
    return tiles


def assert_clear(bridge, tiles):
    """R-37 (ADR-0008 rule 5): no spawn point, object, candidate tile, gate anchor or entry on a
    bridge's deck or ends."""
    a, b = bridge["ends"]
    on = {t for t in range(225) if has(bridge["deck"], t)} | {a, b}
    if on & set(tiles):
        raise Refused("bridge: tile taken", f"tiles {sorted(on & set(tiles))[:3]}")


def check_zone(z):
    """Every Registry check of an authored zone's records `z` (the converter's `zone` dict): the
    same rules as `src/checks.cairo`, run on what each write reads."""
    loc = z["location"]
    anchors = {}
    for gate in z["gates"].values():
        anchors.setdefault(gate["anchor_chunk"], set()).add(gate["anchor_tile"])
    anchors.setdefault(loc["entry_chunk"], set()).add(loc["entry_tile"])
    assert_band(loc)
    assert_floor_rectangle(loc)
    assert_set(z["chunk_set"], loc["width"], loc["height"])
    assert_candidates(z["candidates"], z["chunk_set"])
    assert_quotas(z["quotas"], z["chunk_set"], z["candidates"], z["hearts"])
    for chunk, record in sorted(z["chunks"].items()):
        assert_outline(chunk, record["walls"], z["chunk_set"], z["masks"].get(chunk, 0))
        assert_chunk(record, chunk, z["candidates"], z["quotas"])
        for k, bridge in enumerate(z["bridges"].get(chunk, [])):
            assert_bridge(bridge, k, chunk, record)
            assert_clear(bridge, content(record) | anchors.get(chunk, set()))
    entry = z["chunks"].get(loc["entry_chunk"])
    if entry is None:
        raise Refused("zone: chunk not in the set", "the entry chunk")
    assert_entry(loc["entry_tile"], entry["walls"])
    for gate_id, gate in sorted(z["gates"].items()):
        anchor = z["chunks"].get(gate["anchor_chunk"])
        if anchor is None:
            raise Refused("zone: chunk not in the set", f"gate {gate_id}'s anchor")
        assert_gate(gate_id, gate, anchor)
