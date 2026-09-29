# PENDING — the equipment market key is ambiguous above rarity 127

| | |
|---|---|
| Asked by | `[Opus 5.5] Orchestrateur client visuel (Mac)`, 2026-09-29 |
| For | The project manager (ENG-01's encoding, the game's `contracts/`) |
| Found by | Both audits of IDX-01a ([#144](https://github.com/bal7hazar/grimworld/pull/144)): `[GPT-6-Sol]` (as a blocker) and `[Opus 5.5]` |

## The defect

ENG-01 froze the market key with `LotPosted` (`contracts/persistent/src/models/market.cairo`,
`market_key`; ENG-01-interfaces §3.4):

    equipment: 2^40 + base × 2^16 + requirement × 2^8 + rarity × 2 + identified

`rarity` is a `u8`, so `rarity × 2` takes bits 1 to 8 and overlaps `requirement`'s bit 8: for
`rarity ≥ 128` the key is ambiguous. `requirement = 0, rarity = 128` and `requirement = 1, rarity = 0`
give the same key, so two different markets would share lots, and the indexer cannot tell them
apart.

The design uses a handful of rarities, so no real item reaches 128 today; nothing enforces it.

## Options

| | What | Cost |
|---|---|---|
| A | **Bound it**: `market_key` (or the item's registration) refuses `rarity ≥ 128` with an `errors` constant; ENG-01 §3.4 says "rarity < 128" | One assertion; the key layout is unchanged, so the event stays frozen |
| B | Widen it: keep `rarity × 2` over its full 8 bits (bits 1 to 8) and move `requirement` to `× 2^9` and `base` to `× 2^17` | A layout change of a frozen event's key: a new event name under ENG-01's rule, or before the first deployment only |

**Recommendation: A**, by the game's track, before the market is built (RWD-10). The indexer
(IDX-01a) decodes under the assumption `rarity < 128`, stated in its decoder and README.

## What would reverse it

A design that needs 128 rarities or more.
