# ORCH-client-visual — mandate of the orchestrator of track CV (the client's visual work)

Written by the project manager on 2026-09-29 (D-146), in answer to the owner's Mac session. The
session on the Mac starts a local orchestrator; this file is its mandate.

| | |
|---|---|
| Machine | The owner's Mac: it has a browser the agents can drive; the VPS has none |
| Orchestrator | A local session, `[<Model>] Orchestrateur client visuel (Mac)`, Opus 5.5 unless the project manager says otherwise |
| Repository | `bal7hazar/grimworld` (**public**), a checkout on the Mac with the `assets` submodule initialised |
| Rules | [OPERATIONS.md](../../OPERATIONS.md) in full: `claude` CLI sub-agents on **claude-b7r**, codex audits, committed briefs, one pull request per task, green CI |
| Mandate | `PLAN.md`, section **Track CV**; ADR-0003; design/10 (assets), design/11 (interface), design/18 (rooms) |
| Reports to | The project manager `[Opus 5.5] Chef de projet Grim World`, through the repository (`docs/status/client-visual.md`) and, for a decision only, a cross-session message |
| Language | Documents, briefs, commits, pull requests: English |

## 1. Scope

| | Paths |
|---|---|
| **Writes** | `client/app/src/**` except what stays the game's (below); `client/app/index.html`, `client/app/vite.config.ts`; `client/app/package.json` and `pnpm-lock.yaml` for rendering, input and development dependencies only, each addition named in the pull request; `tools/art/**` (moved from the game's track); `scripts/mac/**` (a launch script for the Mac, if needed, §3); the briefs `docs/briefs/{ART,CLI,SPK-6,CV}*` of its own tasks (the macOS launcher is CV-01); its reports archived in `docs/reports/`; `docs/research/SPK-6-*`; `docs/status/client-visual.md` |
| **Stays the game's** | `client/app/src/account/**`, `client/app/src/chain.ts` and their tests (CLI-01). A change the track needs in `App.tsx` or `main.tsx` that CLI-01 also touches is coordinated through the project manager |
| **Never** | `contracts/`, `client/sim/**`, `spikes/`, `scripts/` outside `scripts/mac/`, `.github/`, the `assets` pointer, `PLAN.md`, `STATUS.md`, `CONTEXT.md`, `PROGRAMME.md`, `OPERATIONS.md`, `docs/design/`, `docs/architecture/`, `docs/decisions/` except a `PENDING-cv-<topic>.md` asking the project manager |

A need outside the scope is written in `docs/decisions/PENDING-cv-<topic>.md` with a
recommendation, and announced to the project manager in one message; the project manager
decides (D-128). Branches are `cv/<task-id>-<slug>`, so that they never collide with the game
orchestrator's `orch/` or the project manager's `pm/`.

## 2. Merges

The local orchestrator merges its own task pull requests, as the other orchestrators do
(OPERATIONS §7): `gh pr checks <n>` shows every check completed and passed; the required audits
are closed without blocker or major; `gh pr view <n> --json files` lists only paths of §1 (a path
outside it: no merge, an escalation); then `gh pr merge <n> --squash`, the number always named.
The game orchestrator does not merge for this track.

## 3. The machine and the agents

- **Account.** On the Mac the CLI's default configuration (`~/.claude`) is the app sessions' and
  stays on bal7hazar. Sub-agents use a separate configuration, `~/.claude-b7r`, logged in as
  claude-b7r: before the first launch `CLAUDE_CONFIG_DIR=~/.claude-b7r claude auth status` shows
  **claude-b7r**, otherwise nothing is launched; the Mac's launcher sets
  `CLAUDE_CONFIG_DIR=~/.claude-b7r` for every sub-agent and refuses to launch without it
  (amended 2026-09-29, answering `PENDING-cv-mandate.md`).
- **Budget.** At most **2 agents at a time on the Mac**, audits included. It is apart from the
  VPS's budget of 3 (D-118): another machine.
- **Launch.** Detached, so that a restart of the desktop app does not kill an agent (OPERATIONS
  §3); the allowlists of `scripts/profiles/` passed to the CLI; never
  `--dangerously-skip-permissions`; no Sepolia account and no registry token in an agent's
  environment; the model tag in every title, unit and log. `scripts/agent.sh` is systemd-only
  and frozen: a macOS equivalent, if one is written, lives in `scripts/mac/`, keeps the contract
  of OPERATIONS §4 (brief, fresh worktree, log, `REPORT.md`, resume, never relaunch from
  scratch), and is audited by `[GPT-6-Sol]` (security lens) before it launches anything.
