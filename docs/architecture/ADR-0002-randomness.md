# ADR-0002 — Randomness

| | |
|---|---|
| Status | **Accepted for the MVP with a provisional source** (owner, 2026-09-28): the transaction hash. The verifiable source described here is the target of version 1 |
| Date | 2026-09-28 |
| Decides | Which outcomes are random, and where each random value comes from |

## Context

Randomness and optimistic rendering pull in opposite directions: a value the client can
predict can be exploited; a value it cannot predict cannot be rendered before
confirmation. Grimscape used only seeds derived from public data; Athanor uses Cartridge
vRNG for crafting and a public hash for exploration.

## MVP: a provisional source (D-110)

| | |
|---|---|
| Source of every Fate draw in the MVP | **The hash of the transaction** |
| Why | To test the game quickly, without depending on any service, and with burner accounts (ADR-0005) |
| Known weakness | A player chooses what they send: by varying their transaction they can try hashes off-chain and submit the one that gives the draw they want. **Every Fate draw can be steered.** The owner accepts this for a test version |
| Therefore | **The MVP must not hold anything of value**: test networks only, no real asset, progress may be wiped |
| Replaced | For version 1, by a verifiable source, without touching game code |

How the replacement stays cheap:

- Game code never reads the transaction hash. It calls one function, `fate(domain)`,
  of a **randomness provider** behind an interface.
- The provider's implementation is configuration. MVP: transaction hash. Version 1:
  verifiable function, from Cartridge or of our own.
- Rules 1 to 3, 5, 6 and 7 below apply from the MVP (rule 7 states the MVP's accepted weakness and what version 1 must add). Rule 4 applies from version 1.
- A deployment check refuses the provisional provider on mainnet.

## Decision for version 1 (proposed)

Two classes of randomness, never mixed.

| Class | Source | Predictable by the player | Used for |
|---|---|---|---|
| **Fate** | Cartridge vRNG, consumed in the transaction | No | **The content of a chunk, at reveal**: terrain, packs, features, quotas; loot, identification, salvage, alchemy discovery |
| **Fog** | Poseidon hash of a stored value and public coordinates | Yes, with a modified client | Only what derives from a word **already revealed**: details inside a chunk once it exists |

And one class that does not exist: **combat has no randomness** (D-40).

### Rules

1. **A Fate draw decides a reward; a Fog draw decides a situation.** If knowing the value
   in advance lets a player gain items, gold, merit or a recipe, it must be Fate.
2. **One vRNG request per transaction.** A transaction that needs several Fate values
   derives them from the single random word: `poseidon(word, domain, index)`, with a
   distinct domain constant per use. Never reuse a value for two decisions.
3. **Fate actions end a batch, and a planned queue** (D-133), and are submitted alone with
   their `request_random` call first in the multicall. Our client submits a Fate action
   alone; the guarantee comes from rule 7, not from the transaction's shape.
4. **No public data as a source** (from version 1). The transaction-hash provider of the
   MVP must be impossible to enable on mainnet.
5. **No re-roll.** State that records a pending Fate draw (remains on a tile, an untried
   pair) is consumed in the same transaction as the draw. There is no path where a player
   sees a result and the draw is still pending. Every precondition of a Fate action is
   checked before drawing.
6. **Nothing is decided before it is seen.** There is no instance seed from which a whole
   location could be computed. Each reveal draws its own word (owner's requirement: a fog
   of war that reading the chain cannot lift).
7. **A transaction may compose several calls** (D-133). In the MVP, the transaction-hash
   provider can be steered by any call in the same transaction; this is the accepted
   weakness above. From version 1, the provider must not draw from anything the same
   transaction can steer: neither its hash or calldata, nor state written by an earlier
   call of the same transaction.

Version 1 also requires of the provider and of the account design (D-133):

- Fate draws are **attempt-stable**: the same attempt cannot be retried for a new value (for
  example, a request committed in one transaction and fulfilled in a later one, the result
  bound to the request).
- A transaction that aborts after seeing its draw does not re-roll it.
- The calls allowed to share a transaction with a Fate call are stated.

This comes on top of rule 7, which it does not replace. The MVP's hash provider stays the
accepted weakness.

### Hidden information

A value stored on a public chain is known to all. The only information that can be hidden
is information that does not exist yet. Layouts are therefore drawn at reveal. What
remains public, and accepted: everything about chunks already revealed, and the anchors
of a location (where its gates are).

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

- The client can predict every tactical outcome exactly and must wait for every reward
  **and every reveal**.
- Loot tables and alchemy can be tuned freely without touching determinism.
- Auditors have a simple test: *any read of the random word outside the Fate entrypoints
  is a finding; any reward decided by Fog is a finding.*
