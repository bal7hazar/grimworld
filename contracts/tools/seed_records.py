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


def location(kind, width, target, floors, next_floor, entry_chunk, entry_tile, spawn_table=0):
    low = (kind + (1 << 8) + (1 << 24) + (1 << 32) + (3 << 40) + (width << 56) + (width << 64)
           + (target << 72) + (floors << 80) + (next_floor << 88) + (spawn_table << 104))
    return [low + ((entry_chunk + (entry_tile << 8)) << 128) + LIVE, LIVE]


def gate(source, destination, anchor, entry, kind):
    low = (source + (destination << 16) + (anchor[0] << 32) + (anchor[1] << 40) + (entry[0] << 48)
           + (entry[1] << 56) + (kind << 64))
    return [low + LIVE]


def item(klass):
    """An `ITEM` of region 1, value 1. A potion's entry heals its holder, 20 at every rank
    (`HEAL`, `SELF`, `SINGLE`): `Registry.set_record` refuses a potion without a legal entry
    (D-166, `ItemAssert::assert_legal`)."""
    entry = 3 + (20 << 16) + (20 << 32) + (1 << 88) if klass == POTION else 0
    return [klass + (1 << 8) + (1 << 32) + (entry << 128) + LIVE]


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
    """`SpawnTableRecord::pack`: seven `(template, weight)` of 24 bits, the density above."""
    bits = [row[1 + 2 * i] + (row[2 + 2 * i] << 16) for i in range(7)]
    low = sum(b << (24 * i) for i, b in enumerate(bits[:5]))
    return [low + ((bits[5] + (bits[6] << 24) + (row[15] << 48)) << 128) + LIVE]
