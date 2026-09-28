# [Opus 5.5] SPK-11 — Indexer spike

## Summary
NS-2 of ADR-0007 is answered: **write our own indexer**. It is one Node 24 process following
Starknet JSON-RPC 0.10, with versioned SQLite tables, HTTP queries and server-sent-event
subscriptions. The runner-up is Checkpoint (MIT, beta, needs Postgres); it was not prototyped.

- `docs/research/SPK-11-indexer.md` covers:
  - the reads, classified: 44 reads, 8 go through the indexer in the MVP, 5 events cover them;
  - the candidates, with sources;
  - the prototype and the reorg results;
  - hosting and cost, and the rebuild procedure;
  - what ENG-01 must freeze.
- `spikes/SPK-11/` holds:
  - a Market contract with game-shaped events (`LotPosted`, `LotClosed`, `AdventurerLocated`);
  - the indexer and a TypeScript client (a cheapest-lot query, hub presence, a lots subscription);
  - the reorg scenario (`demo.ts`) and the cost bench (`bench.ts`).
- Main finding: on devnet 0.10.0, a block that replaces an aborted one keeps the aborted block's
  hash, although its commitments differ. The first run of the scenario therefore missed an offline
  reorg. The indexer now identifies a block by its hash **and** its commitments.

Pull request: https://github.com/bal7hazar/grimworld/pull/31. CI is green on c0b1a41. Not merged.

## Files changed
- `docs/research/SPK-11-indexer.md`: the research document (AC-1 to AC-5, recommendation, ENG-01 freeze list).
- `spikes/SPK-11/Scarb.toml`, `Scarb.lock`, `.gitignore`: the Cairo package (Cairo 2.19, snforge 0.61).
- `spikes/SPK-11/src/lib.cairo`, `src/market.cairo`: the Market contract. Its events have the game's shapes; `post_silent` (no event) exists to measure the event's gas.
- `spikes/SPK-11/tests/test_market.cairo`: 8 tests, each with a budget of ceil(1.05 × measured).
- `spikes/SPK-11/indexer.ts`: the indexer. It follows the chain, decodes events, keeps versioned tables, rewinds, and serves HTTP and SSE.
- `spikes/SPK-11/client.ts`: the TypeScript client.
- `spikes/SPK-11/chain.ts`, `run-indexer.ts`: plumbing (account, deploy, send; start and stop the indexer).
- `spikes/SPK-11/demo.ts`: scenario for AC-3 and AC-4.
- `spikes/SPK-11/bench.ts`: gas, catch-up, disk, empty blocks, latency.
- `spikes/SPK-11/probe.ts`, `probe-hash.ts`: what devnet does on an abort.
- `spikes/SPK-11/with-archive.sh`: `scripts/with-node.sh` with `STATE_ARCHIVE_CAPACITY=full` exported, which devnet needs to abort blocks.
- `spikes/SPK-11/package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`: starknet.js 10.8.0.

