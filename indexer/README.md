# @grimworld/indexer

The indexer of Grim World (D-130; IDX-01a): one Node 24 process that follows a Starknet node over
JSON-RPC 0.10, decodes the nine events frozen by ENG-01 (`Hub`: AdventurerLocated, TitleDisplayed,
TrialPassed, DungeonCleared, RankReached; `Market`: LotPosted, LotClosed, TradeOpened, TradeClosed)
and keeps them in SQLite tables whose rows are versioned by block (`_from`, `_to`). It answers the
queries of the game's screens over HTTP and streams three of them as subscriptions (IDX-01b); its
client library, `@grimworld/indexer/client`, applies the freshness rule. It is never a source of
simulation state (D-133): everything in it is rebuilt from the chain.

```
INDEXER_RPC_URL=<url> node src/main.ts run     --hub <address> --market <address> --from <block> --db <file> [options]
INDEXER_RPC_URL=<url> node src/main.ts rebuild --hub <address> --market <address> --from <block> --db <file> [options]
```

(`pnpm build` emits `dist/main.js`, the same program.)

| Option                                       | Default                      |                                                                                                                                                                                        |
| -------------------------------------------- | ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--from <block>`                             | required                     | **The deployment block of the two contracts.** A database remembers the block it was built from; `run` on it with another configuration and `rebuild --from` another block are refused |
| `--db <file>`                                | required                     | The SQLite file (WAL: also `-wal`, `-shm`)                                                                                                                                             |
| `--port`, `--host`                           | 0 (any free port), 127.0.0.1 | `GET /head`, `GET /stats`                                                                                                                                                              |
| `--poll <ms>`                                | 1000                         | Wait when idle or after a failed step; at least 1                                                                                                                                      |
| `--batch <blocks>`                           | 100                          | Blocks applied per step; at least 1                                                                                                                                                    |
| `--depth <blocks>` or `l1`                   | `l1`                         | History kept below the tip (`l1`: down to the last block accepted on L1). A reorg below it halts                                                                                       |
| `--recheck <blocks>`, `--recheck-every <ms>` | 10, 10000                    | The last blocks below the tip read again, at most that often: `recheck` header reads each time (1 call per second on average at the defaults)                                          |
| `--lot-count`, `--trade-count`               | 0                            | The contracts' counters at the block before `--from`: 0 at deployment, which is the only supported start (below)                                                                       |
| `--max-subscriptions <n>`                    | 512                          | Subscriptions open at once in the process; one more is refused with 429                                                                                                                |
| `--max-subscriptions-per-client <n>`         | 16                           | Subscriptions open at once from one remote address (an HTTP/1.1 connection carries one stream: the cap per connection is kept per address). Behind a proxy, every client is the proxy  |
| `--max-buffered <bytes>`                     | 524288 (512 KiB)             | Unsent bytes one stream may hold; past it, the stream is destroyed at once. With `--max-subscriptions`, the bound on the streams' memory: 512 × 512 KiB = 256 MiB by default           |
| `--stall <ms>`                               | 30000                        | A stream whose socket accepted no write for this long (its reader stopped) is destroyed                                                                                                |
| `--keep-alive <ms>`                          | 15000                        | A comment frame (`: keep-alive`) on a stream idle this long                                                                                                                            |
| `--allow-origin <origin>`                    | none (the same origin only)  | Repeatable. A request from this origin is answered with `access-control-allow-origin`, JSON and event streams alike                                                                    |
| `--rpc <url>`                                | `INDEXER_RPC_URL`            | Prefer the environment: argv is visible to every user of the machine                                                                                                                   |

The RPC URL may carry a provider's key, in its host as well as its path or query: no part of it is
ever logged. The log names it `rpc <8 hex>`, the first 8 hex digits of the URL's sha256, which tells
two configurations apart. A URL that is not http(s) is refused at start without printing it; node
and transport errors are logged by method and code only.

## States (R1, R2)

`loading` until the stored tip has been checked and served; `rewinding` from a divergence until the
fork point is served again; `halted` for good on an undecodable event of the two contracts, a gap in
the lot or trade ids, a close of a lot or trade that is not open, or a node that went back below the
kept history. In those states every query is 503 with the state (and the reason) and no rows.
Only a 200 holds rows: a 4xx or a 500 has `status: "error"`, the `error`, and the serving state in
`state` (its `status` is never `ok`).
Every answer, errors included, carries `head {number, hash, commitments, timestamp}`, the served
block (null while none is). The served block is the highest block checked after it was applied;
rows are read as of it, never as of a block still waiting for its check (R6).

## Block time

Each block keeps its timestamp, the node's (`blocks.timestamp`; a block without one is refused and
the step retried). A sold lot's closed version keeps the time of the block that closed it
(`closed_time`), a trade the time of the block that opened it (`opened_time`): `blocks` is pruned
below the kept history, the rows are not. Q3's window and Q7's expiry read them; the clock of the
indexer's machine is never used for a rule. The schema is version 2: a database of IDX-01a is
refused ("rebuild it").

## Queries (GET, JSON)

Every parameter is checked before anything is read: a missing, unknown, repeated or malformed one
is 400, an unknown route 404, each with the state and the head. u64 values (lot and trade ids,
prices, expiries) are decimal strings; market keys and modifiers 0x hex. `limit` is 1 to 100
(default 20). An answer of state `ok` has `status`, `head`, `behind` (blocks between the served
block and the node's tip) and the rows below. An answer is kept for its served block (by hash and
commitments) and forgotten when another block is served or at a rewind (R6); the answers kept take
at most 32 MiB of JSON, the oldest forgotten first, and one larger than 1 MiB is not kept.

| Route            | Parameters                                                                                                                          | Answer                                                                                                                                                                                                                              |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/lots`          | Q1. `key` (a market key, 0x hex, one of ENG-01's encodings), `size` (1–255), `limit`, `after` (`<price>:<lot>`, from `next`)        | `total`, `lots` (open, cheapest first, ties by lot id: `lot, key, size, price, expiry, equipment, modifiers, posted`), `next` (null on the last page)                                                                               |
| `/market`        | Q2. `kind` (`balance`, `equipment`, `boss`), `items` (balances only: up to 100 item ids, comma-separated), `limit`, `after` (a key) | `keys`: per market key with an open lot, `key`, `decoded` (the key's fields), `sizes` (per lot size, the `cheapest` lot; at most 8 sizes, then `truncated`); `next`                                                                 |
| `/prices`        | Q3. `key`, `size`                                                                                                                   | `sales` in the window `(T − 7 days, T]` (T the served block's time), `window {after, until}`, and `mean` (the floor of the mean lot price) only from 5 sales: absent under 5, never zero. Summed in SQL from the index `lots_sales` |
| `/hubs/presence` | Q4. `hub` (1–65535), `limit`, `after` (an adventurer id)                                                                            | `hub`, `count`, `adventurers` (by id), `next`                                                                                                                                                                                       |
| `/titles`        | Q5. `adventurers` (1 to 100 u32 ids, comma-separated, no repeat)                                                                    | `titles`: per adventurer asked, in order, `{adventurer, title, tier}` or `{adventurer, title: null}`                                                                                                                                |
| `/invitations`   | Q7. `account` (u32, the invited account of `TradeOpened`), `limit`, `after` (a trade id)                                            | `total`, `invitations` (open trades inviting the account with `T − openedTime < 600`: `trade, invited, inviter, opened, openedTime, expiresAt`), `next`                                                                             |

`/head` and `/stats` are IDX-01a's; `/stats` also counts the open subscriptions, the subscribers
dropped (`subscribersDroppedBy`: `buffered`, `stalled`, `failed`), and the answers kept
(`answerCache`: hits, misses, bytes).

## Subscriptions (server-sent events)

`GET /subscribe/lots?key=&size=` (Q1's lots), `GET /subscribe/presence?hub=` (Q4),
`GET /subscribe/invitations?account=` (Q7, filtered on the account). A bad parameter is 400, a cap
429, both JSON with the head. The stream (`src/subscriptions.ts` has the whole protocol):

| Event            | Data                | Meaning                                                                                                                 |
| ---------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `status`         | `{status, reason?}` | The indexer is not `ok`: the copy is not ready; a snapshot follows once a block is served                               |
| `reset-begin`    | `{head, total}`     | A snapshot as of the served block `head`, of `total` rows                                                               |
| `reset-page`     | `{rows}`            | At most 1 000 rows                                                                                                      |
| `reset-end`      | `{head, total}`     | The end: the copy is complete when the rows received count `total`                                                      |
| `add` / `remove` | `{row}` / `{id}`    | A row that appeared or went away in a block (lots by `lot`, presence by the adventurer as text, invitations by `trade`) |
| `head`           | `{head}`            | The end of a block's changes: they apply together, and the copy is now as of that block                                 |
| `rewind`         | `{to}`              | The tables went back to block `to`: a new snapshot follows                                                              |
| (comment)        | `: keep-alive`      | On a stream idle for `--keep-alive`                                                                                     |

A snapshot is sent at the start of a stream and at the first served block after a rewind or a state
other than `ok`. Its pages are all read as of its block (the rows are versioned), and nothing else is
sent to that stream between them; a rewind or a state other than `ok` abandons it. Then come the
changes of every block after the stream's own head, block by block, in block order, up to the
served block and never past it. Invitations also go away by block time alone, 10 minutes after
their block.

The work is done in steps (a page, or a block's changes), in turns across the streams, at most 10 ms
of it per turn of the event loop; a snapshot's pages and a range's changes are read and serialised
once per topic. A stream is written only while its socket accepts (backpressure): one that holds
more than `--max-buffered` unsent is destroyed at once, one whose socket accepted nothing for
`--stall` too, and one whose step throws ends alone.

## The client library (`@grimworld/indexer/client`)

For the browser (CLI-01): nothing in `src/client/` imports a `node:` module or anything outside the
folder (checked by `tsconfig.client.json`, ESLint and a test); it holds no key. The package export
points at `dist/client/` (`pnpm build`).

- `new IndexerClient({ url, node, maxLag = 5, fetch? })`: `node` is the client's node, a JSON-RPC
  URL read with `starknet_blockHashAndNumber` and `starknet_getBlockWithTxHashes` only, or a
  `NodeReader` of its own. `lots`, `market`, `prices`, `presence`, `titles`, `invitations` each
  answer `{fresh: true, answer}` or `{fresh: false, reason}` ("loading": show it, ask again).
  **R3, in its order**: the indexer's answer (`ok` and a head); then the node's tip, the head at
  most `maxLag` blocks below it; then, last, the node's block at the head's number, the same hash
  and commitments. `check(answer)` and `verify(head)` apply it to an answer read otherwise.
- `LotCache(client, key, size)`, `PresenceCache(client, hub)`, `InvitationCache(client, account)`
  (R4): `connect(onFrame?, onEnd?)` opens the stream and returns `close()`; `ready` only after a
  complete snapshot, false again at a `status`, a `rewind` or any end of the stream; a block's
  changes apply with its `head`; `read()`, the only access to the rows, passes the head through R3,
  and is "not fresh" if the copy was voided while the node was read. One connection at a time:
  `connect()` ends the one before.
- Step 1 of R3 accepts a 200 only: any other code is "loading" (a 400 or 404 throws: a bug of the
  caller).

## Assumptions and limits

- **A block is its hash AND its commitments.** starknet-devnet 0.10.0 gives a replacement block the
  hash of the block it replaced. An accepted block without its four commitments, or of another
  height than asked, is refused (the step is retried).
- **Residual, devnet only.** A block replaced deeper than `--recheck` blocks below the tip, under
  replacement blocks that keep the aborted blocks' hashes and commitments (devnet's empty blocks
  do), is not seen. On a real network a replaced block changes its hash, so every child's parent
  hash changes up to the tip, and the tip check sees it.
- **The kept history counts from the indexer's own checked tip** (`--depth <blocks>`), never from
  the node's: during a catch-up the last `--depth` blocks the indexer holds stay rewindable.
- **Rarity < 128 in the equipment market key.** ENG-01's key is `2^40 + base × 2^16 + requirement ×
2^8 + rarity × 2 + identified`: rarity has 7 bits, and a rarity of 128 or more would be the same
  key as `requirement + 1` (`src/events.ts`, `decodeMarketKey`). Escalated to the project manager.
- **A start after deployment is not supported.** Lot and trade ids come from counters; `--lot-count`
  and `--trade-count` would seed them, but a `LotClosed` or `TradeClosed` of a lot or trade opened
  before `--from` halts (no event gives what was open then). A later start would need the open lots
  and trades read from the views at that block (`lot`, `trade`, `lot_count`, `trade_count`), once
  the market implements them (RWD-10).
- **`LotClosed { sold: false }`** is a withdrawal or a return after expiry: the tables keep `sold`.
- Pre-confirmed blocks are never indexed.

## Tests

- `pnpm test`: unit tests against a fake node (no network): the queries, the subscriptions and
  the client library among them.
- `pnpm test:node`: the local-node scenario under `scripts/with-node.sh` with
  `STATE_ARCHIVE_CAPACITY=full` (on macOS through `test-node/bin/setsid`); it needs the emitter's
  artifacts in `emitter/target/dev/` (`scarb --manifest-path emitter/Scarb.toml build`, which needs
  `[lib]` in `contracts/persistent/Scarb.toml`). IDX-01b's part (`test-node/queries.scenario.ts`)
  moves the node's clock with `devnet_increaseTime`.
