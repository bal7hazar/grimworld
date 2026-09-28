# SPK-11 — The indexer: what it must do, and with what

Measured on 2026-09-28, on the VPS (8 vCPU, 31 GB, Linux x86_64), by `[Opus 5.5]`, against
starknet-devnet 0.10.0 (JSON-RPC 0.10.2), Node 24.21.0, starknet.js 10.8.0, Cairo 2.19. Answers
NS-2 of [ADR-0007](../architecture/ADR-0007-native-starknet.md). The prototype is in
[`spikes/SPK-11/`](../../spikes/SPK-11/); the real output of its scenario and benchmark is committed
in [`spikes/SPK-11/results/`](../../spikes/SPK-11/results/) (`demo.txt`, `bench.txt`). Revised in
fix loop 1 after the `[GPT-6-Sol]` audit (§8).

## 0. Recommendation

**Write our own indexer: one TypeScript process (Node 24) that follows a Starknet node over
JSON-RPC 0.10, decodes our events, keeps versioned tables in SQLite, and serves queries over HTTP
and subscriptions over server-sent events, under the correctness rules of §4.** The prototype
passes every check of `demo.ts` (22 checks, `results/demo.txt`):
- no answer the client accepts is ever a state the chain does not hold at that answer's block.
  This covers the live reorg, the restart on a replaced tip, and a subscription cache kept through
  a disconnection;
- lossless u64 values;
- a halt on a missing event;
- no secret in the indexer's environment or logs.

| Reason | |
|---|---|
| Small job | The game needs **5 events and 7 query shapes** (§1). The correctness logic (hash-and-commitment tip check, versioned rows, rewind, serving states, reconciliation) is a few hundred lines in `indexer.ts` |
| No generic indexer fits without cost | Torii indexes Dojo worlds and token standards only. SubQuery has no reorg handling on Starknet. Substreams and a self-hosted Apibara are multi-service stacks. Checkpoint is the one close fit, and it needs Postgres and serves no subscriptions (§2) |
| Reorgs proven, not assumed | The scheme (versioned rows, rewind in one transaction) is the one Checkpoint and Apibara use. The serving rules of §4 are tested against devnet's aborted blocks, answer by answer |
| Operations | One process and one file. No Docker, no Postgres, no etcd, no object store. Rebuilt by deleting the file (§5) |
| Lock-in | None beyond the Starknet JSON-RPC specification |

