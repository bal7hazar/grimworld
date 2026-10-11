# `@grimworld/sim`

The client's simulation core (ADR-0003): a TypeScript mirror of the rules the chain decides, so
that the client predicts what the chain computes, bit for bit (D-140, option (a) of SPK-4). Pure:
no rendering, no chain access, no randomness, no clock, no I/O (mandate §6), except the tests and
the harness's reader.

## What is mirrored

| File                                          | Cairo                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Vector table                      | Cases       |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- | ----------- |
| `src/window.ts`                               | `WindowTrait` (`contracts/logic/src/types/window.cairo`, ENG-02)                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `window.jsonl`                    | 2,065       |
| `src/hit.ts`                                  | `HitTrait::resolve` and the `Serde` of `Hit`, `HitTarget`, `HitOutcome` (`types/hit.cairo`, CBT-03a)                                                                                                                                                                                                                                                                                                                                                                                                                                        | `hit.jsonl`                       | 203         |
| `src/body/`, `src/effect.ts`, `src/combat.ts` | the `Body` operations (`types/executor.cairo`'s `Body`, `MemberBody`, `GoblinBody` and the dispatch `UnitBody`, CLI-02g-C) and what they call of `models/member.cairo` and `models/goblin.cairo` (the snapshot's reads, the lifecycle, the conditions, the interrupt), `types/infliction.cairo`, `durations.cairo`; the effect entry (`EntryTrait`: `line`, `value`, `duration`, `class`, `pack`, `unpack`)                                                                                                                                 | `body.jsonl`                      | 327         |
| `src/executor.ts`, `src/trap.ts`              | a trap's trigger (CLI-02g-D, D-257): `TrapLibrary::trigger` (`systems/trap.cairo`), `TrapTrait`'s lookup and source (`types/trap.cairo`: `locate`, `free`, `trigger`, `terrain`, `by_member`, `by_goblin`, `entries`, `occupied`, `write`) and the executor's trap path (`types/executor.cairo`: `trigger`, `trap`, `strike`, `resolve`, `entries`, `ops`, `hold`, `guards`, `spell`, `put`, `actor`, `DefenceTrait`, `holding`, `Levered`'s cache)                                                                                         | `trap.jsonl`, `segment2.jsonl`    | 63, 44      |
| `src/fate.ts`                                 | `fate::domain`, `fate::derive` and the purposes (`contracts/logic/src/fate.cairo`), Poseidon through `@scure/starknet`                                                                                                                                                                                                                                                                                                                                                                                                                      | `fate.jsonl`                      | 227         |
| `src/packing.ts`                              | `contracts/logic/src/packing.cairo`: `split`, `limbs`, `join`, `peel`, `fits`, the field readers, `Lanes32`, `Lanes16`, `Counter`, `Bitmap`                                                                                                                                                                                                                                                                                                                                                                                                 | `packing.jsonl`                   | 520         |
| `src/movement.ts`                             | the moves of a played batch (ENG-07, CLI-02c): the window's board around the adventurer (`SegmentTrait::board`, `BoardTrait::position`, `AssemblyTrait::origin`), a Move's ticks (`TickMathTrait::move_ticks`), the tick's flood (`Bfs::flood`, `FloodTrait`) and step 0's awake set (`TickTrait::awake`)                                                                                                                                                                                                                                   | `movement.jsonl`                  | 94          |
| `src/batch.ts`                                | where a played batch stops (ENG-07b, CLI-02d): `SegmentTrait::admit` (E-16's cap of 16 records, E-1's weight with +1 a first record) and `SegmentTrait::revealed` (a reveal's weight, 2 a chunk)                                                                                                                                                                                                                                                                                                                                            | `batch.jsonl`                     | 28          |
| `src/segment.ts`                              | one segment of a played batch (ENG-07, D-248, CLI-02f, CLI-02g-A): `SegmentTrait::run` (`types/play.cairo`) on the real world: the owed ticks' fold, `max(1, ticks)`, the three weight checks (`run`'s, `turn`'s, `step`'s), the `ran` rule, a Move's reveal stop, `fits` with its goblin records, the illegal halts, `world.defeated`, the occupied tile, the companions, the fast path's ticks and regeneration, `MOVEMENT`, the followed window; the window's walkable board (`SegmentTrait::board`, `hexx`'s `AssemblyTrait::assemble`) | `segment.jsonl`, `segment2.jsonl` | 47, 44      |
| `src/segment/`                                | the `Serde` codecs of `Content`, `Words`, the ground, `Area`, `executor::Board`, `Action`, `Done` and the recorded calls (`serde.ts`); a member's load and store, the content's `Sheets`, `Index` and `Kit` (`words.ts`); a goblin's load, with its refusals, its store and the fields of its words (`goblin.ts`, CLI-02g-B1); the world's load, with the awake cap, and store (`world.ts`); the fast path's named tick functions, `flag::KEPT` and `can_act` (`tick.ts`); the seam of the classes and their call digests (`classes.ts`)    | `segment2.jsonl`                  | 44          |
| `src/reveal.ts`, `src/reveal/`, `src/hexx.ts` | the reveal of a chunk (ENG-05, ENG-05b, ENG-10b): `RevealTrait::reveal` and its steps (`types/reveal.cairo`, `reveal/board.cairo`, `reveal/placement.cairo`), `SightTrait::chunks`, `fate::EntropyTrait` (`word`, `feed`, `outline`), `PackPlacementTrait::member`, and what they call of `hexx` 0.2.0 (`RngTrait`, `CaverTrait::smooth` and `keep_component`)                                                                                                                                                                              | `reveal.jsonl`                    | 214         |
| `src/exp2.ts`                                 | `helpers/exp2.cairo`'s table, generated for both sides by `contracts/tools/exp2_table.py`                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `--check` in CI                   | 241 entries |
| `src/signed.ts`                               | `helpers/signed.cairo`'s `SignedTrait`: `bits8`, `from8`, `bits16`, `from16`, the two's complement of an `i8` and an `i16`                                                                                                                                                                                                                                                                                                                                                                                                                  | `signed.test.ts`                  | —           |
| `src/felt.ts`                                 | `P`, the integer types (`u8` … `u128`, `i8` … `i32`) with Cairo's panics, truncating division, signed felts, short strings                                                                                                                                                                                                                                                                                                                                                                                                                  | —                                 | —           |

