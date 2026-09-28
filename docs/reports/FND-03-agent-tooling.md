# [Opus 5.5] FND-03 — Agent tooling

Executed by the game orchestrator itself, as its mandate asks
([docs/briefs/ORCH-game.md](../briefs/ORCH-game.md) §3). Pull request
[#8](https://github.com/bal7hazar/grimworld/pull/8). Audit by `[GPT-6-Sol]` (lenses S and Q):
[FND-03-audit-gpt-6-sol.md](FND-03-audit-gpt-6-sol.md).

## Summary

The game can now launch, watch, resume and close sub-agents safely on the VPS:

| File | What |
|---|---|
| `scripts/agent.sh` | Launcher: `claude` agents as transient systemd user units `grimworld-<task>-<hhmmss>` whose description carries the model tag; `codex` auditors detached with `setsid` in a whitelisted environment (their sandbox cannot start in a unit on this kernel); `status`, `wait`, `sid`, `model`; `--dry-run`, `--with-assets`, `--branch`; resume with context; the foreground rule appended to every prompt; the model that actually ran recorded in the log (`model=`) and checked by `status` |
| `scripts/profiles/{research,audit,implement}.txt` | Permission profiles passed as `--permission-mode acceptEdits --allowedTools … --disallowedTools …`; never `--dangerously-skip-permissions`; codex read-only only |
| `scripts/lock.sh` | Project lock, then the machine-wide heavy lock; build and test subcommands of scarb, snforge, sozo and pnpm only; refuses a reversed order |
| `docs/briefs/COMMON.md` | Rules every brief inherits |
| `.github/workflows/tooling.yml` | shellcheck; launcher and lock assertions; no image, audio, font or atlas file; the `assets` pointer unchanged in every pull request |
| `OPERATIONS.md` §3, §4, §7 | Locks, the codex exception, the launcher, what profiles enforce and what they cannot, concurrency measured, how the `assets` pointer moves |

## Verification

| Check | Result |
|---|---|
| Dry-run `smoke claude sonnet new "x" research` | `claude -p … --model claude-sonnet-5 --name '[Sonnet 5] smoke' --permission-mode acceptEdits --allowedTools … --disallowedTools … --max-turns 400 --output-format text`; no `--dangerously` flag (also asserted in CI for every profile and model) |
| Real launches (logs in `.claude/worktrees/logs/` of the main checkout) | `smoke` to `smoke6` on `claude-sonnet-5`, each a systemd unit listed by `status`, log ending `model=claude-sonnet-5` then `exit=0` |
| Permissions, as observed | Unlisted commands refused (`python3`, `curl`, `node`, `git commit` in `research`); file commands allowed inside the worktree and refused outside it, quotes, `$HOME` and `..` included; deny rules applied (`git stash`, `gh pr merge`, `ls ~/.local/bin`); pushing only as `git push -u origin HEAD` or `git push` (`-uf` and `:branch` refused) |
| codex | Read-only sandbox fails in a unit (`bwrap: … uid map: Permission denied`, AppArmor restriction on user namespaces); works detached with `setsid`; a run counted 0 environment variables matching `token|secret|key` |
| Lock | A second call waited 3.5 s behind a held project lock; nested calls take the missing lock in order; a reversed order is refused (exit 3) |
| Concurrency | Empty Dojo 1.8.0 project: `scarb build` 1.4 GB peak, 11 s; `claude` agent about 0.3 GB; budget kept at 3 |

## Cost

| | |
|---|---|
| — | No Cairo in this task |

## Deviations from the brief

- **codex does not run as a systemd unit**: its read-only sandbox cannot start there on this
  kernel. It is detached with `setsid` in the app's cgroup, keeping the sandbox; an app restart
  kills a running audit, which is then resumed. Running it without sandbox was not an option.
- The profiles give no rule for `mkdir`, `touch`, `cp`, `mv`, `rm`: `acceptEdits` approves them
  inside the worktree and refuses them outside, which is stricter than any prefix rule.
- Additions not in the brief: the `model` subcommand and `model=` log line (the project
  manager's request of 2026-09-28), `--branch`, `sid`, the `assets` pointer check.

## Audit

`[GPT-6-Sol]`, reasoning high, read-only: FAIL (4 blockers, 2 majors, 1 minor), then three fix
loops; the findings, their verification and dispositions are in the archived audit report.
Finding 1 (unlisted tools not refused) was disproved by a real run; finding 4 (interpreters
run anything) is inherent and documented, with the protection of `main` escalated as G-1.

## Escalations

- **G-1**, protection of `main` on GitHub (repository settings): in `STATUS.md`, sent to the
  project manager.

## Open questions

- A root change (an AppArmor profile allowing `bwrap` user namespaces to user units) would let
  codex run as a unit and survive an app restart. Not needed today.
