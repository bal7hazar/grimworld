# CBT-05b — The adventurer's action and traps: legality, costs, facing, quick cast; placing and triggering

> CBT-05's second part (PLAN row CBT-05, its **Split**: "CBT-05a the executor (§5.14) …; CBT-05b the
> action's costs (§5.3) and traps (§5.11)"). CBT-05a's brief puts in its *Out* "the action's legality
> and costs, facing, quick cast (§5.3, CBT-05b); traps' placement and trigger (§5.11, CBT-05b)".
> Decisions: D-140, D-143, D-147, D-155 (FX-0, FX-3, FX-5, FX-7, FX-14, FX-25, FX-28, FX-34, FX-39,
> FX-43, FX-45), D-167, D-172, D-174, D-176, D-177. **Starts after CBT-05a merges**: it calls the
> executor (a resolution now, a trap's placement and its payload all run through it, design/19
> §5.3 step 4, §5.14) and shares its files (*Allowlist*); see *Open questions* 1 for FND-11.

## Goal
After this task the **action phase** of design/19 §5.3 exists in the logic package as one scoped
trait: an adventurer's action is checked against the state it meets (illegal: the batch stops,
design/02 *Executing a batch*), its costs are paid at once, the member faces its target, the action
resolves now through CBT-05a's executor **or** starts an activation, and it returns its tick cost for
the pipeline to run. **Traps** exist: a `TRAP` carrier places a trap object (kind 9) on its tile
through the executor's step 2, and a trap (placed, kind 9; terrain, kind 4) triggers once when a foe
of its side enters its tile, its payload resolved by CBT-05a's executor with the entrant as its only
actor, class `TRAP`. Deterministic, never panicking on a legal action (D-140, X-4), its cost stated
against ENG-01 §9.2.

## Context
- **design/19** (v0.5, D-155): **§5.3** (the adventurer's action, steps 1–5), **§5.11** (traps:
  the two object kinds, placing, triggering steps 1–4), §5.12 (the `casts` counters, adrenaline's
  cost at a skill's start), §5.9 (an activation started here; interrupted: energy, a glyph and a
  quick-cast bonus stay spent, FX-39), §5.14 (step 2, placement outside any actor iteration; *A
  trap's trigger*: steps 1, 3, 5, class `TRAP`; the legal-carrier row "`TRAP` entry 1, `TILE`,
  `SINGLE`; the payload `FOE`, `SINGLE`"), §5.4 (class `TRAP`: strength `3 × level`, FX-28; no arc,
  block, flank or evasion), §3.3 (`NEXT_SPELL_COST`, the glyph, consumed when the next spell
  starts), §3.4 *Skill kinds* (1 Attack needs the weapon of its attribute; 5 Stance; 6 Shout; 9
  Trap; 10 Glyph; 11 `Skill`, FX-25: not a spell for glyphs and quick cast), §4 (passives 55
  `QUICK_CAST_EVERY_N`, 57 `ENERGY_COST`), §2.3 (filters: a target the filter refuses), **§6**
  (the edges below), §7.2 (the chunk object's `param` for kinds 9 and 4; `MemberState`'s flags and
  `casts_2`), §8 (Snare: 9; 18, 6, 1; terrain traps: object kind 4; the Trapper is **P**), §9
  (FX-14, FX-34, FX-28, FX-39, FX-43), **§10.6** (the fifth cast, interrupted) and **§10.10** (a
  trap placed, then triggered).
- **design/02** *Executing a batch*, the row "The action is illegal in the state it meets": tile
  blocked, out of range or of sight, not enough energy, recharging, a second turn or a second
  instant skill between two ticks, acting while knocked down, an item not in the belt. **design/04**
  *Actions*: Turn costs 0, at most once between two ticks; Skill costs its activation (min 1);
  instant skills cost 0 ticks, at most one between two ticks; Use item 1.
- **§6's edges this lot owns**: energy cost after reductions below 0 → 0; activation after reductions
  below 1, non-instant → 1; the adventurer knocked down → only Wait (FX-7); a trap on a full chunk,
  an occupied tile, a wall → invalid (FX-14); a counter at N → reset; the geometry rows (same tile:
  facing unchanged; a position outside the window: facing unchanged; a line leaving the window: the
  facing still uses its first step; D-174).
