# 14 — Quests of Region 1

> Status: **Draft v0.1** — every name of place, character and quest is a working name
> (LORE track). Rewards are initial values.
>
> Baseline (D-39): the quests of Guild Wars pre-Searing are used as **structural models**:
> what a quest asks, in which order quests open, what they give. Names, texts, characters
> and places are ours. Source: official wiki, read 2026-09-28.

## What the baseline teaches

| Observation in the baseline | What we keep |
|---|---|
| A short main chain: talk, leave the gate, pass the profession test, pick a second profession, graduate | Same spine, ending on the first promotion trial instead of a one-way exit |
| The profession test is the first source of skills: 2 skills | Same: **the test gives the first 2 skills** |
| Skills then come in bundles of 2–3, given **when the quest is accepted**, and the objective forces the use of one of them | Same. It is how the build system is taught |
| Each area is built around one profession's trainer | Each zone hosts one trainer |
| Most quests give 100–500 experience, the longest 750 | Same scale |
| Almost no gold from quests; item rewards are fixed weapons with one modifier | Small gold; fixed items |
| Repeatable daily contracts from level 10, with foes scaled to the player, were added six years later so that the area stays worth playing | Planned from the start: **guild contracts** |
| Many quests are escorts | **Not kept**: allied characters in instances were considered and dropped, as they bring more complexity than benefit to the player. Replaced by reach and rescue-as-reach objectives |
| Seven creature families | **Goblins only** (pillar 3). Variety comes from castes, packs and places |

## Experience

Adopted as is from the baseline (D-31).

| | |
|---|---|
| Experience to the next level | `1 400 + 600 × level` → level 20 at 140 600 |
| Experience for a kill, by level difference (foe − adventurer) | +5: 184 · +3: 152 · +1: 120 · 0: 100 · −1: 80 · −3: 48 · −5: 16 · −6 or less: **0** |
| Boss | Double |
| Attribute points per level | 5 up to level 10, 10 from 11 to 15, 15 from 16 to 20: 170 |
| Attribute points from the guild | +15 at Tin, +15 at Copper: **200 in total** |

Quests alone bring a new adventurer to about level 7; contracts and dungeons do the rest.

## Places

```
                 [Deep zone Z2] ── elite (later)
                      │
   [Dungeon D1] ── [Outpost B] 
                      │
                 [Road zone Z1] ── trainer: Warden
                      │
 trainer: Arcanist ── [Meadow Z0] ── [Town A]      trainer: Vanguard at the gate
```

## Main chain

| # | Quest | Giver | Asks | Structure | Gives |
|---|---|---|---|---|---|
| M1 | Registration | Guild clerk, Town A | Speak to the guild master | talk | 100 xp, the Wood tag |
| M2 | First steps | Guild master | Leave by the gate and meet your profession's trainer | reach | 250 xp |
| M3 | Profession test | Trainer | See per profession below | varies | 500 xp, **2 skills** |
| M4 | Word from the road | Trainer | Carry a report through Z1 to Outpost B | deliver | 250 xp, a shield or focus, **Outpost B unlocked** |
| M5 | The first nest | Outpost captain | Reach the entrance of D1 and come back | scout | 250 xp |
| M6 | Tin trial | Guild master | Promotion trial (06-guild) | trial | Rank Tin, +15 attribute points |

## Profession tests (M3)

| Profession | Asks | Teaches |
|---|---|---|
| Vanguard | Kill the 3 runts at the ford | Melee, facing |
| Warden | Kill the slinger on the far bank before it reaches cover | Range, line of sight |
| Arcanist | Kill runts until one drops a charred ear | Casting time, energy |

## Skill quests

Two per profession. Skills are given on acceptance; the profession may be primary or
secondary. 250 xp each.

