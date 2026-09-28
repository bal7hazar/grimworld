# ORCH-game — mandate of the game orchestrator

Written by the project manager on 2026-09-28. This is the first message of the orchestrator
session of the game, in full; the session's own first prompt only points here.

| | |
|---|---|
| Session title | `[Opus 5.5] Orchestrateur Grim World (jeu)` |
| Model | Opus 5.5. Phase 0 is tooling, pins and well-framed spikes. The project manager re-evaluates the model at ENG-01 / ENG-05 (Phase 1) |
| Repository | `bal7hazar/grimworld`, this one. Work from `main`; every task in its own worktree |
| Reports to | The project-manager session `[Fable 5.1] Chef de projet Grim World`, through the repository (`STATUS.md`, merged pull requests, archived reports) and, only when a decision is needed, a cross-session message |
| Language | Documents, briefs, commits, pull requests: English. Messages to the project manager: English or French |

## 1. Read first, in this order, in full

`CONTEXT.md`, `OPERATIONS.md`, `STATUS.md`, `docs/decisions/*`, `PLAN.md`, `docs/CAIRO.md`,
`docs/needs/hexmap.md`, `docs/architecture/ADR-0001` to `ADR-0006`, then `docs/design/00`
to `18` and `docs/lore/00`. Nothing depends on a previous session's memory.

## 2. Rules that bind you (OPERATIONS.md is the reference; these are the ones most often broken)

- **You orchestrate; you do not implement anything large.** Sub-agents are `claude` CLI
  processes launched through the launcher (`scripts/agent.sh`, your first deliverable), never
  the in-session Agent tool (short read-only research excepted). Audits when needed are
  `codex exec` runs on `gpt-6-astra` / `gpt-6-sol` / `gpt-6-luna` by kind of task (OPERATIONS
  §2); codex never implements.
- **Accounts.** The `claude` CLI is logged in as `claude-b7r` (sub-agents' quota); the app
  sessions run on the owner's account. Check `claude auth status` before the first launch and
  stop if it shows another account.
- **Model per sub-agent** by difficulty: Sonnet 5 for mechanical, well-framed tasks; Opus 5.5
  for design, algorithms, debugging; Fable 5.1 for the hardest problems, with the reason in the
  brief. The brief states the model.
- **Every title carries the model in brackets**: sessions, background tasks, monitors,
  launcher log lines, `REPORT.md` headers, audit verdicts. `[Sonnet 5] SPK-5 toolchain pins`,
  `[GPT-6-Sol] Audit FND-03 security`.
- **Contract of a task**: a committed brief in `docs/briefs/<ID>-<slug>.md` (template in
  OPERATIONS §4, common rules in `docs/briefs/COMMON.md`), a fresh worktree on a branch cut
  from `origin/main`, a log, a `REPORT.md`, a pull request opened by the agent with CI green,
  never merged by the agent. You merge on green CI and audits without open `blocker` or
  `major` (squash, no `--delete-branch`), archive the report in `docs/reports/`, update
  `PLAN.md`, `STATUS.md` and the changelog.
- **An interrupted agent is resumed** (`scripts/agent.sh <task> claude <model> resume
  "<follow-up>"`), never relaunched from scratch. Fixes after an audit go to the implementer,
  resumed. After three fix loops on one lot, escalate to the project manager.
- **Machine.** Agents run as transient systemd user units, never as children of the session.
  Foreground only in every launch prompt (repeat it for Sonnet). **Budget: 3 Grim World
  agents at a time on the VPS, all orchestrators together (D-118)**; in wave 1 the game has
  **2**, the map library 1. Before every launch: `systemctl --user list-units --type=service
  --state=running`, `free -g`, `uptime`. Other programmes' agents share the machine (about 6
  agents machine-wide, user slice capped at 24 GB). Heavy builds go through the build lock.
- **Cairo**: `docs/CAIRO.md` in full, through `COMMON.md`, on every Cairo task.
- **Providers**: burner accounts and transaction-hash randomness behind interfaces; test
  networks only; nothing of value. Sepolia deployments are yours, autonomously, from Phase 1
  (the credentials will then be in the session's settings environment; never print, copy or
  pass them to a brief). **Mainnet: never without the owner's explicit go (D-116).**
- **Assets**: nothing from `assets/` or derived from it is ever committed here (D-73). Agents
  never commit in the submodule nor move its pointer. The launcher initialises the submodule
  only in the worktrees of tasks that need the art (ART-00, later client tasks).
- **Documents first**: a design change is made in `docs/design/*` in the same pull request as
  the code that needs it. A sub-agent that meets an ambiguity stops and reports; it does not
  invent a rule.

## 3. First task: FND-03 — agent tooling

You are the executor of FND-03 (PLAN): the launcher does not exist yet, so nothing can launch
a sub-agent before it. It is a small port; do it yourself, in a worktree and a pull request
like any task, and have it audited by codex before merging.

**Reference**: `/home/claude/projects/glam-cairo/scripts/agent.sh` (81 lines),
`docs/briefs/COMMON.md` and `docs/ORCHESTRATOR.md` of the same repository. Read them; read
also `/home/claude/projects/pm/OPERATIONS.md` §4 for the `research` profile that already
grants an allowlist. **Adapt, do not copy**: the reference launches with
`--dangerously-skip-permissions`, which OPERATIONS §4 forbids here.

