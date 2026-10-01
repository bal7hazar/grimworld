# Plan

Status: **v0.30, 2026-09-29** (v0.30: track CV, the client's visual work on the owner's Mac (D-146): ART-02, CLI-03a, SPK-6a; the owner's review of ARC-06 (D-147); v0.29: the organisation of Cairo code (D-143): ARC-06, ARC-07, ENG-R1; v0.28: SPK-1 done; fights played on the client and sent in batches (D-133), DES-21 before ENG-01, SPK-1b; v0.27: Sepolia credentials provided, SPK-1 unblocked; v0.26: gate A-G1 decided, the API of quiver accepted (D-131); v0.25: the indexer is our own (D-130), tasks IDX-01 and IDX-02; v0.24: the project manager decides by its recommendations (D-128); cost threshold kept as a target, SPK-1 brought forward to measure on Sepolia, cost constraint on ENG-01 (D-129); v0.23: SPK-2 counts 5 Rifts a day; DES-20; scope of the indexer answered; Sonnet 5.5 for new mechanical launches; v0.22: gate L-G2 decided, the porting plan of `hexx` accepted (D-126); the flood of the tick stops at 15 layers (D-127); v0.21: the repository of track ARC is `bal7hazar/quiver`; its orchestrator's mandate; fix loops escalate to the project manager; v0.20: track ARC in **one repository** holding separate Scarb packages, CI by affected package (D-125); v0.19: track ARC, the Arcade packages rewritten natively (D-124); v0.18: **native Starknet, without Dojo** (D-123, ADR-0007): SPK-5b, FND-01b, SPK-11 added, SPK-8 dropped, SPK-2 measures both, N-9 void; v0.17: N-9, the game cannot build `origami_hexmap` 1.8.0 on Dojo's Cairo 2.13: SPK-7 standalone on 2.19, compiler target studied by LIB-03 for L-G2; v0.16: the window follows the adventurer, 15 × 16, not stored (D-120): SPK-7, ENG-07, L-M1 and R-12 follow; v0.15: gate L-G1 decided by the owner: `hexx` ported in full in `hexx-cairo`, `origami_hexmap` decommissioned at the end (D-119); FND-03 done; v0.14: Phase 0 opened by the project manager: M0 reached, IDE-07 closed, orchestrator briefs in `docs/briefs/ORCH-*.md`, ADR-0001/0003 spike rows moved to burner accounts; v0.13: reconciled after the project manager's first report; proposed decisions accepted; spikes moved to burner accounts; v0.12: track LIB, the map library under its own orchestrator, from the analysis of `hexx` to releases on scarbs.xyz; codex models verified; v0.11: project manager and orchestrators separated; Cairo engineering rules, gas budgets on tests; v0.10: MVP on burner accounts and transaction-hash randomness, behind interfaces; verifiable randomness and accounts move to version 1; v0.9: fully generative maps, drawn at reveal; v0.8: large maps in chunks, ADR-0006; v0.7: lore, Rifts (three open, five a day), invisible chain, accounts behind an interface with burners first, interface and rooms designed; v0.6: owner's third review: looted equipment, boss armor sets, trade and auction house enter the MVP; companions considered and dropped; v0.5: mobile first with responsive desktop; design backlog added; v0.4: owner's second review: PixiJS accepted, implementation on the VPS, asset licence forbids redistribution, Sepolia autonomous; v0.1: first plan; v0.2: owner's first review: mainnet accepted, hex maps, mobile first, defeat softened, instances not saved; v0.3: aligned on the owner's operating conventions: CLI sub-agents, codex audits, launcher, status file).

Process rules are in [OPERATIONS.md](OPERATIONS.md); live state in [STATUS.md](STATUS.md).
The orchestrator keeps this file current: the header is bumped whenever a phase, a budget
or a decision changes.

**Status legend**: `todo` · `doing` · `audit` · `done` · `blocked` · `dropped`

**Audit lenses** (OPERATIONS §6): `D` design conformance · `S` security · `P` determinism
& parity · `C` cost · `Q` code quality · `V` content validation

## Overview

| Phase | Goal | Gate: what must be demonstrated |
|---|---|---|
| **−1 Ideation** | Documents agreed | Owner has ruled on decisions D-xx and questions needed by Phase 0 |
| **0 Foundations** | Stack validated, repo ready | ADR-0001, 0002, 0003 and 0007 confirmed on measurements; CI green on empty contracts |
| **1 Walking skeleton** | Walk through a generated instance, on-chain, with optimistic client | Create adventurer → enter zone → cross rooms → reach a hub, on Sepolia |
| **2 Combat** | Fight goblins with a build | Clear a room of 5 goblins with each MVP profession; parity suite at 0 divergence |
| **3 Career** | Quests, XP, ranks, trials | Wood → Tin through quests and a trial. **Fun gate**: playtest S-1, S-4 |
| **4 Rewards** | Loot, alchemy, merchants | Full expedition loop with loot, brewing and belt |
| **5 World** | Region 1 complete, hubs alive | All MVP content of design/09 playable; S-6 demonstrated |
| **6 Hardening** | Ready for a public network with value | Cross-cutting and external audits closed; playtest on Sepolia |
| **7 Launch** | Mainnet | — |
| **Later** | Post-MVP backlog | See design/09 |

Phases 2–4 contain tracks that run in parallel once their interfaces are frozen.

---

## Phase −1 — Ideation

| ID | Task | Owner | Status |
|---|---|---|---|
| IDE-01 | Consolidate ideation into design documents, context, operations, plan | Orchestrator | done |
| IDE-02 | Owner review, round 1: mainnet, deterministic combat, hexes, hubs, alchemy, ranks, instances | Owner | done |
| IDE-02b | Revise documents after round 1 (v0.2) | Orchestrator | done |
| IDE-03 | Owner's second review: client, machine, licence, merges | Owner | done |
| IDE-07 | Owner rules on what remains open in `docs/decisions/2026-09-28-owner-review-2.md` (not blocking Phase 0) | Owner | done (2026-09-28: all proposed decisions accepted; Q-12 stays open, needed by Phase 2) |
| IDE-08 | Commit and push the documents to `main` | Orchestrator, on the owner's request | done |
| IDE-04 | Realign OPERATIONS, PLAN, STATUS and decisions on the owner's examples | Orchestrator | done |
| IDE-06 | Write the VPS bootstrap prompt | Orchestrator | done |
| IDE-05 | Remove `example/` | Owner | todo (the folder is in the main checkout, untracked) |

