# [Sonnet 5] FND-02 — Continuous integration

## Summary
`.github/workflows/ci.yml` now gates every pull request and every push to `main`, beside the untouched `tooling` workflow.

- `discover` lists every tracked `Scarb.toml`. For each one it reads the Scarb and snforge versions from the nearest `.tool-versions`.
- `cairo (<package>)` is a matrix over that list: `scarb fmt --check`, `scarb build`, `snforge test`.
- `client` installs with `--frozen-lockfile`, then runs lint, typecheck, test, build and `prettier --check client`.

The token is `contents: read`. There is no secret and no `pull_request_target`. Every third-party action is pinned by SHA. A new push to a pull request cancels the superseded run.

Pull request: https://github.com/bal7hazar/grimworld/pull/21. The model in my session is Sonnet 5, as the brief names.

**Matrix: discovered, not listed.** A listed matrix needs a check that no package is missing. Discovery from `git ls-files '*Scarb.toml'` cannot miss one, so a new spike is gated the day it lands. The cost is that a stray `Scarb.toml` also becomes a job, which is acceptable here.

**Nearest `.tool-versions` is resolved per tool**, walking up from the package folder (asdf semantics, so CI matches a local run). A package pinning only `scarb` still gets the root snforge. Each job checks that `scarb --version` and `snforge --version` equal the discovered versions, so a wrong toolchain fails the job.

**No `sozo` in CI.** `scarb build` and `snforge test` (from the package folder) build and pass the Dojo packages, and `sozo build/test` run these same tools underneath. This is faster and installs one tool fewer.

## Files changed
- `.github/workflows/ci.yml`: new workflow.
- `contracts/src/lib.cairo`, `models.cairo`, `systems.cairo`: `scarb fmt` only, in commit `aa0f248`. It reorders `pub mod` declarations and their doc comments. No logic changed.
- `client/README.md`: `prettier --write` only, in the same commit `aa0f248`. It was the only client file failing `prettier --check`.
- `contracts/README.md`, `client/README.md`: a "CI" section each.

`tooling.yml` is untouched. The throwaway files of AC-2 and AC-5 were added and removed (commits `14a1e7a`, `ddf6272`, `58924c2`). The final tree has none of them.

## Commands run
- Local, before pushing:
  - `scarb --manifest-path contracts/Scarb.toml fmt --check` failed on 3 files. After `scarb fmt` it passes.
  - `spikes/SPK-5` passed `fmt --check` untouched.
  - `pnpm exec prettier --check client` failed on `client/README.md` only.
  - `scarb --manifest-path contracts/Scarb.toml build` and `scarb --manifest-path contracts/Scarb.toml test` pass: `Tests: 1 passed, 0 failed`, `l2_gas: ~1763835`.
- I could not run the discovery script locally: the profile refuses `bash <script>`. Its first proof is the CI `discover` log.
- CI runs, all on PR 21:

| Run | What | Result |
|---|---|---|
| 36450811576 | First push, all caches cold | green |
| 36451175477 | Second push, caches warm | green |
| 36451609071 | + throwaway Cairo 2.19 package (AC-5) | green |
| 36451957183 | + failing Cairo and client tests (AC-2) | `cairo (contracts)` and `client` red |
| 36452121421 | After removing the throwaways (final) | green |

Action pins, with tag → SHA read from the GitHub API through WebFetch (not `gh api`, which my profile refuses):

| Action | SHA | Tag |
|---|---|---|
| `actions/checkout` | `3d3c42e5aac5ba805825da76410c181273ba90b1` | v7.0.1 (as in `tooling.yml`) |
| `software-mansion/setup-scarb` | `2a96b748888e3329ee44ac9ac073d930e692b3cd` | v1.6.2 |
| `foundry-rs/setup-snfoundry` | `16e23ddd0e2845f38727c92f4b913a7b728cda9e` | v6.0.0 |
| `pnpm/action-setup` | `ea17c68df8912ef543352723c149a84f56e3d413` | v6.1.0 (the tag is annotated; I dereferenced it to the commit) |
| `actions/setup-node` | `820762786026740c76f36085b0efc47a31fe5020` | v7.0.0 |

Each resolved and ran in CI, so each SHA exists. That each matches its tag rests on the WebFetch reading, so the orchestrator may want to re-check them.

## Cost
—. No Cairo code changed beyond formatting. The contracts test measured `l2_gas: ~1763835` locally and in CI, unchanged.

## Jobs, steps and times
Times are the job durations reported by GitHub, from the runs above.

Cold is run 36450811576. Warm is run 36451175477, and the final run 36452121421 was similar.

