# [Opus 5.5] IDX-01a — indexer core

## Summary

This run was done by Opus 5.5 (`claude-opus-5-5`), the model the brief names.

`indexer/` is now `@grimworld/indexer`, a package of the pnpm workspace. It is one Node 24 process that follows a Starknet node over JSON-RPC 0.10 and decodes the nine events ENG-01 froze (Hub: 5, Market: 4). It keeps them in SQLite (`node:sqlite`) tables where every row is versioned by block (`_from`, `_to`).

What it does:
- **Tip checks:** it checks the node's block at the stored tip by **hash and commitments**. It also checks every block it applied since the last check the same way before serving it (R6 with an identity check; no view-call reconciliation in this task).
- **Reorgs:** on a fork it finds the fork point and rewinds every table to it **in one SQLite transaction**.
- **Pre-confirmed blocks:** never indexed. The tip is `starknet_blockHashAndNumber`, and a block without a hash is refused.
- **Halts:** it goes `halted`, with the reason in the log and in every answer, on:
  - an undecodable event of the two contracts;
  - a gap in lot or trade ids;
  - a close of a lot or trade that is not open;
  - a node that went back below the kept history.
- **History:** it keeps history down to `--depth <blocks>|l1`, where `l1` is the last L1-accepted block (the default).
- **Restart and rebuild:** it resumes from its database. `rebuild --from <block>` empties the database and rebuilds it from the chain.
- **Serving:** `GET /head` and `GET /stats` follow R1 and R2.

The test emitter, `indexer/emitter/`, has two contracts that emit the nine events on demand. Its event structs are `grimworld_persistent::events`, through a path dependency.

**One part is blocked and escalated (E-1).** That path dependency cannot build: `contracts/persistent` has no `[lib]` target, and Scarb says `ignoring invalid dependency grimworld_persistent which is missing a lib or cairo-plugin target`. As the brief orders, I stopped there, did not copy the events, and did not touch `contracts/`. To show the emitter is right once the line exists, I built it against a scratch copy of `contracts/` with `[lib]` appended. The scratch copy was under the worktree, never committed, and deleted after. That build passes its 10 tests, and it is the build the local-node scenario deployed.

Consequence: the pull request's CI is green except `cairo (indexer/emitter)`, whose `format` step passes and `build` step fails for this reason.

Pull request: https://github.com/bal7hazar/grimworld/pull/144 (branch `cv/IDX-01a-indexer-core`, 3 commits).

## Files changed

| File | What it is |
|---|---|
| `pnpm-workspace.yaml` | + `- indexer` |
| `pnpm-lock.yaml` | the indexer importer (starknet 10.8.0, vitest 5.0.2, @types/node 24.19.0) |
| `indexer/package.json` | `@grimworld/indexer`; scripts `build`, `test`, `test:node`, `lint`, `typecheck` |
| `indexer/tsconfig.json` | typecheck config (see *Deviations*, D-9) |
| `indexer/tsconfig.build.json` | emits `dist/` |
| `indexer/eslint.config.js` | the client's rules |
| `indexer/vitest.config.ts` | unit tests |
| `indexer/vitest.node.config.ts` | the local-node scenario |
| `indexer/.gitignore` | `dist/`, `emitter/target/`, `.with-node/`, sqlite files, scratch, the scenario's results |
| `indexer/src/events.ts` | selectors and a strict decoder of the nine events; market key decoding (ENG-01 §3.4) |
| `indexer/src/chain.ts` | read-only JSON-RPC client counted by method: tip, header by number (hash + 4 commitments), last L1-accepted block, events of both contracts by block hash in (transaction, event) order; `redact()` |
| `indexer/src/store.ts` | SQLite schema, `apply` (one transaction per block, gap and close checks), `rewind` and `prune` (one transaction each), counts, dumps, as-of reads |
| `indexer/src/indexer.ts` | the follow loop: states, identity checks, fork point, rewind, halt, pruning, `run` |
| `indexer/src/server.ts` | `/head` and `/stats` (R1, R2); `answer()` is testable without a socket |
| `indexer/src/main.ts` | CLI: `run` and `rebuild`, SIGTERM/SIGINT |
| `indexer/src/testing/fake-node.ts` | fake JSON-RPC node for the unit tests: mine, reorg (optionally keeping hashes, as devnet does), L1 acceptance, hooks between calls |
| `indexer/src/{events,store,indexer,server}.test.ts` | unit tests (39) |
| `indexer/test-node/node.ts` | the only module that deploys or invokes: local host only, the `NODE_ACCOUNT_*` account only |
| `indexer/test-node/node.test.ts` | offline test of that guard (1) |
| `indexer/test-node/run-indexer.ts` | starts the indexer as a child with `INDEXER_RPC_URL` as its only environment |
| `indexer/test-node/scenario.node.test.ts` | the local-node scenario (8 tests) |
| `indexer/test-node/bin/setsid` | perl stand-in for `setsid(1)`, which macOS lacks (D-2) |
| `indexer/emitter/Scarb.toml` | Scarb 2.19.4 package; path dependency on `../../contracts/persistent`; `casm = true` |
| `indexer/emitter/Scarb.lock` | its lockfile |
| `indexer/emitter/src/{lib,hub,market}.cairo` | `HubEmitter` and `MarketEmitter` |
| `indexer/emitter/tests/test_emitter.cairo` | 10 tests, one or more per event, raw keys and data checked, gas budgets |

## The schema

Every table below has `_from INTEGER NOT NULL, _to INTEGER`. A row is valid at block B when `_from <= B AND (_to IS NULL OR _to > B)`.

**How rows change:**
- A change closes the current version (`_to` = block) and inserts the new one.
- Facts (raw events, trial passes, clears) are inserted and never closed.
- **Rewind to F** deletes rows with `_from > F`, sets `_to = NULL` where `_to > F`, and deletes blocks above F, all in one transaction.
- **Prune at a floor** deletes rows with `_to <= floor` and blocks below the floor. The floor is never above the checked blocks. Raw events are kept.

**Value encodings:**
- u64 values are 16-digit lowercase hex text (ordered like the numbers) and leave as decimal strings.
- felt252 values that are not decoded into columns are canonical `0x` hex.

| Table | Columns (besides `_from`, `_to`) | What a row is |
|---|---|---|
| `meta` | key, value | `schema` (1); `config` (hub, market, from, lotCount, tradeCount: a database is refused for another configuration); `checked` (the highest block checked after it was applied) |
| `blocks` | number, hash, parent, commitments | the applied chain; commitments = transaction, event, receipt and state-diff commitments |
| `events` | source, name, keys (JSON), data (JSON), tx_hash, tx, idx | every raw event of both contracts, for audit |
| `lots` | lot, market_key INTEGER, kind (`balance`/`equipment`/`boss`), item, base, requirement, rarity, identified, lot_size, price, expiry, equipment, modifiers, open, sold, posted | one version per state of a lot (open, then closed with `sold`) |
| `trades` | trade, invited, inviter, open, outcome (null, 0, 1, 2), opened | one version per state of a trade |
| `presence` | adventurer, hub | where an adventurer is; hub 0 means in no hub |
| `titles` | adventurer, title, tier | the displayed title |
| `trial_passes` | adventurer, rank, first_attempt, tx, idx | one fact per `TrialPassed` |
| `clears` | adventurer, dungeon, tx, idx | one fact per `DungeonCleared` |
| `ranks` | adventurer, rank | the rank reached last |

**Indexes:**
- `_from` on every table, and `_to` on every table (partial: `WHERE _to IS NOT NULL`);
- current rows per id (`WHERE _to IS NULL`);
- `lots (market_key, lot_size, price, lot) WHERE open = 1`;
- `trades (invited) WHERE open = 1`;
- `presence (hub)`;
- `trial_passes (adventurer)` and `clears (adventurer)`.

**Invariants that halt:**
- A `LotPosted` whose id is not the last lot id + 1, and the same for `TradeOpened` (ENG-01 §3.4: ids come from counters and are never reused; "the indexer detects a gap").
- A `LotClosed` or `TradeClosed` of an id that is not open.
- Each of these rolls back the block's transaction.

