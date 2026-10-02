# FND-16 — Cancel superseded pull-request runs of `tooling.yml`

## Agent
Title: `[Sonnet 5.5] FND-16 tooling.yml concurrency` · Profile: implement · Branch: `hp/grimworld-game/t-0039-fnd-16-tooling-yml-concurrency`

## Goal
After this task a new push to a pull request cancels the superseded run of the `tooling` workflow, and
runs on `main` are never cancelled. GitHub Actions is starved account-wide (the concurrent-job limit), so
every repository stops spending runners on commits nobody waits for.

## Context
- `.github/workflows/ci.yml` already has the block (lines 17-20): group `ci-<pull request number or ref>`,
  `cancel-in-progress` only for `pull_request` events. **`ci.yml` is not changed.**
- **This lot changes the workflow file `.github/workflows/tooling.yml`** (rule nexus #60), which has none.
- FND-13 (#303) also edits `tooling.yml`, elsewhere in the file: whoever merges second merges `origin/main` in.

## Scope
- In: in `.github/workflows/tooling.yml`, after `permissions:`, the same block with its own group prefix and
  the same comment:
  ```
  concurrency:
    group: tooling-${{ github.event.pull_request.number || github.ref }}
    cancel-in-progress: ${{ github.event_name == 'pull_request' }}
  ```
- Out: any trigger, permission, job, step or check of `tooling.yml`; `ci.yml`; a docs-only skip of heavy jobs.
- Allowlist: `docs/briefs/FND-16-ci-concurrency.md`, `.github/workflows/tooling.yml`.

## Acceptance criteria
- [ ] AC-1 `tooling.yml` has the block above after `permissions:`, and nothing else in it changed (`git diff`).
- [ ] AC-2 A second push to the pull request cancels the first run of `tooling` and the second runs
      (`gh run list --workflow tooling.yml --branch <branch>`), shown in the PR.
- [ ] AC-3 Runs on `main` are not cancelled (`cancel-in-progress` is false for `push`).

## Verification
Push a second, empty commit after the first PR run starts; list the runs of the branch.

## Audit
None needed.