| Job | Steps | Cold | Warm |
|---|---|---|---|
| `discover` | checkout, find packages | 5 s | 5 s (3 s in the final run) |
| `cairo (contracts)` | checkout, setup-scarb, setup-snfoundry, toolchain check, fmt, build, test | 34 s (build 11 s, test 11 s) | 30 s (build 4 s, test 8 s) |
| `cairo (spikes/SPK-5)` | same | 39 s (build 12 s, test 12 s) | 26 s (build 4 s, test 10 s) |
| `client` | checkout, pnpm, setup-node, toolchain check, install, lint, typecheck, test, build, prettier | 25 s | 27 s |

The warm run's log shows `Cache hit for: cairo-scarb-cache-linux-…` and `Cache restored successfully`.

**Wall time.** From the run's `createdAt` to `updatedAt`, the cold run took 2 min 33 s and the second (warm) run 2 min 47 s. Most of that was runner queueing before the Cairo jobs started, not work. The last run took 38 s. Every measured wall time is well under ten minutes, and the longest job is 39 s. Each job has `timeout-minutes: 10`.

**Caches.**
- `setup-scarb` caches the Scarb registry and each package's `target/`. The key is that package's `Scarb.lock`. It derives the target folder from `scarb-lock`; the `target-dir` input I first passed does not exist and was removed.
- `setup-node` with `cache: pnpm` caches the pnpm store.
- A pull request's caches fill on its first run and are reused by its later runs. Runs on `main` fill the cache that new pull requests restore from.
- Cold and warm above were both measured on this pull request's runs.

## Acceptance criteria
- **AC-1:** green on this PR, run 36452121421: `discover`, `cairo (contracts)`, `cairo (spikes/SPK-5)`, `client` and `tooling`. Cairo packages build and test with 2.13.1 / 0.51.2. The client installs, lints, typechecks, tests and builds.
- **AC-2:** run 36451957183 added `contracts/tests/test_ci_red.cairo` (`assert_eq!(1, 2)`) and `client/sim/src/ci-red.test.ts` (`expect(1).toBe(2)`). `cairo (contracts)` failed at step `test`, `client` failed at step `test`, and the other jobs stayed green. Both files were removed in `58924c2`.
- **AC-3:** measured above. The longest job was 39 s cold and 30 s warm. Warm Cairo builds drop from 11–12 s to 4 s.
- **AC-4:**
  - `permissions: contents: read`, no `secrets.*`, no `pull_request_target`.
  - The five action references above are pinned by SHA with the version in a comment.
  - The run logs show `Contents: read` and `Metadata: read` as the token permissions.
- **AC-5:** run 36451609071 had a throwaway `spikes/tmp-cairo219/` with its own `.tool-versions` (`scarb 2.19.4`, `starknet-foundry 0.61.0`).
  - The `discover` log listed it as `{"dir":"spikes/tmp-cairo219","scarb":"2.19.4","snforge":"0.61.0"}`, next to `contracts` and `spikes/SPK-5` at 2.13.1 / 0.51.2.
  - Its job ran `scarb 2.19.4 (b45b74c03 2026-07-21)` and `snforge 0.61.0`, and its test passed.
  - The root `.tool-versions` and the other packages stayed on 2.13.1 / 0.51.2. The package was removed in `58924c2`.

## Deviations from the brief
- The spike `spikes/SPK-5` has its own `package.json` and pnpm lockfile. They are not part of the root workspace, so the client job does not install or test them. The brief covers only the Cairo side of spikes.
- Discovery and the version comparisons live inline in the workflow. `scripts/` and `.github/actions/` are not in my allowlist.

## Escalations
None. Two notes for the orchestrator:
- The pinned SHAs were obtained through WebFetch, as described above.
- If a virtual Scarb workspace (a root `Scarb.toml` with `[workspace]` and no `[package]`) is ever added, the discovery would also list its member packages. It would need a small adjustment then.

## Open questions
- Should `push` to `main` also refresh the caches on a schedule? A cache unused for seven days is evicted by GitHub, which would make the next pull request cold, still about a minute.

## Resume 1

The game dropped Dojo (ADR-0007) while the pull request waited. I merged `origin/main` (no rebase) and made the CI right for the new layout. The model is still Sonnet 5.

**Merge.** The merge commit is `c72862d`.
- Both READMEs conflicted. I took `origin/main`'s versions and re-added a CI section to each, rewritten for the new layout.
- `contracts/src/{lib,models,systems}.cairo` were modified by my first formatter commit and deleted upstream. I kept them deleted.
- The formatter commit was redone on the new files (`c08910f`, formatter only): `scarb fmt` moved the `pub mod` order in `contracts/ephemeral/src/lib.cairo` and `contracts/persistent/src/lib.cairo`, and reflowed one array literal in `spikes/SPK-5b/tests/test_mark.cairo`. `prettier --check client` was already clean.

