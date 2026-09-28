# Plan

Status: **v0.7, 2026-09-28** (v0.7: lore, Rifts (three open, five a day), invisible chain, accounts behind an interface with burners first, interface and rooms designed; v0.6: owner's third review: looted equipment, boss armor sets, trade and auction house enter the MVP; companions considered and dropped; v0.5: mobile first with responsive desktop; design backlog added; v0.4: owner's second review: PixiJS accepted, implementation on the VPS, asset licence forbids redistribution, Sepolia autonomous; v0.1: first plan; v0.2: owner's first review: mainnet accepted, hex maps, mobile first, defeat softened, instances not saved; v0.3: aligned on the owner's operating conventions: CLI sub-agents, codex audits, launcher, status file).

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
| **0 Foundations** | Stack validated, repo ready | ADR-0001, 0002 and 0003 confirmed on measurements; CI green on an empty world |
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
| IDE-07 | Owner rules on what remains open in `docs/decisions/2026-09-28-owner-review-2.md` (not blocking Phase 0) | Owner | todo |
| IDE-08 | Commit and push the documents to `main` | Orchestrator, on the owner's request | todo |
| IDE-04 | Realign OPERATIONS, PLAN, STATUS and decisions on the owner's examples | Orchestrator | done |
| IDE-06 | Write the VPS bootstrap prompt | Orchestrator | done |
| IDE-05 | Remove `example/` | Owner | todo (the folder is in the main checkout, untracked) |

## Phase 0 — Foundations

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| FND-00 | **Bootstrap the project-manager session on the VPS** from `docs/briefs/PM-vps-bootstrap.md`: checks accounts, toolchain, repository, credentials presence; reports to the owner | IDE-03 | Owner starts it | — | todo |
| SPK-5 | Pin toolchain (Dojo, Cairo, Scarb, Katana, Torii, dojo.js, Controller); reproducible build | — | Sonnet 5 | Q | todo |
| FND-01 | Repository scaffold: `contracts/`, `client/`, `docs/`, scripts, layering of CONTEXT §4 | SPK-5 | Sonnet 5 | Q | todo |
| FND-02 | CI: build, format, lint, tests for contracts and client | FND-01 | Sonnet 5 | S Q | todo |
| FND-03 | Agent tooling: `scripts/agent.sh` launcher ported from the owner's other repositories (profiles research / implement / audit, detached units, logs, resume), `docs/briefs/COMMON.md`, build lock, concurrency budget measured | FND-00 | Orchestrator | S | todo |
| SPK-1 | Latency spike: submission → pre-confirmed → accepted, via Controller session | SPK-5 | Opus 5.5 | — | todo |
| SPK-2 | Cost spike: worst-case tick and 10-move queue on a throwaway contract; **cost of an active player per day** (10 Rifts, quests, hub actions), fully sponsored | SPK-5 | Opus 5.5 | C | todo |
| SPK-3 | vRNG spike: overhead, latency, provider-down behaviour | SPK-5 | Opus 5.5 | S | todo |
| SPK-4 | Parity spike, two options measured: (a) TypeScript mirror checked by Cairo-generated vectors; (b) **the Cairo code itself run in the client** through a Cairo VM in WebAssembly, as in the owner's physics game. Needs the game logic as a pure library (state in, state out) | SPK-5 | Opus 5.5 | P | todo |
| SPK-6 | Client spike on real phones: PixiJS on demand in Capacitor; battery, heat, Controller session, vRNG (ADR-0003 thresholds); room size for portrait | SPK-5 | Opus 5.5 | — | todo |
| SPK-9 | Accounts spike (ADR-0005): does Controller work on Sepolia from the app shell with sessions, sponsored fees and vRNG; what a burner can use instead | SPK-5 | Opus 5.5 | S | todo |
| SPK-8 | Arcade packages spike: `quest` in storage mode and `achievement` in event mode on a throwaway world; progress keyed by adventurer id; what Controller displays; tests for the edge cases listed in ADR-0004 | SPK-5 | Opus 5.5 | D S | todo |
| SPK-7 | Hexmap spike: room generation chain and shared flood for 8 goblins, measured; line-of-sight prototype | SPK-5 | Opus 5.5 | C P | todo |
| ART-00 | Asset pipeline outside git: pack copied to the VPS by the owner, atlas packing script, clean-up of generated goblin sheets into transparent sprites, renaming after our castes, credit to Pixel Frog | FND-00 | Sonnet 5 | IP check | todo |
| FND-04 | Write spike results into the ADRs; set budgets (actions per queue, cost per expedition, power) | SPK-1…7 | Orchestrator | D | todo |

**Exit criteria**: ADRs accepted or option B re-opened; budgets written in design/02;
`main` builds from a clean machine.

