# 15 — Equipment

> Status: **Draft v0.3** (v0.3: who does what; collectors are in the wilds)
> Previous: **Draft v0.2** — names are working names; numbers are initial values.
> v0.2: looted equipment and boss armor sets in the MVP; trade.
> Baseline: Guild Wars itemisation (official wiki and player analyses, read 2026-09-28).
> What could not be found there is said so; those numbers are ours.

## Principles

| # | Principle | From the baseline |
|---|---|---|
| Q-1 | **Statistics are capped, and the cap is reached early.** Maximum weapons and armor are available around the middle of a region's content, not at its end (D-35) | Max armor and weapons arrive mid-campaign; later content adds no tier |
| Q-2 | **Rarity sets how good the modifiers are, never the base statistics.** A common weapon can have maximum damage | Same |
| Q-3 | **Equipment is made of parts.** Modifiers can be taken off one item and set on another | Prefix, suffix, inscription; insignia, rune |
| Q-4 | **Strong modifiers have a condition or a cost** | "+15% while health is above 50%", "+3 attribute, −75 health" |
| Q-5 | **The look is the item** (D-34). What is rare and wanted is a look, a convenience, a name, a set; never a number above the cap | Prestige armor has the same statistics at 15 times the price |
| Q-6 | **No modifier rolls dice in combat.** Combat is deterministic (D-40) | Departure: the baseline has chance-based modifiers |

## Who does what

| Character | Where | Does | Never |
|---|---|---|---|
| **Merchant** | Hubs | Sells basic goods and kits, buys anything | — |
| **Smith** | Hubs | **Crafts** weapons, **recycles** equipment into materials, **personalises** | Touches a modifier |
| **Armorer** | Hubs | Crafts armor | Touches a modifier |
| **Enchanter** (enchanting table) | Hubs | Everything about **modifiers**: identify, lift off, set, on weapons and armor | Crafts |
| **Collector** | **Exploration zones**, at fixed places | **Barter**: goblin trophies and ingredients against a fixed item | Takes gold or stillstone |
| **Alchemist** | Hubs | Brewing, hints | — |

### Collectors

Collectors are characters met **in the wilds**, not in towns: a hermit, a deserter, a
pedlar who will not come near the walls. Zones have a fixed layout, so a collector is
always at the same place, and finding them is part of exploring.

| | |
|---|---|
| Interaction | Walk next to them and trade: one action, which ends the queue. They are a room feature, not an actor: they do not move, fight or get attacked |
| Offer | Fixed per collector: *5 runt ears → leather gloves*. No gold involved |
| Goods come from | The adventurer's pack, as carried in the instance |
| One piece each | A full armor asks for five collectors across a region |

Kinds of barter to explore, beyond trophies against equipment:

| Gives | Against |
|---|---|
| Armor piece, weapon | Goblin trophies |
| A bag or a belt pouch | Trophies |
| Potions | Ingredients the collector cannot find himself |
| A rare ingredient of another region | Ingredients of this one |
| A rumour: the place of a chest, a vein, a Red Rift | Trophies of a high caste |

## Sources of equipment

| Source | Gives | Randomness |
|---|---|---|
| **Merchant** | Basic weapons, no modifier | None |
| **Smith** (D-37) | A small pool of weapons per hub, fixed statistics, no modifier, chosen look, for gold and materials | None |
| **Armorer** | Armor of the hub's tier, for gold and materials | None |
| **Collector** (D-36) | In the wilds: one fixed piece (armor or weapon) for 3 to 5 goblin trophies | None |
| **Loot** (D-37) | Weapons and armor remains, of any rarity | Fate |
| **Boss** (D-37b) | Its own items: fixed look, fixed modifiers at maximum values | Fate decides whether it drops, not what it is |
| **Quest** | Fixed items | None |

Collectors make common trophies useful and guarantee that a player with bad luck is never
under-equipped. As in the baseline, a collector gives one piece, so a full armor asks for
five collectors across a region, and collector items cannot be changed of look.

## Weapons

### Base

| Weapon | Profession | Hands | Tick cost | Range | Damage at requirement 0 → 9 |
|---|---|---|---|---|---|
| Sword | Vanguard | 1 | 1 | 1 | 9 → 18 |
| Axe | Vanguard | 1 | 1 | 1 | 9 → 17 |
| Maul | Vanguard | 2 | 2 | 1 | 13 → 27 |
| Bow | Warden | 2 | 2 | 6 | 11 → 21 |
| Staff | Casters | 2 | 2 | 6 | 9 → 16 |
| Wand + focus | Casters | 1 + 1 | 2 | 6 | 9 → 16 |
| Shield | Vanguard | off-hand | — | — | Armor 8 → 16 |

Damage is the midpoint of the baseline's range, since we do not roll damage.

### Requirement

Each weapon has a **requirement**: a rank in its attribute, from 0 to 9. Damage grows with
the requirement and stops at 9.