## Commands run
```
$ scripts/lock.sh scarb --manifest-path spikes/SPK-11/Scarb.toml build
    Finished `dev` profile target(s) in 3 seconds

$ cd spikes/SPK-11 && snforge test
[PASS] …test_buy_closes_and_emits (l2_gas: ~1680130)
[PASS] …test_post_packs_the_largest_values (l2_gas: ~1407630)
[PASS] …test_locate_emits (l2_gas: ~368230)
[PASS] …test_post_stores_and_emits (l2_gas: ~1466400)
[PASS] …test_buy_unknown_lot_fails (l2_gas: ~343100)
[PASS] …test_post_silent_stores_the_same (l2_gas: ~1357270)
[PASS] …test_buy_twice_fails (l2_gas: ~1651710)
[PASS] …test_withdraw_closes_and_emits (l2_gas: ~1541690)
Tests: 8 passed, 0 failed

$ scripts/with-node.sh node spikes/SPK-11/probe.ts          # without the archive
abortBlocks from 2: {"error":{"code":-1,"message":"The abort blocks feature requires state-archive-capacity set to full."}}
$ spikes/SPK-11/with-archive.sh node spikes/SPK-11/probe.ts
abortBlocks from 2: {"result":{"aborted":["0x64c6…1d8","0x426a…8c8"]}}
head after abort: {"block_hash":"0x41b1…f61","block_number":1}
block 2 by old hash: {"error":{"code":24,"message":"Block not found"}}
ws: {"method":"starknet_subscriptionReorg","params":{…,"result":{"starting_block_hash":"0x426a…8c8","starting_block_number":2,"ending_block_hash":"0x64c6…1d8","ending_block_number":3}}}

$ spikes/SPK-11/with-archive.sh node spikes/SPK-11/probe-hash.ts
original    block_hash 0x272c0c44…c5c, transaction_commitment 0x1b36…6ce, event_commitment 0x73d5…dde
replacement block_hash 0x272c0c44…c5c, transaction_commitment 0x63aa…5f4, event_commitment 0xdf18…3b1
same number: true; same hash: true; same transactions: false

$ spikes/SPK-11/with-archive.sh node spikes/SPK-11/demo.ts     # first run, before the fix
… offline reorg: Error: timeout; last value {…"lots":[…{"lot":5,…,"price":"500","block":9}]}   (chain had 600)

$ spikes/SPK-11/with-archive.sh node spikes/SPK-11/demo.ts     # after keying blocks by hash + commitments
[demo +12.23s] ok   cheapest open lots of item 7 after lot 2 was bought: [300,400]
[demo +12.23s] ok   presence hub 1 / hub 2: [2,1]
[demo +12.34s] ok   before the reorg the query shows the 120 lot
[demo +12.34s] ok   the subscription heard lot 5 posted
[demo +12.35s] devnet_abortBlocks from 9: 2 blocks aborted, chain head now {"number":8,…}
[indexer …] rewind to 8 (tip 10 0x7ec61454… no longer on the chain); 1 lots retracted
[demo +12.45s] subscription: rewind {"to":8,"head":{"number":8,…},"retracted":[5]}
[demo +12.46s] reorg 1 (live): query consistent 114 ms after the abort was sent; subscription rewind heard at 108 ms
[demo +12.48s] ok   after reorg 1 the query is the chain's: {"indexer":[300,400],"chain":[300,400]}
[demo +12.48s] ok   after reorg 1 presence hub 1 = 2 again
[demo +12.57s] ok   replaced block indexed: lots 300, 400, 500: [300,400,500]
[indexer …] rewind to 8 (tip 9 0x4273d128… no longer on the chain); 1 lots retracted
[demo +13.05s] reorg 3 (offline): restart to consistent query in 352 ms (process start included)
[demo +13.08s] ok   after reorg 3 the query is the chain's: {"indexer":[300,400,600],"chain":[300,400,600]}
[demo +13.09s] ok   after reorg 3 item 9 is the chain's: [90,100]
[demo +13.41s] rebuild from block 2 into an empty database: 321 ms
[demo +13.43s] ok   rebuilt == rewound, answer for answer
[demo +13.48s] all checks passed

$ spikes/SPK-11/with-archive.sh node spikes/SPK-11/bench.ts 100 100
sent 100 transactions × 100 calls in 21.7 s; chain tip 109
10008 events over 108 blocks in 0.99 s (10099 events/s, process start included); database 0.57 MB = 59 bytes per event; peak RSS 119 MB; 221 RPC calls
1000 blocks without our events: 3.04 s (3.04 ms per block), 2022 RPC calls (2.02 per block)
receipt → subscription, 20 posts, poll 100 ms: median 58 ms, min 51, max 64
database after the last stop (write-ahead log checkpointed): 0.80 MB

$ spikes/SPK-11/with-archive.sh node spikes/SPK-11/bench.ts 2 10    # gas table, like-for-like post
post 2085920 / post_silent 1648080 / post again 1683920 / buy 1181440 / withdraw 1181440 / locate 1026560 / post ×2 2512480 / locate ×2 1237760 (l2 gas)

$ scarb fmt   (CI's first run failed on formatting of the two Cairo files; fixed in c0b1a41)
$ gh pr checks 31 --watch --interval 30
cairo (spikes/SPK-11) pass · cairo (contracts) pass · cairo (spikes/SPK-5) pass · cairo (spikes/SPK-5b) pass · client pass · discover pass · tooling pass
```

