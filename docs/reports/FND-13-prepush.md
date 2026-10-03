Archived at the merge of #303, a97f4f0.

## Report
Model: Sonnet 5.5

### Summary
PR #303, head `2c8f32272c297fdb84dae156fc2db5f36159c137` (CI on it still running: 8 pass, 10 pending, none failed at the last look; the previous head `301a5a7` was fully green, `tooling` included). Not merged.

What exists now: `scripts/prepush.sh [--all]` (runs the checks the diff calls for; builds only the touched Cairo packages, from each package's own folder, through `scripts/lock.sh --heavy`, never around the lock); `.githooks/pre-push` (`core.hooksPath` not set); `AGENTS.md`; retries on tool downloads in `ci.yml`, `tooling.yml`, `install-snforge.sh`; and the programme rule of the 90 s wait: `scripts/lock.sh` gains `--wait <s>` (both locks under one deadline, exit 75 and "build lock busy for N s" past it); pre-push waits at most 90 s, then skips the Cairo compile and the checks that build, prints one line, exits 0 for that part (fmt, the scripts' tests and any other failure still exit 1). No `flock` (the Mac): the full check runs, builds direct. `vectors/check.py` and the pnpm steps honour the same wait; `tooling.yml` tests the `--wait` cases.
### Files changed
`docs/briefs/FND-13-prepush.md`, `scripts/prepush.sh`, `scripts/lock.sh` (the `--wait` option only), `.githooks/pre-push`, `AGENTS.md`, `contracts/logic/vectors/check.py` (the lock wait only), `.github/workflows/ci.yml` (second attempt of setup-scarb x3, pnpm/action-setup x2, setup-node x2; `curl --retry 3` on devnet), `.github/workflows/tooling.yml` (`curl --retry 3` on devnet; the `--wait` test cases), `.github/ci/install-snforge.sh` (`curl --retry 3`). No trigger, permission, job condition or check changed in the workflows.
### Commands run
Real output is in the PR description. VPS, heavily loaded (other threads queue on the heavy lock for 500+ s):
- No Cairo change: `real 0m4.871s`.
- One-file Cairo change, lock busy (the 90 s skip): `real 1m32.591s`, exit 0.
- One-file Cairo change, lock free or got within 90 s: NOT obtained. 12 attempts over ~40 min all found the lock busy and skipped at 90 s (`real` 1m31.7s to 1m39.0s). The lock was not bypassed. Nearest real figure: the contracts workspace build, lock obtained, `ok in 69.6s` (in `--all`, first script version).
- `scripts/prepush.sh --all` (first script version): passed, `real 98m21.972s`, `total 5901.8s`, almost all lock waiting (`gas_budgets.py --check` 893.5s, `vectors check.py` 4374.7s); client lint/typecheck/test/prettier ok.
- shellcheck 0.9.0 (CI's version, in a scratchpad venv) clean on `scripts/*.sh`, the hook, `install-snforge.sh`. The new `tooling.yml` `--wait` cases were run locally from the workflow text: pass (9.4 s). A deliberate fmt error gave `FAILED`, `exit=1`.
### Acceptance criteria
AC-1/2: conditional checks and per-step times shown (outputs above); a failing step exits non-zero (shown). AC-3 hook executable, `core.hooksPath` untouched. AC-4 `AGENTS.md` (hooksPath once per clone, run before every push, never push red, `--all`, the lock wait, HEAD and working tree not pushed refs, the no-`flock` case). AC-5 retries only in the workflows, plus the `--wait` tests in `tooling.yml`. AC-6 shellcheck clean locally and `tooling` green on `301a5a7`; on `2c8f322` pending.
### Deviations from the task
- The free-lock one-file Cairo timing could not be measured (above).
- `scripts/lock.sh` and `contracts/logic/vectors/check.py` changed (the lock wait only), as the project manager's rule and the review asked.
- `--all` builds every package of the matrix, as CI does; with a changed root `.tool-versions` it does too.
### Escalations
- `scripts/setup-toolchain.sh` ends with `starknet-devnet: command not found` (0.10.0 not on PATH on this machine).
- A `scarb build` of `indexer/emitter`, `spikes/SPK-12` and `spikes/SPK-15` rewrote their `Scarb.lock` under 2.20.1 (FND-11 left them stale); I reverted them (outside my allowlist). Someone should commit them, or CI relocks.
- Left as the review asked: `lock.sh` exit 75 can be a command's own 75 (the busy line disambiguates); `gas_budgets.py`'s own `lock.sh` call is a second wait (bounded by the same variable).

## Next
Wait for the checks of 2c8f322, then confirm Ready to merge at that sha
Review PR #303 once its checks are green
Commit the relocked Scarb.lock of the emitter and SPK-12/SPK-15
Set core.hooksPath in the VPS and Mac clones after the merge
Remove the worktree and branch after the merge

## Remember
- Never run commands or write a heredoc with unquoted `EOF` containing backticks or `$`: the shell expands them (it mangled a PR body once). Use a quoted heredoc or the Write tool.
- On the VPS the heavy build lock is queued for hours: any measure that needs it can take 1-2 hours; plan for the 90 s bound, not a wait.
- Never name an external repository's issue or PR link or `owner/repo#N` in a commit, PR title or body.
- GitHub Actions is starved: batch the fixes of one review into one push.
