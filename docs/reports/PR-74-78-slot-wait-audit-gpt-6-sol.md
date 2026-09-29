# [GPT-6-Sol] Audit — launcher slot wait (PR 74) — security, quality

## Verdict

**FAIL.** This audit covers **main at 938accd**. A remaining **major** fail-closed finding requires project manager escalation under OPERATIONS §6.

No two agents can run past the budget or a track cap: normal launchers select slots under the shared launch lock, and each inner shell must hold exclusive total and track locks before starting its CLI.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| A1 | **note — resolved within scope** | [run-file markers](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/scripts/agent.sh:224), [confirmation](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/scripts/agent.sh:523) | CLI output cannot supply the acquired or ended markers. | The inner shell writes them to a freshly emptied `.run` file; CLI output goes to `.log`. A shell exit between the state read and the printed “holds slots” timestamp can still age that wording, but cannot admit an extra agent. | None required for launcher scope. |
| A2 | **major — open** | [detached start](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/scripts/agent.sh:514), [timeout cleanup](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/scripts/agent.sh:546) | Free slots do not prove a delayed detached child has stopped. | Cleanup signals only process group `-$pg`. If the background child is delayed before `setsid` creates that group, both group signals can miss it. Its slots are still free, so the launcher reports “stopped”; the child can subsequently create the group, acquire slots, and run after that failure report. This requires no deliberate same-user act. | Terminate and verify the direct child PID as well as its eventual group, then check the slots. If termination cannot be established, report it as unknown. |
| A3 | **note — resolved** | [CI stub](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/.github/workflows/tooling.yml:176) | The held assertion controls the stub’s lifetime. | The fixture creates the release file only after checking `status`. | None. |
| A4 | **note** | [OPERATIONS §3](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-74/OPERATIONS.md:195) | The prose still calls the marker destination “its log.” | The marker now goes to `logs/<task>.run`, separately from agent output in `.log`. This is a documentation distinction, not a budget bypass. | Name the `.run` file when next updating the section. |

## Coverage

Reviewed PR 78’s run-file, confirmation, timeout, and fixture changes. `bash -n`, diff whitespace check, and a Codex dry run passed. Read-only `slots` showed all three total slots held; `thresholds` refused the full budget with exit 4. I did not run holder fixtures or launch an agent.
## Orchestrator's note (`[Opus 5.5]`, 2026-09-29)

The series PR 74 → 75 → 77 → 78 (three fix loops) ends with A2 open (major); escalated to the project manager. Fixed after the escalation by PR 80 (75a1468): the pid is signalled too and the stop verified. Also merged: PR 79 (the waiting marker read failing closed, from the library's audit). One narrow audit of 75a1468 covers PRs 78 to 80 before the CHANGELOG reference moves from 2628b21.
