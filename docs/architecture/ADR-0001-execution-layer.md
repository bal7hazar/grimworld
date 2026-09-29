# ADR-0001 — Execution layer

> **Superseded in part by [ADR-0007](ADR-0007-native-starknet.md)** (2026-09-28, D-123): the game is built as native Starknet contracts, without Dojo, Torii or dojo.js. What this document says of them is kept for the record.

| | |
|---|---|
| Status | **Accepted by the owner on 2026-09-28**, subject to the Phase 0 spikes. May be revisited later for cost or performance reasons |
| Date | 2026-09-28 |
| Decides | Where game transactions execute and settle |

Facts below were gathered on 2026-09-28 from official docs, GitHub and live mainnet RPC.
Items marked *(unverified)* were not confirmed from a primary source or by measurement.

## Context

Grim World is tick-based: one player input is one action, and the player expects the
world's reaction immediately. Four execution models were considered by the owner, each
with a stated concern.

## Options

### A. Starknet mainnet

| | |
|---|---|
| Latency | Blocks measured at ~1.7 s (mean over 20 000 blocks). Pre-confirmed status claimed at ~0.5 s *(unverified by our own transaction)* |
| Cost | ~0.1–0.7 STRK for a moderate game transaction, about $0.004–0.03 *(STRK price unverified)*; sponsorable through the Cartridge paymaster |
| Randomness | Cartridge vRNG: synchronous, same transaction, live on mainnet |
| Liveness | 3 sequencers, centralised prover. Two multi-hour outages with reorgs in the last 13 months (Sept 2025, Jan 2026): even accepted-on-L2 state can be reverted |
| Maturity | Production. Used by nearly every shipped Starknet game (Loot Survivor 2, Eternum, Dark Shuffle, zKube, Pistols at Dawn, …) |
| Owner's concern | 1 s between moves is poor UX unless hidden by optimistic rendering, which breaks when the transaction generates information (randomness) |

### B. L3 with periodic settlement (Katana on Slot, or Madara)

