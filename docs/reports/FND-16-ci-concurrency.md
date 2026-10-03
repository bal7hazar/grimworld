Archived at the merge of #312, 8ab3949.

## Report

Model: Sonnet 5.5

### Summary
`tooling.yml` now has the same `concurrency` block as `ci.yml` (group prefix `tooling-`, cancel only on `pull_request`), after `permissions:`, with the same comment. The brief `docs/briefs/FND-16-ci-concurrency.md` names the workflow file and says `ci.yml` is not changed.

### Files changed
- `.github/workflows/tooling.yml` (+5 lines)
- `docs/briefs/FND-16-ci-concurrency.md` (new)

### Commands run
- `gh pr create` (#312); empty second commit `a0525a9` pushed while the first run was queued
- `gh run list --workflow tooling.yml --branch hp/grimworld-game/t-0039-fnd-16-tooling-yml-concurrency`:
  - `queued  … pull_request 37034546991 (second push)`
  - `completed cancelled … pull_request 37034493927 (first push)`

### Acceptance criteria
- AC-1 block added, nothing else changed: `git diff --stat` shows 1 file, 5 insertions in the workflow.
- AC-2 the first PR run of `tooling` (37034493927) was cancelled by the second push; the second (37034546991) is the live one. Posted as a comment on #312 (review minor 1); head unchanged.
- AC-3 `cancel-in-progress` is `false` for `push` events by the expression.

### Deviations from the task
None. Head sha `a0525a9d6f08aae6b7895a6ac90068d142ee0310` (the empty commit; the change is in the first commit).

### Escalations
- Review minor 1 fixed: proof posted as one comment, no commit. Note 2 (one pending run per group on main) left as for ci.yml.
- The second `tooling` run was still queued (runners starved), so its checks are not green yet.

## Next
Wait for the checks of #312 to turn green