**Changes to `ci.yml`.**
1. A Scarb workspace is one job at its root. `discover` skips any `Scarb.toml` that has an ancestor `Scarb.toml` declaring `[workspace]`. So `contracts/logic`, `contracts/persistent` and `contracts/ephemeral` are not jobs. The steps run `scarb fmt --check --workspace`, `scarb build --workspace` and `snforge test --workspace`.
2. Each job keeps the toolchain of its nearest `.tool-versions`, resolved per tool as before.
   - `contracts` and `spikes/SPK-5b` get Scarb 2.19.4 and snforge 0.61.0 (the root pins).
   - `spikes/SPK-5` gets Scarb 2.13.1 and snforge 0.51.2 (its own file). The job's log shows `scarb 2.13.1` and `snforge 0.51.2`, and its toolchain step compares them to the discovered values.
3. No `sozo`, `katana`, `torii` or `starknet-devnet` is installed. No test needs them: the `contracts` job ran all workspace tests with only `scarb` and `snforge`.
4. The job comments and both README sections describe the new layout.

**Runs on PR 21.**

| Run | What | Result |
|---|---|---|
| 36460636302 | After the merge, caches cold for the new lock files | green |
| 36460995176 | Empty commit `38e3f66`, caches warm | green (final) |

The `contracts` job ran the `grimworld_logic`, `grimworld_persistent` and `grimworld_ephemeral` tests, one each. All pass.

Jobs, from GitHub's job durations. Steps in each Cairo job: checkout, setup-scarb, setup-snfoundry, toolchain check, fmt, build, test.

| Job | Toolchain | Cold | Warm |
|---|---|---|---|
| `discover` | | 5 s | 5 s |
| `cairo (contracts)` | 2.19.4 / 0.61.0 | 1 m 13 s (build 6 s, test 50 s) | 26 s (build 1 s, test 7 s) |
| `cairo (spikes/SPK-5)` | 2.13.1 / 0.51.2 | 27 s (build 4 s, test 8 s) | 24 s (build 2 s, test 6 s) |
| `cairo (spikes/SPK-5b)` | 2.19.4 / 0.61.0 | 25 s (build 5 s, test 4 s) | 19 s (build 1 s, test 2 s) |
| `client` | Node 24.21.0 / pnpm 12.5.1 | 23 s | 30 s |

**Wall time.** From `createdAt` to `updatedAt`, the cold run took 2 min 33 s and the warm run 2 min 22 s. Most of that is runner queueing between `discover` and the Cairo jobs, not work. The critical path in job time is `discover` (5 s) plus the longest Cairo job (1 m 13 s cold), so the work is about 1 m 20 s cold and 35 s warm. Both are far under ten minutes. Each job keeps `timeout-minutes: 10`.

**Caveats.**
- The cold run is cold only for the new lock files. The `contracts` cache entry did not exist (`Cache entry not found` in its log). The warm run hit it.
- The warm run used an empty commit because `gh run rerun` needs an approval my profile does not have. The commit is in the PR history.
- The `contracts` test step is the heaviest (50 s cold), from compiling three packages plus `origami_hexmap`. It is the step to watch when the game code grows. OPERATIONS §7 says to split test packages before CI nears ten minutes.

**Escalations.** None.

## Fix loop 1

Four findings of the [GPT-6-Sol] audit, all fixed. The model is still Sonnet 5.

The logic moved out of the workflow: discovery is `.github/ci/discover.py` (Python 3 with `tomllib`, on the runner image) and the snforge install is `.github/ci/install-snforge.sh`.

### F1: discovery skipped every manifest below a workspace root
- **Fix.** `discover.py` reads each `[workspace]`, expands its `members` (globs included, on the checked-out tree), and requires every member to be a folder with a tracked `Scarb.toml`.
  - It fails when a tracked `Scarb.toml` lies below a workspace root and is not one of its members.
  - It fails on `exclude` (not supported, so it cannot hide a manifest), on a member that leaves the workspace folder (absolute path or `..`), on a member listed twice, on nested workspaces, and on a member pattern that matches nothing.
  - A manifest that is neither a job root nor a member of a workspace that is one can therefore not be dropped.
- **Evidence, locally.**
  - The real tree gives 3 jobs (`contracts`, `spikes/SPK-5`, `spikes/SPK-5b`).
  - With a tracked `contracts/rogue/Scarb.toml`: `contracts/rogue/Scarb.toml is below the workspace contracts but is not one of its members`.
  - With `members = ["l*", "p*", "e*"]` (globs) the discovery still finds the same 3 jobs.