The functions keep the Cairo names and argument order (`sight(open, from, to)`, `arc(source,
target, facing)`, …): `number` for positions, facings and ranges, `bigint` for felts, bitmaps and
the integers of a hit. A Cairo panic is a thrown `CairoPanic` carrying its short strings.

A packing guard that panics in Cairo (`join`'s high limb, `fits`, `pack_bitmap`) throws its
`CairoPanic`; the table records it as a refusal (`[0, result…]` accepted, `[1]` refused), and its
adapter in `src/parity/tables.ts` turns only that guard's own panic into `[1]`.

## The segment and its classes

`run` calls three classes: `TickLibrary::ticks`, `ActionLibrary::act`, `TrapLibrary::trigger`.
They go through one seam, `Classes` (`src/segment/classes.ts`). `run` computes each call's inputs
itself and passes them through it, then loads the words and the ground the class returns, as
`SegmentTrait::reload` does. A trap writes back the members, and the placer goblin of a placed
trap.

**Native**, as `run` holds them:

- the loop and its stops;
- Move: open, occupied by a living member or goblin, Crippled, a held `MOVEMENT` effect;
- Turn and Wait, the followed window;
- the trap lookup (`AiTrait::armed`) and the words it sends;
- `idle`'s choice and the fast path (`TickTrait::idle`): the clock, the flags, the members'
  regeneration out of combat (`MemberTickTrait::regenerate`: health, energy, adrenaline), the
  defeat check;
- `fits`' goblin records.

**Behind the seam**: the three classes. `segment2.jsonl`'s rows are replayed by
`src/parity/replayer.ts`, which is test scaffolding and is never exported by `src/index.ts`. At
each call it checks the kind and the Poseidon digest of the inputs `run` computed (the README of
the vectors gives their order), then returns the recorded words and ground. A replay is sound
only if it checks every digest and consumes every recorded call (D-255): a call of another kind,
other inputs, a call the row lacks or a recorded call left unused fails the row, naming the call's
index and kind (`src/parity/replayer.test.ts`).
Lots D to F replace the replayer with ports, class by class; the batch preview needs those ports,
since it predicts batches nobody recorded (D-255). `TrapLibrary::trigger` (lot D) and
`ActionLibrary::act` (lot E) are ported (below): on a `segment2.jsonl` row the replayer still
takes each recorded trap or action call (its kind, its digest, its place in the span), and the
port's result, felt for felt, must equal it; the port's is what `run` loads. `ticks` stays
replayed (lot F).

**Not mirrored**: two branches, which throw `NotMirrored` (`unported`,
`src/segment/unported.test.ts`, `src/action.test.ts`):

- `EDGE`: a Move whose neighbour is missing (`LayoutTrait::neighbor` → `None`, the window's edge).
  `run` never reaches it: the adventurer stands at the window's column 7, and every direction has a
  neighbour.
- `MIXED`: an action's carrier whose entries mix a `TILE` target with an entity one (`FOE`, `ALLY`,
  an attack's hit), or whose first entry addresses `SELF` with a `TILE` entry later (`aim` gives
  it the source's id, which a `TILE` set reads as a tile): below, _The action_. No content of the
  tables holds one.

**A refusal leaves the ground as it was** (D-259, FIX-01): an Attack, a Skill or an Item refused as
Illegal or Heavy restores the words and the ground; `SegmentTrait::combat` takes `ActionLibrary`'s
ground only when the result is kept. Row 44 (an instant trap skill refused as Heavy) holds it, and
the mutant "a Heavy refusal keeps ActionLibrary's ground" is killed by it.

**A class must not mutate its inputs** (CLI-02g-C). A library call receives its inputs serialised;
`run` keeps that true whatever a port does: it passes each call a copy of the words and the ground
(`copyWords`, `copyGround` in `src/segment/classes.ts`; `play.cairo`'s `combat` clones the ground the
same way). No row records an Illegal refusal whose call changed the ground, nor a class that
mutates its inputs: `src/parity/seam.ts` holds those cases, run by `src/segment/unported.test.ts`
and, against each `seam` mutant (the Illegal refusal keeping the call's ground, the ground or the
words passed uncopied), by `src/parity/mutants.test.ts`.

## The `Body` operations

`src/body/` mirrors the operations the executor runs on an actor (CLI-02g-C, D-257), on a member
and on a goblin through one dispatch, as `UnitBody` (`Unit`: `{ kind: "M", member }` or
`{ kind: "G", goblin }`): the reads (`health`, `max_health`, `is_member`, `alive`, `place`,
`knocked`, `asleep`, `halves`, `armor_vs`, `infliction`, `enchant_percent`, `slots`, `effect`) and
the writes (`wound`, `heal`, `energize`, `struck`, `landed`, `halved`, `inflict`, `cure`, `hold`,
`spend`), each in place on the unit, as Cairo's `ref self` (`copyUnit` for a caller that keeps its
input). `src/effect.ts` is the effect entry. `defence` (lot D) and `offence` (lot E) are
`src/executor.ts`'s, held by `act.jsonl`'s `defence` and `offence` rows.
`src/body/serde.ts` reads and writes a unit, a `Held` and an `Infliction` as the table records
them. Lot D (the trap's path) builds on `body/index.ts`, `body/member.ts` (`interrupt`, `hold`,
`put`, `apply`, `knock`), `body/goblin.ts`, `body/infliction.ts` and `effect.ts`.

`body.jsonl`'s rows are its README's: row 0 the content every actor is loaded through, then one
operation a row. Three mutants survive, holes of the table reported to track game: `hold`'s step 1
at a carrier held to exactly `T`; a potion compared by its belt slot rather than its item (the
table's belt holds four different items); a goblin activating caste slot 3, which no knock-down row
reaches. A fourth, the recharge lanes of bar slots 4–7, is killed by `act.jsonl`'s row 44.

**Fail closed** (CLI-02g-B1): `world()` loads each goblin through `GoblinTrait::load`
(`src/segment/goblin.ts`), as `WordsTrait::indexed` does, and panics with Cairo's string where
Cairo panics: a caste not in the content (`tick: caste not in content`), a caste skill or the
effect's skill not in it (`tick: skill not in content`), an effect's regeneration above an `i8`
(`goblin: regeneration above i8`), a max health above a `u16` (`Option::unwrap failed.`), and more
than 8 goblins awake (`tick: more than 8 awake`). No row of `segment2.jsonl` records a refusal, so
the cases are `src/parity/refusals.ts`', hand copies of the Cairo unit tests where they exist, run by
`src/segment/goblin.test.ts` and, against each mutant that drops a refusal, by
`src/parity/mutants.test.ts`. The lifecycle and condition rules of both kinds, the infliction and
the durations are `src/body/`'s (below); the tick's rules (`GoblinTickTrait::regenerate`,
`conclude`, `lapse`, the members' activation) wait for RV-03c.

`segment.jsonl`'s rows hold a simplified adventurer. Their decoder builds its words as the
unit-test fixture's member (max health 480, no regeneration, no effect or skill), and its classes
fail on any call: the table never reaches one.

## The trap's trigger

`src/trap.ts` is `TrapLibrary::trigger`, computed (CLI-02g-D, D-257): `triggerClass` loads the
words through the content, finds the entrant by its entity (`ExecutorTrait::actor`), runs
`TrapTrait::trigger` with a fresh `Cache` and stores the words back; `src/index.ts` exports it as
`trapTrigger`, a `Classes.trigger`. `src/executor.ts` is the executor's path it runs: the payload's
guards on the trap's source, the hit (class `TRAP`, strength `3 × level`, no arc, never blocked or
evaded) on the target's defence through `Levered`'s cache, then the other entries in entry order
while the entrant lives, and the entrant written back (a goblin at 0 killed, in `killed`).
`segment.ts` takes `locate` and `occupied` from it.

`trap.jsonl`'s rows are its README's: row 0 the content, 52 `trigger` rows (one call of the class
each) and 10 `free` rows. `segment2.jsonl`'s trap calls (rows 26, 28, 43) are computed by the port
and equal their recordings (`src/parity/parity.test.ts`).

A trap's one entrant is written back at once (`put` without `pending`, `Naive`'s write); the
action's carrier is below.

Both goblins of the table are Hobs of one caste, so a port reading another goblin's caste than the
placer's passes every row (until RV-03c's row with distinct castes): `src/parity/trapcases.ts`
holds that case, and that the class leaves its inputs as they were, run by `src/trap.test.ts` and,
against each `trap` mutant, by `src/parity/mutants.test.ts`.

