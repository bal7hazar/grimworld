# Context

Everything a session or an agent must know before touching Grim World. Nothing depends on
a previous session's memory. Reading order for a new orchestrator session: this file,
[OPERATIONS.md](OPERATIONS.md), [STATUS.md](STATUS.md), the `PENDING-*` files in
[docs/decisions/](docs/decisions/), then [PLAN.md](PLAN.md).

## 1. What Grim World is

A fully on-chain, tick-based heroic-fantasy RPG on Starknet. Adventurers of the Guild leave
shared towns to clear goblin-infested wilds in dedicated instances where the world only
moves when the player acts. Full vision: [docs/design/00-vision.md](docs/design/00-vision.md).

## 2. Pillars

1. The world waits for you.
2. Build over grind.
3. One enemy, many faces.
4. Fully on-chain, no asterisk.
5. Deterministic tactics, random rewards.
6. Content scales horizontally.

## 3. Project status

| | |
|---|---|
| Phase | **0 — Foundations**, started 2026-09-28: ideation reviewed three times by the owner, decisions of §6 accepted, project-manager session running on the VPS (FND-00) |
| Repository | Documents only; first code arrives with FND-03 (agent tooling) and SPK-5 (toolchain) |
| Next | Orchestrators created by the project manager ([docs/briefs/ORCH-game.md](docs/briefs/ORCH-game.md), [docs/briefs/ORCH-hexmap.md](docs/briefs/ORCH-hexmap.md)); live state in [STATUS.md](STATUS.md) |

## 4. Technical context

Stack, pending Phase 0 validation
([ADR-0001](docs/architecture/ADR-0001-execution-layer.md),
[ADR-0003](docs/architecture/ADR-0003-client.md)). Versions are pinned by spike
SPK-5, not here.

