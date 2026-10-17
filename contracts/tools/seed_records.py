"""The registry's records as `grimworld_logic::models` packs them (ENG-01 §3.5), and the rows of
`contracts/seed/`: pure functions and constants, shared by `lifecycle_probe.py` and
`scripts/devnet_deploy.py` (OPS-01a). Moved out of the probe unchanged: nothing here touches a node."""
import json
import os

CONTRACTS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LIVE = 1 << 250
REGION, LOCATION, GATE, QUOTAS, ITEM = 1, 2, 4, 5, 11
HUB_GATE, LINK, FLOOR = 1, 2, 3
INGREDIENT, POTION = 1, 3


# The registry's records, packed as `grimworld_logic::models` packs them (ENG-01 §3.5).
def short(text):
    return int.from_bytes(text.encode(), "big")


def region(town, book, first, name):
    return [town + (book << 16) + (first << 32) + (short(name) << 128) + LIVE]


def location(kind, width, target, floors, next_floor, entry_chunk, entry_tile, spawn_table=0,
             levels=(1, 3)):
    low = (kind + (1 << 8) + (1 << 24) + (levels[0] << 32) + (levels[1] << 40) + (width << 56) + (width << 64)
           + (target << 72) + (floors << 80) + (next_floor << 88) + (spawn_table << 104))
    return [low + ((entry_chunk + (entry_tile << 8)) << 128) + LIVE, LIVE]


def gate(source, destination, anchor, entry, kind):
    low = (source + (destination << 16) + (anchor[0] << 32) + (anchor[1] << 40) + (entry[0] << 48)
           + (entry[1] << 56) + (kind << 64))
    return [low + LIVE]


def item(klass):
    """An `ITEM` of region 1, value 1. A potion's entry heals its holder, 20 at every rank
    (`HEAL`, `SELF`, `SINGLE`, filter ALLIES: the holder is its own ally, and under FOES a `SELF`
    entry takes nobody): `Registry.set_record` refuses a potion without a legal entry
    (D-166, `ItemAssert::assert_legal`)."""
    entry = 3 + (20 << 16) + (20 << 32) + (1 << 88) + (1 << 91) if klass == POTION else 0
    return [klass + (1 << 8) + (1 << 32) + (entry << 128) + LIVE]


REGENERATION_POTION = 23  # SEED-02: the seed's first REGENERATION potion, after the 22 items of the probe


def regeneration_item():
    """SEED-02: the REGENERATION potion, an `ITEM` of region 1, value 1 like `item`. Its entry gives
    its holder 3 pips of health regeneration for 40 ticks, at every rank (`REGENERATION`, `SELF`,
    `SINGLE`, filter ALLIES like `item`; a potion's entry does not scale): a holding entry, so it
    carries a duration."""
    entry = 5 + (3 << 16) + (3 << 32) + (40 << 48) + (40 << 64) + (1 << 88) + (1 << 91)
    return [POTION + (1 << 8) + (1 << 32) + (entry << 128) + LIVE]


def seed_rows(name, columns):
    """The rows of one table of `contracts/seed/test-region.json`, `columns` numbers a row."""
    with open(os.path.join(CONTRACTS, "seed", "test-region.json")) as seed_file:
        flat = json.load(seed_file)[name]
    assert len(flat) % columns == 0, f"seed: {name} is not whole rows"
    return [flat[i:i + columns] for i in range(0, len(flat), columns)]


def entry_bits(row):
    """`EntryTrait::pack`: kind 0, param 8, v0 16, v12 32, d0 48, d12 64, charges 80, target 86,
    shape 88, filter 91, guard 92, scope 95 (the values here are not negative)."""
    kind, param, v0, v12, d0, d12, charges, target, shape, filter_, guard, scope = row
    return (kind + (param << 8) + (v0 << 16) + (v12 << 32) + (d0 << 48) + (d12 << 64)
            + (charges << 80) + (target << 86) + (shape << 88) + (filter_ << 91) + (guard << 92)
            + (scope << 95))


def skill_record(row):
    """`SkillRecord::pack`: the header, then the first entry above it; the other two."""
    _, prof, attr, kind, energy, adrenaline, activation, recharge, range_, target, elite = row[:11]
    header = (prof + (attr << 8) + (kind << 16) + (energy << 24) + (adrenaline << 32)
              + (activation << 40) + (recharge << 56) + (range_ << 72) + (target << 80)
              + (elite << 82))
    a, b, c = (entry_bits(row[11 + 12 * i:23 + 12 * i]) for i in range(3))
    return [header + (a << 128) + LIVE, b + (c << 128) + LIVE]


