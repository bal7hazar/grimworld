# [Sonnet 5.5] FND-06 — Gas tooling

## Summary
`scripts/gas_budgets.py` enforces docs/CAIRO.md §2 by tool: it runs the contracts workspace tests through the lock, reads the l2 gas snforge measured per test and each test's `#[available_gas(l2_gas: N)]` from the sources, then writes `docs/BUDGETS.md` and a `GAS.md` per package (`contracts/{logic,persistent,ephemeral}/GAS.md`), `--check`s them, or prints the REPORT gas table (`--report`). The CI's `cairo (contracts)` job runs `--self-test` and `--check --no-lock`. Model matches the brief (Sonnet 5.5). PR: https://github.com/bal7hazar/grimworld/pull/42

Rules implemented: a test without budget fails; a budget above ceil(1.05 × measured) (integer math) fails; a budget below is accepted (lowering needs nothing; a test over its budget already fails in snforge, and the script aborts on any FAIL); a generated file that differs from disk is stale; a non-ignored `#[test]` not measured by the run fails. Date and commit per row are provenance: a row keeps its date/commit while measure and budget are unchanged, else takes the committer date and short hash of the merge base of HEAD and origin/main (survives a squash merge), which makes reruns byte-identical.

Opt-in: a package is covered by being a member of the workspace passed as `--workspace` (default `contracts/`); a spike workspace would use `--workspace <dir> --budgets <file>`.

## Files changed
- `scripts/gas_budgets.py` — new script (rewritten in fix loop 1, with `--self-test`)
- `docs/BUDGETS.md` — generated (header now states the fuzz/test_case/ignored/provenance rules)
- `contracts/logic/GAS.md`, `contracts/persistent/GAS.md`, `contracts/ephemeral/GAS.md` — generated
- `.github/workflows/ci.yml` — one step `gas budgets` after `test`, contracts job only (fetches origin/main and the history, runs `--self-test` then `--check`)

## Commands run
- `python3 scripts/gas_budgets.py` twice: sha256 of the four files identical (`sha256sum -c` OK on the second run).
- `python3 scripts/gas_budgets.py --check` → `gas check: 3 tests, every budget is ceil(1.05 x measured) or lower, 4 files current` (exit 0).
- Throwaway changes, each `--check` exit 1, each reverted:
  - budget line removed: `no #[available_gas(l2_gas: N)]`
  - budget 14406 → 20000: `budget 20000 is loose, measured 13720 allows 14406`
  - figure edited in docs/BUDGETS.md: `docs/BUDGETS.md is stale against the run`
- `python3 scripts/gas_budgets.py --report` printed the table below (before = `origin/main:docs/BUDGETS.md`, absent today, hence "—"/new).
- CI: green run on the PR (https://github.com/bal7hazar/grimworld/actions/runs/36479829076); throwaway commit removing the budget: red, https://github.com/bal7hazar/grimworld/actions/runs/36479954106 (log: `gas check: grimworld_logic::test_hexmap::test_hexmap_distance: no #[available_gas(l2_gas: N)]`); restore commit: green, https://github.com/bal7hazar/grimworld/actions/runs/36480084077. The throwaway and its restore are two commits in the branch history (no force-push).

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_ephemeral::test_ephemeral::test_ephemeral_deploys_and_answers_version | — | 277140 | 290997 | new |
| grimworld_logic::test_hexmap::test_hexmap_distance | — | 13720 | 14406 | new |
| grimworld_persistent::test_persistent::test_persistent_deploys_and_answers_version | — | 277140 | 290997 | new |

## Acceptance criteria
- AC-1 met: two runs, identical bytes.
- AC-2 met: three failure modes shown, tree passes.
- AC-3 met: red run linked above, then reverted and green.
- AC-4 met: `--report` prints COMMON §7's `| Entrypoint or algorithm | Before | After | Budget | Note |` table, before from `origin/main`.

## Deviations from the brief
- The check reruns the tests in the CI (a second `snforge test --workspace`, compiled already, seconds) rather than parsing the `test` step's output, since only the check step could be added.
- The script carries its own `--self-test` (added in fix loop 1, 10 tests after fix loop 2; fixtures of snforge output lines and Cairo sources, plus a throwaway git repository for the provenance rule), which the CI runs before `--check`. The CI step also fetches origin/main and unshallows the checkout, which the raise and provenance rules need.

## Escalations
- None open. The COMMON §7 change (`--report`) and the CAIRO §2 wording for fuzz/parameterized budgets and the raise gate were made by the orchestrator on main (52265e5), merged into this branch.
- The script reads only l2 gas. Fuzz tests are supported (maximum over the runs, `--fuzzer-seed 1`), and so are `#[test_case]` cases.

## Open questions
- Once a lot with a new/changed budget merges, "before" in `--report` comes from `origin/main`'s BUDGETS.md; a lot that must be measured before its BUDGETS.md is regenerated needs the file regenerated in the same PR (the CI's stale check enforces it).

## Fix loop 1
CI green on d4bc186: https://github.com/bal7hazar/grimworld/actions/runs/36482277101 (contracts job runs `--self-test` then `--check`). Local `--check`: `gas check: 3 tests, every budget is ceil(1.05 x measured) or lower, 4 files current`; `--report` prints the table above (baseline absent at origin/main, said on stderr). Snforge is now run with `--fuzzer-seed 1` (the `seed:` attribute did not make the fuzz max reproducible in my probe).

