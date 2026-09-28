# [GPT-6-Sol] Audit — PR 48 (answers to PRs 43 and 46) — security, quality

## Verdict

**FAIL.** The three requested fixes are present. A new **blocker** is in CI: its non-dry “refusal” check can reach the launch path on a push to main.

## Final findings table

| # | Final status | Evidence |
|---|---|---|
| A1 | **Accepted residual — note** | [OPERATIONS §7](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-43-46/OPERATIONS.md:398) describes typed denies as tripwires, consistent with the owner’s accepted same-user access. |
| A2 | **Resolved** | The grant requires one brief, the exact grant line, and the launch profile. |
| A3 | **Resolved** | The `.sepolia` record and resume warning remain in place. |
| A4 | **Resolved** | CI limits its dry-run claim to the arguments passed. |
| B1 | **Resolved within the stated machine layout** | The counter covers the reserved units and recorded detached agents, with directory deduplication. |
| B2 | **Resolved** | Counter command failures refuse a launch. |
| B3 | **Resolved for this launcher** | The shared lock spans count and start; children close fd 9. Other tracks must use the documented same lock. |
| B4 | **Resolved within the reserved-prefix rule** | Recorded PIDs require their task log in the command line. |
| B5 | **Resolved** | The [reused-PID decoy](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-43-46/.github/workflows/tooling.yml:116) now runs in a second directory inside the fake repository. Its exclusion depends on the log-identity check. |
| N1 | **Resolved** | No user manager means the threshold count refuses a launch. |
| N2 | **Resolved** | The orchestrator reports that the allow fixture passed on GitHub’s runner. |
| N3 | **Resolved** | [Real launches fix `ref=origin/main`](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-43-46/scripts/agent.sh:300); `GW_BRIEF_REF` applies only to dry runs. A dry run against b81c954 accepted the SPK-1 grant. |
| N4 | **Resolved** | A [second user-manager failure](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-43-46/scripts/agent.sh:382) now refuses Claude before its launch records are written; it cannot take the detached branch. |

## New finding

| # | Severity | Location | Finding / failing scenario | Suggested fix |
|---|---|---|---|---|
| N5 | **blocker** | [tooling.yml](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-43-46/.github/workflows/tooling.yml:91) | The workflow runs on pull requests **and pushes to main**. Its non-dry SPK-1 resume expects exit 2 because the grant is absent from `origin/main` *before merge*. After merge, that grant can be present. The command then passes authorization and reaches the lock, threshold check, and potentially the agent launch at [agent.sh:390](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-43-46/scripts/agent.sh:390). A threshold refusal would fail the `exit 2` assertion; a permissive runner could start an agent. | Replace the non-dry assertion with a check-only grant path that cannot launch, and test it on both PR and main states. |

## Coverage

I inspected b81c954 and the resulting launcher and workflow, ran `bash -n`, and used one dry-run grant check. I did **not** execute the non-dry CI assertion, launch an agent, read settings or credentials, or modify files.
## Orchestrator's note (`[Opus 5.5]`, 2026-09-28)

The audit of PRs 43 and 46 failed (one blocker, eight majors). PR 48 answered it in three fix loops;
this is the fourth and last report. Every earlier finding is resolved, accepted as the owner's
residual (A1), or resolved within the machine's stated layout (B1, B4). N5 (a non-dry launch in CI
that a push to main could let through) was fixed after this report by removing that CI line
(commit "ci(tooling): no non-dry launch of a real task in CI"); CI green. Past three fix loops, the
merge is escalated to the project manager (OPERATIONS §7). B3 needs the map library's and quiver's
launchers to take the same lock, `~/orchestrator/agent-launch.lock`, around their count and start.

## Merge exception (`[Opus 5.5]`, 2026-09-28 22:50 UTC)

**Merged after three fix loops, with one commit unaudited at merge time**, on the project
manager's decision (D-128): head `b4fd24c`, its ten checks completed and successful; the unaudited
commit changes five lines of `.github/workflows/tooling.yml` and only removes the real launch from
CI (finding N5), replacing it with a comment. Squash commit `e3a2e75` on main. Conditions: the
re-audit by `[GPT-6-Sol]` covers the merged state and says so; a blocker or a major it finds is
fixed before any other tooling change. The lock request (B3) was passed to the map library's and
quiver's orchestrators by the project manager.
