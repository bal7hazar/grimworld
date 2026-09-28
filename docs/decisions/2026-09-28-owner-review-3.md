# Owner review, round 3 — 2026-09-28

## Decided

| # | Decision |
|---|---|
| D-32 | Adventurer creation asks for a name and a profession only. No colour choice, no appearance editor for now |
| D-33 | 3 adventurer slots per account; more can be bought in game. One vault per account, shared by its adventurers |
| D-34 | The look of an adventurer is its equipment: no skin layer over equipment. One appearance per profession is drawn for now. Variations by recolouring in code and by generated sprites are acceptable |
| D-90 | The business model sells cosmetics without any effect on the rules: auras, miniature pets and the like |
| D-35 | Equipment follows the Guild Wars model: statistics capped at level 20, then horizontal upgrades |
| D-36 | **Collectors** trade goblin trophies and ingredients for armor pieces, as in pre-Searing. **Smiths** forge specific appearances |
| D-37 | Weapons come from two sources: **forged** (a small pool) and **looted** from goblins. Some weapon sets are tied to bosses |
| D-37b | **Boss items** follow the Guild Wars unique-item model: a look of their own and **predefined modifiers taken from the existing pool, at their maximum values**. They add no modifier and no value that cannot be obtained elsewhere, so they do not move the power cap |
| D-91 | An idle layer, the **estate**, is kept. It never grants anything that alters the difficulty of an instance; it serves alchemy, enchantment, farming, storage |
| D-92 | Timers cannot be skipped by paying |
| D-93 | The estate belongs to the account, like the vault: it gives value to the account and an incentive to stay on it |
| D-94 | The estate comes after the MVP: the expedition loop must first prove fun on its own |
| D-38 | **Titles**, some attached to the adventurer and some to the account |
| D-39 | Quests of the first region take the pre-Searing quests as structural models, with our own names, texts and characters |

| D-42 | **Companions**: allied characters follow the adventurer in instances, some using their own skills to help. Escort quests are part of the game |
| D-43 | The secondary profession is kept as a feature and deprioritised: not needed to prove technical feasibility |

## To study before deciding

| # | Question | Input needed |
|---|---|---|
| Q-18 | Looted weapons: rarities, identification, gold value, drop rates | Researched; proposal in `docs/design/15-equipment.md`. Drop rates were never published for Guild Wars: ours are our own |
| Q-19 | Should boss-tied sets extend to armor? Under D-37b it would not unbalance anything. The Mighty Quest for Epic Loot had named sets without any set bonus. Guild Wars did not: its armor comes from crafters and collectors. Recommendation: weapons, shields and foci first | Owner |

## Business model elements named so far

Extra adventurer slots; cosmetics without gameplay effect (auras, miniature pets). Not
designed yet (DES-15).
