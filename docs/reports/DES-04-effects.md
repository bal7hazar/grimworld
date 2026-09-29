# [Opus 5.5] DES-04 — The effect catalogue and its resolution order

## Summary
A new design document, **`docs/design/19-effects.md`** (Draft v0.1), now holds:
- **a closed catalogue** of 22 effect kinds that act (ids 1–22: damage, attack bonus, heal, life
  steal, regeneration, condition, cure, energy, next-spell cost, armor, penetration, hit
  penetration, block, evade, on-attack condition, movement, interrupt, trap; post-MVP revive,
  reveal the floor, on-skill-use, summon) and 21 passive kinds (ids 40–60: modifiers, attributes,
  set bonuses, affixes). It also fixes the stable ids of conditions (1–9, in ENG-01's storage order),
  damage types (1–9), shapes (5), guards (5) and targets. Every kind has its parameters, units,
  bounds and sources. No displacement exists, and no summon exists in the MVP;
- **the effect entry** CBT-01 freezes: kind, param, value at rank 0 and 12, **duration at rank 0
  and 12**, target, shape, guard;
- **the resolution order**: tick steps 0–5 with their order between actors; a counting rule for
  every timer ("a timer counts the executions of the step that consumes it", with explicit deadline
  formulas); the action phase; the order inside one hit (arc → block/evade → armor → damage →
  target-side effects → source-side effects → death); areas in ascending tile index,
  target-major, with the set taken at resolution; refresh and stacking; step 3 (pips summed, then
  clamped to ±10); activation and interrupts; zero health, simultaneous deaths and defeat;
- **edges** in D-140's style (§6), 26 rows;
- **what CBT-01 freezes** (§7) and **the caste sheet's shape** for DES-06 (§7.1);
- **a coverage table** (§8) from every source the design documents name to its kinds;
- **escalations FX-0 to FX-24** (§9; details below). Rules marked ⟨FX-n⟩ in the text are
  recommendations and are not decided.

Small cross-reference amendments: design/02 (tick steps → 19 §5), design/03 (skill effects → 19),
design/04 (v0.4: status line; conditions: MVP five and refresh → 19, FX-6/FX-22; interrupts → 19
§5.1/§5.7; the order of one hit → 19 §5.3 and FX-9), design/05 (skills and caste sheet → 19),
design/07 (potions → 19, FX-18), design/15 (modifiers → 19 §4).

Pull request: **https://github.com/bal7hazar/grimworld/pull/139**. CI is green (every check passed,
watched to completion). The model named in the header is the one my session says I am running as
(Opus 5.5), the same model the brief names.

## Files changed
- `docs/design/19-effects.md`: new, the catalogue, the order, the edges, the freeze list, coverage, escalations.
- `docs/design/02-core-loop.md`: a pointer under the tick's five steps.
- `docs/design/03-adventurer.md`: a pointer under the skill definition.
- `docs/design/04-combat.md`: v0.4; pointers in conditions, interrupts and damage types; MVP conditions named.
- `docs/design/05-bestiary.md`: a pointer in the castes' notes.
- `docs/design/07-loot-and-alchemy.md`: a pointer in the potions' rules.
- `docs/design/15-equipment.md`: a pointer after the kept modifiers.

## Commands run
- Read: the brief, COMMON.md, CONTEXT.md, design/02 (the tick, batches, validity), 03, 04, 05, 07
  (potions), 08 (M-1…M-6), 09, 14 (skill quests), 15, 17 (grades, mining), 18 (features,
  perception), ENG-01 §3.1–§3.5 and §9.2, `contracts/logic/src/durations.cairo`, `actions.cairo`,
  `professions.cairo`, `tick.cairo` (empty), D-150's decision, PLAN's CBT/DES rows.
- The damage table values for the examples (`python3`, the table of D-140, 16 fractional bits
  rounded to nearest): `2^(20/40)` → 92,682; `2^(−10/40)` → 55,109; `⌊80 × 92682 / 65536⌋ = 113`;
  `⌊27 × 55109 / 65536⌋ = 22`.
- `git push -u origin HEAD`, `gh pr create` → #139; `gh pr checks 139 --watch --interval 30`: all
  pass (client, discover, tooling, cairo contracts and the seven spike packages).

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| — | — | — | — | a design task, no Cairo |

## Acceptance criteria
- **AC-1** The catalogue is closed (X-1; §3, §4) and §8 lists every source the documents name, 18
  starter skills, the 6 primary attributes, 9 conditions, weapons and arcs, 11 castes and 2
  affixes, 5 potion families, every modifier of design/15, insignias, runes, personalisation, the
  *Hob-breaker* bonuses, terrain traps, veins, the Rift Heart and shouts, each mapped to its kind.
  Non-effects (chests, remains, nodes, collectors, levers, braziers) are named as outside the
  catalogue. Two named things are deliberately **not** catalogued because no document says what
  they do (Paladin "protects the lord", Beguiler "illusions"): FX-20.
- **AC-2** The order is total: every step has an order between actors (§5.1), every multi-target
  effect an order between targets (§2.1), every hit an internal order (§5.3), every timer a
  counting rule with its formula (§5.1). The three worked examples are below.
- **AC-3** §6 gives a result for every reachable edge. The edges whose result is a rule the
  documents leave open (knocked-down adventurer, full effect slots, trap on a full chunk, adrenaline
  cap) point to their escalation, with a recommendation.
- **AC-4** FX-24 lists what does not fit ENG-01's records, each with its cost in slots.
- **AC-5** Every rule not settled by the documents is marked ⟨FX-n⟩ or ⟨C⟩ in the text and listed
  below. None is presented as decided.

### Worked example 1: an area hit that kills two goblins at once
The state is illustrative and the numbers are not balance. An Arcanist of level 20 with Fire 12
stands on tile (10, 10). Goblins stand on the three adjacent tiles: **57** on (10, 9) = tile 2,314
with health 90, **90** on (11, 10) = tile 2,571 with health 100, and **24** on (10, 11) = tile
2,826 with health 200. Each has armor 40 and health regeneration 0, and none holds a block.

1. **Action phase, clock 40.** The Arcanist casts Cinder Ring (15 / 2 / 12). The cast is legal, and
   15 energy is paid at once (⟨C⟩). The activation has n = 2 and first tick 41, so its deadline is
   A = 42 (§5.1). The action's two ticks run next.
2. **Tick 41.** Step 1 has nothing due. In step 2 the goblins act in id order 24, 57, 90; suppose
   none moves away, and none can interrupt. Steps 3 and 4 follow.
3. **Tick 42, step 1.** The member resolves first (entity 0). Its targets are taken **now**: the
   foes on the 6 adjacent tiles, in ascending tile index 2,314 (goblin 57), 2,571 (goblin 90) and
   2,826 (goblin 24). This is not id order.
   - For each target, the damage is `⌊80 × table(60 − 40) / 2^16⌋ = ⌊80 × 92,682 / 65,536⌋ = 113`,
     with a percent sum of 0. Here 80 is the value at rank 12, 60 is `3 × 20` and 40 is the armor.
   - **57**: 90 → 0. It dies at once (§5.8), and the Burning entry is skipped because it is dead.
     `GoblinKilled(57)` is emitted first.
   - **90**: 100 → 0. It dies, and `GoblinKilled(90)` is emitted second.
   - **24**: 200 → 87, then Burning at rank 12 = 3 ticks. The application happens in step 1 of tick
     42, so t₀ = 42 and D = 44.
   - The recharge of 12 counts from the resolution: t₀ = 42, R = 53, so the Arcanist can cast again
     in the action phase at clock ≥ 53.
   - If goblin 57 had an activation due at 42, it would not resolve, because it was killed by an
     actor earlier in step 1's order.
4. **Tick 42, step 2.** Only goblin 24 acts. 57 and 90 have left the awake set.
5. **Step 3 of ticks 42, 43 and 44.** Goblin 24 takes −7 pips = −14 health each tick:
   87 → 73 → 59 → 45. In tick 45 Burning is no longer active (45 > 44), so it degenerated exactly
   3 times.

Any two implementations of §5 get the same events in the same order (57, then 90), the same
health for 24, and the same deadlines.

### Worked example 2: an interrupt
A Hobgoblin, **entity 40**, has armor 70 and health 400. It starts its overhead smash (an attack
skill with activation 3) in **step 2 of tick 50**. Its energy is paid now. The first step 1 after
the start is tick 51, so A = 51 + 3 − 1 = **53**. The adventurer therefore has the action phases
at clocks 50, 51 and 52 before the smash lands: design/04's "exactly three actions".