## Phase 0 — Foundations

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| FND-00 | **Bootstrap the project-manager session on the VPS** from `docs/briefs/PM-vps-bootstrap.md`: checks accounts, toolchain, repository, credentials presence; reports to the owner | IDE-03 | Owner starts it | — | done |
| SPK-5 | Pin toolchain (Dojo, Cairo, Scarb, Katana, Torii, dojo.js); reproducible build. Controller is pinned by SPK-9, not here | — | Sonnet 5 | Q | done (2026-09-28, [#14](https://github.com/bal7hazar/grimworld/pull/14); [report](docs/reports/SPK-5-toolchain.md)) |
| SPK-5b | **Re-pin the toolchain without Dojo** (ADR-0007): Scarb 2.19.4 and snforge 0.61 (the machine's versions), a local Starknet node that accepts the classes of Cairo 2.19, deployment tool, starknet.js; remove sozo, katana-through-sozo and torii from `scripts/setup-toolchain.sh` and `.tool-versions`; reproducible build | — | Sonnet 5 | Q | done (2026-09-28, [#24](https://github.com/bal7hazar/grimworld/pull/24); [report](docs/reports/SPK-5b-toolchain-native.md); NS-1: starknet-devnet 0.10.0) |
| FND-01b | **Scaffold reworked as native contracts**: no Dojo dependency, no `dojo_dev.toml`; two contracts (persistent, ephemeral) with the layering of ADR-0007; snforge tests that deploy them; client workspace on starknet.js | SPK-5b | Sonnet 5 | Q | done (2026-09-28, [#27](https://github.com/bal7hazar/grimworld/pull/27); [report](docs/reports/FND-01b-scaffold-native.md)) |
| FND-01 | Repository scaffold: `contracts/`, `client/`, `docs/`, scripts, layering of CONTEXT §4 | SPK-5 | Sonnet 5 | Q | done (2026-09-28, [#18](https://github.com/bal7hazar/grimworld/pull/18); [report](docs/reports/FND-01-scaffold.md); `origami_hexmap` test escalated as N-9) |
| FND-06 | Gas tooling: budgets on tests, `docs/BUDGETS.md` generated from a test run, CI failing on a budget exceeded, gas table template for `REPORT.md` | FND-02 | Sonnet 5.5 | Q | done (2026-09-28, [#42](https://github.com/bal7hazar/grimworld/pull/42); `scripts/gas_budgets.py`, [report](docs/reports/FND-06-gas-tooling.md)) |
| FND-02 | CI: build, format, lint, tests for contracts and client, **on the toolchain of SPK-5b** (no sozo, katana or torii as a required check) | FND-01 | Sonnet 5 | S Q | done (2026-09-28, [#21](https://github.com/bal7hazar/grimworld/pull/21); [report](docs/reports/FND-02-ci.md)) |
| FND-03 | Agent tooling: `scripts/agent.sh` launcher ported from the owner's other repositories (profiles research / implement / audit, detached units, logs, resume), `docs/briefs/COMMON.md`, build lock, concurrency budget measured. **Adapted, not copied**: the reference launcher runs with `--dangerously-skip-permissions`, which OPERATIONS §4 forbids; ours grants an allowlist per profile. It initialises the `assets` submodule only in the worktrees of tasks that need the art | FND-00 | Orchestrator | S | done (2026-09-28; `scripts/agent.sh`, `scripts/lock.sh`, `scripts/profiles/`, `docs/briefs/COMMON.md`, CI `tooling`; budget measured, kept at 3) |
| SPK-1 | Latency **and cost on Sepolia** (D-129): submission → pre-confirmed → accepted from a burner account; and the gas of the worst tick, a queue of 10 moves, an exploring queue, enter and leave, as native contracts. **Brought forward from Phase 1** | SPK-5b, FND-01b, the Sepolia credentials | Opus 5.5 | C | done (2026-09-28, #45; the threshold does not hold with one action per transaction: D-133) |
| SPK-1b | **The fixed part of a transaction** on Sepolia with the burner class of the MVP, with and without a paymaster; a few tens of transactions, under the rules of SPK-1 (D-133) | SPK-1 | Opus 5.5 | C S | done (2026-09-29, [#51](https://github.com/bal7hazar/grimworld/pull/51); burner fixed part 717,435 L2 gas, D-133 stands; [report](docs/reports/SPK-1b-fixed-part.md)) |
| SPK-2 | Cost spike: worst-case tick and 10-move queue on a throwaway contract; **cost of an active player per day** (5 Rifts, D-101, quests, hub actions), fully sponsored. **Measured twice, on the same worst cases**: on Dojo 1.8 (baseline, first run) and as native contracts (ADR-0007); the report gives the difference per action | SPK-5 | Opus 5.5 | C | done (2026-09-28, [#25](https://github.com/bal7hazar/grimworld/pull/25); [report](docs/reports/SPK-2-cost.md); native expedition $0.69 to $0.93, the threshold does not hold) |
| SPK-3 | Verifiable randomness spike: overhead, latency, provider-down behaviour. **Not needed for the MVP** (D-110); before version 1 | SPK-5 | Opus 5.5 | S | todo (V1) |
| SPK-4 | Parity spike, two options measured: (a) TypeScript mirror checked by Cairo-generated vectors; (b) **the Cairo code itself run in the client** through a Cairo VM in WebAssembly, as in the owner's physics game. Needs the game logic as a pure library (state in, state out) | SPK-5 | Opus 5.5 | P | done (2026-09-29, [#82](https://github.com/bal7hazar/grimworld/pull/82); option (a), a TypeScript mirror gated by vectors from the Cairo code; [report](docs/reports/SPK-4-parity.md)) |
| SPK-6 | Client spike on real phones: PixiJS on demand in Capacitor; battery, heat, transactions from a burner account (ADR-0003 thresholds, without its Controller and vRNG rows, which move to SPK-9); tile size and zoom for sight of radius 6 | SPK-5 | Opus 5.5 | — | todo, in two steps (D-151), **both moved to the end, before Phase 6; Android dropped for now** (D-152); protocol SPK-6a |
| FND-05 | Provider interfaces: `fate(domain)` with the transaction-hash implementation and a deployment check refusing it on mainnet; account provider with the burner implementation | FND-01 | Opus 5.5 | S Q | done (2026-09-29, [#92](https://github.com/bal7hazar/grimworld/pull/92); [report](docs/reports/FND-05-providers.md)) |
| SPK-9 | **Before version 1.** Accounts spike (ADR-0005): does Controller work on Sepolia from the app shell with sessions, sponsored fees and vRNG; what a burner can use instead | SPK-5 | Opus 5.5 | S | todo |
| SPK-8 | Arcade packages spike: `quest` in storage mode and `achievement` in event mode on a throwaway world; progress keyed by adventurer id; what Controller displays; tests for the edge cases listed in ADR-0004 | SPK-5 | Opus 5.5 | D S | dropped (ADR-0007, D-124: replaced by ARC-01 on the native packages) |
| SPK-10 | Player entropy study (ADR-0006, CM-8): how many cheap irreversible options exist in typical situations, what a program gains by steering, measured on the balance simulator | BAL-01 | Opus 5.5 + GPT-6-Astra | S | todo |
| SPK-7 | **Chunked map spike** (ADR-0006): chunk generation with margins; **window of 15 × 16 that follows the adventurer, assembled at each tick** from chunks of 15 × 15 without a loop over rows; shared flood for 8 goblins, **stopped at 15 layers and measured also at 10, 20 and without a limit on a winding board** (D-127); goblins crossing chunks; line of sight; all measured. **Worst case of the tick**: 4 chunks overlapped, two layers each (terrain, occupied), 8 awake goblins, **compared with and without a stored window**. Fallback measured if needed: sight 5 on 13 × 14. Runs in the game's workspace on Cairo 2.19 (ADR-0007), with `origami_hexmap` 1.8.0 | SPK-5b | Opus 5.5 | C P | done (2026-09-28, [#50](https://github.com/bal7hazar/grimworld/pull/50); +720,000 L2 gas per tick with goblins, R-12 partly realised; [report](docs/reports/SPK-7-chunked-maps.md)) |
| LIB-01 | Map library work needed by the game: see **track LIB** below (milestone L-M1) | — | Hexmap orchestrator | — | todo |
| TOOL-01 | Map tool: draw the **outline of a zone** (chunks and border masks) and authored chunks; write them to the registry; render the world map from outlines | LIB-05 | Opus 5.5 | D V Q | todo |
| ART-00 | Asset pipeline outside git: pack copied to the VPS by the owner, atlas packing script, clean-up of generated goblin sheets into transparent sprites, renaming after our castes, credit to Pixel Frog | FND-00 | Sonnet 5 | IP check | done (2026-09-28, [#12](https://github.com/bal7hazar/grimworld/pull/12); [report](docs/reports/ART-00-asset-pipeline.md)) |
| SPK-11 | **Indexer spike** (ADR-0007): what needs indexing at all against what the client reads by view calls; an existing generic indexer configured for our events against our own; reorg handling; hosting and cost | FND-01b | Opus 5.5 | S Q | done (2026-09-28; our own indexer, D-130) |
| FND-04 | Write spike results into the ADRs; set budgets (actions per queue, cost per expedition, power); **the storage slots changed per transaction, read from the traces of SPK-1's and SPK-1b's Sepolia transactions** (quiver's 0.4M per slot checked) | SPK-1…7 | Opus 5.5 (orchestrator reviews) | C D | done (2026-09-29, [#71](https://github.com/bal7hazar/grimworld/pull/71); [cost budget](docs/architecture/cost-budget.md), slots: new about 453,500, other about 32,000, conditional fits; [report](docs/reports/FND-04-budgets.md)) |
| FND-07 | **Launcher items for the gate of Phase 0** (the launcher is frozen until then, project manager 2026-09-29): M1, a CI fixture for the timed-out detached launch (PR 80's pid-and-group stop, then the slot check), and the notes N1–N4 of [the audit of 5d14d89](docs/reports/launcher-5d14d89-audit-gpt-6-sol.md); L-3, a CI check refusing a pull request that deletes a decision file or a row of CONTEXT §6 | FND-03 | Orchestrator | S Q | todo, at the gate |

**Exit criteria**: ADRs accepted or option B re-opened; budgets written in design/02;
`main` builds from a clean machine.

## Track LIB — the map library (its own orchestrator)

Runs beside the game's phases, in the library's repository, under **a second
orchestrator** created by the project manager (OPERATIONS §1). The game consumes the
library **by published version**, never by git revision.

| | |
|---|---|
| Repository | **`bal7hazar/hexx-cairo`** (D-119, owner at gate L-G1): `hexx` ported in full wherever it makes sense on-chain, extended with what Cairo and the network require; the engine of `origami_hexmap` is taken over there with identical results |
| Meanwhile | The game consumes `origami_hexmap` 1.8.0: since ADR-0007 the game is on Cairo 2.19 and builds it (N-9 is void). To fix in the library all the same: `snforge_std` declared as a regular dependency. `origami_hexmap` is decommissioned once the port is complete and the game has migrated |
| Subject | `origami_hexmap` (today in `dojoengine/origami`, `crates/hexmap`) and the Rust crate [`hexx`](https://github.com/ManevilleF/hexx), whose names the library already follows |
| Orchestrator | Opus 5.5 or Fable 5.1, chosen by the project manager. Algorithms under a gas budget are hard problems: Fable is a legitimate choice here |
| Rules | `docs/CAIRO.md` in full: test-driven, gas budget on every test, execution cost first, arithmetic then bitwise then loops, `u252`, oracles |
| Convention | The owner's, from the other programmes: mirror the Rust crate, same names, same API where it makes sense on-chain, deviations documented; a generated parity table checked in CI; numeric results are API |
| Interface with the game | The game writes what it needs in `docs/needs/hexmap.md`; the library's orchestrator answers by releases and a changelog |

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| LIB-02 | **Analysis of `hexx`** and of its intersection with `origami_hexmap`: what `hexx` offers (coordinates, directions, rotation, lines, rings, spirals, ranges, field of view, field of movement, pathfinding, layouts, chunks or wrapping, mesh and rendering helpers), what the library already covers, what differs in convention (coordinate system, orientation, storage), what has no meaning on-chain. Report in `docs/research/` of the library | — | Opus 5.5, research | GPT-6-Sol | done (2026-09-28, audited twice) |
| **Gate L-G1** | **Is a port relevant?** Owner's decision on the report | LIB-02 | Owner | — | **decided 2026-09-28**: in full, in `hexx-cairo` (D-119) |
| LIB-03 | **Porting analysis**, if relevant: milestones, API per milestone, what is mirrored and what is adapted, gas targets per function, release plan. First milestone = **minimal coverage for Grim World** (below) | L-G1 | Opus 5.5 or Fable 5.1 | GPT-6-Astra | done (2026-09-28; five audit passes, merged with open points carried into the briefs) |
| **Gate L-G2** | **Is the plan accepted?** Owner's decision | LIB-03 | Owner | — | **decided 2026-09-28**: accepted (D-126) |
| LIB-04 | Repository, CI, parity table, gas tooling, publication pipeline to scarbs.xyz | L-G2 | Sonnet 5 | GPT-6-Luna | todo |
| LIB-05 | **Milestone L-M1**: implementation, test-driven, at minimal cost; **first the assembly (N-3) and the flood with its selection (N-8), measured on their worst cases** (D-126); **released on scarbs.xyz** | LIB-04 | Opus 5.5, Fable 5.1 for the hardest algorithms | GPT-6-Astra (determinism, cost) | doing: **`hexx` 0.1.0-rc.1 published 2026-10-01** (D-173: N-3, N-4, N-5, N-7, N-8; ENG-02's content); rc.2 (N-1, N-2) after the chunk shape (D-165); N-6 merged after Codex returns |
| LIB-06 | Milestones L-M2 and following, each ending with a release | LIB-05 | As above | As above | todo |
| LIB-07 | **Final release**: parity reached or exclusions closed and documented | LIB-06 | — | GPT-6-Astra | todo |

#### Milestone L-M1 — what the game needs first

| Need | For | Source |
|---|---|---|
| Generation of a board **given its margins** | Chunks that join without seams | ADR-0006 |
| Edges and openings between boards | Reachability of all chunks; emerging outlines | ADR-0006 |
| **Assembly of a board of 15 × 16 from up to 4 chunks of 15 × 15**, the origin on an even global row | The simulation window, assembled at each tick | ADR-0006 §4 |
| Cutting a board by a mask | Zone outlines | ADR-0006 |
| **Line of sight** between two tiles | Ranged attacks, spells, goblin perception | design/04 |
| Range and ring as **geometry**, ignoring walls | Sight of radius 6, areas of effect | design/04, ADR-0006 |
| Directions, opposite, rotation by steps of 60°; the arc of a tile relative to a facing | Facing, flank, back | design/04 |
| One flood giving every goblin its next step, on a board with extra obstacles | The tick | design/02 |
| Distance, neighbours | Everywhere | — |

What is already in the library (shortest path, weighted path, field of movement, range and
ring by movement, generators, distribution) is checked against these needs by LIB-02, not
assumed.

#### Releases

| Version | Content | Consumed by the game at |
|---|---|---|
| Intermediate, one per milestone | L-M1 first | SPK-7 uses a pre-release of L-M1; ENG-05 needs its release |
| Final | Parity or documented exclusions | Version 1 of the game |

Generator outputs are API: a change in what a seed produces is a minor version and moves
the game's test vectors.

## Track ARC — the Arcade packages, native (D-124, D-125)

The packages of the owner's Arcade suite that the game uses are **rewritten without Dojo,
as pure Starknet components and pure Cairo** (ADR-0007), **in one repository** that holds
them as separate Scarb packages (D-125). The game consumes them **by published version**. Same conventions as track LIB:
`docs/CAIRO.md` in full, a gas budget on every test, results are API.

| | |
|---|---|
| Reference | `cartridge-gg/arcade`, `packages/quest` and `packages/achievement` (MIT by the owner's statement; ADR-0004 lists what to settle: the licence file, event mode untested, the quest edge cases) |
| Shape | The logic as a Cairo library without storage; a Starknet component around it with storage, events and hooks; no world, no model |
| Repository | **`bal7hazar/quiver`** (name chosen by the owner; public, MIT; created 2026-09-28): one repository, one name related to video games. A Scarb workspace; **one package per feature**, each published on its own, versioned on its own, with its own changelog and `GAS.md` |
| CI | **Runs the checks of the packages a change touches, and of those that depend on them**; nothing else. The whole workspace runs on `main` and before a release |
| Direction | In time, the home of the owner's other `*-cairo` repositories. **Not part of this track**: moving an existing library is decided library by library, by the owner. `hexx-cairo` stays where it is for now (D-119) |
| Order | `quest` (needed by GLD-02, Phase 3), then `achievement` (titles); `leaderboard` and `social` after the MVP |
| Orchestrator | Opus 5.5, mandate in [docs/briefs/ORCH-quiver.md](docs/briefs/ORCH-quiver.md) |
| Interface with the game | The game writes its needs in `docs/needs/arcade.md`; the track answers by releases |

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| ARC-00 | The repository: name and visibility by the owner; created once named | — | Owner / project manager | — | done (2026-09-28: `bal7hazar/quiver`) |
| ARC-01 | **Analysis** of `quest` and `achievement` as they are: data model, modes, hooks, the edge cases of ADR-0004, what depends on Dojo; API of the native packages; what Grim World needs first (quests one-shot and daily, prerequisites, progress keyed by adventurer id, claim hook; titles with tiers) | ARC-00 | Opus 5.5, research | GPT-6-Sol | done (2026-09-28; audited three times) |
| **Gate A-G1** | **Is the API accepted?** | ARC-01 | Project manager (D-128) | — | **decided 2026-09-28**: accepted (D-131) |
| ARC-02 | Workspace, **CI by affected package** (a change in `quest` runs `quest` and its dependents only), gas tooling, publication pipeline per package | A-G1 | Sonnet 5.5 | GPT-6-Luna | done |
| ARC-03 | `quest`: implementation, test-driven; released on scarbs.xyz | ARC-02 | Opus 5.5 | GPT-6-Astra (access control, ownership) | done: `quiver_quest` 0.1.0 published on 2026-09-29 (D-138) |
| ARC-04 | `achievement`: a package of the same workspace; **event mode only in 0.1.0** (D-139); implementation, release | ARC-03 | Opus 5.5 | GPT-6-Astra | done: `quiver_achievement` 0.1.0 published on 2026-09-29 (D-142) |
| ARC-06 | **The pattern of docs/CAIRO.md §7** (D-143): model, storage, tracked event, store; its cost against a hand-written write; a reference implementation on one model, shown to the owner before any rework | — | Opus 5.5 | Q (organisation) + GPT-6-Sol, C + GPT-6-Astra | done (2026-09-29, quiver #19; reviewed by the owner: D-147) |
| ARC-07 | `quiver_quest` and `quiver_achievement` rewritten on the pattern as **0.2.0**; behaviour, tests and gas caps kept; **D-147: no `logic/` folder; the consumer chooses which models are tracked**; ARC-07a (`quest`) done and **accepted by the owner (D-167)**; ARC-07b (`achievement`) under the test rule of D-167, with the Arcade → quiver mapping; publication asked of the project manager | ARC-06, the owner's review (D-147, D-167) | Opus 5.5 | D S C Q + GPT-6-Astra | todo |
| ARC-05 | `leaderboard`, `social` | After the MVP | — | — | todo |

## Track CV — the client's visual work, on the owner's Mac (D-146)

Run by a local orchestrator on the owner's Mac, which has a browser the agents can drive. Mandate:
[docs/briefs/ORCH-client-visual.md](docs/briefs/ORCH-client-visual.md). It writes `client/app`
(rendering, interface, input; `account/` and `chain.ts` stay CLI-01's) and `tools/art`; live state in `docs/status/client-visual.md`. Budget on the Mac: 5 agents (owner). Tasks of the game
lent to it (D-149): IDX-01.

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| ART-02 | ART-00's atlas corrected: hand-drawn units at their native height, only the generated goblins reduced to the pack's scale (owner, D-146 corrected; ART-1 answered provisionally), Python 3.12, the same output on macOS and Linux | ART-00 | Opus 5.5 | Q + GPT-6-Sol | todo |
| CLI-03a | A rendering sandbox on fixed data: hexagonal room on demand, camera that follows, sight 6, facing and arcs, touch; no rule outside `client/sim` (mandate §6) | — | Opus 5.5 | D Q + GPT-6-Sol | todo |
| SPK-12 | **Client-side proving against L2 batches** (D-161): proving the deterministic segments on the client (SNIP-36), one proof a segment, randomness on L2; cost, proving time, proof size, co-op, reveal, cheating, on our figures; the owner decides whether ADR-0001 is reopened. Lent to track CV | CBT-02, LIB-05's tick figures | Opus 5.5, research | C S + GPT-6-Astra | todo |
| SPK-15 | **The tick's levers before CBT-05** (D-171): the frozen goblins as words, a condition's cost on the member, the executor's overhead; engineering levers told from design levers, each with its gain on the worst tick (6.51M with CBT-04 and CBT-03a) and on S1 | CBT-04, CBT-03a | Opus 5.5, research | C + GPT-6-Astra | todo, now |
| SPK-14 | **Hexagonal chunks of 251 tiles** (9-9-11-9-9-11, the owner's finding, D-165): one felt a layer; the shape's indexing, the storage words (`LIVE`, the edge bits, `OUTLINE`), the 15 × 16 window's assembly, reveal and generation with six neighbours, the library and the tool, costs measured against SPK-7; a recommendation for the owner, before ENG-05 and the library's N-1 and N-2 | SPK-7, LIB-05 N-3/N-4 | Opus 5.5, research | C P + GPT-6-Astra | done (2026-09-30, [#202](https://github.com/bal7hazar/grimworld/pull/202); [report](docs/reports/SPK-14-hexagonal-chunks.md); recommendation: keep 15 × 15; **the owner kept 15 × 15 (D-165 closed)**, so the two review minors deferred for the hexagon are void) |
| SPK-13 | Builds of the same sources that differ in gas and Sierra size (Scarb 2.19.4, found by the map library): reproduce, diff, minimise; the game's class hashes checked (D-154); lent to track CV | — | Opus 5.5 | Q + GPT-6-Sol | todo |
| SPK-6a | The protocol of SPK-6 on real phones | — | Opus 5.5, research | D | done or closing (#138; D-151) |
| CV-02 | The Capacitor shell (configuration, iOS and Android projects) for SPK-6.1; CLI-01 adds accounts and the chain (D-151) | CLI-03a | Opus 5.5 | S Q | todo, **moved before Phase 6** with SPK-6.1 (D-152) |
| SPK-6.1 | SPK-6's rendering verdict on the owner's phones: battery, heat (fails from Android's moderate throttling level), frame time, taps; idle animations at 12 fps, also off | CV-02 | Orchestrator + Opus 5.5 | — | todo, **moved before Phase 6** (D-152) |

CLI-03 (the sandbox wired to `client/sim` and the chain) follows CLI-01 and CLI-02; CLI-05, CLI-07
and CLI-08 are candidates for this track.

## Phase 1 — Walking skeleton

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| ENG-01 | Freeze core interfaces, **under a cost budget for the fixed part of a transaction and the reads and writes of a tick** (D-129): persistent and ephemeral domains, snapshot and results interface, storage layouts and packing, registry shapes, **events as the interface of the indexer** (the nine events and the views `open_lot_count`, `trade_count` of SPK-11; the snapshot of at most 16 task ids an instance reports, D-131), access control between contracts, number and boundaries of contracts against the class size limit (ADR-0007). **First item of its cost budget: the storage slots each entrypoint changes per transaction** (FND-04 on our receipts: about 453,500 L2 gas per **new** slot and 32,000 per overwritten or zeroed one, per transaction; quiver's 402,000 is of the size of a new slot; [cost budget](docs/architecture/cost-budget.md)), checked against SPK-2's and SPK-1's receipts; DES-21's batches counted in slots, not only gas. D-135: quest acceptance mandatory, at most 4 quests held (3 active and one contract). From DES-21 (design/02): the `play` entrypoint, `instance_state` and `instance_region`, the ENG-01 list; OP-1 answered by D-136 (an unrevealed chunk is wall in the window until sight reveals it; the client never waits for a chunk) | FND-04, DES-21 | Orchestrator + Opus 5.5 | D S | done (2026-09-29, #81; two accounting gaps carried to ENG-01b, D-141) |
| ENG-01b | The cost accounting of ENG-01 completed: an objective completed by the ticks of a standalone action, the first-entry branch of `enter_rift`, the slot bound of a reveal (findings F-2, F-3, F-4 of ENG-01's audit) | ENG-01 | Sonnet 5.5 | C + GPT-6-Astra | done (2026-09-29, [#93](https://github.com/bal7hazar/grimworld/pull/93); [report](docs/reports/ENG-01b-accounting.md)) |
| ENG-R1 | The game's contracts written so far brought to docs/CAIRO.md §7 (D-143, D-147: no `logic/`-like layer, tracking optional): helpers and packing scoped in traits, tracked models emitting through the store. Deferred to it from ENG-04's audit ([report](docs/reports/ENG-04-audit-gpt-6-astra.md)): F-5, `Hub`'s storage access and the account list's swap removal behind the store, not in `systems/hub.cairo` (the store's shape is ARC-06's); F-6, the inline check `not in the account list` and `AdventurerListImpl`'s `lane above 6` panics into an `Assert` impl and `errors`. From ENG-06's audit ([report](docs/reports/ENG-06-audit-gpt-6-astra.md)): F-2, `Instances`' `WordImpl` storage syscalls, the lifecycle's direct map access, and `Hub.change_pack`'s page aggregation, behind the store and the models. From CBT-08a's audit ([report](docs/reports/CBT-08a-audit-gpt-6-astra.md)): F-1, `set_build`'s new storage access behind the store. **ENG-R1a, deferred to its fix loop after Codex's audits** (Claude-side quality re-audit at 45ff32b, `~/orchestrator/audits/ENG-R1a-2-quality-claude-opus.md`): the report's cost figures (+3.8 % a call, AC-4, *Escalations*); notes: `StoredLanes::ids` renamed, a test pinning the store's `Adventurer` word offsets against the derived `Store`, unit tests for `ResultsTrait::credit`, `reaches_hub`, `EquippedAssert::assert_worn` and the elite walk, the part cursors out of `set_build`, a comment's wrap | ARC-06, the owner's review | Opus 5.5 | Q (organisation) | doing: ENG-R1a (`Hub`, [brief](docs/briefs/ENG-R1a-hub-on-the-pattern.md)) running since 2026-10-01 02:14, shown to the owner; then ENG-R1b (`Instances`, `Registry`, `Market`), ENG-R1c (the logic package)  |
| ENG-02a | The fixed-point table of `2^(x/40)` (D-140: 16 fractional bits, rounded to nearest, generated once for Cairo and the client's mirror, checked in CI) | ENG-01 | Sonnet 5.5 | P C Q + GPT-6-Astra | done (2026-09-29, [#113](https://github.com/bal7hazar/grimworld/pull/113); [report](docs/reports/ENG-02a-exp2-table.md)) |
| ENG-02 | Hex line of sight and arcs on the map library (`hexx` **0.1.0-rc.1**, by published version, D-173). The packer is ENG-01's `packing`, the seeder FND-05's `derive`, the table ENG-02a ([brief](docs/briefs/ENG-02-geometry.md): the geometry trait CBT-05a consumes). At its merge, the orchestrator adds `python3 contracts/logic/vectors/check.py` to CI's `contracts` job (the committed vector tables checked against the code; CBT-03a's `hit.jsonl` joins it) | ENG-01, LIB-05 rc.1 | Opus 5.5 | P C Q | doing (D-173)  |
| ENG-03 | Registries: region, location, gate + seed data for a test region; **a content version returned with the content, its cost measured** (D-141, E-5) | ENG-01 | Opus 5.5 | D S Q + GPT-6-Astra | done (2026-09-29, [#106](https://github.com/bal7hazar/grimworld/pull/106); [report](docs/reports/ENG-03-registries.md)) |
| ENG-04 | Adventurer creation and ownership | ENG-01 | Opus 5.5 | D S Q + GPT-6-Astra | done (2026-09-29, [#100](https://github.com/bal7hazar/grimworld/pull/100); [report](docs/reports/ENG-04-adventurers.md); F-5, F-6 deferred to ENG-R1) |
| ENG-05 | Chunk reveal engine: random word, generation with margins, edges and openings, bands, quotas, anchors, placement (ADR-0006). D-134: void chunks around every location and outside a zone's outline (wall, never revealed, never stored); a chunk's four corner tiles are always wall | ENG-02, SPK-7, LIB-05 | Opus 5.5 | D S P C Q + GPT-6-Astra | todo |
| ENG-06 | Instance lifecycle: enter with snapshot, resume, return, close; entry draw (Fate); `Instances.set_controller` (ENG-04 calls it from `set_account_owner`, tested there with a double). D-145: read only the records its ticks use, and measure where `bundle`'s 36,000 a slot goes (the call against the read) before the weights are frozen | ENG-03, ENG-04 | Opus 5.5 | D S C Q + GPT-6-Astra | done (2026-09-29, [#120](https://github.com/bal7hazar/grimworld/pull/120); [report](docs/reports/ENG-06-instance-lifecycle.md); F-2 deferred to ENG-R1) |
| ENG-07 | Movement, facing, simulation window (15 × 16, follows the adventurer, assembled at each tick, not stored), action queue with stop conditions, instance clock. From SPK-7: assemble the window only with a goblin awake; read chunks once per batch; B′ (stored window) only if fights pay for it, with a benchmark of a chunk-set change built from valid deferred ticks (SPK-7 audit, finding 3, deferred); select ≤ 8 awake goblins among more. D-134: the window is never clamped; void chunks are a constant in the assembly. D-145: read only the records its ticks use, and measure where `bundle`'s 36,000 a slot goes (the call against the read) before the weights are frozen. The map library's share of a worst tick is 1.06–1.11 M (LIB-05 M1-T9b), CBT-02's pipeline 1.39 M (worst): the budget is the project manager's ([decision](docs/decisions/2026-09-29-cbt-02-tick-cost.md)); a walker beyond the flood's cap (`None` from `Bfs::flood`) holds its tile (D-127). From CBT-02d (#211, report *Escalations* 2–5): frozen goblins kept as words until touched (~0.85 M a tick at the bound; changes `load`'s contract with perception); a hook after step 0 must not wake or sleep a goblin (documented, not enforced); the awake selection 4,663,510 over 100 candidates at step 0. Deferred from #211's cost re-audit (COST-4): reconcile the awake selection's and `Busy`'s absolute figures between isolated and full-suite runs (1,230 and 1,430 apart) before deriving the batch weight from them. **D-172** (SPK-15, #234): L4, perception's one-pass selection (−1.50 M a worst tick, no frozen interface); L1 (the frozen goblins kept as words) decided here on ENG-07's own count of its hooks' writes to frozen goblins; the batch weight stops a batch before a tick that would pass the transaction's limit (a worst tick runs alone); **first**, a representative fight tick defined and measured (a hit, an application, a typical room's awake goblins): S1 and the design levers are judged on it. From ENG-02 (#246): the window's assembly keeps the location's axis orientation, or design/04's tie rule (the lower tile index) differs between the window's index and the location's | ENG-05, ENG-06, ENG-01b | Opus 5.5 | D S P C Q | todo     |
| CLI-01 | Client shell in Capacitor: account provider interface with a **burner** implementation, chain access through starknet.js, subscription to the indexer | FND-01b, IDX-01 (built for the browser first; Capacitor later, D-152) | Opus 5.5 | S Q | todo |
| CLI-02 | Client simulation core mirroring ENG-05/07 + parity harness. SPK-4 / D-140: a TypeScript mirror checked by vectors generated from the Cairo code (option (a)); measure the full tick in TypeScript and Poseidon, which the spike did not | ENG-02, SPK-4 | Opus 5.5 | P Q | todo |
| CLI-03 | Hex room rendering on demand, touch input, facing display, optimistic state with rewind | CLI-01, CLI-02, SPK-6 | Opus 5.5 | D Q + power rules | todo |
| FND-08 | **The burner's funder on a public network**: a service of the game behind FND-05's `Funder` port, tested on the local node; before any play on Sepolia (D-150) | FND-05 | Opus 5.5 | S Q + GPT-6-Astra | done (2026-09-29, [#141](https://github.com/bal7hazar/grimworld/pull/141); [report](docs/reports/FND-08-funder-service.md); caps for decision) |
| FND-09 | `scripts/with-node.sh` on macOS (a fallback without `setsid`) and a `--full-archive` node for the indexer (D-153, item 2) | FND-02 | Sonnet 5.5 | Q + GPT-6-Sol | done (2026-09-29, [#152](https://github.com/bal7hazar/grimworld/pull/152); [report](docs/reports/FND-09-with-node-mac.md)) |
| OPS-01 | Deployment scripts of our own (declare, deploy, configure, upgrade): local node, Sepolia; the indexer. D-156: the funder's stale lock is removed by one named operator, on the one host holding its state file (FND-08, N-1) | ENG-07 | Sonnet 5 | S Q | todo |
| IDX-01 | **The indexer** (D-130): our own process from the prototype of SPK-11; the events frozen by ENG-01; versioned tables, rewind on reorg, queries and subscriptions; the client's freshness rule | ENG-01 | Opus 5.5 | S P Q + GPT-6-Sol | todo (lent to track CV on the Mac, D-149) |
| IDX-02 | The indexer hosted for Sepolia, watched, rebuilt from the chain on demand | IDX-01, OPS-01 | Sonnet 5.5 | S Q | todo |

**Exit criteria**: gate of the overview, demonstrated on Sepolia; constraints M-1…M-6
verified by the cross-cutting audit.

## Phase 2 — Combat

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| CBT-01 | Freeze combat interfaces: actor stats, skill and effect schema, caste schema (the shape of DES-06's sheet). **Pulled forward while the engine chain waits (D-150)** | DES-04 | Orchestrator + Opus 5.5 | D | done (2026-09-29, [#165](https://github.com/bal7hazar/grimworld/pull/165); [report](docs/reports/CBT-01-combat-interfaces.md); open questions A–I for decision) |
| CBT-02 | World tick pipeline (5 steps), regeneration, durations, recharges. From CBT-01 (deferred, [audit](docs/reports/CBT-01-audit-gpt-6-astra.md) CBT-9): the snapshot builder aggregates bonuses for the same condition, and its test oracle with it; before production snapshots, the per-source bounds of CBT-01's question G (DES-06). **D-160**: takes DS-1 to DS-9 of design/20, and, as the lot that builds snapshots, the capacity proof's restrictions (validators, flattening checks, acceptance tests) before any production snapshot | CBT-01 | Opus 5.5 | D P C Q | done (2026-09-30, [#182](https://github.com/bal7hazar/grimworld/pull/182); [report](docs/reports/CBT-02-tick-pipeline.md); cost escalated D-161, merged by D-163) |
| CBT-02b | The tick's cost, no interface change (D-161): no copies of the goblin struct, a cheaper limb split; re-measured against 1.47M a tick. D-163: the worst-case bound proved term by term (COST-1a–c, COST-3). D-160: the snapshot's flattening wired into `Hub.set_build` and `Hub.enter` | CBT-02 | Opus 5.5 | C Q + GPT-6-Astra, GPT-6-Sol | done (2026-09-30, [#196](https://github.com/bal7hazar/grimworld/pull/196); [report](docs/reports/CBT-02b-tick-cost.md); the wiring moved to CBT-02c, D-166) |
| CBT-02c | Design/20's per-source bounds checked once at registration (the registry's validators); the linear flattening wired into `set_build` and `enter`, measured against D-158 and the 50 % class limit (D-166); the capacity proof restated | CBT-02b | Opus 5.5 | D C Q + GPT-6-Astra | done (2026-09-30, [#206](https://github.com/bal7hazar/grimworld/pull/206); [report](docs/reports/CBT-02c-registration-checks.md); merged unwired, the wiring is CBT-02e's, D-168) |
| CBT-02d | The tick's remaining levers (D-166): the goblins' hot fields apart from the array, an index into the content instead of lookups at every load; the worst tick re-proved. From CBT-02b's quality re-audit (deferred): the eight-free-goblin cost test proves each goblin acted in step 2 (an `act` hook that records it, not `Idle`); from #196's Codex review (deferred): the eight-awake limit checked before `conclude` returns on the member's defeat (`types/world.cairo`) | CBT-02b | Opus 5.5 | C Q + GPT-6-Astra | done (2026-10-01, [#211](https://github.com/bal7hazar/grimworld/pull/211); [report](docs/reports/CBT-02d-tick-levers.md); the bound ≤ 3,447,872 a tick inside a batch, 2.35× the target, carried to ENG-07) |
| CBT-02e | The snapshot flattened once at `set_build` in a library class and stored with the adventurer as packed words; `enter` copies it and refuses a stale one; `set_contracts` gains the class hash, `Hub`'s storage the snapshot words (D-168); the entrypoints that invalidate it listed and tested | CBT-02c | Opus 5.5 | D S C Q + GPT-6-Astra | done (2026-10-01, [#212](https://github.com/bal7hazar/grimworld/pull/212); [report](docs/reports/CBT-02e-stored-snapshot.md); deviations accepted: `persistent/Scarb.toml`'s `build-external-contracts`, `IInstanceEntry.create` taking `SnapshotWords`; staleness completed by CBT-02f, D-169) |
| CBT-02f | When a stored snapshot goes stale (D-169): a rules epoch counted by `Hub` on `set_contracts`, stored in the kit word; a counter of the flattening's input kinds returned by `Registry.bundle` and stored instead of the content version; `enter`'s added read measured ([brief](docs/briefs/CBT-02f-flattening-epoch.md)) | CBT-02e | Opus 5.5 | S C Q + GPT-6-Astra | done (2026-10-01, [#219](https://github.com/bal7hazar/grimworld/pull/219); [report](docs/reports/CBT-02f-flattening-epoch.md); the 9-bit epoch's repeat after 512 configuration changes accepted, ENG-01 §3.3) |
| CBT-03 | Weapon attacks, damage formula, armor, arcs, flank and critical. D-140 (design/04 *Edges*): armor clamped at 0; every percent modifier of damage summed and applied once, truncating; damage saturated to [0, 65,535]; a goblin's own tile unmarked asserted; no panic on a legal action. **D-170: split.** CBT-03a ([brief](docs/briefs/CBT-03a-hit.md)): one hit, §5.5 steps 1–4 and §5.6, the arc and flank as inputs; CBT-03b: the arcs and flank from positions, after ENG-02. **CBT-03a, for its fix loop after Codex's audits** (the Claude-fallback review at 36bf2ba, `~/orchestrator/audits/CBT-03a-review-fable.md`): a test that reads `contracts/logic/vectors/hit.jsonl` and checks it against the code (today only a digest constant is compared); the PR body's figures (15 hits, +696,900, ≤ 4,144,772, 2.82×) and `test_hit_cost.cairo:117`'s comment; `HitTrait::damage`'s precondition documented. **`Arc` in `types/combat.cairo` accepted by the orchestrator** (fix loop 1): an addition to CBT-01's combat types; its variant order (Front, FrontSide, RearSide, Back) is the vectors' encoding and is frozen with them | CBT-02 | Opus 5.5 | D S P C Q | doing: CBT-03a (D-170); CBT-03b after ENG-02  |
| CBT-04 | Conditions (MVP five) ([brief](docs/briefs/CBT-04-conditions.md), D-170). **D-172**: SPK-15's L2 (an application written in place, by condition, −0.77 M; and the member's line corrected to 2,114,010) in its fix loop after Codex's audits, or CBT-05a's if that loop has closed | CBT-02 | Opus 5.5 | D P Q | doing (D-170)  |
| CBT-05 | Skill engine: costs, activation, interrupt, effects; skill registry. From CBT-02d (#211): the executor's lookups by id (`hold`, `put`, a stance) still scan the content (~82,000 a skill): pass positions or price the scans. From CBT-04 (#228): `MOVEMENT` (FX-18) is not in the tick's sheets, so Crippled's move cost takes it as a boolean: the held effect's kind in the sheets, or a rule; a `CONDITION`/`CURE` with condition 6–9 panics (`tick: condition not stored`): the validators must refuse it until FX-22 (with CNT-01). From CBT-03a (#229): clamp the scaled `DAMAGE`/`ATTACK_BONUS` before building a `Hit` (§6, at play); one copy of the weapon-strength rule (`HitTrait::weapon_strength` or the snapshot's). **Split**: CBT-05a the executor (§5.14) with SPK-15's L3 (D-172), [brief](docs/briefs/CBT-05a-executor.md), after CBT-03a and CBT-04 merge; CBT-05b the action's costs (§5.3) and traps (§5.11). From ENG-02 (#246): a weapon hit's geometry costs 69,266, more than the hit (46,460): a combined `reach`-and-`arc` call saves one step a hit | CBT-02 | Opus 5.5 | D S P C Q | CBT-05a briefed, launched after CBT-03a, CBT-04 and ENG-02 merge; CBT-05b todo  |
| CBT-06 | Goblin spawn from pack registry; state machine; shared flood pathfinding | CBT-02 | Opus 5.5 | D P C Q | todo |
| CBT-07 | AI profiles: swarm, kite, support, brute | CBT-06 | Opus 5.5 | D P C Q | todo |
| CBT-08a | `set_build`: the bar, attributes, belt and equipment validated in one call; the belt's worst case measured (D-148). CBT-08's first part, pulled forward (D-150) | CBT-01, ENG-04, ENG-06 | Opus 5.5 | D S Q + GPT-6-Astra | done (2026-09-29, [#170](https://github.com/bal7hazar/grimworld/pull/170); [report](docs/reports/CBT-08a-set-build.md); D-158) |
| CBT-08 | Attributes, build lock, skill bar | CBT-05 | Opus 5.5 | D S Q | todo |
| CNT-01 | Seed data: 3 professions × 6 starter skills, 5 castes, MVP packs | CBT-05, CBT-07 | Sonnet 5 | D V | todo |
| CLI-04 | Client simulation of combat + parity vectors | CBT-03…07 | Opus 5.5 | P Q | todo |
| CLI-05 | Combat UI: skill bar, targeting, telegraphs, conditions, combat log | CLI-04 | Opus 5.5 | D Q | todo |
| BAL-01 | Headless balance simulator: run builds against packs, report win rate and ticks | CLI-04 | Opus 5.5 | Q | todo |

Parallel tracks after CBT-02: {CBT-03, CBT-04}, {CBT-05, CBT-08}, {CBT-06, CBT-07}.

## Phase 3 — Career

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| GLD-01 | XP, level, attribute points. From CBT-02e (#212): attribute points are not in the loadout (D-157 A), so attribute ranks never reach a stored snapshot | Phase 2 | Opus 5.5 | D S Q | todo  |
| GLD-02 | Quest registry, board, accept / progress / claim, on the **native `quest` package** (0.2.0, D-143) (track ARC, D-124) in storage mode; the reward hook is the game's | Phase 2, ARC-03 | Opus 5.5 | D S C Q | todo |
| GLD-03 | Objective tracking through the results interface: kill, reach, hand-in | GLD-02 | Opus 5.5 | D S P Q | todo |
| GLD-04 | Merit, ranks, gates by rank | GLD-02 | Opus 5.5 | D S Q | todo |
| GLD-05 | Promotion trials: guild quest in a fixed-seed dungeon | GLD-04 | Opus 5.5 | D S Q | todo |
| GLD-06 | Skill trainers and skill quests | GLD-02 | Opus 5.5 | D S Q | todo |
| CNT-02 | Seed data: MVP quests, 2 trials, trainer skills (6 more per profession) | GLD-02…06 | Sonnet 5 | D V | todo |
| CLI-06 | Hub UI: board, trainer, build editor, character sheet | GLD-01…06 | Opus 5.5 | D Q | todo |
| PLY-01 | **Fun gate** playtest on Sepolia; report against S-1, S-4 | all above | Orchestrator | — | todo |

## Phase 4 — Rewards

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| RWD-01 | Inventory, gold; settlement on return and on defeat | Phase 3 | Opus 5.5 | D S C Q | todo |
| RWD-02 | Remains, loot tables, loot action (Fate) | RWD-01 | Opus 5.5 | D S C Q | todo |
| RWD-03 | Crafter helper and books; rarity signatures, discovery, hints | RWD-01 | Opus 5.5 | D S P C Q | todo |
| RWD-04 | Potions: effects, belt, use in instance | RWD-03, CBT-05 | Opus 5.5 | D S P Q | todo |
| RWD-05 | Merchants, smiths, armorers, collectors. CBT-08a (D-158, audit F-3): every item it creates copies its base's slot and hands into `ItemBase` bits 120–127; `set_build` trusts them | RWD-01 | Opus 5.5 | D S Q | todo |
| RWD-06 | Equipment items as entities: base, requirement, rarity, modifier slots, armor pieces and weighted rating, snapshot into the instance. **D-153: the contract refuses any rarity outside design/15's values (the market key's assumption), tested with 128**. From CBT-02e (#212): `BuildTrait::loadout` does not count a worn armor set's pieces, so set bonuses never reach a stored snapshot (design/20 §6's 1,020 health and 130 energy are not reachable until then); `BASE` lays out no weapon damage. From CBT-02f (#219): a lot that makes `set_build` read another record kind (`BASE`'s weapon statistics, `ARMOR_SET`'s bonuses) adds it to `Registry`'s `Inputs::includes`, or stored snapshots miss its changes; `test_set_build_requests_the_input_kinds` fails until it does | RWD-01 | Opus 5.5 | D S P C Q | todo   |
| RWD-07 | Looted equipment: drop (Fate), identification (Fate), salvage (Fate), setting modifiers, insignias and runes. CBT-08a (D-158, audit F-3): every item it creates copies its base's slot and hands into `ItemBase` bits 120–127; `set_build` trusts them. From CBT-02e (#212, D-168 2): `identify`, `personalise`, `lift_modifier`, `set_modifier` on a worn entity mark the stored snapshot stale; `sell`, `recycle`, `stow`, `Market.escrow` and `exchange` refuse a worn entity (or clear its lane and mark stale), in whichever lot implements them | RWD-06, RWD-02 | Opus 5.5 | D S C Q + GPT-6-Astra | todo  |
| RWD-08 | Boss items and boss armor sets with 3- and 5-piece bonuses | RWD-06 | Opus 5.5 | D S P Q | todo |
| RWD-09 | Trade: direct exchange between players | RWD-06 | Opus 5.5 | D S Q + GPT-6-Astra | todo |
| RWD-10 | Auction house: listings in lots, fees, expiry, purchase | RWD-09 | Opus 5.5 | D S C Q + GPT-6-Astra | todo |
| CNT-03 | Seed data: Region 1 book, loot tables, merchant stock | RWD-02…05 | Sonnet 5 | D V | todo |
| CLI-07 | Inventory, loot reveal, alchemy and grimoire UI | RWD-01…05 | Opus 5.5 | D Q | todo |

## Phase 5 — World

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| WLD-01 | Hub unlock and map travel | Phase 4 | Opus 5.5 | D S Q | todo |
| WLD-04 | Rifts: appearance, stages, grades, Red Rifts, mining, stillstone | WLD-02 | Opus 5.5 | D S P C Q | todo |
| WLD-02 | Multi-floor dungeons, boss rooms, boss AI profile | Phase 4 | Opus 5.5 | D P C Q | todo |
| CNT-04 | Region 1 full content: locations, gates, spawn tables | WLD-01, WLD-02 | Sonnet 5 | D V | todo |
| CNT-05 | Content validation suite (reachability, tables, ranges) | CNT-04 | Sonnet 5 | Q | todo |
| WLD-03 | Hub presence (transport per Q-09) | CLI-06 | Opus 5.5 | S Q | todo |
| CLI-08 | World map, onboarding, mobile layout | CNT-04 | Opus 5.5 | D Q | todo |
| LORE-01 | Names and texts: world, region, professions, skills, castes, quests | Q-11 | Opus 5.5 | D (IP check) | todo |
| ART-01 | Commission: hex tileset, missing animations (hurt, death, cast, knocked down), caster sprite, icon set | ART-00 | Owner | IP check | todo |
| PLY-02 | S-6 demonstration: add a test zone and quest with data only | CNT-05 | Orchestrator | — | todo |

## Phase 6 — Hardening

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| HRD-01 | Cross-cutting security audit of all systems | Phase 5 | Opus 5.5 + GPT-6-Astra | S | todo |
| HRD-02 | Cost pass: worst cases per entrypoint against budgets | Phase 5 | Opus 5.5 | C | todo |
| HRD-03 | Registry permissions, multisig, upgrade policy (Q-08) | Phase 5 | Opus 5.5 | S | todo |
| HRD-04 | Balance pass with BAL-01 and playtest data | PLY-01 | Orchestrator | D | todo |
| HRD-05 | Public playtest on Sepolia | HRD-01…04 | Orchestrator | — | todo |
| HRD-09 | Replace the provisional providers: verifiable randomness, production accounts, sponsored fees (ADR-0002, ADR-0005) | SPK-3, SPK-9 | Opus 5.5 | S + GPT-6-Astra | todo |
| HRD-10 | Pin and verify the checksums of every toolchain download: scarb, snforge and pnpm through their asdf plugins, and the `universal-sierra-compiler` installer (deferred as a minor from the `[GPT-6-Sol]` audit of SPK-5, finding F3, 2026-09-28; sozo, katana and torii are already verified by `scripts/setup-toolchain.sh`) | SPK-5 | Sonnet 5 | S | todo |
| HRD-06 | External audit | HRD-01 | External | S | todo |
| HRD-07 | Paymaster budget and policies for mainnet (Q-10) | HRD-02 | Owner + Orchestrator | S | todo |
| HRD-08 | Store readiness: policy check for on-chain games on both stores, bundled assets, review submission | Phase 5 | Orchestrator | — | todo |

## Phase 7 — Launch

| ID | Task | Depends on | Status |
|---|---|---|---|
| LCH-01 | Mainnet deployment, indexer, account provider with the app identifiers | Phase 6 | todo |
| LCH-04 | Release on the App Store and Google Play | HRD-08, LCH-01 | todo |
| LCH-02 | Monitoring: failed transactions, vRNG availability, paymaster balance | LCH-01 | todo |
| LCH-03 | Incident runbook: reorg, vRNG outage, registry rollback | LCH-01 | todo |

---

## Design backlog

The design documents fix the rules and the direction. They do not yet define everything
an implementer needs. Each gap below is a design task, written by the orchestrator with
the owner, and **due before the phase that consumes it**.

| ID | Missing | Due before | Status |
|---|---|---|---|
| DES-18 | **Invisible chain**: first version in `docs/design/11-interface.md`; onboarding flow still to write with ADR-0005 | Phase 1 (CLI-01) | doing |
| DES-01 | **Interface** (`docs/design/11-interface.md`) | Phase 1 (CLI-03) | done (draft v0.1) |
| DES-02 | **Vision**: what the adventurer sees inside a room (whole room or a radius), what goblins perceive, how line of sight and sleep interact | Phase 1 (ENG-07) | done (`docs/design/18-rooms.md`) |
| DES-03 | **Map parameters**: room size, generator parameters per biome, room features (chests, traps, gathering nodes), gate placement | Phase 1 (ENG-05) | done (`docs/design/18-rooms.md`) |
| DES-04 | **Effect catalogue**: the closed list of skill effects and their exact resolution order; blocking, interrupts, area targeting, simultaneous deaths | Phase 2 (CBT-01) | done (2026-09-29, [#139](https://github.com/bal7hazar/grimworld/pull/139); design/19; D-155; [report](docs/reports/DES-04-effects.md)) |
| DES-05 | **Skill lists**: the 6 trainer skills per MVP profession (only the 6 starters exist) | Phase 2 (CNT-01) | todo |
| DES-06 | **Caste sheets**: health and armor per caste, skill list, priority list, boss phases. **D-157: a per-source bound for every statistic (signed where negative), a prerequisite of production snapshots (CBT-02, ENG-07)** | Phase 2 (CNT-01) | done (2026-09-29, [#179](https://github.com/bal7hazar/grimworld/pull/179); design/20; D-160; [report](docs/reports/DES-06-caste-sheets.md)) |
| DES-07 | **Curves**: experience per level, merit per quest, gold income and prices, attribute points per level | Phase 3 (GLD-01) | todo |
| DES-08 | **Onboarding**: adventurer creation, first ten minutes, skill quests one by one | Phase 3 (CNT-02) | todo |
| DES-09 | **Quest list** of Region 1 and the two promotion trials | Phase 3 (CNT-02) | todo |
| DES-10 | **Equipment**: weapons and armor by level, merchant stock | Phase 4 (RWD-05) | todo |
| DES-11 | **Alchemy content**: the 10 ingredients, the 12 potions with exact effects, loot tables | Phase 4 (CNT-03) | todo |
| DES-12 | **Hubs**: what a town and an outpost look like, services and their characters, presence display | Phase 5 (WLD-03) | todo |
| DES-13 | **Region 1 content**: level design of the zones (terrain, goblins by place and level, collectors), dungeon floors, spawn tables | Phase 5 (CNT-04) | todo |
| DES-14 | **Lore**: premise written (`docs/lore/00-premise.md`), awaiting the owner's reaction; then names (Q-11), Region 1's story, **audio** direction | Phase 5 (LORE-01) | doing |
| DES-17 | **Rifts** (`docs/design/17-rifts.md`): owner's ruling, then spawn rules and prices | Phase 5 (WLD-02) | doing |
| DES-16 | Sets of the first dungeon: fixed modifiers and the 3- and 5-piece bonuses for the three professions, within the budget rule | Phase 4 (RWD-08) | todo |
| DES-15 | **Ownership and economy**: tokens, transfers, registry governance, who funds the paymaster (Q-07, Q-08, Q-10), checked against store rules | Before Phase 4 | todo |
| DES-20 | **A goblin blocked by its own pack** (found by SPK-2): with one flood per tick on frozen occupancy, a goblin whose closer tiles are all taken sidesteps, and was seen leaving the window in 7 ticks. Proposed rule: it **holds its position** when no strictly closer tile is free, except the `flank` profile, which may sidestep | Phase 2 (CBT-06) | todo |
| DES-21 | **Played actions sent in batches** (D-133): what a batch is against a planned queue, its size, when it leaves, actions not yet sent, rewind; entrypoints that follow. In design/02 and design/11 | **Phase 0, before ENG-01** | done (2026-09-28, [#49](https://github.com/bal7hazar/grimworld/pull/49); open points OP-1, OP-2 carried into ENG-01; [report](docs/reports/DES-21-played-batches.md)) |
| DOC-01 | **The documents after DES-21** (D-133, D-136): the accepted amendments of ADR-0001, 0002, 0006, 0007, the glossary, design/07, 09, 18; OP-1 replaced by D-136's rule in design/02 | DES-21 | Sonnet 5.5 | — | done (2026-09-29, [#63](https://github.com/bal7hazar/grimworld/pull/63); [report](docs/reports/DOC-01-after-des-21.md)) |

## Milestones and gates

| # | Milestone | Gate / owner decision | Depends on |
|---|---|---|---|
| M0 | Project documented, decisions of round 2 taken, project-manager session running on the VPS — **reached 2026-09-28** | FND-00 | – |
| M1 | Stack validated by measurements (spikes), budgets written | Owner: keep mainnet and the web-view client, or fall back | M0 |
| M2 | Walking skeleton on Sepolia, played on a phone | – | M1 |
| M3 | Combat playable with three professions, parity at zero divergence | – | M2 |
| M4 | **Fun gate**: career loop playtested | Owner: go on, or rework combat | M3 |
| M5 | Full expedition loop with loot and alchemy | – | M4 |
| M6 | Region 1 complete; content added by data only | Owner: art commission | M5 |
| M7 | Audits closed, public playtest on Sepolia | Owner: mainnet go, paymaster budget | M6 |
| M8 | Mainnet and stores | Owner | M7 |

## Risk register

| # | Risk | Likelihood | Impact | Mitigation | Watched in |
|---|---|---|---|---|---|
| R-1 | Client and chain logic diverge | High | High | Parity lens on every mirrored task; generated vectors; rewind | Every phase |
| R-2 | A tick with 8 goblins exceeds the cost budget | Medium | High | SPK-2 before any design is frozen; lower the cap; bounded pathfinding | Phase 0, 2 |
| R-3 | Mainnet latency worse than claimed | Medium | Medium | SPK-1; queue hides it; fallback to option B | Phase 0 |
| R-4 | Deterministic combat feels flat | Medium | High | Facing, interrupts, telegraphs; fun gate at Phase 3 before building rewards | Phase 3 |
| R-5 | Dependency on Cartridge services; Controller may not be fit (owner's doubt) | High | High | Account provider interface, burners first, SPK-9; **fees and randomness are Cartridge services too and must be re-examined if Controller is dropped** | Phase 0, 7 |
| R-6 | Skill system scope explodes | High | Medium | Effects are a closed, registry-driven set; 12 skills per profession in MVP | Phase 2 |
| R-7 | Too derivative of inspirations (IP) | Low | High | IP check on LORE and ART; no reuse of names or assets | Phase 5 |
| R-9 | Phone heats or drains despite the power rules | Medium | High | SPK-6 on real phones before any client work; renderer is replaceable | Phase 0 |
| R-10 | An asset or a derived sprite gets committed by an agent | Medium | Medium | `.gitignore`; rule in `COMMON.md`; CI check refusing image files outside an allowlist | Every phase |
| R-11 | Store rejects the app (thin wrapper, on-chain content) | Medium | High | Bundle assets, behave as an app; HRD-08 early enough to react | Phase 5 |
| R-12 | Chunked maps exceed the cost budget (window assembly, chunk generation on reveal, flood) | Medium | High | Window assembled by masks and shifts, no loop; one shared flood per tick; a stored window measured as the alternative; fallback sight 5 on a window of 13 × 14; SPK-7 before ENG-05 | Phase 0 |
| R-16 | Generated zones feel the same | Medium | Medium | Biomes, bands, authored set pieces placed by quota; playtest at the fun gate | Phase 3 |
| R-17 | The MVP's randomness can be steered by anyone (transaction hash) | Certain | Low in the MVP, **blocking for version 1** | Nothing of value in the MVP; provider interface; deployment check; the hardening gate requires the verifiable provider | Phase 6 |
| R-15 | Seamless generation across chunks needs a capability the map library does not have | Medium | High | Track LIB, milestone L-M1; rooms-and-corridors generation as fallback for dungeons | Phase 0 |
| R-13 | The MVP grows beyond what a first release can carry (equipment loot, sets, trade, auction house added) | High | High | Phase 4 split in two gates; fun gate at Phase 3 stays before any of it is built | Phase 4 |
| R-14 | Gold and items traded for real money outside the game; bots farming | Medium | High | Fees as gold sinks, listing limits, account age; examined with Q-07 | Phase 4 |
| R-18 | The game waits for the library | Medium | High | L-M1 is scoped to the game's needs only; SPK-7 runs on `origami_hexmap` 1.8.0; rooms-and-corridors generation as fallback | Phase 0–1 |
| R-19 | ~~Dojo pins the game to an older Cairo than the owner's libraries~~ **Closed by ADR-0007** | — | — | — | — |
| R-20 | The indexer is ours to build, host and watch; a fault in it shows wrong markets and rankings | High | Medium | Not on the path of a move; rebuilt from the chain; SPK-11 before CLI-01; rewind on reorg | Phase 0–1, 7 |
| R-21 | Access control and upgrades are our code: a missing check is an exploit | Medium | High | Rules in ADR-0007; security lens and `[GPT-6-Astra]` on every lot touching it; external audit | Every phase |
| R-22 | A contract exceeds the class size limit as features are added | Medium | Medium | Boundaries planned at ENG-01; class size printed in CI | Phase 1–4 |
| R-23 | A third track (ARC) shares a budget of 3 agents with the game and the map library; the career loop waits for `quest` | Medium | Medium | `quest` only before Phase 3; analysis first; the owner may raise the budget | Phase 2–3 |
| R-8 | Solo-only launch closes the co-op door by accident | Medium | High | M-1…M-6 checked by the design lens on every task | Every phase |