## Commands run

Every command below ran from the worktree root unless it says otherwise.

```
$ pnpm install --frozen-lockfile
Lockfile is up to date, resolution step is skipped
Done in 7ms using pnpm v12.5.1

$ pnpm --filter @grimworld/indexer lint
$ eslint .                      (no findings)

$ pnpm --filter @grimworld/indexer typecheck
$ tsc --noEmit                  (no errors)

$ pnpm --filter @grimworld/indexer test
 Test Files  5 passed (5)
      Tests  40 passed (40)
   Duration  264ms
```

**Mutation check of the unit tests.** I temporarily made `sameBlock` compare hashes only (the SPK-11 fix-loop-1 defect). 10 tests failed:
- the five reorg tests;
- the replacement in the middle of a step;
- the reorg within kept history;
- the restart on a replaced tip;
- the rebuild;
- the `rewinding` answer.

I then restored the comparison.

```
$ pnpm --filter @grimworld/indexer test:node
$ STATE_ARCHIVE_CAPACITY=full PATH="$PWD/test-node/bin:$PATH" ../scripts/with-node.sh vitest run --config vitest.node.config.ts
 Test Files  1 passed (1)
      Tests  8 passed (8)
   Duration  23.95s
```

Its real output (`indexer/.scenario-results.txt`, last run after the final code change):

```
# IDX-01a local-node scenario, 2026-09-29T11:46:49.249Z
deployed: HubEmitter at block 2, MarketEmitter at block 4; indexing from 2
indexer: [indexer 2026-09-29T11:46:59.942Z] serving on http://127.0.0.1:51771, following http://127.0.0.1:28826 from block 2; stored tip none; depth 100000
AC-1: blocks 5..9 served 38 ms after the last receipt
AC-1: 19 events in 9 kinds; lots, trades, presence, titles, trial_passes, clears, ranks as sent
AC-2 depth 1: blocks 10..10 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 10->9 in 0.44 ms; new tip served 65 ms after the abort; tables equal a rebuild: true
AC-2 depth 2: blocks 11..12 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 12->10 in 0.27 ms; new tip served 65 ms after the abort; tables equal a rebuild: true
AC-2 depth 3: blocks 13..15 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 15->12 in 0.18 ms; new tip served 111 ms after the abort; tables equal a rebuild: true
AC-2 depth 4: blocks 16..19 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 19->15 in 0.17 ms; new tip served 154 ms after the abort; tables equal a rebuild: true
AC-2 depth 5: blocks 20..24 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 24->19 in 0.20 ms; new tip served 164 ms after the abort; tables equal a rebuild: true
AC-3: stopped at block 24; 3 blocks sent while stopped; restarted: blocksApplied 3 (blocks 25..27); 55 raw events, no position twice; rebuild --from 2: same tables
AC-8 catch-up: rebuild --from 2 to 277: 276 blocks, 5055 events in 0.46 s (process start included): 600 blocks/s, 10989 events/s; maxRSS 187 MB; RPC {"starknet_blockHashAndNumber":4,"starknet_getBlockWithTxHashes":552,"starknet_getEvents":552}; database 1.66 MB (329 bytes per event, all blocks kept); same tables as the live indexer: true
AC-8 empty blocks: rebuild --from 78 to 277: 200 blocks without events in 0.31 s (1.54 ms per block); RPC {"starknet_blockHashAndNumber":3,"starknet_getBlockWithTxHashes":400,"starknet_getEvents":400} = 4.01 calls per block
AC-8 idle following (poll 50 ms), 5 s: RPC {"starknet_blockHashAndNumber":91,"starknet_getBlockWithTxHashes":91,"starknet_getEvents":0} = 36.4 calls per second, 2.00 per poll
AC-8 live indexer: maxRSS 187 MB, rss 187 MB, 253 blocks and 5006 events applied since its restart
logs: [indexer 2026-09-29T11:47:02.256Z] serving on http://127.0.0.1:51799, following http://127.0.0.1:28826 from block 2; stored tip 24 0x5526d049ee5405a0853c48a84928c83c0dcd33c9a230e9927cf47f7aebcf5b4; depth 100000
      [indexer 2026-09-29T11:47:02.264Z] status ok
```

About the scenario's checks:
- **"Tables equal a rebuild"** compares every row of every version of every table, plus the blocks, between the live indexer's database and one produced by a separate `rebuild --from 2` process.
- **The indexer's logs** were also checked: none contains the node account's private key. The child's environment is `INDEXER_RPC_URL` only.

The emitter builds, with the committed manifest (E-1):

```
$ scarb --manifest-path indexer/emitter/Scarb.toml build
warn: grimworld_indexer_emitter v0.1.0 (…/indexer/emitter/Scarb.toml) ignoring invalid dependency `grimworld_persistent` which is missing a lib or cairo-plugin target
error: could not compile `grimworld_indexer_emitter` due to 19 previous errors and 3 warnings
```

`cd indexer/emitter && snforge test` fails the same way.

Against the scratch copy with `[lib]` appended to `persistent/Scarb.toml`:

```
$ scarb --manifest-path indexer/.scratch/indexer/emitter/Scarb.toml build
   Compiling grimworld_indexer_emitter v0.1.0 (…)
    Finished `dev` profile target(s) in 1 second
$ (cd indexer/.scratch/indexer/emitter) scarb fmt --check && snforge test
Tests: 10 passed, 0 failed, 0 ignored, 0 filtered out
```

Root gates:

```
$ pnpm lint        client/sim, client/app, indexer: Done
$ pnpm typecheck   client/sim, client/app, indexer: Done
$ pnpm test        indexer 40 passed; client/sim 8 passed; client/app 43 passed, 1 skipped
$ pnpm build       client/app built; indexer tsc -p tsconfig.build.json
$ pnpm exec prettier --check indexer
Checking formatting...
All matched files use Prettier code style!
```

The prettier check is run after deleting the untracked `dist/` and `emitter/target/` (E-2). Before that deletion, prettier run from the root flagged those build outputs: it reads only the root `.gitignore`.

Pull request CI (`gh pr checks 144 --watch`):

```
cairo (indexer/emitter)  fail   format ✓, build ✗ (E-1)
cairo (contracts)        pass
cairo (spikes/…) ×8      pass
client                   pass   (runs pnpm lint/typecheck/test/build over the workspace, indexer included)
discover, tooling        pass
```

## Cost

These figures were measured on the scratch copy with `[lib]` (snforge 0.61.0). `scripts/gas_budgets.py --report` supports Scarb workspaces only (`KeyError: 'workspace'` on a single package), so the table was built from the snforge output by hand.

Each budget is `ceil(1.05 × measured)`, and each test deploys its emitter.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---:|---:|---|
| test_emitter::test_adventurer_located | — | 362,470 | 380,594 | new |
| test_emitter::test_adventurer_located_in_no_hub | — | 362,470 | 380,594 | new |
| test_emitter::test_title_displayed | — | 373,070 | 391,724 | new |
| test_emitter::test_trial_passed | — | 373,110 | 391,766 | new |
| test_emitter::test_dungeon_cleared | — | 362,570 | 380,699 | new |
| test_emitter::test_rank_reached | — | 362,470 | 380,594 | new |
| test_emitter::test_lot_posted | — | 419,210 | 440,171 | new, u64 extremes |
| test_emitter::test_lot_closed | — | 363,210 | 381,371 | new |
| test_emitter::test_trade_opened | — | 373,470 | 392,144 | new |
| test_emitter::test_trade_closed | — | 362,870 | 381,014 | new |

No budget of `contracts/` was touched.

## The measures (AC-8)

These come from devnet 0.10.0 on the owner's Mac (arm64), with the node and the indexer on the same machine. The SPK-11 figures were taken on the VPS.