def caste_record(row):
    """`CasteRecord::pack`: the sheet's low limb and the per-type armors and loot table, then the
    four skills."""
    (_, tier, ai, health, regen, armor), vs = row[:6], row[6:15]
    wclass, wdamage, wtype, wticks, wrange = row[15:20]
    energy, energy_regen, skills, (rank, flee, loot, boss) = row[20], row[21], row[22:26], row[26:30]
    weapon = wclass + (wdamage << 4) + (wtype << 20) + (wticks << 24) + (wrange << 28)
    low = (tier + (ai << 8) + (health << 16) + (regen << 32) + (armor << 40) + (weapon << 48)
           + (energy << 80) + (energy_regen << 88) + (flee << 96) + (rank << 104) + (boss << 108))
    high = sum(v << (6 * i) for i, v in enumerate(vs)) + (loot << 54)
    packed = sum(sk << (16 * i) for i, sk in enumerate(skills))
    return [low + (high << 128) + LIVE, packed + LIVE]


def pack_record(row):
    """`PackRecord::pack`: five `(caste, min, max)` of 32 bits, the level (signed 8 bits) above."""
    bits = [row[1 + 3 * i] + (row[2 + 3 * i] << 16) + (row[3 + 3 * i] << 24) for i in range(5)]
    level = row[16] % 256
    low = bits[0] + (bits[1] << 32) + (bits[2] << 64) + (bits[3] << 96)
    return [low + ((bits[4] + (level << 32)) << 128) + LIVE]


def spawn_table_record(row):
    """`SpawnTableRecord::pack`: seven `(template, weight)` of 24 bits, the density above, then the
    terrain traps' skill (D-304)."""
    bits = [row[1 + 2 * i] + (row[2 + 2 * i] << 16) for i in range(7)]
    low = sum(b << (24 * i) for i, b in enumerate(bits[:5]))
    return [low + ((bits[5] + (bits[6] << 24) + (row[15] << 48) + (row[16] << 56)) << 128) + LIVE]


BASE, KIT = 12, 29  # CNT-01 (D-309)


def base_record(row):
    """`BaseRecord::pack`: the slot, then the hands, in part 0 (the prefix `BASE` lays out, D-158);
    part 1 is `LIVE` only."""
    _, slot, hands = row
    return [slot + (hands << 8) + LIVE, LIVE]


def kit_record(row):
    """`KitRecord::pack`: the starter weapon's `BASE` (0 none), then the six starter skills, 16 bits
    each."""
    _, weapon, *skills = row
    return [weapon + sum(sk << (16 * (i + 1)) for i, sk in enumerate(skills)) + LIVE]


def quotas_record(row):
    """`QuotaSetRecord::pack`: six `(kind 8 bits, param 16, count 8)` of 32 bits, four in the low limb."""
    bits = [row[1 + 3 * i] + (row[2 + 3 * i] << 8) + (row[3 + 3 * i] << 24) for i in range(6)]
    low = sum(b << (32 * i) for i, b in enumerate(bits[:4]))
    return [low + ((bits[4] + (bits[5] << 32)) << 128) + LIVE]


GATE_ZONE = 5  # CNT-01: the gate zone's `LOCATION`, and its `QUOTAS` (D-145)


def gate_zone_and_kits():
    """CNT-01's records that the deployments write after `devnet_deploy.seed_records()`'s, from
    `contracts/seed/test-region.json`'s rows: the gate zone (`LOCATION` 5: a 1 x 1 meadow at level
    `level_min` to `level_max`, no spawn table), its gates (7 and 8: the seed's after the deployments'
    6), its Heart (`QUOTAS` 5, after the packs), the starter weapons' bases and the kits (D-309, after
    the skills). In that order: a gate and a quota after their location."""
    (zone,) = [r for r in seed_rows("locations", 31) if r[0] == GATE_ZONE]
    _, kind, _, _, low, high, _, width, _, _, _, _, spawn, _, chunk, tile = zone[:16]
    records = [(LOCATION, GATE_ZONE, location(kind, width, 0, 0, 0, chunk, tile, spawn_table=spawn,
                                              levels=(low, high)))]
    for row in seed_rows("gates", 10):
        if row[1] == GATE_ZONE or row[2] == GATE_ZONE:
            _, source, destination, ac, at, ec, et, gate_kind, _, _ = row
            records.append((GATE, row[0], gate(source, destination, (ac, at), (ec, et), gate_kind)))
    records += [(QUOTAS, r[0], quotas_record(r)) for r in seed_rows("quotas", 19) if r[0] == GATE_ZONE]
    records += [(BASE, r[0], base_record(r)) for r in seed_rows("bases", 3)]
    records += [(KIT, r[0], kit_record(r)) for r in seed_rows("kits", 8)]
    return records