- **Evidence, in CI.** Run https://github.com/bal7hazar/grimworld/actions/runs/36462776156: `discover` red with `contracts/rogue/Scarb.toml is below the workspace contracts but is not one of its members`. The Cairo and client jobs were skipped. The throwaway was removed in `644254c`.

### F2: versions from the pull request reached the setup actions unchecked
- **Fix.** `discover.py` runs before any setup step.
  - **Versions:** Scarb, snforge, Node and pnpm must match `^[0-9]+\.[0-9]+\.[0-9]+$`, so `latest`, `nightly`, ranges and `system` are refused.
  - **Folders:** job folders are plain repository-relative paths (`[A-Za-z0-9._-]` components, no `..`, not absolute).
  - **pnpm:** `package.json` `packageManager` must be exactly `pnpm@<the pnpm of .tool-versions>`.
  - **How versions reach the jobs:** the values go from `discover` to the jobs by step outputs. The `client` job now `needs: discover` and takes `node-version` from its output. Matrix values reach shell only through `env:`, never interpolated into a script.
- **Evidence, in CI.** Run 36462776156 (same run as F1) also has, from a throwaway `spikes/SPK-5b/.tool-versions` of `scarb latest` and `starknet-foundry nightly`:
  - `spikes/SPK-5b: scarb 'latest' is not an exact release number (x.y.z)`
  - `spikes/SPK-5b: starknet-foundry 'nightly' is not an exact release number (x.y.z)`
  - No setup action ran (the downstream jobs were skipped). The throwaway was removed in `644254c`.

### F3: `setup-snfoundry` pulled a mutable action tag
- **Fix.**
  - `foundry-rs/setup-snfoundry` is gone. `.github/ci/install-snforge.sh` downloads snforge (`0.61.0` and `0.51.2`) and universal-sierra-compiler (`2.10.1`) from their official GitHub release archives over HTTPS.
  - It verifies each archive against a SHA-256 pinned in the script before extracting it.
  - A snforge version with no pinned hash is refused, so moving `.tool-versions` needs a reviewed hash in the same pull request.
  - Both hashes came from downloading the archives myself with `sha256sum`, and they equal the `digest` GitHub shows for the assets.
  - universal-sierra-compiler is pinned at `2.10.1`, the release `setup-snfoundry` had resolved as "latest" in the earlier runs. It ran with both snforge 0.51.2 and 0.61.0 in this PR's CI.
- **`setup-scarb` kept.** Its `action.yml` (at the pinned SHA) is `using: node24` from its own bundled `dist/`, with no `uses:` step.
- **Every executed action.** I read the `action.yml` of each at its pinned SHA:

| Action | Pinned to | Nested `uses:` |
|---|---|---|
| `actions/checkout` | `3d3c42e…` (v7.0.1) | none, node24 |
| `software-mansion/setup-scarb` | `2a96b74…` (v1.6.2) | none, node24 bundle |
| `pnpm/action-setup` | `ea17c68…` (v6.1.0) | none, node24 |
| `actions/setup-node` | `8207627…` (v7.0.0) | none, node24 |

- **Remaining gap, stated plainly.** `setup-scarb` itself downloads the Scarb release archive at runtime, and I have not checked whether it verifies a checksum. That is the same trust level the repository's `scripts/setup-toolchain.sh` documents for Scarb. Pinning Scarb's archive hash too would mean replacing `setup-scarb` (and losing its cache logic). I did not do it, given your wording ("keep setup-scarb only if its whole chain is pinned"). Node and pnpm are installed by `actions/setup-node` and `pnpm/action-setup` from nodejs.org and npm, the same way.
- **Evidence.** Run 36462287611 (contracts job): `snforge.tar.gz: OK`, `universal-sierra-compiler.tar.gz: OK`, `snforge 0.61.0`, `universal-sierra-compiler 2.10.1`. Its log has no `setup-universal-sierra-compiler` line. The same run is green for `spikes/SPK-5` on 0.51.2.

### F4: AC-2's Cairo failure predates the workspace
- **Fix.** I added a temporary failing test, `contracts/logic/tests/test_ci_red.cairo` (`assert_eq!(1, 2)`), in a current member of the workspace.
- **Evidence.**
  - Run https://github.com/bal7hazar/grimworld/actions/runs/36462497726: `cairo (contracts)` failed at step `test` with `[FAIL] grimworld_logic_integrationtest::test_ci_red::ci_must_turn_red` and `Tests summary: 3 passed, 1 failed`.
  - The other jobs in that run were green.
  - The file was deleted in `16afbf3`, in the same commit as the F1/F2 throwaways, which `644254c` then removed.
  - The client half of AC-2 stays as shown in the first run (36451957183, a failing client test).

