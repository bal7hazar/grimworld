# ENG-02a — The fixed-point table of `2^(x/40)`, for the contracts and the client

> Phase 1. The part of ENG-02 that does not wait for the map library: D-140's table. ENG-02's line
> of sight and arcs follow the library (LIB-05); its packer is ENG-01's `packing` and its seeder
> FND-05's `derive`.

## Agent
Title: `[Sonnet 5.5] ENG-02a exp2 table` · Profile: implement · Branch: `feat/eng-02a-exp2-table`

## Goal
After this task the damage formula's `2^(x/40)` is **one table, generated once**, read by the
contracts (`grimworld_logic`) and by the client's simulation (`client/sim`), with a CI check that
both copies are current and identical. CBT-03 (damage) and CLI-02 (the mirror) build on it.

## Context
- **design/04** *Damage formula* (`damage = base × 2^((strength − armor) / 40)`; the table for
  `x ∈ [−160, +80]`, out-of-range values clamp; no floating point, no runtime exponentiation, no
  `u256`) and *Edges* (**D-140**: 16 fractional bits, each entry rounded to nearest, generated once
  for the contracts and the client).
- **SPK-4** (`spikes/SPK-4/gen_table.py`, `ts/table.ts`, `cairo/logic/src/damage.cairo`; research
  `docs/research/SPK-4-parity.md`): the generator with exact integer rounding, and how the spike
  laid the table out in Cairo and TypeScript. Start from it; the spike's code is not production
  code.
- **docs/CAIRO.md** in full, **§7 and §8 (D-143)**: the table is a helper, in `helpers/`, scoped in
  a trait with a short name (for example `Exp2::at(x)`), its checks in an `Assert` impl, a `mod
  errors`; no free function without a written reason (a constant table may be one: say so).
  COMMON.md.

## Scope
- In:
  - **The generator**, `contracts/tools/exp2_table.py`: 241 entries, `round(2^16 × 2^(x/40))` by
    exact integer rounding (as the spike), written to both targets; `--check` exits non-zero if
    either generated file differs from what it would write.
  - **Cairo**: `grimworld_logic` gains `helpers/exp2.cairo` (and the `helpers` module if it does
    not exist yet): the table, and a lookup that clamps `x` to `[−160, +80]` (D-140: never a panic
    on a legal action). Choose the representation by measured gas (a `felt252` array, packed
    lanes, or a `match`): measure at least two and say why. Tests: every entry against values
    computed independently in the test, the clamp at both ends, and gas budgets.
  - **TypeScript**: `client/sim/src/exp2.ts`, the same table and the same clamp, with Vitest tests
    (a few entries, both clamps, the length).
  - **CI**: one step in `.github/workflows/ci.yml`, `python3 contracts/tools/exp2_table.py --check`.
- Out: the damage formula itself and its modifiers (CBT-03), line of sight and arcs (ENG-02), the
  parity harness (CLI-02).
- Allowlist: `contracts/tools/exp2_table.py`, `contracts/logic/src/helpers/**` and the `mod` lines
  that declare it, `contracts/logic/tests/`, `client/sim/src/exp2.ts` and its test, one step in
  `.github/workflows/ci.yml`, `contracts/logic/GAS.md` and `docs/BUDGETS.md` as generated. Anything
  else is an escalation.

## Acceptance criteria
- [ ] AC-1 One generator writes both tables; `--check` fails on a stale or edited copy (shown by a
      deliberate edit in the report, then reverted) and runs in CI.
- [ ] AC-2 The Cairo lookup and the TypeScript lookup return the same value for every `x` in
      `[−200, +120]` (the clamp included): shown by a test on each side against the generator's
      output.
- [ ] AC-3 The Cairo representation is chosen by measured gas, with the figures.
- [ ] AC-4 D-143: the helper is scoped; any free function or constant table left free has its
      written reason.
- [ ] AC-5 CI green; `python3 scripts/gas_budgets.py --check`; `pnpm -r test`, lint, typecheck.

## Audits
Determinism and parity: **`[GPT-6-Astra]`** (OPERATIONS §2), with the organisation lens of CAIRO §8.

## Verification
From the worktree root:
```
python3 contracts/tools/exp2_table.py --check
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
(cd contracts/logic && snforge test)
python3 scripts/gas_budgets.py --check
pnpm -r test && pnpm -r lint && pnpm -r typecheck
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the generator, the representations measured and the
one chosen, the parity check, the gas table of every test.