**Runner-up: [Checkpoint](https://github.com/snapshot-labs/checkpoint)** (MIT). It detects reorgs by
parent hash and deletes rows above the last good block, and it serves GraphQL. It is still beta,
needs PostgreSQL, and documents no subscriptions. It was **not prototyped**: the machine has no
PostgreSQL server and no Docker, and installing one is outside the brief. **Reference design for
production:** [Ekubo's indexer](https://github.com/EkuboProtocol/indexer) (MIT), plain JSON-RPC 0.10
into Postgres with header hash checks.

## 1. What needs indexing (AC-1)

Source: docs/design (00–18) and ADR-0007 *Events are an interface*. **Every read the client needs
to show something**, classified as exactly one of: **V** view call (own or point state, from
storage), **S** client simulation (derived from what was read), **I** indexer (spans players,
history or a search the contract cannot do in bounded execution). "MVP" follows design/09.

| # | Read | Source | Class | Why | MVP |
|---|---|---|---|---|---|
| 1 | Instance state (clock, adventurer, goblins, revealed chunks, features) | design/11 *Screen in an instance*; design/02 *Instances* | V | Own instance, keyed by instance id (design/08 M-1) | yes |
| 2 | Window, sight, awake goblins | design/02 *Map*, *Simulation budget*; design/18 *What the adventurer sees* | S | Built from chunks each tick, never stored | yes |
| 3 | Health, energy, adrenaline, conditions with ticks left | design/11 status zone | S | Stored as deadlines on the instance clock (design/02 D-02) | yes |
| 4 | Target panel, activation ring, goblin state marks, facing, arcs | design/11 *What the rules need to show* | S | From #1 | yes |
| 5 | Previews: path and cost, range and line of sight, recharge, energy in red, interruptible | design/11 *Acting*, *What the rules need* | S | From #1 and the skill registry | yes |
| 6 | Queue ghosts, why a queue stopped, "the world corrected itself" | design/11 *The queue*, *The chain, unseen* | S | Prediction compared with #1 | yes |
| 7 | "saving…" (confirmation late) | design/11 *The chain, unseen* | V | Transaction status over RPC | yes |
| 8 | Draw outcomes (loot, identification, brewing, chest) | design/11 reveal; design/15 *Identification* | V | Own state after the randomness transaction | yes |
| 9 | Registry content (skills, castes, loot tables, quests, locations, gates, recipes, trainer and smith stock, collector offers) | CONTEXT §5 *Registry*; design/06; design/15 *Sources* | V | Static on-chain data, cacheable | yes |
| 10 | Glow on remains from a caste's best drop | design/11 *What the rules need* | S | Registry loot table | yes |
| 11 | The account's adventurers (3 slots) | design/03 D-33; design/11 first launch | V | Own account, bounded | yes |
| 12 | Character sheet: level, rank, merit, attributes, known skills, build | design/03 *Identity*; design/11 *Desktop* | V | Own state | yes |
| 13 | Promotion eligibility | design/06 *Promotion* | S | Merit against the registry threshold | yes |
| 14 | Pack, vault, gold in the hub header | design/11 *Hubs*; design/15 *Storage* | V | Own balances and entities | yes |
| 15 | Guild board: quests available to this adventurer | design/06 *Quest board*; design/11 Guild | S | Quest log (V) filtered by rank and prerequisites | yes |
| 16 | Quest progress, active quests (max 3) | design/06 *Rules* | V | `quest` package in storage mode (D-63) | yes |
| 17 | Contracts of the day (3 per hub) | design/14 *Guild contracts* | V | "Read in the hub, in the persistent domain" | yes |
| 18 | Rift board: 5 identities and the cleared bitmap | design/17 *On-chain* | V | Stored per account per day | yes |
| 19 | Which Rift is open (4th, Red) | design/17 *On-chain* | S | From the bitmap | yes |
| 20 | **Hub: list and count of present adventurers** | design/11 (hub); design/09 Hubs; ADR-0007 | **I** | Spans players (E-2) | yes |
| 21 | Their positions, walking by | design/02 D-03 | — (off-chain relay, Q-09) | Cosmetic, not chain state | yes |
| 22 | Inspect another adventurer (rank, level, build) | design/08; design/11 | V | Point lookup by id, the id from #20 | yes |
| 23 | **Title under another adventurer's name** | design/13 *What a title is*; ADR-0007 | **I** | Listed by ADR-0007 (E-3) | yes |
| 24 | Own titles: progress and tier | design/13 *Implementation notes* | S | On-chain counters (V) and the tier table | yes |
| 25 | **Own displayed title** | design/13; D-63 | **I** if event mode, else V | E-3 | yes |
| 26 | Trainer: skills to buy, rising prices | design/11 Trainer; design/15 *Gold* | S | Registry and the count of known skills | yes |
| 27 | Build editor warnings | design/11 | S | From the chosen bar | yes |
| 28 | Smith, armorer, enchanter, alchemist screens; grimoire; hints | design/11; design/07 *Hints* | V | Own items and grimoire, registry | yes |
| 29 | Item value estimates | design/15 *Identification*, *Gold* | S | Formulas | yes |
| 30 | **Market search by category** | design/11 (auction house); design/16 | **I** | World-wide scan across sellers | yes |
| 31 | **Cheapest lot per item and lot size, and the next after a lost race** | design/16 | **I** | "Not computed on-chain" | yes |
| 32 | **Average price over the last sales** | design/16 | **I** | History | yes |
| 33 | My lots | design/11 | V | Bounded (10 + rank per account), stored for the limit anyway | yes |
| 34 | Lot slots left, right to sell (Tin) | design/16 | S | Lot count and the highest rank | yes |
| 35 | Is a lot expired or returnable | design/16 | S | Expiry against now | yes |
| 36 | Direct trade: both sides, confirmations | design/16 *Direct trade* | V | Stored trade record, by id | yes |
| 37 | **Direct trade: incoming request** | design/16 *Direct trade* | **I** (subscription), or the relay | Addressed from another player (E-3) | yes |
| 38 | Gate and map: unlocked hubs, requirements, zone outlines | design/11 Gate; design/18 TP-2 | V | Own unlocks and registry | yes |
| 39 | **Leaderboards: rank, trials** | design/08 | **I** | Ranking across players | ambiguous (E-1) |
| 40 | Leaderboard: elite clears | design/08 | I | Same | later |
| 41 | Estate buildings and yield | design/12 *Implementation notes* | S | `min(cap, rate × elapsed)` from stored fields | later |
| 42 | Visiting another player's estate | design/12 EQ-2 | V | Point lookup by account | later |
| 43 | Trophy hall | design/12 *Buildings* | as #24/#25 | Own titles | later |
| 44 | Co-op: other members' actions | design/08 | I (stream) | "Reconcile on the indexer stream" | later |

Totals: 19 V, 17 S, 8 I in the MVP (#20, #23, #25, #30, #31, #32, #37, #39), 2 I later, and 1
off-chain relay (#21).

| Query | Serves | Shape | Subscription |
|---|---|---|---|
| Q1 | #31 | open, unexpired lots of `(item, lot size)` by price then lot id, first *k* | yes, while the market is open |
| Q2 | #30 | items of a category with an open lot, cheapest per size | no |
| Q3 | #32 | mean per unit over the last *N* sales of an item | no |
| Q4 | #20 | adventurers whose current hub is H: count and list | yes, while in the hub |
| Q5 | #23, #25 | current title of a set of adventurer ids | no |
| Q6 | #39 | top *K*, paginated, and "my position" | no |
| Q7 | #37 | requests to an adventurer id | yes |

Events the indexer needs: **five**, each as small as the reads allow.

| Event | Keys (after the selector) | Data | Emitted by | Serves |
|---|---|---|---|---|
| `LotPosted` | `item`, `lot_size` | `lot`, `price`, `expiry` (+ the equipment id for equipment) | posting a lot | Q1–Q3 |
| `LotClosed` | `lot` | `sold: bool` | buy, withdraw, return of an expired lot | Q1–Q3 |
| `AdventurerLocated` | `hub` (0: in no hub) | `adventurer` | travel, return, defeat, gate entry | Q4 |
| `TitleDisplayed` | `adventurer` | `title`, `tier` | claiming or choosing a title | Q5 |
| `RankPromoted` (only if #39 is in the MVP) | `adventurer` | `rank`, `first_attempt` | a successful trial | Q6 |

Not emitted, on purpose:
- the seller (my lots is a view call);
- the buyer (no read uses it);
- an expiry event (expiry is lazy: the indexer compares `expiry` with block time);
- names (batched view calls).

`TradeRequested` exists only if direct trade does not go through the relay (E-3). The prototype's
events are `LotPosted`, `LotClosed` and `AdventurerLocated`, without `lot_size` and `expiry`. It
adds `LotCountSet`, used only to reach the u64 boundaries.

## 2. Candidates (AC-2)

Web research on 2026-09-28. Each claim links the page it was read from. **Unknown** marks what the
pages consulted do not state.

| Candidate | What | Licence | Last release | Self-hosted without a paid service | Fit |
|---|---|---|---|---|---|
| **Apibara, upstream** ([apibara/dna](https://github.com/apibara/dna), `@apibara/indexer`) | A Rust stream server (DNA) that ingests from a node, and a TS SDK | Apache-2.0 | `dna-starknet/v2.1.4`, 2026-05-18 ([releases](https://github.com/apibara/dna/releases)) | Possible by running DNA. **Its dependencies (etcd, object store) are unknown for upstream**: the README consulted does not list them | Custom events: yes. Upstream's future is unclear: Ekubo left the DNA stream ([README](https://raw.githubusercontent.com/EkuboProtocol/indexer/main/README.md)) |
| **Apibara, Starkstream fork** ([software-mansion-labs/starkstream-dna](https://github.com/software-mansion-labs/starkstream-dna)) | Software Mansion's fork of DNA | Apache-2.0 | unknown | Yes, with Starknet JSON-RPC + WebSocket providers, **etcd** and an **object store** (S3/MinIO), per its README; a Dockerfile is provided | Same SDK |
| **Apibara, hosted streams** (`mainnet.starkstream.io`, `testnet.starkstream.io`) | Streams "provided by a partner" ([docs](https://www.apibara.com/docs/networks/starknet)) | — | — | Not self-hosted. **Whether an API key or payment is needed is unknown** | Would put a third party in the path |
| [Checkpoint](https://github.com/snapshot-labs/checkpoint) | TS library, writers per event, GraphQL | MIT | `v0.1.0-beta.80`, 2026-08-19 ([releases](https://github.com/snapshot-labs/checkpoint/releases)) | Yes. RPC + **PostgreSQL** ([quickstart](https://github.com/snapshot-labs/checkpoint-docs/blob/master/guides/quickstart.md)) | Custom events: yes |
| [Torii](https://github.com/dojoengine/torii) | Dojo's indexer, SQLite, GraphQL + subscriptions, gRPC, SQL | Apache-2.0 | v1.8.16, 2026-05-20 | Yes | **No**: contract types WORLD, ERC20, ERC721, ERC1155. Raw events are "dev only" ([configuration](https://book.dojoengine.org/toolchain/torii/configuration)) |
| [SubQuery](https://github.com/subquery/subql-starknet) | Node + GraphQL query service + Postgres | GPL-3.0 | node-starknet 6.1.0, 2025-07-23; last push 2025-10-30 | Yes | Stale. `--unfinalized-blocks` is for Substrate and Ethereum only ([reference](https://subquery.network/doc/indexer/run_publish/references.html)) |
| [Firehose / Substreams](https://github.com/streamingfast/firehose-starknet) | StreamingFast's block stream. The Graph serves Starknet only through it ([docs](https://thegraph.com/docs/en/supported-networks/starknet-mainnet/)) | Apache-2.0 | v1.1.2, 2026-01-05 | In principle, with a Starknet RPC **and an Ethereum L1 RPC**, plus substreams and a sink | A heavy multi-service stack |
| Goldsky | Hosted pipelines ([chain page](https://goldsky.com/chains/starknet)) | proprietary | — | **No**: usage-priced after a $100 credit ([pricing](https://docs.goldsky.com/pricing/summary)) | Recorded, not tried (paid service) |
| Envio, Ponder, rindexer | | | | | EVM (and Fuel) only ([Envio](https://docs.envio.dev/docs/HyperIndex/supported-networks), [Ponder](https://ponder.sh/docs/getting-started/new-project), [rindexer](https://github.com/joshstevens19/rindexer)) |
| **Our own** | Node 24 + JSON-RPC 0.10 + SQLite (`spikes/SPK-11/indexer.ts`) | ours | — | Yes: a node or RPC endpoint and one process | Custom events by construction |

| | Apibara (self-hosted) | Checkpoint | **Our own** |
|---|---|---|---|
| Reorg detection | Server-side canonical chain; the SDK receives `invalidate` ([docs](https://www.apibara.com/docs/getting-started/indexers)) | Compares `parent_hash` with the stored hash ([provider.ts](https://raw.githubusercontent.com/snapshot-labs/checkpoint/master/src/providers/starknet/provider.ts)) | The stored tip is checked by hash **and** commitments at every step; events are fetched by block hash (§4) |
| Rollback | Rows past the new head reverted from an audit table ([internals](https://www.apibara.com/docs/storage/drizzle-pg/internals)) | Deletes rows with `lower(block_range) > lastGoodBlock` ([container.ts](https://raw.githubusercontent.com/snapshot-labs/checkpoint/master/src/container.ts)) | Rows valid over `[_from, _to)`, rewound in one transaction |
| Serving during divergence | unknown | unknown | 503 `loading`/`rewinding`; every answer carries its block; a client freshness rule (§4) |
| Pre-confirmed (0.14) | DNA starknet v2.1.2 enables ingestion | Reads `pre_confirmed` | Not indexed (§3) |
| Query / subscription | None built in / — | GraphQL / none documented | HTTP JSON / SSE with snapshot and block identity |
| Processes | Node + DNA (+ etcd + object store for the fork) + indexer + Postgres | RPC + indexer + Postgres | RPC + indexer (SQLite file) |

Starknet's reorgs are deep:
- **2025-09-02**: two reorgs of `ACCEPTED_ON_L2` blocks, about 1 h and 20 min reverted
  ([incident report](https://www.starknet.io/blog/starknet-incident-report-september-2-2025/)).
- **2026-01-05**: 18 min reverted
  ([incident report](https://www.starknet.io/blog/starknet-incident-report-january-5-2026/)).

In both, only L1-accepted blocks were safe. The rewind walks back as far as the chain disagrees,
and a production indexer keeps versioned history at least down to the last L1-accepted block.

## 3. The prototype (AC-3)

| File | What |
|---|---|
| `src/market.cairo`, `tests/test_market.cairo` | The contract (details below the table). 12 tests with budgets |
| `indexer.ts` | The indexer |
| `client.ts` | The client: `cheapest`, `presence`, the freshness rule (`check`, `verify`), `subscribe`, `LotCache` |
| `run-indexer.ts` | Starts the indexer with an explicit one-variable environment |
| `chain.ts` | The node's account, deploy, send, abort |
| `demo.ts`, `results/demo.txt` | The scenario of §4 and its output |
| `bench.ts`, `results/bench.txt` | The figures of §5 and its output |
| `with-archive.sh` | `scripts/with-node.sh` with `STATE_ARCHIVE_CAPACITY=full` in the environment, which `devnet_abortBlocks` needs (devnet reads the option from its environment; `with-node.sh` is unchanged) |
| `probe.ts`, `probe-hash.ts` | What devnet does on an abort |

The contract:
- `post` emits `LotPosted { #[key] item, lot, quantity, price }`.
- `buy` and `withdraw` emit `LotClosed { #[key] lot, sold }`.
- `locate` emits `AdventurerLocated { #[key] hub, adventurer }`.
- `skip_lots` emits `LotCountSet { count }` (test only).
- `lot` and `lot_count` are views.
- `post_silent`, `withdraw_silent` and `locate_silent` exist only to measure event gas. `post_silent`
  also tests completeness (§6).

**Pre-confirmed blocks are not indexed.** The indexer serves `ACCEPTED_ON_L2` blocks only. The
player's own pending action is shown by the client from its own transaction status ("saving…",
design/11). Indexing `pre_confirmed` as a provisional overlay is possible, but was not tried.

Commands (from the repository root):

```
scripts/lock.sh scarb --manifest-path spikes/SPK-11/Scarb.toml build
cd spikes/SPK-11 && snforge test && pnpm install
spikes/SPK-11/with-archive.sh node spikes/SPK-11/demo.ts
spikes/SPK-11/with-archive.sh node spikes/SPK-11/bench.ts 100 100
```

## 4. Reorgs, and what the client may be shown (AC-4)

### What devnet simulates, and how faithfully

`devnet_abortBlocks {starting_block_id}` (needs `--state-archive-capacity full`) removes the blocks
from the given one to the tip:
- the head goes back;
- the aborted blocks answer `Block not found`;
- their transactions are gone, and the state is the parent's;
- the lot counter goes back too, so **the same lot id is handed out again**;
- WebSocket subscribers receive `starknet_subscriptionReorg` (`probe.ts`), as in the
  [specification](https://raw.githubusercontent.com/starkware-libs/starknet-specs/master/api/starknet_ws_api.json).

**Not faithful:**
- **A replacement block gets the hash of the block it replaces** (same number and parent), although
  its commitments differ (`probe-hash.ts`). On Starknet the hash commits to those. The indexer and
  the client therefore compare hash **and** commitments. This is equivalent on Starknet and
  necessary on devnet: in fix loop 1, a demo check that compared hashes only reported a stale
  cache as current.
- Aborted transactions are dropped. On Starknet they may be included again.
- Everything is local and instantaneous.

### The rules

| # | Rule | Where |
|---|---|---|
| R1 | **Serving states.** `loading` from start until the stored tip has been checked against the chain. `rewinding` from the moment a divergence is seen until the rewind is committed. `halted` when an invariant fails (§6). In these states every query answers **503 with the state and no rows**. `ok` otherwise | `indexer.ts`, `setStatus`, HTTP handler |
| R2 | **Block identity on every answer.** `head {number, hash, commitments}`: the block the answer is consistent with, read with the rows in one synchronous read | HTTP handler |
| R3 | **Client freshness rule.** An answer is accepted only if (1) the indexer says `ok`, (2) the client's own node still has the head block with the same hash and commitments, read **after** the answer, and (3) that block is at most `maxLag` (5) blocks below the node's tip. Otherwise the screen says "loading" and the client asks again. This covers the window no indexer can close: a reorg on the node before the indexer's next step. An accepted answer may be up to `maxLag` blocks old, a past state of the canonical chain | `client.ts`, `check`/`verify` |
| R4 | **Subscriptions resync, never patch across a gap.** A connection starts with a `reset` snapshot of the item's open lots, and every rewind is followed by a new `reset`. `posted`/`closed`/`head` events carry block identity. The `LotCache` is rebuilt from each `reset`, is not `ready` after a disconnection or a `rewind` until the next `reset`, and is shown only if its head passes R3 | `indexer.ts`, `reset`; `client.ts`, `LotCache` |
| R5 | **The contract stays authoritative.** Acting on an accepted lot that a later reorg removed reverts (`buy`: `'lot not open'`), and the client falls back to the next lot, the "lost race" path of design/16 | contract |

### Evidence (`results/demo.txt`, all 22 checks passed)

The criterion: an answer with rows is **wrong** if it differs from the chain's state at the
answer's own head block, computed by view calls (`lot(i)`) at that block. An orphaned block counts
as wrong.

| Case | What happened | Result |
|---|---|---|
| Live reorg (poll 500 ms to widen the window): a purchase of lot 1 and a new lot 5 aborted | Sampled from the abort until an answer at the chain's tip was accepted: 40 answers. **37 raw answers were orphaned**, and the rule rejected all of them. The cache was rebuilt by the `reset` after the rewind, **reopening lot 1**; a rewind event alone could not have done that | `acceptedWrong 0`, `cacheWrong 0`; latest state accepted **526 ms** after the abort (bounded by the poll) |
| Cache through a disconnection, a reorg and a reused id | Disconnected; lot 5 posted at 500, aborted, lot 5 posted again at 650, lot 3 withdrawn; reconnected | The accepted cache equals the chain: `1:300 5:650` |
| Restart on a replaced tip, node slowed to 50 ms per call | The database held orphaned block 9. The indexer served from its first answer: **37 answers `loading`**, then 15 with rows, all states the chain held at their head (14 of them its state two blocks back, within `maxLag`) | `rawWrong 0`; latest state accepted 609 ms after the first answer |
| u64 boundaries | Lots `2^53+1`, `2^63`, `2^64-1` at prices `2^64-1`, `2^63`, `2^53+1`; lot `2^63` bought | The query equals the chain's view calls, ordered losslessly. The abort rewound them all, and the next lot id was the chain's (7) |
| Rebuild | An empty database from the deployment block | Answer for answer equal to the indexer that lived through the reorgs |

What the table does not cover:
- The indexer is only as right as its node. It must run against one node we trust, never mixing
  endpoints within a step.
- The client's node is the arbiter of R3. If both follow a minority branch, both agree on it until
  the network settles. That is the chain's own limit, and R5 still holds.

## 5. Hosting and cost (AC-5)

### Measured (`results/bench.txt`, devnet on the same machine)

| Figure | Value |
|---|---|
| Catch-up from an empty database | 10 000 events over 101 blocks in **1.08 s** (9 230 events/s, process start included) |
| RPC calls for that catch-up | `getBlockWithTxHashes` 103, `getEvents` 101, `blockHashAndNumber` 3, `call` 2 |
| Peak memory of the indexer | **127 MB** RSS (Node 24 baseline included) |
| Disk | 1.21 MB for 10 000 events: **127 bytes per event**. It rose from 59 in the first version, because u64 values are stored as 16-digit text (lossless, §4) and each lot also writes a counter row |
| Disk per stored block | 1.43 MB after 1 121 blocks and 10 020 events |
| 1 000 blocks without our events | 2.57 s (**2.57 ms per block**). RPC calls: `getBlockWithTxHashes` 1 011, `getEvents` 1 000, `blockHashAndNumber` 11, `call` 11 = **2.03 per block** |
| Idle following, 100 ms poll | 48 `blockHashAndNumber` + 48 `getBlockWithTxHashes` in 5 s = **19.2 calls per second** (2 per poll) |
| 20 live blocks with one event each, idle polls included | `getBlockWithTxHashes` 60, `blockHashAndNumber` 40, `getEvents` 20, `call` 20 |
| Live latency (receipt → `posted` on the subscription, 100 ms poll) | median **54 ms**, min 14, max 72 |
| Time to consistency after a reorg | live: 526 ms at a 500 ms poll; restart: 609 ms with a 50 ms node (§4) |

### Projections (not measured; each assumption named)

Cost per call from Alchemy's table ([CU costs](https://www.alchemy.com/docs/reference/compute-unit-costs)):
`starknet_blockHashAndNumber` 10 CU; `starknet_getBlockWithTxHashes`, `starknet_getEvents`,
`starknet_call` 20 CU each.

| Item | Formula | At a 1 s poll and **an assumed block every 6 s** (unverified) |
|---|---|---|
| Idle polls | 1 × `blockHashAndNumber` + 1 × `getBlockWithTxHashes` per poll = 30 CU | 86 400 polls/day → 2.6 M CU/day |
| New blocks | 1 × `getBlockWithTxHashes` + 1 × `getEvents` + 1 × `call` (reconciliation, when the tip changes) ≈ 60 CU | 14 400 blocks/day → 0.86 M CU/day |
| Month | | ≈ 104 M CU. Above the free 30 M; ≈ 74 M × $0.525/M ([pricing](https://www.alchemy.com/pricing)) ≈ **$39/month** |
| With a WebSocket `newHeads` wake-up instead of polling | idle polls → 0 | ≈ 26 M CU/month, inside the free tier |

Alchemy lists Starknet RPC v0_6–v0_9 only ([FAQ](https://www.alchemy.com/docs/reference/starknet-api-faq)).
The indexer needs 0.10 for `getEvents` by block hash with `EMITTED_EVENT` positions: check before
choosing it. **Disk, projected linearly** from 127 bytes per event: ≈ 121 MB per million events,
plus the stored blocks (prunable below the last L1-accepted block).

| | Sepolia | Mainnet |
|---|---|---|
| Process | One Node 24 process (≈130 MB) under systemd | Same; a second instance on another host for failover, each with its own database |
| Database | SQLite | SQLite while one writer is enough; Postgres if several processes must share tables (same versioned schema) |
| RPC | JSON-RPC **0.10**, HTTP, optionally WebSocket. A public endpoint to start, e.g. Nethermind's open `free-rpc.nethermind.io/sepolia-juno/` ([docs](https://docs.data.voyager.online/)); its rate limits are unknown | **Our own Juno node**: 4 cores, 8 GB+ RAM, NVMe ([hardware](https://juno.nethermind.io/hardware-requirements)); **85.6 GB pruned**, 453.9 GB full as of 2026-07-31 ([snapshots](https://juno.nethermind.io/snapshots)); serves RPC 0.10.1 and WebSocket. Or a hosted RPC at the projection above |

### Rebuild from the chain

1. Stop the indexer. Delete its database file (with `-wal` and `-shm`).
2. Start it with `--from <the contract's deployment block>`. It answers `loading` until its first
   step, then serves states whose `head` says how far it has got. Clients reject answers more than
   `maxLag` blocks behind (R3) and show "loading".

Measured: `demo.ts` rebuilt the scenario's chain, and its answers equalled the lived-through
indexer's. On mainnet, a rebuild at 2 calls per block from the deployment block is millions of
calls. The production indexer must catch up **below the last L1-accepted block** with `getEvents`
over block ranges, about one call per thousand events. **Not prototyped.**

## 6. What ENG-01 must freeze (events as an API)

1. **Names and layouts.** The first key is the selector of the event's name. Renaming, reordering,
   retyping, or moving a field between keys and data breaks every rebuild of the history. A change
   is a **new event name**; the indexer decodes both forever.
2. **Completeness is a contract invariant.** Every path that changes an indexed thing emits its
   event exactly once: posting, buying, withdrawing and returning an expired lot; every change of
   hub. **What the indexer can detect, and what it cannot:**
   - *Lots: detectable.* Lot ids come from a counter, and the counter never changes unannounced
     (in the prototype, `LotCountSet` for the test-only skip). The indexer halts on a `LotPosted`
     whose id is not the next one. At every new tip it also compares the chain's `lot_count` (a
     view call at that block) with its own. `demo.ts` shows both: `post_silent` halted the running
     indexer by reconciliation, and a rebuild by the id gap. After a halt, queries answer 503
     `halted`: stale, never wrong.
   - *Closing a lot without `LotClosed`: not detected.* It would need a count of open lots on the
     chain, compared the same way. ENG-01 should expose it (a view `open_lot_count`, or a counter
     in `LotClosed`).
   - *Presence, titles: not detectable* without a similar counter or a periodic sample of view
     calls. There the invariant rests on the contract's tests. The claim of the first version
     ("fail-stop on a missing event") was too broad and is withdrawn in this form.
3. **Identifiers.** The ids in events are the storage ids. Ids handed out by a counter are
   **reused after a reorg** (lot 5 was 120, 500, 650 then 700 in `demo.ts`). Clients never keep
   anything by id across a `reset`.
4. **Integer widths.** Gold amounts and lot ids are u64 or narrower. The indexer stores them
   losslessly (16-digit hex text, ordered like the numbers) and sends decimal strings, never JSON
   numbers (exact only below 2^53). A wider type needs the same treatment.
5. **Keys** are what a third party filters by (`item` and `lot_size`, `hub`, `adventurer`). They
   cost the same as data.
6. **Stable addresses.** The indexer filters by contract address. Upgrades by class replacement keep
   it (ADR-0007, NS-4). A new address is a new source, with its deployment block.
7. **Size, measured** (receipt deltas against the same write without the event, `results/bench.txt`):

   | Event | Felts | L2 gas | Of the transaction |
   |---|---|---|---|
   | `LotPosted` | 5 (selector, item, lot, quantity, price) | **35 840** | 2.1 % of `post` (1 683 920) |
   | `LotClosed` | 3 | **65 600** | 5.6 % of `withdraw` (1 181 440) |
   | `AdventurerLocated` | 3 | **25 600** | 2.5 % of `locate` (1 026 560) |

   None adds L1 data gas. The costs are not proportional to size: `LotClosed` costs more than the
   larger `LotPosted`. The delta measures the entrypoint with its event against the entrypoint
   without it, so it includes any difference in the compiled code around the emission. ENG-01
   measures its own events the same way; no per-felt rate is assumed.

## 7. Open questions

| # | Question | For |
|---|---|---|
| E-1 | Are leaderboards in the MVP? design/08 says v1 has them "read from chain"; design/09, ADR-0004 and ADR-0007 put `leaderboard` after the MVP. Decides `RankPromoted` | owner |
| E-2 | Hub presence: the relay (design/02 D-03, Q-09) or `AdventurerLocated` through the indexer (ADR-0007)? | owner / design |
| E-3 | Is the displayed title stored or only emitted (D-63)? How does a player learn of a trade request? | design/13, design/16 |
| E-4 | What is "one item" on the market for equipment? The average-price window (N, mean or median)? | design/16 |
| — | Pre-confirmed overlay, WebSocket wake-up, range catch-up below L1 acceptance, alerting on `halted`, an `open_lot_count` reconciliation | the indexer track |

## 8. Fix loop 1

Changes after the `[GPT-6-Sol]` audit (lenses S, Q), all shown by `results/demo.txt` and
`results/bench.txt`:
- serving is gated (R1);
- a client freshness rule (R3);
- resync on reconnect and after a rewind (R4);
- completeness checks and a narrowed completeness claim (§6);
- lossless u64 storage (§4);
- the indexer launched with a one-variable environment and a redacted RPC URL (§5, and below);
- committed benchmark output, with gas for all three events and RPC use per method (§5, §6);
- the 44 reads listed (§1);
- Apibara split into upstream, fork and hosted (§2).

**Secrets.** The indexer holds **no signing key**. `run-indexer.ts` starts it with exactly one
variable, `INDEXER_RPC_URL`. The URL may carry a provider's key: it lives in the process's
environment, never in argv, the database or a log. Logs show the URL as
`http://host:port/…(redacted)`. `demo.ts` checks the environment line, and checks that no log holds
the fake key it put in the URL or the node account's private key. The database holds nothing that
cannot be rebuilt from the chain (the rebuild check).
