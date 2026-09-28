# SPK-11 — Indexer spike

## Agent
Title: `[Opus 5.5] SPK-11 indexer spike` · Profile: implement · Branch: `chore/spk-11-indexer`

## Goal
After this task we know what the game's indexer must do and with what: which reads need an
indexer at all (against view calls), whether an **existing generic indexer** configured for our
events is enough or we write **our own**, how it **rewinds on a reorg**, and what it costs to
host. A prototype indexes the events of a native contract on the local node, serves a query
and a subscription to a TypeScript client, and survives a simulated reorg. This answers open
point NS-2 of ADR-0007 and turns "probably our own" into a decision the owner can take.

## Context
- **ADR-0007** *Events are an interface* (the player's own instance is read by **view calls**
  and the client's simulation, no indexer on the path of a move; the indexer serves what spans
  players or history: market listings and cheapest lot, hub presence counts, rankings, titles
  of others) and *Indexer* (follows the chain, decodes our events, keeps tables, serves queries
  and subscriptions, **rewinds on a reorg**, holds nothing that cannot be rebuilt from the chain,
  pillar 4); NS-2.
- CONTEXT §8 *Reorgs* (two multi-hour outages with reorgs in 13 months; the client treats the
  chain as authoritative and can rewind); design/16 (the auction house: the cheapest lot and the
  average price are computed by the indexer, not on-chain); design/11 *The chain, unseen*
  (hub presence, "saving…", "the world corrected itself"); ADR-0001 (*no infrastructure to
  operate beyond* the indexer now).
- The toolchain (SPK-5b): Cairo 2.19, `sncast`, **starknet-devnet 0.10.0** through
  `scripts/with-node.sh` (it can **abort blocks**: use it to simulate a reorg, and say how
  faithful that is), starknet.js 10.8.0; `spikes/SPK-5b/` for a native contract and its flow.
- Depends on: SPK-5b, FND-01b (merged).

## Scope
- In:
  1. **What needs indexing**: from the design documents, the list of reads the client needs,
     each classified as view call, client simulation, or indexer; for the indexer ones, the
     events they need (name, keys, data) and the query shape. Keep it small: an event costs gas
     on every action (ADR-0007).
  2. **Candidates**: the maintained generic Starknet indexers you can find (for example Apibara,
     Checkpoint, or others: say what each is, its licence, its last release, whether it runs
     self-hosted without a paid service), against our own (starknet.js or a Rust client
     following blocks, decoding events, writing to SQLite or Postgres). Compare on: reorg
     handling, pending and pre-confirmed blocks, query and subscription interface, operations,
     cost, lock-in. Sources for every claim.
  3. **A prototype** in `spikes/SPK-11/`, of the candidate you recommend (and, if cheap, the
     runner-up): a native contract emitting two or three events shaped like the game's (a
     market listing and a sale; a presence change), deployed on the local node; the indexer
     following it into a database; a query (the cheapest lot of an item) and a subscription
     (new listings) served to a TypeScript client.
  4. **Reorg**: abort blocks on the node after events were indexed; the indexer rewinds, the
     query and the subscription reflect the rewind; measured time to consistency.
  5. **Hosting and cost**: what it takes to run for Sepolia then mainnet (process, database,
     memory, disk per million events, the RPC it needs and its cost), and how it is rebuilt from
     the chain.
- `docs/research/SPK-11-indexer.md`: all of the above, a recommendation with its reasons, and
  what ENG-01 must freeze (events as an API).
- Out: the game's events (ENG-01); the production indexer (a track after this spike);
  Sepolia or mainnet; `contracts/`, `client/`.
- Allowlist: `spikes/SPK-11/**`, `docs/research/SPK-11-indexer.md`. Anything else is an
  escalation. If a candidate needs Docker, root, or a paid service to run, record it and do not
  work around it.

## Acceptance criteria
- [ ] AC-1 The classified list of reads, with the events the indexer needs.
- [ ] AC-2 The candidates compared with sources; a recommendation.
- [ ] AC-3 The prototype indexes events from the local node and serves one query and one
      subscription to a TypeScript client (commands and output).
- [ ] AC-4 A simulated reorg is rewound by the indexer; the client sees the rewound state;
      time to consistency measured.
- [ ] AC-5 Hosting and cost figures, and the rebuild-from-chain procedure.

## Audits
Security and quality (PLAN: S Q): the auditor checks that nothing in the recommended design can
serve the client a state the chain does not hold after a reorg, and that the indexer holds no
secret and nothing that cannot be rebuilt.

## Verification
The commands that deploy the contract, start the indexer, emit events, query, subscribe, abort
blocks and query again, all under `scripts/with-node.sh`, with their real output in the report.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7; the cost table has the gas of each prototype
event and the indexer's memory, disk and time figures.