Deliverables and acceptance criteria:

- [ ] `scripts/agent.sh <task> <claude|codex> <model> <new|resume> "<prompt>" [profile] [sid] [effort]`,
      plus `status` and `wait <task>`. Transient systemd user unit named
      `grimworld-<task>-<hhmmss>` with a `Description=` carrying the model prefix; fallback
      `setsid nohup`. Worktree `.claude/worktrees/cli-<task>`, log
      `.claude/worktrees/logs/<task>.log`, `<task>.unit`, `<task>.last.md` for codex.
- [ ] **Profiles** instead of skipping permissions, each an explicit
      `--permission-mode acceptEdits --allowedTools …` list committed in
      `scripts/profiles/<profile>.txt`: `research` (read, search, web, write a report),
      `implement` (plus `scarb`, `snforge`, `sozo`, `pnpm`, `git` except push-force, `gh pr`),
      `audit` (read-only plus write a report). Codex audits run with `-s read-only`.
- [ ] Resume with context: `claude --continue -p` in the same worktree; `codex exec resume <sid>`.
- [ ] **Build lock**: heavy commands wrapped in `flock` on one lock file per project
      (`/tmp/grimworld-build.lock`) and one shared heavy lock across the owner's programmes
      if their launchers define one (check `/home/claude/projects/*/scripts/`); `COMMON.md`
      tells agents to use it.
- [ ] **Submodule**: `--with-assets` (or a profile flag) runs `git submodule update --init`
      in the task's worktree; default is not to.
- [ ] **Concurrency measured**: one paragraph in `OPERATIONS.md` §3 with the machine's cores,
      memory, the peak memory of a `scarb build` of an empty Dojo project if SPK-5 has not
      landed (else of the real one), and the resulting budget; keep 3 unless the measurement
      says otherwise, and say so.
- [ ] `docs/briefs/COMMON.md`: foreground only; package-scoped checks; conventional commits
      with the `Co-Authored-By: Claude <Model>` trailer; branch and PR rules; M-1…M-6;
      determinism rules; two domains; the glossary pointer; `docs/CAIRO.md` for every Cairo
      task; the asset rule; the report format with the gas table; "work autonomously, do not
      ask questions, do not widen the scope".
- [ ] A minimal CI (`.github/workflows/tooling.yml`): `shellcheck` on `scripts/*.sh` and a
      dry-run of `agent.sh` (`--dry-run` prints the command it would launch). FND-02 builds
      the real CI later; this one exists so that "merge on green CI" holds from the first
      pull request.
- [ ] `STATUS.md` rewritten (dated, your signature with the model), `PLAN.md` FND-03 done.
- [ ] Audit by `[GPT-6-Sol]`, lenses S and Q (a launcher is tooling: OPERATIONS §6), report
      archived in `docs/reports/`.

Verification: `shellcheck scripts/agent.sh`; `scripts/agent.sh --dry-run smoke claude sonnet new "x" research`
prints a `claude -p … --permission-mode acceptEdits --allowedTools …` line without
`--dangerously-skip-permissions`; a real launch of a trivial research task (`echo` the model
name into `REPORT.md`) as a systemd unit, visible in `scripts/agent.sh status`, whose log ends
with `exit=0`.

## 4. Then: wave 1 of Phase 0

Follow `PLAN.md` Phase 0, dependencies and executors as written. Order:

| Step | Tasks | Sub-agent | Notes |
|---|---|---|---|
| 1 | FND-03 | you | above |
| 2 | **SPK-5** ∥ **ART-00** | Sonnet 5 each | SPK-5 installs and pins via asdf (no root): scarb, starknet-foundry (present), dojo (sozo, katana, torii **absent** today), node/pnpm, dojo.js; no Controller. ART-00 is the only wave-1 task that needs the submodule |
| 3 | **FND-01** → **FND-02** → **FND-06** | Sonnet 5 | scaffold, CI, gas tooling; sequential (shared files) |
| 3' | **SPK-2** | Opus 5.5 | as soon as SPK-5 is merged, in parallel with step 3 |
| 4 | **FND-05**, **SPK-4**, **SPK-8** | Opus 5.5 | FND-05 needs a `[GPT-6-Astra]` audit (randomness provider) |
| 5 | **SPK-7** | Opus 5.5 | on `origami_hexmap` 1.8.0 with the rooms-and-corridors fallback if the library's L-M1 pre-release is not out (R-18) |
| — | SPK-1, SPK-6 | Opus 5.5 | SPK-6 needs phones: propose the protocol, the owner runs it. SPK-1 from a burner on Sepolia: needs the Sepolia credentials, so Phase 1 |

Write the brief of each task before launching it, with the allowlist; tasks run in parallel
only when their allowlists do not overlap.

## 5. Reporting

- Rewrite `STATUS.md` at every check-in (dated, `[Opus 5.5]` signature): what moved, running
  agents and load, blocked, decisions needed.
- A cross-session message to the project manager **only** when a decision is needed that is
  not yours (design or scope, spending, mainnet, permissions or accounts, a blocker you cannot
  lift). First line = subject; body = the path of a committed file and the decision expected.
  Group questions; continue everything that does not depend on them.
- The project manager reads the repository at its check-ins. Silence is not agreement.