## Cost
Gas measured from devnet receipts (the whole invoke transaction, account validation included). snforge figures are per test, with declare and deploy included.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| `post` (LotPosted), devnet receipt | — | 1 683 920 l2 / 320 l1 data | — | 2 085 920 for the first post (writes `lot_count` from zero) |
| `post_silent` (same write, no event) | — | 1 648 080 l2 / 320 l1 data | — | measurement only |
| **LotPosted event** (5 felts) | — | **35 840 l2**, 0 l1 data | — | post − post_silent, like for like |
| `buy` / `withdraw` (LotClosed) | — | 1 181 440 l2 / 256 l1 data | — | |
| `locate` (AdventurerLocated) | — | 1 026 560 l2 / 128 l1 data | — | the second `locate` in one transaction adds 211 200 |
| test_post_stores_and_emits | — | 1 466 400 | 1 539 720 | snforge |
| test_post_silent_stores_the_same | — | 1 357 270 | 1 425 134 | snforge |
| test_post_packs_the_largest_values | — | 1 407 630 | 1 478 012 | snforge |
| test_buy_closes_and_emits | — | 1 680 130 | 1 764 137 | snforge |
| test_withdraw_closes_and_emits | — | 1 541 690 | 1 618 775 | snforge |
| test_buy_twice_fails | — | 1 651 710 | 1 734 296 | snforge |
| test_buy_unknown_lot_fails | — | 343 100 | 360 255 | snforge |
| test_locate_emits | — | 368 230 | 386 642 | snforge |
| Indexer catch-up, 10 008 events / 108 blocks | — | 0.99 s, 221 RPC calls | — | devnet, local |
| Indexer peak memory | — | 119 MB RSS | — | Node 24 baseline included |
| Indexer disk | — | ≈ 59 B per event (≈ 57 MB per million), ≈ 230 B per stored block | — | SQLite, WAL checkpointed |
| Following blocks without our events | — | 3.0 ms, 2.02 RPC calls per block | — | |
| Live latency (receipt → subscription) | — | median 58 ms (51–64) | — | 100 ms poll |
| Time to consistency after a reorg | — | 114 ms query, 108 ms subscription (live); 352 ms (restart after an offline reorg) | — | |

## Acceptance criteria
- [x] **AC-1**: research §1 lists the 44 classified reads, the 8 indexer reads with their query shapes, and the 5 events with their keys and data (`LotPosted`, `LotClosed`, `AdventurerLocated`, `TitleDisplayed`, and `RankPromoted` if leaderboards are in the MVP).
- [x] **AC-2**: research §2 compares Apibara, Checkpoint, Torii, SubQuery, Firehose/Substreams, Goldsky, Envio, Ponder and rindexer against our own. Each has a licence, last release and self-hosting status, with a source link. §0 makes the recommendation.
- [x] **AC-3**: `demo.ts` deploys, indexes, and serves `cheapest(item 7, 3)` and presence over HTTP, and the `posted`/`closed` subscription over SSE, to `client.ts` (output above).
- [x] **AC-4**: `demo.ts` covers three reorgs: live, same-height replacement, and offline. In each the indexer rewinds, and the query and subscription show it. The result is checked against the contract's view calls. Measured: 114 ms / 108 ms / 352 ms.
- [x] **AC-5**: research §5 gives the measured process, memory and disk figures, the RPC calls per block and per poll, the Sepolia and mainnet options (Juno 85.6 GB pruned, hosted RPC ≈ $40/month at 1 s polling), and the rebuild procedure.

## Deviations from the brief
- **Runner-up not prototyped.** Checkpoint needs a PostgreSQL server. The machine has none and no Docker, and installing one is outside the brief, so per the brief I recorded it and did not work around it.
- **The node is started through `spikes/SPK-11/with-archive.sh`**, which exports `STATE_ARCHIVE_CAPACITY=full` and then calls `scripts/with-node.sh` unchanged. `devnet_abortBlocks` refuses to run without it, and the profile refuses an inline `VAR=… scripts/with-node.sh`.
- **The contract has an extra entrypoint, `post_silent`,** used only to measure the gas of the `LotPosted` event.
- **A benchmark run broke the foreground rule.** The first `bench.ts` hung for 15 minutes and the harness moved it to the background. I stopped it right away (no result was used). The cause was the benchmark, not the indexer: it withdrew a lot posted without an event, so the indexer stopped advancing (see Open questions). Every wait in `bench.ts` now has a timeout.
- **Pre-confirmed blocks are not indexed.** The trade-offs are in research §3.
- **Catch-up over block ranges below L1 acceptance is not built.** It is described in research §5.

