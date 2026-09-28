# ADR-0002 — Randomness

| | |
|---|---|
| Status | **Proposed** — depends on [ADR-0001](ADR-0001-execution-layer.md) |
| Date | 2026-09-28 |
| Decides | Which outcomes are random, and where each random value comes from |

## Context

Randomness and optimistic rendering pull in opposite directions: a value the client can
predict can be exploited; a value it cannot predict cannot be rendered before
confirmation. Grimscape used only seeds derived from public data; Athanor uses Cartridge
vRNG for crafting and a public hash for exploration.

## Decision (proposed)

Two classes of randomness, never mixed.

| Class | Source | Predictable by the player | Used for |
|---|---|---|---|
| **Fate** | Cartridge vRNG, consumed in the transaction | No | Instance seed, loot, alchemy discovery, hints |
| **Fog** | Poseidon hash of a stored seed and public coordinates | Yes, with a modified client | Room layout, pack placement, goblin caste and level in a pack |

And one class that does not exist: **combat has no randomness** (D-40).

### Rules

1. **A Fate draw decides a reward; a Fog draw decides a situation.** If knowing the value
   in advance lets a player gain items, gold, merit or a recipe, it must be Fate.
2. **One vRNG request per transaction.** A transaction that needs several Fate values
   derives them from the single random word: `poseidon(word, domain, index)`, with a
   distinct domain constant per use. Never reuse a value for two decisions.
3. **Fate actions end an action queue** and are submitted alone with their
   `request_random` call first in the multicall.
4. **No fallback to public data.** If the vRNG provider address is not configured, Fate
   entrypoints revert. A transaction-hash fallback, as in Athanor, is allowed in test
   builds only and must be impossible to enable on a public network.
5. **No re-roll.** State that records a pending Fate draw (remains on a tile, an untried
   pair) is consumed in the same transaction as the draw. There is no path where a player
   sees a result and the draw is still pending.
6. **The instance seed is Fate; what derives from it is Fog.** The seed is unpredictable
   before entry, so an instance cannot be chosen; once inside, its content is
   deterministic and public.

### Accepted limitation

Fog is visible to anyone who reads the chain and runs the generator. A modified client can
show the whole layout of an instance. This does not change rewards (rule 1) and is
accepted as a non-goal for v1. Should hidden information become a requirement, it needs
its own ADR.

## Trust model

Cartridge vRNG (v0.3.x) verifies an EC-VRF proof on-chain. The provider **cannot choose**
a value. It can, in principle, **withhold** a transaction, and the scheme assumes the
provider does not leak its key or collude with a player. A TEE-based provider is announced,
not shipped.

| Risk | Mitigation |
|---|---|
| Provider down: Fate actions unavailable | Deterministic play continues; the client queues Fate actions and tells the player. Measured in SPK-3 |
| Provider withholds selectively | Rewards at stake per draw are small by design; high-value draws (if any are ever added) need a separate review |
| Provider changes or disappears | Provider address is configuration behind an interface; a second source can be added without touching game rules |

## Consequences

- The client can predict every tactical outcome exactly and must wait for every reward.
- Loot tables and alchemy can be tuned freely without touching determinism.
- Auditors have a simple test: *any read of the random word outside the Fate entrypoints
  is a finding; any reward decided by Fog is a finding.*
