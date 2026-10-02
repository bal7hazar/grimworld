# FND-13 — Stop pushing red CI: `scripts/prepush.sh`, a pre-push hook, retries on tool downloads

> The owner's request (2026-10-02, through the project manager). Across the organisation's repositories since
> 2026-10-01: 22 CI failures out of ~770 runs; 6 were infrastructure (HTTP 500 downloading snforge or scarb);
> about 15 a local check would have stopped. In this repository: formatting (`scarb fmt --check`, 3),
> `docs/BUDGETS.md` not regenerated (generated artefacts), compile or manifest errors (2). Nothing in the
> repository said what to run before a push.

## Agent
Title: `[Sonnet 5.5] FND-13 prepush` · Profile: implement · Branch: `hp/grimworld-game/t-0031-fnd-13-prepush-check`

## Goal
After this task a push to this repository is preceded by a local check that stops what CI would stop: one script,
`scripts/prepush.sh`, runs the checks the diff calls for (under two minutes on a typical change), a
`.githooks/pre-push` hook runs it, `AGENTS.md` tells every agent to use both, and the downloads of tools in CI
retry once or twice so that a registry's HTTP 500 does not fail a run.

## Context
- `.github/workflows/ci.yml`: the `cairo` job's checks (format, build, test, gas budgets, class sizes, exp2 table,
  vectors) and the `client` job's (lint, typecheck, test, build, prettier) are what the script mirrors.
- `scripts/lock.sh` (single-threaded build through `RAYON_NUM_THREADS=1`, D-176; one heavy build at a time),
  `scripts/gas_budgets.py` (`--self-test`, `--check`; `--check` runs the tests and needs `origin/main`).
- `.github/ci/install-snforge.sh` (SHA-256 pinned downloads), `.github/ci/discover.py` (the package list).
- The prepush script is a convenience, not a gate: CI stays the gate and no CI check is weakened or removed.
- Rule nexus #60: a brief names every workflow file it changes (below).

## Scope
- In:
  - `scripts/prepush.sh`: from `git diff --name-only <upstream or origin/main>...HEAD` plus the working tree
    (staged, unstaged, untracked), decides which checks run; prints each step and its time; exits non-zero at
    the first failing step's end (every step runs, the summary lists the failures, exit 1).
    - always: `scarb fmt --check` of the contracts workspace; the self-tests of the repository's scripts
      (`scripts/gas_budgets.py --self-test`, `tools/art/tests/test_build.py` when `tools/art/` changed);
    - the compile (`scripts/lock.sh scarb --manifest-path <pkg>/Scarb.toml build`) of the Cairo packages touched
      only (the `contracts` workspace when a file under `contracts/` changed);
    - generated-artefact checks only when their inputs changed: `gas_budgets.py --check` and
      `contracts/tools/class_sizes.py` when Cairo sources, Scarb manifests or locks, or `.tool-versions` changed;
      `contracts/logic/vectors/check.py` when `contracts/logic/src/**` or `contracts/logic/vectors/` changed;
      `contracts/tools/exp2_table.py --check` when its inputs changed (`contracts/tools/exp2_table.py`, the
      generated files it names);
    - the client: only when `client/`, `indexer/` or the pnpm files changed: lint, typecheck, test, prettier as
      CI's `client` job runs them;
    - `--all` runs every check whatever the diff.
  - `.githooks/pre-push` (executable) running `scripts/prepush.sh`. `core.hooksPath` is **not** set by this PR:
    the orchestrator sets it in the clones after the merge.
  - `AGENTS.md` at the root: short.
  - **Workflow files changed** (retries only; no trigger, permission, job condition, or check changes):
    - `.github/workflows/ci.yml`: a second attempt of `software-mansion/setup-scarb`, `pnpm/action-setup` and
      `actions/setup-node` (the first step `continue-on-error: true` with an `id`, the second guarded by
      `if: steps.<id>.outcome == 'failure'`, same pinned SHA and inputs); `curl --retry` on the starknet-devnet
      download of the `indexer-node` job.
    - `.github/workflows/tooling.yml`: `curl --retry` on its starknet-devnet download (it downloads a tool).
    - `.github/ci/install-snforge.sh`: `curl --retry` on both archive downloads.
- Out: any other change to the workflows; setting `core.hooksPath`; a check's rule or threshold; the gas
  budgets, class sizes or vectors themselves.
- Allowlist: `docs/briefs/FND-13-prepush.md`, `scripts/prepush.sh`, `.githooks/pre-push`, `AGENTS.md`,
  `.github/workflows/ci.yml`, `.github/workflows/tooling.yml`, `.github/ci/install-snforge.sh`. Anything else is
  an escalation.

## Acceptance criteria
- [ ] AC-1 `scripts/prepush.sh` runs the always-checks, and each conditional check only when its inputs changed;
      `--all` runs all; a failing step makes it exit non-zero (shown by a deliberate formatting error, undone).
- [ ] AC-2 It prints what it ran and each step's time; the measured real output of a typical change and of
      `--all` is in the report and the PR.
- [ ] AC-3 `.githooks/pre-push` is executable and runs the script; `core.hooksPath` untouched.
- [ ] AC-4 `AGENTS.md` says: set `core.hooksPath` once per clone, run `scripts/prepush.sh` before every push,
      never push red, `--all`.
- [ ] AC-5 The workflow diff is retries only; `git diff` of the workflows shown in the report.
- [ ] AC-6 `shellcheck` clean on the new and changed shell scripts (the `tooling` job runs it on `scripts/*.sh`).

## Audits
None expected. `Audit: none needed`.

## Verification
```
shellcheck scripts/prepush.sh .githooks/pre-push .github/ci/install-snforge.sh
time scripts/prepush.sh
time scripts/prepush.sh --all
git diff origin/main -- .github
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the PR and head, the measured times (real output), what runs on
which change, the workflow lines changed.
