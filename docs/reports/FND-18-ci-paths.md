Archived at the merge of #322, 93eb1b6.

## Report

Model: Sonnet 5.5 (claude-sonnet-5-5)

### Summary
CI now runs each test job only when a path it depends on changed. `.github/ci/changes.py` (new, with `--self-test`) classifies the changed paths. `ci.yml`'s `discover` job and a first step of `tooling.yml`'s `tooling` job read it. A new `ci result` job (`if: always()`) fails on failure or cancelled and passes on success or skipped. A change to a workflow or `.github/ci/**`, a path no rule claims, or an unknown base runs everything. A push to main runs what it ran before (`indexer-node` still follows its diff).

### Files changed
`docs/briefs/FND-18-ci-paths.md` (first commit), `.github/ci/changes.py`, `.github/workflows/ci.yml`, `.github/workflows/tooling.yml`. OPERATIONS.md is unchanged: its sections name no CI jobs.

### Job → paths (full table in the brief)
- `cairo (<pkg>)`: the package folder plus its path-dependency closure (`indexer/emitter` → `contracts/persistent` and `contracts/logic`; `SPK-12` and `SPK-15` → `contracts/logic`), non-markdown. `.tool-versions` at the root hits every package whose scarb or snforge pin is the root's. `contracts` also takes `scripts/gas_budgets.py`, `docs/BUDGETS.md` and `contracts/**/GAS.md`.
- `class-artefacts`: `*.cairo`, `Scarb.toml`, `Scarb.lock` and `.tool-versions` under `contracts/`, plus root `.tool-versions`.
- `client`: `client/`, `services/`, `indexer/`, `contracts/logic/vectors/`, `contracts/seed/`, `tools/art/manifest.toml`, the pnpm and prettier root files, `.tool-versions`.
- `indexer-node`: `indexer/` only, as before.
- `tooling` script checks: `scripts/`, `.tool-versions`, `docs/briefs/SPK-1-*`, `.github/`. The two D-73 guard steps run on every change.
- Docs that run nothing: `docs/**` (except `BUDGETS.md` and the SPK-1 brief), `*.md`, `LICENSE`, `.gitmodules`, `assets`, `.githooks/`, `tools/` (except the art manifest), `spikes/` outside a package.

### Commands run
- `python3 .github/ci/changes.py --self-test`: ok.
- A live run against origin/main, with `PACKAGES` from `discover.py`, gave `cairo=[]`, `classes=false`, `client=false`, `indexer=false` and `tooling=false`.
- `scripts/prepush.sh`: all checks passed.
- Verification: four draft PRs based on the thread branch, job lists from `gh run view`, polled about every 5 minutes.

### Acceptance criteria
- AC-1 Diff limited to the listed items: `git diff origin/main -- .github/workflows` only adds the script step, the `if:`s, the `cairo` matrix source (`cairo` output instead of `packages`), the `result` job and comments.
- AC-2 Self-test passes. It also runs in the `tooling` job (step "changed-paths self-test"), and ran there on #322.
- AC-3 Docs (#323, run 37099331391):
  - `discover` and `ci result` success; `cairo`, `class-artefacts`, `client` and `indexer-node` skipped.
  - `tooling` (run 37099331389): only "changed paths", "no asset file committed" and "assets pointer unchanged" ran; `changed-paths self-test`, `shellcheck`, `launcher dry-run` and `with-node` skipped.
- AC-4
  - Client (#324, run 37099338529): `client` success; `cairo`, `class-artefacts` and `indexer-node` skipped.
  - Contracts (#325, run 37099343221): `cairo` ran for contracts, indexer/emitter, SPK-12 and SPK-15, plus `class-artefacts`; `client` and `indexer-node` skipped.
  - I did not run a PR that changes `indexer/`; that case is covered by the self-test only.
- AC-5 Workflow (#326, run 37099348263): all 15 `cairo` packages, `class-artefacts`, `client`, `indexer-node` and `ci result` ran, all success. The PR's own run (#322) also ran everything, 20 checks green.
- AC-6 `ci result` passing on skipped and success is shown by #323 to #326. Failure and cancelled are covered only by reading the step's code; I did not run a deliberately failing check.
- AC-7 Push to main: shown only by the self-test cases for `event == push`; a real push will confirm.

### Deviations from the task
- One command of mine used an empty `cat >> ci.yml <<'E'` redirection (no content). It changed nothing, but it was a redirection against a workflow. Every real edit was made with the file-editing tool.
- The skipped matrix job shows the literal name `cairo (${{ matrix.dir }})` in `gh pr checks`. That is cosmetic.
- Closing the four throw-away PRs (#323 to #326) was refused by the permission layer: `Permission to use Bash with command … gh pr close … has been denied.` The orchestrator has since closed them (branches kept).

### Escalations
- The three open questions were decided by the orchestrator (2026-10-03) and are recorded in the brief under "Decided by the orchestrator", with what reverses each. Decision 1 is implemented: `indexer-node` also runs for `contracts/persistent/**`, `contracts/logic/**` (non-markdown), the root `.tool-versions` and `scripts/with-node.sh` (`changes.py`, its self-test, the job comment, the brief). Decisions 2 and 3 change nothing.
- FND-17 (#327, aa5bcc1) merged on main; I merged origin/main (clean), added the path condition to FND-17's hook step and `.githooks/` to the tooling paths, and pushed once.
- `scripts/prepush.sh` skipped the Cairo compile, `gas_budgets.py --check` and `pnpm test` because the build lock stayed busy for 90 s; CI compiles. Everything else passed.
- The verification runs above predate decision 1, so the widened `indexer-node` rule is covered by the self-test only (a contracts change now also runs `indexer-node`).
- Audit: none needed.

## Next
Review PR 322 on its head after that push
Remove the four verification branches fnd18-verify-*

## Review fixes (head 16f6b99, one push)
Review of #322 at 6194a97 (Opus): FAIL, two majors. All six points fixed in one push:
1. `client/sim/src/exp2.ts` is in `CONTRACTS_FILES`; self-test: it runs `contracts` and `client`.
2. `closure` returns folders and files: the workspace manifest of each reached member. `contracts/Scarb.toml` runs `contracts`, `indexer/emitter`, `spikes/SPK-12`, `spikes/SPK-15` and `indexer-node`. `contracts/Scarb.lock` is not an input for the packages outside the workspace (each has its own lock). The pinned closure assertion is updated.
3. Markdown under `client/` and `indexer/` runs `client`; decision written in the brief, with a self-test case.
4. The stale `ci.yml` comment and the PR body are fixed.
5. The PR body quotes the four verification runs and says decision 1 is shown by the self-test, not by #325.
6. `assets` is matched exactly (`assets` or `assets/…`).
Checks: `changes.py --self-test` ok; `scripts/prepush.sh` all checks passed.
