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
| **Writes** | The allowlist of each task lent by the game (§8); `client/app/src/**` except what stays the game's (below); `client/app/index.html`, `client/app/vite.config.ts`; `client/app/package.json` and `pnpm-lock.yaml` for rendering, input and development dependencies only, each addition named in the pull request; `tools/art/**` (moved from the game's track); the Capacitor shell: its configuration and the iOS and Android projects of `client/app` (D-151; CLI-01 adds accounts and the chain to it); `scripts/mac/**` (a launch script for the Mac, if needed, §3); the briefs `docs/briefs/{ART,CLI,SPK-6,CV}*` of its own tasks (the macOS launcher is CV-01); its reports archived in `docs/reports/`; `docs/research/SPK-6-*`; `docs/status/client-visual.md` |
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
- **Budget.** At most **5 agents at a time on the Mac**, audits included, the tasks lent by the
  game (§8) counted in it (owner, 2026-09-29; the Mac has 12 cores and 64 GB). It is apart from the
  VPS's budget of 3 (D-118): another machine. **Before each launch**, as on the VPS: no new agent
  while the 5-minute load average is above 18 (1.5 × the 12 cores) or available memory is under
  8 GB; wait and check again; a running agent is never stopped for load. The Mac's launcher
  (CV-01) enforces the cap and both thresholds.
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
| ART-02 | The atlas of ART-00 corrected: (1) **scale** (owner, D-146 corrected): the pack's hand-drawn units keep their native height (no resampling, no non-integer factor); only the generated goblin sheets are reduced to the scale of the pack's units (runt about 67–70 px, shaman about 87, hobgoblin about 119); the final sizes a line of the manifest, set by the owner's eye on CLI-03a; the table sprite → height in the report (answers question ART-1 provisionally); (2) **Python**: the version the pinned NumPy needs (3.12), in the README and the pipeline's check; (3) **determinism across machines**: the same `out/` on macOS arm64 and Linux x86_64, or, if an encoder differs, a fingerprint of the decoded pixels and the metadata that is equal on both, with the cause stated | ART-00 | Opus 5.5 | Q + `[GPT-6-Sol]` |
| CLI-03a | **A rendering sandbox on fixed data**: a hexagonal room rendered on demand, a camera that follows, sight of radius 6, facing and arcs, touch input; iterated in the browser, mobile and desktop. Wired to `client/sim` and the chain by CLI-03 | none (ART-02 for the art at its final scale) | Opus 5.5 | D Q + `[GPT-6-Sol]` |
| SPK-6a | **The protocol of SPK-6** on real phones: devices, builds, what is measured (battery, heat, frame time on demand, taps on the intended tile at the default zoom), the thresholds of ADR-0003, how a run is recorded. SPK-6 itself runs on CLI-03a's build | none | Opus 5.5, research | D (project manager) |

**Moved to the end, before Phase 6 (D-152, owner): CV-02 and SPK-6.1/6.2; Android dropped for now.** As decided by D-151: **CV-02**, the Capacitor shell, before **SPK-6.1**, the rendering verdict on the owner's phones (iPhone 14 first; it does not close without an Android at 90 or 120 Hz), which unblocks CLI-01; **SPK-6.2**, transactions from a burner, after CLI-01. Builds with the atlas stay on the owner's phones (D-73).

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

## 8. Tasks lent by the game's track (D-149)

The VPS runs the game's chain of engine tasks under a budget of 3; the Mac has room. The project
manager lends this orchestrator whole tasks of the game that need neither Sepolia nor a file the
game's orchestrator is writing. For a lent task this orchestrator writes the brief, launches,
reviews, has it audited and merges it, under OPERATIONS.md and the game's rules (`docs/CAIRO.md`,
`docs/briefs/COMMON.md`); its allowlist is the brief's, and the brief names the paths.

| ID | Task | Allowlist | Before the first launch |
|---|---|---|---|
| IDX-01 | **The indexer** (D-130, PLAN Phase 1): a TypeScript process from SPK-11's prototype; the events frozen by ENG-01 are its interface; versioned tables, rewind on reorg, queries and subscriptions; the client's freshness rule. Tested against a local node, never Sepolia | `indexer/**` (a new package of the pnpm workspace), the line adding it to `pnpm-workspace.yaml`, `pnpm-lock.yaml`, `docs/briefs/IDX-*`, its report | Node 24.21 (`.tool-versions`) on the Mac; Scarb 2.19.4, snforge 0.61 and starknet-devnet 0.10.0 as `scripts/setup-toolchain.sh` pins them, checked by a build of `contracts/` |

- The game's orchestrator does not launch a lent task. A change a lent task needs in the game's
  events or contracts is a `PENDING-cv-*` request; if ENG-R1 or a later lot changes an event,
  the game's orchestrator announces it in `STATUS.md`.
- Next candidates, lent by the project manager when they are ready: CLI-02 (the client's mirror,
  after ENG-02), audits by `claude` of the game's lots, spikes that need no Sepolia.

