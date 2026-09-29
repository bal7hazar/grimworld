# 09 — MVP scope

> Status: **Draft v0.1**

The MVP is the smallest release in which the three core loops (tick, expedition, career)
are all playable end to end by a stranger, on a public network.

## In

| Area | MVP content |
|---|---|
| World | Region 1: 1 town, 1 outpost, 3 zones (tutorial, road, deep), 1 dungeon of 3 floors |
| Professions | Vanguard, Warden, Arcanist |
| Skills | 12 per profession (6 starter + 6 from trainers), no elite |
| Level | 1 → 20 |
| Guild ranks | Wood → Copper (3 ranks, 2 promotion trials) |
| Quests | 25 per adventurer plus repeatable guild contracts ([14-quests-region-1](14-quests-region-1.md)) |
| Titles | 6 character titles, 2 account titles ([13-titles](13-titles.md)) |
| Account | 3 adventurer slots, shared vault |
| Castes | Runt, Slinger, Skirmisher, Shaman, Hobgoblin (boss) |
| Conditions | Bleeding, Poison, Burning, Crippled, Knocked down |
| Loot | Ingredients, gold, trophies, **equipment**, heartstone, stillstone |
| Alchemy | Region 1 book: 10 ingredients, 12 recipes, belt of 4 |
| Equipment | Merchant, smith, armorer, collectors; **looted equipment** with rarity, identification, salvage and modifiers; **boss weapons and boss armor with set bonuses** ([15-equipment](15-equipment.md)) |
| Trade | Direct trade between players and an **auction house** ([16-trade](16-trade.md)) |
| Hubs | Services as contract calls; the list of adventurers present, from the indexer. No chat, no live movement, no rankings |
| Client | iOS and Android apps first, desktop web second; optimistic rendering, played batches |
| Account | Burner accounts behind the account interface; no prompt, no fee (ADR-0005). Randomness from the transaction hash (ADR-0002). **Test networks only, nothing of value** |
| Rifts | Grades Wood to Copper; three open, five a day, the Red Rift last; mining and stillstone ([17-rifts](17-rifts.md)) |
| Maps | Chunks generated at reveal, simulation window, zone outlines (ADR-0006) |

## Out (ordered by expected priority after MVP)

1. Secondary profession
2. Cleric, then Gravecaller and Beguiler
3. Elite zone, elite skills and capture
4. Remaining castes (Trapper, Wolf rider, Hexer, Champion, Paladin, Lord)
5. Ranks Iron → Onyx
6. Region 2
7. Tokenisation (Q-07)
9. Estate (idle layer)
9. Co-op
10. Hardcore ruleset

## MVP success criteria

| # | Criterion | Measure |
|---|---|---|
| S-1 | A new player reaches the outpost without external help | Playtest, ≥ 70% of testers |
| S-7 | The phone stays cool | ADR-0003 thresholds: ≤ 8% battery per 30 minutes on reference phones |
| S-2 | Acting feels instant | Input-to-render ≤ 100 ms (optimistic); chain confirmation never blocks the next input |
| S-3 | Optimistic state is right | Client/chain divergence on deterministic actions = 0 in the parity test suite |
| S-4 | Builds matter | At least 3 distinct viable bars per profession clear the dungeon in playtest |
| S-5 | An expedition is affordable | Cost per expedition within the budget fixed in Phase 0 |
| S-6 | Content is data | Adding a test zone and a test quest requires no contract code change |