## Phase 1 — Walking skeleton

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| ENG-01 | Freeze core interfaces: persistent and ephemeral domains, snapshot and results interface, models, registry shapes, events | FND-04 | Orchestrator + Opus | D S | todo |
| ENG-02 | Helpers: packer, seeder, fixed-point table; hex line of sight and arcs on top of `origami_hexmap` | ENG-01 | Opus 5.5 | P C Q | todo |
| ENG-03 | Registries: region, location, gate + seed data for a test region | ENG-01 | Opus 5.5 | D S Q | todo |
| ENG-04 | Adventurer creation and ownership | ENG-01 | Opus 5.5 | D S Q | todo |
| ENG-05 | Room generation with `origami_hexmap` (biome generator, entrances, single component, placement), fixed and shifting seeds | ENG-02 | Opus 5.5 | D P C Q | todo |
| ENG-06 | Instance lifecycle: enter with snapshot, resume, return, close; instance seed (Fate) | ENG-03, ENG-04 | Opus 5.5 | D S C Q | todo |
| ENG-07 | Movement, facing, room transition, action queue with stop conditions, instance clock | ENG-05, ENG-06 | Opus 5.5 | D S P C Q | todo |
| CLI-01 | Client shell in Capacitor: account provider interface with a **burner** implementation, Torii subscription | FND-01, SPK-6 | Opus 5.5 | S Q | todo |
| CLI-02 | Client simulation core mirroring ENG-05/07 + parity harness | ENG-02, SPK-4 | Opus 5.5 | P Q | todo |
| CLI-03 | Hex room rendering on demand, touch input, facing display, optimistic state with rewind | CLI-01, CLI-02, SPK-6 | Opus 5.5 | D Q + power rules | todo |
| OPS-01 | Deployment scripts: Katana local, Sepolia; Torii | ENG-07 | Sonnet 5 | S Q | todo |

**Exit criteria**: gate of the overview, demonstrated on Sepolia; constraints M-1…M-6
verified by the cross-cutting audit.

## Phase 2 — Combat

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| CBT-01 | Freeze combat interfaces: actor stats, skill and effect schema, caste schema | Phase 1 | Orchestrator + Opus | D | todo |
| CBT-02 | World tick pipeline (5 steps), regeneration, durations, recharges | CBT-01 | Opus 5.5 | D P C Q | todo |
| CBT-03 | Weapon attacks, damage formula, armor, arcs, flank and critical | CBT-02 | Opus 5.5 | D S P C Q | todo |
| CBT-04 | Conditions (MVP five) | CBT-02 | Opus 5.5 | D P Q | todo |
| CBT-05 | Skill engine: costs, activation, interrupt, effects; skill registry | CBT-02 | Opus 5.5 | D S P C Q | todo |
| CBT-06 | Goblin spawn from pack registry; state machine; shared flood pathfinding | CBT-02 | Opus 5.5 | D P C Q | todo |
| CBT-07 | AI profiles: swarm, kite, support, brute | CBT-06 | Opus 5.5 | D P C Q | todo |
| CBT-08 | Attributes, build lock, skill bar | CBT-05 | Opus 5.5 | D S Q | todo |
| CNT-01 | Seed data: 3 professions × 6 starter skills, 5 castes, MVP packs | CBT-05, CBT-07 | Sonnet 5 | D V | todo |
| CLI-04 | Client simulation of combat + parity vectors | CBT-03…07 | Opus 5.5 | P Q | todo |
| CLI-05 | Combat UI: skill bar, targeting, telegraphs, conditions, combat log | CLI-04 | Opus 5.5 | D Q | todo |
| BAL-01 | Headless balance simulator: run builds against packs, report win rate and ticks | CLI-04 | Opus 5.5 | Q | todo |

Parallel tracks after CBT-02: {CBT-03, CBT-04}, {CBT-05, CBT-08}, {CBT-06, CBT-07}.

## Phase 3 — Career