| Profession | Quest | Asks | Skills given | The objective forces |
|---|---|---|---|---|
| Vanguard | The vineyard | Kill 4 runts nesting in the vines | Cleave, Rending Cut | Adrenaline use |
| Vanguard | The brute at the bridge | Defeat a hobgoblin; interrupt its wind-up | Skullring, Brace | **Interrupt a telegraphed attack** |
| Warden | Marksman's round | Kill 5 runts within 40 ticks | Aimed Shot, Hamstring Shot | Tick economy |
| Warden | The poisoned well | Kill the pack at the well without being hit in melee | Venom Coat, Snare | Traps, kiting |
| Arcanist | The experiment | Kill 3 goblins standing together with one cast | Cinder Ring, Deep Draw | Area effects |
| Arcanist | Cold hands | Reach the far entrance while slowing the wolf rider | Rime Shard, Stone Skin | Control |

The test gives the two others: Second Wind and Warcry (Vanguard), Field Dressing and
Sidestep (Warden), Ember Bolt and Static Lash (Arcanist). Test plus skill quests make the
6 starter skills of each profession
([03-adventurer](03-adventurer.md#mvp-starter-skills)). The 6 further skills of the MVP
are sold by trainers.

## Side quests

| Quest | Giver | Asks | Structure | Gives |
|---|---|---|---|---|
| The stolen strongbox | Merchant, Town A | Take the strongbox back from raiders in Z0 and return it | collect + deliver | 250 xp, 50 gold |
| The hermit by the ford | Guild clerk | Find the collector in Z0 and barter with him once | reach + barter | 250 xp; introduces collectors |
| The miller's bees | Miller, Z0 | Lure 3 packs over the bridge without fighting them | lure | 500 xp; teaches aggro |
| The long message | Steward, Town A | Carry a letter to the far end of Z2 | deliver, long | 750 xp, a weapon |
| Three witnesses | Outpost captain | Speak to 3 settlers scattered in Z1 | talk to N | 500 xp |
| The alchemist's list | Alchemist, Town A | Bring 2 each of 3 common ingredients | gather | 250 xp, **first hint**; introduces alchemy |
| Candles for the dead | Priest, Outpost B | Light 4 braziers in D1, floor 1 | activate N | 250 xp |
| The shaman's totem | Outpost captain | Kill a shaman and bring its totem | kill + collect | 500 xp; teaches "kill the shaman first" |
| Wolf tracks | Hunter, Z1 | Kill 2 wolf riders | kill N | 500 xp |
| The missing scout | Outpost captain | Find the scout in Z2 (reach the marker) | reach | 250 xp; unlocks the next quest |
| What the scout saw | Scout | Reach the overlook in Z2 and return | scout | 500 xp |
| The hob of the first nest | Guild board, Outpost B | Kill the boss of D1 | nest clearing | 1 000 xp, boss trophy |
| A second calling | Guild master, at Copper | Complete any trainer's skill quest outside your profession | meta | Secondary profession |

## Guild contracts (repeatable)

Inspired by the baseline's daily contracts, present from the start.

| | |
|---|---|
| Available from | Level 10 |
| Offered | 3 per day on the board of each hub, drawn from a list; one held at a time |
| A contract held at the end of the day | **Lost with its progress** at 00:00 UTC; the board offers the new day's (D-131) |
| Foes | **Never scaled.** Each contract states its foes and their levels. Easy contracts stay available and can be redone |
| Rank | A higher guild rank gives access to **new contracts**, harder and better paid |
| In the zone | A held contract adds its targets to the zone as a quota (ADR-0006) |
| Types | Annihilation (kill 6 pack leaders in a zone), Bounty (kill a named goblin), Search (reach a marker deep in a zone) |
| Give | 1 000 xp, 50 gold, merit with diminishing returns ([06-guild](06-guild.md#rules)) |

The daily draw is the only place where quests use the date. It is read in the hub, in the
persistent domain, never inside an instance.

## Count

6 main (the test counted once) · 6 skill quests · 13 side quests: **25 quests** for one
adventurer, plus contracts.

## Closed

Closed: no companions, hence no escorts (D-42, withdrawn). The secondary profession is kept as a feature and
deprioritised: it is not needed to prove technical feasibility (D-43).
