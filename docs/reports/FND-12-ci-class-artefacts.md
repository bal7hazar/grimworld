Archived at the merge of #291, f1a0b41.

## Report

Model: Sonnet 5.5

### Summary
CI now builds `contracts/` once at CI's checkout root and keeps the class files as an artefact. A new job `class-artefacts` in `.github/workflows/ci.yml` runs on every pull request and every push to `main`. It is a job of its own, not a step of the `cairo` matrix: the matrix builds as a side effect of tests and the gas gate, from a restored `target/` cache, and a step there would upload once per package. The job needs `discover` for the validated Scarb version of `contracts`.

It runs `scarb build --workspace` with `RAYON_NUM_THREADS=1` set in the step. FND-11 had not landed the pin, so it is set here. It then uploads the class files and `build-root.json` as `contract-classes-<head sha>`, retention 90 days, `if-no-files-found: error`. The action is pinned by SHA (`actions/upload-artifact` v7.0.1, `043fb46d…`). OPERATIONS §7's deployment record now also names the CI root and the artefact.

Head: `68ae010e1b5305b9b78130706ea74df1abc5eed6` (after the Opus review's fixes below). Both CI runs on it succeeded (every `cairo` job, `class-artefacts`, `client`, `discover`, `tooling`); `indexer-node` is skipped, as designed. I did not merge.

### Review fixes (Opus, FAIL at 655c44f; all three fixed)
1. Major, not a clean build: `setup-scarb` now has `cache: false`, `rm -rf contracts/target` runs before the build, and the upload excludes `!contracts/target/**/*.test.*`.
2. Minor, merge commit vs head: the job's checkout uses `ref: head sha || github.sha`, so the build, the artefact name and `build-root.json`'s `commit` are one commit. The job's comment says so.
3. Note: OPERATIONS §7 says a declared class comes from the artefact of a push to `main`, never of a pull request's run.
The brief is updated for all three.

Proof (run 37008580863 at 56ca696): the artefact `contract-classes-56ca69649150dae286a11d8b57127a955b8ca300` has 23 files: `build-root.json` and 22 class files (11 classes × 2), nothing else. The 11 are persistent {Hub, Market, Registry, TxHashFate, FlattenLibrary}, logic {TickLibrary, FlattenLibrary}, ephemeral {Instances, CallProbe, EventProbe, ReuseProbe}. No `*.test.*` files. `build-root.json`: root `/home/runner/work/grimworld/grimworld`, commit `56ca69649150dae286a11d8b57127a955b8ca300`, scarb `2.19.4`, os `Linux ubuntu24 20260927.320.1`.
Correction: my first report and the brief said 10 classes. It is 11 (22 class files plus `build-root.json` = 23 files, in the first run too). The brief now says 11. The head moved to 68ae010 for that docs-only fix; I did not re-download the artefact from that run.

### Files changed
- `docs/briefs/FND-12-ci-class-artefacts.md` (new, first commit)
- `.github/workflows/ci.yml` (job `class-artefacts`)
- `OPERATIONS.md` (§7 deployment record, one sentence)

### Commands run
- `gh pr view 283` and `gh pr view 290`: #283 is merged, #290 was still open.
- `git ls-remote` for the `upload-artifact` v7.0.1 tag SHA.
- YAML parse of `ci.yml`.
- `gh pr checks 291` until no check was pending.
- `gh run download 37005883267` and `37008580863` with `-p 'contract-classes-*'` and a listing of the downloaded files.

### Acceptance criteria
- AC-1 (met): the `class-artefacts` job passes; the artefact of run 37008580863 (proof above) holds exactly:
  - `grimworld_persistent_*`: Hub, Market, Registry, TxHashFate, FlattenLibrary
  - `grimworld_logic_*`: TickLibrary, FlattenLibrary
  - `grimworld_ephemeral_*`: Instances, CallProbe, EventProbe, ReuseProbe
  - each as `.contract_class.json` and `.compiled_contract_class.json`, 11 classes in all
- AC-2 (met): `build-root.json` from the downloaded artefact of run 37008580863:
  ```json
  {
    "root": "/home/runner/work/grimworld/grimworld",
    "commit": "56ca69649150dae286a11d8b57127a955b8ca300",
    "scarb": "2.19.4",
    "os": "Linux ubuntu24 20260927.320.1"
  }
  ```
  The commit equals the head of that run (56ca696); the PR head is now 68ae010 (docs-only change to the brief).
- AC-3 (met): retention is 90 days and `if-no-files-found: error` is set. I did not run a negative case, and I did not read the expiry date from the API (`gh api` was denied in this session).
- AC-4 (met): only the deployment-record sentence changed in OPERATIONS.
- AC-5 (met): nothing in `contracts/` changed, no class hash or Sierra hash is pinned or compared, no secret is used, the token stays read-only, and the checkout uses `persist-credentials: false`.

### Deviations from the task
- None in scope. The retention figure of 90 days is my choice; the task asked for it to be stated.
- `build-root.json`'s `os` field is `RUNNER_OS` plus `ImageOS` plus `ImageVersion` (for example `Linux ubuntu24 20260927.320.1`), richer than just `Linux`.

### Escalations
- FND-11 edits `ci.yml` at the same time. Whoever merges second must merge `origin/main` in. FND-11 may move `RAYON_NUM_THREADS=1` to the repository's one place; the step here sets it itself, and says so in its comment.
- #290 (the build-root rule) was still open when I looked. OPERATIONS §7's new sentence stands without it, but the two should land together.

## Next
Review the PR with a model other than Sonnet
Ready to merge at 68ae010e1b5305b9b78130706ea74df1abc5eed6
Remove the worktree and branch once merged

## Remember
- An `actions/*` tag can be resolved to its commit SHA with `git ls-remote https://github.com/<owner>/<repo> 'refs/tags/<tag>'` when `gh api` is denied.