1. **Action phase, clock 50.** The adventurer steps to the Hobgoblin's front tile, and tick 51 runs.
2. **Action phase, clock 51.** The adventurer uses Skullring: 6 adrenaline, knock-down for 2. The
   adventurer is a Vanguard of level 20 with a maul and Mauls 12, holding 24 quarter strikes.
   - Per FX-5 the skill has no activation ("–"), so it lands at once, and its tick cost is the
     maul's, 2. The adrenaline cost is paid first: 24 → 0 quarters.
   - The arc is front, and the Hobgoblin holds no block.
   - The damage is `⌊27 × table(60 − 70) / 2^16⌋ = ⌊27 × 55,109 / 65,536⌋ = 22`, so 400 → 378.
   - On the target side, the Hobgoblin is knocked down. The knock-down is applied in the action
     phase, so t₀ = 52 and D = 53 (with *Hob-breaker*'s 3 pieces it would be +1 flat: D = 54).
   - **The knock-down interrupts** the activation (§5.7, design/14): the activation is cleared, the
     Hobgoblin's energy stays spent, and its recharge counts from t₀ = 52.
   - On the source side, the adventurer gains +1 strike (4 quarters) and the Hobgoblin +¼ strike
     (it is still alive).
3. **Tick 52.** Step 1: nothing, because the activation is gone. Step 2: the Hobgoblin is knocked
   down (52 ≤ 53) and does not act.
4. **Tick 53.** Step 1: nothing, which is the tick the smash would have landed. Step 2: the
   Hobgoblin is still knocked down (53 ≤ 53).
5. **Tick 54.** The Hobgoblin acts again (54 > 53), and its smash is on recharge.

The reverse case is a goblin knocking down the adventurer during a 3-tick spell. Under §5.7 the
spell's energy stays paid, the spell goes on recharge and has no effect. Whether the rest of the
adventurer's action's ticks still run is FX-3 (recommended: yes). The adventurer's next action
phases are Wait only while knocked down (FX-7). Because a knock-down applied in step 2 of tick T
lasts until the end of tick T + d − 1, the adventurer loses d − 1 action phases, plus the rest of
tick T.

### Worked example 3: a condition refreshed while ticking
The adventurer has health regeneration 0 and is Poisoned with D = 72, from earlier. **Goblin 17**
(a Skirmisher) hits it in **step 2 of tick 70** with a Bleeding of 8 ticks, so t₀ = 70 and D = 77.

- **Ticks 70–72**, step 3: −3 (Bleeding) − 4 (Poison) = −7 pips → −14 health a tick. This
  includes tick 70, the tick of application: the bleed was applied in step 2, before step 3.
- **Ticks 73 and later**: Poison has ended (73 > 72), so −3 pips → −6 health a tick.
- **Step 2 of tick 74**: goblin 17 applies Bleeding 8 again, D_new = 74 + 8 − 1 = 81.
  - With FX-6's recommendation, `max(77, 81)` gives D = 81. The replace reading also gives 81.
  - In tick 74, step 3 degenerates **once** (−6), not twice: the same condition does not stack.
- **Variant** where the reapplication at tick 74 is a Bleeding of 2 (D_new = 75): `max` keeps 77,
  but the replace reading shortens it to 75. That is two fewer ticks of −6, and FX-6 settles which
  one is right.
- **Action phase, clock 75**: the adventurer casts Field Dressing (5 / 1 / 15), which resolves in
  step 1 of tick 76. Its Heal is capped at max health. Its Cure gives Bleeding a duration of 0, so
  D = 76 − 1 = 75, and step 3 of tick 76 no longer finds it active (76 > 75).
- **Result under the recommendation**: 3 ticks at −14 (70, 71, 72), then 3 ticks at −6 (73, 74,
  75). The cure then stops the bleed, which would otherwise have run to tick 81.

## Deviations from the brief
- The brief lists "the five conditions" (ENG-01's words and design/09's MVP). design/04 names nine.
  The catalogue holds all nine: the five MVP ones with their storage, and four post-MVP ones marked
  **P** whose storage is FX-22.
- The brief points at design/17 for "the Rift Heart, burning and poisoned". design/17 names no
  effect of its own: the Heart is a caste (Skirmisher, Shaman or Hobgoblin in the MVP grades) acting
  through its skills, and "poisoned" appears only in a quest's name (design/14, *The poisoned
  well*). Mining's interrupt by a hit is design/17's only rule of this kind, and it is covered
  (§5.4, §5.7).
- I added no glossary term to CONTEXT §5. Terms the document introduces are listed below, for the
  project manager.

## Escalations
Each item gives the question, the options, and the recommendation (**R**). The cost in slots is
given where a record changes. A decision on FX-1, FX-2, FX-5 or FX-6 changes the results of the
examples above, and will change the shared test vectors once they exist.

**FX-0: the ⟨C⟩ conventions.** These are ordering choices the documents do not make, all needed for
determinism:
- area targets are taken at resolution, in ascending tile index, target-major;
- costs are paid when an action or activation starts; a glyph is consumed at the next spell's start;
- facing toward a non-adjacent target is the direction of the hex line's first step;
- life steal is bounded by the target's remaining health;
- target-side on-hit effects apply only to a living target, while source-side ones apply to any hit;
- a goblin that resolves an activation in step 1 does not act in step 2;
- a skill whose target became illegal at resolution does nothing, and its costs stay paid;
- remains do not block movement;
- a frozen goblin's condition expires by the clock without ticking;
- ranks above 12 (from runes) are capped at 12 for scaling.

**R:** accept as written. The main alternative is effect-major areas (each entry applied to all
targets before the next entry), which only changes the source's counters' order.

**FX-1: when an activation resolves.** design/02 puts it in step 1 of a tick, while design/04 says
"at the end of the n-th tick".
- (a) Step 1 of the n-th tick. Goblins get n − 1 chances to interrupt an adventurer's n-tick spell,
  so a 1-tick spell cannot be interrupted by goblins.
- (b) After step 3 of the n-th tick. Goblins get n chances, but this contradicts design/02's order.

The Hobgoblin's "three actions" hold under both. **R: (a)**, design/02's pipeline, on which CBT-02
is built; design/04's sentence is then reworded.

**FX-2: when a recharge starts.**
- (a) When the activation ends (resolution or interruption; GW1's baseline).
- (b) At use.

**R: (a)**, counted by step 4 from the tick where it ends, that tick included.

**FX-3: the adventurer interrupted mid-action.** When a goblin interrupts the adventurer's n-tick
skill at tick k:
- (a) The remaining n − k ticks still run. The tick cost and weight stay what the client counted.
- (b) The action ends after tick k. The player acts sooner, but the ticks an action runs become
  variable.

**R: (a).**

**FX-4: an interrupted adrenaline skill.** Its adrenaline is either (a) spent or (b) refunded.
design/04 only says "pays its energy". **R: (a)**, symmetric with energy.

**FX-5: attack skills.** design/03 gives Aimed Shot activation 1 with a bow of 2 ticks, and gives
Cleave and Rending Cut "–".
- For the tick cost the options are (a) the activation, (b) max(weapon, activation), (c) the sum.
- For the landing: at once (like a weapon attack) or at resolution.

**R:** (b); "–" is stored as 0 and means the weapon's ticks. The skill lands at once without an
activation and at resolution with one: the Hobgoblin's wind-up is an attack skill with activation
3, which must be interruptible.

**FX-6: refresh.** Reapplying a condition or a timed effect can (a) set `D = max(old, new)` or (b)
replace the deadline. **R: (a)**: a weaker reapplication never helps the holder.

**FX-7: knocked down.**
- What may the knocked-down adventurer do? "Acting while knocked down" is invalid (design/02), but
  if every action is invalid the instance can never advance. Options: (a) Wait is the only legal
  action; (b) the knock-down's ticks run automatically inside the action that caused it (this
  changes the weight).
- Can a knocked-down actor block? This is unsettled. The critical already applies from any arc.

**R:** (a) Wait only; a knocked-down actor cannot block.

**FX-8: the adventurer at 0 health mid-tick.**
- (a) Defeated at once: the tick stops in the action phase and in steps 1–2, while step 3 completes
  for every actor first.
- (b) The tick completes and step 5 checks.

Under (b), regeneration in step 3 could raise the adventurer from 0. **R: (a)** as in §5.8. Health
at 0 is never raised again.

**FX-9: penetration's unit.** design/04's formula subtracts a flat penetration, but every numbered
source is a percent: Static Lash 25 %, the modifier +2…+4 %. Warcry's and Might's units are not
stated, and `MemberStats.penetration` is one `u8`. Options: (a) percent of the armor after bonuses,
summed and capped at 100; (b) flat; (c) both, in a fixed order. **R: (a)**, and design/04's formula
is amended once decided.

**FX-10: what a hit is.** It matters for adrenaline taken, mining's interrupt and Dazed. **R:** an
attack or damaging entry that reaches its target unblocked, unevaded and not missed, whatever its
damage (0 included). Degeneration, life steal and trap entries are not hits. Alternative: only
weapon attacks are hits.

**FX-11: flank and evasion.** design/04 says flank ignores "blocks and stances that block", but
Sidestep evades. Options: (a) evasion is ignored from the rear-side and back, like a block; (b)
evasion holds from every arc. **R: (a)**; otherwise Sidestep dominates Brace against flankers.

**FX-12: adrenaline.** There is one pool (`MemberState.adrenaline`, quarter strikes, `u16`; a goblin
has 8 bits), but no cap and no definition of "out of combat". **R:**
- the cap is the highest adrenaline cost on the bar (the caste's, for a goblin);
- "out of combat" means no goblin is engaged with that member;
- the decay rate is BAL-01's.

**FX-13: effect slots full.** A member has 4 slots and a goblin 1 (ENG-01). When a new effect
arrives and every slot is taken, it can (a) replace the one with the earliest deadline, (b) fail, or
(c) replace the oldest applied. **R: (a)**. For a goblin this means a new effect always replaces its
one effect. The same skill always refreshes its own slot.

**FX-14: traps.** design/18 does not say what a terrain trap does, how long a placed trap lasts,
whether it triggers once, or what happens when the chunk already holds 3 objects (ENG-01 E-3).
**R:**
- a trap feature's object `param` holds a `SKILL` id, at a rank from the location's level band;
- a placed trap's `param` holds its placer (1 bit member/goblin, then a member 0–7 and bar slot 0–7,
  or a goblin id of 12 bits and caste skill 0–3: 15 bits);
- a trap lasts until triggered or until the instance closes, and triggers once;
- placing on a full chunk, an occupied tile or a wall is invalid.

Cost: 0 slots.

**FX-15: a crippled goblin.** Goblins choose each tick, so "2 ticks per tile" needs a rule. **R:** a
crippled goblin that moves skips its next act, using a flag in `GoblinState.flags`. Cost: 0 slots.

**FX-16: Rime Shard.** Its "moves 1 tile per 2 ticks for 2…5 ticks" is exactly Crippled. **R:** it
applies Crippled, rather than adding a new kind. design/03 would then be amended.

**FX-17: Second Wind's "more if below 50 % health".** **R:** a second `HEAL` entry guarded by
`HOLDER_BELOW_HALF`, tested before the first heal applies. Its value is CNT-01's and BAL-01's.

**FX-18: potions.**
- "+movement": options are (a) moves cost 1 tick even when crippled, (b) two tiles a move, like the
  Wolf rider. **R: (a)**; (b) breaks the flood's one-step assumption.
- Revive: triggered automatically when health would reach 0, using the belt's first revive potion,
  to a fixed share of max health. **R:** post-MVP, designed with that rule.
- Reveal the floor conflicts with "≤ 3 chunks revealed by one action" and with the weight. **R:**
  post-MVP, and not before ENG-07's measurements.
- A bomb's target: the `Item` action carries an entity only (`actions.cairo`). Options: (a) add a
  tile flag like `Skill`'s (bit 21 is free; 0 slots, a wire-format change); (b) a bomb targets an
  entity and the area is centred on its tile. **R: (a)**.

