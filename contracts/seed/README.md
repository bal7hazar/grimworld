# Seed data

Content written into `Registry` through `set_record` (ENG-03). The records' bit layouts are
the models of `grimworld_logic::models` and docs/architecture/ENG-01-interfaces.md §3.5; the files here hold the
fields, not the packed felts.

| File | What |
|---|---|
| `test-region.json` | The test region: one region, its town, one zone, a dungeon of two floors, their gates; the reveal's content (ENG-05): two pack templates, a spawn table, the zone's and floor 1's quotas; the castes and the skill the packs name (ENG-07t); three more skills for the devnet adventurer's bar (SEED-02) |

## The test region

| Kind | Id | What |
|---|---|---|
| `REGION` | 1 | "Test Region": town 1, no book, first location 1 |
| `LOCATION` | 1 | The town (a hub: no map, so no size and no entry) |
| `LOCATION` | 2 | A zone: meadow, levels 1–3, 3 × 2 chunks, entered at chunk 0, tile 105 (row 7, column 0), spawn table 1 |
| `LOCATION` | 3 | The dungeon's first floor: cave, levels 3–5, `N` 6, 2 floors, next floor 4, entered at chunk 112, tile 112 (the centre, ENG-01 §3.2), spawn table 1 |
| `LOCATION` | 4 | The second and last floor: `N` 8, spawn table 1 |
| `OUTLINE` | 767 (2 × 256 + 255) | The zone's chunk set: (0, 0), (1, 0), (2, 0), (0, 1), (1, 1) |
| `OUTLINE` | 514 (2 × 256 + 2) | Chunk (2, 0)'s tile mask: columns 0–11 |
| `OUTLINE` | 528 (2 × 256 + 16) | Chunk (1, 1)'s tile mask: rows 0–9, and columns 0–9 of rows 10–14 |
| `GATE` | 1, 2 | Town → zone (entering at chunk 0, tile 105), zone → town (anchored there): hub gates |
| `GATE` | 3, 4 | Zone → floor 1 (anchored at chunk 16, tile 110), floor 1's entrance → zone: links |
| `GATE` | 5 | Floor 1 → floor 2: a floor gate, no anchor (a dungeon's exit is a quota, ADR-0006) |
| `PACK` | 1 | 2 to 5 goblins: caste 1 (1–2), caste 2 (1–3); level offset 0 |
| `PACK` | 2 | 1 to 3 goblins: caste 3 (1), caste 1 (0–2); level offset +1 |
| `SPAWN_TABLE` | 1 | Template 1 (weight 3), template 2 (weight 1); density 128 (each of a chunk's two pack slots filled with probability 1/2) |
| `QUOTAS` | 2 | The zone's collector camp: collector 1, once (design/18) |
| `QUOTAS` | 3 | Floor 1's exit: gate 5, once (ADR-0006) |

**Quotas (D-145: `QUOTAS` id = the location's id; the layout is ENG-05's,
`grimworld_logic::models::quotas`).** `QUOTAS` 3, floor 1's exit (count 1; gate 5 has no anchor
because a dungeon's exit is a quota, ADR-0006); `QUOTAS` 2, the zone's collector camp (count 1,
design/18; collector 1 is a `COLLECTOR` id the seed does not write yet, its layout being a later
lot's). `QUOTAS` 4, floor 2's boss arena, a set-piece quota, waits for a `SET_PIECE` (an authored
chunk, CM-7 and TOOL-01). The town (1) has no map and no quota. The registry accepts them only after
their location.

**Packs (ENG-05, `models::pack`, `models::spawn_table`).** The registry checks only that a template's
`min` is not above its `max` (`PackAssert`).

**Castes and skill (ENG-07t).** The castes 1 to 3 the templates name are written, with the one skill
they carry, so that a fight runs on the node (`lifecycle_probe.py --fight on` writes them from this
file). Placeholders for the mechanics, not DES-06's sheets (DES-06 fills the real ones):

| Kind | Id | What |
|---|---|---|
| `SKILL` | 1 | An attack (kind 1), range 1, 4 strikes of adrenaline, one `ATTACK_BONUS` entry (+2 at rank 0, +6 at rank 12) |
| `CASTE` | 1 | Grunt: tier 1, 100 % health, an axe (damage 6, slashing, 2 ticks, range 1), skill 1 |
| `CASTE` | 2 | Slinger: tier 1, 100 % health, a bow (damage 5, piercing, 3 ticks, range 4), skill 1 |
| `CASTE` | 3 | Brute: tier 2, 150 % health, armor 2, a maul (damage 9, blunt, 3 ticks, range 1), skill 1 |

**The bar's skills (SEED-02, D-275, D-277).** Skills 2 to 4 are what `buy_skill` sells to the devnet
adventurer, a Vanguard (profession 1, so each skill is of profession 1: `set_build` refuses another),
so that its bar holds an instant attack, an activation skill, a trap and a REGENERATION skill (`scripts/devnet_deploy.py
--build full`). No design table names them for a Vanguard (design/03's starter tables give the trap to the Warden,
the heal to both), so their numbers are small and plain, from design/03's rows where one exists, and every
skill is a legal carrier (`assert_carrier`, R-44: no `TILE` entry beside a `FOE` or `ALLY` one, no `SELF` entry
before an addressed one; the registry checks them at `set_record`). They are not DES-06's sheets.

| Kind | Id | What |
|---|---|---|
| `SKILL` | 2 | The activation skill, a Skill (kind 11) of profession 1, attribute 1, 5 energy, activation 1 tick, recharge 20, on its caster: `HEAL` 40 at rank 0, 140 at rank 12 (design/03's Second Wind, without its half-health bonus) |
| `SKILL` | 3 | The trap, kind 9, 10 energy, activation 2, recharge 20, range 3, on a tile: a `TRAP` entry, then 10 to 40 earth damage and Crippled for 3 ticks on the foe that enters it (design/03's Snare) |
| `SKILL` | 4 | The REGENERATION skill, a Skill (kind 11), 5 energy, instant, recharge 20, on its caster: `REGENERATION` 2 pips at rank 0, 5 at rank 12, held 30 ticks at rank 0, 60 at rank 12 (plain values: no design row) |

The REGENERATION potion is not in this file: the items are `seed_records.py`'s (the probe and the deployment
write them, `item` and `regeneration_item`). `ITEM` 23 is a potion whose entry is `REGENERATION` 3 pips for
40 ticks on its holder, at every rank (a potion's entry does not scale), next to the healing potions 1, 8,
15 and 22 (`HEAL` 20).

**Names for the client (CLI-05; off-chain, CV's single source).** The registry holds no names. Every skill and
item id of the seed, with a short English name and what it is:

| Kind | Id | Name | What |
|---|---|---|---|
| `SKILL` | 1 | Strike | Attack (kind 1), instant (activation 0), range 1, 4 strikes of adrenaline; entry 1 `ATTACK_BONUS` +2 (rank 0) to +6 (rank 12) |
| `SKILL` | 2 | Second Wind | Skill (kind 11), activation 1, 5 energy, recharge 20, self; entry 1 `HEAL` 40 to 140 |
| `SKILL` | 3 | Snare | Trap (kind 9), activation 2, 10 energy, recharge 20, range 3, a tile; entries `TRAP`, `DAMAGE` earth 10 to 40 on a foe, `CONDITION` Crippled 3 ticks on a foe |
| `SKILL` | 4 | Mending | Skill (kind 11), instant (activation 0), 5 energy, recharge 20, self; entry 1 `REGENERATION` 2 to 5 pips, held 30 to 60 ticks |
| `ITEM` | 1, 8, 15, 22 | Healing Potion | Potion; entry `HEAL` 20 on its holder (`SELF`, `SINGLE`), at every rank |
| `ITEM` | 23 | Regeneration Potion | Potion; entry `REGENERATION` 3 pips for 40 ticks on its holder (`SELF`, `SINGLE`) |
| `ITEM` | 2 to 7, 9 to 14, 16 to 21 | Ingredient (2 to 7, 9 to 14, 16 to 21) | Ingredient (18 items, no entry); named "Ingredient <id>" until the content pass names them |

Skills come first in the file's order of writing (a caste names its skills, the registry reads
them), and `skill_fields` and `caste_fields` give the columns (a skill's three entries are `e1_` to
`e3_` and the entry's twelve fields; a caste's armors are `armor_vs_1` to `armor_vs_9`).

A chunk of the chunk set with no tile mask is whole. No set piece, book or quest is referenced:
those kinds' content is later tasks'.

## Format

snforge's `read_json` puts an object's values in the alphabetical order of its keys, flattens
nested arrays, drops empty arrays and writes a one-element array without its length. So each kind
is one flat array, a record per line with fixed columns, next to the names of its columns
(`<kind>_fields`), which the reader checks. No array may be empty. A region's name is a string of
at most 15 characters, in its row.

An outline's row lists `location`, `chunk` (255 for the chunk set) and 15 numbers: bit `c` of
`row_r` is bit `15 r + c` of the record, a chunk `(c, r)` of the set or a tile `(c, r)` of the
chunk. A pack template's row: `id`, five `(caste, min, max)`, `level` (a signed offset). A spawn
table's: `id`, seven `(template, weight)`, `density`. A location's quotas: `location`, six `(kind,
param, count)` (kind 1 exit, 2 Heart, 3 vein, 4 collector, 5 landmark, 6 set piece).

## Writing it

`contracts/persistent/tests/test_seed.cairo`: `SeedTrait::write(registry)` reads the file, builds
every record as its model, packs it through `content::Record`, and writes it as the
administrator, regions first, locations before their outlines and their quotas. `test_seed_written_and_read_back`
writes it and reads it back in one `bundle`. The deployment scripts that write it to a network are
OPS-01's.