| ID | Task | Depends on | Executor | Audits | Status |
|---|---|---|---|---|---|
| GLD-01 | XP, level, attribute points | Phase 2 | Opus 5.5 | D S Q | todo |
| GLD-02 | Quest registry, board, accept / progress / claim | Phase 2 | Opus 5.5 | D S C Q | todo |
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
| RWD-05 | Merchants, smiths, armorers, collectors | RWD-01 | Opus 5.5 | D S Q | todo |
| RWD-06 | Equipment items as entities: base, requirement, rarity, modifier slots, armor pieces and weighted rating, snapshot into the instance | RWD-01 | Opus 5.5 | D S P C Q | todo |
| RWD-07 | Looted equipment: drop (Fate), identification (Fate), salvage (Fate), setting modifiers, insignias and runes | RWD-06, RWD-02 | Opus 5.5 | D S C Q + codex | todo |
| RWD-08 | Boss items and boss armor sets with 3- and 5-piece bonuses | RWD-06 | Opus 5.5 | D S P Q | todo |
| RWD-09 | Trade: direct exchange between players | RWD-06 | Opus 5.5 | D S Q + codex | todo |
| RWD-10 | Auction house: listings in lots, fees, expiry, purchase | RWD-09 | Opus 5.5 | D S C Q + codex | todo |
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
| HRD-01 | Cross-cutting security audit of all systems | Phase 5 | Opus 5.5 + codex | S | todo |
| HRD-02 | Cost pass: worst cases per entrypoint against budgets | Phase 5 | Opus 5.5 | C | todo |
| HRD-03 | Registry permissions, multisig, upgrade policy (Q-08) | Phase 5 | Opus 5.5 | S | todo |
| HRD-04 | Balance pass with BAL-01 and playtest data | PLY-01 | Orchestrator | D | todo |
| HRD-05 | Public playtest on Sepolia | HRD-01…04 | Orchestrator | — | todo |
| HRD-06 | External audit | HRD-01 | External | S | todo |
| HRD-07 | Paymaster budget and policies for mainnet (Q-10) | HRD-02 | Owner + Orchestrator | S | todo |
| HRD-08 | Store readiness: policy check for on-chain games on both stores, bundled assets, review submission | Phase 5 | Orchestrator | — | todo |

## Phase 7 — Launch

| ID | Task | Depends on | Status |
|---|---|---|---|
| LCH-01 | Mainnet deployment, Torii, Controller preset with the app identifiers | Phase 6 | todo |
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
| DES-04 | **Effect catalogue**: the closed list of skill effects and their exact resolution order; blocking, interrupts, area targeting, simultaneous deaths | Phase 2 (CBT-01) | todo |
| DES-05 | **Skill lists**: the 6 trainer skills per MVP profession (only the 6 starters exist) | Phase 2 (CNT-01) | todo |
| DES-06 | **Caste sheets**: health and armor per caste, skill list, priority list, boss phases | Phase 2 (CNT-01) | todo |
| DES-07 | **Curves**: experience per level, merit per quest, gold income and prices, attribute points per level | Phase 3 (GLD-01) | todo |
| DES-08 | **Onboarding**: adventurer creation, first ten minutes, skill quests one by one | Phase 3 (CNT-02) | todo |
| DES-09 | **Quest list** of Region 1 and the two promotion trials | Phase 3 (CNT-02) | todo |
| DES-10 | **Equipment**: weapons and armor by level, merchant stock | Phase 4 (RWD-05) | todo |
| DES-11 | **Alchemy content**: the 10 ingredients, the 12 potions with exact effects, loot tables | Phase 4 (CNT-03) | todo |
| DES-12 | **Hubs**: what a town and an outpost look like, services and their characters, presence display | Phase 5 (WLD-03) | todo |
| DES-13 | **Region 1 content**: zones, dungeon floors, spawn tables | Phase 5 (CNT-04) | todo |
| DES-14 | **Lore**: premise written (`docs/lore/00-premise.md`), awaiting the owner's reaction; then names (Q-11), Region 1's story, **audio** direction | Phase 5 (LORE-01) | doing |
| DES-17 | **Rifts** (`docs/design/17-rifts.md`): owner's ruling, then spawn rules and prices | Phase 5 (WLD-02) | doing |
| DES-16 | Sets of the first dungeon: fixed modifiers and the 3- and 5-piece bonuses for the three professions, within the budget rule | Phase 4 (RWD-08) | todo |
| DES-15 | **Ownership and economy**: tokens, transfers, registry governance, who funds the paymaster (Q-07, Q-08, Q-10), checked against store rules | Before Phase 4 | todo |

## Milestones and gates

| # | Milestone | Gate / owner decision | Depends on |
|---|---|---|---|
| M0 | Project documented, decisions of round 2 taken, project-manager session running on the VPS | FND-00 | – |
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
| R-12 | Eight goblins pathfinding exceeds the budget on hex rooms | Medium | High | One shared flood per tick; SPK-7 | Phase 0 |
| R-13 | The MVP grows beyond what a first release can carry (equipment loot, sets, trade, auction house added) | High | High | Phase 4 split in two gates; fun gate at Phase 3 stays before any of it is built | Phase 4 |
| R-14 | Gold and items traded for real money outside the game; bots farming | Medium | High | Fees as gold sinks, listing limits, account age; examined with Q-07 | Phase 4 |
| R-8 | Solo-only launch closes the co-op door by accident | Medium | High | M-1…M-6 checked by the design lens on every task | Every phase |
