# CV-02 — The Mac launcher: a budget of 5, the pinned Node

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur client visuel (Mac)`, on
2026-09-29, under [ORCH-client-visual](ORCH-client-visual.md) §3 as amended by D-149 (#127).

## Agent
Title: `[Sonnet 5.5] CV-02 launcher budget` · Profile: implement

## Goal

After this task, `scripts/mac/agent.sh` (CV-01, [report](../reports/CV-01-mac-launcher.md)) runs up to
**5 agents at a time**, refuses a launch while the 5-minute load average is above **18**, and gives
its agents the Node and pnpm that the repository pins (`.tool-versions`: nodejs 24.21.0, pnpm
12.5.1), not the Node that happens to hold the `claude` CLI. Nothing else changes.

## Context

- The owner's decision of 2026-09-29, relayed by the owner's architecture session and written by the
  project manager in the mandate (§3, D-149): **at most 5 agents at a time on the Mac, audits and lent
  tasks included; no new agent while the 5-minute load average is above 18 (1.5 × the 12 cores) or
  available memory is under 8 GB**; a running agent is never stopped for load.
- The launcher today: `SLOT_NAMES=(cv-1 cv-2)`, `MAX_LOAD5=10 MIN_MEM_GB=8`, and
  `PATH_FIXED` starting with `$HOME/.asdf/installs/nodejs/22.22.2/bin` (which holds `claude` and a
  pnpm) before `$HOME/.asdf/shims`, so that an agent's `node` is 22.22.2 whatever the worktree pins.
- Measured by the orchestrator on 2026-09-29: nodejs 24.21.0 is now installed under asdf, with pnpm
  12.5.1 in its global packages; with `$HOME/.asdf/shims` first on `PATH`, inside the repository
  `node -v` is v24.21.0 and `pnpm -v` 12.5.1. The asdf shims also hold a shim named `claude`, which
  resolves the Node of the current directory's `.tool-versions` (24.21.0) where no `claude` is
  installed: the launcher must therefore never start `claude` through `PATH`.
- A small defect found by the orchestrator: `scripts/mac/agent.sh status` prints a bash error for a
  task whose `logs/<task>.cli` is missing (`ligne 221: …CV-01-audit-sol.cli: No such file or
  directory`); it should print the task with `ran=unknown`, silently.

## Scope

- In:
  1. Five slots `cv-1`…`cv-5`; `slots-init` creates the missing ones (it already creates missing
     files only; check it works on a directory holding `cv-1` and `cv-2` while they are free, as on
     this Mac now, and refuses while one is held, as today).
  2. `MAX_LOAD5=18`; `MIN_MEM_GB=8` unchanged.
  3. The agents' `PATH`: `$HOME/.asdf/shims` first (a worktree's pins decide `node`, `pnpm`,
     `scarb`, `snforge`), the rest as today, and **no** `nodejs/22.22.2/bin` on it. The CLIs are
     started by absolute path, from a fixed table in the script: `claude`
     `$HOME/.asdf/installs/nodejs/22.22.2/bin/claude`, `codex` `$HOME/.local/bin/codex`; the
     launcher refuses (exit 2) when that file is missing or not executable, and the account check of
     requirement 1 uses the same binary. If `claude` is a script that needs `node` on `PATH` rather
     than a native binary, say so and give it the 22.22.2 `node` by the narrowest means you can
     justify (not by putting that folder on the agent's `PATH`).
  4. `status` silent on a missing `.cli`.
  5. The tests (`scripts/mac/test.sh`) moved to 5: the budget case holds five stubs and refuses a
     sixth; the race case keeps one free slot out of five; the threshold case tests 18; a case that
     the agent's `PATH` starts with the shims and holds no `nodejs/22.22.2`; a case that the CLI is
     started by its absolute path (the stub table of the test mode stands in for it, as the stubs do
     today). Every other case unchanged and passing.
  6. `scripts/mac/README.md` updated; its summary cites the owner's decision of 2026-09-29 (D-149).
- Out: anything else in the launcher; `scripts/agent.sh`, `scripts/profiles/`, `OPERATIONS.md`;
  installing anything (Node 24.21.0 and pnpm are installed).
- Allowlist: `scripts/mac/**`, `REPORT.md`.

## Acceptance criteria

- [ ] AC-1 `slots-init` on the real Mac directory would add `cv-3`…`cv-5` and keep `cv-1`, `cv-2`
  (shown in test mode, on a test home prepared with two slots).
- [ ] AC-2 Five stubs run at once; a sixth launch refuses (exit 4) before any worktree or job.
- [ ] AC-3 The thresholds refuse above 18 and accept at 18 (test mode's forced value).
- [ ] AC-4 The agent's `PATH` begins with `$HOME/.asdf/shims` and holds no `nodejs/22.22.2`; the CLI
  is started by absolute path; a missing CLI binary refuses with exit 2.
- [ ] AC-5 `status` prints nothing on stderr for a task without `.cli`.
- [ ] AC-6 `bash -n`, `shellcheck scripts/mac/*.sh`, `scripts/mac/test.sh` all pass; the dry run
  shows the new `PATH` and the absolute CLI path.

## Verification

```
bash -n scripts/mac/agent.sh scripts/mac/test.sh
shellcheck scripts/mac/*.sh
scripts/mac/test.sh
scripts/mac/agent.sh --dry-run CV-02-dry claude sonnet new "hello" implement
```

## Rules of this run

The same as CV-01's ([brief](CV-01-mac-launcher.md), *Rules of this run*): the owner's personal
Mac; test jobs only under `grimworld.cv.test.`, removed by exact label and path; never a real
`claude` or `codex`; never read `~/.claude`, `~/.claude-b7r`, `~/.codex`, `~/.config/gh` or the
keychain. **Do not run `scripts/mac/agent.sh` against the real home** (`status`, `slots` and
`--dry-run` excepted): real agents are running under it. Pull request: branch
`cv/CV-02-launcher-budget` (your worktree is on it, with this brief as its first commit), title
`feat(scripts/mac): CV-02, a budget of 5, load 18, the pinned Node (owner, 2026-09-29, D-149)`.
Commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Report

`REPORT.md`, header `[Sonnet 5.5] CV-02 — launcher budget`: summary; the diff in words; the
verification commands with their real output; deviations; escalations.
