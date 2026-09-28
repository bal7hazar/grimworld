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
| Phase | Ideation consolidated and reviewed once by the owner (2026-09-28); implementation not started |
| Repository | Documents only |
| Next | Owner rules on the remaining proposed decisions (§6) and questions (§7), then Phase 0 of [PLAN.md](PLAN.md) |

## 4. Technical context

Stack, pending Phase 0 validation
([ADR-0001](docs/architecture/ADR-0001-execution-layer.md),
[ADR-0003](docs/architecture/ADR-0003-client.md)). Versions are pinned by spike
SPK-5, not here.

| Layer | Choice |
|---|---|
| Chain | Starknet mainnet (Sepolia for testing, Katana locally) |
| Contracts | Cairo, Dojo |
| Indexer | Torii |
| Account | Cartridge Controller, session policies, paymaster |
| Randomness | Cartridge vRNG ([ADR-0002](docs/architecture/ADR-0002-randomness.md)) |
| Maps | [`origami_hexmap`](https://github.com/dojoengine/origami/tree/main/crates/hexmap) 1.8.0 (pointy-top hexes, one felt per room) |
| Client | TypeScript, dojo.js, PixiJS rendered on demand, Capacitor for iOS and Android. **Mobile first** |
| Art | Pixel art, 64 × 64 tiles, *Tiny Swords* pack by Pixel Frog as prototype ([design/10](docs/design/10-art-direction.md)) |

### Prior art by the owner

| Project | Reused | Not reused |
|---|---|---|
| [Grimscape](https://github.com/bal7hazar/grimscape) | Rooms as felt bitmaps, lazy room generation, Poseidon seed chain, queued actions in one transaction, layering (system → component → store → model → types → elements) | State keyed by adventurer; every goblin always chasing; unbounded dungeon; block timestamp as seed; square grid |
| [Arcade packages](https://github.com/cartridge-gg/arcade/tree/main/packages) | `quest`, `achievement`; later `leaderboard`, `social` ([ADR-0004](docs/architecture/ADR-0004-arcade-packages.md)) | Platform packages (registry, provider, controller) |
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
| **Room** | A hex board of at most 251 tiles; the unit of generation and of simulation |
| **Entrance** | An open tile on the border of a room, leading to the next room |
| **Facing / arc** | The direction an actor looks at; front, front-side, rear-side and back tiles around it |
| **Gate** | A link between two locations |
| **Caste** | A type of goblin |
| **Pack** | A group of goblins spawned and alerted together |
| **Awake** | A goblin that is simulated each tick |
| **Build** | Attributes + 8 skills + belt, locked during an expedition |
| **Remains** | What a dead goblin leaves; looting it rolls the drop |
| **Maw** | A dungeon that appears for a limited time, graded by the Guild. **Nest**: a permanent dungeon |
| **Stillstone** | The ore mined in Maws: material and main income |
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
| D-02 | One clock per instance; durations stored as deadlines; instances keyed by instance id | design/02 | Proposed (revised) |
| D-03 | Hubs have no on-chain geometry; presence is off-chain and cosmetic | design/02 | Accepted 2026-09-28 |
| D-04 | Defeat costs the instance only: experience, loot and quest progress are kept | design/02 | Proposed (revised after the owner found loot loss too harsh) |
| D-05 | Instances are not saved: leaving closes the instance, re-entering creates a new one | design/02 | Accepted 2026-09-28 |
| D-10 | Zones have fixed layouts, dungeons shifting ones, same generator | design/01 | Accepted 2026-09-28 |
| D-11 | Hexagonal maps, pointy-top, on `origami_hexmap` | design/02 | Accepted 2026-09-28 |
| D-20 | Rank ladder Wood → Platinum; promotion needs merit and a trial quest in a dungeon | design/06 | Accepted 2026-09-28 |
| D-30 | Six professions; Vanguard, Warden, Arcanist in the MVP | design/03 | Proposed |
| D-31 | GW1 numbers as baseline, 1 second = 1 tick | design/03 | Proposed |
| D-40 | Combat is fully deterministic | design/04 | Accepted 2026-09-28 |
| D-41 | Six facings, four arcs; critical from the back, flank from rear-sides | design/04 | Proposed (revised for hexes) |
| D-50 | Loot is rolled when remains are looted, not at death | design/07 | Proposed |
| D-51 | Alchemy discovery is per adventurer and per regional book | design/07 | Accepted 2026-09-28 |
| D-52 | Recipes have a rarity signature, identical for every adventurer | design/07 | Proposed; kept only if its step cost is negligible (SPK-2) |
| D-60 | Execute on Starknet mainnet; persistent and ephemeral domains split in code | ADR-0001 | Accepted 2026-09-28, subject to spikes |
| D-61 | Two randomness classes, Fate (vRNG) and Fog (seeded hash) | ADR-0002 | Proposed |
| D-62 | Client: TypeScript, PixiJS on demand, Capacitor; mobile first | ADR-0003 | Accepted 2026-09-28, subject to SPK-6 |
| D-72 | The orchestrator merges on green CI and audits, and deploys to Sepolia autonomously | OPERATIONS §7 | Accepted 2026-09-28 |
| D-73 | `assets/` and anything derived from it is never committed; licence forbids redistribution | design/10 | Accepted 2026-09-28 |
| D-70 | Documents, briefs, commits and pull requests in English; chat with the owner in French | OPERATIONS §11 | Accepted (owner's convention) |
| D-71 | Sub-agent titles start with the model used, in brackets | OPERATIONS §1 | Accepted 2026-09-28 |
| D-32…D-46, D-90…D-94 | Round 3: creation, slots, vault, look is equipment, collectors, smiths, looted equipment and boss armor sets in the MVP, titles, trade and auction house, estate, cosmetics; companions withdrawn | [decisions/2026-09-28-owner-review-3](docs/decisions/2026-09-28-owner-review-3.md) | Accepted 2026-09-28 |
| D-63 | Quests on the `quest` package in storage mode, titles on `achievement` in event mode | ADR-0004 | Proposed |
| D-80 | Co-op direction: every action of any member ticks the world | design/08 | Proposed (owner's idea, to design later) |

## 7. Open questions

| ID | Question | Needed by | Recommendation |
|---|---|---|---|
| Q-02 | Co-op: does "every action ticks" need a party-size modifier on spawns? | After Phase 3 | Decide by simulation |
| Q-03 | Is "defeat costs the instance only" the right severity, or is it now too soft? | Phase 1 | Yes; tune by playtest |
| Q-05 | Equipment: merchant-only, or drops and upgrades later? | Post-MVP | Merchant-only in MVP |
| Q-07 | Are items, potions, gold transferable or tokenised? Are adventurers NFTs? | Before Phase 4 | Adventurer as NFT; items non-transferable in MVP |
| Q-08 | Who can write registries: admin key, multisig, governance? | Phase 1 | Multisig, with a timelock before mainnet |
| Q-09 | Presence and chat in hubs: which transport? | Phase 5 | Torii off-chain messages if sufficient; else a small relay |
| Q-10 | Business model and who funds the paymaster | Before mainnet | — (owner) |
| Q-11 | Names: world, regions, professions, skills | `LORE` track | Working names stand until then |
| Q-12 | The asset pack has no caster sprite. Keep the Arcanist in the MVP (needs one commissioned sprite) or replace it by the Cleric (Monk sprite exists)? | Phase 2 | Keep the Arcanist if a sprite can be commissioned; else Cleric |
| Q-22 | Extract the Arcade packages into dedicated, published repositories | Programme level | Yes, `quest` first |
| Q-17 | Do mainnet deployments and mainnet registry writes need an explicit go from the owner each time? | Before Phase 7 | Yes |
| Q-14 | Default room size for portrait phones | SPK-6 | 13 × 19 if readable, else 15 × 15 with a following camera |

## 8. Constraints that are easy to forget

- **Intellectual property.** Guild Wars and Goblin Slayer are inspirations for systems and
  tone. No name, text, icon, character or map from either may be reused. Numbers and
  mechanics may serve as a baseline.
- **Multiplayer door.** Constraints M-1…M-6 in
  [docs/design/08-multiplayer.md](docs/design/08-multiplayer.md) apply to every task.
- **No block data in instances.** No rule inside an instance reads block number,
  timestamp or transaction hash.
- **Bounded execution.** Every loop in a contract has a bound stated in the design.
- **Two domains.** Persistent and ephemeral state never share a model (ADR-0001).
- **Power budget.** The client has no permanent render loop (ADR-0003).
- **Assets.** `assets/` and anything derived from it is never committed: the licence
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
| Sub-agents | `claude` CLI logged in as **claude-b7r** (check with `claude auth status`): Opus 5.5 or Sonnet 5 by difficulty, Fable only marginally. `codex` CLI: audits and second opinions only |
| Credentials | Sepolia deployment credentials are in the session's settings environment. Never copy them into a document, a brief or a log |
| Assets | *Tiny Swords* by Pixel Frog, `assets/` at the root of the main checkout, ignored by git; to be copied to the VPS by the owner, outside git |
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
