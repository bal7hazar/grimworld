# IDX-01b — The indexer, part 2: queries, subscriptions, the client's freshness rule

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur client visuel (Mac)`, on
2026-09-29. IDX-01 is lent to track CV (D-149, [ORCH-client-visual](ORCH-client-visual.md) §8) and
split at the brief stage: IDX-01a (merged, [#144](https://github.com/bal7hazar/grimworld/pull/144):
following the chain, the versioned tables, rewind) and this task.

## Agent
Title: `[Opus 5.5] IDX-01b indexer queries` · Profile: implement · Launched on the owner's Mac with
`scripts/mac/agent.sh`

## Goal

After this task, `@grimworld/indexer` answers the queries the game's screens need, over HTTP, as of
the block it serves; streams the live ones as subscriptions (server-sent events) that start with a
paged snapshot and restart after every rewind; and ships a small **client library** that applies the
freshness rule, so that the client (CLI-01) can read the indexer without ever trusting a stale or
rewound answer. Everything is proven on the local node, never Sepolia.

## Context

- The core this builds on: `indexer/` as merged by IDX-01a, its
  [report](../reports/IDX-01a-indexer-core.md), in particular *What IDX-01b needs from this*: the
  `Indexer`'s `served`, `status`, `reason`, `chainTip`; `answer()` and `headOf()` in `server.ts` (R1
  gating, R2 heads); the `Store`'s as-of reads (`_from <= B AND (_to IS NULL OR _to > B)`) and
  `u64Decimal()`; the indexes already in place; **no subscription hooks yet** (to add: "block served"
  after `setStatus("ok")`, and "rewind"); **no block timestamp yet** (`Chain.header` can take
  `timestamp` from `getBlockWithTxHashes` at no extra call).
- Decisions: [D-130](../decisions/2026-09-28-indexer.md), [the indexer's
  scope](../decisions/2026-09-28-indexer-scope.md) (hub presence from the indexer; the displayed title
  kept by the indexer; a trade opening names the invited account, delivered by a subscription
  filtered on that account, expiring after 10 minutes, declinable; the market key; lots listed
  cheapest first per key; the average price over the last 7 days per key and lot size, hidden under 5
  sales), [D-153](../decisions/2026-09-29-indexer-needs-and-market-key.md), ADR-0007 (the indexer is
  never a source of simulation state).
- The prototype and its rules: [SPK-11 research](../research/SPK-11-indexer.md): the queries Q1 to Q7
  (Q6, rankings, is later), the rules **R1** (serving states), **R2** (the head on every answer),
  **R3** (the client's freshness rule: the indexer's answer; then the node's tip, the head at most
  `maxLag` (5) blocks below it; then, last, the node's block at the head's number, which must have
  the same hash and commitments; otherwise "loading" and ask again), **R4** (subscriptions: a paged
  snapshot `reset-begin {head,total}`, `reset-page` frames of 1 000, `reset-end`, written in one
  synchronous run; a new snapshot after every rewind; the cache ready only when the count matches;
  any end of the stream makes it not ready; `read()` the only access), **R5** (the contract stays
  authoritative), **R6** (answers as of the served block, cached by hash and commitments, cleared on
  every rewind; a new block waits for reconciliation). Code: `spikes/SPK-11/client.ts` (`verify`,
  `LotCache`), `indexer.ts` (the endpoints).

## Scope

- In:
  1. **Queries** (HTTP GET, JSON, gated by R1, a head on every answer by R2, served as of `served` and
     cached by R6):
     - Q1: the open lots of a market key and lot size, cheapest first, ties by lot id; paged.
     - Q2: the market keys of a category, with the cheapest open lot per lot size.
     - Q3: the mean price of the sales of the last 7 days (block time) per market key and lot size,
       hidden (absent, not zero) under 5 sales.
     - Q4: the adventurers present in a hub, and the count.
     - Q5: the displayed title of an adventurer (and of a list of adventurers).
     - Q7: the open trade invitations of an account under 10 minutes old (block time), not yet closed.
     Every parameter validated (bounded integers, felt252 as hex, page sizes capped); SQL
     parameterised; an unknown route or bad parameter a 4xx with the head.
  2. **Block time**: the timestamp of each block stored with it (a column of `blocks`, versioned like
     the rest), used by Q3 and Q7; the clock of the indexer's machine is never used for a rule.
  3. **Subscriptions** (server-sent events): the open lots of a market key and lot size (Q1), a hub's
     presence (Q4), and an account's invitations (Q7, filtered on the account). Each follows R4: a
     paged snapshot as of the served block, then the changes of each newly served block, in block
     order; after a rewind, a new snapshot. Events of a block are published only once the block is
     served (after reconciliation). The hooks in `Indexer` ("block served", "rewind"). Bounded: a cap
     on subscriptions per process and per connection, slow consumers dropped (their stream ends, and
     R4 makes the client's cache not ready).
  4. **The client library** `indexer/src/client/` (exported by the package, for CLI-01): an
     `IndexerClient` applying R3 (the node's tip and block read through a minimal JSON-RPC reader of
     its own, or an injected function: no starknet.js account, no key), and the caches of R4
     (`LotCache`, `PresenceCache`, `InvitationCache`) with `read()` as the only access and `ready` as
     the rule says. No dependency on `node:` modules in this folder (it must run in a browser); tested
     under Node.
  5. **Tests**: unit tests with the fake node of IDX-01a (every query; R1 to R6; a rewind in the
     middle of a snapshot; a subscriber that stops reading; the invitation expiring by block time; the
     7-day window at its edges and the 5-sale threshold); the local-node scenario extended
     (`test:node`): the emitter posts lots, sales, trades and presence, the queries and subscriptions
     are checked against it, a reorg is rewound and every subscription resnapshots; the client library
     against the running indexer, including a stale head (more than 5 blocks behind) and a head whose
     block the node no longer has (R3 says "loading").
  6. **Measures**, as SPK-11 did: query latency (median, p95) on 10 000 lots, snapshot time, memory
     per subscription, RPC calls per served block with subscriptions open.
- Out: rankings (Q6, later); hosting (IDX-02); the client's screens (CLI-01, CLI-06/07);
  `contracts/` (never: a need there is a `PENDING-cv-*` request through the orchestrator); `.github/`
  beyond what exists (the `indexer-node` job already runs `test:node`).
- Allowlist: `indexer/**`, `pnpm-lock.yaml`, `REPORT.md`.

## Acceptance criteria

- [ ] AC-1 Each query Q1–Q5 and Q7 answers exactly what the emitter's events imply, on the local node,
  as of the served block; with a head on every answer; 503 in `loading`, `rewinding`, `halted`.
- [ ] AC-2 Q3's window and threshold and Q7's expiry use block time only; tested at their edges.
- [ ] AC-3 Every subscription follows R4 (snapshot, then per-block changes, a new snapshot after a
  rewind, nothing from an unserved block); a rewind during a snapshot is tested.
- [ ] AC-4 The client library applies R3 in its order, and its caches are ready only under R4; it has
  no `node:` import and holds no key; tested against the running indexer on the local node.
- [ ] AC-5 Bounded: page sizes, subscriptions per process and per connection, slow consumers; tested.
- [ ] AC-6 lint, typecheck, test, build, `prettier --check client indexer` pass; the CI is green,
  including `indexer-node`.
- [ ] AC-7 The measures and the scenario's real output are in the report.

## Rules of this run

- You run on the owner's Mac. `node` and `pnpm` follow `.tool-versions`. The node lives inside one
  `scripts/with-node.sh …` command through the package's `test:node` script; foreground only; kill only
  a pid you recorded; delete only what you created.
- Never Sepolia. The sending module of the scenario stays local-only (the host is 127.0.0.1 or
  localhost, the account `NODE_ACCOUNT_*`), as IDX-01a made it.
- The equipment market key assumes `rarity < 128` (D-153): keep the assumption where it is decoded.
- Pull request: branch `cv/IDX-01b-indexer-queries` (your worktree is on it; this brief is on `main`),
  title `feat(indexer): IDX-01b, queries, subscriptions, the client's freshness rule`. Commits end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Wait for the CI in the foreground.

## Report

`REPORT.md`, header `[Opus 5.5] IDX-01b — indexer queries`: summary; files; the routes and their
parameters; the subscription protocol; the client library's API; commands with their real output; the
measures; deviations; escalations; what CLI-01 needs to know.
