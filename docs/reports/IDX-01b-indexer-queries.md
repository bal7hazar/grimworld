# [Opus 5.5] IDX-01b — indexer queries

## Summary

Pull request: https://github.com/bal7hazar/grimworld/pull/154 (branch `cv/IDX-01b-indexer-queries`,
5 commits). CI is green: 14 checks, `indexer-node` included. The model named by the brief (Opus 5.5)
is the model of this session.

What exists now that did not before:

- **Block time.** Every block keeps the node's timestamp (`blocks.timestamp`). A block without one
  is a `BadAnswer`, and the step is retried. The schema goes to version 2: a database from IDX-01a is
  refused with "rebuild it".
  - Two time columns are also written on the rows, because `blocks` is pruned below the kept history
    and the rows are not: a sold lot's closed version keeps its close's block time (`closed_time`),
    and a trade keeps its opening's (`opened_time`).
  - Q3 and Q7 read only these columns. The clock of the indexer's machine is never used.
- **The queries Q1–Q5 and Q7** over HTTP GET (`src/queries.ts`, routed and validated in
  `src/server.ts`):
  - Every query is read as of the served block and gated by R1.
  - Every answer carries a head (R2), now with the block's `timestamp`.
  - An answer is kept for its served block, keyed by hash and commitments. It is forgotten when
    another block is served, or at a rewind (R6).
- **Three subscriptions** over server-sent events (`src/subscriptions.ts`): Q1's lots, Q4's
  presence, and Q7's invitations filtered on the account.
  - They follow R4, with hooks in `Indexer` (`listen({served, rewound, status})`).
  - The hooks are called after the block's check and **before pruning**, so a listener can read the
    tables at any block from the previously served one to the new one.
  - Bounded: at most N subscriptions per process and per client address. A subscriber that stops
    reading is dropped.
- **The client library** `@grimworld/indexer/client` (`src/client/`), for CLI-01:
  - `IndexerClient` applies R3 in its order. It reads the node through its own two-method JSON-RPC
    reader, or through an injected `NodeReader`.
  - `LotCache`, `PresenceCache` and `InvitationCache` keep the subscriptions under R4.
  - The folder has no `node:` import and holds no key.
- **Tests:**
  - 98 unit tests on the fake node, 32 of them new.
  - The local-node scenario gains a second part, `test-node/queries.scenario.ts`: 4 tests, 13 in all
    with IDX-01a's 9.

## Files changed

All under `indexer/`; the allowlist was kept.

- `src/chain.ts`: `Header.timestamp` (a `BadAnswer` without it), `Head`, and `headOf` moved here.
- `src/store.ts`: schema 2 (`blocks.timestamp`, `lots.closed_time`, `trades.opened_time`, the
  indexes the queries and diffs need), `statement()` (prepared once), the time columns written.
- `src/indexer.ts`: listeners (`served(previous, next)`, `rewound(to)`, `status`), called before
  pruning; a listener that throws is logged.
- `src/queries.ts` (new): Q1–Q5, Q7 as of a block, and the per-block changes the subscriptions send.
- `src/subscriptions.ts` (new): the subscription hub, the protocol, the caps, dropping slow
  consumers.
- `src/server.ts`: routes, parameter validation, the R6 answer cache, the SSE endpoints, `/stats`
  counters; `serve()` returns the server with `.subscriptions`.
- `src/main.ts`: `--max-subscriptions`, `--max-subscriptions-per-client`, `--max-buffered`; the
  streams are ended at stop.
- `src/client/{protocol,reader,client,caches,index}.ts` (new): the client library.
- `src/testing/fake-node.ts`: block timestamps (`time`, `interval`).
- `src/testing/setup.ts` (new): the shared test helpers, including a `fetch` that answers JSON-RPC
  from the fake node.
- `src/queries.test.ts`, `src/subscriptions.test.ts`, `src/client.test.ts` (new); `chain.test.ts`,
  `indexer.test.ts`, `server.test.ts`, `store.test.ts`: adjusted for timestamps and routes, plus one
  timestamp test.
- `test-node/queries.scenario.ts` (new), `scenario.node.test.ts` (registers it), `node.ts`
  (`increaseTime`), `run-indexer.ts` (`extra` options).
- `package.json`: `exports["./client"]` (to `dist/client/`), `typecheck` runs
  `tsconfig.client.json` too; `tsconfig.build.json`: `declaration: true`; `tsconfig.client.json`
  (new: DOM libraries, no Node types); `eslint.config.js`: `node:*` and `../*` imports are banned in
  `src/client/`.
- `README.md`: block time, routes, protocol, client library, options.

## The routes and their parameters

A few rules hold for every route:

- **Validation first.** Every parameter is checked before anything is read. A missing, unknown,
  repeated or malformed parameter is **400**; an unknown route is **404**; both carry the state and
  the head.
- **States.** In `loading`, `rewinding` and `halted` every query is **503** with the state, the
  reason and the head, and no rows.
- **Paging.** `limit` is 1–100 (default 20).
- **Number formats.** u64 values are decimal strings; market keys and modifiers are 0x hex.
- **The body of an `ok` answer** is `status`, `head {number, hash, commitments, timestamp}`,
  `behind`, and then:

