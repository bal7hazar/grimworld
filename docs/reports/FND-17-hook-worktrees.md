Archived at the merge of #327, aa5bcc1.

## Report

Model: Opus 5.5 (claude-opus-5-5)

### Summary
- Cause, measured in a scratch repository: in a linked worktree git exports
  `GIT_DIR=<clone>/.git/worktrees/<name>` to the pre-push hook (the main checkout gets only `GIT_EXEC_PATH`,
  `GIT_PREFIX`). prepush.sh's steps inherited it, and `gas_budgets.py --self-test`'s `git init` in its temporary
  folder re-initialised the real repository (core.bare = true), committed into it and checked out `branch`.
- `.githooks/pre-push` and `scripts/prepush.sh` now unset `$(git rev-parse --local-env-vars)` and every
  `GIT_CONFIG*` before finding the work tree: the repository comes from the folder, no step inherits a
  repository variable (scarb, pnpm, Python included).
- `scripts/gas_budgets.py`, self-test only: the provenance fixture and `provenance_ok` under it run with those
  variables removed (`mock.patch.dict(os.environ, clean, clear=True)` + explicit `env=`), with
  `GIT_CEILING_DIRECTORIES` above the temporary repository.
- Other scripts prepush runs (`scripts/lock.sh`, `contracts/logic/vectors/check.py`,
  `contracts/tools/class_sizes.py`, `contracts/tools/exp2_table.py`, `tools/art/**`): none calls git; nothing changed.
- CI: `tooling.yml` gains shellcheck on the hook and a step `pre-push hook in a linked worktree` (scratch clone
  from `git archive HEAD`, linked worktree, hooksPath, local bare remote; real pushes from the worktree and from
  the main checkout; prepush.sh by hand with GIT_DIR exported; branches, HEADs, `.git/config` byte-identical,
  core.bare false, core.worktree unset; a stub `scarb` fails if a repository variable reaches a step; the
  self-test with GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE on a decoy leaves it unchanged).

### Files changed
- `docs/briefs/FND-17-hook-worktrees.md` (new)
- `.githooks/pre-push`, `scripts/prepush.sh`
- `scripts/gas_budgets.py` (`test_provenance_needs_an_ancestor_of_main` only)
- `.github/workflows/tooling.yml` (test cases only, edited with the file-editing tool: shellcheck line + one new step)

Commits: ec16172, 8cf699d, 2688cdd (head).

### Commands run
All reproduction work in `/tmp/claude-1000/.../scratchpad` only (copies in the library folder):
- `hookenv.sh`: the hook's GIT_* vars. Main checkout: `GIT_EXEC_PATH`, `GIT_PREFIX=`. Linked worktree: also
  `GIT_DIR=.../c/.git/worktrees/wt`.
- `repro.sh <worktree> d1f3e93 before` (pre-fix): `push rc=1 in 3.1s`; self-test `FAIL:
  test_provenance_needs_an_ancestor_of_main`; clone diff: config `core.bare=true`, new `refs/heads/branch 7742506`,
  `feature` moved 2111c4e → 1630b5e, worktree HEAD → `refs/heads/branch`.
- `repro.sh <worktree> 2688cdd final` (fixed): `push rc=0 in 2.7s`; `prepush: total 2.3s` (fmt 1.9 s, self-test
  0.4 s); `prepush: all checks passed`; branches, HEADs, config identical.
- `ci_case.sh` (runs the new tooling step on a `git archive` of a commit, optional files restored from d1f3e93):
  fixed `step rc=0`; mutant all three files `step rc=1` (`stub scarb: GIT_DIR reached a step`, self-test FAIL);
  mutant self-test only: the clone's `refs/heads/branch` appears, `step rc=1`; mutant hook+prepush only:
  `stub scarb: GIT_DIR reached a step`, `step rc=1`; mutant prepush.sh only: the by-hand run fails, `step rc=1`.
- shellcheck 0.11.0 (scratch venv, `shellcheck-py`): `shellcheck scripts/*.sh .githooks/pre-push` rc 0; the new
  step extracted, `shellcheck -s bash` rc 0.
- Own push: `time git push origin <branch>` → `real 0m1.936s`, **with no prepush output: the hook did not run**
  (core.hooksPath not set in `/home/claude/projects/grimworld` now, apparently; reading the clone's config is
  refused to me, and I did not touch it). Clone config sha256 `ec8fc8ea…` identical before and after; no
  `refs/heads/branch`.
- `time .githooks/pre-push` in this worktree (the real hook, real worktree, no GIT_DIR): `real 1m32.165s` —
  fmt 1.6 s, self-test 0.2 s, then `gas_budgets.py --check` SKIPPED after waiting 90.1 s for a busy build lock
  (my diff touches `scripts/gas_budgets.py`, a gas input; and see the shallow-clone escalation).

### Acceptance criteria
- AC-1 Reproduction before/after: `repro.sh` lines above (fail + writes before; pass + nothing changed after).
- AC-2 tooling case: passes locally on the fix and fails on every mutant; CI: `tooling` pass in 2m6s at 2688cdd
  (run 37099620462); every other check green at 2688cdd too (cairo contracts 6m8s, spikes, class-artefacts,
  client; indexer-node skipped by path filter).
- AC-3 Decoy: part of the tooling step (`diff decoy-before decoy-after`), passing locally.
- AC-4 shellcheck: clean (above).
- AC-5 Time on the VPS, push from a linked worktree, no Cairo change: **2.7 s** for the whole `git push` through
  the hook (prepush 2.3 s), scratch clone at 2688cdd. The real clone's own push did not run the hook (not enabled).

### Deviations from the task
- The CI test is inline in `tooling.yml` rather than a test file like quiver's `scripts/test_hook.py`: the allowlist
  admits no new file.
- `scarb` is a stub in the CI step (the tooling job has no Cairo toolchain); it doubles as the env probe.
- Pushed without `-u` (it would write the branch's upstream to the shared config and blur the before/after check).

### Escalations
- core.hooksPath appears not set in the VPS clone (my push ran no hook). Re-enabling it is the owner's (memory:
  no thread sets it); safe once this PR is on main.
- The VPS clone is shallow (`git rev-parse --is-shallow-repository` → true): `git merge-base origin/main HEAD`
  fails, prepush.sh falls back to origin/main itself as base, and counts main's newer files as changed (12 files
  here instead of 5), which can widen the checks run. Out of FND-17's allowlist; a later lot (or unshallowing the
  clone) fixes it.

## Next
Ready to merge at 2688cdd once reviewed
Send PR #327 to review (Opus wrote it: review with Sonnet)
Ask the owner to re-enable core.hooksPath in the VPS clone once #327 merges
Brief a lot for prepush's base in a shallow clone
Remove the worktree and branch once merged

## Remember
- In a linked worktree git exports GIT_DIR to hooks; any fixture `git init` in a hook's child writes the real repo.
- Test scripts that create git repositories must strip `git rev-parse --local-env-vars` and GIT_CONFIG* first.
- `git push -u` writes the shared config: don't use it when comparing config before/after.
