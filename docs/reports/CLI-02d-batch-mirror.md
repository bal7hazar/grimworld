# CLI-02d — The batch's stop points in client/sim

Lot CLI-02d, track CV, 2026-10-10. CBT-05d (#407, 1ac4f86) added
`contracts/logic/vectors/batch.jsonl`: 28 cases of where a played batch stops (ENG-07b: E-16's cap
of 16 records, E-1's weight, D-141). This lot mirrors them in `client/sim` and replays the table in
place, as the other mirrors are replayed (`src/parity/`).

## What is mirrored

| `fn` | Cases | Cairo | Mirror |
|---|---|---|---|
| `records` | 14 | `SegmentTrait::admit` (`types/play.cairo`) | `batch.ts`: `admit` |
| `owed` | 8 | `admit` again, with the owed ticks' records added by the Cairo test | `parity/tables.ts`: the row's adapter |
| `reveal` | 6 | `admit` for the Move, then `SegmentTrait::revealed` | `batch.ts`: `admit`, `revealed` |

`batch.ts` holds the two contract functions, with the Cairo names and argument order, and
`MAX_RECORDS` (16) and `CHUNK_WEIGHT` (2). The `u8` sum `cost + firsts` and the `u32` sum of
records overflow as in Cairo; `revealed`'s `2 × chunks` is narrowed to `u8` as `try_into().unwrap()`.

The `owed` and `reveal` rows restate what the Cairo test builds around `admit` (the README of the
vectors says so): the owed records added to the next action's, the records written when no action
follows, and the Move counted before its reveal. That composition is in the adapters of
`src/parity/tables.ts`, not in `batch.ts`: the mirror decides no rule. `SegmentTrait::run`'s own
counting of owed ticks is checked by the contract's `test_play_records_owed_ticks`, not by this
table.

## How the table is replayed

One entry of `TABLES` (floor 28). `parity.test.ts` pins the count of each `fn` (records 14, owed 8,
reveal 6): a case added to the table, or a new `fn`, fails the replay until the mirror follows.
All 28 cases pass.

## Mutants

Nine mutants were added to `src/parity/mutants.test.ts`, one per rule and three of the mirror's own
(review of #408). The table kills all nine; none survives.

| Mutant | Killed by |
|---|---|
| E-16's cap of 17 records | `batch.jsonl` id 1 (records) |
| the 16th record cut (the cap exclusive) | id 0 (records) |
| a first record weighs nothing more (no +1) | id 7 (records) |
| the invocation's first action is bound too (E-21) | id 11 (records) |
| a Move's owed ticks not counted with the next action | id 14 (owed) |
| a reveal's weight taken before the Move, not after | id 22 (reveal) |
| a reveal weighs 3 a chunk | id 22 (reveal) |
| a reveal's weight not floored at 0 | id 24 (reveal) |
| E-1's weight stop dropped from `admit` | id 8 (records) |

The fifth and sixth (the owed ticks, the reveal's weight before the Move) are mutants of the adapters
in `tables.ts`, since the composition they break is the Cairo test's; the other seven mutate `batch.ts`.

## Review fixes (t-0160)

- `admit` computes the u32 sum of records only when `ran`, as Cairo's `&&` short-circuits;
  `admit(0xffffffff, 1, 0, 1, false, 5)` returns 4 and does not panic (`src/batch.test.ts`).
- `revealed` narrows `chunks` to `u8` first, then multiplies in `u8`: 128 to 255 chunks panic
  `u8_mul Overflow`, 256 and more `Option::unwrap failed.` (tested).
- The header of `batch.ts` says it mirrors `admit` and `revealed` only, and lists what a preview still
  needs of `SegmentTrait::run` (a later lot).

## Questions for track game

None: every case was mirrored as written.