| | |
|---|---|
| Latency | Configurable, near-instant soft confirmation. Provable mode recommends a block time (docs example: 30 s) |
| Cost | Slot $50–200 / month per service, plus proving credits and settlement gas *(proving price unpublished)* |
| Randomness | vRNG runs on Slot chains (seen in one game's preset); the single sequencer is a trusted party |
| Liveness | Single operator. Starknet ↔ Katana messaging is documented as experimental |
| Maturity | Katana 1.8 is a release candidate; Madara is alpha with no game in production. One shipped game found on Slot chains |
| Owner's concern | Waiting for settlement before assets are usable on Starknet |

### C. Ephemeral per-session chain (zk thread / execution shard)

| | |
|---|---|
| Maturity | **Not available.** Dojo's documentation labels execution sharding as planned and not in production; no zkThreads product found |
| Owner's concern | Infra cost, loss of decentralisation if the infra fails, stack not ready — confirmed |

### D. Client-side proving

| | |
|---|---|
| Latency | Local execution instant; proving takes seconds per proof on phones for a trivial benchmark; then one mainnet transaction |
| Cost | ~75M L2 gas for a 500 KB proof, about 1.7 STRK at today's price |
| Randomness | No same-transaction VRF: the proof is produced before sequencing. Seed at session start or commit-reveal only |
| Maturity | Protocol support (SNIP-36) live since April 2026, phase 1 verified by consensus only. No game tooling and no shipped game found |
| Owner's concern | No decentralised randomness — confirmed |

## Decision

**Option A — Starknet mainnet**, with Dojo, Cartridge Controller sessions, the Cartridge
paymaster and Cartridge vRNG. *(Superseded in part by [ADR-0005](ADR-0005-accounts.md) and
D-110: the MVP runs on burner accounts and transaction-hash randomness behind interfaces;
Controller, paymaster and vRNG are version-1 candidates, evaluated by SPK-9 and SPK-3.)*

The owner's concern about A is real, and it is addressed **by game design rather than
by infrastructure**:

1. **Deterministic tactics** (pillar 5, D-40). Moving, attacking, using skills and goblin
   AI involve no randomness. The client can compute the exact result of an action before
   the chain does, so optimistic rendering is not a guess: it is the same function.
2. **Randomness only at reveal moments** (D-50). Instance entry, looting and brewing are
   the only actions that consume randomness. They are moments where ~0.5–2 s of delay reads
   as suspense. See [ADR-0002](ADR-0002-randomness.md).
3. **Action queue** (`docs/design/02-core-loop.md`). Several deterministic actions travel
   in one transaction; the chain lags behind the player without blocking the next input.
   Played actions travel in batches (D-133, design/02).

### Why not the others

- **B** trades a UX problem we can design away for an operations problem we cannot: a
  chain to run, fund and keep alive, plus bridging that is still experimental. It remains
  the **fallback** if Phase 0 shows that A cannot meet the cost or latency budget.
- **C** cannot be bought today.
- **D** has no tooling and makes pillar 5's "random rewards" impossible without trust
  trade-offs worse than vRNG's. Worth re-evaluating yearly.

### Keeping the exit open

The owner's stated risk: moving to several layers later would mean splitting the game,
with assets on L2 and temporary game state on L3, and reworking it. To make that split a
deployment change rather than a rewrite, the code is **split along that line from the
start**, even though everything is deployed on one layer:

| Domain | Content | Lifetime | Would live on |
|---|---|---|---|
| **Persistent** | Adventurer, level, rank, skills known, inventory, grimoire, quest log, registries | Forever | L2 |
| **Ephemeral** | Instance, rooms, goblins, positions, clocks, conditions, recharges | One instance | L2 today, L3 if needed |

Rules:

- The two domains are separate namespaces and separate systems. No model mixes fields of
  both.
- The ephemeral domain reads a **snapshot** of the adventurer taken at instance entry
  (stats, build, belt) and never reads persistent models during play.
- The ephemeral domain writes to the persistent one through **one narrow interface**:
  a list of results (experience, items, quest progress, outcome). Today it is a direct
  call; across layers it would become a message.
- No dependency on mainnet-only contracts inside core systems; external addresses
  (vRNG provider, tokens) are configuration.
- No game rule reads block number, block timestamp or transaction hash inside an instance.

Note: the hosted L3 offer examined above (Slot) was reported as retired by Cartridge in
April 2026 in a later search. Option B's cost figures are therefore to be re-checked
before it is ever used as a fallback.

## Consequences

| | |
|---|---|
| + | No infrastructure to operate beyond Torii; lowest time to a playable build |
| + | Composability with mainnet assets and identity from day one |
| − | **Game logic exists twice**: Cairo (authoritative) and client (prediction). Divergence is the main technical risk. Mitigation: shared test vectors generated from Cairo, a parity audit lens, and rollback to chain state on any mismatch |
| − | Every action costs a fee, and **the player never pays it** (pillar 7): the paymaster sponsors every game transaction, without quota visible to the player. The cost per active player per day is a figure the business model must cover; it is bounded by game rules (daily cap on Rifts), measured in Phase 0 (SPK-2) and watched in production |
| − | A sponsored game is a target for abuse (scripts burning the paymaster). Limits are game rules and silent rate limits per account, never fees. The limits count **gas**, not transactions, since one transaction can carry several batches (D-133) |
| − | Reorgs happen. The client must treat chain state as authoritative and be able to rewind its optimistic state at any time. A reorg can undo confirmed actions to any depth, including Fate draws, gates and the entry into an instance: the client drops every prediction and recovers to the canonical state. Its speculation (two batches ahead of the chain) is not a bound on rollback (design/02, *The chain's answer*, D-133) |
| − | The optimistic client installs chain state **only from one snapshot**, read in one call pinned to a block hash or to `pre_confirmed`. A transaction that is not found is an unknown outcome, decided by the account's nonce and a snapshot (D-133, design/02) |
| − | The client simulates only over a **copy of the instance read from the chain**, pinned to one block; the indexer is never a source of simulation state (D-133, ADR-0007). Recovery after an unknown outcome uses only the account's nonce and a snapshot at one block, and keeps only the actions whose results are unchanged |
| − | Dependency on Cartridge services (paymaster, vRNG) for liveness |

## Validation — Phase 0 spikes

The decision becomes **Accepted** when all pass; otherwise option B is re-examined.

| Spike | Question | Pass threshold (proposed) |
|---|---|---|
| SPK-1 Latency | Time from submission to pre-confirmed and to accepted-on-L2, from a burner account (ADR-0005 stage A), on Sepolia then mainnet | p50 ≤ 1 s and p95 ≤ 3 s to pre-confirmed |
| SPK-2 Cost | L2 gas of a worst-case tick (8 awake goblins) and of a queue of 10 moves | Expedition of 300 actions ≤ $0.50 sponsored |
| SPK-3 vRNG | Gas overhead and added latency of a vRNG request; behaviour when the provider is down | Overhead measured; failure is detectable and retryable |
| SPK-4 Parity | Can one source of truth feed both sides (Cairo test vectors replayed by the client simulation)? | 10 000 generated vectors, 0 divergence |
| SPK-5 Toolchain | Pin Dojo / Cairo / Scarb / Katana / Torii / dojo.js versions that work together | Reproducible build from a clean machine |
