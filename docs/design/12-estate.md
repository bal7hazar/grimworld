# 12 — Estate (idle layer)

> Status: **Draft v0.2** — post-MVP. Names and numbers are initial proposals.
> v0.2: lessons from comparable games (research of 2026-09-28).

## What it is

Each **account** owns one estate (working name). The player spends resources and **real
time** to build and upgrade buildings that serve the side activities of the game: growing
ingredients, brewing, enchanting, storing. It is the long-term, low-attention part of the
game, played in a few taps between expeditions.

This departs from Guild Wars, which had no such layer.

## Rules that cannot be broken (D-91)

| # | Rule |
|---|---|
| E-1 | **Nothing from the estate alters the difficulty of an instance.** No statistic, no skill, no attribute, no extra belt slot |
| E-2 | **Timers cannot be skipped by paying** (D-92) |
| E-3 | The estate belongs to the **account** and is shared by its adventurers, like the vault (D-93). It gives value to the account over time |
| E-4 | **Discovery stays manual.** The estate only repeats what an adventurer already knows how to do |
| E-5 | **What is rare stays in the wilds.** The estate produces common goods only |
| E-6 | **Accrual is capped.** A full building stops producing until it is emptied |

## Buildings

| Building | Does | Upgrading gives | Never gives |
|---|---|---|---|
| **Garden** | Grows common ingredients of the regions the account has unlocked | More plots, shorter growth | Uncommon or rare ingredients |
| **Laboratory** | Brews, in series, recipes already in the grimoire of the adventurer who queues them | Longer queue, shorter brewing | Discovery of recipes; stronger potions |
| **Enchanter's workshop** | Extracts a modifier from a looted weapon and sets it on another | More benches, shorter work | Modifiers stronger than what loot gives |
| **Storehouse** | Extends the shared vault | More space | — |
| **Trophy hall** | Displays titles and boss trophies | Decoration | Anything else |

## Time

| Level of a building | Order of magnitude of an upgrade |
|---|---|
| 1–3 | Minutes |
| 4–6 | Hours |
| 7–9 | A day to several days |
| 10 | Weeks |

Production fills its cap in about **three days**. One visit every few days loses nothing;
visiting several times a day brings nothing more. The estate must never become a daily
obligation.

## Lessons from comparable games

| Game | What happened | What we take |
|---|---|---|
| The Mighty Quest for Epic Loot (PC) | Resource mines that stop when full; upgrades taking hours, skippable with premium currency; perceived as pay-to-win and closed in 2016 | Caps (E-6); no paid skip (E-2) |
| Same | Named item sets gave **no bonus** for wearing several pieces | Boss sets can be desirable without set bonuses |
| Clash of Clans | Timers gate power and are sold; the studio cut them repeatedly (2018, 2023) and removed army training time in 2025 | Long timers on power are a dead end even for their inventor |
| World of Warcraft garrison | Large payoff made it a mandatory chore that kept players away from the game; its own designers regretted that followers played instead of the player | Small payoff, generous cap; the estate repeats, it does not play |
| Melvor Idle | Offline progress capped at 24 hours to protect the economy | A cap is an economic tool, not a punishment |
| Guild Wars 2 masteries | Account-wide unlocks of capabilities, not statistics; a later statistics tier caused a backlash | Account-wide, no statistics (E-1, E-3) |

## Why this does not break the pillars

| Pillar | Check |
|---|---|
| The world waits for you | It still does, **inside instances**. The estate lives outside them, where real time already exists (hubs) |
| Build over grind | Power is untouched (E-1). The estate supplies **quantity and comfort**: a stocked belt without farming commons by hand |
| Deterministic tactics, random rewards | No randomness in the estate: a plot yields a known quantity after a known time |

The belt holds four potions: owning two hundred changes nothing to an expedition.

## Implementation notes

- Persistent domain. Lazy evaluation, as in Eternum and Primodium: each building stores
  `(last update, rate, cap)`; the yield is `min(cap, rate × elapsed)`, computed when the
  player collects. No transaction is needed for time to pass.
- **Settle before any change of rate**: an upgrade first collects at the old rate, then
  changes the rate, otherwise the new rate applies to the past.
- Only the owner can settle their estate: no third party controls when state is written.
- Rounding remainders are carried, not lost. Timestamps are 64 bits.
- Block timestamps are used here. This does not conflict with the rule "no block data in
  an instance", which concerns the ephemeral domain only.
- The sequencer can shift a timestamp by a few seconds; with cycles of minutes to days
  this is accepted.

## Open

| # | Question |
|---|---|
| EQ-1 | What buildings cost: gold, ingredients, boss trophies? |
| EQ-2 | Can an estate be visited by other players (social, display of trophies)? |
| EQ-3 | Enchanting: is moving modifiers enough, or does it need its own design once equipment is written? |
| EQ-4 | Does the estate have a place on the map (a location near the first town) or is it a screen? |