| | |
|---|---|
| Attribute rank ≥ requirement | Full damage |
| Attribute rank < requirement | Damage divided by 3; modifiers still work |
| Anyone can hold any weapon | The requirement, not a class lock, is what ties a weapon to a build |

### Modifier slots

| Slot | On | Example |
|---|---|---|
| **Prefix** | Weapons (not wands) | Rending: bleeding you inflict lasts 33% longer |
| **Suffix** | Weapons, shields, foci | of Fortitude: +30 health |
| **Inscription** | Everything held | +15% damage while your health is above 50% |

### Modifiers and determinism (Q-6)

The baseline has modifiers that trigger "with a 10–20% chance". They are converted:

| Baseline | Grim World |
|---|---|
| 10–20% chance of +20% armor penetration | +2 to +4% armor penetration, always |
| 2–10% chance of double adrenaline on a hit | Every 10th to 5th hit gives double adrenaline (a counter on the adventurer) |
| 10–20% chance of halved casting time | Every 5th spell of the attribute costs 1 tick less |
| 10–20% chance of +1 attribute while using a skill | Dropped |

Modifiers kept as they are: condition duration (+33%), damage type change, life steal with
a health regeneration cost, energy on hit with an energy regeneration cost, health (+10 to
+30), armor (+4 to +5), armor against a damage type (+4 to +7), enchantment duration
(+10 to +20%), conditional damage (+10 to +15%), damage with a drawback (+15% damage,
−5 energy).

## Rarity

| Rarity | Colour | Modifiers | Value range of each modifier |
|---|---|---|---|
| Common | White | None | — |
| Fine | Blue | 1 | Lower half |
| Superior | Purple | 1–2 | Third quarter |
| Rare | Gold | 2–3 | Top quarter |
| **Boss** | Green | All slots | Maximum, fixed (D-37b) |

Base statistics depend on the level of the goblin that dropped the item: about 20% of the
maximum at level 1, the maximum from level 20. Rarity does not change them (Q-2).

### Drop rates

The baseline's publisher never published rates, and no rigorous player study was found.
The only figures are anecdotal: boss items about once in 8 to 12 kills. **Our rates are
ours**, to tune with the balance simulator:

| | Initial value |
|---|---|
| Remains holding equipment rather than ingredients or gold | 15% |
| Of those: common / fine / superior / rare | 60 / 28 / 10 / 2 % |
| Boss item, per boss kill | 10% |
| Bosses: number of items | Up to 3, plus gold |

### Identification (Q-18)

Looted equipment of fine rarity or better is **unidentified**: its rarity and base are
known, its modifiers are not.

| | |
|---|---|
| Identifying | At the enchanter's, for a few gold |
| On-chain | **Identifying is the draw.** Modifiers do not exist until the item is identified; the Fate draw happens in that transaction ([ADR-0002](../architecture/ADR-0002-randomness.md)). Nothing hidden needs to be stored |
| Needed to | Equip it, change its modifiers, salvage it cleanly |
| Value | Unidentified value follows the goblin's level. Identified value = (unidentified + a draw up to itself) × 1 for common and fine, × 2 for superior, × 4 for rare — formula measured by players of the baseline on about 1 000 items |
| The decision | Sell it closed for a sure small price, or pay to open it |

### Recycling (smith)

Recycling an item gives **materials** (iron, hide, wood, cloth, bone), more for a more
valuable item. The item and its modifiers are consumed.

### Modifiers (enchanter)

| Operation | Result | Risk |
|---|---|---|
| Lift a modifier off an item | The modifier, as a component | **The item is destroyed one time in two** (Fate) |
| Same, with 1 stillstone | The modifier | None |
| Set a component on an item | The item carries it | The modifier it replaces is lost |
| Same, with 1 stillstone | The item carries it | None: the replaced modifier comes back as a component |

## Armor

### Rating

| Armor class | Professions | Maximum rating | Innate |
|---|---|---|---|
| Heavy | Vanguard | 80 | +20 against physical damage |
| Medium | Warden | 70 | +30 against elemental damage |
| Light | Casters | 60 | + energy and energy regeneration |

Five pieces. The baseline draws the piece that is hit at random; we do not. The rating
used by the damage formula is the **weighted sum** of the pieces:

| Piece | Chest | Legs | Head | Hands | Feet |
|---|---|---|---|---|---|
| Weight | 3/8 | 2/8 | 1/8 | 1/8 | 1/8 |

### Tiers

| Hub | Heavy / medium / light | Order of price per piece |
|---|---|---|
| Town A | 35 / 25 / 15 | 20 gold |
| Outpost B | 50 / 40 / 30 | 75 gold + materials |
| Region 2, first hub | 65 / 55 / 45 | 200 gold + materials |
| **Region 2, second hub** | **80 / 70 / 60 (maximum)** | 1 000 gold + materials |
| Any later hub | Maximum, other looks | Much more, for the look only |

### Insignias and runes

