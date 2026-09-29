# [Sonnet 5.5] FND-09 — with-node.sh on macOS and a full-archive node

## Summary
`scripts/with-node.sh` now runs where `setsid` is absent (macOS) and takes `--full-archive`. On Linux with `setsid` it behaves as before. PR: https://github.com/bal7hazar/grimworld/pull/152 (all checks green). The model matches the brief's title.

- **Fallback chosen: perl.** `perl -e 'use POSIX (); POSIX::setsid() != -1 or die …; exec { $ARGV[0] } @ARGV; … exit 127' -- <command>`. It calls setsid(2), the same system call as `setsid(1)`, then `exec`s, so the pid stays the command's and equals the new group id. The script's background job is never a group leader in a non-interactive shell, so setsid(2) succeeds. The script keeps recording the pid as the pgid, and the existing `stop_group` (`kill -- -pgid`) hits the command and its descendants and nothing else. If setsid(2) or the exec fails, the command does not run (127). It never falls back to running in the script's own group, which the cleanup would then signal.
- **Why perl:** it ships with macOS. `python3` on a stock Mac is a Command Line Tools stub. `set -m` would make the shell's job control affect signals and the terminal. If neither `setsid` nor `perl` exists, the script exits 127 before starting a node.
- **Devnet flag:** `--state-archive-capacity full` (default `none`; values `none, full`), read from `starknet-devnet --help` of the pinned 0.10.0. `--full-archive` passes it.
- **Not verified:** I did not run the fallback on macOS itself. It was exercised on Linux with `setsid` hidden from PATH.

## Files changed
- `scripts/with-node.sh`: `--full-archive`, setsid/perl selection, usage text and header.
- `.github/workflows/tooling.yml`: new `with-node` step. It does not touch the other fixtures.

## Commands run
- `starknet-devnet --version` gave 0.10.0. `starknet-devnet --help` gave the `--state-archive-capacity` option.
- Local: `scripts/with-node.sh --full-archive sh -c '…ps…'` showed `starknet-devnet --seed 0 --state-archive-capacity full --port 26570`.
- I could not run the whole fixture, nor the fallback path, locally: my profile refused running the extracted script and a command with a modified PATH. CI was the verification.
- shellcheck is not installed here. CI's first run failed on SC2016 for the perl one-liner (fixed with a `disable` directive and a reason, commit 0182bc7).
- CI run 36568221325, `tooling` job, `with-node` step:
  - `with-node cases ok: setsid`
  - `with-node cases ok: no setsid (perl fallback)`
  - `node: starknet-devnet --seed 0 --state-archive-capacity full --port 25617`
  - `block 0: …"result":["0x3635c9adc5dea00000","0x0"]`, `latest: …["0x3635c9adc5dea003e8","0x0"]`
  - Without the flag: `node: starknet-devnet --seed 0 --port 34827` and `block 0: …"No state at block Number(0); consider running with --state-archive-capacity full"`.
- `gh pr checks 152`: every check passes (tooling, cairo ×9, client, discover).

## Cost
—

## Acceptance criteria
- **AC-1:** the fixture runs `cases` twice, with `PATH` as is and with `PATH` rebuilt without `setsid` (the check that `setsid` is invisible is asserted).
  - Group: the command's pid equals its pgid, which differs from the script's group. The node is dead afterwards.
  - Exit: the status is 3, and a `sleep` child left behind is dead.
  - Signal: SIGTERM gives status 143, the child is dead and the node port is closed.
  - Timeout: status 124, the child is dead and the node port is closed.
  - Also checked: a missing command gives 127 on the fallback path, and a PATH with neither `setsid` nor `perl` is refused (127, "neither setsid nor perl").
- **AC-2:** flag on the node's command line, a block-0 balance read answering after a mint, and the same read refused without the flag (output above).
- **AC-3:** the repository had no with-node fixtures before this step, so "the existing fixtures" are the pre-existing `tooling` steps, all green. shellcheck (0.9.0 in CI) is clean after the SC2016 fix. CI is green.

## Deviations from the brief
- The `with-node` fixture step downloads the pinned devnet release (x86_64 Linux tarball) on the runner when `starknet-devnet` is not on PATH, and verifies its sha256 against the pin in `scripts/setup-toolchain.sh` before running it. The brief did not mention how CI would get the node.

## Escalations
None.

## Open questions
None.

## Fix loop 1
Audit finding (major, [GPT-6-Sol] on 0182bc7): the perl fallback exited 1, not 127, when setsid(2) failed. Merged `origin/main` first. Fixed at 18b84a6, CI green (all checks pass, `tooling` included).

- **Fix (`scripts/with-node.sh`):** the one-liner now prints `with-node: setsid: <error>` and does `exit 127` when `POSIX::setsid() == -1`. It no longer uses `die`, which took errno as the exit status. An exec failure still exits 127. In neither case does the command run.
- **Mistake on the way, caught by the new fixture:** my first version tested `defined(POSIX::setsid())`. Perl's `POSIX::setsid` returns -1 on failure, not undef, so that test ignored the failure and the command ran (fixture: `rc=0`, `ran` file present). The check is now `!= -1`.
- **Fixture (`tooling.yml`, `with-node` step):** a `perl` wrapper placed first on the PATH makes perl a process-group leader with a second live member. It calls `POSIX::setpgid(0,0)` and forks a `sleep 5` child in that group, then execs the real perl. Linux refuses setsid(2) with EPERM to such a process; a lone leader is not enough, as a first attempt using `setpgrp` alone showed. The fixture asserts exit status 127, a `setsid:` message on stderr, and that the command (`touch <file>`) did not run. It passed in CI after the `!= -1` fix, and it failed while the `defined` bug was present, so it does detect the defect.
- Not run locally: my profile refuses PATH-modified and perl one-liner commands, so all verification was on CI.
