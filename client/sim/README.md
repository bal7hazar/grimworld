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
since it predicts batches nobody recorded (D-255).

**Not mirrored**: two branches, which throw `NotMirrored` (`unported`,
`src/segment/unported.test.ts`):

- `EDGE`: a Move whose neighbour is missing (`LayoutTrait::neighbor` → `None`, the window's edge).
  `run` never reaches it: the adventurer stands at the window's column 7, and every direction has a
  neighbour.
- `HEAVY_GROUND`: an Attack, a Skill or an Item refused as Heavy whose `act` call changed the
  ground. `run` keeps that ground (an instant trap skill keeps its placed trap), a bug that game
  fixes after RV-02 by restoring the input ground. When the call left the ground unchanged,
  keeping and restoring agree, and the mirror goes on. No `segment2.jsonl` row reaches the throw.

**Fail closed** (CLI-02g-B1): `world()` loads each goblin through `GoblinTrait::load`
(`src/segment/goblin.ts`), as `WordsTrait::indexed` does, and panics with Cairo's string where
Cairo panics: a caste not in the content (`tick: caste not in content`), a caste skill or the
effect's skill not in it (`tick: skill not in content`), an effect's regeneration above an `i8`
(`goblin: regeneration above i8`), a max health above a `u16` (`Option::unwrap failed.`), and more
than 8 goblins awake (`tick: more than 8 awake`). No row of `segment2.jsonl` records a refusal, so
the cases are `src/parity/refusals.ts`', hand copies of the Cairo unit tests where they exist, run by
`src/segment/goblin.test.ts` and, against each mutant that drops a refusal, by
`src/parity/mutants.test.ts`. `GoblinTrait`'s tick, lifecycle and condition rules, and the members'
(`MemberTickTrait`, `MemberLifecycleTrait`, infliction, durations) have no oracle before RV-03:
they are lot B's remainder.

`segment.jsonl`'s rows hold a simplified adventurer. Their decoder builds its words as the
unit-test fixture's member (max health 480, no regeneration, no effect or skill), and its classes
fail on any call: the table never reaches one.

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
  a copy of `src/`; the vectors must kill it. A mutant that survives is listed with `survives` (what
  the tables lack) and reported to track game: the tables are never edited from here.

## How to add a table

One entry of `TABLES` in `src/parity/tables.ts`: the file name, its floor (the cases it holds),
and the mirror's function per `fn` (`""` for a table without `fn`), adapting a case's felts to the
mirror's arguments and its result to Cairo's `Serde`. Then add a mutant or more for the rule.

## Commands

```
pnpm --filter @grimworld/sim test        # the unit tests, the parity and the mutation check
pnpm --filter @grimworld/sim bench       # the measurements (Poseidon, the replay), printed only
```
