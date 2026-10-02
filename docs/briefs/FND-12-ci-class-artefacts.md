# FND-12 — The contracts' class files built at CI's checkout root, kept as an artefact

> SPK-13b (#283): class hashes and Sierra file hashes depend on the absolute build path (closure type
> names), so a class built in a worktree differs from one built in CI, even on Linux; gas, Sierra felt
> counts and CASM do not. The build-root rule (#290, the project manager's, going into `OPERATIONS.md`)
> makes CI's checkout root the one root a declared class is built at. **No class is declared on Sepolia
> under that rule until this lot lands.**

## Agent
Title: `[Sonnet 5.5] FND-12 CI class artefacts` · Profile: implement · Branch: `hp/grimworld-game/t-0017-fnd-12-ci-class-artefacts`

## Goal
After this task every run of CI on a pull request and on `main` builds the contracts at CI's checkout
root and keeps the class files as a workflow artefact, with a record of the root path, the commit, the
Scarb version and the runner's OS, so that a declaration can name the exact files it declared and the
root they were built at. This lot only builds and keeps files: no declaration, no sending, no secret.

## Context
- **SPK-13b, #283** (merged; `spikes/SPK-13b/README.md`): the path reaches the Sierra type ids of closures
  (`{closure@<absolute path>/…}`), hence the Sierra text and the class hash; Sierra felt count,
  `withdraw_gas` count, CASM felts and CASM sha256 do not move with it. With the path normalised, Mac and
  Linux agree.
- **#290** (the build-root rule, open when this brief was written): the reference build root is CI's
  checkout path; class hashes are pinned only from CI's output with the root recorded; classes declared on
  a network are CI-built class files, never a local worktree build.
- **`.github/workflows/ci.yml`**: the `cairo` matrix builds every package with `scarb build --workspace`;
  `discover` validates the toolchain versions (exact x.y.z) before any setup step, and every action is
  pinned by SHA. FND-11 (Scarb 2.20.1, the `RAYON_NUM_THREADS=1` pin of D-176) edits the same file at the
  same time: whoever merges second merges `origin/main` in.
- OPERATIONS §7 (deployments record the class hash and the commit, D-154); CAIRO.md §2 (D-176).

## Scope
- In:
  - **A job of its own**, `class-artefacts`, in `ci.yml`, on the workflow's triggers (every pull request
    and every push to `main`). Why a job of its own: the `cairo` job runs in a matrix, builds as a side
    step of tests and the gas gate and restores a cache of `target/`; the artefact must come from one clean
    build of exactly `contracts/`, whose result nothing else touches, and an extra step in the matrix would
    upload once per package. It needs `discover` for the validated Scarb version of `contracts`.
  - Its steps: checkout (no credentials kept), `setup-scarb` at the contracts' pin, `scarb build
    --workspace` in `contracts/` with `RAYON_NUM_THREADS=1` set in the step (the repository's build pin,
    D-176; FND-11 moves it to the repository's one place if it lands first), then `actions/upload-artifact`
    (pinned by SHA) of `contracts/target/**/*.contract_class.json`, `*.compiled_contract_class.json` and a
    small `build-root.json`, named `contract-classes-<commit sha>`, retention 90 days (the maximum of the
    default plan: long enough for a declaration to follow its merge by weeks), `if-no-files-found: error`.
  - `build-root.json`: `root` (`$GITHUB_WORKSPACE`), `commit` (the commit built: the pull request's head,
    not the merge commit), `scarb` (the version scarb reports), `os` (the runner's OS and image).
  - **OPERATIONS.md §7**: the deployment record also names the CI root path and the artefact (run id or
    URL, and name) the declared class came from. One or two sentences.
- Out: anything in `contracts/`; any class hash or Sierra file hash pinned or compared (#283); declaring,
  sending, any secret; the discover script; the other jobs.
- Allowlist: `docs/briefs/FND-12-ci-class-artefacts.md`, `.github/workflows/ci.yml`, `OPERATIONS.md` §7
  (the deployment record only). Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 On the pull request, the `class-artefacts` job runs, builds `contracts/` at CI's checkout root
      and uploads an artefact named `contract-classes-<sha>` holding the class files of the packages that
      declare and `build-root.json`.
- [ ] AC-2 `build-root.json` holds the right values (root = the job's `$GITHUB_WORKSPACE`, the head
      commit, the Scarb version, the runner's OS), quoted in the report from the downloaded artefact.
- [ ] AC-3 The retention is stated (90 days) and the job fails if no class file is found.
- [ ] AC-4 OPERATIONS.md §7's deployment record names the CI root path and the artefact; nothing else in
      OPERATIONS changes.
- [ ] AC-5 Nothing in `contracts/` changed; no class hash or Sierra hash pinned or compared; no secret; the
      token stays read-only; the action is pinned by SHA.

## Audit
None expected (D-177): a CI job and one sentence of documents; the review and the checks.

## Verification
```
python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/ci.yml"))'
gh run view <run id> --json jobs
gh run download <run id> -n contract-classes-<sha> && cat build-root.json
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the job and why it is its own, the artefact's name and
retention, `build-root.json` quoted from the artefact, the files it holds (names, count), the FND-11
overlap.
