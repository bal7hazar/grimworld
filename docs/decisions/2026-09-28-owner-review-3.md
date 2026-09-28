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

| D-42 | ~~Companions and escort quests~~ **Withdrawn the same day**: considered, designed, then dropped by the owner as bringing more complexity than benefit to the player. The design is in the git history (commit 3f61552) |
| D-44 | **Looted equipment is in the MVP** |
| D-45 | **Boss armor is in the MVP**, with a bonus for wearing 3 pieces of a set and a second one for wearing all 5 |
| D-46 | **Players can trade with each other**, and there is an **auction house**, modelled on the one of classic Dofus |
| D-43 | The secondary profession is kept as a feature and deprioritised: not needed to prove technical feasibility |

| D-47 | Boss items are tradable |
| D-48 | Personalising an item gives a damage or defence bonus and binds it to the adventurer, making it unsellable, as in Guild Wars |
| D-49 | Auction house strategy delegated to the orchestrator: one world market, listing fee only, Tin rank to sell |
| — | Arcade packages are under MIT licence (owner's statement) |

| D-95 | ~~Shared closing delay~~ Replaced by D-101 |
| D-101 | Rifts (the owner's word, instead of Maw) are **personal**: **3 open, 5 per day and per account**, the fifth being the Red Rift; against farmers destabilising the economy, and against repeating the same day on each adventurer |
| D-102 | Accounts: Cartridge Controller is not taken for granted. Burner accounts first; Controller evaluated; a solution of our own if needed |
| D-100 | **No fee is ever paid by the player.** The business model covers network costs without the player knowing. The abstraction must let the player ignore the blockchain entirely |
| D-96 | Stillstone is a rare reagent for precise operations of craft, alchemy and enchantment. It does not replace materials and is not the main income: the treasure is what goblins carry |
| D-97 | English only for the first version, multilingual afterwards. Names short and international |
| D-20 (revised) | Ten grades, accepted: Wood, Tin, Copper, Iron, Steel, Bronze, Silver, Gold, Platinum, Onyx |

| D-98b | Stillstone uses: personalisation (smith), modifiers (enchanter), hints (alchemist) |
| D-98 | Roles: the smith crafts, recycles and personalises and never touches a modifier; modifiers belong to the enchanter (enchanting table) |
| D-99 | Collectors are characters met in exploration zones who barter items against items. No stillstone, no gold |

| D-103 | Maps are large and cut in chunks; goblins cross chunks; top-down camera (ADR-0006). Generation with margins is added to the map library by the owner |
| D-104 | ~~Zones are authored level design~~ Replaced the same day by D-106 |
| D-106 | **Fully generative**: zones and dungeons are generated chunk by chunk at reveal, under generic constraints (level band of the zone) and contextual ones (what an active quest or contract needs). Nothing scales with the adventurer |
| D-107 | A fog of war must resist reading the chain: what is not yet seen must not be derivable. Accepted risk for nothing |
| D-108 | Guild contracts do not scale. Easy ones can be redone; guild rank opens harder, better-paid ones |
| D-105 | What is revealed of a map belongs to the instance and resets with a new one |
| — | Rule of sight (same information on every screen): adopted provisionally; the owner rules after testing |

| D-109 | Zones have an **outline drawn in advance** (irregular, any size), so that the world map can be drafted without knowing the content. Dungeons let their outline emerge (a free edge is a border with some probability, respecting neighbours) |

| D-110 | **MVP randomness is the transaction hash.** Known to be weak; the aim is to test quickly. Improved for version 1 |
| D-111 | Random word at reveal: one draw at entry, then a value built from the adventurer's irreversible actions. Reading one chunk ahead is accepted. An alternative in the same spirit may be looked for later |
| D-112 | Dungeons have a target size, 6 to 12 chunks by grade; their outline emerges within it |

## To study before deciding

| # | Question | Input needed |
|---|---|---|
| Q-18 | Looted weapons: rarities, identification, gold value, drop rates | Researched; proposal in `docs/design/15-equipment.md`. Drop rates were never published for Guild Wars: ours are our own |
| ~~Q-19~~ | **Closed by D-45**: boss armor sets are in the MVP. ~~Should boss-tied sets extend to armor?~~ Under D-37b it would not unbalance anything. The Mighty Quest for Epic Loot had named sets without any set bonus. Guild Wars did not: its armor comes from crafters and collectors. Recommendation: weapons, shields and foci first | Owner |

## Business model elements named so far

Extra adventurer slots; cosmetics without gameplay effect (auras, miniature pets). Not
designed yet (DES-15).