## Escalations
- **E-1: leaderboards in the MVP?** design/08 says v1 has them, "read from chain". design/09, ADR-0004 and ADR-0007 put `leaderboard` after the MVP. This decides whether `RankPromoted` exists.
- **E-2: hub presence transport.** design/02 D-03 and Q-09 say an off-chain relay. ADR-0007 says the indexer, through `AdventurerLocated`. One should be chosen.
- **E-3: titles, and direct-trade requests.**
  - Is a displayed title stored (a view call) or only emitted (D-63 event mode)? If only emitted, even the player's own title needs the indexer.
  - How does a player learn of an incoming trade request: the relay, or an event?
- **E-4: what "one item" is on the market for equipment**, and the average-price window (N sales, mean or median): design/16.
- **Suggestion for `scripts/with-node.sh`** (shared, not edited): a flag, or a documented environment pass-through, for devnet options such as `STATE_ARCHIVE_CAPACITY`. The indexer track will need it for its reorg tests.

## Open questions
- **Devnet hashes.** A replaced block keeps its hash on devnet 0.10.0. Any reorg test on devnet, including the production indexer's CI, must compare commitments as well as hashes, or it will pass for the wrong reason. This is worth reporting upstream to 0xSpaceShard.
- **Fail-stop.** On an event that contradicts its tables, the indexer stops advancing and keeps serving the last consistent head. Production needs an alert for this. ENG-01 must guarantee completeness: every path that changes an indexed thing emits its event.
- **Lot ids after a reorg.** Ids handed out by a counter are reused after a reorg (lot 5 was 120, then 500, then 600 in the scenario). The client must drop what it holds for the retracted ids and query again.
- **Price width.** The prototype stores prices as SQLite INTEGER (64-bit signed) and sends them as strings. ENG-01 fixes the width of gold amounts.
- **Research sources.** Part of the candidate research came from GitHub API pages; claims that could not be confirmed are marked "unverified" in the document. Alchemy lists no RPC 0.10 support: check that before choosing it.

## Fix loop 1

This round answers the `[GPT-6-Sol]` audit (lenses S, Q). The model is Opus 5.5, as in my session.
Commits `4020a40`, `8d28537` (after `c0b1a41`). CI is green on `8d28537`: `cairo (spikes/SPK-11)`, `cairo (contracts)`, `cairo (spikes/SPK-5)`, `cairo (spikes/SPK-5b)`, `client`, `discover` and `tooling` all pass. The PR is not merged.

The evidence is committed real output:
- `spikes/SPK-11/results/demo.txt`: 22 `ok` checks, `all checks passed`.
- `spikes/SPK-11/results/bench.txt`.

The criterion used throughout: an answer with rows is **wrong** if it differs from the chain's state **at the answer's own head block**, computed by view calls `lot(i)` at that block. An orphaned block counts as wrong.

