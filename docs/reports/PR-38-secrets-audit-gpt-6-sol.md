# [GPT-6-Sol] Audit — PR 38 — security, quality

## Verdict

**PASS WITH FINDINGS.** The narrowed functional claim is supported: the launcher supplies the empty-token override on new and resumed Claude launches, and the profiles deny the named direct forms. Same-user file access remains the documented, owner-escalated residual. One minor wording contradiction remains.

## Findings

| # | Final severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | **note — accepted residual** | [OPERATIONS.md](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-38/OPERATIONS.md:236) | An allowed interpreter can still read the user’s settings file and publish. This is now outside the PR’s narrowed guarantee and is explicitly documented for an owner decision. | §4 names `python3` and `node` and states the need for OS-level credential isolation. | Track the accounts-and-secrets decision through the project manager. |
| 2 | **note — resolved** | [tooling.yml](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-38/.github/workflows/tooling.yml:69) | CI checks the exact escaped `--settings` argument and empty value for new and resume in all three profiles. | The new assertions name the full JSON value. Read-only dry runs matched it in six profile/mode combinations. The [launcher](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-38/scripts/agent.sh:252) appends it after both Claude command branches. | None. |
| 3 | **note — resolved** | [research.txt](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-38/scripts/profiles/research.txt:91) | The broad `*_TOKEN` deny is gone. | The remaining variable-name deny targets `SCARB_REGISTRY`; ordinary searches containing `_TOKEN` no longer match that removed rule. | None. |
| 4 | **minor — open** | [OPERATIONS.md](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-38/OPERATIONS.md:233), [agent.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-38/scripts/agent.sh:253) | Two absolute statements still overstate the boundary. | §4 says “nothing of value is ever reachable … without the owner’s go,” then says an interpreter can read the token and publish. The new launcher comment says “no agent publishes,” despite that accepted residual. | Remove those absolute statements; describe the empty process environment and direct-command denies as the guarantees. |

## Coverage

Reviewed the new diff and inherited profiles. `bash -n` and `git diff --check` passed. GitHub remained unreachable, so I could not independently inspect the PR comment or its live-agent probe. No credential file or credential value was read.
## History and disposition

| Round | Verdict |
|---|---|
| 1 | FAIL: 1 blocker (an allowed interpreter can read the settings file and publish), 1 major (CI assertion), 2 minors |
| 2 (fix loop 1) | PASS WITH FINDINGS; the claim narrowed to what the change guarantees; the last minor (wording) fixed by the orchestrator before merge |

The blocker is a residual that permission rules cannot close: documented in OPERATIONS §4, escalated to the owner through the project manager (OS-level isolation of credentials).

Run by `scripts/agent.sh AUD-38 codex gpt-6-sol`, reasoning high, read-only; model recorded by the CLI: `gpt-6-sol`.
