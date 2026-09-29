# [Sonnet 5.5] ENG-02a — The fixed-point table of `2^(x/40)`

## Summary
One generator writes the 241-entry table (`round(2^16 × 2^(x/40))`, exact integer rounding as SPK-4) to the contracts and the client; `--check` runs in CI. `grimworld_logic` gains `helpers/` with `Exp2::at(x)` (clamps to [−160, +80]); `client/sim` gains `exp2(x)`. The model named by the brief and the one that ran agree (Sonnet 5.5).
PR: https://github.com/bal7hazar/grimworld/pull/113 (CI green: all jobs pass).

## Files changed
- `contracts/tools/exp2_table.py`: generator and `--check`.
- `contracts/logic/src/helpers.cairo`, `helpers/exp2.cairo`, `helpers/exp2_table.cairo` (generated): the module, the `Exp2` trait, `Exp2Assert`, `mod errors`, the table.
- `contracts/logic/src/lib.cairo`: `pub mod helpers;`.
- `contracts/logic/tests/test_exp2.cairo`: 7 tests.
- `client/sim/src/exp2.ts` (generated), `exp2.test.ts`: table, lookup, Vitest.
- `.github/workflows/ci.yml`: one step, `exp2 table is current`.
- `docs/BUDGETS.md`, `contracts/logic/GAS.md`: regenerated.

## Commands run
- `python3 contracts/tools/exp2_table.py --check` → `241 entries, both files current`. After appending a line to `client/sim/src/exp2.ts`: `stale or edited, run python3 contracts/tools/exp2_table.py: client/sim/src/exp2.ts`, exit 1; regenerated (reverted), exit 0.
- `scarb build` (contracts), `scarb fmt --workspace`, `snforge test test_exp2`: pass.
- `python3 scripts/gas_budgets.py --check` → `111 tests, every budget is ceil(1.05 x measured) or lower, 4 files current`.
- `pnpm -r test` (sim 7 tests, app 43), `pnpm -r lint`, `pnpm -r typecheck`, `pnpm exec prettier --check client`: pass.

### Representations measured (l2 gas, a lookup at a runtime index, minus the bare call, 14420)
| Representation | first / mid / last index | Above the bare call |
|---|---|---|
| constant `[u32; 241]`, `span().at(i)` | 15690 / 15690 / 15690 | ~1270 |
| `match` of 241 arms | 15790 / 15790 / 15790 | ~1370 |
| 4 × u32 lanes per u128, div_rem twice | 22730 / 22730 / 22730 | ~8310 |

Chosen: the constant array, the cheapest and the plainest (no lane arithmetic, no 241-arm code). The scratch measurement file was deleted; figures are not in the repository.

### Parity (AC-2)
- Cairo `test_every_entry_and_clamp`: x from −200 to +120 against a literal list computed by another method (`Decimal` at 80 digits, round half even), which equals the generator's table entry for entry (asserted when produced). Plus exact octaves and both clamps.
- Vitest: x from −200 to +120 against an exact bigint search `(2v−1)^40 ≤ 2^(680+x)`, independent of the generator, plus length, octaves, a few entries, clamps.

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| grimworld_logic::test_exp2::test_assert_covered | — | 13720 | 14406 | new |
| grimworld_logic::test_exp2::test_assert_covered_above_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_exp2::test_assert_covered_below_refused | — | 15520 | 16296 | new |
| grimworld_logic::test_exp2::test_bench_lookup | — | 19160 | 20118 | new |
| grimworld_logic::test_exp2::test_clamp_ends | — | 20850 | 21893 | new |
| grimworld_logic::test_exp2::test_every_entry_and_clamp | — | 2901800 | 3046890 | new (321-x sweep) |
| grimworld_logic::test_exp2::test_octaves_exact | — | 23960 | 25158 | new |

## Acceptance criteria
- AC-1: generator, deliberate edit failing `--check`, CI step. Done.
- AC-2: the two parity tests above. Done.
- AC-3: the table of representations. Done.
- AC-4: `Exp2` trait (`Exp2::at`), `Exp2Assert of AssertTrait`, `mod errors`; the only free item is the generated constant table `EXP2_X40`, with its reason written in the file.
- AC-5: CI green; the local commands above.

## Deviations from the brief
- The generator also writes the lookup function into `exp2.ts` (the whole file is generated), so the TypeScript clamp cannot drift either.
- The TS table is one bigint per line, the way prettier formats it; the Cairo one is packed as `scarb fmt` does.
- `Exp2Assert::assert_covered` (strict range check) is provided for callers that must not clamp; nothing calls it yet.

## Escalations
None.

## Open questions
- Is `Exp2::at` returning `u32` what CBT-03 wants, or should it take/return the `u16` types of damage? Left as `u32` (the table's width).

## Fix loop 1
Audit `[GPT-6-Astra]` of PR 113 at 115dabc: PASS WITH FINDINGS. Fixed in 941dd88 (origin/main merged first; CI green on the PR, all jobs pass).

- **Finding 1 (minor), `--check` compared normalised text.** `contracts/tools/exp2_table.py` now encodes both outputs as UTF-8, reads the files in binary and compares bytes, and writes those same bytes. Deliberate edits, each reverted afterwards (`git checkout` for the committed file, then a regeneration; a final `--check` exits 0):
  - `client/sim/src/exp2.ts` with every LF turned into CRLF: `--check` exit 1, names the file.
  - the same with CR: exit 1.
  - `contracts/logic/src/helpers/exp2_table.cairo` with CRLF: exit 1, names the file; with CR: exit 1.
  - Regenerated files: `--check` exit 0, `prettier --check client` passes. No automated regression test of the newline mutation was added (the brief asked for the demonstration only); the demonstration above is the evidence.
- **Note 2, integer x only.** The emitted doc of `exp2` in `exp2.ts` now says `x` is an integer like the contracts' `i32`; a non-integer, NaN or infinite `x` throws a `RangeError`. New Vitest test covers 0.5, −159.5, NaN and Infinity (sim: 8 tests pass). lint, typecheck pass.
- **Note 3:** nothing needed, as instructed.

The Cairo side is unchanged, so its gas figures and `docs/BUDGETS.md` are unchanged.
