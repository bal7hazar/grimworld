# ADR-0007 — Native Starknet contracts, without Dojo

| | |
|---|---|
| Status | **Decided by the owner on 2026-09-28** (D-123). The gain in gas is to be measured (SPK-2); the indexer is to be specified (SPK-11) |
| Date | 2026-09-28 |
| Decides | What the contracts are built on, and what replaces what Dojo brought |
| Supersedes | The Dojo parts of ADR-0001 (decision paragraph), ADR-0003 (chain access, indexer), ADR-0004 (use of the Arcade packages as they are), the pins of SPK-5, and D-122 (N-9) |

## Context

| | |
|---|---|
| Gas | Every action of the game is a transaction the game pays (pillar 7). Dojo puts a layer between a system and its state: the world contract, model schemas, permissions checked at each write, events emitted for every model write. The owner wants that cost out of the tick |
| Compiler | Dojo 1.8's tools (`sozo migrate`, `dojo_snf_test`) pin the game to Cairo 2.13. The owner's libraries, the map library first, target Cairo 2.19 and use what it gives (`BoundedInt`). The game could not build its own map library (N-9) |
| Releases | Dojo's newest Cairo package dates from October 2025; Katana 1.8 is still a release candidate (SPK-5) |

## Decision

**The game is a set of plain Starknet contracts written in Cairo. No Dojo world, no `sozo`,
no Torii, no dojo.js.**

| Layer | Before | Now |
|---|---|---|
| Contracts | Dojo world, models, systems | Starknet contracts and components (`#[starknet::contract]`, `#[starknet::component]`) |
| State | Dojo models, written through the world | Contract storage, packed explicitly (docs/CAIRO.md §4, §5) |
| Compiler | Cairo 2.13 (Scarb 2.13.1, snforge 0.51.2) | **Cairo 2.19** (Scarb 2.19.4, snforge 0.61), the toolchain of the owner's libraries; exact pins by SPK-5b. **Moved to Cairo 2.20 (Scarb 2.20.1, snforge 0.64.0) by FND-11, D-180** |
| Permissions | Dojo's owners and writers | Ours: who may call what, written and audited (§ Access control) |
| Deployment | `sozo migrate` | Declare and deploy scripts of our own (OPS-01) |
| Local network | Katana, through sozo | A local Starknet node that accepts the classes of Cairo 2.19: chosen by SPK-5b |
| Indexer | Torii | **Probably an indexer of our own**; scope and candidates by SPK-11 |
| Client access | dojo.js | starknet.js, and the indexer's interface |
| Quests, titles | The Arcade packages, which are Dojo packages | Written in the game, modelled on them (§ Arcade packages) |

What does not change: Starknet mainnet as the execution layer (ADR-0001, option A), the
randomness and account providers behind their interfaces (ADR-0002, ADR-0005: neither
needs Dojo), the client technology (ADR-0003: TypeScript, PixiJS, Capacitor), the chunked
maps (ADR-0006), and every rule of the design documents.

### The layering is kept

The pattern of CONTEXT §4 came from Grimscape, not from Dojo, and stays:

```
systems/      contracts: entrypoints, access control, nothing else
components/   game logic, reusable across contracts (Starknet components)
store         single access point to storage
models/       storage structs: layout, packing, invariants (asserts)
types/        enums dispatching to elements
elements/     one file per content behaviour
helpers/      pure functions
registries    content as data, in storage
```

| Rule | |
|---|---|
| Two domains, never mixed | **Two contracts at least**: persistent and ephemeral. No storage struct mixes fields of both |
| The narrow interface | The ephemeral contract writes to the persistent one through one dispatcher call carrying the list of results (ADR-0001, *Keeping the exit open*) |
| Pure logic | The rules of a tick are a library without storage (state in, state out), so that the client can mirror or run it (SPK-4) and tests need no deployment |
| Class size | A contract has a maximum size. Splitting by domain and by feature is planned from ENG-01, not discovered later |

### Access control

Dojo gave permissions for free; they are now ours, and security-critical.

| | |
|---|---|
| Player entrypoints | The caller must own the adventurer (or the account-level object) it acts on |
| Contract to contract | The persistent contract accepts results only from the ephemeral contract registered for it |
| Registries | Written by an administrator role; who holds it is Q-08 |
| Upgrades | By class replacement, by the same role; policy with Q-08 |
| Audit | Security lens and `[GPT-6-Astra]` on every lot that touches it (OPERATIONS §2: access control and ownership, always) |

### Events are an interface

Without Torii nothing reads storage for the client. **What the indexer and the client need
is emitted as events, designed and frozen like an API** (ENG-01), and kept small: an event
costs gas on every action.

| Read by | How |
|---|---|
| The player's own instance (window, goblins, adventurer) | **View calls** on the contracts, and the client's own simulation. No indexer needed to play |
| What spans players or history: market listings and cheapest lot, hub presence counts, rankings, titles of others | The indexer, from events |

This keeps the indexer out of the path of a move, and bounds what it must do.

