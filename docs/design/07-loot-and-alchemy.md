# 07 — Loot and alchemy

> Status: **Draft v0.2** — numbers are initial values for balancing.
> v0.2: rarity signatures added to alchemy; satchel removed (loot is kept on defeat).

This is where randomness lives (pillar 5). Every draw in this document uses the
unpredictable randomness source ([ADR-0002](../architecture/ADR-0002-randomness.md)).

## Loot

### What drops

| Item class | Source | Use |
|---|---|---|
| **Ingredients** | Goblins, gathering nodes, chests | Alchemy, gathering quests |
| **Gold** | Goblins, quests, selling | Trainers, services |
| **Trophies** | Bosses (guaranteed) | Proof for nest-clearing quests, rare recipes |
| **Equipment** | Goblins, bosses | See [15-equipment](15-equipment.md) |

Weapons and armor come from merchants, smiths, armorers and collectors, and from **loot**
with rarity and identification, in the MVP (D-44; [15-equipment](15-equipment.md#scope)).

### When it is rolled

A dead goblin leaves **remains** on its tile. The drop is rolled **when the adventurer
loots the remains** (walks onto the tile), not when the goblin dies (D-50). It goes
straight to the inventory and is kept whatever the outcome of the expedition
([02-core-loop](02-core-loop.md#ending-an-expedition-d-04)).

Why on loot and not on death: moving and fighting then need no randomness at all, so they
can be rendered optimistically and batched; only the loot action carries a randomness
request, and it is a moment where a short reveal delay reads as suspense rather than lag.
Looting always ends an action queue and a batch.

### Loot tables

A loot table is a registry entry per caste, optionally overridden per location.

```
LootTable { caste, entries: [(ingredient id, weight)], nothing_weight, gold: (min, max) }
```

| Caste tier | Ingredient rarity drawn from |
|---|---|
| 1–2 | Common |
| 3–4 | Common, Uncommon |
| 5–6 | Uncommon, Rare, guaranteed Trophy for bosses |

Each region adds its own ingredients. An ingredient belongs to exactly one region.

## Alchemy

Adapted from Athanor's crafter. The player combines **two ingredients**; the result is
either a **potion** or a **failed brew**.

### Principles

- There is **no published recipe table**. The result of a pair is decided **the first time
  this adventurer brews it**, then frozen for this adventurer forever.
- Therefore **each adventurer's grimoire is unique**. What works for someone else does not
  work for you; knowledge cannot be copied from a wiki. Potions, however, can be shared if
  trading exists.
- Discovery is **sampling without replacement**: every failed attempt raises the chance of
  the next one, and every recipe is guaranteed to be found before the pairs run out.
- **A recipe costs the same to everyone** (D-52). Which two ingredients make a potion
  differs between adventurers; *how rare* those two ingredients are does not.

### Rarity signatures (D-52)

Every ingredient has a rarity: Common (C), Uncommon (U) or Rare (R). Every recipe has a
fixed **signature** in the registry: the pair of rarities it is brewed from. A pair of
ingredients can only ever reveal a recipe of its own signature.

Region 1 book, 10 ingredients = 5 C + 3 U + 2 R:

| Signature | Pairs | Recipes | First-try chance |
|---|---|---|---|
| C + C | 10 | 3 | 30% |
| C + U | 15 | 4 | 27% |
| U + U | 3 | 1 | 33% |
| C + R | 10 | 2 | 20% |
| U + R | 6 | 1 | 17% |
| R + R | 1 | 1 | 100% |
| **Total** | **45** | **12** | |

Registry rule, checked by content validation: in every signature,
`recipes ≤ pairs`, so that every recipe is reachable.

**Cost.** The signature is computed from two rarity lookups in a packed constant. It adds
one mask and one packed counter to the discovery, both in storage slots the algorithm
already reads and writes. No loop is added. The step budget of brewing is measured in
spike SPK-2 and the feature is kept only if its overhead is negligible.

### Books

Recipes are grouped in **books**. A book is a closed set, so that the probability math
stays exact when the world grows:

```
Book { id, region, ingredients: n, recipes: r }      pairs = n × (n − 1) / 2
```

| Book | Ingredients | Pairs | Recipes | First-try chance |
|---|---|---|---|---|
| Region 1 (MVP) | 10 | 45 | 12 | 26.7% |
| Each later region | 10–12 | 45–66 | 12–15 | ~23–27% |

A pair is only valid within one book. Cross-book pairs are reserved for a later
"grand grimoire" feature.

### Discovery algorithm

Book constants (registry):

```
rarities         packed rarity of each ingredient
masks[sig]       bitmap of the recipes of each signature
```

State per adventurer and per book:

```
grimoire         bitmap of discovered recipes
remaining[sig]   untried pairs per signature, packed in one felt
Discovery(adventurer, a, b) → { discovered, recipe }     with a < b
```

Brewing `(a, b)`:

```
if Discovery(a, b).discovered:
    result = Discovery(a, b).recipe             # deterministic, no randomness needed
else:
    sig        = signature(rarity(a), rarity(b))
    candidates = masks[sig] & ~grimoire
    p          = count(candidates) / remaining[sig]
    if roll_1 < p:  result = candidates[roll_2 mod count(candidates)]
    else:           result = none
    remaining[sig] -= 1
    Discovery(a, b) = { discovered: true, recipe: result }

consume the ingredients
if result is none: grant a failed brew (sells for 1 gold)
else:              grant the potion
```

Differences from Athanor, on purpose:

| Athanor | Grim World | Why |
|---|---|---|
| Same random word for the success roll and the selection | Two independent draws derived from the word | The two outcomes should not be correlated |
| Pair stored in the order first supplied, both orders looked up | Pair normalised to `a < b` | One storage read instead of two |
| Re-brewing a known pair still consumes randomness | Known pairs skip the randomness request | Cheaper, and instantly confirmable by the client |
| One game-wide book, fixed at 25 ingredients | One book per region | Horizontal scaling |
| Any pair can reveal any recipe | A pair reveals only recipes of its rarity signature | Same ingredient cost for everyone |
| Hints bought with gold, at a price that triples | Hints bought from the alchemist for **one stillstone** each | Ties alchemy to Rifts |

### Hints

A hint is bought from the alchemist, in a hub, for **one stillstone**
([17-rifts](17-rifts.md#what-it-is-for)). A few quests give one as a reward.

A hint binds one undiscovered recipe to one ingredient: *"nightroot is part of the Draught
of Stone"*. As in Athanor, the hinted recipe leaves the general pool and can only be found
through a pair containing that ingredient, with its own denominator (the untried partners
of that ingredient **that have the rarity required by the signature**), which guarantees
discovery within at most that many attempts.

### Potions

Potions are consumables used in an instance (1 tick). They fill the gaps of a solo build.

| Family | Examples of effect |
|---|---|
| Restoratives | Heal over time, remove a condition, restore energy |
| Draughts | +armor, +health regeneration, +movement for N ticks |
| Oils | Weapon applies a condition for N attacks |
| Bombs | Thrown: area damage or condition on a tile |
| Rare (R + R) | Revive once in the expedition; reveal the floor |

Rules:

- The **belt** holds 4 potion slots, filled in a hub. The belt is part of the build.
- A potion's strength is fixed by its recipe; potions do not scale with attributes.
- Brewing happens in hubs only.

## Economy notes

- Gold is an internal balance in the MVP, not a token.
- Sinks: skill trainers, equipment merchants, map travel fee, belt refills for those who
  buy instead of brewing.
- Whether ingredients, potions and gold are transferable between adventurers, and whether
  any of it is tokenised, is open (Q-07). The data model must not prevent it: item
  balances are keyed by owner and item id.
