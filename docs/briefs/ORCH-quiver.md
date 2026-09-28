# ORCH-quiver — mandate of the orchestrator of track ARC

Written by the project manager on 2026-09-28. This is the first message of the orchestrator
session of `quiver`, in full; the session's own first prompt only points here.

| | |
|---|---|
| Session title | `[Opus 5.5] Orchestrateur quiver (packages)` |
| Model | Opus 5.5: components, storage and access control on a known data model. Fable 5.1 only for a problem that proves hard, with the reason in the brief |
| Repository | `bal7hazar/quiver` (public, MIT, one commit with the `LICENSE`), local checkout `/home/claude/projects/quiver` |
| Mandate | `PLAN.md` of `bal7hazar/grimworld`, section **Track ARC**; ADR-0007 § Arcade packages; `docs/needs/arcade.md` |
| Reports to | The project-manager session `[Fable 5.1] Chef de projet Grim World`, through your repository and, only at the gates or for a blocker, a cross-session message |
| Language | Documents, briefs, commits, pull requests: English |

## 1. What `quiver` is (D-124, D-125)

One repository, a Scarb workspace, **one package per feature**, each published on
scarbs.xyz and versioned on its own, with its own changelog and `GAS.md`. Packages are
**pure Cairo libraries and pure Starknet components: no Dojo**, no world, no model. Its
first packages are the native rewrites of the owner's Arcade packages that Grim World needs:
`quest`, then `achievement`. In time the repository is meant to gather the owner's other
`*-cairo` libraries; moving one is the owner's decision, library by library, and is **not**
part of this mandate.

| Shape of a package | |
|---|---|
| Logic | A Cairo library without storage: state in, state out |
| Component | A Starknet component around it: storage, events, hooks the consumer implements |
| Modes | Storage when a rule of the consumer reads the data; events when it is only shown; chosen per call (ADR-0004) |
| Naming | Package names prefixed by the repository's, as `origami_hexmap` was: `quiver_quest`, `quiver_achievement`; to confirm at gate A-G1 with the registry's availability |

## 2. Read first, in full

In `/home/claude/projects/grimworld` (read `origin/main`, never write there):
`OPERATIONS.md`, `docs/CAIRO.md`, `docs/architecture/ADR-0007-native-starknet.md`,
`docs/architecture/ADR-0004-arcade-packages.md`, `PLAN.md` § *Track ARC*,
`docs/needs/arcade.md`, `docs/design/06-guild.md`, `docs/design/13-titles.md`,
`docs/design/14-quests-region-1.md`, `docs/briefs/ORCH-game.md` §2 (the rules, identical
for you). Reference to analyse: `cartridge-gg/arcade`, `packages/quest` and
`packages/achievement` (clone into the task's worktree, read-only).

## 3. Rules

Those of `grimworld/OPERATIONS.md`: you orchestrate, you do not implement anything large;
sub-agents are `claude` CLI processes launched through the launcher as detached systemd
user units with an allowlist profile; audits by `codex`, never implementation; every title
carries the model that actually ran; committed brief, fresh worktree, log, `REPORT.md`, pull
request with green CI, merged by you; interrupted agents are resumed; after three fix loops
you escalate to the project manager. `docs/CAIRO.md` binds every implementation task.
**Toolchain**: Scarb 2.19.4 and snforge 0.61 (the machine's global versions);
`snforge_std` is a dev-dependency.

**Launcher**: copy `scripts/agent.sh`, `scripts/lock.sh`, `scripts/profiles/` and
`docs/briefs/COMMON.md` from `bal7hazar/grimworld` `main`, adapt names and paths, as your
first pull request with the repository's minimum (README, STATUS.md, PLAN.md owning track
ARC, docs/, `.gitignore`, a CI that checks at least scripts and links).

**Budget**: **1 agent at a time** for you; 3 Grim World agents in total with the game and
the map library (D-118). The launcher refuses a launch above a 5-minute load of 12 or under
8 GB available. `claude auth status` must show `claude-b7r` before the first launch.

**Publishing** on scarbs.xyz is outward-facing and cannot be undone: every publication
needs the project manager's go, who decides in the owner's name (D-132; procedure in
the game's `OPERATIONS.md` §7). No sub-agent publishes.

## 4. First task: ARC-01 — analysis

Sub-agent **Opus 5.5**, profile `research`. Report
`docs/research/ARC-01-quest-achievement.md`:

- The two Dojo packages as they are: data model, storage and event modes, hooks, intervals,
  prerequisites, claim; every dependency on Dojo and what replaces it.
- The defects found by reading (ADR-0004, points 3 to 5), each confirmed or refuted in the
  source, as future test cases.
- The **API of the native packages**: the library's functions, the component's storage,
  events, entrypoints and hook traits, with signatures; what the consumer must implement;
  access control (who may report progress: only contracts the consumer registers).
- Against the game's needs A-1 to A-9 of `docs/needs/arcade.md`: covered, adapted, missing.
- Cost: storage writes per progress call and per claim; what packing saves.
- The workspace: layout, how a package depends on another, **CI by affected package**
  (a change runs the package and its dependents only; the whole workspace on `main` and
  before a release), publication per package.

Audit by `[GPT-6-Sol]`. Merge on green CI.

## 5. Stop at the gate

**A-G1** (after ARC-01): is the API accepted? Write `docs/decisions/PENDING-A-G1.md`
(question, options, recommendation), update `STATUS.md`, send one cross-session message to
the project manager whose first line is `A-G1: decision needed on the API of quiver` and
whose body is the path of that file. Launch no implementation before the answer.