| # | Finding | Fix | Evidence |
|---|---|---|---|
| 1 (blocker) | Queries could serve a state the chain removed: before the first `step()` after a restart, and between a live reorg and the next poll. The client did not compare the head | **R1**: status `loading` until the stored tip is checked against the chain, and `rewinding` while a rewind runs. In both, queries answer 503 with the state and no rows. **R2**: every answer carries `head {number, hash, commitments}`. **R3** (`client.ts`, `check`/`verify`): an answer is accepted only if the indexer is `ok`, the client's own node still has the head block with the same hash and commitments (read after the answer), and it is at most 5 blocks behind the tip | **Restart** on an orphaned tip (block 9) with the node slowed to 50 ms per call: 52 answers sampled from the first one, 37 `loading`, 15 with rows, **0 wrong** (14 were the chain's state 2 blocks back, within the lag), latest state at 609 ms. **Live** reorg at a 500 ms poll: 40 answers, **37 raw answers orphaned, 0 accepted wrong**, latest state accepted at 526 ms. `demo.txt` lines "live reorg, sampled…" and "restart with a 50 ms node…" |
| 2 (major) | A reconnecting subscription could keep an orphaned lot. There was no cursor or resync, and events carried no block identity | **R4**: every connection starts with a `reset` snapshot of the item's open lots, and every rewind is followed by a new `reset`. `posted`, `closed` and `head` carry `{number, hash, commitments}`. `LotCache` is rebuilt from each `reset` and is not `ready` after a disconnection or a `rewind`. It is shown only if its head passes R3 | Cache disconnected, lot 5 posted at 500, aborted, lot 5 reposted at 650, lot 3 withdrawn, reconnected: the accepted cache is `1:300 5:650`, the chain's. In the live reorg the `reset` **reopened lot 1**, whose purchase was aborted; the old `retracted` list alone could not do that. `cacheWrong 0` over the live window |
| 3 (major) | The fail-stop claim for a missing event was unsupported | Completeness is stated as a **contract invariant for ENG-01** (research §6). Two detectable checks are added for lots. **Gap:** a `LotPosted` whose id is not the counter + 1 halts the indexer. **Reconciliation:** at each new tip, the view call `lot_count` at that block is compared with the indexed counter. The counter never changes unannounced: `skip_lots` emits `LotCountSet`. In state `halted`, queries answer 503 and subscribers receive `status halted`. The claim is narrowed: a missing `LotClosed`, `AdventurerLocated` or title event is **not** detected without a further counter, and research §6 says so | `post_silent` on the running indexer: `halted: lot_count on the chain at block 12 is 8, indexed 7`, queries 503, the cache is not ready. A rebuild over the same chain: `halted: LotPosted 9 in block 13, expected lot 8` |
| 4 (major) | u64 prices and ids: SQLite refused values above 2^63-1, and ids went through JS `Number` | Lot ids and prices are stored as 16-digit hex text, which is lossless and ordered like the numbers. They leave as decimal strings. A value that is not a u64 halts the indexer | Lots `2^53+1`, `2^63`, `2^64-1` at prices `2^64-1`, `2^63`, `2^53+1`, lot `2^63` bought: the query equals the chain's view calls, in order. Then aborted: item 77 empty, as on the chain, and the next lot id is 7, the chain's. Cairo test `test_skip_lots_announces_and_moves_the_counter` reaches lot `2^64-1` |
| 5 (major) | The indexer inherited `NODE_ACCOUNT_PRIVATE_KEY` and logged its full RPC URL | `run-indexer.ts` spawns it with `env: { INDEXER_RPC_URL }` only. The URL comes from the environment, not argv. Logs show `http://host:port/…(redacted)` when the URL has a path, query or credentials. The claim is qualified: the indexer holds no signing key, and the provider key is in its environment only (research §8) | `environment: INDEXER_RPC_URL` checked. The demo ran with the URL `…/?key=spk11-fake-provider-key`, and no log line holds that key or the node account's private key (both checked) |
| 6 (major) | AC-5's figures had no committed output, and only LotPosted's gas was reported. The RPC cost was wrong | `results/bench.txt` is committed. Silent variants for all three events give receipt deltas, like for like. RPC calls are counted per method. The projection uses Alchemy's per-method CU (`blockHashAndNumber` 10, verified on their page; the other methods 20) and is kept apart from the measured values in research §5 | Event gas: **LotPosted 35 840, LotClosed 65 600, AdventurerLocated 25 600** L2 gas, no L1 data gas. Catch-up of 10 000 events in 1.08 s, 127 MB peak RSS, 127 B/event (up from 59, the cost of lossless text). Blocks without our events: 2.03 calls per block. Idle: 19.2 calls/s at a 100 ms poll. Projection: ≈ $39/month at a 1 s poll, with the block rate assumed |
| 7 (major) | AC-1 gave counts instead of the reads | Research §1 lists all 44 reads with class, source section, reason and MVP status, then the queries and the events | Research §1 table |
| 8 (minor) | Apibara mixed upstream, the fork and hosted | Three rows: upstream (etcd and object store **unknown**), the Starkstream fork (etcd and object store per its README), and hosted streams (key or payment **unknown**) | Research §2 |

