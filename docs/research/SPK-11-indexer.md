# SPK-11 — The indexer: what it must do, and with what

Measured on 2026-09-28, on the VPS (8 vCPU, 31 GB, Linux x86_64), by `[Opus 5.5]`, against
starknet-devnet 0.10.0 (JSON-RPC 0.10.2), Node 24.21.0, starknet.js 10.8.0, Cairo 2.19. Answers
NS-2 of [ADR-0007](../architecture/ADR-0007-native-starknet.md). The prototype is in
[`spikes/SPK-11/`](../../spikes/SPK-11/).

## 0. Recommendation

**Write our own indexer: one TypeScript process (Node 24) that follows a Starknet node over
JSON-RPC 0.10, decodes our events, keeps versioned tables in SQLite, and serves queries over HTTP
and subscriptions over server-sent events.** It is what the prototype is, and it passed every check
of §4: the live reorg was consistent 114 ms after the blocks were aborted, the offline reorg
352 ms after a restart, and a rebuild from the chain matched the rewound indexer answer for answer.

| Reason | |
|---|---|
| Small job | The game needs **5 events and 7 query shapes** (§1). A framework buys little for that; the rewind logic is ~40 lines (`indexer.ts`: `rewind`, `forkPoint`, `step`) |
| No generic indexer fits without cost | Torii indexes Dojo worlds and token standards only; SubQuery has no reorg handling on Starknet; Substreams and Apibara's DNA are multi-service stacks; Checkpoint is the one close fit, and it needs Postgres and serves no subscriptions (§2) |
| Reorgs are proven in, not assumed | The scheme (hash-anchored blocks, versioned rows, rewind in one transaction) is the one Checkpoint and Apibara use, and it is tested here against devnet's aborted blocks |
| Operations | One process and one file. No Docker, no Postgres, no etcd, no object store. Rebuilt by deleting the file (§5) |
| Lock-in | None beyond the Starknet JSON-RPC specification, which every node (pathfinder, juno, devnet) implements |