**FX-19: *Hob-breaker*'s "the first attack that would bring you under 50 % is halved".** It could
be (a) applied after D-140's summed percents, on the final damage (`⌊damage / 2⌋`), or (b) −50 %
inside the sum, which would need the sum computed twice to know whether the attack "would bring"
the holder under 50 %. **R: (a)**. The "used" flag goes in `MemberState.flags`.

**FX-20: castes and summons not designed enough.**
- Shaman "shields": **R** an `ARMOR` enchantment on an ally, reusing kind 10.
- Paladin "protects the lord" and Beguiler "illusions": no rule exists. They wait for their design
  (post-MVP), and nothing is catalogued.
- Summons (Lord, Gravecaller): entity ids `8 + 16 × chunk + k` have no room for a summoned actor.
  This needs an id range and a record, with at least 2 slots per summon (a goblin record). Post-MVP.
- Wolf rider "moves 2 tiles per tick": a caste movement field, with its effect on the flood.
  Post-MVP.

**FX-21: areas of radius 2 and 3** ("nearby", "in the area"). No MVP source uses them. ENG-01 §9.2
bounds "goblins changed by the adventurer's action beyond the 8 awake" at **6**, from the
adjacent-foes shape. Radius 2 or 3 moves that bound to 18 or 36 goblins; 30 more goblins is 60
more words, about 1.9 M L2 gas at O a tick. Line of sight from an area's centre is also unsettled.
**R:** MVP content may not use them (the content pipeline refuses them); when a source needs one,
ENG-01's bound is re-measured and line of sight is decided (recommended: needed from the centre).
The Lord's shout to allies within 8 is the same question.

**FX-22: storage of the four post-MVP conditions.** `MemberTimers` has 26 free bits and
`GoblinTimers` 10, not enough for 4 × 28-bit deadlines. Options:
- (a) one more word per member (+1 slot; the per-tick member words go 4 → 5, +1 O) and per goblin
  (+1 slot; up to 16 more goblin words a batch, about +0.51 M L2 gas at O);
- (b) hold them in effect slots, which then compete with stances and enchantments (0 slots);
- (c) 16-bit offsets from the clock.

**R: (b)** for the post-MVP start, re-measured when the Beguiler or Hexer ships.

**FX-23: damage types.**
- Shadow and holy are neither physical nor elemental in `MemberStats`. **R:** they take neither
  class bonus (post-MVP, Gravecaller and Cleric).
- design/15's "armor against a damage type" is per type, but the snapshot keeps two aggregates.
  **R:** 3 (type, value) pairs of 12 bits in `MemberStats` bits 200–235 (0 slots); a fourth
  distinct type is refused by `set_build`.

**FX-24: additions to ENG-01's records.** All are within existing words, **0 new slots**, unless
noted.

| Record | Needs | Room | Cost |
|---|---|---|---|
| `SKILL` (2 parts) | per entry: `param`, a duration at rank 0 and 12, `shape`, `guard`, `target` (3 entries × about 80 bits); the skill's "weapon ticks" sentinel (FX-5) | 500 bits in 2 parts | 0 |
| `ITEM` | the potion effect as one entry (kind, param, value, duration, shape, target) | 1 part, about 100 bits free | 0 |
| `MODIFIER` | passive id, value range, guard, condition id (for 50) | 1 part | 0 |
| `MemberEffects` | a "source is a belt slot" bit, so a potion's timed effect names its potion (the entry holds a skill `u16`) | the 4 unused bits of each 32-bit deadline (28 used) | 0 |
| `MemberKit` | the condition named by the duration modifier; armor while in a stance or enchanted (2 × `u8`); set bonus ids | bits 208–249 | 0 |
| `MemberStats` | armor against up to 3 types (FX-23) | bits 200–249 | 0 |
| `MemberState.flags` | the set bonus's "used", the crippled-move flag | flags 160–167 | 0 |
| `GoblinTimers` | charges for its effect (a goblin `BLOCK`) | bits 240–249 | 0 |
| `GoblinState.flags` | crippled moved last tick (FX-15) | flags 120–127 | 0 |
| chunk object `param` | a placed trap's placer (FX-14) | 16 bits | 0 |
| `Action::Item` | a tile target (FX-18) | bit 21 of 24 | 0; wire format |
| Post-MVP conditions | FX-22 | — | 0 (b) or +1 slot per member and goblin (a) |
| Summons | FX-20 | — | ≥ 2 slots per summon, and an id range |
| Areas of radius 2–3 | FX-21 | — | per-tick bound 6 → 36 goblins |

**Glossary (CONTEXT §5), proposed for the project manager:**
- **Effect**: one entry of a carrier, of a kind from design/19.
- **Carrier**: what holds effects (skill, potion, modifier, set bonus, trap).
- **Holder**: the actor an effect stays on.
- **Hit**: FX-10.
- **Action phase**: between two ticks, where the adventurer's action is applied.

## Open questions
- The values design/19 leaves open are balance values, not rules: Brace's, Venom Coat's and Deep
  Draw's durations, Warcry's and Stone Skin's amounts, Second Wind's extra heal, adrenaline decay,
  the MVP's six trainer skills per profession, the Warden and Arcanist armor sets' bonuses. They
  are CNT-01's, DES-06's and BAL-01's. Any of them that needs a kind outside §3 and §4 is an
  amendment of design/19 first.
