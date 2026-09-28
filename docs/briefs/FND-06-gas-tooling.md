# FND-06 — Gas tooling

## Agent
Title: `[Sonnet 5.5] FND-06 gas tooling` · Profile: implement · Branch: `chore/fnd-06-gas-tooling`

## Goal
After this task the rule of docs/CAIRO.md §2 is enforced by tools, not by memory: every test of
the game's Cairo workspace has a gas budget, the measured figures are written to
`docs/BUDGETS.md` from a test run, the CI fails when a budget is exceeded or a test has none,
and the gas table of a `REPORT.md` is generated rather than typed.

## Context
- **docs/CAIRO.md §2 in full**: every test has a budget `#[available_gas(l2_gas: N)]` with
  `N = ceil(1.05 × measured)`; a budget exceeded is a failed test; benchmarks are tests on the
  worst case; figures in `docs/BUDGETS.md` (per entrypoint and algorithm: measured value, budget,
  date, commit) and a `GAS.md` per package for the detail; reports carry a before/after/budget
  table; raising a budget needs a written reason and the orchestrator's agreement, lowering one
  needs nothing. §6 (what a cost auditor checks).
- OPERATIONS §5 (`docs/BUDGETS.md` is the source of truth for cost budgets; a lot exceeding a
  budget does not merge without an owner decision).
- The workspace (FND-01b): `contracts/` (Scarb workspace: `grimworld_logic`,
  `grimworld_persistent`, `grimworld_ephemeral`), Cairo 2.19, snforge 0.61; tests run as
  `cd contracts && snforge test --workspace`. The CI (FND-02): `.github/workflows/ci.yml` and
  `.github/ci/`; the `cairo (contracts)` job.
- The owner's other programmes have gas tooling to learn from (read-only):
  `/home/claude/projects/glam-cairo/scripts/gas_tables.py`, `bench.py`;
  `/home/claude/projects/nalgebra-cairo/scripts/gas_report.py`; the map library's `GAS.md`
  convention. Copy nothing; write what this repository needs.
- Depends on: FND-02 (merged).

## Scope
- In:
  - A script (Python 3 or shell, under `scripts/`) that runs the workspace's tests (through the
    lock), parses snforge's gas output per test, and:
    1. **checks** that every test declares `#[available_gas(l2_gas: N)]` and that `N` equals
       `ceil(1.05 × measured)` within the rule (a test over its budget already fails in
       snforge; a test without a budget, or with a budget more than 5 % above its measure, is
       reported and fails the check);
    2. **writes** `docs/BUDGETS.md` (per test: package, test, measured l2 gas, budget, date,
       commit) and one `GAS.md` per package, deterministically (same run, same file);
    3. **prints** the gas table for a `REPORT.md` (before from `origin/main`'s `docs/BUDGETS.md`,
       after from the run, budget), in the format of docs/briefs/COMMON.md §7.
  - A `--check` mode used by the CI: fails if a test has no budget, if a budget is loose, or if
    `docs/BUDGETS.md` is stale against the run.
  - The CI's `cairo (contracts)` job runs that check (in `.github/workflows/ci.yml` or
    `.github/ci/`), within the ten-minute rule.
  - `docs/BUDGETS.md` and the `GAS.md` files generated from the current tests.
  - docs/briefs/COMMON.md §7 is the orchestrator's: list under *Escalations* the one-line change
    it needs (the command that prints the table).
- Out: new tests or benchmarks of game code (ENG-* tasks write them); the spikes' packages
  (their budgets stay theirs; the check covers `contracts/` only, say how a package opts in);
  changing any budget value by hand.
- Allowlist: `scripts/` (the new script and its tests if any), `.github/workflows/ci.yml` and
  `.github/ci/` (the check step only), `docs/BUDGETS.md`, `contracts/*/GAS.md`. Anything else is
  an escalation.

## Acceptance criteria
- [ ] AC-1 The script produces `docs/BUDGETS.md` and the `GAS.md` files from a test run,
      byte-identical on a second run of the same commit.
- [ ] AC-2 `--check` fails on a test without a budget, on a loose budget, and on a stale
      `docs/BUDGETS.md` (each shown on a throwaway change, then reverted), and passes on the
      current tree.
- [ ] AC-3 The CI runs `--check` in the contracts job; a pull request that removes a budget
      turns it red (shown with a run link, then reverted).
- [ ] AC-4 The printed report table matches COMMON §7's format and uses `origin/main`'s
      figures as "before".

## Verification
From the worktree root: the script's run and `--check` with their output; the CI runs linked
in the report.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, with the table the script prints.