Found while fixing (the tests did their job):
- A first run of the new checks failed on the reconnect case. The demo's "caught up" wait compared hashes only, and devnet re-uses a replaced block's hash, so the reconnect snapshot was the indexer's pre-rewind state. The freshness rule, which compares commitments, would have rejected that cache. The demo now waits and accepts through the rule.
- The same run counted 28 restart answers as wrong. They were the chain's state two blocks back, so the criterion was too strict (a state the chain held, within the lag), not the indexer wrong. The criterion is now "the chain's state at the answer's head".

Cost changes of this round (snforge, `ceil(1.05 × measured)`). The contract gained `withdraw_silent`, `locate_silent`, `skip_lots`, `lot_count` and `LotCountSet`, and the emission moved out of `close`:

| Test | Before | After | Budget |
|---|---|---|---|
| test_post_stores_and_emits | 1 466 400 | 1 466 100 | 1 539 405 |
| test_post_silent_stores_the_same | 1 357 270 | 1 357 270 | 1 425 134 |
| test_post_packs_the_largest_values | 1 407 630 | 1 407 330 | 1 477 697 |
| test_buy_closes_and_emits | 1 680 130 | 1 680 930 | 1 764 977 |
| test_withdraw_closes_and_emits | 1 541 690 | 1 542 490 | 1 619 615 |
| test_buy_twice_fails | 1 651 710 | 1 653 620 | 1 736 301 |
| test_buy_unknown_lot_fails | 343 100 | 344 210 | 361 421 |
| test_locate_emits | 368 230 | 369 630 | 388 112 |
| test_withdraw_silent_closes_without_event | — | 1 590 160 | 1 669 668 |
| test_locate_silent_does_nothing | — | 279 020 | 292 971 |
| test_skip_lots_announces_and_moves_the_counter | — | 2 033 330 | 2 134 997 |
| test_lot_count_counts_every_lot | — | 2 018 950 | 2 119 898 |

Still open after this round:
- `LotClosed`, presence and titles have no completeness check (research §6). ENG-01 should add an `open_lot_count` view.
- The live window is bounded by the poll interval (526 ms at 500 ms). A WebSocket `newHeads` wake-up would shorten it; not built.
- Both the indexer and the client trust their nodes: R3 cannot help if both follow a minority branch (research §4).
- Superseded by this round, in the sections above: the 59 B/event figure and the "≈ $40/month at 20 CU per call" projection. The Open questions entry on price width is resolved (lossless text).

## Fix loop 2

This round answers the `[GPT-6-Sol]` re-audit: findings 4, 5, 6 and 8 were resolved; 1, 2, 3 and 7 were verified by the orchestrator. The model is Opus 5.5, as in my session.

Commits:
- `4d0f126`: merge of `origin/main`, for `docs/decisions/2026-09-28-indexer-scope.md`.
- `bc060ac`: code and results.
- `915833d`: research.

**CI is green on `915833d`**: `cairo (spikes/SPK-11)`, `cairo (contracts)`, `cairo (spikes/SPK-2)`, `cairo (spikes/SPK-2/account)`, `cairo (spikes/SPK-2/native)`, `cairo (spikes/SPK-5)`, `cairo (spikes/SPK-5b)`, `client`, `discover` and `tooling` all pass. The PR is not merged.

Evidence, committed under `spikes/SPK-11/results/`:
- `demo.txt`: 27 `ok` checks, `all checks passed`.
- `snapshot.txt`: `ok complete snapshot beyond one page and beyond 10 000 lots`.
- `bench.txt`: rerun with the new indexer.

