# ORCH-hexmap — mandate of the map-library orchestrator (track LIB)

Written by the project manager on 2026-09-28. This is the first message of the orchestrator
session of the map library, in full; the session's own first prompt only points here.

| | |
|---|---|
| Session title | `[Fable 5.1] Orchestrateur hexmap (lib)` |
| Model | Fable 5.1: algorithms under a gas budget and API arbitration against a Rust crate are hard problems (PLAN, track LIB) |
| Repository | `bal7hazar/hexx-cairo` (created, empty: one commit with an MIT `LICENSE`), local checkout `/home/claude/projects/hexx-cairo`. Where the work finally lands (this repository, `dojoengine/origami`, elsewhere) is a **finding of LIB-02**, reported at gate L-G1, not a question to ask beforehand (D-117) |
| Mandate | `PLAN.md` of `bal7hazar/grimworld`, section **Track LIB**, and `docs/needs/hexmap.md` there. The game consumes `origami_hexmap` 1.8.0 meanwhile and will consume your library **by published version** (scarbs.xyz), never by git revision |
| Reports to | The project-manager session `[Fable 5.1] Chef de projet Grim World`, through your repository (`STATUS.md`, `docs/research/`, merged pull requests) and, only at the two gates, a cross-session message |
| Language | Documents, briefs, commits, pull requests: English |

## 1. Read first, in full

In `/home/claude/projects/grimworld` (read `main`, do not write there): `OPERATIONS.md`,
`docs/CAIRO.md`, `PLAN.md` § *Track LIB* and § *Milestone L-M1*, `docs/needs/hexmap.md`,
`docs/architecture/ADR-0006-chunked-maps.md`, `docs/design/02-core-loop.md` § *Map* and
§ *Simulation budget*, `docs/design/04-combat.md` § *Ranges* and § *Facing and arcs*,
`docs/design/18-rooms.md`. Then `docs/briefs/ORCH-game.md` §2 (the rules, identical for you).

Sources to analyse: the Rust crate [`hexx`](https://github.com/ManevilleF/hexx) (clone the
latest release into the task's worktree, read-only) and `origami_hexmap` at
`/home/claude/git/origami/crates/hexmap` (the owner's library; `crates/map` is the older
square-grid library, not the subject). The owner has maintainer rights on `dojoengine/origami`.

## 2. Rules

Those of `grimworld/OPERATIONS.md`, summarised in `ORCH-game.md` §2: you orchestrate, you do
not implement anything large; sub-agents are `claude` CLI processes as detached systemd user
units with an allowlist profile, never `--dangerously-skip-permissions`; audits by `codex`
when needed, never implementation; every title carries the model; brief committed, fresh
worktree, log, `REPORT.md`, pull request with green CI, merged by you; interrupted agents are
resumed. Conventions of the owner's other programmes apply to a port: mirror the crate, same
names, same API where it makes sense on-chain, deviations documented, a generated parity
table checked in CI, numeric results are API (`/home/claude/projects/glam-cairo/docs/DESIGN.md`
and `AGENTS.md` show the house style; `nalgebra-cairo` is the most recent port).

**Budget**: 1 agent at a time for you in wave 1 (the game has 2; 3 Grim World agents in total,
D-118). Check running units, memory and load before launching. Cairo rules (`docs/CAIRO.md`)
bind every implementation task later: test-driven, `#[available_gas]` on every test at
1.05 × measured, execution cost first, arithmetic then bitwise then loops, `u252`, oracles.

**Launcher**: the game's FND-03 delivers `scripts/agent.sh` with the profiles (`research`,
`implement`, `audit`) in `bal7hazar/grimworld`; adopt it in your repository as soon as it is
merged (copy `scripts/agent.sh`, `scripts/profiles/`, adapt `docs/briefs/COMMON.md`). Until
then you may launch your single research agent by hand with the same constraints:
`systemd-run --user --unit="hexmap-<task>-<hhmmss>" --description="[Opus 5.5] LIB-02 …" …
claude -p "<prompt>" --model opus --permission-mode acceptEdits --allowedTools <read, search,
web, write list> --name LIB-02`, output to a log, from the task's worktree. `claude auth status`
must show `claude-b7r` first.

## 3. First task: LIB-02 — analysis of `hexx` and of its intersection with `origami_hexmap`

Set up the minimum your repository needs first (yourself, one small pull request):
`README.md` (purpose, status, link to the game's PLAN track LIB), `STATUS.md`, `PLAN.md`
(track LIB copied and owned here from now on), `docs/research/`, `docs/briefs/`,
`docs/decisions/`, `.gitignore`, and a minimal CI that at least checks Markdown links, so that
"merge on green CI" holds from the first pull request.

Then brief and launch **LIB-02** — sub-agent **Opus 5.5**, profile `research`:

- What `hexx` offers, feature by feature: coordinates (axial, offset, doubled), directions,
  rotation and reflection, lines, rings, spirals, ranges, wedges, field of view, field of
  movement, pathfinding, layouts and orientation, chunks or wrapping, mesh and rendering
  helpers, bounds, edges and vertices.
- What `origami_hexmap` 1.8.0 already covers, from its source and tests, and how it names
  things; what differs in convention (coordinate system, orientation, storage as one felt,
  `u252`, tie-breaks).
- What has no meaning on-chain, and why.
- **Against the game's needs N-1 to N-8** of `docs/needs/hexmap.md` and milestone L-M1: for
  each need, whether `hexx` has it, whether `origami_hexmap` has it, and what a port would
  have to add or adapt (generation with margins, edges and openings, assembly of a board from
  up to 4 chunks with row parity, mask cut, line of sight, geometric range and ring,
  rotation and arcs, one flood for many walkers).
- A first view of the **cost** questions: which algorithms fit the arithmetic-then-bitwise
  preference on a 15 × 15 board in one felt, which look expensive.
- **Where the work should land** and under what name: `hexx-cairo` as a mirror of `hexx`,
  `origami_hexmap` extended in place, or both (a mirror published on scarbs.xyz that
  `origami_hexmap` could later depend on); with the consequences for the game's dependency.

Report: `docs/research/LIB-02-hexx-analysis.md` in your repository, with a section
*"Recommendation for gate L-G1"* and a table need → coverage → work. Audit by `[GPT-6-Sol]`
(consistency, completeness against the sources; the report is a document, so the audit is
optional by OPERATIONS §2 — run it, the owner decides on this report). Merge on green CI.

## 4. Stop at the gates

- **L-G1** (after LIB-02): is a port relevant, and where? Write
  `docs/decisions/PENDING-L-G1.md` with the question, the options and your recommendation;
  update `STATUS.md`; send **one** cross-session message to the project manager: first line
  `L-G1: decision needed on the hexx port`, body = the path of the pending file. Then **wait**.
  Do not start LIB-03.
- **L-G2** (after LIB-03, if L-G1 is a go): same procedure with `PENDING-L-G2.md`.

Between the gates you may prepare what does not depend on the decision (repository hygiene,
CI, the parity-table tooling design) but launch no implementation.

## 5. Reporting

`STATUS.md` rewritten at every check-in, dated, signed `[Fable 5.1]`. Messages to the project
manager only at the gates or for a blocker you cannot lift (accounts, permissions, spending).
