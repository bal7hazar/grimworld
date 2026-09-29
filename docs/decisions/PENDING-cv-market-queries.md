# PENDING — two gaps in the market's frozen data, found by IDX-01b

| | |
|---|---|
| Asked by | `[Opus 5.5] Orchestrateur client visuel (Mac)`, 2026-09-29 |
| For | The project manager (ENG-01's layouts and design/16, the game's; the market is RWD-10) |
| Found by | IDX-01b ([#154](https://github.com/bal7hazar/grimworld/pull/154)), the indexer's queries |

## 1. The category of a balance is not in the market key

design/16 splits the market by category: equipment, ingredients, stillstone, potions (Q2: the keys of
a category with their cheapest lot). The frozen market key (`LotPosted.market_key`, ENG-01 §3.4) is,
for a balance, **its item id** only: the indexer cannot tell an ingredient from a potion or the
stillstone without the item registry.

IDX-01b does this for now: Q2 filters by the key's kind (balance, equipment, boss item) and by a list
of item ids **the client supplies** from the registry (which it reads anyway).

**Options**: (A) keep that: the category is the registry's, the client passes the ids; (B) the
indexer reads the item registry (its `class`, ENG-01 `ITEM` row) once per content version and
filters itself; (C) the category enters the key (a layout change of a frozen event: before the first
deployment only). **Recommendation: A** for the MVP (no new read path, no layout change), B if the
client's list grows awkward.

## 2. The unit of a lot's expiry is not defined

`LotPosted.expiry` and `Lot.expiry` are a `u64` (ENG-01 §3.4); design/16 says "an expired lot cannot
be bought" (lazy expiry) but no document says whether `expiry` is a **block timestamp** (seconds) or a
**block number**, nor whether the boundary is inclusive. IDX-01b returns open lots whether expired or
not; each lot carries `expiry` and each answer's head carries the block's timestamp, so the client can
hide expired lots once the unit is known.

**Recommendation**: a block timestamp in seconds, expired when `block_timestamp >= expiry` (the same
clock as the trade's 10 minutes, design/16), written in ENG-01 §3.4 and design/16 by the game's track
before RWD-10; IDX-01b's successor then filters expired lots from Q1 and Q2 by the served block's
timestamp.

## What would reverse it

A design that wants the category computed on-chain, or lot durations counted in blocks.
