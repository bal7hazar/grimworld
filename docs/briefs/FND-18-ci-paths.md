# FND-18 — CI runs only the test jobs the changed paths concern; one summary job that always runs

> The owner's rule (2026-10-02, every repository): "CI tests must absolutely run only if files related to the
> tests were modified, so docs should skip all tests." The project manager gave the GO to modify workflows for
> this rule only (nexus #62, 2026-10-02). GitHub Actions is starved account-wide: a documents PR must not
> spend a Cairo build, a client install or a devnet.

## Agent
Title: `[Sonnet 5.5] FND-18 ci by changed paths` · Profile: implement · Branch: `hp/grimworld-game/t-0050-fnd-18-ci-by-changed-paths`

## Goal
After this task each job of CI runs only when a path it depends on changed in the pull request; a documents-only
pull request runs no test; one light final job, named stably, always runs and reports the result of the jobs that
ran, so that `gh pr checks <n>` always has a result and `gh pr checks <n> && gh pr merge …` keeps working.

## Context
- Workflow files today (checked on origin/main at `5b72373`: `.github/workflows/` and `.github/ci/`):
  `.github/workflows/ci.yml`, `.github/workflows/tooling.yml`; helpers `.github/ci/discover.py`,
  `.github/ci/build_stable.py`, `.github/ci/install-snforge.sh`. No other workflow exists (no release workflow).
- **This lot changes the workflow files `.github/workflows/ci.yml` and `.github/workflows/tooling.yml`** (rule
  nexus #60), and adds the helper `.github/ci/changes.py`. `discover.py` is not changed.
- Both workflows trigger on `pull_request` and on `push` to `main`, with the concurrency block of FND-16.
- `ci.yml` already has one path filter: its `discover` job's `changes` step decides `indexer-node` from
  `git diff` against the PR base (or `github.event.before` on a push), and runs the job when the base is unknown.
  This lot generalises that step; the way it fetches the base and fails open stays.
- Main has no branch protection and no ruleset (project manager's check): no required check constrains job
  names. The standard's merge command only needs `gh pr checks` to return a result.
- The owner's list of what is allowed in the workflows (nexus #62), and nothing else: a path filter per job
  (a first job listing the changed paths, or a pinned filter action), and one final job with `if: always()` that
  fails if a needed job failed or was cancelled and passes when all passed or were skipped. Still refused:
  `continue-on-error` (the existing FND-13 retry steps keep theirs), `if: false`, a narrowed test command, a
  deleted job; no trigger, permission or concurrency change.

## The jobs and the paths that concern them
A path concerns a job when a change to it can change the job's outcome: the job's sources, its manifests and
locks, `.tool-versions`, the scripts and CI helpers it calls, the inputs it reads, and the workflow file itself.

| Job (workflow) | Runs when one of these paths changes | Why |
| --- | --- | --- |
| `discover` (ci) | always | it validates pins and paths and lists the packages and the changes; a few seconds, no test |
| `cairo (<dir>)`, one per discovered package | the package's folder; the folder of every path dependency, transitively (`indexer/emitter` → `contracts/persistent`, `contracts/logic`; `spikes/SPK-12`, `spikes/SPK-15` → `contracts/logic`); any `Scarb.toml`, `Scarb.lock`, `.tool-versions` of those folders; the root `.tool-versions` (every package whose pin comes from it); for `contracts` also `scripts/gas_budgets.py`, `docs/BUDGETS.md`, `contracts/**/GAS.md`, `contracts/tools/**`, `contracts/logic/vectors/**`; a Cairo source (`*.cairo`) of the closure | format, build and `snforge test` of the folder and what it compiles; the `contracts` steps (gas budgets, class sizes, exp2 table, vectors, three clean builds) read those files. The contracts workspace is one package: any file under `contracts/` except the non-GAS markdown |
| `class-artefacts` (ci) | the `contracts` package's paths (the row above, `contracts` only) | one clean build of `contracts/` kept for declarations; a change elsewhere cannot change the bytes |
| `client` (ci) | `client/**`, `services/**`, `indexer/**`, `package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, the root `.gitignore` and prettier or eslint config files, `.tool-versions`, `contracts/logic/vectors/**` and `contracts/seed/**` (the sim's parity tests read them), `tools/art/manifest.toml` (read by a client test) | install, lint, typecheck, test, build, prettier of the pnpm workspace (`client/*`, `services/*`, `indexer`) |
| `indexer-node` (ci) | `indexer/**`, and what the emitter and the node depend on: `contracts/persistent/**`, `contracts/logic/**` (non-markdown), the root `.tool-versions`, `scripts/with-node.sh` | the scenario compiles the emitter from `contracts/persistent` (which depends on `contracts/logic`) and starts the pinned devnet through `with-node.sh` (decided by the orchestrator, 2026-10-03: Decided by the orchestrator, 1) |
| `tooling` (tooling) — step group "tooling checks": shellcheck, launcher dry-run, `lock.sh` cases, `with-node.sh` cases, helper self-test | `scripts/**`, `.tool-versions`, `docs/briefs/SPK-1-*` (the dry-run reads that brief's grant line), `.github/**` | they exercise the scripts and the pinned devnet; nothing else in the repository reaches them |
| `tooling` — steps "no asset file committed" and "assets pointer unchanged" (D-73) | every change | repository-policy guards, a `git ls-files` and a `git ls-tree`: an image added under `docs/` is exactly what they catch; they are not tests of code and cost seconds. They stay unconditional steps of the `tooling` job |
| the workflow files, `.github/ci/**` | **everything runs** | a change to a workflow or a CI helper can change any job; it is checked by all of them |

Paths that no row claims are classified by the script, never guessed:

- **Documents (no test):** `docs/**` (except `docs/BUDGETS.md` and `docs/briefs/SPK-1-*`, claimed above), every
  `*.md` outside what a row claims (`PLAN.md`, `STATUS.md`, `CHANGELOG.md`, `OPERATIONS.md`, `PROGRAMME.md`,
  `README.md`, `CONTEXT.md`, `CREDITS.md`, `AGENTS.md`, every `README.md`), `LICENSE`, `.gitmodules`, the
  `assets` submodule pointer (guarded by the tooling job), `.githooks/**`, `tools/**` except
  `tools/art/manifest.toml` (their tests are not in CI), `spikes/**` outside a package folder.
- **Anything else is unclassified and runs every job** (a new top-level folder, an unknown extension at the
  root): the fail-safe direction. The step prints each unclassified path.

## Mechanism (recommended)
A script, `.github/ci/changes.py`, run by the first job (`discover` in `ci.yml`; a first step of the `tooling` job
in `tooling.yml`, since it is a single job), writes outputs; each test job has `if:` on its output. Chosen over
a path-filter action (`dorny/paths-filter` pinned by SHA) because:
- it needs the Scarb path dependencies (`indexer/emitter` → `contracts/persistent`): a static glob per job would
  drift when a manifest changes, the script reads the tracked manifests as `discover.py` does;
- it is plain Python reading `git diff`, with no third-party code and no token, testable offline by a
  `--self-test` (the table above as cases) run in the `tooling` job;
- the unclassified fail-safe and the log of each decision are one place, not YAML.

Contract of the script:
- Base: a pull request is compared with `github.event.pull_request.base.sha`; the base commit is fetched alone
  (`git fetch --no-tags --depth=1`, the checkout is shallow). An unknown or malformed base, or a failed fetch,
  sets every output to run everything (as `discover`'s `changes` step does today). Event values reach it as
  environment variables, never interpolated into a command.
- **On a push to `main`: unchanged behaviour.** `cairo`, `class-artefacts`, `client` and `tooling checks` run as
  today (the declarations come from the push's `class-artefacts`, FND-12); `indexer-node` keeps its diff against
  `github.event.before`. No filter narrows a push to `main`. Whether to narrow it too is an open question.
- Outputs: `cairo` (JSON list of the discovered packages to run, same objects as `packages`; `[]` when none),
  `classes`, `client`, `indexer` (booleans) in `ci.yml`; `tooling` (boolean) in `tooling.yml`.
- `cairo` has `if: needs.discover.outputs.cairo != '[]'` and `matrix.include` from that list (an empty matrix
  fails a job, hence the `if:`). The packages' pins still come from `packages` (`class-artefacts` and
  `indexer-node` read it).

## The final job
In `ci.yml`, a job `result` (`name: ci result`): `needs: [discover, cairo, class-artefacts, client,
indexer-node]`, `if: always()`, `runs-on: ubuntu-latest`, `timeout-minutes: 2`, no checkout, no secret, one step:
it fails if any needed job's result is `failure` or `cancelled`, and passes when every one is `success` or
`skipped`; it prints the table of results. It is the check `gh pr checks` always shows for `ci`.
- A documents-only pull request shows: `discover` pass, `cairo`, `class-artefacts`, `client`, `indexer-node`
  skipped, `ci result` pass, and the `tooling` job pass with its two D-73 guard steps only.
- `tooling.yml` has one job that always runs (the guards): it is its own always-present result; no second job.

## Scope
- In:
  - `.github/ci/changes.py` (new): the classification, the outputs, `--self-test`.
  - `.github/workflows/ci.yml`: the `discover` job's `changes` step replaced by the script and its outputs;
    `if:` on `cairo`, `class-artefacts`, `client` (and `indexer-node`'s from the new output); the `result` job.
  - `.github/workflows/tooling.yml`: a first step running the script, and `if:` on the tooling-check steps (one
    step condition each, the commands unchanged); the self-test as a step of the same group.
  - `docs/briefs/FND-18-ci-paths.md` (this file); `OPERATIONS.md` (one paragraph: the rule, the table's
    location, the verification) if its CI section names the jobs.
- Out: any trigger, permission, concurrency or retry step; any test command or its arguments; any step deleted,
  `continue-on-error` or `if: false` added; `discover.py`, `install-snforge.sh`, `build_stable.py`; the behaviour
  of a push to `main` and of the `class-artefacts` artefact; widening `indexer-node` beyond the paths of Decided by the orchestrator, 1; setting branch protection.
- Allowlist: `docs/briefs/FND-18-ci-paths.md`, `.github/workflows/ci.yml`, `.github/workflows/tooling.yml`,
  `.github/ci/changes.py`, `OPERATIONS.md`. Anything else is an escalation.
- Rules for the implementer: edit the workflow files with the file-editing tool only, never with a script,
  `sed` or a redirection that rewrites them; nothing else in the workflows changes (`git diff` shows only the
  items above); CI polled at most once every 5 minutes (`gh pr checks`, or `gh run watch --interval 300`);
  batch pushes; `scripts/prepush.sh` before each push.

## Acceptance criteria
- [ ] AC-1 The brief names `.github/workflows/ci.yml` and `.github/workflows/tooling.yml` as changed and lists the
      jobs and paths above; `git diff origin/main -- .github/workflows` changes only what Scope lists
      (no trigger, permission, concurrency or test command touched; no `if: false`, no new `continue-on-error`).
- [ ] AC-2 `changes.py --self-test` passes in CI and covers: a documents-only change, a client-only change, a
      contracts change, a Cairo spike change, a change under `contracts/logic` (runs `contracts`, `SPK-12`,
      `SPK-15`, `indexer/emitter`, client vectors), `.tool-versions`, a workflow or helper change (everything),
      an unclassified path (everything), an unknown base (everything), a push (as today).
- [ ] AC-3 A documents-only pull request: `cairo`, `class-artefacts`, `client`, `indexer-node` skipped; `discover`,
      `ci result` and `tooling` (guards only) pass; `gh pr checks` returns a result.
- [ ] AC-4 A client-only pull request runs `client` and nothing of Cairo; a contracts pull request runs the
      `contracts` package, `class-artefacts`, `client` only if a client path it feeds changed; a change under
      `indexer/` runs `indexer-node`.
- [ ] AC-5 A change to a workflow file runs every job.
- [ ] AC-6 `ci result` fails when a needed job fails or is cancelled (shown by the self-test of its step's script
      or a run of a deliberately failing check on a throw-away branch), and passes when all are success or skipped.
- [ ] AC-7 A push to `main` runs what it ran before this lot.

## Verification
Four throw-away draft pull requests whose base is this branch (so the workflow under test is this branch's), each
closed after its run is read; the job list of each quoted from `gh run view <id>` in the report:
1. docs only (a line in a file of `docs/`): expected `cairo`, `class-artefacts`, `client`, `indexer-node` skipped.
2. client only (a comment in `client/sim/src`): expected `client` runs, the others skipped.
3. contracts (a comment in a `.cairo` file of `contracts/logic/src`): expected `cairo (contracts)`,
   `class-artefacts`, `client` (vectors), and the spikes that depend on `contracts/logic`; `indexer-node` (it depends on
   `contracts/logic`).
4. workflow (a comment in `ci.yml`): expected every job.
Plus `python3 .github/ci/changes.py --self-test` and `scripts/prepush.sh`.

## Audit
None needed: no contract or cost change; the verification pull requests above prove the behaviour. A review of the
workflow diff by another model is the pull request's usual one.

## Decided by the orchestrator (2026-10-03)
1. `indexer-node` also runs when `contracts/persistent/**`, `contracts/logic/**` (non-markdown), the root
   `.tool-versions` or `scripts/with-node.sh` change: the emitter depends on them. Reversed if: track CV, which
   owns the indexer, prefers otherwise. (`scripts/setup-toolchain.sh` alone stays out, as the job's comment says.)
2. A push to `main` is not filtered: it runs what it ran before (safety net; FND-12's artefacts). Reversed if: the
   queue on `main` becomes the bottleneck.
3. The two D-73 guard steps of `tooling` run on every change, a documents PR included: they are cheap guards.
   Reversed if: they cost more than a few seconds.