**The indexer is never a source of simulation state** (D-133). The client simulates only over
a copy of the instance read from the chain by view calls, pinned to one block; recovery after
an unknown outcome uses only the account's nonce and a snapshot at one block, and keeps only
the actions whose results are unchanged (design/02, *The client's copy of the instance*). The
indexer serves display, and may serve as an optional early signal of a reorg.

### Indexer

| | |
|---|---|
| **Our own** (D-130) | Torii indexes Dojo worlds; no generic indexer fits without several services or without reorg handling (SPK-11). One process, tables versioned by block |
| What it is | A service that follows the chain, decodes our events, keeps tables, serves queries and subscriptions to the client, and **rewinds on a reorg** (CONTEXT §8) |
| Consequence | One more thing to build, host and watch. ADR-0001 counted "no infrastructure to operate beyond Torii": it is now "beyond our indexer" |
| Spike | SPK-11: scope (what needs indexing at all), candidates (existing generic indexers against our own), reorg handling, hosting, cost |
| Pillar 4 | Unchanged: the indexer holds nothing that cannot be rebuilt from the chain |

### Arcade packages

`quest`, `achievement`, `leaderboard` and `social` are written for Dojo worlds (ADR-0004).
They cannot be used as they are.

| | |
|---|---|
| **Decision (owner, 2026-09-28, D-124, D-125)** | **The packages are rewritten without Dojo: pure Starknet components and pure Cairo**, in **one repository** with a name of its own, as separate Scarb packages; its CI runs only the packages a change concerns. The game consumes them by published version, like the map library. In time that repository gathers the owner's other `*-cairo` libraries |
| D-63 | Revised: quests on the native `quest` package in storage mode, titles on the native `achievement` package in event mode. The rule of ADR-0004 stands: storage when a game rule depends on the data, events when it is only shown |
| What "pure" means | The logic (tasks with a target count, intervals, prerequisites, completion, claim) is a Cairo library without storage; a Starknet component wraps it with storage, events and hooks. No world, no model, no dependency on Dojo |
| SPK-8 | Dropped as written. The edge cases of ADR-0004 (points 3, 4 and 5) become test cases of the new packages |
| Lost | Quests and achievements shown in Controller's profile without interface work. Our own screens were already planned (design/11) |
| Track | **ARC** in PLAN: `quest` first (the career loop, Phase 3), then `achievement`; `leaderboard` and `social` after the MVP |

## What is lost, and what it costs

| Lost | Replaced by | Cost |
|---|---|---|
| `sozo build / migrate`, manifests | Scarb, and deployment scripts | OPS-01, larger |
| Torii | Indexer | SPK-11, then a track of its own |
| dojo.js, generated bindings | starknet.js and typed bindings generated from the contracts' interfaces | CLI-01 |
| Model introspection | Documented storage layouts | ENG-01 |
| World permissions | Our access control | Audited code |
| `spawn_test_world` | snforge deployment helpers | FND-01b |

## What is gained

| | |
|---|---|
| Gas | To be measured, not assumed: SPK-2 measures the same worst cases on Dojo 1.8 (its baseline, already running) and natively, and reports the difference per action |
| Compiler | Cairo 2.19 for the game and its libraries: N-9 disappears. The map library keeps one target |
| Freedom | Storage layout, packing, events and class boundaries are chosen for cost |

## Measured (Phase 0, gathered by FND-04 on 2026-09-29)

Figures and their sources only; no decision is changed.

| Question | Measured | Source |
|---|---|---|
| **Native against Dojo**, like for like, one node and one account (local node) | The worst tick as a transaction: **5.16M** native against **18.94M** on Dojo 1.8 (0.27×). Every action measured: native is **0.26× to 0.58×** Dojo | SPK-2 §8, §9; D-129 |
| The meter on Sepolia | Sierra gas: the game's calls come within 2 % to 18 % of snforge's Sierra-gas figures | SPK-1 §3 |
| **The fixed part of a transaction** | 717,435 L2 gas with the MVP's burner sending directly: validation 87,805, the account's execution 141,670, the STRK fee transfer 455,360, a residual 32,600. The fee transfer does not depend on the account | SPK-1b §1 |
| What native storage costs per transaction | A new slot (its value was 0) **453,524** L2 gas; an overwritten or zeroed slot **32,072** (both fitted under a chosen normalisation of the per-transaction constant: 452,808 to 453,691 and 24,878 to 33,751 under every admissible one); a felt of calldata 5,120; an event nothing beyond its call | FND-04 §3, §4, §4.1 |
| The floor of a burner transaction, before the game computes | 816,939 L2 gas (D, under the same normalisation; 806,297 to 862,551 under every admissible one) | [cost-budget.md](cost-budget.md) §1 |
| NS-1, the local node | starknet-devnet accepts the classes of Cairo 2.19; it meters VM resources, not Sierra gas, and reports state diffs in its traces | SPK-5b; SPK-2 §8.2; FND-04 §5 |
| The indexer | Our own (D-130): the nine events and two views the MVP's indexer needs | SPK-11 |

## Consequences elsewhere

| Document or task | Change |
|---|---|
| CONTEXT §4 | Stack table |
| PLAN | SPK-5b, FND-01b, FND-02, SPK-2, SPK-8 dropped, SPK-11 new, ENG-01, CLI-01, OPS-01, LCH-01, track LIB, risks |
| D-122, N-9 | Void: the library builds on Cairo 2.19, the game's compiler. The defect of `snforge_std` declared as a regular dependency stays to fix in the library |
| SPK-7 | Runs inside the game's workspace, no longer apart |
| ADR-0001, ADR-0003, ADR-0004 | A note at the top of each |
| docs/CAIRO.md | Unchanged: its rules never depended on Dojo |

## Open

| # | Question |
|---|---|
| NS-1 | Local node: which one accepts the classes of Cairo 2.19 today (SPK-5b) |
| ~~NS-2~~ | **Closed (D-130)**: our own indexer, one process, versioned tables, rewind on reorg ([decision](../decisions/2026-09-28-indexer.md)) |
| NS-3 | Number and boundaries of contracts, against the class size limit (ENG-01) |
| NS-4 | Upgrade policy and who holds the administrator role (Q-08) |