| Layer | Choice |
|---|---|
| Chain | Starknet mainnet (Sepolia for testing, a local node chosen by SPK-5b) |
| Contracts | **Native Starknet contracts** in Cairo 2.19, **without Dojo** ([ADR-0007](docs/architecture/ADR-0007-native-starknet.md)) |
| Indexer | Probably our own, from the contracts' events; scope by SPK-11. Not on the path of a move: the client reads its instance by view calls |
| Account | Behind an interface: **burner accounts first**, Cartridge Controller under evaluation, our own solution if needed ([ADR-0005](docs/architecture/ADR-0005-accounts.md)) |
| Fees | Always paid by the game |
| Randomness | Behind an interface. **MVP: transaction hash**, known to be steerable. Version 1: a verifiable source ([ADR-0002](docs/architecture/ADR-0002-randomness.md)) |
| Maps | [`origami_hexmap`](https://github.com/dojoengine/origami/tree/main/crates/hexmap) 1.8.0 (in `crates/hexmap`; `crates/map` is the older square-grid library), on Cairo 2.19 like the game since ADR-0007. Successor: `hexx-cairo` (D-119), consumed by published version |
| Client | TypeScript, starknet.js, PixiJS rendered on demand, Capacitor for iOS and Android. **Mobile first** |
| Art | Pixel art, 64 × 64 tiles, *Tiny Swords* pack by Pixel Frog as prototype ([design/10](docs/design/10-art-direction.md)) |

### Prior art by the owner

| Project | Reused | Not reused |
|---|---|---|
| [Grimscape](https://github.com/bal7hazar/grimscape) | Rooms as felt bitmaps, lazy room generation, Poseidon seed chain, queued actions in one transaction, layering (system → component → store → model → types → elements) | State keyed by adventurer; every goblin always chasing; unbounded dungeon; block timestamp as seed; square grid |
| [Arcade packages](https://github.com/cartridge-gg/arcade/tree/main/packages) | `quest`, `achievement`; later `leaderboard`, `social`: **rewritten without Dojo, in one repository of separate Scarb packages** (D-124, D-125, PLAN track ARC) | The Dojo packages as they are; platform packages (registry, provider, controller) |
| [origami_hexmap](https://github.com/dojoengine/origami/tree/main/crates/hexmap) | Generators, entrances, connectivity, shortest path, ranges | — (line of sight is missing and is ours to add) |
| [Athanor](https://github.com/djizus/athanor) | Crafter: discovery by sampling without replacement, lazy recipe assignment, hints, packed balances | One word for two draws; transaction-hash fallback; single global book |

### Contract architecture pattern

```
systems/      thin contracts: entrypoints, access control, nothing else
components/   game logic, reusable across systems
store         single access point to models
models/       state + invariants (asserts) per model
types/        enums dispatching to elements
elements/     one file per content behaviour (a skill effect, a caste profile)
helpers/      pure functions: bitmap, packer, seeder, math, crafter
registries    content as data (regions, locations, castes, skills, quests, loot, books)
```

Two domains, never mixed: **persistent** (adventurer, inventory, progress, registries) and
**ephemeral** (instance state). See ADR-0001, *Keeping the exit open*.

## 5. Glossary

Use these words, in code and in prose, with these meanings only.

| Term | Meaning |
|---|---|
| **Adventurer** | A player character. Persistent on-chain entity |
| **Hub** | A town or an outpost. Shared, no tick |
| **Location** | Any node of the world graph: hub, zone, dungeon, elite zone |
| **Instance** | One dedicated, private copy of a location, with its own state and clock. Closed when the adventurer leaves or is defeated; never saved |
| **Expedition** | Everything between leaving a hub and returning or being defeated. May span several instances |
| **Tick** | The unit of time in an instance |
| **Clock** | The time of an instance, in ticks |
| **Action** | One player input in an instance, with a tick cost |
| **Queue** | Several actions submitted in one transaction |
| **Chunk** | 15 × 15 tiles: the unit of storage and generation of a map |
| **Window** | The board of 15 columns × 16 rows on which a tick is computed. It follows the adventurer and is assembled from the chunks at each tick, never stored |
| **Sight** | The hexagon of radius 6 within which goblins are shown; always inside the window |
| **Facing / arc** | The direction an actor looks at; front, front-side, rear-side and back tiles around it |
| **Gate** | A link between two locations |
| **Caste** | A type of goblin |
| **Pack** | A group of goblins spawned and alerted together |
| **Awake** | A goblin that is simulated each tick |
| **Build** | Attributes + 8 skills + belt, locked during an expedition |
| **Remains** | What a dead goblin leaves; looting it rolls the drop |
| **Rift** | A dungeon that appears for a limited time, graded by the Guild. **Nest**: a permanent dungeon |
| **Stillstone** | The ore mined in Rifts: material and main income |
| **The Hush** | In the lore, why time moves only when the adventurer moves |
| **Guild** | The Adventurers' Guild: the institution that ranks adventurers and posts quests. Never a group of players |
| **Company** | A group of players (what the `social` package calls a guild). Post-MVP |
| **Contract** | A repeatable daily quest posted by the Guild |
| **Vault** | The account's storage, shared by its adventurers |
| **Estate** | The account's idle layer (post-MVP) |
| **Merit** | Points toward guild rank |
| **Trial** | The instance to pass to be promoted |
| **Book** | A closed set of ingredients and recipes for alchemy |
| **Signature** | The pair of rarities a recipe is brewed from |
| **Grimoire** | The recipes one adventurer has discovered |
| **Fate / Fog** | Unpredictable / derivable randomness (ADR-0002) |
| **Registry** | On-chain content data read by core systems |

## 6. Decision log

Status values: Proposed (by the orchestrator, awaiting the owner), Accepted (by the
owner, with the date), Superseded.

| ID | Decision | Where | Status |
|---|---|---|---|
| D-01 | The world advances only through adventurer actions; unit is the tick, no sub-tick | design/02 | Accepted 2026-09-28 (owner's requirement) |
| D-02 | One clock per instance; durations stored as deadlines; instances keyed by instance id | design/02 | Accepted 2026-09-28 (owner adopts the recommendation) |
| D-03 | Hubs have no on-chain geometry; presence is off-chain and cosmetic | design/02 | Accepted 2026-09-28 |
| D-04 | Defeat costs the instance only: experience, loot and quest progress are kept | design/02 | Accepted 2026-09-28 (owner adopts the recommendation) |
| D-05 | Instances are not saved: leaving closes the instance, re-entering creates a new one | design/02 | Accepted 2026-09-28 |
| D-10 | ~~Zones fixed, dungeons shifting~~ | — | Superseded by D-64: everything is generated |
| D-11 | Hexagonal maps, pointy-top, on `origami_hexmap` | design/02 | Accepted 2026-09-28 |
| D-20 | Ten ranks: Wood, Tin, Copper, Iron, Steel, Bronze, Silver, Gold, Platinum, Onyx; promotion needs merit and a trial quest in a dungeon | design/06 | Accepted 2026-09-28 |
| D-100 | **The chain is invisible**: the player never pays a fee, never sees a wallet, a signature, a transaction or a token. The business model covers network costs | design/00 | Accepted 2026-09-28 |
| D-30 | Six professions; Vanguard, Warden, Arcanist in the MVP | design/03 | Accepted 2026-09-28 (owner adopts the recommendation) |
| D-31 | GW1 numbers as baseline, 1 second = 1 tick | design/03 | Accepted 2026-09-28 (owner adopts the recommendation) |
| D-40 | Combat is fully deterministic | design/04 | Accepted 2026-09-28 |
| D-41 | Six facings, four arcs; critical from the back, flank from rear-sides | design/04 | Accepted 2026-09-28 (owner adopts the recommendation) |
| D-50 | Loot is rolled when remains are looted, not at death | design/07 | Accepted 2026-09-28 (owner adopts the recommendation) |
| D-51 | Alchemy discovery is per adventurer and per regional book | design/07 | Accepted 2026-09-28 |
| D-52 | Recipes have a rarity signature, identical for every adventurer | design/07 | Accepted 2026-09-28 (owner adopts the recommendation); kept only if its cost is negligible (SPK-2) |
| D-60 | Execute on Starknet mainnet; persistent and ephemeral domains split in code | ADR-0001 | Accepted 2026-09-28, subject to spikes |
| D-61 | Randomness behind an interface; transaction hash in the MVP, verifiable in version 1; reveal by entry draw plus player entropy | ADR-0002, ADR-0006 | Accepted 2026-09-28 |
| D-62 | Client: TypeScript, PixiJS on demand, Capacitor; mobile first | ADR-0003 | Accepted 2026-09-28, subject to SPK-6 |
| D-72 | The orchestrator merges on green CI and audits, and deploys to Sepolia autonomously | OPERATIONS §7 | Accepted 2026-09-28 |
| D-73 | No asset file, nor anything derived from one, is committed in this repository: the licence forbids redistribution. Assets live in the **private** repository `tiny-swords`, attached as the submodule `assets` | design/10 | Accepted 2026-09-28 |
| D-70 | Documents, briefs, commits and pull requests in English; chat with the owner in French | OPERATIONS §11 | Accepted (owner's convention) |
| D-113 | Chain of command: owner, project manager, orchestrators (created by the project manager), sub-agents and auditors | OPERATIONS §1 | Accepted 2026-09-28 |
| D-114 | Cairo engineering rules | docs/CAIRO.md | Accepted 2026-09-28 |
| D-71 | Sub-agent titles start with the model used, in brackets | OPERATIONS §1 | Accepted 2026-09-28 |
| D-32…D-46, D-90…D-94 | Round 3: creation, slots, vault, look is equipment, collectors, smiths, looted equipment and boss armor sets in the MVP, titles, trade and auction house, estate, cosmetics; companions withdrawn | [decisions/2026-09-28-owner-review-3](docs/decisions/2026-09-28-owner-review-3.md) | Accepted 2026-09-28 |
| D-63 | Quests on the `quest` package in storage mode, titles on `achievement` in event mode | ADR-0004 | Accepted 2026-09-28, **revised by D-124**: on the native rewrites of the packages, not on the Dojo ones |
| D-64 | Large maps cut in chunks, **generated at reveal from a fresh random word**, simulated in a window centred on the adventurer. Constraints as bands, quotas and anchors. Rule of sight provisional | ADR-0006 | Accepted 2026-09-28, costs subject to SPK-7 |
| D-115 | Promotion trials are generated like any dungeon; size, band and quotas are fixed per rank | design/06 | Accepted 2026-09-28 (owner adopts the recommendation) |
| D-116 | Every mainnet deployment and every mainnet registry write needs an explicit go from the owner | OPERATIONS §7 | Accepted 2026-09-28 (owner adopts the recommendation) |
| D-117 | Map library: the game consumes `origami_hexmap` 1.8.0 for now. What it consumes in the end depends on the findings of the library's orchestrator (PLAN, track LIB) | PLAN | Accepted 2026-09-28; **its first sentence proved false the same day** (N-9): the game cannot build 1.8.0 |
| D-119 | Map library: **`hexx` is ported in full** (feature parity wherever it makes sense on-chain, extended with what Cairo and the network require) in **`bal7hazar/hexx-cairo`**, which takes over the engine of `origami_hexmap` with identical results; `origami_hexmap` is decommissioned once the port is complete and the game has migrated. `u252` becomes its own crate in `bal7hazar/types-cairo` | [decisions/2026-09-28-L-G1-hexx-port](docs/decisions/2026-09-28-L-G1-hexx-port.md) | Accepted 2026-09-28 (owner, at gate L-G1; differs from the recommendation) |
| D-122 | N-9: the map library must build with the compiler Dojo imposes on the game (Cairo 2.13 today), `snforge_std` as a dev-dependency. LIB-03 studies the compiler floor and the alternative of a separate class; the owner decides at gate L-G2. SPK-7 runs standalone on Cairo 2.19 meanwhile | [decisions/2026-09-28-N-9-compiler-target](docs/decisions/2026-09-28-N-9-compiler-target.md) | Project manager's arbitration, 2026-09-28; compiler target left to the owner at L-G2 **Void since D-123**: the game is on Cairo 2.19 |
| D-123 | **The game is built as native Starknet contracts, without Dojo**: less gas in the path of an action, Cairo 2.19 for the game and its libraries. Probably an indexer of our own | [ADR-0007](docs/architecture/ADR-0007-native-starknet.md) | Accepted 2026-09-28 (owner); gain in gas to be measured by SPK-2 |
| D-124 | The Arcade packages are rewritten **without Dojo: pure Starknet components and pure Cairo**. The game consumes them by published version. `quest` first, then `achievement` | [ADR-0007](docs/architecture/ADR-0007-native-starknet.md) § Arcade packages; PLAN, track ARC | Accepted 2026-09-28 (owner); "one repository each" revised by D-125 |
| D-125 | **One repository, one name** related to video games, holding the packages as separate Scarb packages; CI runs only the packages a change concerns. In time, the home of the owner's other `*-cairo` repositories, moved one by one on the owner's decision | PLAN, track ARC | Accepted 2026-09-28 (owner); name: **`quiver`** (`bal7hazar/quiver`) |
| D-126 | The porting plan of `hexx` is accepted (gate L-G2): package named `hexx`; a mirror of a Rust crate keeps the crate's name, packages of our own take the prefix of their repository; the tick (assembly, flood) is measured first; nothing is published without the owner's go | [decisions/2026-09-28-L-G2-porting-plan](docs/decisions/2026-09-28-L-G2-porting-plan.md) | Accepted 2026-09-28 (owner) |
| D-127 | The flood of the tick stops at 15 layers; a goblin it did not reach holds its position and still acts if it can | design/02, design/04, ADR-0006 §4 | Accepted 2026-09-28 (owner); number tuned by SPK-7 and playtest |
| D-128 | **The project manager goes ahead with its own recommendations** and reports afterwards. Stay the owner's act: mainnet, what cannot be undone outside the repositories (publishing, store submission), money, accounts and secrets | OPERATIONS §10 | Accepted 2026-09-28 (owner) |
| D-129 | The threshold of $0.50 for 300 actions stays the target; the cost is measured on Sepolia before anything is decided (SPK-1 brought forward); ENG-01 carries a cost budget. Native contracts measured at 0.26× to 0.58× the cost of Dojo | [decisions/2026-09-28-cost-threshold](docs/decisions/2026-09-28-cost-threshold.md) | Project manager, 2026-09-28, under D-128 |
| D-120 | **The simulation window follows the adventurer**: no margin of 3 tiles, no cut of sight at the ring. Window of **15 columns × 16 rows**, origin on an even row, **not stored**, assembled at each tick without a loop over rows. Fallback: sight 5 on 13 × 14. Chunks stay 15 × 15 | ADR-0006 §4, [decisions/2026-09-28-window-follows](docs/decisions/2026-09-28-window-follows.md) | Accepted 2026-09-28 (owner), cost subject to SPK-7 |
| D-121 | `main` is not protected on GitHub for now, on either repository: freedom during the kick-start. The residual of finding F4 (FND-03 audit) is accepted; raised again at the gate of Phase 0 | [decisions/2026-09-28-G-1-main-protection](docs/decisions/2026-09-28-G-1-main-protection.md) | Accepted 2026-09-28 (owner; differs from the recommendation) |
| D-118 | Concurrency: 3 Grim World agents at a time on the VPS, beside the other programmes | OPERATIONS §3 | Accepted 2026-09-28 (owner adopts the recommendation) |
| D-80 | Co-op direction: every action of any member ticks the world | design/08 | Accepted 2026-09-28 (owner adopts the recommendation) |

## 7. Open questions

| ID | Question | Needed by | Recommendation |
|---|---|---|---|
| Q-02 | Co-op: does "every action ticks" need a party-size modifier on spawns? | After Phase 3 | Decide by simulation |
| Q-03 | Is "defeat costs the instance only" the right severity, or is it now too soft? | Phase 1 | Yes; tune by playtest |
| Q-05 | Equipment: merchant-only, or drops and upgrades later? | Post-MVP | Merchant-only in MVP |
| Q-07 | Are items, potions, gold transferable or tokenised? Are adventurers NFTs? | Before Phase 4 | Adventurer as NFT; items non-transferable in MVP |
| Q-08 | Who can write registries: admin key, multisig, governance? | Phase 1 | Multisig, with a timelock before mainnet |
| Q-09 | Presence and chat in hubs: which transport? | Phase 5 | A small relay beside the indexer |
| Q-10 | Business model and who funds the paymaster | Before mainnet | — (owner) |
| Q-11 | Names: world, regions, professions, skills | `LORE` track | Working names stand until then |
| Q-12 | The asset pack has no caster sprite. Keep the Arcanist in the MVP (needs one commissioned sprite) or replace it by the Cleric (Monk sprite exists)? | Phase 2 | Keep the Arcanist if a sprite can be commissioned; else Cleric |
| ~~Q-22~~ | ~~Extract the Arcade packages into dedicated, published repositories~~ | — | **Closed by D-124**: rewritten natively, in one repository (D-125) |

## 8. Constraints that are easy to forget

- **Intellectual property.** Guild Wars and Goblin Slayer are inspirations for systems and
  tone. No name, text, icon, character or map from either may be reused. Numbers and
  mechanics may serve as a baseline.
- **Multiplayer door.** Constraints M-1…M-6 in
  [docs/design/08-multiplayer.md](docs/design/08-multiplayer.md) apply to every task.
- **No block data in instances.** No rule inside an instance reads block number,
  timestamp or transaction hash.
- **Bounded execution.** Every loop in a contract has a bound stated in the design.
- **Invisible chain.** No fee is ever charged to the player and no blockchain vocabulary
  reaches the interface (D-100). Abuse is limited by game rules (daily caps), never by
  making the player pay.
- **Provisional providers.** The MVP runs on burner accounts and transaction-hash
  randomness. Neither may reach mainnet; the MVP holds nothing of value.
- **Cairo rules.** Test-driven with a gas budget on every test; execution cost before
  deployment cost; arithmetic, then bitwise, then loops; no `u256`, `u252` from
  `origami_hexmap` ([docs/CAIRO.md](docs/CAIRO.md)).
- **Two domains.** Persistent and ephemeral state never share a model (ADR-0001).
- **Power budget.** The client has no permanent render loop (ADR-0003).
- **Assets.** They live in the private repository `tiny-swords`, attached as the
  submodule `assets`; this repository holds a pointer, never a file. That repository must
  stay private. No asset and nothing derived from one is committed here: the licence
  forbids redistribution, even modified (D-73). Asset names referring to the manga must
  not reach the game or the repository.
- **Reorgs.** Starknet had two multi-hour outages with reorgs in 13 months. The client
  treats the chain as authoritative and can rewind.

## 9. People, accounts, machines

| who / what | detail |
|---|---|
| Owner | bal7hazar (GitHub `bal7hazar`, git author `bal7hazar@proton.me`). Speaks French. Decides on vision, scope, design decisions, releases, mainnet |
| Ideation session (this) | Claude Desktop (Code tab), account bal7hazar, model Fable 5.1, on the owner's Mac, repository `~/git/grimworld`. Documents only |
| Project-manager session (implementation) | **A new session on the VPS**, account bal7hazar, started from [docs/briefs/PM-vps-bootstrap.md](docs/briefs/PM-vps-bootstrap.md) |
| Orchestrator sessions | Created in the Claude App by the project manager; Opus 5.5 or Fable 5.1 by its judgement |
| Sub-agents | `claude` CLI logged in as **claude-b7r** (check with `claude auth status`): Sonnet 5, Opus 5.5 or Fable 5.1 by difficulty. `codex` CLI (`gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna` by kind of task): audits when needed, never implementation |
| Credentials | Sepolia deployment credentials are in the session's settings environment. Never copy them into a document, a brief or a log |
| Assets | *Tiny Swords* by Pixel Frog and derived sprites, in the private repository `bal7hazar/tiny-swords`, submodule `assets`. After cloning: `git submodule update --init` |
| Libraries by the owner | `origami_hexmap` (dojoengine/origami, may move to a dedicated repository) |

## 10. Known gaps in these documents

- The VPS procedures in OPERATIONS §3 are taken from the owner's other programmes and
  have not been checked on the machine for this project; the bootstrap task does it.
- Latency and cost figures in ADR-0001 come from public data and RPC reads, not from our
  own transactions.
- Balance numbers are initial values and have not been simulated.
- Battery, store policy and engine market-share statements in ADR-0003 are from general
  knowledge, not from sources checked for this project.
- `origami_hexmap` figures are the library's own benchmarks; its tests were not run by us.