Of the trap path's 65 mutants, 39 were killed by `trap.jsonl` and 3 by `trapcases.ts` (another
goblin's kit, rank or level read for the placer's). Since `act.jsonl` (lot E), 10 of the 22
survivors are killed by its rows: `strike`'s block spend (205), the knocked-down (209) and sleeping
(211) target, a trap's damage of no type (`offence` 185), the cached and the expired defence (159,
161, 173), an `ARMOR` effect below 0 (164), a `HEAL` and a holding entry (44, 215). 12 survive.
Nine are holes of `trap.jsonl`, reported to track game: a position, a chunk column or a chunk row
past the location landing on a chunk no row's ground holds (rows 42, 47, 48); `locate`'s guard of a
tile West of `ORIGIN`, which Cairo has too, not killed by any row (RV-03a2); no goblin placer's
payload guarded; no entrant holding an `ARMOR` effect on a trap's hit; no payload's entry other than
its hit guarded; no payload with a `CURE` entry; no dead goblin entering. The block's cap at 63
cannot be reached through `act`: `act` strikes goblins only, whose charges are 6 bits (at most 63,
rows 213 and 214); a member's (7 bits) passes 63 only under a goblin's hit, the ticks' (lot F). Two
are equivalent on the trap path: `trap`'s and `entries`' checks of a dead entrant mask each other.
One is equivalent outright, marked `equivalent`: the same guard's South half, whose chunk is below
0, which no ground holds.