| Figure | IDX-01a | SPK-11 prototype |
|---|---|---|
| Catch-up from an empty database | 276 blocks, 5,055 events in 0.46 s including process start (600 blocks/s, ~11,000 events/s) | 10,000 events over 101 blocks in 1.13 s |
| RPC calls per block during catch-up | 2 `getBlockWithTxHashes` + 2 `getEvents` = **4.01 per block** | 2.04 |
| Empty blocks | 1.54 ms per block | 2.51 ms |
| Idle following | **2.00 calls per poll** (tip + header): 36.4 calls/s at a 50 ms poll, so 2/s at the default 1 s poll | 2 per poll |
| Peak RSS | **187 MB** (`src/main.ts` run by Node with type stripping, starknet.js loaded) | 119 MB |
| Disk | 1.66 MB for 5,055 events and 276 blocks: **329 bytes per event** | 137 bytes |
| Rewind time, SQLite transaction only | 0.17–0.44 ms for depths 1–5 | — |
| Time until the new tip is served after `devnet_abortBlocks` | 65–164 ms, poll 50 ms, including sending the d replacement transactions | 491 ms at a 500 ms poll |
| Live latency, last receipt to served | 38 ms | median 62 ms |

Why per-block calls doubled relative to SPK-11:
- `getEvents` is called once per contract, because the 0.10 event filter takes one address.
- Every applied block is read a second time before it is served, because a replacement's parent hash proves nothing on devnet.

On Starknet, where the hash commits to the commitments, the second read could be dropped when a block's child is applied on top of it. That is not done here: devnet is where it is proven.

Disk rose because this version keeps raw events as JSON text, has more columns per lot, and has more indexes.

## Acceptance criteria

- **AC-1: met on the local node.** Scenario test `AC-1` checks:
  - every column of the three lots: a balance key 77, an equipment key (7, 12, 3, identified), a boss key 2^41+5, price 2^64−1, 2^53+1 and 1, expiry 2^63, 2^64−1 and 0, equipment 2^32−1, modifiers `0x1234abcd`;
  - `sold` true and false;
  - trades with outcomes 0, 1 and 2;
  - presence, including hub 0 and hub 65535 for adventurer 2^32−1;
  - the title (65535, 255);
  - trial passes with `first_attempt` true and false;
  - the clear and the rank;
  - the 19 raw events in block order, interleaved across both contracts inside one transaction.

  Unit tests cover decoding and refusals (`events.test.ts`).
- **AC-2: met on the local node.** Scenario tests `AC-2 depth 1..5`:
  - `devnet_abortBlocks` and replacement transactions give replacement hashes equal to the aborted ones with other commitments, so the detection can only have come from commitments;
  - one rewind to `first − 1` per depth;
  - tables equal to a separate `rebuild` each time.

  Unit tests cover the same five depths on the fake node with same-hash replacements, and a replacement in the middle of a step.
- **AC-3: met.** Scenario test `AC-3`:
  - the indexer was stopped by SIGTERM (exit 0) and 3 blocks were sent;
  - after restart, the log says `stored tip 24`, `blocksApplied` is 3, and no raw event position appears twice;
  - `rebuild --from 2` gives the same tables.

  Unit tests cover the restart, the restart onto a replaced tip, and the rebuild after `clear`.
- **AC-4: met by unit tests.** The `halting` tests in `indexer.test.ts` cover an undecodable event (unknown selector; a value wider than u64), a gap in lot ids, and the node going below the kept history. Each checks the reason and the 503 `halted`.
- **AC-5: met by unit tests.** `server.test.ts` covers `loading`, `ok` with `{number, hash, commitments}` and `behind`, `rewinding` and `halted`. No `tables`/`versions` appear in any 503. It also tests HTTP GET, 404 and 405.
- **AC-6: not met.** The emitter reuses the structs of `grimworld_persistent::events` by a path dependency, but that dependency cannot build until `contracts/persistent` has `[lib]` (E-1). Against a copy with that line, it builds and its 10 tests pass with budgets. CI for it is red.
- **AC-7: partly met.**
  - Root `pnpm lint`, `pnpm typecheck`, `pnpm test` and `pnpm build` pass.
  - `pnpm exec prettier --check indexer` passes once untracked build outputs are removed (E-2).
  - Pull-request CI is green except `cairo (indexer/emitter)` (E-1).
- **AC-8: met.** See *The measures* and the scenario output above.

## Deviations from the brief

1. **The emitter's event enums.** First I tried reusing `Hub::Event` and `Market::Event` themselves as a `#[flat]` variant, which would be the strongest guarantee. The Cairo 2.19 derive refused it (`Into<Event, Event> has multiple implementations`). Each contract instead declares its own `Event` enum with the game contract's variant names, in its order, over the imported structs. The first key is therefore the same selector: the local node's probe reported `RankReached` as `0x16d3…cd7d`, which a unit test pins.
2. **`setsid` on macOS.**
   - `scripts/with-node.sh` runs `setsid "$@"`, and macOS has no `setsid(1)`. On the Mac, `scripts/with-node.sh printenv NODE_URL` exits 127 with `setsid: command not found`.
   - `pnpm test:node` therefore puts `indexer/test-node/bin/` first on `PATH`. That folder holds a perl stand-in: `POSIX::setsid` then `exec`, which keeps the pid. It refuses to run the command if `setsid` fails.
   - It is used only by this script. It works on Linux too, where it shadows the real `setsid` for this one script.