1. Full-path keys (`package::module::test`, inline `mod` nesting followed by brace tracking; declarations checked one by one, duplicates reported). Throwaway `tick.cairo` with `tests::test_unit_probe` (budget) and `tests::deep::test_unit_probe` (none), both measured: `gas check: grimworld_logic::tick::tests::deep::test_unit_probe: no #[available_gas(l2_gas: N)] (contracts/logic/src/tick.cairo)`, the other not flagged. Also `--self-test` `test_same_name_other_module_is_rejected`, `test_unmeasured_twin_is_not_hidden`. Removed.
2. Fuzz lines parsed (`runs: N, (... l2_gas: {max: ~M ...`), figure = max; `#[test_case]` cases mapped to their source function (each case a row, count of cases must equal count measured; the budget is the function's). Throwaway `tmp_probe.cairo` with a `#[fuzzer]` test and two `#[test_case]`: BUDGETS.md rows `tmp_probe::test_fuzz_probe | 90360 | 94878`, `tmp_probe::test_sum_1_2_3 | 13720 | 14406`, `tmp_probe::test_sum_4_5_9 | 13720 | 14406`, no problem reported. Rule written in the script's help and in the BUDGETS.md header. Removed.
3. Every declared test needs the attribute, `#[ignore]`d included; ignored rows say `ignored`. Same probe: `gas check: grimworld_logic::tmp_probe::test_ignored_probe: no #[available_gas(l2_gas: N)]`; row `tmp_probe::test_ignored_probe | ignored | — |`. Removed.
4. Raise check against origin/main's BUDGETS.md with the `// gas: raised, <reason>` comment above the attribute; `--report` Note shows `raised: <reason>; ...`. **Not shown on the real tree**: origin/main has no BUDGETS.md yet, so there is no baseline to raise from; shown by the self-test `test_raise_needs_a_reason` (`budget raised 500 -> 1050 without a ...` and the reasoned raise passing with `raised` set).
5. Multiline `#[available_gas(\n l2_gas: 14406\n)]` is read (probe `test_sum` above uses it, and the self-test). Choice: cfg gates other than `cfg(test)` are **not evaluated**; their tests are listed and not checked unless the run measured them: `gas: grimworld_logic::tmp_probe::gated::test_gated: cfg-gated, not checked` (probe with `#[cfg(feature: 'nope')]`, snforge does not collect it).
6. Retained date/commit verified (`git cat-file -e`, `git show -s --format=%cs`). With the commit column edited to `deadbee`: `gas check: grimworld_logic::test_hexmap::test_hexmap_distance: date 2026-09-28 / commit deadbee do not verify (commit missing from the history, or its committer date differs)`. Reverted. Changed rows are stamped with the merge base of HEAD and origin/main rather than HEAD, so the commit stays in main's history after a squash merge. The CI job fetches origin/main and unshallows for this.
7. `--report` fails on collection problems (throwaway test without budget: `gas report: grimworld_logic::tmp_nobudget::test_nobudget: no #[available_gas(l2_gas: N)]`, exit 1; removed). Baseline states are distinguished: absent file at origin/main prints `gas: docs/BUDGETS.md is absent at origin/main: empty baseline`; a git error exits 1 (with GIT_DIR pointing nowhere: `1  git: origin/main is not known here (git fetch origin main)`). In write mode a missing baseline only warns.
Self-test: `python3 scripts/gas_budgets.py --self-test` → `Ran 9 tests ... OK` (fixtures held in the script, no Scarb).

## Fix loop 2
origin/main merged into the branch (`git merge origin/main`, 125b9bb). CI green on f5a8844: https://github.com/bal7hazar/grimworld/actions/runs/36484279674 (all jobs pass).

- **N1** One budget per fuzz test or `#[test_case]` function, N = ceil(1.05 x the most expensive): the check was already per function against the maximum over its cases (`top = max(...)`); the script's help and the BUDGETS.md header now say exactly that (`A fuzz test or a #[test_case] function has one budget for all its runs or cases: N = ceil(1.05 × the most expensive)`).
- **4** The raise gate is unchanged (`// gas: raised, <reason>` plus the orchestrator's review of the raised notes in `--report`), as settled on main.
- **5** Every declared test carries its budget, cfg-gated included; a gated test the run does not measure is listed as `cfg-gated, not measured (only its budget attribute is checked)`. Throwaway `tests/tmp_gated.cairo` with `#[cfg(feature: 'nope')]` and two tests, one without budget: `python3 scripts/gas_budgets.py --check` gave `gas check: grimworld_logic::tmp_gated::gated::test_gated_nobudget: no #[available_gas(l2_gas: N)] (contracts/logic/tests/tmp_gated.cairo)` and, as lines, `gas: grimworld_logic::tmp_gated::gated::test_gated_budget: cfg-gated, not measured (only its budget attribute is checked)` (the one with a budget is not a problem). Removed. Self-test `test_cfg_gated_needs_a_budget`.
- **6** `provenance_ok` now also requires `git merge-base --is-ancestor <commit> origin/main`. With the commit column of the hexmap row edited to `125b9bb` (a branch commit whose committer date, 2026-09-28, matches): `gas check: grimworld_logic::test_hexmap::test_hexmap_distance: date 2026-09-28 / commit 125b9bb do not verify (commit missing from the history, or its committer date differs)` (exit 1). Restored to `5267868` (an ancestor of origin/main); `--check` → `gas check: 3 tests, every budget is ceil(1.05 x measured) or lower, 4 files current`. Self-test `test_provenance_needs_an_ancestor_of_main` builds a throwaway repo with a main commit and a branch commit of the same date: main commit accepted, branch commit, wrong date and unknown commit refused.
- Self-test: `python3 scripts/gas_budgets.py --self-test` → `Ran 10 tests ... OK`.
- The generated files changed only in the header sentence of BUDGETS.md (rows and figures identical).
