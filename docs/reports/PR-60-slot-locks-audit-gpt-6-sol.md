# [GPT-6-Sol] Audit — launcher slot locks (PR 60) — security, quality

## Verdict

**FAIL.** This audit covers **main at 2628b21**. The game launcher fixes the three reported code and wording issues, but the shared-machine A1 fix is incomplete: the library and quiver launchers still contain the older `slots-init`.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| A1 | **blocker — open across tracks** | [game initializer](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-60/scripts/agent.sh:194), [library initializer](/home/claude/projects/hexx-cairo/.claude/worktrees/focused-diffie-2df05c/scripts/agent.sh:200), [quiver initializer](/home/claude/projects/quiver/.claude/worktrees/optimistic-volhard-5b5218/scripts/agent.sh:195) | The game initializer is fixed, but another track can still make the shared slot directory writable while a slot is held. | The available library `origin/main` (`9786f99`) and quiver `origin/main` (`63cb965`) retain the earlier initializer: it calls `chmod 755 "$SLOTS"` without taking the launch lock or checking holders. An ordinary `slots-init` from either track can therefore reopen the pathname-replacement window. The added CI holder fixture runs only the game launcher. | Sync both shared launchers to the guarded initializer before treating A1 as closed machine-wide; cover all three initializers in the fixture. |
| A2 | **major — resolved** | [OPERATIONS §3](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-60/OPERATIONS.md:187) | Lock lifetime is stated accurately. | It is tied to the inner shell, the CLI it waits for, and any process retaining the descriptors. | None. |
| A3 | **major — resolved in this launcher** | [agent.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-60/scripts/agent.sh:160), [CI fixture](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-60/.github/workflows/tooling.yml:114) | Later slot errors are now inspected before selection. | `first_free` checks the full list; `slot_state` reports non-contention `flock` failures as `unlockable`. CI adds a later unreadable-slot case. | None for the game launcher. |
| N1 | **minor — resolved** | [agent.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-60/scripts/agent.sh:134) | The introductory comment now matches the revised lifetime rule. | It no longer claims that every remaining process keeps a slot. | None. |

## Coverage

The **same-user `chmod` residual is accurately stated** in §3. A1 above is separate: the locally available launchers of two other tracks still change the directory mode as part of their normal initializer.

I reviewed the PR 68 diff and CI fixtures; `bash -n` passed. Claude and Codex dry runs retained the expected profile, credential, and sandbox arguments. `slots` showed held locks, and `thresholds` refused the occupied budget with exit 4. I did not execute CI’s holder fixtures, change files, or launch an agent.
## Orchestrator's note (`[Opus 5.5]`, 2026-09-29)

The audits of the slot locks: PR 60 (the design), PR 66 (names protected), PR 68 (slots-init locked,
every slot checked). This last report, at 2628b21, resolves every finding in the game's launcher;
A1 remains only in the map library's and quiver's copies until they sync to 2628b21, which the
project manager has passed on. The launcher's scope (OPERATIONS §3, since 0582dc7) is accidents, not
deliberate acts of the same Unix user; the same-user chmod is the accepted residual. **2628b21 is
marked as the launcher reference** in the CHANGELOG.
