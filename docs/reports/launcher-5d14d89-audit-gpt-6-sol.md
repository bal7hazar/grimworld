# [GPT-6-Sol] Audit — launcher at 5d14d89 (PRs 78 to 80) — security, quality

## Verdict

**FAIL on quality; no over-launch finding.** This audit covers **main at 5d14d89**. Within the accidental-launch scope of OPERATIONS §3, **no launch can pass the budget or a track cap**. Every CLI must first hold one exclusive total lock and one exclusive track lock, and normal launchers select them under the shared launch lock.

PR 78 separates launcher markers from agent output. PR 79 refuses a non-game launch when the waiting marker cannot be read and CI pins the emitted publish denies. PR 80 signals the detached child PID and group, then checks both are gone and both slots are free. The remaining major is a test gap under OPERATIONS §6; it goes to the project manager under the stated decision.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| M1 | **major** | [timeout cleanup](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/scripts/agent.sh:559), [CI fixture](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/.github/workflows/tooling.yml:184) | The PR 80 timeout acceptance criterion has no test. | The CI stub tests successful acquisition. CI’s three-second timeout stops a caller waiting on the *launch lock*, before a detached child starts. Nothing exercises PID-and-group signalling or verifies the subsequent slot checks. OPERATIONS §6 rates an acceptance criterion without a test as major. | Add a controlled detached-timeout fixture using a stub, with no real agent. |
| N1 | **note** | [confirmation](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/scripts/agent.sh:536) | “Holds slots” describes a snapshot. | The inner shell may exit between the `.run` read and the printed timestamp. The kernel locks still prevent an extra agent. | Treat the line as a snapshot when reading it. |
| N2 | **note** | [slot selection](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/scripts/agent.sh:172) | A brief probe can cause a conservative refusal. | `first_free` can see the last available slot held momentarily by `slots` or `status` and return no free slot. It cannot admit an extra agent. | Retry the launch if this becomes operationally frequent. |
| N3 | **note** | [timeout verification](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/scripts/agent.sh:563) | Verification may conservatively ask for manual attention after a stop. | A lingering zombie can make `kill -0` report an existing PID, or a brief probe can make `slot_state` report held. Neither makes the launcher claim an uncertain stop was verified. | Check the unit, process, and slots before manual action. |
| N4 | **note** | [script comments](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/scripts/agent.sh:213) | Two comments still call `.run` “its log.” | OPERATIONS §3 now names `logs/<task>.run` correctly; agent output goes to `.log`. | Update the comments on the next launcher edit. |

## Coverage

Reviewed the launcher portions of commits `938accd`, `3dd93a6`, and `75a1468`, the resulting script, CI fixtures, and profile rules. `bash -n`, diff checks, and Codex and Claude dry runs passed. The implement dry run emitted both Scarb publish denies and no broad Cargo subcommand allow. Read-only `slots` showed all three total slots held; `thresholds` refused the full budget with exit 4. I did not run holder or timeout fixtures or launch an agent.