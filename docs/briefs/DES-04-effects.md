# DES-04 — The effect catalogue and its resolution order

> D-150: the first task of the game's first slot while the engine chain waits for the map library.
> A design document in its own pull request; CBT-01 (the combat interfaces) is written from it.

## Agent
Title: `[Opus 5.5] DES-04 effects` · Profile: implement · Branch: `docs/des-04-effects`

## Goal
After this task the game has **one closed list of what a skill, a condition, an item or a goblin can
do to the world**, and **one exact order in which a tick resolves it**, precise enough that the
contracts and the client's TypeScript mirror (SPK-4, D-140) compute the same result from the same
state, and that CBT-01 can freeze the schemas without inventing a rule.

## Context
- **design/04** (combat) in full: actions and their ticks, ranges, weapons, facing and arcs (D-41),
  the damage formula and its **Edges (D-140)**, energy and adrenaline, the five conditions,
  interrupts and activation, the goblin AI, death and defeat. **design/02** *The tick (D-01)* (the
  world tick and its steps), *Planned queues and played batches* (a batch, weight, stops).
- The skills and effects the design already names: **design/03** (professions, attributes, the
  skill bar), **design/05** (bestiary: castes and their skills), **design/15** (equipment modifiers
  and their effects), **design/07** (potions and their effects), **design/17** (the Rift Heart,
  burning and poisoned), design/18 (terrain and features).
- **What the data can hold**: `docs/architecture/ENG-01-interfaces.md` §3.5, the `SKILL` record (3
  effects of kind, value at rank 0 and 12, duration), `CASTE`, `MODIFIER`, `ITEM`'s potion effect;
  §3.2, the member's and goblin's words (5 conditions, an effect, the activation, recharges);
  `grimworld_logic::durations` (the cap on durations). The catalogue must fit these, or say
  precisely what it needs added (an escalation, not a change).
- D-140 (a rule never panics on a legal action; percent modifiers summed and applied once; damage
  saturated), D-133/D-141 (batches; at most 16 goblins changed an invocation), CONTEXT.md (§5, the glossary).

## Scope
- In: a new **`docs/design/19-effects.md`**, with:
  - **The catalogue**: every effect kind (damage by type, heal, the five conditions and their
    removal, energy and adrenaline changes, knock-down, movement and displacement, interrupt, area
    shapes, summons if any, the item and potion effects, the modifiers' effects), each with its
    parameters, its units, its bounds, and which sources use it (skills, castes, items, modifiers).
    Closed: an effect not in it does not exist.
  - **The resolution order** within a tick and within one action: what is computed from the state
    before the tick and what from the state being changed; the order between actors (by entity id
    or another total order: say which and why it is deterministic); simultaneous hits and deaths;
    blocking and evasion if the design has them; interrupts (what an interrupted activation spends
    and keeps); area targeting (which tiles, which actors, in which order); conditions applied,
    refreshed or stacked; what happens at 0 health mid-resolution.
  - **Edges**, in D-140's style: every case a player can reach has a defined result, no panic.
  - **What CBT-01 freezes** from it, and the sheet shape DES-06 fills later (castes: the fields, not
    their values).
  - A short amendment list for the design documents it contradicts or completes (design/04 above
    all), made in this pull request as small edits with the new document's reference.
- Out: numbers for balance (curves, values of skills and castes: BAL-01, DES-06); any code; the
  interfaces themselves (CBT-01).
- **A rule the design documents cannot settle comes to the orchestrator as an escalation** (the
  project manager decides it, D-150): write the question, the options, and your recommendation;
  do not decide a game rule the documents leave open.
- Allowlist: `docs/design/19-effects.md`, small cross-reference edits in `docs/design/*.md`,
  `REPORT.md` (a new term is listed there for the glossary of CONTEXT §5, which the project
  manager keeps).

## Acceptance criteria
- [ ] AC-1 The catalogue is closed and covers every skill, condition, item effect and modifier the
      design documents name (a table from source to effect kind, nothing left out).
- [ ] AC-2 The resolution order is total and deterministic: two implementations following it
      compute the same state (the report walks three worked examples: an area hit killing two
      goblins at once, an interrupt, a condition refreshed while ticking).
- [ ] AC-3 Every reachable edge has a defined result (D-140's principle).
- [ ] AC-4 What does not fit ENG-01's records is listed as an escalation with its cost in slots.
- [ ] AC-5 Every rule the documents did not settle is an escalation, not a decision.

## Audits
Design (determinism of the order, completeness, consistency with the design documents):
**`[GPT-6-Astra]`**.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the sources read, the catalogue's coverage table, the
three worked examples, the escalations with options and recommendations.