| # | Finding | Fix | Evidence |
|---|---|---|---|
| 1 (major) | `verify()` read the answer's block and then the tip, so a reorg between the two reads passed an orphaned answer | `client.ts`, `verify`: the tip first (lag check), then **the answer's block last** (`blockIs`, hash and commitments). The guarantee is stated as of that last read, in `client.ts` and research R3. A test hook, `between`, runs between the two reads | `demo.txt` section V: block 9, holding lot 5 at 111, aborted between the reads. The old order says `"fresh"` with lots `5:111 1:300 3:400`, which is the defect reproduced. The new order says `"block 9 is gone"` |
| 2 (major) | An unplanned stream close left `LotCache` ready, `sorted()` exposed it, and the snapshot was capped at 10 000 | **Lifecycle:** `LotCache` owns its stream (`connect()` returns `close`). Any end of the stream (its owner, the server or the network) makes it `ready: false`, `status: disconnected`. **Read API:** `read()` is the only access to the lots; `sorted()` is gone. It takes lots and head together and applies R3. A block's events are applied together with its `head` event. **Snapshot:** it is paged (`reset-begin {total}`, `reset-page` of 1 000, `reset-end`), written in one synchronous run, with no cap. The cache becomes ready only if the count matches the announced total | `demo.txt` section E: the indexer process stopped with nobody touching the cache, and it went `{"ready":false,"status":"disconnected"}` with `read()` refusing. `snapshot.txt`: 10 050 lots, frames `reset-begin 1, reset-page 11, reset-end 1`, received in 82 ms; the cache shows 10 050 lots, **identical lot for lot** to the chain's view calls |
| 3 (major) | Reconciliation was keyed by height (`reconciledAt`) and not cleared on rewind, and a new tip was served before its check | **Keyed by identity:** a served block (`served`), known by hash and commitments. It is set only after `reconcile(block)` passes, and cleared (`null`) on every rewind. **Rows withheld:** queries, snapshots and the stream are read **as of the served block** (`_from <= B < _to`). A newly applied block's events wait in `pending` until it is served. `reconcile` re-reads the block after its call, because devnet re-uses hashes. Research R6 | `demo.txt` section H: block 12 (lot 8 at 900) was served, then aborted and replaced at height 12 by `post_silent`, with the same hash (`true` in the log). The indexer halted: `lot_count on the chain at block 12 is 8, indexed 7`. Of the 48 answers sampled meanwhile, **0 were at the replacement's identity** (41 at the old block 12, which R3 rejects; 3 `rewinding`; 3 at block 11; 1 `halted`). A rebuild then halted on the id gap. Under fix loop 1's code, the same height would have skipped the check |
| 7 (major) | Read classes, events, queries, MVP flags and totals did not follow the PM's scope decision | Research §1, §6, §7 apply `docs/decisions/2026-09-28-indexer-scope.md`. **Rankings** (#39, #40): later, with `TrialPassed`, `DungeonCleared`, `RankReached` emitted from the MVP. **Hub membership** (#20): from the indexer; live movement and chat (#21) go to the relay, later. **Titles** (#23, #25): event only. **Trade invitations** (#37): `TradeOpened {#[key] invited}` / `TradeClosed`, a subscription filtered on the invited account, a 10-minute expiry on block time, declinable; the trade itself stays stored (#36, V). **Market key** (#31): base, requirement, rarity, identified (boss items one key each; balances their item id), each lot with its modifiers (`LotPosted`: `market_key`, `lot_size` keys; `equipment`, `modifiers` data). **Average** (#32, Q3): 7 days per key and lot size, hidden under 5 sales. E-1 to E-4 are closed | Research §1: totals recounted from the table as 16 V, 17 S, 10 I (**7 in the MVP**: #20, 23, 25, 30, 31, 32, 37), 1 relay = 44 (fix loop 1's "19 V" was miscounted). 6 MVP queries, 9 events for ENG-01 (6 MVP + 3 ranking inputs), including the trade invitation. §6 item 8 freezes the list |

Figures that moved (rerun, `bench.txt`):
- 137 B/event (was 127).
- 119 MB peak RSS.
- 1.13 s for 10 000 events.
- 2.04 RPC calls per empty block.
- Each new tip reads its header one more time (the re-read after reconciliation). The projection is now ≈ $43/month at a 1 s poll and an assumed 6 s block; it was ≈ $39.
- The Cairo contract and its tests did not change in this round (snforge budgets as in fix loop 1).

Still open:
- Missing `LotClosed`, presence, title and ranking events are still not detectable (research §6). ENG-01 should add `open_lot_count` and `trade_count` views.
- The six non-prototyped events (`TitleDisplayed`, `TradeOpened`, `TradeClosed`, `TrialPassed`, `DungeonCleared`, `RankReached`) and the market key's encoding are specified, not implemented.
- R3 holds only as of its last read. The contract (R5) covers a reorg after it.
