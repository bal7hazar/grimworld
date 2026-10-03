Archived at the merge of #331, ffef058.

## Report

Model: Sonnet 5.5 (claude-sonnet-5-5)

Unblocked after the clone repair: merged origin/main (merge commit `a2977c0`, contains aa5bcc1, checked `yes`), one push, PR opened. Head `a2977c07acbd9a389767fd57ee5f40df703f1d5c`. Checks not yet polled.

### Summary
The game is moved to hexx 0.1.0-rc.2 and every local check is green. The push failed (see Escalations).

### Files changed
- `contracts/Scarb.toml` (line 13: `hexx = "0.1.0-rc.2"`), `contracts/Scarb.lock`
- `spikes/SPK-12/Scarb.lock` and `spikes/SPK-15/Scarb.lock`: both rewritten by their builds (hexx rc.1 to rc.2, same checksum). The other spikes do not depend on `contracts/logic`.
- `contracts/{logic,persistent,ephemeral}/GAS.md`, `docs/BUDGETS.md`: regenerated, **no figure moved**. Only the Date and Commit columns changed (see Deviations).
- No code change: no API the game calls changed.

### Commands run
- `scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build`: ok, 76 s. The hexx lock entry reads:
  `name = "hexx"`, `version = "0.1.0-rc.2"`, `checksum = "sha256:c4bf8aef830ca5ed0d9ebc02ad82aeea637ae96ab7311bbf522fc8d4d613a753"` (equals the expected one).
- `snforge test` in contracts/logic (through `lock.sh --heavy`): **655 passed, 0 failed**. `persistent` and `ephemeral` use hexx only through `grimworld_logic` (not run separately; their tests are covered by `gas_budgets.py`'s 938 tests).
- `python3 contracts/logic/vectors/check.py`: window.jsonl 2065 cases **as computed**, hit.jsonl 200, fate.jsonl 218, packing.jsonl 520, all as computed.
- `python3 scripts/gas_budgets.py` then `--check`: "938 tests, every budget is ceil(1.05 x measured) or lower, 4 files current".
- `python3 contracts/tools/class_sizes.py`: all ok (Hub 45.89 %, the largest). I did not diff it against an earlier run.
- `scripts/prepush.sh`: all checks passed. Its vectors check was skipped because the build lock was busy for 90 s (the documented skip); I ran that check myself, above.
- `git push -u origin HEAD`: **failed** (see Escalations).

### hexx changelog, rc.1 to rc.2 (`CHANGELOG.md` at v0.1.0-rc.2, hexx-cairo, read-only)
- "Results changed: None. Every function of 0.1.0-rc.1 returns the same result for the same input."
- Changes to files of rc.1 are additions (N-1, N-2, N-6) and gas budgets re-measured on Cairo 2.20.0 (lower or equal gas).
- Fixed: `Caver::smooth` ignores stray `grid` bits. It is new in rc.2, so no published result changes.
- Requires Cairo >= 2.20.0, which the game already uses (2.20.1).
- Touching the game's calls: `git grep "hexx::"` shows `grimworld_logic::types::window` (`Bits`, `Direction`, `DirectionTrait`, `LayoutTrait`, `LineTrait`, `HexMap`, `Arc`), `contracts/logic/tests/test_hexmap.cairo` (`GeometryTrait`), and SPK-14 (git rev, not touched). None of these changed: it all compiled, 655 tests pass and window.jsonl is as computed.

### Budget moves
None: measured and budget columns are identical to HEAD for all 938 rows (compared by stripping the date/commit columns). Nothing is on the expedition path and nothing is above +10 %, so nothing goes to the PM for D-144.

### Acceptance criteria
- Lock checksum equals the expected one: shown above.
- window.jsonl unmoved: `check.py` "as computed".
- Tests, budgets and class sizes: shown above.
- `prepush.sh`: green (vectors check skipped on a busy lock, run by hand instead).
- PR titled `chore(contracts): FND-19 hexx 0.1.0-rc.2`, `Audit: none needed`: **not met, blocked.**

### Deviations from the task
- The regenerated GAS.md and BUDGETS.md carry only new date/commit stamps (`2026-10-03`, `aad6d6c`). Before regenerating, `gas_budgets.py --check` already failed on HEAD with "date 2026-10-02 / commit f55176c do not verify". I committed the regenerated files so that `--check` is green. If you prefer no churn, revert them and treat `--check` as failing on main too.
- main has moved (`aa5bcc1`); this branch is on `aad6d6c`. CBT-05a also regenerates these files: whoever merges second merges origin/main and regenerates.

### Escalations
1. **The push is refused and the clone looks damaged.** `git push` ran `.githooks/pre-push`, which printed `fatal: this operation must be run in a work tree` and `/scripts/prepush.sh: No such file or directory` (the hook's `git rev-parse --show-toplevel` returned nothing). Afterwards even `git status` and `git merge` fail with "fatal: this operation must be run in a work tree", while `git log` still works. That is the signature of `core.bare=true` in the shared clone config (the repair the standard assigns to the coordinator). I cannot confirm it: my `git config` read was refused. I did not skip the hook, touch the config or any other worktree, or use another route to push. main's `aa5bcc1` (FND-17, "the pre-push hook works in linked worktrees") fixes the hook but is not in my branch.
2. Needed from the coordinator: repair the clone (`core.bare` false, a stray `core.worktree` removed) and prompt me again. I will then merge origin/main (fixed hook), regenerate GAS.md/BUDGETS.md if the merge conflicts, run `scripts/prepush.sh`, push once, open the PR and report.

### Update after the merge
- Conflicts only in generated files (ephemeral/persistent GAS.md, BUDGETS.md): took main's, regenerated with `gas_budgets.py`; no figure differs from origin/main (956 tests, `--check` ok).
- `scripts/prepush.sh` by hand: all passed; its vectors step was skipped again on the busy lock, so I ran `check.py` by hand: all four files as computed.
- The earlier Escalations are resolved (clone repaired by the coordinator).

## Next
Review PR #331 (hexx bump, no code change) and merge when checks are green