| Route | Parameters | Answer |
|---|---|---|
| `GET /lots` (Q1) | `key` (0x hex; must decode as one of ENG-01's encodings), `size` 1–255, `limit`, `after` = `<price>:<lot>` | `total`, `lots` (open; cheapest first, ties by lot id), `next` |
| `GET /market` (Q2) | `kind` ∈ `balance`, `equipment`, `boss`; `items` (balance only, ≤ 100 u32, no repeat); `limit`; `after` (a key) | `keys[{key, decoded, sizes[{size, cheapest}]}]`, `next` |
| `GET /prices` (Q3) | `key`, `size` | `sales`, `window {after, until}` = `(T − 604800, T]`; `mean` (floor of the mean lot price) only when there are ≥ 5 sales |
| `GET /hubs/presence` (Q4) | `hub` 1–65535, `limit`, `after` (adventurer id) | `hub`, `count`, `adventurers`, `next` |
| `GET /titles` (Q5) | `adventurers` (1–100 u32, no repeat) | `titles` in the order asked; `title: null` for none |
| `GET /invitations` (Q7) | `account` (u32), `limit`, `after` (trade id) | `total`, `invitations[{trade, invited, inviter, opened, openedTime, expiresAt}]` with `T − openedTime < 600`, `next` |
| `GET /subscribe/lots` | `key`, `size` | SSE stream (below); 400 on a bad parameter, 429 over a cap |
| `GET /subscribe/presence` | `hub` | SSE stream |
| `GET /subscribe/invitations` | `account` | SSE stream |

`/head` and `/stats` are unchanged. `/stats` adds `subscriptions`, `subscribersDropped` and
`answerCache {hits, misses}`.

## The subscription protocol

One stream per subscription, in this order:

- **`status {status, reason?}`** while the indexer is not `ok`.
- **A snapshot** as of the served block: `reset-begin {head, total}`, then `reset-page {rows}` (at
  most 1 000 rows per page), then `reset-end {head, total}`. It is read and written in one
  synchronous run, so nothing can fall between its pages.
- **Then, for each newly served block, in block order:** `remove {id}` and `add {row}`, followed by
  `head {head}`. Only blocks with changes get their own `head`. A final `head` for the served block
  is always sent.
- **`rewind {to}`** after a rewind. A new snapshot comes at the next served block. A snapshot also
  follows any non-`ok` state.

Row ids: a lot by `lot`; presence by the adventurer (as text); invitations by `trade`.

How the changes are computed:

- **Lots and presence:** from the versions whose `_from` or `_to` falls in `(previous, next]`,
  comparing each touched id's state at `b−1` and at `b`. A lot posted and closed in the same block
  produces no event.
- **Invitations:** the whole set is recomputed at each block and compared, so an invitation also
  goes away by block time alone.

Slow consumers: a subscriber whose unsent output is still above `--max-buffered` when the next
publication comes is dropped (its socket is destroyed). This is checked before a publication, not
after each write, so a reader never loses a snapshot that is larger than the cap.

## The client library's API (`@grimworld/indexer/client`)

- **`new IndexerClient({url, node, maxLag = 5, fetch?})`**
  - `node` is a JSON-RPC URL (read with `starknet_blockHashAndNumber` and
    `starknet_getBlockWithTxHashes` only), or a `NodeReader {tip(), block(n)}`.
  - Query methods: `lots(key, size, {limit, after})`, `market(kind, {items, limit, after})`,
    `prices(key, size)`, `presence(hub, {limit, after})`, `titles(ids)`,
    `invitations(account, {limit, after})`.
  - Each returns `Checked<T>` = `{fresh: true, answer}` or `{fresh: false, reason}`.
  - Other methods: `check(answer)`, `verify(head)` (R3's steps 2 and 3, with a test hook between
    them), `raw(path, query)`, and `stream(path, query, onFrame, signal)`.
  - A 400 or 404 throws, because it is a bug of the caller. A 503 or a network error is "not
    fresh".
- **`LotCache(client, key, size)`, `PresenceCache(client, hub)`, `InvitationCache(client, account)`**,
  all built on `StreamCache<Row>`:
  - `connect(onFrame?, onEnd?)` opens the stream and returns `close()`.
  - `ready` and `head` give the cache's state; `status` is one of `disconnected`, `connecting`, the
    indexer's state, or `incomplete snapshot`.
  - `read()` is the only access to the rows: it returns `Checked<{head, rows}>`.
  - `receive(frame)` is public for the tests.
- **Also exported:** `jsonRpcReader(url, fetch?)`, `parseFrame`, `byPriceThenLot`, and the
  protocol's types.

## Commands run

Checks from `indexer/`, on the owner's Mac (node v24.21.0, pnpm 12.5.1):

```
$ pnpm typecheck
$ tsc --noEmit && tsc --noEmit -p tsconfig.client.json        (no error)
$ pnpm lint
$ eslint .                                                   (no error)
$ pnpm build
$ tsc -p tsconfig.build.json                                 (dist/client/{index,client,caches,protocol,reader}.{js,d.ts})
$ pnpm -w exec prettier --check client indexer
All matched files use Prettier code style!
$ pnpm test
      Tests  98 passed (98)
   Duration  1.64s
```

The unit suite was run 5 times in a row after the slow-consumer test was fixed: 98/98 each time.

Before that fix, the HTTP slow-consumer test failed 2 times out of about 8 full runs:
`expected +0 to be 1` on `dropped`. On macOS the paused socket's kernel buffers sometimes held the
whole 3 MB snapshot. The test now publishes blocks of 2 000 lots until the drop happens, bounded at
40 blocks. This fixed the test, not the code.

The emitter build, then the scenario on the local node:

```
$ scarb --manifest-path …/indexer/emitter/Scarb.toml build
    Finished `dev` profile target(s) in 1 second
$ pnpm test:node          (starknet-devnet 0.10.0 through scripts/with-node.sh; last run)
      Tests  13 passed (13)
   Duration  50.18s
```

The first local-node run failed 1 of 13: the measure expected 100 pages and got 101. With exactly
10 000 lots, the 100th page is full, so one empty page follows before `next` is null. The test now
counts the non-empty pages.

The scenario's real output for IDX-01b (`.scenario-results.txt`, last local run):

```
IDX-01b: emitters deployed at blocks 280 and 281; indexer http://127.0.0.1:…
IDX-01b AC-1: Q1 ["2@20","4@20"] of 4, next 20:4; Q2 [{"key":"0x4d2","decoded":{"kind":"balance","item":1234},"sizes":[{"size":1,"cheapest":{"lot":"7",…,"price":"15",…}},{"size":10,"cheapest":{"lot":"2",…,"price":"20",…}}]}]; Q4 hub 40 [101,102]; Q5 101 -> title 8 tier 3, 102 and 103 none; Q7 account 500 [trade 1], 501 [] (declined); Q3 4 sales: no mean, 5 sales: mean 300; every head is the node's block, time included
IDX-01b AC-2: after devnet_increaseTime(600) the invitation opened at block time 1790686706 is gone at block time 1790687306; after 7 more days, Q3 counts 0 sales and has no mean
IDX-01b AC-3: 3 caches (lots, presence, invitations) followed block 291; block 291 aborted and replaced: each got `rewind` then a new snapshot, and read() equals the queries at the replacement, 56 ms after the abort
IDX-01b AC-4: R3 through the client's own JSON-RPC reader: an answer 6 blocks behind -> "indexer 6 blocks behind the node"; an answer at an aborted block -> "block 298 is not the node's", and the cache at it -> "block 298 is not the node's"; after the replacement the cache is fresh again
IDX-01b AC-7: 10 000 lots posted in 100 transactions and served in 12.4 s
```

IDX-01a's scenario lines (AC-1 to AC-3, AC-8, the pruning test) still pass unchanged. Timestamps
and ports vary from run to run.

CI (run 36572282336): all 14 checks pass. `indexer-node` ran `test:node` in 1m34s and printed the
same IDX-01b lines; its measures are in the table below.

`gh pr checks 154 --watch` ended with every check `pass`.

## Measures

Measured by the scenario on starknet-devnet 0.10.0, with the client in the same process as the
HTTP requests. There are 10 000 open lots in one key and lot size. The poll is 50 ms. Latencies are
over HTTP, 100 new targets each, so none is served from the R6 cache (except the "kept" row).

| Measure | Owner's Mac | CI runner |
|---|---|---|
| Q1, a page of 100, cursor through all 10 000 (n=101) | median 1.23 ms, p95 1.43 ms | 1.97 / 2.29 ms |
| Q1, the same page again (kept, R6) | 0.24 / 0.30 ms | 0.45 / 0.80 ms |
| Q2 kind=balance, limit 1–100 | 0.27 / 0.45 ms | 0.80 / 0.90 ms |
| Q3 | 0.14 / 0.22 ms | 0.49 / 0.73 ms |
| Q4 | 0.16 / 0.24 ms | 0.60 / 0.94 ms |
| Q5, 1–100 adventurers | 0.17 / 0.20 ms | 0.41 / 0.67 ms |
| Q7 | 0.16 / 0.20 ms | 0.56 / 0.68 ms |
| Snapshot of 10 000 lots, open to ready in `LotCache` (n=10) | median 24.74 ms, p95 33.67 ms | 49.00 / 54.88 ms |
| Indexer RSS: 10 subscriptions of 10 000 lots | 199 → 226 MB (≈ 2.7 MB each, just after their snapshots) | 189 → 227 MB (≈ 3.9 MB each) |
| Indexer RSS: 200 subscriptions of a hub's presence | +2 MB (≈ 10 KB each) | +4 MB (≈ 20.5 KB each) |
| RPC calls per served block (1 lot and 1 move a block, idle polls included) | 6.60 without subscriptions, 6.40 with 214 open | printed by the job |

Notes on these figures:

- **Q2 was 18.6 ms / 19.3 ms (Mac) in the first version.** That version used a window function over
  every open lot of the kind. It is now index seeks: the next key, the next lot size, then the
  cheapest lot, each `LIMIT 1`. See *Deviations*.
- **RSS is rounded to MB and is a process-wide figure.** The ≈ 2.7 MB per 10 000-lot subscription
  is taken right after the snapshots were written, so it includes buffers that were not yet
  collected. It is not a steady state.
- **Subscriptions make no RPC calls.** The difference between 6.60 and 6.40 is noise from idle
  polls.

## Cost

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| — | — | — | — | No Cairo change (`indexer/emitter` untouched) |

## Acceptance criteria

- **AC-1**: `src/queries.test.ts` (Q1–Q5, Q7, R1 503 in all three states, R2 head on 200, 400 and
  404, R6), and `IDX-01b AC-1` on the local node, where every head is checked equal to the node's
  block (timestamp included).
- **AC-2**: `src/queries.test.ts`:
  - Q3 at `T − 7 days` is excluded and `T − 7 days + 1` is included; 4 sales give no mean, 5 give
    one; a withdrawal is not a sale; u64 prices keep the floor.
  - Q7 at 599 s is shown and at 600 s is gone; a declined trade is gone.
  - On the local node, `devnet_increaseTime` covers both.
- **AC-3**: `src/subscriptions.test.ts`:
  - the state before the first served block, then a snapshot, then per-block changes;
  - nothing from an applied block that is not yet served;
  - several served blocks published one by one;
  - a rewind leads to a new snapshot;
  - **a rewind in the middle of a snapshot**: the node is reorganised while the first page is
    written; that snapshot stays whole at its head, R3 refuses its head, and the next snapshot
    matches Q1;
  - invitations expiring by block time alone.

  On the local node (`IDX-01b AC-3`), three caches go through an aborted and replaced block.
- **AC-4**: `src/client.test.ts`:
  - the order indexer → tip → block, logged;
  - a head 6 behind is refused without reading its block;
  - a block that is gone, or replaced (hash or commitments), is refused;
  - a reorg between the two node reads is seen;
  - a 503 is refused without reading the node;
  - caches: incomplete snapshot, rewind mid-snapshot, changes held until their `head`, a status, a
    stream ended by the server, a 429 at opening.

  The no-`node:` and no-key check is enforced three ways: `tsconfig.client.json` (DOM libraries, no
  Node types), ESLint, and a test that scans the folder's imports. On the local node, `IDX-01b AC-3`
  and `AC-4` run through `jsonRpcReader` against devnet.
- **AC-5**: `src/subscriptions.test.ts` tests the caps per process and per client, and a slow
  consumer dropped while a reader is kept. It also tests, over HTTP, a 400, a 429 with the head, and
  a paused socket that gets dropped. `src/queries.test.ts` tests the `limit` cap (0 and 101 are
  400) and the list caps.
- **AC-6**: lint, typecheck, test, build and prettier all pass locally, and CI is green including
  `indexer-node`.
  - `gh pr edit` failed on a GitHub API deprecation error. The REST fallback (`gh api … PATCH`) was
    refused by this run's permissions. So the PR body still shows AC-6 unticked, with the text "CI:
    see the checks".
- **AC-7**: the measures and the scenario's real output are above.

## Deviations from the brief

- **R5 has no test here.** The contract stays authoritative, and the market system that would
  revert a stale purchase is not written yet.
- **Q1 lists the open lots, expired or not.** This is the brief's wording; SPK-11's table says
  "open, unexpired". Each lot carries its `expiry`, and the head carries the block's `timestamp`, so
  a client can hide expired lots. The unit and boundary of `expiry` are not written anywhere (see
  *Escalations* E-2).
- **Q2's answer has no count of open lots per size**, only the cheapest lot. The first version had
  one, at 18.6 ms per call over 10 000 lots, because the count needs a scan of the key's lots. The
  brief does not ask for it.
- **Q3's `mean` is the floor of the mean lot price** for the key and lot size; per unit is
  `mean / size`. `sales` (the count) is also given.
- **The cap "per connection" is kept per remote address.** An HTTP/1.1 connection carries one
  stream, so a per-connection cap would always be 1. Behind a proxy, every client is the proxy
  (IDX-02 should set `--max-subscriptions-per-client` or forward the address).
- **The head of every answer now carries `timestamp`** besides `number, hash, commitments`. R3 still
  compares hash and commitments only.
- **Two new files for the tests:** `src/testing/setup.ts` and `test-node/queries.scenario.ts`. The
  heredoc route to append the latter to the existing scenario file was refused, and a module is
  cleaner anyway.

## Escalations

- **E-1: Q2's "category" is not in the market key.** design/16 splits the market into equipment,
  ingredients, stillstone and potions. The key (ENG-01 §3.4) only tells balance, equipment and boss
  apart. Splitting balances needs the registry's item class (`ITEM` record), which the indexer does
  not read.
  - I did not invent a rule. Q2 takes `kind` (balance, equipment, boss) and optionally `items` (the
    balance item ids of a category, which the client reads from the registry).
  - To decide: whether the indexer should read the registry, or the client keeps passing item ids.
  - Also: whether boss items belong to the "equipment" category, in which case the client asks
    `kind=equipment` and `kind=boss`.
  - Read: design/16 *Principle*, ENG-01 §3.4 and §3.5, SPK-11 §1 (#30, Q2).
- **E-2: lot expiry.** SPK-11's Q1 says "open, unexpired". The brief says "open lots". ENG-01 gives
  `expiry: u64` without a unit, and `systems/market.cairo` does not exist yet.
  - To decide: whether `expiry` is a block timestamp in seconds, whether a lot is expired at
    `T ≥ expiry` or at `T > expiry`, and whether the indexer (Q1, Q2, the lots subscription) should
    drop expired lots by block time, as Q7 does for invitations.
  - Q7's rule, `T − opened < 600`, is my reading of "under 10 minutes old" and of the model's
    comment `opened at … (expiry: 10 minutes later)`. It should be confirmed with RWD-10's
    contract.
- **E-3: the equipment rarity < 128 assumption** is unchanged (D-153). It lives where the key is
  decoded (`events.ts`). Q1, Q3 and the subscriptions refuse an undecodable key with 400.

## Open questions

- Should the mean price of Q3 be per unit rather than per lot? Today it is per lot, with the size
  known.
- Should a subscription reply 503 instead of streaming `status` while the indexer is `loading`?
  Today it accepts and waits, which R4 allows. The query routes answer 503.

## What CLI-01 needs to know

- **Import** from `@grimworld/indexer/client`. The export points at `dist/client/`, so run
  `pnpm build` in `indexer/` (or `pnpm -r build`, with the dependency declared) before bundling. The
  sources use `.ts` import extensions, NodeNext style, which is why the export is the built output.
- **Only show what `read()` or a query method returns with `fresh: true`.** Anything else is
  "loading": show it and ask again. The rows of a cache are only reachable through `read()`.
- **Keep one cache per screen topic**, connected while the screen is open:
  - a lot list: `LotCache(key, size)`;
  - a hub's presence: `PresenceCache(hub)`;
  - the invitations: `InvitationCache(account)`.

  `close()` it when leaving. After any end of the stream, `ready` is false; reconnect with a new
  `connect()`.
- **The node URL** given to `IndexerClient` must be the client's own node (R3's arbiter). Only two
  read methods are called on it.
- **Expired lots are not filtered** by the indexer (E-2). Compare `lot.expiry` with
  `head.timestamp` until that is decided.
- **The "next lot after a lost race"** (R5) is Q1's next row. `after=<price>:<lot>` pages from any
  lot.

## Resume 1

**What was asked:** fix loop 1, from the two audits of #154. The orchestrator accepted every
finding: Opus 5.5 1–8 and GPT-6-Sol 1–3.

**Result:**

- **All findings are fixed and tested.** The table below maps each one.
- **Pushed to #154** in 3 commits, after merging `origin/main`: `cebda80` (the fix), `c5d612b`
  (README, and the new resnapshot measure), `dc3b450` (the HTTP stall test made to hold on Linux).
- **CI is green:** 14/14, `indexer-node` included (run 36575684783).
- **The PR body was not updated.** `gh pr edit 154 --body-file …` failed again with the GitHub
  error `GraphQL: Projects (classic) is being deprecated … (repository.pullRequest.projectCards)`,
  and the body is unchanged. The text to set is under *PR body* below.
- **Main moved during the fix:** `origin/main` brought `PENDING-cv-market-queries.md` (#155), the
  orchestrator's request to the project manager about E-1 and E-2. It is still pending, so Q2 and
  lot expiry are unchanged.

### Findings and what was done

| Finding | Change | Test |
|---|---|---|
| Opus 1 (medium): R3 step 1 must require 200; error bodies looked `ok` | `IndexerClient.query()` accepts a 200 only: a 400 or 404 throws, a 503 is `indexer <state>`, any other code is `indexer error <code>`, and the node is not read. Every 4xx and 500 body is `{status: "error", error, state, head}`. `status` is never `ok` on an error. | `client.test.ts`: 500, 429 and 502 with an `ok`-looking body are refused and the node is not read; a real server whose query throws while `ok` gives a 500 with `status: "error"`, `state: "ok"`, and the client says `indexer error 500`. `server.test.ts` and `queries.test.ts` updated for the new bodies. |
| Opus 2 (low): implicit continuity; one throw skipped every later subscription | Each subscription keeps its own `head`, and its changes are read over `(its head, served]`. Each step runs in a `try`; a throw drops that stream only (`drops.failed`). | `subscriptions.test.ts`: a paused subscription misses three blocks, is written nothing while it waits for drain, then receives exactly the tail of the same sequence as a live one, ending at the served block. A sink that throws is dropped while the subscriptions before and after it get the block. |
| Opus 3 and GPT 1 (major): nominal bounds, no backpressure | See *Backpressure and bounds* below. | See below. |
| Opus 4 (low): every resnapshot in one run; invitations 2 queries per block per subscription | Work goes in steps (one page, or one block's changes), in turns, at most `sliceMs` (10 ms) per turn of the event loop and at least one step per turn. Snapshot pages are read and serialised once per topic and block. The changes of a range are read once per topic and range. Invitation changes use 2 queries per range (the range's blocks, then every trade version that may be shown in it), compared block by block in memory. | Unit: a rewind between two pages of a snapshot (`sliceMs: 0`, one step per turn); invitations over several blocks at once give the same frames as one block at a time. Local node, with 210 subscriptions open (10 of 10 000 lots, 200 small): after a rewind, all are ready again at the replacement in 106 ms on the Mac and 192 ms on CI, and `GET /head` answers meanwhile (max 46 ms on the Mac, 50 ms on CI). |
| Opus 5 (low): Q2 up to 255 sizes per key; cache counted in entries | Q2 reads at most `MAX_SIZES` = 8 lot sizes per key and marks the key `truncated` when there are more. A request is then at most `(limit + 1) × (2 × 8 + 2)` index seeks. The answer cache is bounded in bytes of JSON: 32 MiB in all, oldest first out; an answer over 1 MiB is not kept. `/stats` shows `answerCache.bytes`. | `queries.test.ts`: 9 lot sizes give 8 plus `truncated`. An `AnswerCache(1000, 600)` stays at or under 1000 bytes, forgets the oldest, and never keeps a 700-byte answer. |
| GPT 2 (major): Q3 loaded every sale in memory | One aggregate row in SQL: `count(*)`, and `sum(price_hi)` and `sum(price_lo)` only when `count(*) >= 5`. `FROM lots INDEXED BY lots_sales`, a covering index `(market_key, lot_size, closed_time, price_hi, price_lo, _from, _to) WHERE sold = 1`: a range seek on key, size and window. The new columns hold a u64 price as two 32-bit halves, because SQLite's integers are signed 64-bit; each sum stays below 2^63 up to 2^31 sales in the window, and SQLite raises an error rather than wrap. The sums are read as bigints. The schema stays version 2, which has never been released. | The existing Q3 tests (window edges, the 5-sale threshold, u64 prices at 2^64 − 1 with the floor of the mean) pass unchanged. |
| Opus 6 (low): `connect()` over a live connection; a late `finally` cleared the current one | `StreamCache` keeps one connection at a time. `connect()` aborts the previous one, and a `generation` makes its late frames and its end no-ops. | `client.test.ts`: connect twice against a running server. The first ends (`null`), the server ends with one subscription, and the cache stays `ok` and ready until `close()`. |
| GPT 3 (minor): `read()` fresh after a voiding during the node check | Every voiding (`status`, `rewind`, a new `reset-begin`, the end of the stream, `connect`) bumps an `epoch`. `read()` checks `ready` and the epoch after the node's answers. | `client.test.ts`: a rewind, a new snapshot, or a halted status arriving during `block()` makes the read not fresh. |
| Opus 7 (tests): R6's rewind clear untested alone | New test: block 4 is replaced under blocks 5' and 6' that keep the hashes and commitments of 5 and 6. The served block 6 is the same before and after, and the answer must be the replacement's. | `queries.test.ts` "R6: a block served again…". **Removing the listener (`indexer.listen({ rewound: () => this.clear() })`) fails it:** `expected [ '1@10', '2@20', '3@30', '4@40' ] to include '4@44'`, 1 failed and 13 passed. Restored, it passes 14/14. |
| Opus 8 (info): CORS, keep-alive | `serve({allowedOrigins})` and `--allow-origin` (repeatable; default none, the same origin only): an allowed `Origin` gets `access-control-allow-origin` and `vary: Origin`, on JSON and event streams alike. `: keep-alive` comments go on streams idle for `keepAliveMs` (`--keep-alive`, 15 s). | `subscriptions.test.ts`: an allowed origin gets the header on a 400 and on an event stream, another origin on a 429 does not; with `keepAliveMs: 30`, at least 2 comments in 120 ms. |

### Backpressure and bounds (Opus 3, GPT 1)

- **The sink.** `Sink.write` returns the socket's `write()` result, and `onDrain` waits for
  `drain`.
- **Steps.** A step writes one snapshot page (at most 1 000 rows) or one block's changes, and only
  while the socket accepts. After a refused write the subscription waits for `drain`.
- **Immediate drop.** If a subscription's unsent output (`writableLength`) passes `maxBuffered`
  after a write, it is dropped at once.
- **Stall drop.** A subscription that has been waiting for `drain` for `stallMs` is dropped.
- **Consistency across pages.** A snapshot's pages are all read as of its block, and nothing else
  is written to that stream between them. A rewind or a non-`ok` state abandons the snapshot.
- **New defaults:**
  - `perProcess` 512 (was 1000);
  - `maxBuffered` 512 KiB (was 16 MiB);
  - `stallMs` 30 s;
  - `keepAliveMs` 15 s;
  - `perClient` 16.
- **The stated bound: 512 × 512 KiB = 256 MiB** of unsent output at most, plus the shared pages
  being sent. It is written in `subscriptions.ts`, `main.ts` and the README.
- **Tests:**
  - A paused sink gets `reset-begin` and nothing more until drain; then the 10 pages and
    `reset-end`.
  - A sink already over the cap is dropped at once (`drops.buffered`).
  - A paused sink under the cap is dropped after `stallMs` (`drops.stalled`), while a reader
    continues.
  - Over HTTP, a client that reads nothing from the start of a 20 000-lot snapshot is dropped for
    the stall, never for bytes: `drops` is `{buffered: 0, stalled: 1, failed: 0}`.
- **Change to SPK-11's wording of R4.** R4 said a snapshot is "written in one synchronous run". It
  is not any more, because the finding asked for backpressure. The guarantee is kept another way:
  every page is read as of the snapshot's block, and changes come only after `reset-end`.

### The CI failure on the way

The first push after the fix (`c5d612b`, run 36575329790) failed in `client`: the new HTTP stall
test timed out after 5000 ms on the Linux runner. The Linux loopback socket buffers held the whole
3.5 MB snapshot, so the paused socket never pushed back.

The test now publishes blocks of 2 000 lots, at most 40, until the socket blocks and the stall drop
comes, with a 40 s timeout (`dc3b450`). CI then passed 14/14.

### Commands run (after the fix)

```
$ pnpm typecheck      tsc --noEmit && tsc --noEmit -p tsconfig.client.json   (no error)
$ pnpm lint           eslint .                                               (no error)
$ pnpm build          tsc -p tsconfig.build.json                             (no error)
$ pnpm -w exec prettier --check client indexer
All matched files use Prettier code style!
$ pnpm test           (5 runs, each)  Tests  110 passed (110)
$ pnpm test:node      Tests  13 passed (13)   Duration  50.82s
$ gh pr checks 154 --watch --interval 30      exit 0; 14 checks pass (run 36575684783)
```

### Measures after the fix (`test:node`)

| Measure | Owner's Mac | CI |
|---|---|---|
| Q1 page of 100 through 10 000 lots | median 1.25 ms, p95 1.64 ms | 1.81 / 2.51 ms |
| Q1 kept (R6) | 0.22 / 0.30 ms | 0.62 / 0.95 ms |
| Q2 | 0.26 / 0.36 ms | 0.53 / 0.82 ms |
| Q3 (SQL aggregate) | 0.14 / 0.23 ms | 0.33 / 0.46 ms |
| Q4 / Q5 / Q7 | 0.16 / 0.17 / 0.15 ms median | 0.45 / 0.55 / 0.57 ms |
| Snapshot of 10 000 lots, open to ready | median 6.53 ms, p95 30.81 ms (was 24.74 / 33.67) | 14.70 / 37.49 ms |
| Rewind with 210 subscriptions open, all ready again | 106 ms; `/head` meanwhile median 9.56, max 46.18 ms (n=3) | 192 ms; `/head` median 11.79, max 49.67 ms (n=5); none dropped |
| RPC calls per served block | 6.50 without subscriptions, 6.30 with 214 open | 6.60 and 6.60 |

- **The RSS measure no longer resolves the cost of a subscription.** `/stats` rounds RSS to MB.
  With shared pages, 10 subscriptions of 10 000 lots moved RSS by 0 MB on both machines, and 200
  small ones by 3 MB on the Mac and 0 MB on CI. That is below the resolution; it is not a claim of
  zero.
- **The `/head` samples during the rewind are few** (n=3 and n=5), because the resnapshot ends
  quickly.

### Files changed in this resume

- **Library code:**
  - `src/subscriptions.ts`: rewritten.
  - `src/server.ts`: error bodies, byte-bounded `AnswerCache`, CORS, drain sink.
  - `src/queries.ts`: Q3 in SQL, Q2 size cap, `lotPage` public, optional counts, `invitationChanges`.
  - `src/store.ts`: `price_hi` and `price_lo`, the covering `lots_sales` index, bigint statements.
  - `src/main.ts`: `--stall`, `--keep-alive`, `--allow-origin`, new defaults.
  - `src/client/client.ts`: 200 only.
  - `src/client/caches.ts`: generation and epoch.
- **Tests:**
  - `src/subscriptions.test.ts`: rewritten for the asynchronous hub, plus 7 new tests.
  - `src/queries.test.ts`: 3 new tests.
  - `src/client.test.ts`: 4 new tests.
  - `src/server.test.ts`: error bodies.
  - `src/testing/setup.ts`: a `recheck` option.
  - `test-node/queries.scenario.ts`: the resnapshot measure.
- **Docs:** `README.md`.

### PR body

The text to set on #154, because `gh pr edit` failed as described above:


````markdown
IDX-01b (brief `docs/briefs/IDX-01b-indexer-queries.md`), on top of IDX-01a (#144).

## Summary

- **Block time**: every block keeps the node's timestamp (`blocks.timestamp`, schema 2; a block without one is refused and retried). A sold lot keeps its close's block time and a trade its opening's, on the rows (`blocks` is pruned, the rows are not). Q3 and Q7 read only these; the machine's clock is never used for a rule.
- **Queries** Q1–Q5 and Q7 over HTTP GET (`src/queries.ts`, `src/server.ts`): read as of the served block, gated by R1 (503 in `loading`, `rewinding`, `halted`), a head on every answer (R2, time included), kept per served block by hash and commitments and forgotten at every rewind (R6). Every parameter is checked (bounded integers, market keys as 0x hex that must decode, lists ≤ 100, `limit` ≤ 100, no unknown or repeated parameter) before anything is read; SQL is parameterised.
- **Subscriptions** over server-sent events (`src/subscriptions.ts`): Q1's lots, Q4's presence, Q7's invitations filtered on the account. R4: a paged snapshot written in one synchronous run, then each newly served block's changes followed by its head, in block order; a new snapshot after every rewind or non-`ok` state; nothing from an unserved block. Hooks in `Indexer` (`served`, `rewound`, `status`), called before pruning. Bounded: per process, per client address, and slow consumers dropped.
- **Client library** `@grimworld/indexer/client` (`src/client/`): `IndexerClient` applying R3 in its order through its own two-method JSON-RPC reader (or an injected one), and `LotCache`, `PresenceCache`, `InvitationCache` under R4. No `node:` import (checked by a browser-only tsconfig, ESLint and a test), no key.
- **Tests**: 98 unit tests on the fake node (32 new); the local-node scenario extended (`test-node/queries.scenario.ts`): queries against the emitter's events, `devnet_increaseTime` for Q7's expiry and Q3's window, three caches through a reorg, R3's stale and vanished heads, and the measures.

## Acceptance criteria

- [x] AC-1 Q1–Q5 and Q7 answer what the emitter sent, as of the served block, with a head; 503 in the three states (`src/queries.test.ts`, `IDX-01b AC-1` in `test:node`)
- [x] AC-2 Q3's window and threshold and Q7's expiry by block time, at their edges (`src/queries.test.ts`, `IDX-01b AC-2`)
- [x] AC-3 R4 for every subscription; a rewind during a snapshot tested (`src/subscriptions.test.ts`, `IDX-01b AC-3`)
- [x] AC-4 the client library applies R3 in its order, caches ready only under R4, no `node:` import, no key; against the running indexer on the local node (`src/client.test.ts`, `IDX-01b AC-3`, `AC-4`)
- [x] AC-5 page sizes, subscriptions per process and per client, slow consumers (`src/subscriptions.test.ts`)
- [x] AC-6 lint, typecheck, test, build, prettier pass locally; CI green, 14 checks including indexer-node (after fix loop 1 too)
- [x] AC-7 measures (local node, the owner's Mac): Q1 page of 100 over 10 000 lots median 1.23 ms / p95 1.43 ms; Q2 0.27 / 0.45 ms; snapshot of 10 000 lots 24.7 / 33.7 ms; ~10 KB of RSS per small subscription; RPC calls per served block 6.60 without subscriptions, 6.40 with 214 open

## Fix loop 1 (the two audits, all findings accepted)

- R3 step 1 needs a 200: every other code is "loading" for the client; error bodies are `status: "error"` with the serving state in `state` (a 500 while `ok` tested).
- Subscriptions rebuilt on backpressure: a stream is written only while its socket accepts, dropped at once past `--max-buffered` (512 KiB) or after `--stall` (30 s) without a write accepted; defaults bound the streams to 512 × 512 KiB = 256 MiB. Each subscription continues from its own head; a throw ends that stream only; work in steps, at most 10 ms per turn of the event loop; snapshot pages and range changes read and serialised once per topic; invitation changes batched per range (2 queries). Keep-alive comments; `--allow-origin` for CORS.
- Q3 summed in SQL from the covering index `lots_sales` (u64 prices as two 32-bit halves); Q2 reads at most 8 lot sizes a key; the answer cache bounded in bytes (32 MiB, 1 MiB an entry).
- Caches: one connection at a time (a generation); a read voided during the node's check is not fresh.
- R6's rewind clear has a test that fails without it (checked by removing the listener).
- Measures after the fix (the owner's Mac): snapshot of 10 000 lots median 6.5 ms; a rewind with 210 subscriptions open, all ready again in 106 ms, `/head` answering meanwhile (max 46 ms).

## Escalations (in the report)

- Q2's "category" (design/16: equipment, ingredients, stillstone, potions) is not in the market key: the indexer filters by the key's kind (`balance`, `equipment`, `boss`) and by item ids the client gives from the registry.
- Q1 lists open lots, expired or not (the brief's wording); a lot's `expiry` and the head's `timestamp` let the client hide expired ones. Its unit and boundary are not written anywhere yet (the market system is not implemented).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
````

## Resume 2

**What was asked:** fix loop 2, from the second audit passes. GPT-6-Sol 1, 2 and 3 and Opus 5.5
N1, N2 and N3 were accepted. The Opus auditor checked the spread snapshot's guarantee and found
that it holds.

**Result:**
- **Every accepted finding is fixed and tested.** The table below maps each one.
- **Pushed to #154 as `1bf9fe0`.**
- **CI is green:** 14/14, `indexer-node` included (run 36577845090).
- **The PR body was not touched in this resume** (not asked). The text under *Resume 1 → PR body*
  still needs setting, and does not yet mention fix loop 2.

### Findings and what was done

| Finding | Change | Test |
|---|---|---|
| GPT 1 (major): shared snapshot pages bypassed the bounds (kept after their readers, until the next served block) | Each topic-and-block entry of pages keeps its readers. A page is freed as soon as every reader has passed it; a single reader holds only the page it is at. The entry goes when no snapshot reads it: when its last reader ends its snapshot, closes, is dropped, is reset by a rewind or a state, or restarts. A new snapshot joins an entry only while its page 0 is still held; otherwise it gets its own entry. All shared pages together are capped at `pagesMaxBytes` (64 MiB by default), with LRU eviction. Past the cap, other entries go first, least recently used first. Then the current entry's slowest readers are detached (never the one asking), which frees what they held; they start their snapshot again (a new `reset-begin`, which the client's cache handles). What remains past the cap is at most one page. The old clean-up at each served block is gone. | `subscriptions.test.ts`, "GPT 1: …do not accumulate": 5 topics of 60 lots, requested one after another at a stable head. Each is read whole, then read again and closed after its first page; after each, `pagesHeld` and `pagesBytes` are 0. "GPT 1: past pagesMaxBytes…": cap 4 000 bytes, a reader stopped at the start of topic 1, a faster reader of topic 1, a reader of topic 2. The shared bytes never pass the cap plus one page. The stopped reader, once resumed, gets a second `reset-begin` and then a complete copy (100 lots); the other two are complete too; at the end 0 bytes are held. |
| GPT 2 (major): `status()` and `rewound()` wrote in loops without isolation; a same-height replacement never resnapshotted a stale head | `write()` itself catches a sink that throws (in `write`, `buffered` or `onDrain`) and drops that stream only (`drops.failed`). So a rewind, a state, a tick and a step each isolate every subscriber. `step()` now checks identity (hash and commitments), not only the number: a head, or a snapshot's block, that is no longer the stored or served block at its height starts a new snapshot. | "GPT 2: a sink that throws on the rewind's write…": 3 subscriptions, the first throws. It alone is dropped; the other two get `status`, `rewind`, a new snapshot, and a fresh copy equal to Q1. "GPT 2: a subscription that did not hear of a rewind…": the hub's `rewound` and `status` are made no-ops, and block 2 is replaced at the same height. The subscription still resnapshots, at the new commitments, and matches Q1. **Removing the identity check fails this test** (`expected [] to deeply equal [ 'reset-begin', 'reset-page', …]`, 1 failed and 19 passed); restored, 20 pass. |
| GPT 3 and Opus N1: schema changed but still version 2 | `SCHEMA_VERSION` is `"3"`. The `Store` constructor reads `meta.schema` first. On another version it closes the database and throws `SchemaMismatch` before any `CREATE` or `prepare`, with the message `the database has schema N, this indexer 3: rebuild it from the chain (grimworld-indexer rebuild --from <the contracts' deployment block> ...)`. This applies to read-only opens too. `rebuild` passes `{rebuild: true}`, which drops every table whatever the version; the indexer is rebuilt from the chain, with no migration. The `--from` check of `rebuild` now reads the file with `Store.peek()` (schema and configuration, read-only) before anything is dropped, so a refused rebuild still keeps the database. `main.ts` exits 2 with the message on a mismatch. | `store.test.ts` builds a schema-2 database with the old `lots` layout (no price halves). Opening it (read-write and read-only) throws `SchemaMismatch` with the message, not SQLite's `no such column`, and `peek` shows it unchanged. `rebuild` then drops and recreates it at version 3, and a plain open succeeds. `main.test.ts`: `run` on a schema-2 file exits 2 with the message. The existing "rebuild --from another block … keeps the database" still passes. |
| Opus N2: one block's changes were one unbounded chunk (3 000 lots is about 540 KB, over 512 KiB) | A block's changes are split into chunks of at most `page` (1 000) frames: removals, then additions. The block's `head` goes in its last chunk; only that chunk moves the subscription's head. A step writes one chunk, so a reader that keeps up holds at most the high-water mark plus one step. A range's plan is also capped at `planBlocks` (100) blocks. | "Opus N2": a reader that drains one turn after each refused write, `maxBuffered` 300 KiB, and 3 000 lots posted in one block. It is not dropped and gets 3 000 `add`s, then a single `head`, last, in exactly 3 writes, each under the cap. The block's frames together are over 300 KiB. |
| Opus N3: a block served (not a rewind) while a snapshot is spread | No code change; the test shows the existing guarantee. | "Opus N3": `sliceMs 0` and `page 2`, a snapshot of 5 lots at block 1. Block 2 (lot 6 posted, lot 3 sold) is served after the first page. The frames are `reset-begin`, 3 pages, `reset-end` (all at block 1: lots 1–5, 3 still there, no 6), then `remove 3`, `add 6`, `head 2`. The client's cache is never ready on part of the snapshot, holds block 1's rows under head 1, and ends equal to Q1 at block 2. |

### Commands run

```
$ pnpm typecheck      tsc --noEmit && tsc --noEmit -p tsconfig.client.json   (no error)
$ pnpm lint           eslint .                                               (no error)
$ pnpm build          tsc -p tsconfig.build.json                             (no error)
$ pnpm -w exec prettier --check client indexer
All matched files use Prettier code style!
$ pnpm test           (3 runs, each)  Tests  119 passed (119)
$ pnpm test:node      Tests  13 passed (13)   Duration  50.41s
$ gh pr checks 154 --watch --interval 30      exit 0; 14 checks pass (run 36577845090)
```

Notes on the runs:
- **The first prettier check flagged my own scratch files** under `indexer/.scratch/` (ignored by
  git, never committed). I deleted them and the check passed.
- **The first `gh pr checks --watch` returned** before the new run had registered its checks. The
  second watch waited for all 14.

### Measures that moved (`test:node`, the owner's Mac)

| Measure | Result |
|---|---|
| Snapshot of 10 000 lots, open to ready (n=10) | median 25.40 ms, p95 36.51 ms, was 6.53 ms in fix loop 1 |
| RSS with 10 subscriptions of 10 000 lots, opened one after another | 197 → 208 MB, rounded to MB |
| Rewind with 210 subscriptions open | all ready again in 108 ms; `GET /head` max 15.10 ms (n=4); none dropped |
| Q1 page of 100 | median 1.27 ms, p95 1.51 ms |
| RPC calls per served block | 6.50 without subscriptions, 6.30 with 214 open |

- **Why the snapshot is slower:** the measure opens its 10 subscriptions one after another. Pages
  are now released as soon as their reader passes them, so the next subscription reads and
  serialises its own (GPT 1's bound). Subscriptions that snapshot at the same time still share
  their pages, as the rewind measure shows.

### Files changed in this resume

- **Library code:**
  - `src/subscriptions.ts`: reader-counted pages, the byte cap and eviction, isolated writes,
    identity checks, change chunks bounded by `page` and plans by `planBlocks`.
  - `src/store.ts`: `SCHEMA_VERSION` "3", `SchemaMismatch`, the version check at open, the
    `rebuild` drop, `Store.peek`.
  - `src/main.ts`: `rebuild` through `peek` and `{rebuild: true}`; `SchemaMismatch` exits 2.
- **Tests:**
  - `src/subscriptions.test.ts`: 6 new tests and a keeping-up `Reader` sink.
  - `src/store.test.ts`: 2 new tests.
  - `src/main.test.ts`: 1 new test.
- **Docs:** `README.md` (schema 3, identity positions, bounded frames, the pages' cap).