- **Shared machine.** The owner's Mac: delete and kill only what the track created, by exact
  path and pid (OPERATIONS §3).

## 4. The art pack (D-73)

The repository is **public**. Nothing of the pack and nothing derived from it is committed, or
posted on GitHub: no sprite, no atlas, no **screenshot or recording showing the art**, in the
repository, a pull request, an issue or a comment. Screenshots stay on the Mac or go to the owner
directly. The client loads the atlas that `tools/art` builds locally from the submodule.
Screenshots of shapes with no art from the pack (debug tiles, outlines) may be posted.

## 5. The first tasks

| ID | Task | Depends on | Executor | Audits |
|---|---|---|---|---|
| ART-02 | The atlas of ART-00 corrected: (1) **scale**: every sprite resampled to the height of the pack's unit of its build (78, 94 or 128 px), a basic goblin never taller than a hero; the table caste → height in the report (answers question ART-1 provisionally, D-146); (2) **Python**: the version the pinned NumPy needs (3.12), in the README and the pipeline's check; (3) **determinism across machines**: the same `out/` on macOS arm64 and Linux x86_64, or, if an encoder differs, a fingerprint of the decoded pixels and the metadata that is equal on both, with the cause stated | ART-00 | Opus 5.5 | Q + `[GPT-6-Sol]` |
| CLI-03a | **A rendering sandbox on fixed data**: a hexagonal room rendered on demand, a camera that follows, sight of radius 6, facing and arcs, touch input; iterated in the browser, mobile and desktop. Wired to `client/sim` and the chain by CLI-03 | none (ART-02 for the art at its final scale) | Opus 5.5 | D Q + `[GPT-6-Sol]` |
| SPK-6a | **The protocol of SPK-6** on real phones: devices, builds, what is measured (battery, heat, frame time on demand, taps on the intended tile at the default zoom), the thresholds of ADR-0003, how a run is recorded. SPK-6 itself runs on CLI-03a's build | none | Opus 5.5, research | D (project manager) |

After these: CLI-03 (the sandbox wired to `client/sim` and the chain) when CLI-01 and CLI-02 are
merged; CLI-05, CLI-07 and CLI-08 are candidates for this track, assigned by the project manager
when they come.

## 6. What CLI-03a respects, so that it does not diverge from `client/sim`

1. **No rule in `client/app`.** What the chain decides (a legal move, a change of facing, the arc
   a hit comes from, line of sight, which tiles are in sight, a goblin's step) is computed only
   in `client/sim`, the mirror checked by vectors from the Cairo code (D-140). The sandbox shows
   these from fixture data. Where it needs one before CLI-02, it takes it from a fixture or from
   a placeholder in one file, `client/app/src/sandbox/placeholders.ts`, each function marked
   `PLACEHOLDER until CLI-02`; CLI-03 deletes the file.
2. **The design's conventions, not new ones**: pointy-top hexes (D-11); the coordinates,
   directions and their numbering of `hexx` as ported in `bal7hazar/hexx-cairo`; the window of
   15 × 16 whose origin is on an even global row (D-120); chunks of 15 × 15; sight of radius 6;
   six facings and four arcs (D-41, design/04); a chunk not revealed is wall (D-136).
3. **The renderer's input is a view state**, a type of `client/app` (`render/view.ts`): tiles and
   their kinds, actors with position and facing, the tiles in sight, arcs as data. CLI-02 or
   CLI-03 produces it from the state of `client/sim`. Anything the track wants in `client/sim` is
   a `PENDING-cv-*` request.
4. **Pixels to tiles and back** (drawing, taps) are presentation and live in `client/app`. A tap
   produces an intent (a target tile), never a result.
5. **Rendered on demand, no render loop** (ADR-0003); the power rules of design/11.
6. No randomness and no clock in anything `client/sim` will decide later.

## 7. Status and reporting

`docs/status/client-visual.md`, dated, rewritten by the local orchestrator at each check-in:
tasks, agents, pull requests, what waits. The project manager reads it like the tracks'
`STATUS.md`. A message to the project manager only for a decision; first line, the subject.
