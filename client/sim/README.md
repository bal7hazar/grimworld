# `@grimworld/sim`

The client's simulation core (ADR-0003): a TypeScript mirror of the rules the chain decides, so
that the client predicts what the chain computes, bit for bit (D-140, option (a) of SPK-4). Pure:
no rendering, no chain access, no randomness, no clock, no I/O (mandate §6), except the tests and
the harness's reader.

## What is mirrored

| File              | Cairo                                                                                                                                                                                                                                                                                                     | Vector table     | Cases       |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- | ----------- |
| `src/window.ts`   | `WindowTrait` (`contracts/logic/src/types/window.cairo`, ENG-02)                                                                                                                                                                                                                                          | `window.jsonl`   | 2,065       |
| `src/hit.ts`      | `HitTrait::resolve` and the `Serde` of `Hit`, `HitTarget`, `HitOutcome` (`types/hit.cairo`, CBT-03a)                                                                                                                                                                                                      | `hit.jsonl`      | 203         |
| `src/fate.ts`     | `fate::domain`, `fate::derive` and the purposes (`contracts/logic/src/fate.cairo`), Poseidon through `@scure/starknet`                                                                                                                                                                                    | `fate.jsonl`     | 227         |
| `src/packing.ts`  | `contracts/logic/src/packing.cairo`: `split`, `limbs`, `join`, `peel`, `fits`, the field readers, `Lanes32`, `Lanes16`, `Counter`, `Bitmap`                                                                                                                                                               | `packing.jsonl`  | 520         |
| `src/movement.ts` | the moves of a played batch (ENG-07, CLI-02c): the window's board around the adventurer (`SegmentTrait::board`, `BoardTrait::position`, `AssemblyTrait::origin`), a Move's ticks (`TickMathTrait::move_ticks`), the tick's flood (`Bfs::flood`, `FloodTrait`) and step 0's awake set (`TickTrait::awake`) | `movement.jsonl` | 94          |
| `src/exp2.ts`     | `helpers/exp2.cairo`'s table, generated for both sides by `contracts/tools/exp2_table.py`                                                                                                                                                                                                                 | `--check` in CI  | 241 entries |
| `src/felt.ts`     | `P`, the integer types (`u8` … `u128`, `i8` … `i32`) with Cairo's panics, truncating division, signed felts, short strings                                                                                                                                                                                | —                | —           |

The functions keep the Cairo names and argument order (`sight(open, from, to)`, `arc(source,
target, facing)`, …): `number` for positions, facings and ranges, `bigint` for felts, bitmaps and
the integers of a hit. A Cairo panic is a thrown `CairoPanic` carrying its short strings.

A packing guard that panics in Cairo (`join`'s high limb, `fits`, `pack_bitmap`) throws its
`CairoPanic`; the table records it as a refusal (`[0, result…]` accepted, `[1]` refused), and its
adapter in `src/parity/tables.ts` turns only that guard's own panic into `[1]`.

Not yet mirrored: the reveal of a chunk (CLI-02b, ENG-05).

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