3. **What "a gap" means.** I took "a gap" as ENG-01 §3.4's gap in lot and trade ids ("the indexer detects a gap"). A block that is missing on the node, or whose parent is not the stored tip, is retried at the next step, because the tip checks turn it into a rewind.
4. **One more halt.** The indexer also halts on a close of a lot or trade that is not open (from the prototype). Without it the tables would silently diverge.
5. **`--lot-count` and `--trade-count`.** These give the counters at the block before `--from` (default 0, the deployment's). I added them so the id-gap check can start at a later block and so u64-extreme ids are reachable in unit tests. A start after deployment still halts on a close of a lot posted before `--from`: a complete index starts at the deployment block.
6. **Reconciliation is an identity check.** Before a block is served, it is read again after it was applied and must have the same hash and commitments. The views are not called, as the brief says. The mark `meta.checked` survives restarts, so a restart re-reads only the unchecked blocks.
7. **`/stats` in `loading`, `rewinding` and `halted`.** It answers 503 with the state, reason, head (null, or the last served block when halted) and the process's own figures (RPC calls, RSS, blocks applied, rewinds), but never table counts. `/head` answers 503 with the state, reason and head only.
8. **Facts and raw events have a `_to` column** that is never set, so the rewind code is the same for every table.
9. **The TypeScript configuration.**
   - The client's Bundler/`noEmit` base does not fit a Node process. `tsconfig.json` uses NodeNext, `types: ["node"]`, `erasableSyntaxOnly` and `allowImportingTsExtensions`, so Node 24 runs `src/*.ts` as they are (the scenario runs `src/main.ts`). It keeps the client's strictness.
   - `tsconfig.build.json` emits `dist/` with `rewriteRelativeImportExtensions`.
   - **`@types/node` 24.19.0** is the one added dependency, for `node:sqlite` and `node:http` types. It matches the Node 24 runtime; the lockfile's other copy, 26.6.3, comes in transitively through vite and vitest.
10. **`Store` has a `readOnly` option.** The scenario uses it to read the running indexer's database beside it.
11. **The sending module stays.** `test-node/node.ts`, the local-node sending module, is permanent: the scenario needs it on every run. COMMON §4's removal rule is written for Sepolia. The module refuses any host but `127.0.0.1` and `localhost` (offline test `test-node/node.test.ts`), reads only `NODE_URL`, `NODE_ACCOUNT_ADDRESS` and `NODE_ACCOUNT_PRIVATE_KEY`, and exports no account. It also calls `devnet_createBlock` for the empty-block measure.
12. **The gas table was built by hand** (see *Cost*).
13. **A difference from the brief's context.** The brief says the game's contracts emit nothing yet. `Hub` already emits `AdventurerLocated` in `enter` (hub 0), `travel` and `report` (`contracts/persistent/src/systems/hub.cairo` lines 484, 501, 713). All `Market` entrypoints and views still panic `'not implemented'`. The nine layouts in `events.cairo` are exactly the brief's table.

## Escalations

- **E-1 (blocker, AC-6 and CI): `contracts/persistent/Scarb.toml` needs a `[lib]` target.**
  - Without it Scarb ignores the package as a dependency.
  - The one-line fix (`[lib]` beside `[[target.starknet-contract]]`) was verified on a scratch copy. The emitter then builds, its 10 tests pass, and the persistent package still builds.
  - Whether it changes anything for `contracts/`' own CI (class sizes, gas) is for the orchestrator to check.
  - Until it lands, the committed `indexer/emitter` fails CI at `build`. Once it is on `main`, merging `main` into this branch should turn CI green with no change here.
  - Alternative, not taken: a symlink of `events.cairo` into the emitter. It is one source, but not the path dependency the brief asks for.
- **E-2: prettier and ignore files.**
  - The CI's prettier step and the root `format` script cover `client` only; `indexer` should be added.
  - With it, the root `.gitignore` (or a root `.prettierignore`) needs `indexer/dist/` and `indexer/emitter/target/`, as it has `client/*/dist/` and `contracts/target/`. Prettier run from the root does not read `indexer/.gitignore`, and the CI runs `pnpm build` before prettier, so `dist/` would be checked.
- **E-3: the local-node scenario runs only where starknet-devnet is installed.** The CI's `client` job has no starknet-devnet, so `test:node` runs on the Mac (or the VPS) only; `pnpm test` skips it.
- **E-4: `scripts/with-node.sh`.**
  - It needs `setsid(1)`, which macOS lacks (D-2's stand-in works around it for this package only).
  - It passes `STATE_ARCHIVE_CAPACITY` through the environment only.
  - A `--full-archive` option and a macOS fallback for `setsid` would let other packages use it on the Mac.

## Open questions

1. **Rarity above 127 in the market key.** `rarity × 2` occupies bits 1–7, so a rarity of 128 or more would carry into `requirement`. The decoder reads 7 bits. ENG-01 should bound rarity, or say the key is unique only below 128.
2. **Withdrawn or returned.** `LotClosed { sold: false }` does not say whether the lot was withdrawn or returned after expiry. The table keeps `sold` 0/1 only.
3. **Reconciliation against the views, once the market exists (RWD-10).** At each block about to be served:
   - call `lot_count`, `open_lot_count` and `trade_count` by block hash;
   - compare them with the tables at that block (`max(lot)`, the count of lots with `open = 1`, `max(trade)`);
   - re-read the block's header after the calls and require the same identity (devnet reuses hashes);
   - halt on a mismatch.

   It fits in `Indexer.step` between the identity checks and `setChecked`. It costs 3 `starknet_call` per new tip, about 60 CU at Alchemy's rates.
4. **What the out-of-scope features would need:**
   - **WebSocket wake-up:** a `starknet_subscribeNewHeads` subscription that calls `step()` instead of the poll timer. The identity checks stay as they are.
   - **Range catch-up below L1 acceptance:** `getEvents` over `[from, l1_accepted]` per contract, paged. Every block's header in the range is still needed for `blocks`, or the stored history starts at `l1_accepted` with the rows of earlier blocks inserted without block rows.
   - **Alerting:** a watcher on `/head` answering 503 `halted`, or a log line `status halted`.
5. **A rebuild from a block after deployment** would need the counters (views) and the open lots and trades at that block. For now `--from` should be the deployment block.

## What IDX-01b needs from this

- **`Indexer`:** `served` (the head every answer is read at, R6), `status`, `reason`, `chainTip`.
- **`answer()` in `server.ts`:** a pattern for R1 gating and R2 heads that the query routes can reuse. `headOf()` shapes a head.
- **`Store` reads:** as-of reads by `_from <= B AND (_to IS NULL OR _to > B)`, and `u64Decimal()` for u64 text. The indexes for "cheapest open lot per (market_key, lot_size)", "open trades by invited account" and "presence by hub" exist. The prepared queries themselves are IDX-01b's.
- **Subscription hooks:** the loop has none yet. IDX-01b needs callbacks from `Indexer` at "block served" (after `setStatus("ok")`) and at "rewind" (in `rewind()`), to publish events held until their block is served and to send snapshots (R4).
- **The 7-day average price** (scope 6) needs sale times. A sale's time is its block's (events.cairo), and `blocks` has no timestamp yet. `Chain.header` can add `timestamp` from `getBlockWithTxHashes` at no extra call.

## Resume 1

**What was asked:** fix the red `cairo (indexer/emitter)` job of #144 (run 36563950321, job 109391267414, head 00b3b57) inside `indexer/**`. The request assumed the emitter builds on the Mac and that the CI runs it differently.

**Result:**
- **Not fixable inside the allowlist.** The CI and the Mac behave the same. The emitter has never built with the committed manifest on either one: in the first run it built only against a scratch copy of `contracts/` with `[lib]` added (*Summary* and E-1 above).
- **Nothing was changed or pushed.** #144's CI is unchanged: red on `cairo (indexer/emitter)` only.
- **The exact change is escalated below** (E-1, restated).

### What the CI runs

From `.github/workflows/ci.yml` and `.github/ci/discover.py`:
- **The job:** `discover.py` makes every tracked `Scarb.toml` that is not a member of a workspace its own job root, so `indexer/emitter` is one job.
- **The toolchain:** it takes its Scarb and snforge from the nearest `.tool-versions`, which is the root's: Scarb 2.19.4, snforge 0.61.0.
- **The commands:** the `cairo` job runs them with `working-directory: indexer/emitter`:
  - `scarb fmt --check --workspace`
  - `scarb build --workspace`
  - `snforge test --workspace`
- **The path dependency:** Scarb resolves `grimworld_persistent = { path = "../../contracts/persistent" }` against the checked-out tree, as it does locally.

### Reproduction on the Mac

The CI's exact commands, from `indexer/emitter`, with the same Scarb:

```
$ scarb --version
scarb 2.19.4 (b45b74c03 2026-07-21)
$ scarb fmt --check --workspace          (passes, as in CI)
$ scarb build --workspace
warn: grimworld_indexer_emitter v0.1.0 (…/indexer/emitter/Scarb.toml) ignoring invalid dependency `grimworld_persistent` which is missing a lib or cairo-plugin target
error[E0006]: Identifier not found.
 --> …/indexer/emitter/src/hub.cairo:13:9
error[E0006]: Identifier not found.
 --> …/indexer/emitter/src/market.cairo:21:9
error: could not compile `grimworld_indexer_emitter` due to 19 previous errors and 3 warnings
```

These are the CI's errors, at the same lines.

**The cause** is the `warn` line. `contracts/persistent/Scarb.toml` declares only `[[target.starknet-contract]]`, with no `[lib]`. Scarb therefore drops the package as a dependency, so `grimworld_persistent::events` does not exist in the emitter's crate. The type-inference errors all follow from that.

**Why nothing inside `indexer/**` can fix it:** a dependent package cannot give its dependency a target. Every alternative stops using the path dependency, and the brief forbids that: "by a path dependency, never a copy; if that cannot build, stop and escalate". I considered and did not implement:
- a copy of the events;
- a symlink to `events.cairo`;
- a wrapper package in `indexer/` whose `[lib]` compiles `contracts/persistent/src` under the same name, which would also add a CI job re-testing `persistent`.

### The fix, verified

**E-1 (restated, exact change):** in `contracts/persistent/Scarb.toml`, insert these two lines just before `[[target.starknet-contract]]`:

```toml
[lib]

```

I verified it in a scratch copy of `contracts/` (logic, persistent, ephemeral, seed, tools, the workspace manifest and lock). The copy was made under the worktree, never committed, and deleted after. With the CI's own commands:

- **Emitter job** (`indexer/emitter`, path dependency onto the patched copy):
  - `scarb fmt --check --workspace` passes.
  - `scarb build --workspace`: `Finished`.
  - `snforge test --workspace`: `Tests: 10 passed, 0 failed`, with the gas budgets.
- **`contracts` job** (the workspace with `[lib]` added):
  - `scarb fmt --check --workspace` passes.
  - `scarb build --workspace`: `Finished`.
  - `snforge test --workspace`: `Tests: 43 passed`, `54 passed` and `128 passed`, 0 failed. Every test has a budget, so no budget was exceeded.
  - `python3 tools/class_sizes.py`: every class `ok`, unchanged in kind. The largest are Hub at 742,928 bytes (35.38 %) and Instances at 724,161 bytes (35.21 %).
  - Not run on the copy: `scripts/gas_budgets.py --check` (it needs `contracts/` itself and origin/main) and `exp2_table.py --check`. The line changes no Cairo source, test or table, and the gas budgets are enforced by the snforge run above.

**Once the line is on `main`:** merging `main` into `cv/IDX-01a-indexer-core` should turn #144's CI green with no change in `indexer/`. I have not merged, because the line is not on `main` yet.

**CI not watched this time:** `gh pr checks 144 --watch` was not run again because nothing was pushed. The checks are those of head 00b3b57, reported above.

**The other escalations** (E-2: the root `.gitignore`, prettier in CI and the root `format` script; E-3: devnet in CI; E-4: `with-node.sh` on macOS) are with the orchestrator, as instructed. Nothing was changed for them.

**Files:** the scratch copy and the failed build's `indexer/emitter/target/` were deleted. The worktree is clean apart from this report.

## Resume 2

**What was asked:** fix loop 1 on the two audits of #144 (Opus 5.5; GPT-6-Sol), as accepted by the orchestrator.

**Commits pushed:**
- `be43147` fix(indexer): IDX-01a fix loop 1: node answers validated, race of the same-hash replacement, ancestor window, server guards, CLI bounds
- `25acaa5` test(indexer): IDX-01a fix loop 1: the race and the halt re-check, server 400/500 and head, CLI refusals, pruning on the local node

**CI is now green on every check, `cairo (indexer/emitter)` included.** D-153 (#148) put `[lib]` in `contracts/persistent/Scarb.toml` on `main`, and the PR's CI builds the branch merged with `main`, so E-1 is resolved. The branch itself was not merged with `main`: nothing asked for it and nothing needs it.

### Findings and what changed

| Finding | Change | Test |
|---|---|---|
| Opus 1 (medium): `new URL` unguarded in the listener; `GET //[` kills the process | `server.ts`: `respond()` answers 405 unless GET and 400 for a target that is not a path (`URL.canParse`). Any throw while answering is a 500 with no detail. The listener has its own try/catch | `server.test.ts`, *fix loop 1*: 400 for `//[`, `http://indexer/head`, `*` and `//`; 500 when `countsAt` throws; `GET //[ HTTP/1.1` on a raw socket gets `HTTP/1.1 400`, and `/head` answers 200 afterwards |
| Opus 2 (medium): under devnet's same-hash quirk, N+1 applies on a stale N and a false halt becomes permanent | See below | See below |
| Opus 3 (low), GPT 5 (minor): the RPC URL and provider text in logs | See below | See below |
| Opus 4 = GPT 4 (low): checked ancestors are never re-verified | See below | See below |
| Opus 5 (low): `--batch 0` and `--poll 0` spin | Both must be ≥ 1, and so must `--depth` and `--recheck-every`. `Indexer` also enforces batch ≥ 1 and poll ≥ 1 itself | `main.test.ts` (exit 2, `must be a whole number of at least 1`); `indexer.test.ts` `runs at least one block per step and waits at least 1 ms` |
| Opus 6 (low): counters parsed with `Number` | `--lot-count` and `--trade-count` are parsed as bigint, `^\d+$`, and must be < 2^64 | `main.test.ts`: `18446744073709551616`, `1e3` and `-1` are refused |
| Opus 7 (low): `rebuild --from` later than deployment | See below | See below |
| Opus 8 (info): 404 and 405 without head | Every error answer carries `{error, status, head}` | `server.test.ts` |
| Opus 9 (info): unbounded rewind list | `rewindCount`, plus the last `REWINDS_KEPT` = 20 rewinds (`/stats`: `rewindCount`, `rewinds`) | `keeps a count of rewinds and only the last ones` (25 rewinds: count 25, 20 kept) |
| Opus 11 (tests): pre-confirmed, redact, the race, pruning on the local node | All four added | `chain.test.ts` (pre-confirmed and hash-less refused; `redact`), the race tests (below), and the pruning scenario test (below) |
| GPT 2 (major): a header's height not checked | `Chain.header(block, number)` refuses a block whose `block_number` is not the height asked, and one without a parent hash (`BadAnswer`: the step fails and is retried; nothing is applied). Events must carry the block's number as well as its hash | `chain.test.ts`: another height, a node answering another height, events of another number; `indexer.test.ts` `retries, never applies, a block of another height or without commitments` |
| GPT 3 (major): missing commitments replaced by `-` | An accepted block missing any of its four commitments (absent or null) is a `BadAnswer`: never stored, the step retried. Identity is hash AND commitments | `chain.test.ts` (each commitment and the parent, absent and null); the same `indexer.test.ts` test |

**Opus 2, the race under devnet's same-hash quirk.** Two guards in `indexer.ts`, step 3:
1. **The parent is read again.** Block N+1 is applied only after the stored tip N is read again, after N+1's header and events. N must still have the stored hash AND commitments; otherwise the step ends and the next one rewinds. That read also counts as N's check, so catch-up still costs 4 calls per block.
2. **A halt is checked before it becomes permanent.** A Halt raised while applying (a gap, no such lot or trade, undecodable) becomes permanent only if N+1 and N are both still the node's when read again. Otherwise it is logged (`block … changed while it was applied (…); checking again`) and the next step rewinds.

Tests, on the fake node (blocks 5 and 6 replaced under the same hashes while block 6 is read; 5' posts lot 6 and 6' closes it):
- `applies a block only if its parent is still the stored one` — one rewind, never the halt path, tables equal a rebuild's;
- `does not make a halt permanent when the block or its parent changed meanwhile` — the re-read is made to answer the stale block once, so the halt path runs, is not made permanent, and the tables equal a rebuild's;
- `still halts for good when the block and its parent are the node's`.

Mutation check:
- with the re-read removed, both race tests fail;
- with every halt made permanent, the second fails.

**Opus 3 and GPT 5, secrets in logs.**
- `main.ts` refuses, before anything else, an RPC URL that is not http(s): `the RPC URL is not an http(s) URL (not shown)`, exit 2.
- `redact()` never throws: an invalid URL becomes `(not an http(s) URL; not shown)`.
- `RpcError` holds the method and code only (`starknet_getEvents: JSON-RPC error 24`), never the provider's message.
- A fetch failure is `<method>: transport error <cause code>`. undici's message and its `cause` are dropped, since they can hold the URL; one eslint `preserve-caught-error` exception is written on that line with the reason.

Tests:
- `main.test.ts`: three bad URLs holding `SECRETKEY`; the output never holds it;
- `chain.test.ts`: `redact`, `parseRpcUrl`, `RpcError`, and a real refused connection to `http://127.0.0.1:1/SECRETKEY?key=SECRETQUERY`, whose message holds neither the key nor the host.

**Opus 4 = GPT 4, re-verifying ancestors.** Step 2 re-reads the last `--recheck` blocks below the tip (default 10), at most once every `--recheck-every` ms (default 10,000).

Cost: `recheck` extra header reads per period, so 1 call per second on average at the defaults, on top of the 2 calls per idle poll. At the default 1 s poll that is 3 calls per second instead of 2. The scenario, at a 50 ms poll, measured 2.11 calls per poll.

Test, `checks a window of ancestors again`:
- Block 4 is replaced under two empty blocks that keep their hashes and commitments.
- With `depth: 0` the change goes unseen and the tables differ from a rebuild. This shows why the window is needed.
- With `depth: 10` there is one rewind 6→3 and the tables equal a rebuild's.

**Opus 7, `rebuild --from` a later block.**
- `rebuild --from X` is refused (exit 2) when the database was built from another block, and the database is kept: `this database was built from block 5, the contracts' deployment; a rebuild starts there (a later start would need the lots and trades open at that block)`.
- `run` on a database built for another configuration was already refused.
- `README.md` states it, and says how a later start would be seeded: the views `lot`, `trade`, `lot_count`, `trade_count` at that block, once RWD-10 implements them.

Test: `main.test.ts`.

**Pruning on the local node** (new scenario test):
- A `run --depth 20` indexer kept blocks from 259 at tip 279.
- A reorg of 3 blocks inside the kept history was rewound.
- Every table read as of the tip equals the unpruned indexer's.

**Not for me: GPT 1 and Opus 10.** The ambiguity of the equipment key is ENG-01's. The assumption `rarity < 128` is written where the decoder reads it (`src/events.ts`, the comment of `decodeMarketKey` and the line that reads 7 bits) and in the new `indexer/README.md`. Nothing else was changed there.

### Files

**Changed:**
- `indexer/src/chain.ts`
- `indexer/src/indexer.ts`
- `indexer/src/server.ts`
- `indexer/src/main.ts`
- `indexer/src/events.ts` (the comment only)
- `indexer/src/testing/fake-node.ts` (a `tamper` hook; `beforeCall` gets the params)
- `indexer/src/indexer.test.ts`
- `indexer/src/server.test.ts`
- `indexer/test-node/scenario.node.test.ts`

**New:**
- `indexer/src/chain.test.ts`
- `indexer/src/main.test.ts`
- `indexer/README.md`

### Verification, real output

```
$ pnpm install --frozen-lockfile
Done in 7ms using pnpm v12.5.1
$ pnpm lint
client/sim lint: Done
client/app lint: Done
indexer lint: Done
$ pnpm typecheck
client/sim typecheck: Done
indexer typecheck: Done
client/app typecheck: Done
$ pnpm test
client/sim test:  Test Files  2 passed (2)
client/sim test:       Tests  8 passed (8)
client/app test:  Test Files  5 passed | 1 skipped (6)
client/app test:       Tests  43 passed | 1 skipped (44)
indexer test:  Test Files  7 passed (7)
indexer test:       Tests  65 passed (65)
$ pnpm build
indexer build: Done
client/app build: ✓ built in 102ms
client/app build: Done
$ pnpm exec prettier --check indexer        (after removing the untracked dist/ and emitter/target/, E-2)
Checking formatting...
All matched files use Prettier code style!
$ pnpm --filter @grimworld/indexer test:node
 Test Files  1 passed (1)
      Tests  9 passed (9)
   Duration  25.17s (tests 100%)
```

**How `test:node` got its emitter.** The branch does not carry D-153, so the emitter's artifacts were built as in the first run: against a scratch copy of `contracts/` with the same `[lib]` line, never committed, deleted after. `scarb build` printed `Finished`. The artifacts were copied to `indexer/emitter/target/dev/`, then deleted.

The scenario's output (`indexer/.scenario-results.txt`):

```
# IDX-01a local-node scenario, 2026-09-29T12:11:05.461Z
deployed: HubEmitter at block 2, MarketEmitter at block 4; indexing from 2
indexer: [indexer 2026-09-29T12:11:16.177Z] serving on http://127.0.0.1:52453, following http://127.0.0.1:23601 from block 2; stored tip none; depth 100000
AC-1: blocks 5..9 served 3 ms after the last receipt
AC-1: 19 events in 9 kinds; lots, trades, presence, titles, trial_passes, clears, ranks as sent
AC-2 depth 1: blocks 10..10 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 10->9 in 0.22 ms; new tip served 43 ms after the abort; tables equal a rebuild: true
AC-2 depth 2: blocks 11..12 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 12->10 in 0.25 ms; new tip served 61 ms after the abort; tables equal a rebuild: true
AC-2 depth 3: blocks 13..15 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 15->12 in 0.22 ms; new tip served 116 ms after the abort; tables equal a rebuild: true
AC-2 depth 4: blocks 16..19 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 19->15 in 0.18 ms; new tip served 127 ms after the abort; tables equal a rebuild: true
AC-2 depth 5: blocks 20..24 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 24->19 in 0.17 ms; new tip served 154 ms after the abort; tables equal a rebuild: true
AC-3: stopped at block 24; 3 blocks sent while stopped; restarted: blocksApplied 3 (blocks 25..27); 55 raw events, no position twice; rebuild --from 2: same tables
AC-8 catch-up: rebuild --from 2 to 277: 276 blocks, 5055 events in 0.47 s (process start included): 589 blocks/s, 10789 events/s; maxRSS 191 MB; RPC {"starknet_blockHashAndNumber":4,"starknet_getBlockWithTxHashes":564,"starknet_getEvents":552}; database 1.66 MB (329 bytes per event, all blocks kept); same tables as the live indexer: true
AC-8 empty blocks: rebuild --from 78 to 277: 200 blocks without events in 0.33 s (1.63 ms per block); RPC {"starknet_blockHashAndNumber":3,"starknet_getBlockWithTxHashes":411,"starknet_getEvents":400} = 4.07 calls per block
AC-8 idle following (poll 50 ms), 5 s: RPC {"starknet_blockHashAndNumber":89,"starknet_getBlockWithTxHashes":99,"starknet_getEvents":0} = 37.6 calls per second, 2.11 per poll
AC-8 live indexer: maxRSS 194 MB, rss 194 MB, 253 blocks and 5006 events applied since its restart
logs: [indexer 2026-09-29T12:11:18.455Z] serving on http://127.0.0.1:52481, following http://127.0.0.1:23601 from block 2; stored tip 24 0x5526d049ee5405a0853c48a84928c83c0dcd33c9a230e9927cf47f7aebcf5b4; depth 100000
      [indexer 2026-09-29T12:11:18.473Z] status ok
fix loop 1, pruning: --depth 20: lowest kept block 259 at tip 279; 10098 row versions kept of 10118 in the unpruned database; abort of blocks 276.. rewound (1 rewind); tables as of the tip equal the unpruned indexer's: true
```

**Measures against the first run:**
- Catch-up is unchanged at 4 calls per block: 564 headers for 276 blocks, the extra 12 being the ancestor window.
- Idle following is 2.11 calls per poll instead of 2.00; the difference is the window (10 headers per 10 s).
- The rest is within noise: maxRSS 191–194 MB against 187; catch-up 589 blocks/s against 600.

Pull-request CI after the push (`gh pr checks 144 --watch`, head 25acaa5, merged with `main` by the CI):

```
cairo (indexer/emitter)  pass 21s
cairo (contracts)        pass 1m4s
cairo (spikes/…) ×8      pass
client                   pass 24s
discover                 pass 4s
tooling                  pass 34s
```

**The emitter's gas** is as in the first run's *Cost* table: no Cairo file changed. Its tests now run in CI (`cairo (indexer/emitter)` pass).

**Remaining escalations** (E-2 root `.gitignore` and prettier, E-3 devnet in CI, E-4 `with-node.sh` on macOS) stay with the orchestrator. E-1 is resolved by D-153.

**Files left:** the scratch copy, `indexer/dist/`, `indexer/emitter/target/` and `client/app/dist/` from this run were deleted. The worktree holds only ignored files: `REPORT.md` and `indexer/.scenario-results.txt`.

## Resume 3

**What was asked:** D-153 answered the escalations.
- E-1: `[lib]` is on `main` (#148). Merge `origin/main` and run on the real tree.
- Granted for the indexer only:
  - `.github/workflows/ci.yml` (the prettier step and a new job);
  - the root `package.json` `format` script;
  - the root `.gitignore`.

**Commits pushed:**
- `668cb0a` Merge `origin/main` into `cv/IDX-01a-indexer-core`: `git fetch` then `git merge origin/main`, no rebase, no conflict.
- `e40cd51` ci: IDX-01a (D-153), prettier and format cover indexer; indexer build outputs ignored; a starknet-devnet job runs the indexer's local-node scenario when indexer/ changes.

### 1. The real tree (E-1 closed)

After the merge, `contracts/persistent/Scarb.toml` has `[lib]`. No scratch copy was used this time.

From `indexer/emitter`:

```
$ scarb fmt --check --workspace        (passes)
$ scarb build --workspace
    Finished `dev` profile target(s) in 1 second
$ snforge test --workspace
Tests: 10 passed, 0 failed, 0 ignored, 0 filtered out
```

The local-node scenario on the Mac:

```
$ pnpm --filter @grimworld/indexer test:node
 Test Files  1 passed (1)
      Tests  9 passed (9)
   Duration  24.84s (tests 100%)
```

Its figures:
- AC-2 depths 1–5: replacement hashes equal the aborted ones, commitments differ, one rewind each (0.20–0.24 ms), and the tables equal a rebuild's.
- AC-3: blocksApplied 3 after the restart.
- Catch-up: 276 blocks and 5,055 events in 0.43 s (639 blocks/s); 4.07 calls per empty block; 2.11 per idle poll; maxRSS 188–197 MB.
- Pruning: `--depth 20` keeps blocks from 259 at tip 279, and the tables at the tip equal the unpruned indexer's.

The emitter's gas is unchanged, and `cairo (indexer/emitter)` now measures it in CI.

### 2. What changed for CI and the repository

- **Root `package.json`:** `"format": "prettier --write client indexer"`.
- **Root `.gitignore`:** `indexer/dist/` and `indexer/emitter/target/`, beside `client/*/dist/`. Prettier run from the root reads this file, so the client job's `pnpm build` no longer puts `indexer/dist/` under the check.
- **`indexer/.gitignore`:** also `emitter/.snfoundry_cache/`, which snforge now leaves in the real tree.
- **`ci.yml`, `client` job:** `pnpm exec prettier --check client indexer`.
- **`ci.yml`, `discover` job:** a new step, `changes`, and an output, `indexer`.
  - A pull request is compared with `github.event.pull_request.base.sha`, and a push with `github.event.before`.
  - The base commit alone is fetched (`git fetch --no-tags --depth=1 origin <sha>`; the checkout is shallow), then `git diff --name-only <base> HEAD -- indexer/` decides.
  - Event values reach the script through `env:`, never interpolated into it. A base that is not a 40-hex sha, is all zeros (a new branch), or cannot be fetched counts as changed, so the job runs.
  - I followed `discover.py`'s pattern, where the discover job decides what runs, without changing `discover.py`. A workflow-level `paths:` filter would have applied to every job.
- **`ci.yml`, new job `indexer-node`:**
  - **When and limits:** `needs: discover`; `if: needs.discover.outputs.indexer == 'true'`; `ubuntu-latest`; `timeout-minutes: 15`. No secret; the token is the workflow's read-only one (`contents: read`).
  - **`pins` step:**
    - It requires Linux x86_64.
    - It takes the Scarb version of the `indexer/emitter` entry of discover's validated `packages` output (python `json`), and refuses one that is not x.y.z.
    - It checks that `.tool-versions` pins `starknet-devnet` at the job's `DEVNET_VERSION` (0.10.0), and that `scripts/setup-toolchain.sh` holds exactly `starknet-devnet:0.10.0:amd64) echo <DEVNET_BINARY_SHA256> ;;`. So a bump of devnet in either file without this job fails the job.
  - **Setup actions:** `software-mansion/setup-scarb`, `pnpm/action-setup` and `actions/setup-node`, at the same SHAs as the existing jobs. Versions come from discover; the Scarb cache is keyed by `indexer/emitter/Scarb.lock`.
  - **`toolchain is the one of .tool-versions` step:** node, pnpm and scarb are checked as the `client` and `cairo` jobs check them.
  - **`starknet-devnet` step:**
    - `curl -fsSL --proto '=https' --tlsv1.2` of `starknet-devnet-x86_64-unknown-linux-gnu.tar.gz`, release v0.10.0.
    - `sha256sum -c` of the tarball (`0d27863e…969b`) before `tar`, and of the extracted binary (`4e2e6479…167c`, setup-toolchain.sh's pin) before it is run.
    - Its `--version` must be exactly `starknet-devnet 0.10.0`; then its folder goes on `$GITHUB_PATH`.
    - I got the tarball's sha256 by downloading both Linux x86_64 assets of the release. The GNU one's binary hashes to setup-toolchain.sh's pin; the musl one's does not (`9db7f96e…`). The release lists no asset digest through `gh release view --json assets`.
  - **Remaining steps:** `pnpm install --frozen-lockfile`; `scarb --manifest-path indexer/emitter/Scarb.toml build`; `pnpm --filter @grimworld/indexer test:node`; then `cat indexer/.scenario-results.txt` (`if: always()`).
  - **Network:** the npm registry and the setup actions' downloads, scarbs.xyz for the emitter's dependencies, and the devnet release on github.com.
  - **The node:** `scripts/with-node.sh` binds 127.0.0.1 on a random port. On Linux the package's perl `setsid` stand-in is used too; it behaves like `setsid(1)`.
- **Nothing else changed** in `.github/` or `scripts/`. `with-node.sh` on macOS is the game's (D-153, FND-09).

**Local checks of the workflow:**
- The YAML parses (python `yaml`): jobs `discover`, `cairo`, `client`, `indexer-node`; discover's outputs include `indexer`.
- shellcheck on the new `run:` scripts reports only SC2154, for variables set by `env:`, as in the existing `client` job's check.
- `actionlint` is installed but not permitted to my profile, so it was not run.
- `pnpm exec prettier --check client indexer`: `All matched files use Prettier code style!`

### 3. CI result (real)

`gh pr checks 144 --watch`, head `e40cd51`, run 36567246781:

```
cairo (contracts)             pass  1m11s
cairo (indexer/emitter)       pass  13s
cairo (spikes/SPK-11)         pass  15s
cairo (spikes/SPK-2)          pass  33s
cairo (spikes/SPK-2/account)  pass  19s
cairo (spikes/SPK-2/native)   pass  23s
cairo (spikes/SPK-4/cairo)    pass  17s
cairo (spikes/SPK-5)          pass  22s
cairo (spikes/SPK-5b)         pass  16s
cairo (spikes/SPK-7)          pass  37s
client                        pass  31s
discover                      pass  5s
indexer-node                  pass  1m9s
tooling                       pass  35s
```

From the logs:

```
discover / changes:        indexer/ changed: true            (the base was fetched and compared)
indexer-node / toolchain:  node v24.21.0, pnpm 12.5.1, scarb 2.19.4 (b45b74c03 2026-07-21)
indexer-node / devnet:     /home/runner/work/_temp/starknet-devnet/devnet.tar.gz: OK
                           /home/runner/work/_temp/starknet-devnet/starknet-devnet: OK
indexer-node / test:node:  Test Files 1 passed (1), 9 tests ✓, Duration 33.40s
  AC-1: blocks 5..9 served 7 ms after the last receipt
  AC-1: 19 events in 9 kinds; lots, trades, presence, titles, trial_passes, clears, ranks as sent
  AC-2 depth 1..5: replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 10->9, 12->10, 15->12, 19->15, 24->19 in 0.31–0.47 ms; new tip served 67–227 ms after the abort; tables equal a rebuild
  AC-3: stopped at block 24; 3 blocks sent while stopped; restarted: blocksApplied 3 (blocks 25..27); 55 raw events, no position twice; rebuild --from 2: same tables
  AC-8 catch-up: rebuild --from 2 to 277: 276 blocks, 5055 events in 1.18 s (process start included): 234 blocks/s, 4286 events/s; maxRSS 166 MB
  AC-8 empty blocks: 200 blocks in 0.82 s (4.12 ms per block); 4.07 calls per block
  AC-8 idle following (poll 50 ms), 5 s: 38.0 calls per second, 2.00 per poll
  fix loop 1, pruning: --depth 20: lowest kept block 259 at tip 279; 10098 row versions kept of 10118; abort rewound (1 rewind); tables as of the tip equal the unpruned indexer's
```

The job took 1m9s end to end, about 34 s of it the scenario. The runner is slower than the Mac: catch-up 234 blocks/s against 639.

### Notes for the tooling audit

- **The skip path is not yet shown in CI.** This pull request touches `indexer/`, so only `indexer/ changed: true` has run. A later pull request without `indexer/` changes should show `indexer-node` as skipped.
- **What the job does not watch.** It triggers on `indexer/` only, as asked, so a change to `ci.yml`, `scripts/with-node.sh` or `contracts/persistent/src/events.cairo` alone does not run it.
  - The emitter's compile against the events is still gated by `cairo (indexer/emitter)`, a discovered job.
  - Adding those paths would be a small change to the `git diff` pathspec, if the orchestrator wants it.
- **The devnet tarball hash is new in the repository.** It is pinned in `ci.yml` only. `setup-toolchain.sh` pins the binary, which the job also checks.

**Remaining escalations:** E-1 is closed (D-153, #148, merged). E-2 is done here, as D-153 granted. E-3 is done here with the `indexer-node` job. E-4, `with-node.sh` on macOS, is the game's (FND-09); the package's `setsid` stand-in stays until then.

**Files left:** only ignored files: `REPORT.md`, `indexer/.scenario-results.txt`, `indexer/emitter/target/` and `indexer/emitter/.snfoundry_cache/`, all from local runs.

## Resume 4

**What was asked:** fix loop 2, the second passes of both audits, as accepted by the orchestrator.

Commit pushed: `6f65490` fix(indexer): IDX-01a fix loop 2: prune floor from the checked tip; no part of the RPC URL logged; devnet-only residual stated; CI comments and persist-credentials.

| Finding | Change | Test |
|---|---|---|
| GPT-6-Sol 1 (major): a catch-up prunes the kept history, because the floor came from the node's tip | See below | See below |
| GPT-6-Sol 2 (note): a deep replacement under empty same-hash, same-commitment devnet blocks escapes the window | No code change. It is stated as a **devnet-only residual** in the header comment of `indexer.ts` and in `README.md` (*Assumptions and limits*): on a real network a replaced block changes its hash, so every child's parent hash changes up to the tip and the tip check sees it | — |
| GPT-6-Sol 3 (minor): the hostname was still logged | See below | See below |
| Opus N1: the workflow comment claimed a devnet bump outside the job "fails" | The `indexer-node` comment now says the job runs only for a change under `indexer/` (D-153's grant) or an unknown base, and does **not** run for a change elsewhere it depends on: `.tool-versions`, `scripts/setup-toolchain.sh`, `scripts/with-node.sh`, `contracts/persistent` (the events), `ci.yml`. Such a change is checked at the next change under `indexer/`, and widening the trigger is with the project manager. The `pins` comment now reads "when this job runs, it fails if … pin another devnet …; a bump in those files alone does not run it". The trigger itself is unchanged | — |
| Opus N2 (low) | Beside `DEVNET_TARBALL_SHA256`: the tarball hash is pinned in `ci.yml` only; the binary's hash lives in `scripts/setup-toolchain.sh` (`binary_sha256`, `starknet-devnet:0.10.0:amd64`) and is repeated there; a bump edits both files, and `.tool-versions` | — |
| Opus N3 (info) | `persist-credentials: false` on the `indexer-node` checkout | CI |

**GPT-6-Sol 1, the prune floor.**
- **Change:** `Indexer.prune()` no longer takes the node's tip.
  - With `--depth <blocks>`, the floor is the indexer's own **checked tip** minus the depth.
  - With `l1`, the floor is the last L1-accepted block (final), never above the checked tip, as before.
  - The comment of `prune` and `README.md` say so.
- **Test:** `counts the kept depth from its own checked tip during a catch-up, not from the node's`.
  - Setup: 1,000 blocks on the node, `--depth 20`, `--batch 100`. After two steps the checked tip is 100, and the lowest kept block is **80**.
  - Then blocks 99 to 1000 are replaced, a reorg of depth 2 below the checked tip.
  - Result: status `ok`, one rewind to 98, served tip 1000, and `presence` and `events` as of 1000 equal a rebuild's.
  - Mutation check: with the floor computed from the node's tip again, the test fails with `expected 100 to be 80`.

**GPT-6-Sol 3, the RPC URL in logs.**
- **Change:** `redact(url)` now returns `rpc <first 8 hex of sha256(url)>`, with no part of the URL, and never throws. The startup log reads `following rpc 89f2e5ae` (Mac run) or `following rpc e9f6cbfa` (CI run).
- **Test:** the `redact` test in `chain.test.ts`.
  - `https://SECRETHOST.rpc.example.com/` gives exactly `rpc` plus the first 8 hex of its sha256.
  - For that URL, a URL with credentials, path and query, `http://127.0.0.1:5050`, a non-URL and an ftp URL, the label matches `^rpc [0-9a-f]{8}$` and holds none of `SECRET`, `example`, `127.0.0.1`, `5050` or `http`.
  - Two URLs get different labels, and the same URL always the same one.
- **Unchanged:** the URL is still refused at start without printing it when it is not http(s), and node and transport errors are still method and code only.

### Verification, real output

On the Mac, on the tree merged with `main` (the real `contracts/persistent`, with `[lib]`):

```
$ pnpm lint
client/sim lint: Done
client/app lint: Done
indexer lint: Done
$ pnpm typecheck
client/sim typecheck: Done
indexer typecheck: Done
client/app typecheck: Done
$ pnpm test
client/sim test:       Tests  8 passed (8)
client/app test:       Tests  43 passed | 1 skipped (44)
indexer test:       Tests  66 passed (66)
$ pnpm build
indexer build: Done
$ scarb --manifest-path indexer/emitter/Scarb.toml build
    Finished `dev` profile target(s) in 0 seconds
$ pnpm --filter @grimworld/indexer test:node
 Test Files  1 passed (1)
      Tests  9 passed (9)
   Duration  24.80s (tests 100%)
$ pnpm exec prettier --check client indexer
All matched files use Prettier code style!
```

The workflow YAML parses (python `yaml`); the `indexer-node` checkout reads `{'persist-credentials': False}`.

Pull-request CI (`gh pr checks 144 --watch`, head `6f65490`, run 36568441431):

```
cairo (contracts)             pass  1m8s
cairo (indexer/emitter)       pass  14s
cairo (spikes/SPK-11)         pass  15s
cairo (spikes/SPK-2)          pass  28s
cairo (spikes/SPK-2/account)  pass  20s
cairo (spikes/SPK-2/native)   pass  20s
cairo (spikes/SPK-4/cairo)    pass  16s
cairo (spikes/SPK-5)          pass  22s
cairo (spikes/SPK-5b)         pass  12s
cairo (spikes/SPK-7)          pass  33s
client                        pass  31s
discover                      pass  5s
indexer-node                  pass  1m3s
tooling                       pass  36s
```

From the `indexer-node` log:

```
starknet-devnet: /home/runner/work/_temp/starknet-devnet/devnet.tar.gz: OK
                 /home/runner/work/_temp/starknet-devnet/starknet-devnet: OK
indexer: serving on http://127.0.0.1:45011, following rpc e9f6cbfa from block 2; stored tip none; depth 100000
AC-2 depth 5: blocks 20..24 aborted and replaced; replacement hashes equal the aborted ones: true; commitments differ: true; rewinds 24->19 in 0.27 ms; new tip served 179 ms after the abort; …
fix loop 1, pruning: --depth 20: lowest kept block 259 at tip 279; 10098 row versions kept of 10118 in the unpruned database; abort of blocks 276.. rewound (1 rewind); tables as of the tip equal …
Test Files  1 passed (1)    Duration 33.59s
```

The `http://127.0.0.1:<port>` in that line is the indexer's own listening address, not the RPC URL.

**Files left:** only ignored files: `REPORT.md`, `indexer/.scenario-results.txt`, and `indexer/emitter/target/` and `indexer/emitter/.snfoundry_cache/` from the emitter build. `indexer/dist/`, `client/app/dist/` and `indexer/.with-node/` from this run were deleted.
