# Seed data

Content written into `Registry` through `set_record` (ENG-03). The records' bit layouts are
the models of `grimworld_logic::models` and docs/architecture/ENG-01-interfaces.md §3.5; the files here hold the
fields, not the packed felts.

| File | What |
|---|---|
| `test-region.json` | The test region: one region, its town, one zone, a dungeon of two floors, the gate zone (CNT-01), their gates; the reveal's content (ENG-05): design/05's four MVP packs and the gate pack, a spawn table, the quotas; design/20's five castes and their skills; the three MVP professions' 18 starter skills (CNT-01); the caves' terrain trap skill (GEN-TRAP); the creation kits and the starter weapons' bases (D-309) |

## The test region

| Kind | Id | What |
|---|---|---|
| `REGION` | 1 | "Test Region": town 1, no book, first location 1 |
| `LOCATION` | 1 | The town (a hub: no map, so no size and no entry) |
| `LOCATION` | 2 | A zone: meadow, levels 1–3, 3 × 2 chunks, entered at chunk 0, tile 105 (row 7, column 0), spawn table 1 |
| `LOCATION` | 3 | The dungeon's first floor: cave, levels 3–5, `N` 6, 2 floors, next floor 4, entered at chunk 112, tile 112 (the centre, ENG-01 §3.2), spawn table 1 |
| `LOCATION` | 4 | The second and last floor: `N` 8, spawn table 1 |
| `LOCATION` | 5 | The gate zone (CNT-01, GATE-2a): meadow, levels 1–1, 1 × 1 chunk, entered at chunk 0, tile 105, no spawn table: its only pack is its Heart |
| `OUTLINE` | 767 (2 × 256 + 255) | The zone's chunk set: (0, 0), (1, 0), (2, 0), (0, 1), (1, 1) |
| `OUTLINE` | 514 (2 × 256 + 2) | Chunk (2, 0)'s tile mask: columns 0–11 |
| `OUTLINE` | 528 (2 × 256 + 16) | Chunk (1, 1)'s tile mask: rows 0–9, and columns 0–9 of rows 10–14 |
| `GATE` | 1, 2 | Town → zone (entering at chunk 0, tile 105), zone → town (anchored there): hub gates |
| `GATE` | 3, 4 | Zone → floor 1 (anchored at chunk 16, tile 110), floor 1's entrance → zone: links |
| `GATE` | 5 | Floor 1 → floor 2: a floor gate, no anchor (a dungeon's exit is a quota, ADR-0006) |
| `GATE` | 6 | Zone → floor 1, anchored at the zone's entry (chunk 0, tile 105), entering at chunk 112, tile 112: a link, the deployments' shortcut (`devnet_deploy.py`), in the seed so that ids agree |
| `GATE` | 7, 8 | Town → gate zone (entering at chunk 0, tile 105), gate zone → town (anchored there): hub gates |
| `PACK` | 1 | *Rabble* (design/05, tier 1): 3 to 5 Runts; level offset 0 (as every pack below) |
| `PACK` | 2 | *Raiders* (tier 1): 2–3 Runts, 1–2 Slingers |
| `PACK` | 3 | *Warband* (tier 3): 2 Skirmishers, 1 Slinger, 1 Shaman |
| `PACK` | 4 | *Hob guard* (tier 4): 1 Hobgoblin, 2 Skirmishers, 1 Shaman |
| `PACK` | 5 | The gate pack (CNT-01): 3 Runts and 2 Slingers, each at its fewest = its most, so always 5 goblins (the Raiders at their largest) |
| `SPAWN_TABLE` | 1 | Template 1, the Rabble (weight 3), template 2, the Raiders (weight 1); density 128 (each of a chunk's two pack slots filled with probability 1/2); trap 5 (the dungeon's generated terrain traps take Rockfall; the meadow zone, which shares the table, generates none: GEN-TRAP, D-304). The Warband and the Hob guard are in no table yet: a deeper location's |
| `QUOTAS` | 2 | The zone's collector camp: collector 1, once (design/18) |
| `QUOTAS` | 3 | Floor 1's exit: gate 5, once (ADR-0006) |
| `QUOTAS` | 5 | The gate zone's Heart: pack 5, once |
| `BASE` | 1, 2 | The starter weapons' bases (D-309): 1 an axe (weapon slot, one hand), 2 a bow (two hands) |
| `KIT` | 1, 2, 3 | The creation kits (D-309), id = the profession: the Vanguard's (axe, skills 1, 22, 3, 4, 6, 7), the Warden's (bow, skills 8–13), the Arcanist's (no weapon, skills 14–19) |

**Quotas (D-145: `QUOTAS` id = the location's id; the layout is ENG-05's,
`grimworld_logic::models::quotas`).** `QUOTAS` 3, floor 1's exit (count 1; gate 5 has no anchor
because a dungeon's exit is a quota, ADR-0006); `QUOTAS` 2, the zone's collector camp (count 1,
design/18; collector 1 is a `COLLECTOR` id the seed does not write yet, its layout being a later
lot's). `QUOTAS` 4, floor 2's boss arena, a set-piece quota, waits for a `SET_PIECE` (an authored
chunk, CM-7 and TOOL-01). The town (1) has no map and no quota. The registry accepts them only after
their location.

**Packs (ENG-05, `models::pack`, `models::spawn_table`).** The registry checks only that a template's
`min` is not above its `max` (`PackAssert`).

**The gate zone (CNT-01, GATE-2a, P2-3).** A pack's count is drawn at reveal from the entry draw,
which follows the transaction hash, so a script cannot fix it; a template whose fewest are its most
can. Location 5 is one chunk with no spawn table, and its quotas hold one Heart (`QUOTAS` kind 2)
of pack 5: a 1 × 1 zone's only chunk hosts every quota (`placement`'s subset, no draw), so the pack
is placed in chunk 0 at every entry, at the band's highest level (1), on an allowed tile at least
3 tiles from the entry (the reveal's allowed tiles exclude those within 2 of an anchor); only its tile and its goblins' offsets
follow the draw. Chunk 0 is within sight of the entry tile, so it is revealed at `enter`. A script
finds it so: `Hub.enter(adventurer, 7)`, then `instance_state` (VIEW-01: the 3 × 3 chunks around
the member hold the whole zone) lists the five goblins, entities 8 to 12 (`8 + 16 chunk + k`); or
`instance_region(instance, 0, 1)` gives chunk 0's features, whose first pack word holds the pack's
tile (bits 0–7), template 5 and count 5. The script walks to the tile and fights until no goblin of
the list is alive, then leaves by gate 8. A goblin's count is lower than 5 only when fewer than four
allowed tiles are free within 2 of the pack's tile, which an open meadow chunk does not produce
(not measured on every draw: a property of the generated terrain).

**Castes (design/20 §2.2, v1.0; design/09's five).** The sheets field by field; AI profiles are
design/05's ids (1 `swarm` … 5 `brute`), which the tick does not read yet (every caste runs
design/04's Engaged row, CBT-05h/CBT-07); loot tables 0 until a `LOOT_TABLE` is seeded.

| Kind | Id | What |
|---|---|---|
| `CASTE` | 1 | Runt: tier 1, `swarm`, 50 %, armor 20, an axe (17, slashing, 1 tick, range 1), no energy, no skill, rank 4, flees below 30 % |
| `CASTE` | 2 | Slinger: tier 1, `kite`, 40 %, armor 20 (+30 against types 4–7), a bow (21, blunt, 2 ticks, range 6), rank 4 |
| `CASTE` | 3 | Skirmisher: tier 2, `flank`, 50 %, armor 40 (+20 against types 1–3), a sword (18, slashing, 1, 1), energy 20 / 2, Rending Cut (2), rank 6 |
| `CASTE` | 4 | Shaman: tier 3, `support`, 60 %, armor 30, a staff (16, earth, 2, 6), energy 30 / 4, Mend Kin (20) then Stone Skin (17), rank 9 |
| `CASTE` | 5 | Hobgoblin: tier 4, `brute`, 100 %, armor 60 (+20 against types 1–3), a maul (27, blunt, 2, 1), energy 20 / 2, Overhead Smash (21), rank 12 |

**Skills (design/03 *MVP starter skills*, values settled by design/20 §3.1, DS-22, DS-30 to DS-33;
the castes' own, §3.2).** Skills 1–4 replace the placeholders of SEED-02 (the bar `devnet_deploy.py
--build full` picks by kind, see CNT-01's report); skill 5, Rockfall, is kept for GEN-TRAP. Values are
rank 0…12; an attack's range is its weapon's (the executor reads the weapon's, the record's is the
client's); `SELF` entries are filtered ALLIES (R-45); a spell's range is 6 where design/03 gives none
(the staff's and design/20's for Stone Skin and Mend Kin). **One weapon family per starter bar
(D-310):** the Vanguard's three starter attacks are Axes attacks, Cleave, Gash and Haft Blow; Rending
Cut (Blades) and Skullring (Mauls) are trainers' skills (CNT-02), and Skullring is not seeded.
design/03's table is updated by WPN-01.

The attribute ids the records name are **design/03's attribute table in order, from 1**: Might 1,
Blades 2, Axes 3, Mauls 4, Tactics 5, Fieldcraft 6, Archery 7, Survival 8, Trapping 9, Wellspring 10,
Fire 11, Frost 12, Storm 13, Stone 14, Grace 15, Mending 16, … Insight 26 (D-157 A's global ids, never
numbered before CNT-01; no rule reads them yet: `Build::loadout` passes no bar attribute).

| Id | Name | Profession, attribute | Kind | Energy / adrenaline, activation, recharge, range | Entries |
|---|---|---|---|---|---|
| 1 | Cleave | Vanguard, Axes | Attack | 4 strikes, 0, 0, the weapon's | `ATTACK_BONUS` 10…30 |
| 2 | Rending Cut | Vanguard, Blades | Attack | 5, 0, 8, the weapon's | `CONDITION` Bleeding 5…20; the Skirmisher's, not a starter (D-310: a trainer's, CNT-02) |
| 3 | Haft Blow | Vanguard, Axes | Attack | 6 strikes, 0, 0, the weapon's | `CONDITION` Knocked down 2: Skullring's values and kind as an axe attack (D-310) |
| 4 | Second Wind | Vanguard, Tactics | Skill | 5, 1, 20, self | `HEAL` 40…140; `HEAL` 20…70 `BELOW_HALF` (DS-31) |
| 5 | Rockfall | none | Trap | 0, 0, 0, a tile | `TRAP`; `DAMAGE` earth 10…40 (GEN-TRAP) |
| 6 | Brace | Vanguard, Tactics | Stance | 5, 0, 15, self | `BLOCK` 1…3 for 8…15 (DS-33) |
| 7 | Warcry | Vanguard, Might | Shout | 5, 0, 20, self | `PENETRATION` 5…20 % for 5…11, scope `WEAPON` (DS-30) |
| 8 | Aimed Shot | Warden, Archery | Attack | 10, 1, 6, the weapon's | `ATTACK_BONUS` 10…25 |
| 9 | Hamstring Shot | Warden, Archery | Attack | 10, 1, 10, the weapon's | `CONDITION` Crippled 3…12 |
| 10 | Venom Coat | Warden, Survival | Preparation | 15, 2, 12, self | `ON_ATTACK_CONDITION` Poison 24, held 12 (its recharge: design/03 gives the poison's 24, not the coat's duration) |
| 11 | Snare | Warden, Trapping | Trap | 10, 2, 20, range 1, a tile | `TRAP`; `DAMAGE` piercing 10…40; `CONDITION` Crippled 3…8 (DS-32) |
| 12 | Field Dressing | Warden, Survival | Skill | 5, 1, 15, self | `HEAL` 30…120; `CURE` Bleeding |
| 13 | Sidestep | Warden, Fieldcraft | Stance | 5, 0, 20, self | `EVADE` melee for 2…6 |
| 14 | Ember Bolt | Arcanist, Fire | Spell | 5, 1, 2, range 6 | `DAMAGE` fire 15…60 |
| 15 | Cinder Ring | Arcanist, Fire | Spell | 15, 2, 12, self | `DAMAGE` fire 20…80 and `CONDITION` Burning 1…3, `SELF`, `RING_1`, foes |
| 16 | Rime Shard | Arcanist, Frost | Spell | 5, 1, 4, range 6 | `DAMAGE` cold 10…50; `CONDITION` Crippled 2…5 (FX-16) |
| 17 | Stone Skin | Arcanist, Stone | Enchantment | 10, 1, 20, range 6, an ally | `ARMOR` 10…30 for 8…20, `ALLY`, allies (DS-22) |
| 18 | Static Lash | Arcanist, Storm | Spell | 10, 1, 6, range 6 | `DAMAGE` lightning 10…60; `HIT_PENETRATION` 25 % |
| 19 | Deep Draw | Arcanist, Wellspring | Glyph | 0, 1, 25, self | `NEXT_SPELL_COST` 5…15, held 25 (its recharge; design/03 gives none: it is spent by the next spell, design/19 §3.4) |
| 20 | Mend Kin | Cleric, Mending | Spell | 10, 2, 8, range 6, an ally | `HEAL` 20…100, `ALLY`, allies (the Shaman's) |
| 21 | Overhead Smash | Vanguard, Mauls | Attack | 10, 3, 10, the weapon's | `ATTACK_BONUS` 20…60 (the Hobgoblin's wind-up) |
| 22 | Gash | Vanguard, Axes | Attack | 5, 0, 8, the weapon's | `CONDITION` Bleeding 5…20: Rending Cut's values and kind as an axe attack (D-310) |

**The creation kits (D-309).** A `KIT` per profession, id = the profession's: its starter weapon's
`BASE` (0 none) and its starter skills. `create_adventurer` reads it with the region (one `bundle`)
and credits the purse that buys exactly those skills from none known, priced by `SKILL_PRICES`
(`SkillTrainerTrait::purse`: 50 + 60 + 70 + 80 + 90 + 100 = 450 for six); a profession without a
`KIT` gets nothing. A later kit is a seed change. The bases hold only the slot and the hands that
`BASE` lays out (D-158); the weapon itself is CNT-01's open proposal (its report).

**Names for the client (CLI-05; off-chain, CV's single source).** The registry holds no names. Every skill and
item id of the seed, with a short English name and what it is:

| Kind | Id | Name | What |
|---|---|---|---|
| `SKILL` | 1 | Cleave | The skills' table above |
| `SKILL` | 2 | Rending Cut | The skills' table above |
| `SKILL` | 3 | Haft Blow | The skills' table above |
| `SKILL` | 4 | Second Wind | The skills' table above |
| `SKILL` | 5 | Rockfall | The skills' table above |
| `SKILL` | 6 | Brace | The skills' table above |
| `SKILL` | 7 | Warcry | The skills' table above |
| `SKILL` | 8 | Aimed Shot | The skills' table above |
| `SKILL` | 9 | Hamstring Shot | The skills' table above |
| `SKILL` | 10 | Venom Coat | The skills' table above |
| `SKILL` | 11 | Snare | The skills' table above |
| `SKILL` | 12 | Field Dressing | The skills' table above |
| `SKILL` | 13 | Sidestep | The skills' table above |
| `SKILL` | 14 | Ember Bolt | The skills' table above |
| `SKILL` | 15 | Cinder Ring | The skills' table above |
| `SKILL` | 16 | Rime Shard | The skills' table above |
| `SKILL` | 17 | Stone Skin | The skills' table above |
| `SKILL` | 18 | Static Lash | The skills' table above |
| `SKILL` | 19 | Deep Draw | The skills' table above |
| `SKILL` | 20 | Mend Kin | The skills' table above |
| `SKILL` | 21 | Overhead Smash | The skills' table above |
| `SKILL` | 22 | Gash | The skills' table above |
| `ITEM` | 1, 8, 15, 22 | Healing Potion | Potion; entry `HEAL` 20 on its holder (`SELF`, `SINGLE`, filter ALLIES), at every rank |
| `ITEM` | 23 | Regeneration Potion | Potion; entry `REGENERATION` 3 pips for 40 ticks on its holder (`SELF`, `SINGLE`, filter ALLIES) |
| `ITEM` | 2 to 7, 9 to 14, 16 to 21 | Ingredient (2 to 7, 9 to 14, 16 to 21) | Ingredient (18 items, no entry); named "Ingredient <id>" until the content pass names them |

Skills come first in the file's order of writing (a caste names its skills, the registry reads
them), and the bases and the kits come last (a kit names both), and `skill_fields` and `caste_fields` give the columns (a skill's three entries are `e1_` to
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

**The terrain trap skill (GEN-TRAP, D-268, D-304).** Skill 5, Rockfall, is what the cave's generated
terrain traps fire (spawn table 1's `trap`): kind 9, profession 0 (never on a bar: `set_build`
refuses it), a `TRAP` entry (`TILE`, `SINGLE`), then an earth `DAMAGE` of 10 at rank 0 to 40 at rank
12 on a `FOE`, `SINGLE` (Snare's payload without its condition). A terrain trap fires at rank 0 and
the band's lower level, so it deals 10. Spike pit (skill 6, the ruins' piercing one) waits for a ruin
location in the seed.