## The action

`src/action.ts` is `ActionLibrary::act`, computed (CLI-02g-E, D-257): `actClass` loads the words
through the content, runs `ActionTrait::act` for member 0 with `Delegate`'s rules and a fresh
`Cache`, and returns the words stored back (or the words as they came on a refusal), the ground and
the `Result`; `src/index.ts` exports it as `actionAct`, a `Classes.act`. `act` is the legality in
its order (the clock, the adventurer, knocked down, then each arm's: Turn's flag; the skill's
`Empty`, `Kind`, `Instant`, `Recharging`, `Adrenaline`, `Energy`, `aim`'s `Target` and `Reach`,
`Trap`; the item's `Empty`, `Belt`, `aim`), the costs at once (energy after _Fieldcraft_ and the
glyphs, consumed; adrenaline; the quick-cast counters; the belt's count), the facing, and the
carrier now (`carry`) or an activation started (`A = c + n`), with its tick cost.

`carry` is `Delegate`'s: a `TRAP` carrier is placed in the ground (`trap.ts`'s `spot`, `place`,
`placer`) if its guard holds, before any sub-world; any other runs through `executor.ts`'s
`execute`, on the whole world. That is equal to the sub-world for carriers whose entries share a
target kind; a mixed-target carrier is not mirrored. `Delegate` picks the sub-world's goblins (the
addressed one, those within one tile of the source and the address) by the carrier's first entry,
where `actors` centres each entry's set by its own target: a `TILE` set beside an entity one
(`FOE`, `ALLY`, an attack's hit), or beside a carrier addressing `SELF`, reads the address as the
other kind and may reach a goblin the sub-world does not hold (review t-0209). `action.ts`'s
`mixed` refuses those with `NotMirrored` (`unported.MIXED`); `SELF` with `FOE` or `ALLY`, `FOE`
with `ALLY`, and `TILE` first with `SELF` later stay mirrored. `src/parity/actcases.ts` holds the refused shapes (a `TILE` hit then a `FOE`
or an `ALLY` condition; the reverse, an order `assert_carrier` refuses, `HIT_NOT_FIRST`; a `SELF` hit then a
`TILE` condition) and the kept ones, each run against its expected result (a `SELF` disc hit then a
`FOE` condition; a `TILE` disc hit then a `SELF` condition; a `FOE` hit then an `ALLY` condition),
run by `src/action.test.ts` and, against the `act` mutants of `mixed` (its guard, its `SELF` arm,
and two that refuse a kept shape), by `src/parity/mutants.test.ts`. `execute` is §5.14: the
carrier's entries (`read`), their guards, each entry's `Op`, the hit modifiers (`modifiers`), the
target sets (`actors`: every set's shape on its centre, the actors its filter takes, ascending
position; a carrier of `SINGLE` entries reads its source and the addressed entity alone), the
source's terms (`offence`: a member's weapon, passives and held `PENETRATION`, a goblin's caste
weapon; `penetration`, `attack`), each actor in order (`on`: the hit, then the other entries), the
source's side of a landed weapon hit, and each actor written back, a carrier's awake goblins
gathered into one write of the awake set (`put` with `pending`, `flush`: `Levered`'s lever). Not
here: `conclude` and `legal` (an activation's end) and the goblins' acts (lot F).

`act.jsonl`'s rows are its README's: row 0 the content, 175 `act` rows (one call of the class
each), 19 `defence` and 28 `offence` rows (`Body::defence`, `Body::offence` through `UnitBody`). On
a refusal the words and the ground are the case's, felt for felt. `segment2.jsonl`'s `act` calls
(rows 1 to 11 and 44) are computed by the port and equal their recordings
(`src/parity/parity.test.ts`). The liveness reads are the class's own: `locate` reads a goblin's AI
state and health, `TrapTrait::occupied` and a wide carrier's candidates its AI state alone (rows
217 to 222 hold goblins dead by one field only).

Of the action's 154 mutants, 130 are killed by the tables and 5 by `actcases.ts` (`mixed`'s guard,
its `SELF` arm, the `ALLY` one that makes a `TILE` then `ALLY` carrier run on the whole world, and
two that refuse a kept shape: `TILE` counted with `ALLY`, and `TILE` first with `SELF` later
refused; the third such mutant, `SELF` counted as a `TILE` one, is killed by the tables, not by
`actcases.ts`). `mixed`'s attack arm (`let entity = attack`) has no test: it is defence in depth.
`assert_carrier`'s `ATTACK_ENTRY` keeps an attack's entries `FOE` + `SINGLE`, so legal content
never holds an attack with a `TILE` entry, and no case reaches the arm. 16 survive, holes of `act.jsonl`
reported to track game: no attack skill on a slot other than 0 with that slot's (or slot 0's)
weapon-required bit alone; no negative `NEXT_SPELL_COST`; no spell counting for a quick-cast pair
from a bar slot above 0; no `act` row landing an attack skill with passives or a held
`PENETRATION`; no `ATTACK_BONUS` or `HIT_PENETRATION` entry; no `PENETRATION` of scope `ALL` held
(two mutants); no `ON_ATTACK_CONDITION`; no `act` row with `LIFE_STEAL_ON_HIT` or `ENERGY_ON_HIT`
(only `offence` row 182 reads them); no hit whose filter takes the source's side; no `SINGLE`
`TILE` entry reaching an actor; no wide carrier near a member at 0 health; no two actors of a
carrier whose index order is not their position order; no carrier holding a hit and another entry
whose set holds an actor the hit's does not. Three are `equivalent`: a refusal's words stored back
(every refusal comes before any write, and a store of a load gives the words back); the awake
goblins written at once rather than gathered (the mirror's world is one array); a trap placed on a
wall (through `act`, `aim`'s reach refuses a walled tile first).

## Where the vectors come from

The tables are printed by the tests of `grimworld_logic` and kept in `contracts/logic/vectors/`
(their format is its README); CI's `contracts` job runs `check.py`, which fails while a table
differs from what the code prints. The harness (`src/parity/`) reads them **in place**, never a
copy: CI's `client` job replays every table on every pull request, so a change of a rule on either
side fails until both agree.

- `src/parity/table.ts`: `readTable(name)`, the reader; it fails loudly on a malformed line, a
  felt not in hexadecimal, ids not consecutive from 0, an empty table. A case that panics carries
  `err` (its panic data) or `"ok": false`.
- `src/parity/replay.ts`: `replay(entry, vectors)` calls the mirror per `fn` and compares the whole
  `ok` (or the panic); it fails with the case's id on any divergence, an unknown `fn`, a count under
  the table's floor.
- `src/parity/mutants.test.ts`: the mutation check. Each mutant is one typical mistake applied to
  the mirror; the vectors must kill it. A mutant that survives is listed with `survives` (what
  the tables lack) and reported to track game: the tables are never edited from here. A kill by a
  crash (a TypeError, a ReferenceError, a stack overflow) must say with `crash` why the crash is
  the mutant's own divergence; otherwise it fails, as a broken mutant. A mutant no input tells
  from the mirror is marked `equivalent`: neither the tables nor the unit tests' cases may kill it. The mutants run in a pool of at most four
  worker threads (`src/parity/mutate.ts`), each a few dozen mutants then a fresh one: no copy is
  written, a module hook serves the mutated file and the modules that import it from memory, and
  the modules the mutant does not reach are loaded once per worker and shared.

## How to add a table

One entry of `TABLES` in `src/parity/tables.ts`: the file name, its floor (the cases it holds),
and the mirror's function per `fn` (`""` for a table without `fn`), adapting a case's felts to the
mirror's arguments and its result to Cairo's `Serde`. Then add a mutant or more for the rule.

## Commands

```
pnpm --filter @grimworld/sim test        # the unit tests, the parity and the mutation check
pnpm --filter @grimworld/sim bench       # the measurements (Poseidon, the replay), printed only
```
