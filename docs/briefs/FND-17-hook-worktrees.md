# FND-17 — the pre-push hook works in a linked worktree and never touches the repository it runs in

## Agent
Profile: impl-opus · Branch: `hp/grimworld-game/t-0049-fnd-17-pre-push-hook-in-worktrees`

## Goal
After this task a push from a linked worktree (or the main checkout) with `core.hooksPath .githooks` runs the
checks of `scripts/prepush.sh` and leaves the repository's branches, HEADs and configuration untouched.

## Context
- 2026-10-02 19:22: a push from a linked worktree of the VPS clone ran `.githooks/pre-push` (FND-13, #303). In a
  linked worktree git exports `GIT_DIR` (the worktree's folder under the shared `.git`) to the hook; every step of
  `prepush.sh` inherited it, and the fixture of `scripts/gas_budgets.py --self-test` (`git init`, empty commits, a
  branch `branch`) ran against the real repository: a commit on the thread's branch, `branch` checked out, the
  shared config rewritten (`core.bare = true`), every worktree of the clone broken until the owner repaired it.
- Every thread of both tracks pushes from a linked worktree.
- Rule nexus #60: this brief names the workflow file it changes (below).

## Scope
- In:
  1. `.githooks/pre-push` and `scripts/prepush.sh` drop every repository variable git hands a hook
     (`git rev-parse --local-env-vars`: GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY,
     GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_PREFIX, GIT_COMMON_DIR, …, and every GIT_CONFIG*) before finding the
     work tree, so the repository is found from the folder and no step inherits one.
  2. `scripts/gas_budgets.py --self-test` (its environment only): the provenance fixture's git commands, and
     `provenance_ok` under the test, run with those variables removed, in their own temporary directory, with
     `GIT_CEILING_DIRECTORIES` above it.
  3. The other scripts `prepush.sh` runs were searched for git calls: `scripts/lock.sh`,
     `contracts/logic/vectors/check.py`, `contracts/tools/class_sizes.py`, `contracts/tools/exp2_table.py`,
     `tools/art/**` call none; scarb and pnpm get the clean environment from item 1.
  4. **Workflow file changed: `.github/workflows/tooling.yml`, test cases only**: shellcheck on the hook; a case
     that builds a scratch clone, a linked worktree, `core.hooksPath .githooks` and a local bare remote, pushes
     through the real hook from the worktree and from the main checkout, and asserts the pushes succeed, the
     clone's branches, HEADs and `.git/config` are byte-identical (core.bare false, core.worktree unset), and no
     repository variable reaches a step (a stub `scarb` fails if one does); the self-test run with GIT_DIR,
     GIT_WORK_TREE and GIT_INDEX_FILE on a decoy repository leaves the decoy unchanged.
- Out: what the checks run; any other workflow change; pins.
- Allowlist: this brief, `.githooks/pre-push`, `scripts/prepush.sh`, `scripts/gas_budgets.py` (the self-test's
  environment only), `.github/workflows/tooling.yml` (test cases only).

## Acceptance criteria
- [ ] AC-1 Reproduced in a scratch clone (never the real clone): before the fix the push from a linked worktree
  fails and writes to the repository (commit, branch, core.bare); after it the push passes and nothing changes.
- [ ] AC-2 The tooling case passes in CI; it fails on the code before the fix.
- [ ] AC-3 The self-test under GIT_DIR on a decoy leaves the decoy unchanged.
- [ ] AC-4 shellcheck clean on the hook and `scripts/prepush.sh`.
- [ ] AC-5 The real time of the hook on a push from a linked worktree on the VPS (no Cairo change), quoted.

## Verification
The reproduction script in the report; `scripts/prepush.sh`; CI's `tooling` job on Linux.

## Audit
None needed: a tooling fix with its regression test in CI; no contract, cost or determinism touched.