- **What it calls**:
  - CBT-05a's executor (`docs/briefs/CBT-05a-executor.md`): only what that brief freezes: the
    executor called "for an immediate carrier" by the action phase, the placement of its step 2,
    and a trap's payload "once CBT-05b triggers it". **Read CBT-05a's report and merged code first**
    and use its trait as merged; a change to its signature is an escalation, not an edit.
  - ENG-02's `WindowTrait` (`types/window.cairo`, frozen in `docs/reports/ENG-02-geometry.md`):
    `facing(from, to, facing)` for §5.3 step 3 (22,500 on every path, ENG-01 §9.2), `reach(from, to,
    range)` for range and sight, `distance`; positions are the window's index `15 y + x`, 0–239.
  - The member's lifecycle (`models/member.cairo`: `start` takes `n` after reductions, CBT-02's
    report *Deviations*; `interrupt`, `knock`); CBT-04's predicates (`can_act`, `move_ticks`,
    `docs/reports/CBT-04-conditions.md`); the tick's sheets (`types/tick.cairo`: `SkillSheet` holds
    `kind`, `adrenaline`, `activation`, `recharge` today, not the header's energy, range or target,
    ENG-01 §3.5 `SKILL` part 0: energy 24–31, range 72–79, target 80–81).
  - The chunk object (ENG-01 §3.2 `Features`: objects at 128, 160, 192, tile · kind · state ·
    `param`; at most 3 a chunk) and `types::combat::Placer` (`param`/`from_param`, already merged).
- **Carried from CBT-02** (`docs/reports/CBT-02-tick-pipeline.md`, *Deviations* and fix-loop scope
  notes): the quick-cast counters are not moved at an activation's start (§5.3 step 2 is CBT-05's);
  the snapshot's quick-cast attribute is a build-local index while a skill's is a global id (D-157
  A); the adrenaline spent at an adrenaline skill's start is a cost, not built.