| Slot | One per piece | Examples |
|---|---|---|
| **Insignia** | Yes | +15/10/5 health (chest/legs/other); +10 armor while in a stance; +10 armor while enchanted |
| **Rune** | Yes | +1 attribute; **+2 attribute, −35 health; +3 attribute, −75 health**; +30 to +50 health |

Rules taken from the baseline: only the highest rune of an attribute counts, but every
penalty counts; health runes of the same kind do not add up. Attributes reach 12 by points
and about 16 with everything.

## Boss items (D-37b)

| | |
|---|---|
| Tied to | One named boss |
| Look | Its own |
| Statistics | Requirement 9, every slot filled, every modifier at its maximum, all taken from the common pool |
| Cannot be | Modified, salvaged |
| Trade | **Tradable** (D-47), until personalised |
| Why want it | The look; a finished weapon without assembling one; the name of the boss |
| Weapon sets | The bosses of one dungeon or elite zone form a set by their look |

### Boss armor and set bonuses (D-45)

Each boss also drops the pieces of **one armor set per profession**: five pieces, a look
of their own.

| Pieces of the same set worn | Effect |
|---|---|
| 1–2 | Nothing more than the pieces |
| **3** | First bonus |
| **5** | First and second bonus |

How this stays under the cap (Q-1):

| Rule | |
|---|---|
| A boss piece has the maximum rating of its class, **no insignia slot and no rune slot** | Its insignia and rune are fixed, from the common pool, as for boss weapons |
| The set bonuses are what the player gets **in exchange** for the freedom they give up | Five free pieces hold five insignias and five runes of the player's choice; a set decides for them |
| **Budget**: the fixed modifiers of the five pieces plus the two bonuses must be worth no more than the best five free pieces | Checked by the balance simulator for every set before it ships |
| Bonuses are effects, not raw statistics, whenever possible, and obey Q-4 (a condition or a cost) and Q-6 (no dice) | Example below |
| Mixing | 3 pieces of one set and 2 free pieces is a legitimate build: one bonus and two free slots |

Example, first dungeon (working names), Vanguard set *Hob-breaker*:

| | |
|---|---|
| Pieces | Heavy armor 80; fixed insignia: +10 armor while in a stance; fixed rune: +30 health on the chest, none elsewhere |
| 3 pieces | Knock-downs you inflict last 1 tick longer |
| 5 pieces | The first attack that would bring you under 50% health in an instance is halved |

Drop: one piece at most per boss kill, of the adventurer's primary profession, in addition
to the chance of the boss weapon.

Art cost: five pieces per profession per boss. While equipment is not drawn on the
character, a piece is an icon; the MVP needs 15 icons for the first dungeon.

## Personalisation (D-48)

As in the baseline, any weapon, shield, focus or armor piece can be **personalised** by a
smith, for **one stillstone** and a small fee in gold.

| | |
|---|---|
| Effect on a weapon | +20% base damage |
| Effect on a shield or armor piece | +10% of its rating |
| Bound | To the adventurer, forever. The item can no longer be traded, listed or moved to another adventurer through the vault |
| Undo | Never |
| Boss items | Can be personalised like any other |

Since everyone can do it, the bonus is part of the expected power of a finished build, not
an advantage. What it creates is a decision: **keep the item's market value, or make it
yours**. It also removes items from the market for good, which supports prices.

## Gold

| Sink | |
|---|---|
| Skill trainers | 50 gold for the first skill bought, rising to 1 000 from the 21st, as in the baseline |
| Kits | 1 to 20 gold per use |
| Armor and smiths | See tiers |
| Looks | The largest sink by far |

Merchants buy at the item's value and sell at twice that value.

## Storage

| | Slots |
|---|---|
| Adventurer's pack | 20 |
| Belt pouch, bags | +5 each, from collectors and quests |
| Vault (account) | 25 per pane; panes are added by the estate's storehouse |
| Materials and ingredients | Counted, not slotted |

## On-chain notes

- An equipment item is an entity: base, requirement, rarity, up to three modifiers with
  their values, look, owner (adventurer or account). Packed in one or two felts.
- Ingredients, materials, potions and gold are balances, not entities.
- The instance reads equipment once, in the snapshot taken at entry (ADR-0001). Equipment
  cannot change during an expedition.
- Every draw (what the remains hold, identification, salvage) is Fate and happens in its
  own transaction.

## Scope

| Release | Contains |
|---|---|
| **MVP** | Every source of equipment; rarity, identification, salvage, modifiers, insignias and runes; the boss weapon and the three armor sets of the first dungeon; trade ([16-trade](16-trade.md)) |
| Later | More sets, looks, equipment drawn on the character |

Order inside the MVP: crafted and collector equipment first (it is enough to play), then
loot and modifiers, then sets, then trade. Each step is playable without the next.

## Open

| # | Question |
|---|---|
| EQP-4 | Balance is tuned for personalised or non-personalised equipment? Recommendation: personalised |