- Audit: `[GPT-6-Astra]`, design lens (the order's determinism, completeness, consistency).

---

# Fix loop 1 — `[Opus 5.5]`, after the `[GPT-6-Astra]` audit (FAIL, 12 majors, 1 minor, at `69e49b6`)

## Summary
- **What was done.** `origin/main` was merged first (`d78524d`; none of its changes touches
  design/19 or the files design/19 reads). design/19 was then rewritten as **v0.2**, and the
  cross-references were updated.
- **Pushed.** Commit `28f944c`. **CI is green at 28f944c**: every check passed, watched with
  `gh pr checks 139 --watch` to completion.
- **Section numbers moved.** The sections cited in the report above are v0.1's; v0.2's are:
  - §2 the entry;
  - §5.2 the awake set;
  - §5.4 hit classes;
  - §5.7 refresh;
  - §5.10 mining;
  - §5.11 traps;
  - §5.12 counters;
  - §7.2 the inventory;
  - §9 the grouped escalations;
  - §10 the worked examples, which now live in the document.
- **Recommendations changed after the audit's view:** FX-10, FX-11, FX-22, FX-23, FX-0b. Each
  change is given below.

## Findings and where they are fixed
| # | Finding | Fixed in design/19 v0.2 |
|---|---|---|
| F-1 | Enumerations incomplete: the kind `Skill`, the Seal of Capture | §3.4 **skill kinds** 1–12 with the generic `Skill` (11, rules FX-25) and the Seal of Capture (12); effect kind 23 `CAPTURE` (§3.6, FX-26); §7.1 lists every enumeration CBT-01 freezes (effect and passive kinds, conditions, damage types, skill kinds, shapes, targets, filters, guards, scopes, hit classes, object kinds); §8 has Second Wind and Field Dressing as `Skill` and a Seal of Capture row |
| F-2 | The entry cannot express the catalogue | §2.1: a 98-bit entry, field by field. `v0`/`v12` are signed `i16`. Durations and **charges** are their own fields. `scope` and `filter` are added. Entries with **two durations** have an explicit rule: the condition's duration is the value, the holding duration is `d`. Legal combinations are the "reads" column of §3, and the writer refuses the rest. §2.2: scaling in `i32` with truncation toward zero, and bounds. §4: **one passive id, one statistic** (43 split into 43/44); `MODIFIER` = a benefit and a cost (compound modifiers), with the rolled byte the benefit's. §7.2 shows the packings |
| F-3 | Weapon-only rules applied to spells | §5.4 **hit classes** `WEAPON`, `SPELL`, `ITEM`, `TRAP`, with a table of which rule applies to which: strength, arcs and critical, block and evade, Weakness, scoped percents and penetration (Might `ATTACK_SKILL`), adrenaline, energy and life steal on hit, counters, on-attack conditions, the set bonus. §5.5 is the pipeline gated by class at each step |
| F-4 | Guards: time and subject in conflict | §2.4: the **subject** is the holder of the carrier (the defender for an armor passive, the attacker for a damage passive, the source for a skill or potion). The **time**: all the guards of one carrier are evaluated once, before its first entry. Second Wind is worked there (200/480: the bonus applies) |
| F-5 | Refresh and replacement: no total order, no potency rule | §5.7: **identity** by carrier (skill id or belt potion), not caster. One rule in four ordered cases: same carrier → keep the application with the later deadline whole (rank, charges, deadline), the new one on a tie (FX-30); a stance replaces a stance; lowest free slot; eviction by earliest deadline, ties lowest slot (FX-13). A slot stores the source's rank, so the caster's death changes nothing (§7.2). Example §10.4: equal deadlines, and a stance replacing a stance |
| F-6 | The activation lifecycle under the awake-set limit | §5.2: the awake set is taken once at step 0, fixed for the tick, **not refilled** by deaths; alerted goblins join next tick; only awake goblins resolve, act and regenerate. A goblin not awake at its deadline: **FX-29** (new). **Busy goblins** (activating or recovering) do nothing in step 2. A member's activation lies inside its action. Example §10.5 |
| F-7 | Mining treated as an activation | §5.10: `mine` as ENG-01 §4.1 froze it. Three ticks, each fully run. A hit at any point of tick `k` sets a flag, checked **after step 5 of tick `k`**: a hit stops the action there (no further tick). Three ticks without a hit complete it. It is not a skill: no cost, recharge, FX-3 or FX-4. §5.9 says mining is not an activation |
| F-8 | Traps outside the resolution order | §5.11: placing (tile legality, object slot reuse by lowest index empty or used), two object kinds (terrain 4, placed 9) with their `param` encodings (§7.2). **Triggering** comes right after the entering move (action phase or the goblin's step-2 act). The allegiance: placed traps hit the placer's foes; terrain traps FX-34. The source and strength: placer, dead placer's record, terrain FX-28. Entries as class `TRAP`; the object marked used; the move's cost unaffected; death |
| F-9 | Bombs under-specified, the area bound exceeded | §2.3 separates **addressing** (`target`: where the shape is centred) from the **filter** (`FOES`/`ALLIES`). **Clipping** is stated: tiles outside the window are skipped, and the false §6 claim is removed. Counts corrected: `DISC_1` 7, `DISC_2` 19, `DISC_3` 37. The bound: **FX-35** (new: 7 against ENG-01's 6), FX-21 recomputed (19/37). Bomb range and line of sight: FX-18 |
| F-10 | Counters and decay not executable | §5.12: `hits` and `casts` start at 0, have their increment points and pre-reset tests, stay below `N ≤ 255` (never wrap), and stay 0 when `N = 0`. A quick-cast bonus is spent at the spell's start, interrupted or not (FX-39). Adrenaline gains, spending and caps are saturating. **Decay** is a phase: §5.8 step 3.3, after the tick's gains (FX-12) |
| F-11 | FX-24's inventory incomplete | §7.2: **a field-by-field inventory against ENG-01 §3.2**, with free bits and packings. Covered: the effect slot's **rank** and potion flag in the deadline's 4 unused bits; the goblin effect's charges and rank in bits 240–249; the goblin's energy **in thirds**; the kit's quick-cast attribute and the other kit fields (39 of 42 free bits); armor per type (FX-23); trap `param`; the `SKILL`, `ITEM`, `MODIFIER` and `CASTE` layouts; revive's expedition state (post-MVP). **Registry reads** are counted: 32 at worst with the MVP's 5 castes, exactly `MAX_READ` (for ENG-07). The MVP fits in 0 new slots; the post-MVP slot costs are listed |
| F-12 | Unsettled rules presented as inherited | Knocked down's refresh → **FX-31**; the Hexer's trigger → **FX-32** (kind 21 is now a placeholder, not a behaviour); discs with their centre versus design/04's 18/36 → **FX-33** |
| F-13 | Examples overstate | §5.1 and design/04 say **three ticks**, and when those are three actions. §10.1 gives facings, the kit and the awake-set assumptions; §10.2 gives the smash's recharge (10 → usable from tick 62) and notes that two actions used the three ticks. New §10.4 (equal-deadline eviction), §10.5 (a frozen activation), §10.6 (a fifth cast interrupted). Each example states its assumptions |

Cross-references:
- design/04: the order of one hit and the hit classes → §5.4–§5.5; refresh → §5.7 with FX-31;
  interrupts → §5.9, with mining → §5.10; "exactly three actions" corrected to three ticks.
- design/05: the caste sheet → §7.3.

## Escalations added or changed
§9 of design/19 groups them (A time and activation, B hits, C held effects, D counters, E areas and
traps, F content shape, G storage) and marks **★ those CBT-01 needs first**: FX-0, 1, 2, 3, 5, 6, 8,
9, 12, 13, 14, 15, 18, 22, 23, 24, 25, 27, 28, 29, 30, 31, 35. The recommendation for each is in §9;
the added and changed ones follow, with the auditor's view where it gave one.

**Changed**
- **FX-0**: the rank beyond 12 is now split out as **FX-0b**.
  - Options: (a) cap the rank at 12; (b) extrapolate the line up to 15, the snapshot's 4 bits.
  - **R changed to (b)**, the auditor's view ("preserve a bounded benefit from runes above 12"),
    which is also the baseline's.
  - Area tile order is now stated as the one exception to X-7 (the auditor's view).
- **FX-10**: **R changed**: damaging trap entries are hits too. Auditor: "otherwise trap damage
  bypasses mining's 'any hit' interrupt".
- **FX-11**: **R changed to (b)**, evasion holds from every arc. Auditor: design/04's flank rule
  names blocks only, and a melee-only evasion does not dominate Brace against ranged attacks.
- **FX-7**: adds that a knocked-down actor neither blocks **nor evades** (the auditor asked that it
  be settled).
- **FX-12**: now executable.
  - Recommendation:
    - the cap is the highest cost on the bar or the caste, 0 if none;
    - out of combat, for a member: no goblin in the tick's awake set is Engaged; for a goblin: it
      is not Engaged;
    - decay runs in step 3 after the tick's gains;
    - the rate is a code constant `ADRENALINE_DECAY` until BAL-01.
  - Options for the rate's home: a code constant, or a registry record (none exists for globals).
  - Auditor: agrees provisionally and asked for empty bars, goblins, storage and phase, all now
    defined.
- **FX-13**: ties by lowest slot index (auditor); a goblin's single slot is replaced. Options for
  the goblin: (a) the new effect replaces its effect; (b) the effect with the later deadline stays.
  R (a).
- **FX-15**: generalised to **any goblin act costing `k > 1` ticks** (a 2-tick bow or maul, a
  crippled move). Goblins act once per tick, so without this a bow goblin shoots every tick.
  - Options: (a) the goblin skips its next `k − 1` acts (recovery stored as activation slot 254
    with a deadline); (b) the act starts as an activation of `k` ticks and lands at the end; (c)
    goblins ignore tick costs.
  - **R (a)**, with the auditor's point: the recovery survives the condition's end.
- **FX-18**: bombs now need a **range** (8 bits in `ITEM`) and **line of sight to the target tile**
  (a thrown potion is ranged, design/04). Revive's once-per-expedition state is listed in §7.2 as
  post-MVP (auditor).
- **FX-19**: R (a), with the exact predicate `2h ≥ max ∧ 2(h − damage) < max`, applied to weapon
  hits only ("the first attack"). The flag is spent only when it triggers (auditor).
- **FX-21**: counts corrected to 19 and 37 goblins.
- **FX-22**: **R changed to (a)**, one more word per member and per goblin when the four conditions
  ship. Auditor: effect slots would change stacking and dispel behaviour.
- **FX-23**: **R changed**.
  - Options: (a) at most 3 (type, value) pairs, with a fourth type refused by `set_build`;
    (b) 9 × 6 bits, a value per type saturating at 63, replacing the two aggregates (0 slots, §7.2).
  - **R (b)**. The auditor rejected (a) as an arbitrary build limit.
- **FX-24**: rewritten as §7.2's inventory. The auditor did not approve v0.1's; v0.2 gives the
  packings.

**Added**
- **FX-25 ★ The generic `Skill` kind.** design/03's starter tables use it (Second Wind, Field
  Dressing); its kinds table does not define it.
  - Options: (a) interruptible like a spell, but not a spell for Dazed, glyphs or quick cast;
    (b) a spell in every respect; (c) not interruptible.
  - **R (a)**: the baseline's generic skills are interruptible, and design/03 keeps "spell" as its
    own kind.
- **FX-26 The Seal of Capture** (post-MVP). It targets the remains of a boss that used an elite
  skill; the seal is replaced by the skill, an exception to the bar locked during an expedition.
  - Options: (a) a standalone action on remains, like `loot`: 0 ticks, no draw. Its result
    (the skill learnt) is reported to `Hub`, and the persistent build's slot changes; the instance's
    snapshot keeps the seal until the next entry. (b) The instance's bar changes at once, which
    breaks the snapshot's "fixed at entry".
  - **R (a)**.
- **FX-27 ★ Arcs for spells; scopes.** design/04's criticals come from "position and state" in a
  section about attacks.
  - Options: (a) arcs and criticals apply to weapon hits only; (b) to spells too.
  - For Warcry's "+armor penetration" and the damage percents (an inscription is on "everything
    held", foci included), the options are `WEAPON` or `ALL`.
  - **R (a)**, with Warcry `WEAPON`; each modifier's scope is written in its `MODIFIER` record, with
    `WEAPON` as the default.
- **FX-28 ★ The strength of a bomb and a trap.** design/04 defines only a weapon's and a spell's.
  - Options: (a) `3 × level` of the source, as a spell; a terrain trap uses its location's minimum
    level; (b) strength 0 (only armor mitigates); (c) the potion's or trap's own value.
  - **R (a)**.
- **FX-29 ★ A goblin's activation while it is not awake at its deadline.**
  - Options: (a) cancelled as an interrupt in step 1 of its deadline tick; (b) it resolves at its
    next awake step 1, with its target re-checked (the deadline overdue); (c) an activating goblin
    has priority in the awake set.
  - (c) breaks "the nearest 8" and its ordering; (b) keeps an overdue state alive indefinitely.
  - **R (a)**: no deadline is ever overdue, and walking away is a legitimate answer to a wind-up.
- **FX-30 ★ Potency on refresh.**
  - Options: (a) the application with the later deadline is kept whole, the new one on a tie;
    (b) the new one always replaces rank and charges, with `max` deadline; (c) the strongest rank
    with the longest deadline, combined.
  - **R (a)**: one comparison, and no strength and duration taken from two different casts. The
    auditor asked for potency and charges to be specified beside the deadline.
- **FX-31 ★ Knocked down reapplied while held.** design/04 says conditions refresh; its knock-down
  row says "does not stack with itself".
  - Options: (a) nothing happens; (b) it refreshes like any condition.
  - **R (a)**: the knock-down row states a separate rule, and (b) allows endless knock-down chains.
- **FX-32 The Hexer's "punishes skill spam"** (post-MVP). Options: damage or energy loss to the
  holder at each skill start, at each skill resolution, or above a count of skills in a window of
  ticks. **R: none yet**; DES-06 designs it, and kind 21 stays a placeholder.
- **FX-33 design/04's 18 and 36 tiles.**
  - Options: (a) for an area centred on a target, a disc with its centre (19, 37); (b) the ring
    without its centre, where the target itself would be spared.
  - **R (a)**; `RING_1` stays for "adjacent foes" around the source.
- **FX-34 Terrain traps' allegiance.** Options: (a) they trigger on members only; (b) on any actor.
  **R (a)**: a lair's traps are the goblins' own, and (b) would make the AI's paths depend on traps.
- **FX-35 ★ A bomb's `DISC_1` and ENG-01 §9.2's bound.** Up to 7 goblins outside the awake 8,
  against 6 budgeted.
  - Options: (a) raise the bound to 7: +2 goblin words in the worst tick, 64,144 L2 gas at O
    (32,072), the per-invocation cap of 16 unchanged; (b) bombs limited to `SINGLE`; (c) a bomb
    takes at most 6 actors, the 6 lowest tile indexes.
  - **R (a)**.
- **FX-39 The quick-cast bonus.**
  - Options: (a) the `N`-th spell of the attribute with activation ≥ 1, counted at its start, the
    bonus spent even if interrupted; (b) counted at resolution, so an interrupted spell does not
    count; (c) instant spells count too, with no effect.
  - **R (a)**.

FX-36 to FX-38 are not used: the questions drafted under those numbers (adrenaline decay, a
goblin's single slot, the goblin's weapon speed) were folded into FX-12, FX-13 and FX-15.

**Unchanged:** FX-1 to FX-6, FX-8, FX-9, FX-14, FX-16, FX-17, FX-20. The auditor agreed with each
recommendation, adding the precisions now written: FX-1's "three ticks", FX-5's distinction
between zero-activation attacks and instant skills, FX-6's potency (FX-30), and FX-8's step-5
finalisation.

## Commands run (fix loop 1)
- `git fetch origin && git merge --no-edit origin/main` → `d78524d` (12 files of main: CONTEXT,
  PLAN, decisions, reports, status; none of design/19's sources).
- Read: the audit in full; ENG-01 §4.1 (the standalone actions, `mine`'s row).
- `git commit`, `git push` → `28f944c`; `gh pr checks 139 --watch --interval 30` → every check
  `pass` (cairo contracts and the 8 spike packages, client, discover, tooling).

## Acceptance criteria after fix loop 1
- **AC-1**: enumerations complete (§7.1), coverage with the Seal of Capture and `Skill` (§8).
- **AC-2**: the order is total, including the awake set, busy actors, traps, mining and counters;
  six worked examples in §10.
- **AC-3**: the edges table is updated (§6).
- **AC-4**: the inventory of §7.2 gives every field with its bits and slots.
- **AC-5**: FX-25 to FX-39 are added for the rules the fixes needed; none is decided in the text.

---

# Fix loop 2 — `[Opus 5.5]`, after the `[GPT-6-Astra]` re-audit (FAIL at `28f944c`)

## Summary
- **Merge.** `origin/main` was merged first. Its changes (client art tools, the indexer, decisions)
  touch neither design/19 nor what it reads: `git diff 28f944c HEAD -- docs/design
  docs/architecture contracts/logic` is empty.
- **The document.** design/19 is rewritten as **v0.3**. The re-audit's own examples check still
  holds (§10.1–§10.6 keep their numbers), and §10.7 and §10.8 are added.
- **Pushed.** Commit **`bd3f35e`**. **CI is green at bd3f35e**: every check passed, watched with
  `gh pr checks 139 --watch` to completion, including the new `indexer/emitter` and `indexer-node`
  jobs from main.
- **Main result.** A lossless snapshot of the MVP's passives does **not** fit ENG-01's frozen words:
  it needs **one more member word** (+1 slot per member), recommended under FX-24, now changed.
- **Also.** Registry reads reach **38 + T records**, above `MAX_READ` = 32, which is the new FX-46.

## Findings and where they are fixed
| # | Re-audit status | Fixed in v0.3 |
|---|---|---|
| F-1, F-3, F-5, F-7, F-8, F-9, F-10, F-13 | resolved | kept; F-5's potion identity moved to FX-42 (F-12), charge lifetime is F-14 |
| **F-2** | open | §2.1: the entry recounted, **97 bits**, total shown in the table. Charges 6 bits (0–63), shape 3, filter 1, guard 3. **Empty entry** = kind 0, all fields 0, packed without gaps, the count being the last non-empty index. **A duration carried as a value** (`CONDITION`, `ON_ATTACK_CONDITION`) is bounded to **1…32,767**, the signed field's range, and the pipeline refuses more (it was 43,688, which does not fit `i16`). `ITEM`: 72 low + **113** high (entry 97 + range 8 + bomb strength 8). §7.2 shows every total |
| **F-4** | partial | §2.4: **one guard snapshot per carrier's execution**, taken before anything applies and held for every actor and entry. The false invariant ("the source does not change") is removed; it is now FX-40. §10.7 is a threshold-crossing example with life steal: the source goes from 230 to 250 then 270 on 480, and the second target is still damaged |
| **F-6** | partial | §5.2. **Perception** (design/18's table) runs at step 0 **before** the awake-set selection (FX-41). **Lapsed activations** of goblins not awake at `A` are applied **lazily**, as the auditor proposed: nothing is written while frozen; at the goblin's next awake step 1 the activation is cleared and its recharge dated from `A`, in the write of that goblin's record, which the awake bound already counts. So there is no scan and no extra write, and it covers leaving the window too (§10.5, bounded). **The activation field** has three states: none 255, activating 0–3, recovering 254. The transition table includes an attack skill's `k − n` recovery after resolution, and a pending activation is never discarded by a recovery |
| **F-11** | open | §7.2, a **lossless** inventory. (a) **Rank 0–15** in the effect slot's 4 spare bits; the potion flag moved to bit 15 of the skill field (skill ids ≤ 32,767). (b) **Damage percents** stored per guard × class (6 sums of `i8`) and **penetration** per class (3 × `u8`), with the range argument (7 passives × 18 ≤ 127). (c) **Two quick-cast pairs** and a second counter `casts_2`. (d) **Caste health regeneration** added to the caste sheet (§7.3), with the weapon inline. (e) The arithmetic shows that ENG-01's kit cannot hold it: 171 > 122, over by 49, so **one more member word** (`MemberMods`), with its cost |
| **F-12** | partial | New FX-40 (area guard sampling), FX-41 (perception and fixed membership), FX-42 (potion identity by **item**, not belt slot: two slots with the same potion are one carrier). The ★ criterion is now stated ("changes a field, an enumeration, a legal combination, or a step or order of §5's functions") and applied to every escalation; **FX-39 is ★** |
| **F-14** | new | §3.4: charge-only effects store **`MAX_CLOCK`** as their deadline. The clock never reaches it, because an action runs only while `clock ≤ LAST_TICK = MAX_CLOCK − 65,545` and runs at most `MAX_DURATION` ticks, so they have no time expiry. §5.5 step 8: **a charge is spent on every weapon hit landed, the target dead or not**; step 7 applies the condition only to a living target. §10.8 is a killing blow spending the last charge |
| **F-15** | new | **§5.14, one executor.** The hit pipeline resolves one hit and no longer iterates entries (the old step 6 is gone). The executor does: guards once; hit modifiers pre-read; per-entry target sets taken at once; the actor list as their union in tile order; per actor, the entries whose set holds it, in entry order. A stopped hit skips the carrier's remaining entries on that actor; non-hit entries apply only to the living. **Legal carriers** (FX-45): at most one hit and at most one holding entry per carrier, hit modifiers only with a hit, attack skills' entries `FOE SINGLE`, `TRAP` first. So two `DAMAGE` entries or two holding entries cannot exist |
| **F-16** | new | §7.2: **the request union** deduplicated per invocation, counted below. It includes the `CASTE` records, and removes the `BASE` reads by putting the caste's weapon inline. `LOCATION` and terrain-trap skills are counted. **38 + T > 32** → FX-46. FX-29 adds no read |

## The arithmetic
**The entry** (§2.1). 97 bits: fits a 122-bit high limb.

| Field | Bits |
|---|---:|
| kind | 8 |
| param | 8 |
| v0 | 16 |
| v12 | 16 |
| d0 | 16 |
| d12 | 16 |
| charges | 6 |
| target | 2 |
| shape | 3 |
| filter | 1 |
| guard | 3 |
| scope | 2 |
| **Total** | **97** |

**`SKILL`** (2 parts, as ENG-01): 0 extra slots.
- The header takes part 0's low limb, 83 ≤ 128:

  | Field | Bits |
  |---|---:|
  | profession | 8 |
  | attribute | 8 |
  | skill kind | 8 |
  | elite | 1 |
  | energy | 8 |
  | adrenaline | 8 |
  | activation | 16 |
  | recharge | 16 |
  | range | 8 |
  | target | 2 |
  | **Total** | **83** |

- The three entries take part 0 high (97 ≤ 122), part 1 low (97 ≤ 128) and part 1 high (97 ≤ 122).

**`ITEM`** (1 part): 0 extra slots.

| Limb | Fields | Bits |
|---|---|---:|
| low | class 8 + region 16 + rarity 8 + value 32 + book index 8 | 72 ≤ 128 |
| high | entry 97 + range 8 + bomb strength 8 | 113 ≤ 122 |

**`MODIFIER`** (1 part): 0 extra slots.
- One passive: id 8 + param 8 + guard 3 + scope 2 + min 16 + max 16 = **53**. (Fix loop 1 said 54;
  this is the corrected count.)
- Two passives, a benefit and a cost: 106 ≤ 122 in the high limb.

**`ARMOR_SET`** (1 part): 0 extra slots. Low limb: 5 bases × 16 = 80; high limb: 106.

**`CASTE`** (2 parts): **239** bits, 0 extra slots.

| Field | Bits |
|---|---:|
| tier | 8 |
| AI | 8 |
| health multiplier | 16 |
| health regeneration | 8 |
| armor | 8 |
| per-type armor | 54 |
| weapon | 28 |
| energy and regeneration | 16 |
| 4 skills | 64 |
| rank | 4 |
| flee threshold | 8 |
| loot table | 16 |
| boss | 1 |
| **Total** | **239** |

**Words written in play:** 0 extra slots.

| Word | Fit |
|---|---|
| `MemberEffects` | 4 slots × (skill 16 + charges 8 + deadline 28 + rank 4) = 4 × 56 = 224. Two slots per limb: 112 ≤ 128 low, 112 ≤ 122 high |
| `GoblinTimers` | charges 6 + rank 4 = 10 bits, exactly bits 240–249 |
| `MemberState` | 2 flag bits (3 of 8 used today) and `casts_2` 8 bits at 168–175 |
| Chunk object `param` | a member placer: 1 + 3 + 3 = 7 bits; a goblin placer: 1 + 12 + 2 = 15 bits (entity − 8 ≤ 3,593 < 4,096) |
| `GoblinState` | energy in thirds: 85 × 3 = 255; adrenaline cap 252 quarters = 63 strikes |

**The snapshot** (§7.2).
- **ENG-01's kit high limb holds 80** today: conditional damage 8, threshold 8, life steal 8, energy
  on hit 8, condition duration 8, enchantment duration 8, double adrenaline N 8, quick cast N 8,
  health bonus 16. Of 122, **42 are free**.
- **Lossless needs 171 bits** in that limb, over it by 49:

  | Need | Bits | Arithmetic |
  |---|---:|---|
  | damage sums | 48 | 2 guards × 3 classes × 8 |
  | penetration | 24 | 3 × 8 |
  | quick cast | 24 | 2 × (4 + 8) |
  | condition duration | 10 | 4 + 6 |
  | enchantment | 6 | — |
  | armor in a stance, enchanted | 16 | 2 × 8 |
  | knock-down flat, halving | 3 | 2 + 1 |
  | life steal | 8 | — |
  | energy on hit | 8 | — |
  | double adrenaline N | 8 | — |
  | health bonus | 16 | — |
  | **Total** | **171** | 122 + 49 |

- **`ARMOR_VS`**, 9 × 6 = 54 bits, fits `MemberStats`: 2 types in 48–63 (12 bits of 16) and 7 in
  200–249 (42 of 50).
- **With `MemberMods`** (word 8):

  | Word | Limb | Holds | Bits |
  |---|---|---|---:|
  | `MemberMods` | low | damage sums 48 + penetration 24 | 72 ≤ 128 |
  | `MemberMods` | high | quick cast | 24 ≤ 122 |
  | `MemberKit` | high | 8 + 8 + 10 + 6 + 8 + 16 + 16 + 3 | 75 ≤ 122 |

- **Cost of `MemberMods`**: +1 slot per member (8 → 9 words).
  - Lifetime: **453,524** L2 gas once per adventurer slot (N, ENG-01 §10).
  - Each create and gate: **32,072** (O).
  - In play: never written; a storage read, which ENG-01 does not price (for ENG-07).

**Registry reads** (per invocation, deduplicated, MVP worst case with 5 castes):

| Records | Count | Slots |
|---|---:|---:|
| bar `SKILL` | 8 | 8 × 2 = 16 |
| potions (`ITEM`) | 4 | 4 × 1 = 4 |
| `CASTE` | 5 | 5 × 2 = 10 |
| caste `SKILL`s | 20 | 20 × 2 = 40 |
| `LOCATION` | 1 | 1 × 2 = 2 |
| terrain-trap `SKILL`s | T | T × 2 = 2T |
| **Total** | **38 + T** | **72 + 2T** |

At ~36,000 a slot (ENG-01 §3.5): 72 × 36,000 = **2,592,000 L2 gas** + 72,000 × T. The union passes 32
even with T = 0, so a second `bundle` call is needed (C ≈ 0.12–0.14 M). ENG-05's generation reads
come on top and are not counted here.

## Escalations added or changed (fix loop 2)
§9 of v0.3 lists every escalation by group (A time, perception, activation; B hits; C held effects
and carriers; D counters and passives; E areas and traps; F content; G storage and reads) with a ★
on those CBT-01 needs first.
- **★**: FX-0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 18, 19, 22, 23, 24, 25, 27, 28, 29,
  30, 31, 33, 34, 35, 39, 40, 41, 42, 43, 45, 46.
- **Not ★**: FX-16, 17, 20, 21, 26, 32.

**Added**
- **FX-40 ★ When a carrier's guards are evaluated.**
  - Options: (a) once per carrier's execution, before anything applies; (b) once per actor, before
    that actor's entries (the source may have changed); (c) per entry, just before it applies (this
    breaks Second Wind's bonus, as the first audit showed).
  - **R (a)**: one reading, independent of the order of targets. Auditor (FX-0 row): asked that
    "area guard sampling" be decided explicitly.
- **FX-41 ★ Perception and the awake set within a tick.**
  - Options: (a) perception at step 0 before the selection, the set fixed for the tick, deaths not
    refilling it; (b) perception after the selection, so a goblin that notices joins next tick;
    (c) the set refilled after each death, which adds a selection per death.
  - **R (a)**: design/18's "asleep, within 2 tiles, notices" takes effect at once, and one selection
    a tick bounds the work. Auditor (F-6): asked that perception be positioned relative to the
    selection.
- **FX-42 ★ The identity of a held effect.**
  - Options: (a) its carrier, a skill id or a potion's **item** id, whatever the caster and the belt
    slot; (b) the carrier and the caster, so two Shamans' shields stack in two slots; (c) the belt
    slot for potions, so the same potion in two slots stacks.
  - **R (a)**. Auditor (F-12): (c), as v0.2 implied, let identical potions occupy two slots.
- **FX-43 ★ Passives held twice.**
  - Options: (a) sums per statistic, scope, guard and type; the lowest N for double adrenaline (as
    design/15's "only the highest rune counts"); one counter per quick-cast modifier, at most 2,
    bonuses added, activation ≥ 1; (b) only one modifier of each non-additive passive allowed by the
    build (`set_build` refuses a second).
  - **R (a)**: no build restriction. The auditor rejected build restrictions under FX-23.
- **FX-45 ★ Legal carriers.**
  - Options: (a) the §5.14 constraints (one hit, one holding entry, hit modifiers with a hit, attack
    skills `FOE SINGLE`, `TRAP` first); (b) several hits or holding entries per carrier. That costs a
    slot identity of (carrier, entry) and more effect slots, and every on-hit rule would need a
    per-hit decision.
  - **R (a)**: no source of the design documents needs more. Auditor (F-15): "either support
    independent held components with costed state, or explicitly constrain legal carrier
    combinations".
- **FX-46 ★ Registry reads above `MAX_READ`.**
  - Options: (a) two `bundle` calls when the union passes 32 (+C ≈ 0.13 M; the reads themselves
    2.59 M + 0.07 M × T at worst); (b) raise `MAX_READ` to 64 (an ENG-01 bound, and a costlier single
    call); (c) copy caste data into `Instances` when a pack wakes (writes, and a second home for
    content, which E-5 avoided); (d) a content bound: a location's spawn table names castes whose
    skills keep the union ≤ 32.
  - **R (a)**, priced by ENG-07, with (d) as the lever if the cost misses. Auditor (F-16): "price
    additional calls or change the bound explicitly".

**Changed**
- **FX-24 ★**: from "0 new slots" to **one more member word `MemberMods`**, lossless (arithmetic
  above).
  - Options: (a) the word (+1 slot per member; 453,524 once per adventurer slot, 32,072 per create
    or gate, no write in play); (b) content restrictions: damage percents scoped `WEAPON` or `ALL`
    and guarded `ALWAYS` or `ABOVE_HALF`, one quick-cast modifier, and the kit's health bonus folded
    into `MemberStats`. That comes to 113 bits, which fits only if the health bonus is redundant with
    `MemberStats`' max health, which ENG-01 does not say.
  - **R (a)**. Auditor: "Do not approve the inventory yet"; v0.3 gives the layout.
- **FX-28 ★**: **R changed** to the auditor's view: a bomb's strength comes from its recipe (an
  `ITEM` field, 8 bits, counted), and traps take `3 × level` of the source.
- **FX-31 ★**: **R changed** to the auditor's view, (b): knocked down refreshes like any condition.
  Design/04's general rule is then kept, and "does not stack with itself" is a restatement.
- **FX-39**: now ★ (auditor).
- **FX-29 ★**: R (a) is now **lazy expiry with the recharge dated from `A`** (auditor's view).
- **FX-15 ★**: the recovery shares the activation field in a three-state machine (§5.2); the auditor
  asked for the transitions.
- **FX-26**: R unchanged, (a) a standalone action. Auditor's view: prefers (b), immediate
  replacement of the seal, matching design/03, with the snapshot exception priced when Capture is
  designed.
- **FX-19 ★**: the predicate is written with saturating subtraction, `2(h ⊖ damage) < max`
  (auditor).

**Unchanged**: every other recommendation. The auditor agreed with FX-1 to FX-14, FX-16 to FX-18,
FX-20 to FX-23, FX-25, FX-27, FX-30 and FX-33 to FX-35 as written, sometimes with the precisions now
made.

## Commands run (fix loop 2)
- `git fetch origin && git merge --no-edit origin/main`: merged; the diff since 28f944c on design,
  architecture and logic is empty.
- The arithmetic check (`python3`): entry 97, caste 239, kit today 80, kit with `MemberMods` 75,
  kit without it 171, SKILL header 83, ITEM 72 / 113, MODIFIER 106, reads 38 records / 72 slots /
  2,592,000, the largest goblin offset 3,593, `MAX_CLOCK − LAST_TICK` = 65,545. The first draft said
  243 bits for `CASTE`, 3,608 for the goblin offset and 54 bits for a passive; all three were
  corrected before the commit.
- `git commit`, `git push` → `bd3f35e`; `gh pr checks 139 --watch --interval 30` → all `pass`.

## Acceptance criteria after fix loop 2
- **AC-1**: unchanged; the enumerations now include kind classes and the activation field's states.
- **AC-2**: the order is total, including perception, lazy lapses, the executor and the counters;
  eight examples.
- **AC-3**: the edges table covers charge-only effects, empty carriers, durations above 32,767.
- **AC-4**: the lossless inventory, with its bit arithmetic and the cost of the one added word.
- **AC-5**: FX-40 to FX-46 are added; every recommendation changed after the audit is marked
  "changed".

**What remains for the third loop or the project manager**:
- FX-24's word and FX-46's second call are **costs to approve**, not errors.
- The storage-read price of `MemberMods` in play is unmeasured (ENG-07).

---

# Fix loop 3 — `[Opus 5.5]`, after the `[GPT-6-Astra]` third audit (FAIL at `bd3f35e`)

## Summary
- **Merge.** `origin/main` was merged first. Its changes (the indexer) touch neither design/19 nor
  what it reads: the diff since bd3f35e on `docs/design`, `docs/architecture` and `contracts/logic`
  is empty.
- **The document.** design/19 is now **v0.4**. It fixes the verdict's five corrections, and F-17,
  F-18 and F-19.
- **Pushed.** Commit **`4186f53`**. **CI is green at 4186f53**: every check passed, watched with
  `gh pr checks 139 --watch` to completion. The `indexer-node` job was skipped by its own path filter.
- **Two corrections to fix loop 2.**
  - **The extra member word is withdrawn** (F-17). The auditor was right that other snapshot words
    have room: the snapshot now fits ENG-01's frozen words, **0 new slots**. `MemberMods` stays only
    as an optional layout, with its cost corrected: N 453,524 **instead of** an overwrite at its
    first write, then 32,072 per write.
  - **The complete registry-read bound** is `36 + 5C + T` records: **3 calls** at the MVP's worst
    (71 records, 119 slots, 4,284,000 L2 gas of reads).

## Findings and where they are fixed
| # | Third audit status | Fixed in v0.4 |
|---|---|---|
| **F-15** | partial | §5.14 rewritten. **The carrier's hit** is defined for every carrier: a weapon attack is a carrier with no entry and an **implicit weapon hit** on the attacked entity; an attack skill has the same implicit hit, with its entries on that entity; other carriers have a hit only through a `DAMAGE` entry. **The hit is always first** on an actor: legal-carrier rule "a `DAMAGE` entry comes before every other entry but `TRAP`", and the executor's step 5 "the hit first". So Skullring's knock-down follows its blow, and §10.2 now says so. **Trap placement** is step 2, **outside the actor iteration**: the payload is deferred and the executor stops. The trigger runs the payload alone with the entrant as its only actor. **Hit modifiers** are kept only if their guard held (the snapshot of step 1), and must have the hit's addressing, shape and filter, so they apply on each actor the hit reaches. §10.10 walks a Snare placed on an empty tile, then triggered by goblin 44 (damage 56, Crippled to 307) |
| **F-6** | partial | §5.2. The activated attack's recovery is **`B = A + k − n − 1`**, only when `k ≥ n + 2`; the next act is in step 2 of `T + max(k, n + 1)`, as for a plain attack of the same weapon. §10.9 is the boundary example: `k = 2, n = 1` acts again at 52, as a plain 2-tick attack does (v0.3 gave 53); `k = 3, n = 1` acts at 53 |
| **F-11** | partial | §7.2. **(1)** The potion tag is in **bit 7 of the charges byte** (charges use 0–5), so the skill field keeps every `u16` id and the rank its 4 bits. **(2)** The weapon's **class** and **damage type** are both specified: a member has `MemberStats.weapon` (88–95, CBT-01 fixes that it is the class) and `damage type` (160–167); the caste sheet's inline weapon now has class 4 and damage type 4 (243 bits). **(3)** Signed sums are bounded at both ends: `DAMAGE_PERCENT` values in [−18, +18], 7 held → [−126, +126] ⊂ `i8`; `PENETRATION` values in [0, 36], 7 × 36 = 252 ≤ 255. Also FX-43: health runes of one kind do not add up, and `DAMAGE_TYPE` is never summed (the auditor's view). `GoblinTimers`' free bits are corrected to 124–127 |
| **F-16** | partial | §7.2 now bounds **the whole union**, generation included, by kind, from the frozen records and the rules. `T ≤ 10` (terrain traps trigger on the member's moves only, and a batch has at most 10). `C ≤ 5` in the MVP. The call count is `⌈(36 + 5C + T) / 32⌉` calls of at most 32 records. The subtotal is no longer called the union. The generation rows are an **assumption** from ENG-01 §3.5's kinds, which ENG-05 confirms |
| **F-17** | new | The necessity claim is withdrawn: FX-24 now recommends the auditor's **0-slot** placement (`MemberBar` 136–231, `MemberKit` 75 bits, `MemberStats` 54 bits), with `MemberMods` as an option at its correct cost |
| **F-18** | new | X-3 rewritten: **signed arithmetic where the quantity is signed** (`v12 − v0`, `strength − armor`, percent sums, pip sums), clamped only to stated ranges; **`⊖` only** for health, energy, adrenaline, charges and a prospective health. §5.5 step 4: the exponent `x = strength − armor` is signed and **clamped to [−160, +80]** (design/04, D-140); the interrupt example's 22 (x = −10) is what the rule now gives. §5.5 step 3: armor after penetration cannot be negative since `p ≤ 100`. §6 has a row for the exponent's clamp |
| **F-19** | new | design/15's link → `19-effects.md#4-the-catalogue-passive-effects`. Every other link was checked against v0.4's headings: §4, §5, §5.1, §5.5, §5.7, §5.9, §5.10 |

F-1 to F-5, F-7 to F-10, F-12 to F-14: resolved in the third audit; unchanged, except FX-43's two
exceptions and FX-45's wording.

## The totals, recounted (`python3`, from the fields as declared)
**Registry records.** A limb is 128 bits low or 122 high (bit 250 `LIVE`; nothing straddles bit
128). Every record fits; none needs a slot beyond ENG-01's parts.

| Structure | Arithmetic | Total | Fit |
|---|---|---:|---|
| Entry | 8 + 8 + 16 + 16 + 16 + 16 + 6 + 2 + 3 + 1 + 3 + 2 | **97** | one limb |
| Passive | 8 + 8 + 3 + 2 + 16 + 16 | **53** | two passives, **106**: one high limb |
| `SKILL` header | 8 + 8 + 8 + 1 + 8 + 8 + 16 + 16 + 8 + 2 | **83** | part 0 low |
| `SKILL` whole | 83 + 3 × 97 | **374** | 2 parts, one limb each |
| `ITEM` | low 8 + 16 + 8 + 32 + 8 = 72; high 97 + 8 + 8 = 113 | **185** | 1 part |
| `ARMOR_SET` | low 5 × 16 = 80; high 106 | 186 | 1 part |
| `CASTE` | 8 + 8 + 16 + 8 + 8 + 54 + 32 + 16 + 64 + 4 + 8 + 16 + 1 | **243** | 2 parts |

**Words written in play.** All fit their frozen words.

| Word | Arithmetic | Total | Free |
|---|---|---:|---|
| `MemberEffects` | 4 × (16 + 8 + 28 + 4) | **224** | tag in charges bit 7; bit 6 free |
| `GoblinTimers` | low 8 + 16 + 28 + 28 + 28 + 16 = 124; high 4 × 28 = 112; + 10 | **246** | 124–127 (4 bits) |

**The snapshot, 0 new slots.**

| Word | Arithmetic | Total | Free |
|---|---|---:|---|
| `MemberBar` | low 8 × 16 = 128; high: elite 8 + damage sums 48 + penetration 24 + quick cast 24 = 104 ≤ 122 | 232 | 232–249, 18 bits |
| `MemberKit` high limb | 8 + 8 + 10 + 6 + 8 + 16 + 16 + 2 + 1 | **75** ≤ 122 | — |
| `MemberStats` (`ARMOR_VS`) | 2 × 6 = 12 ≤ 16 low; 7 × 6 = 42 ≤ 50 high | 54 | — |

**Registry reads**, `C = 5`, `T = 10`:

| | Arithmetic | Total |
|---|---|---:|
| Records | 1 + 5 + 1 + 1 + 7 + 4 + 4 + 1 + 8 + 4 + 5C + T = 36 + 25 + 10 | **71** |
| Calls | ⌈71 / 32⌉ | **3** |
| Slots | 2 + 5 + 1 + 1 + 7 + 8 + 4 + 1 + 16 + 4 + 10C + 2T = 49 + 50 + 20 | **119** |
| L2 gas of reads | 119 × 36,000 | **4,284,000** |
| With `T = 0` | 61 records, 2 calls, 99 slots | 3,564,000 |

**Examples** (the arithmetic of the two new ones; §10.1–§10.8's were checked by the auditor):

| Example | Arithmetic | Result |
|---|---|---:|
| §10.10 trap hit | ⌊40 × 92,682 / 65,536⌋ | **56** |
| §10.9, `k = 2, n = 1` | next act 50 + max(2, 2) | **52** |
| §10.9, `k = 3, n = 1` | next act 50 + max(3, 2) | **53** |

## Escalations changed in fix loop 3
- **FX-24**: the recommendation is now the 0-slot repacking; the auditor's view.
- **FX-46**: the recommendation is now calls of at most 32 records, 3 at the MVP's worst; the
  auditor's view, now that the union is bounded.
- **FX-15**: the recovery formula is corrected.
- **FX-35**: `DISC_1` only in potions (1 tick), so the unsplittable action's bound stays 3 × 14 = 42
  goblins; a bomb's tick changes at most 8 + 7 = 15.
- **FX-43**: runes and `DAMAGE_TYPE` are no longer summed.
- **FX-45**: now includes the implicit hit, the hit first, and the deferred payload.

**No escalation was added.** FX-36 to FX-38 and FX-44 are unused numbers.

## Commands run (fix loop 3)
- `git fetch origin && git merge --no-edit origin/main`: merged; the diff since bd3f35e on design,
  architecture and logic is empty.
- The recount above (`python3`).
- `git commit`, `git push` → `4186f53`; `gh pr checks 139 --watch --interval 30` → all `pass`
  (`indexer-node` skipped by its path filter).

---

# For the project manager

The escalations of design/19 v0.4, one numbered list. For each: the question, the options, **R** my
recommendation, and **A** the auditor's view (`[GPT-6-Astra]`, third audit, 2026-09-29). **★ =
CBT-01 needs it decided before it freezes**: the decision changes a field, an enumeration, a legal
combination, or a step or order of the pipeline.

**The count.** 37 escalations are ★ and 6 are not (FX-16, 17, 20, 21, 26, 32). FX-36, 37, 38 and 44
are unused numbers.

**Where the auditor differs from me.** On FX-26 only, a post-MVP question (the Seal of Capture). On
every other escalation the auditor's view is the same as my recommendation. Earlier differences were
settled by changing my recommendation to the auditor's: FX-10, 11, 22, 23, 24, 28, 29, 31, 46.

## A. Time, perception, activation
1. **FX-0 ★ The ordering conventions of design/19 marked ⟨FX-0⟩.** These are:
   - a carrier's actors in tile order;
   - target sets taken at resolution;
   - costs paid at the start;
   - facing by the first step of the hex line;
   - life steal bounded by the target's health;
   - effects on the living target only;
   - remains not blocking;
   - frozen timers lapsing by the clock.

   Options: as written, or alternatives (e.g. effect-major areas). **R** as written. **A** agrees.
2. **FX-0b ★ Ranks 13–15** (runes). Options: (a) cap at 12; (b) extrapolate the line up to 15, with
   every scaled bound validated. **R** (b). **A** (b).
3. **FX-1 ★ When an activation resolves.** Options: (a) step 1 of its `n`-th tick (design/02);
   (b) at the tick's end (design/04's words). **R** (a). **A** (a).
4. **FX-2 ★ When a recharge starts.** Options: (a) at the activation's end (resolution,
   interruption, lapse); (b) at use. **R** (a). **A** (a).
5. **FX-3 ★ The adventurer interrupted.** Options: (a) the action's remaining ticks run; (b) the
   action ends. **R** (a); mining keeps its own early stop. **A** (a).
6. **FX-4 ★ An interrupted adrenaline skill.** Options: (a) spent; (b) refunded. **R** (a).
   **A** (a).
7. **FX-5 ★ Attack skills' tick cost and landing.**
   - Tick cost options: (a) the activation; (b) max(weapon, activation); (c) the sum.
   - Landing options: at once, or at resolution.

   **R** (b); at once without activation, at resolution with one. **A** (b).
8. **FX-8 ★ The adventurer at 0 health mid-tick.** Options: (a) defeated at once (steps 0–2), step 3
   completing first, step 5's finalisation always; (b) checked only at step 5. **R** (a).
   **A** (a).
9. **FX-15 ★ A goblin's act costing `k > 1` ticks.** Options: (a) a recovery in the activation
   field, `B = T + k − 1` (plain) or `B = A + k − n − 1` (activated, `k ≥ n + 2`); (b) the act as a
   `k`-tick activation landing at its end; (c) goblins ignore tick costs. **R** (a). **A** (a),
   with the corrected formula.
10. **FX-29 ★ A goblin's activation while it is frozen at its deadline.** Options: (a) it lapses at
    `A`, applied lazily with the recharge from `A`; (b) it resolves at its next awake step 1;
    (c) activating goblins get priority in the awake set. **R** (a). **A** (a).
11. **FX-41 ★ Perception and the awake set.** Options: (a) perception at step 0 before the
    selection, the set fixed for the tick and not refilled; (b) perception after the selection;
    (c) the set refilled after each death. **R** (a). **A** (a).

## B. Hits and damage
12. **FX-9 ★ Penetration.** Options: (a) a percent, summed, capped at 100; (b) flat (design/04's
    formula); (c) both. **R** (a). **A** (a).
13. **FX-10 ★ What a hit is.** Options: (a) any class reaching its target unstopped, 0 damage and
    traps included; (b) weapon hits only. **R** (a). **A** (a).
14. **FX-11 ★ Flank and evasion.** Options: (a) flank ignores evasion like a block; (b) evasion
    holds from every arc. **R** (b). **A** (b).
15. **FX-19 ★ *Hob-breaker*'s halving.** Options: (a) on the final damage of a weapon hit, with the
    predicate `2h ≥ max ∧ 2(h ⊖ damage) < max`, the flag spent when it triggers; (b) −50 % inside
    D-140's sum. **R** (a). **A** (a).
16. **FX-23 ★ Damage types and per-type armor.** Options: (a) 3 (type, value) pairs and a build
    limit; (b) 9 × 6 bits, saturated at 63. Also: shadow and holy take neither class bonus.
    **R** (b); neither bonus. **A** (b); approve the cap of 63 explicitly.
17. **FX-27 ★ Arcs for spells; scopes.** Options: (a) arcs and criticals for weapon hits only;
    (b) for spells too. Scopes default to `WEAPON`. **R** (a). **A** (a).
18. **FX-28 ★ The strength of bombs and traps.** Options: (a) `3 × level` of the source; (b) 0;
    (c) the recipe's. **R** bombs (c), traps (a). **A** the same.

## C. Held effects and carriers
19. **FX-6 ★ Refreshing a condition.** Options: (a) `max(old, new)`; (b) the new deadline replaces
    the old. **R** (a). **A** (a).
20. **FX-7 ★ Knocked down.** Options: (a) only Wait is legal, and the actor neither blocks nor
    evades; (b) its ticks run automatically. **R** (a). **A** (a).
21. **FX-13 ★ Effect slots full.** Options: (a) evict the earliest deadline, ties to the lowest
    slot, a goblin's one slot replaced; (b) the new effect fails; (c) evict the oldest applied.
    **R** (a). **A** (a).
22. **FX-30 ★ Potency on refresh.** Options: (a) the application with the later deadline, whole;
    the new one on a tie; (b) the new one's rank and charges with the `max` deadline; (c) the
    strongest rank combined with the longest deadline. **R** (a). **A** (a).
23. **FX-31 ★ Knocked down reapplied while held.** Options: (a) nothing happens; (b) refreshed like
    any condition. **R** (b). **A** (b).
24. **FX-40 ★ When a carrier's guards are evaluated.** Options: (a) once, before anything applies;
    (b) per actor; (c) per entry. **R** (a). **A** (a).
25. **FX-42 ★ The identity of a held effect.** Options: (a) its carrier (a skill id, a potion's item
    id); (b) the carrier and the caster; (c) the belt slot. **R** (a). **A** (a).
26. **FX-45 ★ Legal carriers.**
    - Option (a) constrains every carrier:
      - at most one hit, which is implicit for attacks;
      - the hit first;
      - one holding entry;
      - hit modifiers with the hit's set;
      - `TRAP` first, with its payload deferred;
      - one entry per potion.
    - Option (b) allows several hits or holding entries, with costed state.

    **R** (a). **A** (a).

## D. Adrenaline, counters, passives
27. **FX-12 ★ Adrenaline.**
    - Options for the cap, out of combat and decay: as design/19 §5.8 and §5.12 write them, or other
      definitions.
    - Options for the rate: a code constant `ADRENALINE_DECAY`, or a registry record.

    **R** as written, with a code constant until BAL-01. **A** agrees.
28. **FX-39 ★ Which spell takes the quick-cast bonus.** Options: (a) counted at a spell's start, the
    bonus spent if interrupted; (b) counted at resolution; (c) instant spells count too. **R** (a).
    **A** (a).
29. **FX-43 ★ Passives held twice.**
    - Option (a) sums per statistic, scope, guard and type, with these exceptions:
      - health runes of one kind do not add up;
      - `DAMAGE_TYPE` is never summed;
      - the lowest N counts for double adrenaline;
      - one counter per quick-cast modifier, at most 2.
    - Option (b) is a build restriction.

    **R** (a). **A** (a).

## E. Areas, bombs, traps
30. **FX-14 ★ Traps.** Options: a terrain trap is a `SKILL` id; it lasts until triggered or until
    the instance closes; it triggers once; placement is invalid when the chunk's objects are full.
    **R** as stated. **A** agrees.
31. **FX-33 ★ design/04's 18 and 36 tiles.** Options: (a) discs with their centre (19, 37); (b) rings
    without it. **R** (a). **A** (a).
32. **FX-34 ★ Whom a terrain trap hits.** Options: (a) members only; (b) any actor. **R** (a).
    **A** (a).
33. **FX-35 ★ A bomb's 7 tiles against ENG-01's budget of 6.** Options: (a) raise the bound to 7,
    with `DISC_1` only in potions; (b) bombs `SINGLE` only; (c) at most 6 actors. **R** (a).
    **A** (a), updating the cold and full-action bounds (the unsplittable class stays at 42).
34. **FX-21 Radius 2 and 3.** Options: allowed in MVP content now, or not until measured. **R** not
    until measured. **A** agrees.

## F. Content shape
35. **FX-25 ★ The generic `Skill` kind.** Options: (a) interruptible, but not a spell for Dazed,
    glyphs or quick cast; (b) a spell in every respect; (c) not interruptible. **R** (a). **A** (a).
36. **FX-18 ★ Potions.**
    - "+movement": (a) moves cost 1 tick even when crippled; (b) 2 tiles a move.
    - Revive and reveal the floor: post-MVP.
    - A bomb's target: (a) a tile flag in `Item`, with range and line of sight; (b) an entity only.

    **R** (a), post-MVP, (a). **A** the same.
37. **FX-16 Rime Shard's slow.** Options: (a) Crippled; (b) a new kind. **R** (a). **A** (a).
38. **FX-17 Second Wind's "more if below 50 %".** Option: a second `HEAL` guarded `BELOW_HALF`, read
    before either heal. **R** that. **A** agrees.
39. **FX-20 The Shaman's "shields", the Paladin, summons, the Wolf rider.** Options for the shields:
    `ARMOR`, or a kind of their own; the rest waits for its design. **R** `ARMOR`; defer the rest.
    **A** agrees.
40. **FX-26 The Seal of Capture** (post-MVP). Options: (a) a standalone action on remains, with the
    seal kept in the instance's snapshot until the next entry; (b) immediate replacement of the seal
    in the instance. **R** (a). **A** (b), matching design/03, with the snapshot exception priced
    when Capture is designed. **The one difference between us.**
41. **FX-32 The Hexer's "punishes skill spam"** (post-MVP). Options: damage or energy loss at each
    skill start, at each resolution, or above a count. **R** defer to DES-06; kind 21 stays a
    placeholder. **A** agrees.

## G. Storage and reads
42. **FX-22 ★ The four post-MVP conditions.** Options: (a) one more word per member and per goblin
    when they ship; (b) in effect slots; (c) 16-bit offsets. **R** (a). **A** (a).
43. **FX-24 ★ The state inventory.** Options: (a) the lossless snapshot repacked into `MemberBar`,
    `MemberKit` and `MemberStats`, 0 new slots; (b) a word `MemberMods` (+1 key, N 453,524 at its
    first write, then O 32,072 per create or gate); (c) content restrictions. **R** (a). **A** (a).
44. **FX-46 ★ Registry reads above `MAX_READ`.** Options:
    - (a) calls of at most 32 records, `⌈(36 + 5C + T) / 32⌉`: 3 at the MVP's worst (71 records,
      4.28 M of reads + about 0.26 M for the two extra calls), 2 without terrain traps;
    - (b) raise `MAX_READ` to 64;
    - (c) copy castes into `Instances`;
    - (d) a content bound on `C`.

    **R** (a), with (d) as the lever. **A** (a).

## Is 19-effects complete enough for CBT-01?
**Yes, once the 37 ★ escalations are decided.** CBT-01 can then freeze the schemas without a design
decision of its own:
- the enumerations and their ids;
- the 97-bit entry;
- the legal carriers;
- the pipeline's functions and their order;
- the state layouts in ENG-01's frozen words, 0 new slots.

Three things remain outside CBT-01, and none blocks the freeze:
- **ENG-05** confirms the generation reads assumed in the read bound;
- **ENG-07** measures the read costs;
- **CNT-01, DES-06 and BAL-01** set the values.

The third audit's remaining corrections are all addressed in v0.4. Whatever a fourth reading finds
goes to the project manager with this list.