### Runs
| Run | What | Result |
|---|---|---|
| 36462287611 | F1–F3 fix | green |
| 36462497726 | + failing test in `contracts/logic` (F4) | `cairo (contracts)` red at `test`, others green |
| 36462776156 | + `contracts/rogue/Scarb.toml`, floating versions in `spikes/SPK-5b` (F1, F2) | `discover` red, downstream skipped |
| 36462867919 | after removing all throwaways (final, `644254c`) | green: discover 5 s, contracts 23 s, SPK-5 21 s, SPK-5b 18 s, client 22 s |

The final tree has none of the throwaways (`git diff --stat origin/main...HEAD` lists only the CI files, the two READMEs and the formatter changes). The times are with warm caches, well under ten minutes.

**Escalations.** None. The workflow now depends on files under `.github/ci/`, which I read the fix-loop instructions to allow.

## Fix loop 2

Two findings of the [GPT-6-Sol] re-audit, both fixed. The model is still Sonnet 5.

### F2: `pnpm/action-setup` could download an unvalidated pnpm
- **Finding.** The action was given no `version`. At its pinned commit, `devEngines.packageManager.version` (ranges accepted) takes priority over `packageManager`. A pull request adding that field would therefore make it download a pnpm nobody validated.
- **Fix, in the workflow.** `client` now passes `version: ${{ needs.discover.outputs.pnpm }}` to `pnpm/action-setup`. That value is the exact `x.y.z` of `.tool-versions` that `discover.py` validated.
- **Fix, in `discover.py`.** It reads `package.json`'s `devEngines.packageManager` (a single object or a list). It fails unless every entry is `name: pnpm` with `version` exactly equal to the validated pnpm. Absence is fine.
- **Evidence, the action accepts the explicit version.** In the green run 36463537503 the `client` log shows `Run pnpm/action-setup@ea17c68…` with `version: 12.5.1`, and the job passes (install, lint, typecheck, test, build, prettier).
- **Evidence, rejection.** Throwaway commit `becb76d` added `"devEngines": { "packageManager": { "name": "pnpm", "version": ">=1" } }` to `package.json`. Run https://github.com/bal7hazar/grimworld/actions/runs/36463691523: `discover` red with `package.json devEngines.packageManager {'name': 'pnpm', 'version': '>=1'} is not exactly pnpm 12.5.1 (.tool-versions)`.

### F5: a workspace member's own `.tool-versions` was silently ignored
- **Finding.** A workspace is one job on its root's toolchain, so a `.tool-versions` inside a member did nothing, and nothing said so.
- **Fix.** For every member, `discover.py` compares the nearest pin of `scarb` and of `starknet-foundry` from the member with the pin from the workspace root. Any difference is an error that names the file, both versions, the reason and the two ways out: remove the pin, or move the package out of the workspace. I chose "reject when the pins differ" over "reject any file": an identical pin changes nothing and stays allowed.
- **Evidence, rejection.** The same throwaway commit `becb76d` also added `contracts/logic/.tool-versions` (`scarb 2.13.1`, `starknet-foundry 0.51.2`). In run 36463691523 `discover` reports, in the same run as F2's error:
  - `contracts/logic/.tool-versions: scarb 2.13.1 differs from the workspace contracts (2.19.4); a workspace is one job on its root's toolchain, so a member's own pin is ignored: remove it, or move the package out of the workspace`
  - the same message for `starknet-foundry 0.51.2` against `0.61.0`.
  - The Cairo and client jobs were skipped, so no setup action ran.
- **Evidence, locally.** I ran `discover.py` with the same throwaway files before pushing and got the same messages. The real tree still gives the same 3 jobs.
- **Cleanup.** `package.json` and `contracts/logic/.tool-versions` were restored and removed in `02e3ca8`. `git diff --stat origin/main...HEAD` lists only the CI files, the two READMEs and the formatter changes.

### Runs
| Run | What | Result |
|---|---|---|
| 36463537503 | F2, F5 fix (`81cb45c`) | green |
| 36463691523 | + `devEngines` range and a member `.tool-versions` (F2, F5) | `discover` red, the other jobs skipped |
| 36463783326 | after removing the throwaways (final, `02e3ca8`) | green: discover 5 s, contracts 22 s, SPK-5 24 s, SPK-5b 15 s, client 32 s |

**Escalations.** None.
