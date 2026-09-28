# FND-02 — Continuous integration

## Agent
Title: `[Sonnet 5] FND-02 continuous integration` · Profile: implement · Branch:
`chore/fnd-02-ci`

## Goal
After this task every pull request is gated by a CI that builds, formats, lints and tests
the contracts and the client, each on its pinned toolchain, in under ten minutes, beside the
existing `tooling` workflow. "Merge on green CI" then means the code works, not only the
scripts.

## Context
- OPERATIONS §7 (merge on green CI; CI under ~10 minutes; split test packages before they
  grow), §3 (local checks are package-scoped, the pull-request CI is the full gate).
- The toolchain (SPK-5, `docs/research/SPK-5-toolchain.md`): root `.tool-versions` (Scarb
  2.13.1, snforge 0.51.2, sozo 1.8.7, Katana 1.7.1, Torii 1.8.16, Node 24.21.0, pnpm 12.5.1),
  `scripts/setup-toolchain.sh`. **The game is on Cairo 2.13.**
- **Per-package toolchains** (D-122, `docs/decisions/2026-09-28-N-9-compiler-target.md`): a
  standalone spike package may pin another Cairo in its own `.tool-versions` (SPK-7 will be
  on Cairo 2.19 in `spikes/SPK-7/`). The CI must build each Cairo package with **the
  toolchain of the nearest `.tool-versions`**, and must never move the game's workspace off
  2.13.
- The scaffold (FND-01): `contracts/` (Dojo package `grimworld`, tests with
  `dojo_snf_test`), the pnpm workspace at the root with `client/sim` and `client/app`
  (Vitest, ESLint, Prettier, TypeScript, Vite); `spikes/SPK-5/` (Dojo, Cairo 2.13).
- The existing `.github/workflows/tooling.yml` (shellcheck, launcher dry-runs, no asset
  file, `assets` pointer unchanged): keep it as it is; it is not yours to change.
- Depends on: FND-01 (merged).

## Scope
- In:
  - A workflow (for example `.github/workflows/ci.yml`) on `pull_request` and on `push` to
    `main`, with `permissions: contents: read`, **no secret**, no `pull_request_target`,
    every third-party action **pinned by commit SHA** with its version in a comment (as the
    `tooling` workflow does), `concurrency` cancelling superseded runs of a pull request.
  - **Cairo job(s)**: for every Cairo package of the repository (`contracts/` and each
    `spikes/*/` that has a `Scarb.toml`), with the toolchain of its nearest `.tool-versions`:
    format check, build, tests. Dojo packages build and test the way they do locally
    (`sozo build`, `sozo test`, or the `scarb`/`snforge` forms if those are what work). A
    matrix discovered from the repository, or listed explicitly with a check that no package
    is missing: say which and why.
  - **Client job**: Node and pnpm at the pinned versions, `pnpm install --frozen-lockfile`,
    lint, typecheck, test, build, `prettier --check`.
  - Caching (Scarb registry and target, pnpm store) so that a pull request's CI stays under
    ten minutes; measure it.
  - If a format or lint check fails on code already on `main`, fix it with the formatter
    only (`scarb fmt`, `prettier --write`), in its own commit, and list the files.
  - A short section in `contracts/README.md` and `client/README.md` naming the CI jobs.
- Out: gas budgets and `docs/BUDGETS.md` (FND-06); branch protection or required checks (D-121:
  `main` is not protected); deployment; the `tooling` workflow; any change to game code
  beyond formatting.
- Allowlist: `.github/workflows/` (new files only; `tooling.yml` untouched), formatting-only
  changes in `contracts/`, `client/`, `spikes/`, and the two READMEs' CI sections. Anything else
  is an escalation.

## Acceptance criteria
- [ ] AC-1 The new workflow runs on this pull request and is green: every Cairo package
      builds and tests with the toolchain of its nearest `.tool-versions`, the client
      installs, lints, typechecks, tests and builds.
- [ ] AC-2 It fails when it should: show in the report one run (or a local equivalent) where
      a failing Cairo test and a failing client test each turn the job red (then revert).
- [ ] AC-3 A pull request's CI wall time is under ten minutes with caches warm; the report
      gives cold and warm times.
- [ ] AC-4 Every action is pinned by SHA; permissions are read-only; no secret is used.
- [ ] AC-5 A package pinned to another Cairo in its own `.tool-versions` would get that
      toolchain: show it (for example a dry-run of the matrix, or a throwaway package in the
      pull request's history, removed before the end), without changing the root pins.

## Verification
The pull request's own checks (`gh pr checks <n> --watch --interval 30`), and the runs of
AC-2 and AC-5 linked from the report.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, with a table of jobs, their steps and their cold
and warm times.
