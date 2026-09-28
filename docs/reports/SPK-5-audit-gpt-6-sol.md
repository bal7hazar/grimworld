# [GPT-6-Sol] Audit — SPK-5 — quality, security

## Verdict

**PASS WITH FINDINGS.** Fix loop 3 resolves N1-b and N3. I found no new code finding. The remaining items have the orchestrator dispositions shown below; this verdict does not clear the outstanding merge follow-up.

## Findings

| # | Final severity | Location | Finding | Evidence / failing scenario | Suggested fix or disposition |
|---|---|---|---|---|---|
| F1 | Resolved | [with-katana.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/scripts/with-katana.sh:104) | Command descendants could survive. | EXIT cleanup retains and stops the command’s process group; the research records a child-outliving-parent check. | — |
| F2 | Resolved | [setup-toolchain.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/scripts/setup-toolchain.sh:236) | Setup could replace another programme’s links. | It creates no shared links and removes only links pointing into its configured legacy tools directory. | — |
| F3 | **Minor — deferred by orchestrator** | [research](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/docs/research/SPK-5-toolchain.md:47) | Scarb, snforge and pnpm downloads lack pinned checksums. | The limitation and plugin install paths are documented. Sozo, Katana and Torii are hashed before the script invokes them. | Orchestrator disposition: defer under a PLAN entry; standard machine install path, beyond this brief, test networks only. **I could not find the stated entry in checked-out or `origin/main` `PLAN.md`.** |
| F4 | Resolved | [.tool-versions](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/.tool-versions:1) | Three asdf pins were missing. | All seven tools are pinned; the research records the separate plugins’ installation. | — |
| F5 | Resolved | [with-katana.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/scripts/with-katana.sh:72) | Port selections were lost. | Selection state stays in the parent shell, with readiness checks and bind-failure retries. | — |
| F6 | **Minor — orchestrator follow-up** | [with-katana.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/scripts/with-katana.sh:67), [.gitignore](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/.gitignore:1) | Root `.with-katana/` logs are unignored. | The wrapper defaults to that root-relative directory; the root ignore file has no rule for it. | Orchestrator to add the shared-file rule. |
| N1-a | **Note — open incident** | [setup-toolchain.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/scripts/setup-toolchain.sh:222) | Pre-existing Node/pnpm shims fail outside pinned directories on this machine. | Setup warns; the shims predate this fix. A clean machine with matching system versions gets no Node/pnpm plugin. | Orchestrator disposition: track in `docs/reports/INC-2026-09-28-asdf-node-shims.md` on `origin/main`. |
| N1-b | Resolved | [setup-toolchain.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/scripts/setup-toolchain.sh:141) | A global `system` line could be accepted without a system executable. | The plugin-add branch now requires both a nonempty system executable path and the global fallback line; otherwise setup exits 1. | — |
| N2 | Resolved | [setup-toolchain.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/scripts/setup-toolchain.sh:11) | Writes outside asdf were misstated. | The script and research name legacy-link removal, temporary logs and the Foundry plugin’s `~/.local/bin` side effect. | — |
| N3 | Resolved | [setup-toolchain.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5/scripts/setup-toolchain.sh:236) | Failed setup could remove working legacy links. | Cleanup now runs only after tool checks have left `status=0`. | — |

## Coverage

I reviewed `origin/main...HEAD`, the fix-loop diff, brief, scripts, research, ignore rules and the incident reference. `git diff --check` passes; the assets pointer is unchanged. I ran no installs, builds or nodes. The CI workflow still includes both requested scripts in shellcheck, but I did not independently confirm the current PR check result.

Under OPERATIONS §6, the orchestrator should make the stated F3 PLAN deferral visible and complete or formally defer F6 before merge.
## History

| Round | Head | Verdict |
|---|---|---|
| 1 | `9a9dc95` | FAIL: 5 majors (process-group cleanup, symlink ownership, binary integrity, asdf plugins untested, ports), 1 minor |
| 2 (fix loop 1) | `a5434e2` | FAIL: F3 open, N1 new (majors), N2 minor |
| 3 (fix loop 2) | `120bf2a` | FAIL: F3, N1, N3 majors |
| 4 (fix loop 3) | `767bd18` | PASS WITH FINDINGS |

Orchestrator dispositions: F3 downgraded to minor and deferred as PLAN HRD-10 (checksums of asdf-plugin downloads: beyond the brief, the machine-wide install path of every programme, documented, test networks only); N1-a kept as a note tied to INC-2026-09-28 (the shims pre-exist on this machine); F6 done on main (`.with-katana/` ignored).

Run by `scripts/agent.sh AUD-SPK-5 codex gpt-6-sol`, reasoning high, read-only; model recorded by the CLI: `gpt-6-sol`.