**Runner-up: [Checkpoint](https://github.com/snapshot-labs/checkpoint)** (MIT, snapshot-labs). It
has the same reorg design (parent-hash check, rows with a block range deleted above the last good
block) and a GraphQL API. It is still beta (`v0.1.0-beta.80`), needs PostgreSQL, and documents no
subscriptions. It was **not prototyped**: the machine has no PostgreSQL server and no Docker, and
installing one is outside the brief. The reference design for a production indexer of our own is
[Ekubo's indexer](https://github.com/EkuboProtocol/indexer) (MIT). In September 2026 it moved from
Apibara's DNA stream to plain JSON-RPC 0.10 into Postgres, with header hash checks and a reorg
window.

## 1. What needs indexing (AC-1)

From docs/design (read in full for 02, 03, 06, 08, 09, 11–18) and ADR-0007 *Events are an
interface*. 44 reads were classified; the table keeps the ones the indexer serves, and a count of
the others.

| Class | Reads | Examples |
|---|---|---|
| **View call** (own state, from storage) | 19 | instance state (design/11, 02), character sheet, pack and vault, quest progress (D-63 storage mode), contracts of the day (14), Rift board (17), my lots (16: bounded to 10 + rank, stored for the limit anyway), direct trade record, inspect one adventurer by id (08, 11), registries |
| **Client simulation** (derived from what was read) | 17 | window, sight, awake goblins (02), health and deadlines, previews, queue ghosts and "the world corrected itself" (11), promotion eligibility, guild board filter, trainer prices, lot expiry, estate yield |
| **Indexer** | 8 in the MVP (+2 later) | below |

| # | Indexer read | Source | Query shape | Subscription |
|---|---|---|---|---|
| 1 | Cheapest lot per item and lot size, and the next ones after a lost race | design/16 (not computed on-chain) | Q1: open, unexpired lots of `(item, lot size)` by price then lot id, first *k* | yes, while the market is open |
| 2 | Market search by category | design/11 (auction house), 16 | Q2: items of a category with an open lot, cheapest per size | no |
| 3 | Average price over the last sales | design/16 | Q3: mean per unit over the last *N* sales of an item | no |
| 4 | Hub presence: count and list | design/11 (hub), 09, ADR-0007 | Q4: adventurers whose current hub is H | yes, while in the hub |
| 5 | Title shown under another adventurer's name | design/13, ADR-0007 | Q5: current title of a set of adventurer ids (from Q4) | no |
| 6 | Own displayed title, if titles are in event mode | design/13, D-63 | as Q5 | no |
| 7 | Incoming direct-trade request, if not on the relay | design/16 *Direct trade* | Q7: requests to adventurer id | yes |
| 8 | Leaderboards (rank, trials) | design/08 (v1 "read from chain") | Q6: top *K*, paginated, and "my position" | no |
| later | Elite-clear leaderboard (08), co-op stream (08) | | | |

Events the indexer needs: **five**, each as small as the reads allow.

| Event | Keys (after the selector) | Data | Emitted by | Serves |
|---|---|---|---|---|
| `LotPosted` | `item`, `lot_size` | `lot`, `price`, `expiry` (+ the equipment id for equipment) | posting a lot | 1, 2, 3 |
| `LotClosed` | `lot` | `sold: bool` | buy, withdraw, return of an expired lot | 1, 2, 3 (price and item joined from `LotPosted`; the sale time is the block's) |
| `AdventurerLocated` | `hub` (0: in no hub) | `adventurer` | travel, return, defeat, gate entry | 4 |
| `TitleDisplayed` | `adventurer` | `title`, `tier` | title claim or selection | 5, 6 |
| `RankPromoted` (only if 8 is in the MVP) | `adventurer` | `rank`, `first_attempt` | a successful trial | 8 |

What is deliberately not emitted: the seller of a lot (my lots is a view call), the buyer (no read
uses it), an expiry event (expiry is lazy, design/16: the indexer compares `expiry` with block
time), names (batched view calls). `TradeRequested` exists only if direct trade does not go through
the relay (escalation E-3). The prototype's events (`LotPosted`, `LotClosed`, `AdventurerLocated`)
are this list without `lot_size` as a key and without `expiry`.

## 2. Candidates (AC-2)

Web research done on 2026-09-28. Each claim links the page it was read from; "unverified" marks
what could not be confirmed.

| Candidate | What | Licence | Last release | Self-hosted without a paid service | Fit |
|---|---|---|---|---|---|
| [Apibara](https://github.com/apibara/dna) (DNA v2 + `@apibara/indexer`) | A Rust stream server over a node, and a TS SDK | Apache-2.0 | `dna-starknet/v2.1.4`, 2026-05-18 ([releases](https://github.com/apibara/dna/releases)) | Only if the DNA server is run too. Software Mansion's fork [Starkstream DNA](https://github.com/software-mansion-labs/starkstream-dna) needs JSON-RPC + WebSocket providers, **etcd** and an **object store** (S3/MinIO). The hosted Starknet stream is "provided by a partner" ([docs](https://www.apibara.com/docs/networks/starknet)). Upstream's own requirements are unverified | Custom events: yes. Upstream's future is unclear: Ekubo left it ([README](https://raw.githubusercontent.com/EkuboProtocol/indexer/main/README.md)) |
| [Checkpoint](https://github.com/snapshot-labs/checkpoint) | A TS library, writers per event, GraphQL | MIT | `v0.1.0-beta.80`, 2026-08-19 ([releases](https://github.com/snapshot-labs/checkpoint/releases)) | Yes. Needs RPC + **PostgreSQL** ([quickstart](https://github.com/snapshot-labs/checkpoint-docs/blob/master/guides/quickstart.md)); Docker only to start Postgres | Custom events: yes |
| [Torii](https://github.com/dojoengine/torii) | Dojo's indexer, SQLite, GraphQL + subscriptions, gRPC, SQL | Apache-2.0 | v1.8.16, 2026-05-20 | Yes | **No**: contract types WORLD, ERC20, ERC721, ERC1155; raw events are "dev only" ([configuration](https://book.dojoengine.org/toolchain/torii/configuration)). ADR-0007 dropped it |
| [SubQuery](https://github.com/subquery/subql-starknet) | Node + GraphQL query service + Postgres | GPL-3.0 | node-starknet 6.1.0, 2025-07-23; last push 2025-10-30 | Yes | Stale; `--unfinalized-blocks` (reorg rollback) is for Substrate and Ethereum only ([reference](https://subquery.network/doc/indexer/run_publish/references.html)) |
| [Firehose / Substreams](https://github.com/streamingfast/firehose-starknet) | StreamingFast's block stream; The Graph serves Starknet only through Substreams ([docs](https://thegraph.com/docs/en/supported-networks/starknet-mainnet/)) | Apache-2.0 | v1.1.2, 2026-01-05 | In principle; needs a Starknet RPC **and an Ethereum L1 RPC**, plus substreams and a sink | Heavy multi-service stack |
| Goldsky | Hosted pipelines ([chain page](https://goldsky.com/chains/starknet)) | proprietary | — | **No**: hosted, usage-priced after a $100 credit ([pricing](https://docs.goldsky.com/pricing/summary)) | Recorded, not tried (paid service) |
| Envio, Ponder, rindexer | | | | | EVM (and Fuel) only ([Envio](https://docs.envio.dev/docs/HyperIndex/supported-networks), [Ponder](https://ponder.sh/docs/getting-started/new-project), [rindexer](https://github.com/joshstevens19/rindexer)) |
| **Our own** | Node 24 + JSON-RPC 0.10 + SQLite (`spikes/SPK-11/indexer.ts`) | ours | — | Yes: a node (or an RPC endpoint) and one process | Custom events by construction |

| | Apibara (self-hosted) | Checkpoint | **Our own** |
|---|---|---|---|
| Reorg detection | Server-side canonical chain; the SDK receives `invalidate` ([docs](https://www.apibara.com/docs/getting-started/indexers)) | Compares `parent_hash` with the stored hash, throws `ReorgDetectedError` ([provider.ts](https://raw.githubusercontent.com/snapshot-labs/checkpoint/master/src/providers/starknet/provider.ts)) | Parent hash **and** stored-tip check each step, by hash and commitments (§4); events fetched by block hash |
| Rollback | Triggers write an audit table; rows past the new head reverted in reverse order ([internals](https://www.apibara.com/docs/storage/drizzle-pg/internals)) | Walks back to the last matching hash; deletes rows with `lower(block_range) > lastGoodBlock` ([container.ts](https://raw.githubusercontent.com/snapshot-labs/checkpoint/master/src/container.ts)) | Rows valid over `[_from, _to)`; `DELETE _from > F`, `UPDATE _to = NULL WHERE _to > F`, one transaction |
| Pre-confirmed blocks (Starknet 0.14) | Ingestion enabled in DNA starknet v2.1.2 | Reads `pre_confirmed` | Not indexed (§3) |
| Query interface | None (you own the database) | GraphQL; no subscriptions documented | HTTP JSON; each answer carries the head it was read at |
| Subscription | — | — | Server-sent events: `posted`, `closed`, `rewind`, `head` |
| Processes | Node + DNA + etcd + object store + indexer + Postgres | RPC + indexer + Postgres | RPC + indexer (SQLite file) |
| Lock-in | DNA protocol, uncertain upstream | Beta API | None |

Starknet's reorgs are deep. **2025-09-02**: two reorgs of `ACCEPTED_ON_L2` blocks, about one hour
and about 20 minutes of activity reverted, after v0.14.0
([incident report](https://www.starknet.io/blog/starknet-incident-report-september-2-2025/)).
**2026-01-05**: 18 minutes reverted
([incident report](https://www.starknet.io/blog/starknet-incident-report-january-5-2026/)). In both,
only L1-accepted blocks were safe. The rewind therefore cannot assume a few blocks: the prototype
walks back as far as the hashes disagree, and a production indexer keeps its versioned history
at least down to the last L1-accepted block.

## 3. The prototype (AC-3)

| File | What |
|---|---|
| `src/market.cairo`, `tests/test_market.cairo` | A contract with the game's event shapes: `post` → `LotPosted { #[key] item, lot, quantity, price }`, `buy`/`withdraw` → `LotClosed { #[key] lot, sold }`, `locate` → `AdventurerLocated { #[key] hub, adventurer }`; `post_silent` (the same write, no event) for measuring the event's gas. A lot packed in one felt. 8 tests with budgets |
| `indexer.ts` | The indexer: follow, decode, versioned SQLite tables, rewind, HTTP + SSE |
| `client.ts` | The TypeScript client: `cheapest(item, k)`, `presence(hub)`, `subscribe(onEvent)` |
| `chain.ts`, `run-indexer.ts` | Test plumbing: the node's account, deploy, send; start and stop the indexer process |
| `demo.ts` | The scenario of §4 |
| `bench.ts` | The figures of §5 |
| `with-archive.sh` | `scripts/with-node.sh` with `STATE_ARCHIVE_CAPACITY=full` in the environment, which `devnet_abortBlocks` needs. Devnet reads the option from its environment, so `with-node.sh` is unchanged |
| `probe.ts`, `probe-hash.ts` | What devnet does on an abort (§4) |

How it follows the chain (`indexer.ts`, `step`):

1. Each step reads the chain's head, then re-reads the stored tip's header. If that block is gone,
   or has another hash or other commitments, the indexer walks down its stored blocks until one
   matches the chain (`forkPoint`) and rewinds to it.
2. It takes the next blocks in batches of at most 100. For each one, the header's parent must be
   the stored block below, and the events are fetched **by the block's hash**
   (`starknet_getEvents` with `from_block = to_block = {block_hash}`, the contract's address, and
   the three selectors as keys). Every event must carry that hash.
3. It applies a block's events and records the block in **one SQLite transaction**, then publishes
   to subscribers. A subscriber never hears of a row that a query could not return.
4. If an event contradicts the tables (a `LotClosed` for a lot never posted), it **stops
   advancing** and keeps serving the last consistent head (§4, *fail-stop*).

**Pre-confirmed blocks are not indexed.** The indexer serves only `ACCEPTED_ON_L2` blocks. The
player's own pending action is the client's to show ("saving…", design/11), from its transaction
status. Other players' pre-confirmed actions (a lot posted a second ago) would appear about one
block later. Indexing `pre_confirmed` as a provisional overlay is possible (`starknet_getEvents`
accepts it; devnet answered `{"events":[]}` in `probe.ts`), but was not tried.

Commands (from the repository root):

```
scripts/lock.sh scarb --manifest-path spikes/SPK-11/Scarb.toml build
cd spikes/SPK-11 && snforge test && pnpm install
spikes/SPK-11/with-archive.sh node spikes/SPK-11/demo.ts
spikes/SPK-11/with-archive.sh node spikes/SPK-11/bench.ts 100 100
```

Output of `demo.ts` (trimmed; the lines of the reorgs are in §4):

```
[demo +11.55s] Market deployed at 0x2a40…245 in block 2
[indexer …] serving on http://127.0.0.1:35323, following http://127.0.0.1:27286 from block 2, tip null
[demo +11.87s] subscription: posted {"lot":1,"item":7,"quantity":1,"price":"300","block":3}
…
[demo +12.15s] buy(lot 2) in block 8
[demo +12.22s] subscription: closed {"lot":2,"item":7,"sold":true,"block":8}
[demo +12.23s] query cheapest(item 7, 3) = {"head":{"number":8,"hash":"0x7406…512"},"lots":[{"lot":1,…,"price":"300","block":3},{"lot":3,…,"price":"400","block":5}]}
[demo +12.23s] ok   cheapest open lots of item 7 after lot 2 was bought: [300,400]
[demo +12.23s] ok   presence hub 1 / hub 2: [2,1]
```

## 4. Reorgs (AC-4)

### What devnet simulates, and how faithfully

`devnet_abortBlocks {starting_block_id}` (needs `--state-archive-capacity full`) removes the blocks
from the given one to the tip. The head goes back, the aborted blocks answer `Block not found` by
hash, their transactions are gone, and the state is back to the parent's. The nonce and the lot
counter are rolled back, so **the same lot id is given again**: lot 5 was 120, then 500, then 600
in the scenario. WebSocket subscribers receive `starknet_subscriptionReorg` with
`starting_block_hash/number` and `ending_block_hash/number` (`probe.ts`), as in the specification
([ws API](https://raw.githubusercontent.com/starkware-libs/starknet-specs/master/api/starknet_ws_api.json)).

| Faithful | Not faithful |
|---|---|
| The chain is shorter, then grows again on another branch; the state is the fork point's | **A replacement block gets the same hash as the block it replaces** when it has the same number and parent, although its transaction, event, receipt and state-diff commitments differ (`probe-hash.ts`: both `0x272c…c5c`). On Starknet the block hash commits to those, so a replaced block has another hash. An indexer that trusts hashes alone misses a reorg on devnet. **The first run of `demo.ts` did miss one**: the offline case served the aborted 500 lot instead of the chain's 600. The indexer now keys a block by hash **and** commitments: that is equivalent on Starknet and correct on devnet |
| The reorg notification of the WebSocket API | Aborted transactions are dropped. On Starknet the transactions of an orphaned branch may be included again, in another order |
| | Everything is instantaneous and local. A real reorg comes with an outage, a node that may lag or sit on the minority branch, and hours rather than milliseconds (§2) |

### The three cases (`demo.ts`, all passed)

```
[demo +12.34s] ok   before the reorg the query shows the 120 lot: {"head":{"number":10,…},"lots":[{"lot":5,…,"price":"120","block":9},…]}
[demo +12.35s] devnet_abortBlocks from 9: 2 blocks aborted, chain head now {"number":8,"hash":"0x7406…512"}
[indexer …] rewind to 8 (tip 10 0x7ec61454… no longer on the chain); 1 lots retracted
[demo +12.45s] subscription: rewind {"to":8,"head":{"number":8,"hash":"0x7406…512"},"retracted":[5]}
[demo +12.46s] reorg 1 (live): query consistent 114 ms after the abort was sent (abort call itself 2 ms); subscription rewind heard at 108 ms
[demo +12.48s] ok   after reorg 1 the query is the chain's: {"indexer":[300,400],"chain":[300,400]}
[demo +12.48s] ok   after reorg 1 presence hub 1 = 2 again
[demo +12.57s] ok   replaced block indexed: lots 300, 400, 500: [300,400,500]
[demo +12.70s] aborted block 9; posted 600 (item 7) in block 9 and 90 (item 9) in block 10: the chain is now one block past the indexer's tip, whose hash is gone
[indexer …] rewind to 8 (tip 9 0x4273d128… no longer on the chain); 1 lots retracted
[demo +13.05s] reorg 3 (offline): restart to consistent query in 352 ms (process start included)
[demo +13.08s] ok   after reorg 3 the query is the chain's: {"indexer":[300,400,600],"chain":[300,400,600]}
[demo +13.43s] ok   rebuilt == rewound, answer for answer
[demo +13.48s] timings: {"liveQueryMs":114,"liveSubscriptionMs":108,"offlineRestartMs":352}
[demo +13.48s] all checks passed
```

"The chain's" answer is computed by **view calls** on the contract (`lot(i)` for every lot), not by
the indexer. Time to consistency is measured from the moment the abort is sent until the client's
query returns the rewound state. It is the poll interval (100 ms) plus two or three local RPC
calls. With a WebSocket `newHeads` subscription to wake the loop, the poll would go.

### Can the client be served a state the chain does not hold? (for the audit)

| Window | Bound | Why it is safe |
|---|---|---|
| Between a reorg on the node and the indexer's next step | poll interval + RPC time (114 ms measured locally) | Every answer carries `head {number, hash}`. The client can compare it with the head it sees, and the contract is authoritative for anything that matters: `buy` on a lot the reorg removed **reverts** (`'lot not open'`), and the client moves to the next cheapest lot, the "lost race" path of design/16 |
| The node itself lags or is on the minority branch | the node's | The indexer is only as right as its node. Production runs against a node we operate or one trusted endpoint, and never mixes endpoints within a step (a header from one and events from another) |
| A block replaced between its header and its events | none | Events are fetched by block hash and must carry it. On devnet, where the hash does not change, the next step's commitment check rewinds it |
| A lot id reused after a reorg | — | The subscription's `rewind` lists the retracted lot ids. The client drops what it holds for them and queries again; it never keeps a lot across a rewind by id alone |
| An event that contradicts the tables | — | The indexer stops advancing (fail-stop) and serves the last consistent head: stale, never wrong. It needs an alert (found by `bench.ts` when a lot was posted by `post_silent`, with no event) |

The indexer holds **no secret**. It reads a public chain. The only configuration is the RPC URL,
which may carry a provider's API key; that key goes in the process's environment, never in the
database. It holds **nothing that cannot be rebuilt**: every row is derived from events (the rebuild
check above).

## 5. Hosting and cost (AC-5)

### Measured (`bench.ts 100 100`, devnet on the same machine)

| Figure | Value |
|---|---|
| Catch-up from an empty database | 10 008 events over 108 blocks in **0.99 s** (≈10 100 events/s, process start included), 221 RPC calls |
| Peak memory of the indexer | **119 MB** RSS (Node 24 baseline included) |
| Disk | 0.57 MB for 10 008 events: **≈ 59 bytes per event → ≈ 57 MB per million events** (versioned rows and indexes, write-ahead log checkpointed). Block records: 0.80 MB after 1 128 blocks and 10 028 events, so **≈ 230 bytes per stored block** |
| Blocks without our events | 1 000 empty blocks in 3.04 s: **3.0 ms and 2.02 RPC calls per block** (header + `getEvents`) |
| Live latency | Receipt in starknet.js to `posted` on the subscription, 20 posts, 100 ms poll: **median 58 ms**, min 51, max 64 |
| Idle cost of following | 2 RPC calls per poll (head + tip header): 1.7 M calls a day at 100 ms, 173 k at 1 s, ~0 with a WebSocket `newHeads` wake-up |

Devnet is local and instantaneous. On a public network the per-block time is the RPC round trip,
so catch-up from the deployment block is bounded by the RPC, not by the indexer.

### Sepolia, then mainnet

| | Sepolia | Mainnet |
|---|---|---|
| Process | One Node 24 process (≈120 MB), managed by systemd on the VPS or any small host | Same; a second instance on another host for failover, each with its own database (both rebuildable) |
| Database | SQLite file: tens of MB per million events | SQLite while one writer is enough. Postgres only if several indexer processes must share tables; the versioned schema is the same |
| RPC it needs | JSON-RPC **0.10** (`EMITTED_EVENT` positions, `getEvents` by block hash), HTTP, optionally WebSocket | Same |
| Endpoint | A public endpoint is enough to start: Nethermind's open `free-rpc.nethermind.io/sepolia-juno/` ([docs](https://docs.data.voyager.online/)), rate limits unverified. **Alchemy lists RPC v0_6–v0_9 only** ([FAQ](https://www.alchemy.com/docs/reference/starknet-api-faq)): check 0.10 before choosing it | **Our own Juno node**: 4 cores, 8 GB+ RAM, NVMe ([hardware](https://juno.nethermind.io/hardware-requirements)); **85.6 GB pruned** or 453.9 GB full as of 2026-07-31 ([snapshots](https://juno.nethermind.io/snapshots)); serves RPC 0.10.1 and WebSocket with reorg notifications. Pathfinder: 4 cores, 16 GB, 1 TB SSD recommended |
| RPC cost if hosted | At 1 s polling and 2 calls per block: ≈ 175 k calls/day ≈ 5.2 M/month. At Alchemy's 20 CU per `getEvents` ([CU costs](https://www.alchemy.com/docs/reference/compute-unit-costs)) that is ≈ 105 M CU/month, above the free 30 M, ≈ **$40/month** pay-as-you-go at $0.525 per M CU ([pricing](https://www.alchemy.com/pricing)). The per-call CU of `blockHashAndNumber` and `getBlockWithTxHashes` is taken as 20: upper bound, unverified | A node of our own has no per-call cost. A hosted one costs the same order as Sepolia, plus the rebuild's burst |

### Rebuild from the chain

1. Stop the indexer. Delete its database file (with `-wal` and `-shm`).
2. Start it with `--from <the contract's deployment block>`: it applies every block from there, and
   serves queries whose `head` says how far it has got.
3. The client treats answers whose `head` is far behind the chain as "the market is loading".

Measured on devnet: 321 ms for the scenario's chain, and the rebuilt answers were identical to
those of the indexer that lived through three reorgs. On mainnet, with 2 calls per block from the
deployment block, a rebuild months after launch is millions of calls. The production indexer must
therefore catch up **below the last L1-accepted block** with `starknet_getEvents` over block
*ranges* (1 000 events per page, by the contract's address). That is about one call per thousand
events, and those blocks cannot reorg. It follows block by block only above that block. **Not
prototyped.**

## 6. What ENG-01 must freeze (events as an API)

1. **Names and layouts.** The first key is the selector of the event's *name*: renaming an event,
   or reordering, retyping, or moving a field between keys and data, breaks the indexer and every
   rebuild of the history. A change is a **new event name**; the indexer decodes both forever.
2. **Completeness.** Every path that changes an indexed thing emits its event: posting, buying,
   withdrawing, and returning an expired lot all emit. A lot that appears or closes without its
   event stops the indexer (fail-stop, §4). The prototype's `post_silent` showed it.
3. **Identifiers.** The ids in events are the storage ids (lot, adventurer, hub, item). Ids handed
   out by a counter are **reused after a reorg**: clients and the indexer never trust an id alone
   across a rewind.
4. **Integer widths.** Whatever reaches a price or a sum must fit what the indexer computes in.
   SQLite `INTEGER` is 64-bit signed; JSON numbers are exact below 2^53. The prototype sends prices
   as strings. ENG-01 states the width of gold amounts, and the production indexer keeps them exact.
5. **Keys** are what a third party filters by (`item` and `lot_size` for lots, `hub` for presence,
   `adventurer` for titles). They cost the same as data.
6. **Stable addresses.** The indexer filters by contract address; upgrades by class replacement
   (ADR-0007, NS-4) keep it. A new contract address is a new source in the indexer's configuration,
   with its deployment block.
7. **Size.** Measured on devnet: `LotPosted` (5 felts including the selector) costs **35 840 L2 gas**
   on a `post` of ~1.68 M L2 gas, about 2 %; no L1 data gas. Linear by felt, that is ≈ 7 200 L2 gas
   per felt: an estimate, not a measure of the other events.

## 7. Open questions

| # | Question | For |
|---|---|---|
| E-1 | Leaderboards in the MVP? design/08 says v1 has them "read from chain"; design/09, ADR-0004 and ADR-0007 put `leaderboard` after the MVP. Decides `RankPromoted` | owner |
| E-2 | Hub presence: the relay (design/02 D-03, Q-09) or `AdventurerLocated` through the indexer (ADR-0007)? One transport | owner / design |
| E-3 | Titles: is the displayed title written to storage (view call) or only emitted (D-63 event mode, then even the player's own title needs the indexer)? Direct trade: how does the other player learn of a request? | design/13, design/16 |
| E-4 | What is "one item" on the market for equipment (base, rarity, identified or not)? Decides `LotPosted.item` | design/16 |
| E-5 | Average price: over how many sales, mean or median? | design/16 |
| — | Pre-confirmed overlay, WebSocket wake-up, range catch-up below L1 acceptance, alerting on fail-stop | the indexer track |
