# [GPT-6-Sol] Audit — SPK-5b — quality, security

## Verdict

**PASS WITH FINDINGS.** F1–F4, F6 and F7 are resolved on static review. F5 remains a minor supply-chain limitation deferred in PLAN HRD-10. No major finding remains open.

## Findings

| # | Final severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| F1 | note — resolved | [.gitignore](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/.gitignore:10) | Local node key files are ignored. | `git check-ignore` matches `.with-node/node.log` and `.with-node/accounts.json`. | — |
| F2 | note — resolved | [SPK-5/locked.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/spikes/SPK-5/locked.sh:20), [run.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/spikes/SPK-5/run.sh:17) | The Dojo spike has its own wrapper, and its heavy `sozo` commands use a restricted lock wrapper. | `locked.sh` accepts only `sozo build/test/migrate`, refuses the reversed-lock case, and nests the heavy lock inside the project lock. `run.sh` uses it for build and migrate. End-to-end execution was not independently repeated. | — |
| F3 | note — resolved | [setup-toolchain.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/scripts/setup-toolchain.sh:152) | The devnet fallback now hashes the selected binary. | `system_path` is recorded only after the matching system binary is selected; otherwise `check_hash` resolves the asdf installation. | — |
| F4 | note — resolved | [setup-toolchain.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/scripts/setup-toolchain.sh:129) | An existing plugin proceeds to installation of its repository pin. | The existing-plugin branch reaches the `asdf install` loop. | — |
| F5 | minor — deferred | [setup-toolchain.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/scripts/setup-toolchain.sh:41), [PLAN HRD-10](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/PLAN.md:252) | Scarb, Foundry and pnpm plugin downloads still lack pinned checksum verification. | The limitation is documented in the script and tracked by HRD-10. Devnet has a pinned hash checked before its version command. | Complete HRD-10. |
| F6 | note — resolved | [research.txt](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/scripts/profiles/research.txt:69) | Inherited Dojo version grants are gone. | Research grants `sncast` and `starknet-devnet` version checks and no longer grants `sozo`, `torii` or `katana` version checks. | — |
| F7 | note — resolved | [audit.txt](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/scripts/profiles/audit.txt:14) | Auditors can use the Scarb 2.19 global `--manifest-path` form through the lock. | Narrow rules cover build, test, lint and checked formatting, plus heavy build/test; [lock.sh](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-SPK-5b/scripts/lock.sh:32) validates the form. | — |

## Coverage

Reviewed `origin/main...HEAD` at `cb4c3a7`. `bash -n`, `git diff --check` and the ignore checks passed. This was a read-only review: setup, builds, node cleanup and the reported end-to-end runs were not executed.
## History

| Round | Head | Verdict |
|---|---|---|
| 1 | first push | FAIL: 6 majors (key file unignored, Dojo baseline not runnable, plugin rule partial, setup edge case, checksums, research profile) |
| 2 (fix loop 1) | `a9d15bd` | FAIL: 3 majors (sozo unlocked in the Dojo spike, devnet hash path, audit profile) |
| 3 (fix loop 2) | `cb4c3a7` | PASS WITH FINDINGS (F5 deferred as HRD-10) |

Run by `scripts/agent.sh AUD-SPK-5b codex gpt-6-sol`, reasoning high, read-only; model recorded by the CLI: `gpt-6-sol`.