- **The cost**: ENG-01 §9.2 counts the action phase with the tick: its hit row counts "the member's
  action (7 …)" and "a trap its move enters" among the 15 hits; its conditions paragraph says "a
  trap's trigger replaces an application already counted, never adds one" (a goblin entering a
  Snare does not attack; a member that moves runs no carrier, so ≤ 1 terrain payload on it, FX-34).
  STATUS keeps §9.2's combined line (5,464,542, 3.72× the 1,469,435 target, after #229); CBT-05a
  writes the executor's line. This lot adds **the action phase's own work** (legality, costs, one
  facing, a placement or a trigger's lookup) as one line, measured.
- CAIRO.md §2 (test-driven, every test a gas budget, unit tests in their module, D-167; measured
  builds single-threaded, D-176), §7 and §8 (D-143, D-147: rules in scoped traits, checks in
  `Assert` impls with `errors` modules). COMMON.md. **D-149**: no event of ENG-01 changes.

## Scope
- In:
  - **The action phase** (§5.3 steps 1–4), a scoped trait in the logic package that takes the
    world, the sheets, the window and one decoded `Action` (`actions.cairo`) of the combat kinds
    (Attack, Skill, Item, Turn, Wait) and returns either the action's tick cost (§5.3 step 5,
    FX-3, FX-5: an attack skill costs `max(weapon, activation)`) or the refusal that stops the
    batch. ENG-07's `play` calls it (see *Open questions* 2 for Move and Interact).
  - **Legality (step 1)**, each with a refusal test: design/02's list for these kinds (a target
    out of range or out of sight through `WindowTrait::reach`; energy short after reductions;
    adrenaline short; the skill recharging; a second Turn or a second instant skill between two
    ticks, from `MemberState`'s flags bits 0–1; any action but Wait while knocked down, FX-7; an
    item whose belt count is 0); an attack skill without the weapon of its attribute (§3.4); a
    target the entry's filter refuses (§2.3: a dead goblin is neither foe nor ally); a trap tile
    that cannot take one (§5.11 placing: not walkable, holds an actor or an object, out of range,
    no object index empty or a used trap; FX-14); the clock past `LAST_TICK` (ENG-01 §4.1, E-4).
    Illegal is a refusal, never a panic (D-140).
  - **Costs (step 2)**, at once (FX-0): energy after `ENERGY_COST` (passive 57, its profession)
    and a held glyph (`NEXT_SPELL_COST`, kind 9) at a spell's start, floored at 0 (§6), the glyph
    consumed; adrenaline (in quarter strikes, §5.12); an instant skill's recharge from its use (§5.1's
    counting; an activation's recharge runs from its end, FX-2, where CBT-05a resolves it); the potion's belt count; **quick cast**: the
    `casts`/`casts_2` counters move when a spell (kind 2, 3 or 4, not kind 11, FX-25) with
    activation ≥ 1 starts, each by its modifier's attribute and N, the bonuses added, the activation
    never below 1 (§5.12, FX-39, FX-43). Interrupted later, every cost stays spent (§5.9).
  - **Facing (step 3)** through `WindowTrait::facing` toward the target entity or tile, Turn's
    direction set directly, with §6's geometry edges tested.
  - **Resolution or activation (step 4)**: an attack, an attack skill without activation (FX-5), a
    potion, an instant skill → CBT-05a's executor now; otherwise the member's activation starts
    (`MemberTrait::start`, `n` after the quick-cast bonus), resolving in step 1 of its `n`-th tick
    through CBT-05a's `resolve`.
  - **Traps** (§5.11): **placing**, the executor's step 2 writing a kind-9 object with its `Placer`
    `param` (a member: member and bar slot; a goblin placer is accepted by the same code, though no
    MVP goblin places one, §8's Trapper **P**); **triggering**, a scoped function the move's owner
    calls right after an actor enters a tile (a member's move in the action phase, a goblin's in
    step 2): it finds an unused trap on the tile, checks the entrant is a foe of its side (placed:
    the placer's foes; terrain: members only, FX-34), builds the source (§5.11 step 1: a member
    placer's snapshot level and bar rank; a goblin placer's record caste, level and caste rank; a
    terrain trap's location values, FX-14, FX-28), runs the payload through CBT-05a's executor
    (class `TRAP`, the entrant the only actor), marks the object used, and reports a death (§5.13:
    the adventurer at 0 stops before the ticks, CBT-02's `TickTrait::tick` already checks it; a
    goblin killed in its own move ends its act).
  - **Tests** in their modules: each legality row refused, each cost, the counters at N (§10.6 to
    the unit, with its interruption), facing on every geometry edge, §10.10 to the unit (placement
    at 302, the trigger at 305: 100 → 44, Crippled `D = 307`, the object used, the goblin's act
    ended), a trap on its own side not triggering, a used trap not triggering twice, a trap
    replacing a used one at the lowest index, a full chunk refused.
  - **The per-tick budget line**: the action phase's worst (legality, costs, one facing, a placement
    or a trigger's lookup; the executor's own cost is CBT-05a's line), stated against the bound and
    written into ENG-01 §9.2; whether a trigger keeps §9.2's "replaces, never adds" sentence true,
    measured.
- Out: the executor and every entry kind's rule (CBT-05a); the move itself, its occupancy, the
  window's assembly and its origin, the batch loop, its weight and `play` (ENG-07); `Interact`,
  chests, veins, `mine` (ENG-06/ENG-07, §5.10); a goblin's choice to act, place or skip (ENG-07,
  CBT-07: "skipped by the AI", FX-14); generating terrain traps (ENG-05); post-MVP kinds (**P**).
- Allowlist: `contracts/logic/src/**` (new files welcome; `types/window.cairo` not touched);
  `contracts/persistent/src/systems/registry.cairo` for the validators' refusals only (a `TRAP`
  carrier §5.14 refuses, if one is missing); the packages' tests; `docs/architecture/ENG-01-
  interfaces.md` §9.2; `GAS.md` and `docs/BUDGETS.md` as generated. Anything else is an escalation.
  **Overlaps**: the whole allowlist is CBT-05a's (`contracts/logic/src/**`, the registry's
  validators, ENG-01 §9.2, `GAS.md`, `BUDGETS.md`), so this lot starts **after CBT-05a merges**;
  the generated gas files are also FND-11's (toolchain, CI, every `Scarb.toml`/lock, generated gas
  files), so it does not run alongside FND-11 (*Open questions* 1).

## Acceptance criteria
- [ ] AC-1 The report opens with an inventory: §5.3's steps and §5.11's rules, where each lives
      after CBT-05a, and what this lot adds.
- [ ] AC-2 Every legality row above refused with its test, as a refusal (no panic); every legal
      action of the five kinds accepted, with its tick cost (FX-3, FX-5).
- [ ] AC-3 Costs at once: energy after reductions floored at 0, the glyph consumed, adrenaline, the
      recharge, the belt; the `casts` counters by FX-39/FX-43; §10.6 reproduced to the unit.
- [ ] AC-4 Facing through `WindowTrait::facing` only; §6's geometry edges tested.
- [ ] AC-5 Traps placed through CBT-05a's executor step 2 and triggered through its payload path,
      both kinds, every rule of §5.11 tested; §10.10 reproduced to the unit.
- [ ] AC-6 The carried items from CBT-02 done or answered.
- [ ] AC-7 The action phase's per-tick line in the report and ENG-01 §9.2; `TickLibrary` under 50 %
      (ENG-01 §1.3) or the stop.
- [ ] AC-8 D-143; unit tests in their modules (D-167); CI green; `gas_budgets.py --check`;
      `class_sizes.py`.

## Audit
This lot meets the exception rule for **one cost lens** (D-177: a cost only a measurement proves):
its line in ENG-01 §9.2 and the claim that a trap's trigger replaces, never adds, an application
feed ENG-07's batch weight; no other lens expected. The orchestrator decides at the close.

## Verification
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
The report as in `docs/briefs/COMMON.md` §7: the inventory, the action phase and each legality row,
the costs and quick cast, facing, the traps, the carried items, the per-tick budget line, the gas
table of every test.

## Open questions
1. **FND-11 and the generated gas files.** FND-11 (Scarb 2.20.1) rewrites every `Scarb.toml`/lock
   and the generated gas files; this lot writes `GAS.md` and `BUDGETS.md` too. *Recommendation*:
   start CBT-05b after FND-11 merges (the order of the track is CBT-05a, then FND-11), so its budgets
   are set once, under the new compiler.
2. **Move and Interact.** §5.3 covers every action, but ENG-07's row owns "movement, facing, …,
   action queue". *Recommendation*: CBT-05b owns the five combat kinds and the trap trigger; Move
   (its walkable, unoccupied tile, Crippled's 2 ticks through `move_ticks`, its facing) and Interact
   stay ENG-07's, which calls the trigger after each move. If the orchestrator prefers one action
   trait, Move's legality joins this lot and only the window and `play` stay ENG-07's.
3. **Entities and global tiles against window positions.** An action names an entity (`u16`) or a
   global tile (`x + 256 y`, ENG-01 §3.2); `WindowTrait` takes window positions (0–239) and a
   `Window` holds no origin. *Recommendation*: the action phase takes the window's origin as an
   argument from its caller (ENG-07 assembles the window) and converts once.
4. **The sheets lack the skill header's energy, range and target** (`SkillSheet`, `types/tick.cairo`).
   *Recommendation*: add them to the in-call sheet as CBT-02d's index did (no frozen interface
   changes), measured, unless CBT-05a's decoded entries already carry them.
5. **The quick-cast attribute's mapping** (a build-local index in the snapshot, a global id on the
   skill, D-157 A; CBT-02's report gives it to ENG-06, which merged in #120). *Recommendation*: check
   ENG-06's report and code; if the mapping is missing, add it where the sheets are built, as a
   carried item, and report it.
6. **A terrain trap's source and payload.** §5.11 step 1 says "its location's values (FX-14,
   FX-28)", but `LOCATION` (ENG-01 §3.5) holds a level band, not a level, and no rank; and a
   terrain trap's `param` is a `SKILL` id whose entries may or may not start with `TRAP`.
   *Recommendation*: the band's lower level and rank 0, the payload the skill's entries without a
   `TRAP` entry if it has one; the project manager confirms (a design reading, D-155's owner), and
   the lot builds the placed trap first, which needs none of this.
