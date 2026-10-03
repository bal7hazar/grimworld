Archived at the merge of #350, ac10593.

## Report

Model: Opus 5.5 (claude-opus-5-5)

### Summary
Following the project manager's priority message, I tried the quick lever first and it is enough. `scripts/gas_budgets.py` now runs `snforge test --workspace --fuzzer-seed 1 --max-threads 2`. The whole workspace gas run passes under `prlimit --as=8589934592` with a peak of 4.88 GB; before the change it peaked at 8.29 GB and failed. No test, budget, vector or generated file changed. The test splits (task steps 2–3) are left for a later lot, as the project manager allowed.

Cause: snforge 0.64.0 runs one test thread per CPU (8 here). Each heavy test adds 1–2 GB of address space on top of a ~2.8 GB process baseline. Several at once go past the 8 GiB cap, and the failed allocation shows up as a test failure ("Vector capacity exceeded"). One at a time, every heavy test passes under the cap.

PR #350, head `0377572`: MERGED as `ac10593` at 2026-10-03T15:31:38Z. Ordered by the line `Merge the PR: no review (…) at 0377572ee0fc…`. I posted the comment `Review: none — …` on #350 first, then waited for the checks to finish: cairo (contracts) passed in 7m30s, discover, tooling and ci result passed, and the client, class-artefacts and indexer-node jobs were skipped. Then I ran exactly `gh pr checks 350 && gh pr merge 350 --squash --match-head-commit 0377572ee0fc401a798c57ec6de20654eb697140`.

### Files changed
- `scripts/gas_budgets.py`: `--max-threads 2` on the snforge call, with a comment giving the figures; the docstring updated to match. It is on the allowlist for this lever, and the PR says so.

### Commands run (all on the VPS, under `prlimit --as=8589934592`, VmPeak sampled over the process tree from `$!`)

Whole runs:

| Run | Result | Peak | Wall |
| --- | --- | --- | --- |
| `gas_budgets.py --check`, 8 threads (main) | FAIL `window::tests::test_shapes_every_centre_0`: "Vector capacity exceeded" | 8.29 GB | 199 s (may include a build) |
| same, `--max-threads 4` | pass | 7.11 GB | 127 s |
| same, `--max-threads 2` (kept) | pass | 4.88 GB | 160 s |
| `contracts/logic/vectors/check.py` | 4 tables "as computed" (window 2065, hit 200, fate 218, packing 520) | 4.03 GB | 69 s |
| `git push` (pre-push hook: fmt, self-test, `gas_budgets.py --check`: 956 tests, 4 files current) | all checks passed | 5.92 GB (whole hook tree) | 176 s |

Each heavy test alone (peak before; after: unchanged, since the tests did not change):

| Test | Gas | Peak |
| --- | --- | --- |
| `window::tests::test_sight` (baseline, a light test) | 114,606 | 2.78 GB |
| `window::tests::test_vectors` | 1,205,575,917 | 4.87 GB |
| `hit::tests::test_vectors` | 915,710,825 | 3.83 GB |
| `window::tests::test_shapes_every_centre_0` / `_3` | 875,624,260 / 877,075,110 | 3.83 GB |
| `window::tests::test_line_against_oracle_edges` | 448,517,490 | 2.78 GB |
| `window::tests::test_vectors_1` | 418,043,405 | 2.84 GB |

Measured with a scratch script: the command ran in the background, and its tree was walked from `$!` through `/proc/<pid>/task/*/children`. Nothing was signalled.

I couldn't re-run the 8-thread case on a warm build to compare wall times fairly: that command was refused, so the 199 s may include compile time.

### Acceptance criteria
- Cause found statically, then measured capped one test at a time: see the tables above.
- Whole workspace run under the cap with its peak: `gas_budgets.py --check` 4.88 GB; `check.py` 4.03 GB; the pre-push hook passed on this push.
- Every vector "as computed", no test's result changed: `check.py` output above; `gas_budgets.py --check` reports every budget current.
- Budgets regenerated for split tests: none split, no gas moved, nothing for D-144.
- Splits of the shape and vector tests: not done. Per the project manager's instruction they wait for a later lot.

### Deviations from the task
- Steps 2–3 (the splits) are not done, on the project manager's instruction ("open the PR with that alone").
- 4 threads also passed (7.11 GB). I chose 2 so the peak stays well under the cap. CI's gas job also runs on 2 threads now, so it may be slower there.

### Escalations
None.

## Next
Tell CBT-05a (#334) and ENG-05 (#348) to merge main (ac10593) and push again
Remove this thread's worktree and branch
Brief the later lot: split the shape and vector tests so snforge can run more threads

## Remember
- Under `prlimit --as`, snforge's peak is roughly 2.8 GB plus the sum of the heavy tests running at once; `--max-threads` is the lever.
