# IDX-01a — The indexer, part 1: following the chain, versioned tables, rewind

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur client visuel (Mac)`, on
2026-09-29. IDX-01 is lent to track CV by the project manager (D-149,
[ORCH-client-visual](ORCH-client-visual.md) §8). It is split in two at the brief stage (OPERATIONS §7:
a pull request is reviewable in one sitting): **IDX-01a** (this brief: the process that follows the
chain and keeps the tables) and **IDX-01b** (queries, subscriptions, the client's freshness rule),
which builds on it.

## Agent
Title: `[Opus 5.5] IDX-01a indexer core` · Profile: implement · Launched on the owner's Mac with
`scripts/mac/agent.sh`

## Goal

After this task, `indexer/` is a package of the pnpm workspace, `@grimworld/indexer`: one Node process
that follows a Starknet node over JSON-RPC, decodes the **nine events frozen by ENG-01**, and keeps them
in SQLite tables where every row is versioned by block; it checks the tip by hash **and** commitments,
rewinds in one transaction on a reorg, serves nothing before reconciliation, halts on anything it
cannot decode, and is rebuilt from the chain on demand. It is proven on a local node (starknet-devnet
0.10.0) with a test contract that emits every frozen event, including reorgs and a restart. It never
touches Sepolia.

## Context

- Decisions: [D-130](../decisions/2026-09-28-indexer.md) (our own indexer: one TypeScript process,
  rows versioned by block, SQLite for the MVP, the correctness rules), [the indexer's
  scope](../decisions/2026-09-28-indexer-scope.md), [D-149](../decisions/2026-09-29-mac-lane.md);
  [ADR-0007](../architecture/ADR-0007-native-starknet.md) §§ on events and the indexer (**events are an
  API; the indexer is never a source of simulation state**, D-133; nothing that cannot be rebuilt from
  the chain).
- The prototype and what it learned: [SPK-11 report](../reports/SPK-11-indexer.md),
  [research](../research/SPK-11-indexer.md) (rules R1–R6, §6 on reorgs and lot ids, the rebuild
  procedure, the open points), [audit](../reports/SPK-11-audit-gpt-6-sol.md), code in
  `spikes/SPK-11/` (`indexer.ts`, `chain.ts`, `run-indexer.ts`, `with-archive.sh`, `demo.ts`). Start
  from it; the prototype indexed two events of one contract, this task indexes the nine of two.
- **The interface: the frozen events**, [ENG-01-interfaces.md](../architecture/ENG-01-interfaces.md)
  "Events" (about lines 717–752) and `contracts/persistent/src/events.cairo`:

  | Event | Contract | Keys (after the selector) | Data |
  |---|---|---|---|
  | AdventurerLocated | Hub | hub: u16 (0 = no hub) | adventurer: u32 |
  | TitleDisplayed | Hub | adventurer: u32 | title: u16, tier: u8 |
  | TrialPassed | Hub | adventurer | rank: u8, first_attempt: bool |
  | DungeonCleared | Hub | adventurer | dungeon: u16 |
  | RankReached | Hub | adventurer | rank: u8 |
  | LotPosted | Market | market_key: felt252, lot_size: u8 | lot: u64, price: u64, expiry: u64, equipment: u32, modifiers: felt252 |
  | LotClosed | Market | lot: u64 | sold: bool |
  | TradeOpened | Market | invited: u32 | trade: u64, inviter: u32 |
  | TradeClosed | Market | trade: u64 | outcome: u8 (0 done, 1 declined, 2 cancelled) |

  The seven events of `Instances` are not the indexer's. Read the table from the code, not from this
  brief, and report any difference.
- **The game's contracts emit nothing yet**: every entrypoint of `Hub` and `Market` panics
  `'not implemented'` (the market is RWD-10). Hence the test emitter below, and no reconciliation
  against the views `open_lot_count`, `trade_count` in this task (a later lot does it, once the market
  exists: say how in the report).
- Findings of SPK-11 that bind this task: on devnet a replacement block keeps the aborted block's hash,
  so **a block is identified by hash and commitments**; `devnet_abortBlocks` needs
  `STATE_ARCHIVE_CAPACITY=full` in the node's environment; production keeps history down to the last
  block accepted on L1 (reorgs of 18 minutes and about an hour were observed); pre-confirmed blocks are
  not indexed; ids of a retracted lot can come back after a reorg.

## Scope

- In:
  1. **The package** `indexer/`: `package.json` (`@grimworld/indexer`, scripts `test`, `lint`,
     `typecheck`, `build` that the root's `pnpm -r` runs, and a `test:node` for the local-node
     scenario), its own `tsconfig.json` and `eslint.config.js` (the client's rules; the Bundler/`noEmit`
     base of `client/` does not fit a Node process, say what you chose), the line adding `indexer` to
     `pnpm-workspace.yaml`, `pnpm-lock.yaml`. Dependencies: starknet.js at the client's exact version,
     vitest at the client's; anything else named and justified in the report (the prototype needed
     nothing more: `node:sqlite`, `node:http`).
  2. **The process**: follows the node by polling (the interval a parameter), checks the tip by hash
     and commitments, applies each block's events of the two contracts (addresses given at start) in
     block, transaction and event order; on a fork, finds the fork point and rewinds every table to it
     in one SQLite transaction, then re-applies; keeps history down to a configurable depth (the last
     L1-accepted block in production); never indexes pre-confirmed blocks; **halts** (state `halted`,
     nothing served) on an event of the two contracts it cannot decode, a gap, or a node that goes
     back below the kept history, and says why in its log; restarts from its database; `rebuild --from
     <block>` rebuilds from the chain.
  3. **The tables**: every row versioned (`_from`, `_to` by block), one table per kind of state the
     queries of IDX-01b will need (lots, trades, presence per hub, titles, trial passes, clears, ranks),
     and the raw events kept for audit. Values of u64 stored so that ordering by price works (the
     prototype's fixed-width hex) and served as decimal strings. The market key decoded as ENG-01
     defines it (item id; `2^40 + base·2^16 + requirement·2^8 + rarity·2 + identified`; boss item
     `2^41 + base`) into its columns.
  4. **Serving, minimal**: `GET /head` and `GET /stats` only, with the states of R1 (`loading`,
     `rewinding`, `halted` answer 503 with the state and no rows; otherwise `ok`) and R2 (every answer
     carries `head {number, hash, commitments}`). Queries and subscriptions are IDX-01b's.
  5. **The test emitter**: a Cairo package under `indexer/` (for example `indexer/emitter/`, Scarb
     2.19.4, `casm = true`) with two contracts that emit exactly the frozen events on demand.
     **It reuses the event definitions of `contracts/persistent` by a path dependency, never a copy**;
     if that cannot build, stop and escalate. Its `Scarb.toml` makes CI discover it as a Cairo job
     (`.github/ci/discover.py`): it must build and its tests (at least one per event, checking the
     emitted keys and data) pass in CI, with the gas budget attribute of docs/CAIRO.md §2 on each test.
  6. **Tests**: unit tests (vitest, run by CI, no network: a fake JSON-RPC answering blocks and events,
     reorgs of depth 1 to 5, a gap, an undecodable event, a restart); and a **local-node scenario**
     (`pnpm --filter @grimworld/indexer test:node`, whose package script runs the scenario under
     `scripts/with-node.sh` with `STATE_ARCHIVE_CAPACITY=full`, skipped when `NODE_URL` is unset): deploy
     the emitter, emit every event, check every table; abort blocks and check the rewind by
     commitments; stop and restart the indexer and check it resumes; rebuild from the deployment block
     and compare. Measures as SPK-11 did (catch-up rate, RSS, RPC calls per empty block, rewind time).
- Out: queries, subscriptions, the client's freshness rule and cache (IDX-01b); hosting (IDX-02);
  WebSocket wake-up, `getEvents` range catch-up, alerting (say what they would need); `contracts/`
  (**never**: a need there is a `PENDING-cv-*` request through the orchestrator); `.github/`,
  `scripts/`, the root `package.json` (**escalate** instead: the root `format` and the CI's prettier
  check cover `client` only, see *Escalations expected*).
- Allowlist: `indexer/**`, the one line in `pnpm-workspace.yaml`, `pnpm-lock.yaml`, `REPORT.md`.

## Sending transactions, on the local node only

COMMON.md §4's "sending lives in one module" was written for Sepolia; here it applies so: the only code
that deploys or invokes is one module of the scenario (`indexer/test-node/…`), which **refuses unless
the RPC URL's host is `127.0.0.1` or `localhost`** and uses only the account that `scripts/with-node.sh`
exports (`NODE_ACCOUNT_ADDRESS`, `NODE_ACCOUNT_PRIVATE_KEY`, devnet's seed-0 account); it never reads
`STARKNET_*` (the launcher leaves them empty anyway). devnet's chain id is also `SN_SEPOLIA`: the check
is on the host, not the chain id. The indexer itself holds no key; its RPC URL comes from its
environment or arguments and is never logged in full.

## Acceptance criteria

- [ ] AC-1 The nine events are decoded into their tables, checked on the local node against what the
  emitter sent (every field, including felt252 market keys decoded into their columns, u64 extremes,
  `bool`, the three trade outcomes).
- [ ] AC-2 A reorg of depth 1 to 5 on the local node (`devnet_abortBlocks`) is detected by commitments
  and rewound in one transaction; after it the tables equal those of a fresh rebuild of the same chain.
- [ ] AC-3 A restart resumes from the database without re-applying a block; `rebuild --from` gives the
  same tables.
- [ ] AC-4 Halts, with a stated reason and a 503 `halted`: an undecodable event, a gap, history below the
  kept depth (unit tests).
- [ ] AC-5 `/head` and `/stats` follow R1 and R2 (unit tests).
- [ ] AC-6 The emitter reuses `contracts/persistent`'s event types, its tests pass in CI with gas budgets.
- [ ] AC-7 `pnpm lint`, `pnpm typecheck`, `pnpm test`, `pnpm build` pass at the root; the pull request's
  CI is green; `pnpm exec prettier --check indexer` passes locally (the CI does not check it yet).
- [ ] AC-8 The measures, and the local-node scenario's real output, are in the report.

## Verification

```
pnpm install --frozen-lockfile
pnpm --filter @grimworld/indexer lint
pnpm --filter @grimworld/indexer typecheck
pnpm --filter @grimworld/indexer test
pnpm --filter @grimworld/indexer test:node
scarb --manifest-path indexer/emitter/Scarb.toml build
cd indexer/emitter && snforge test
pnpm exec prettier --check indexer
```

## Escalations expected

Write them in the report; the orchestrator turns them into a `PENDING-cv-*` request: the CI's prettier
check and the root `format` script cover `client` only; the CI's `client` job has no starknet-devnet, so
the local-node scenario runs only on the Mac; `scripts/with-node.sh` passes `STATE_ARCHIVE_CAPACITY`
through the environment only.

## Rules of this run

- You run on the owner's Mac, not on the VPS: COMMON.md §3's VPS specifics (`scripts/lock.sh`, the
  build shims) do not apply. `node` and `pnpm` follow `.tool-versions` (24.21.0, 12.5.1).
- Foreground only: the node and the indexer of a scenario live inside one `scripts/with-node.sh …`
  command (through the package's `test:node` script), started and stopped in it; nothing in the
  background; kill only a pid you recorded; delete only files you created (the SQLite files of a run
  under the worktree).
- Never Sepolia, never a public network.
- Pull request: branch `cv/IDX-01a-indexer-core` (your worktree is on it; this brief is on `main`),
  title `feat(indexer): IDX-01a, following the chain, versioned tables, rewind`. Commits end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Report

`REPORT.md`, header `[Opus 5.5] IDX-01a — indexer core`: summary; files; the schema; commands with their
real output; the measures; the gas table of the emitter's tests; deviations; escalations; open
questions; what IDX-01b needs from this.
