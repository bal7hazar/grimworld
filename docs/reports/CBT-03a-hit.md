# [Opus 5.5] CBT-03a — One hit: block, evasion, armor, damage

## Summary

One hit is now computed as design/19 §5.5 steps 1–4 and §5.6 say. `HitTrait::resolve` is a pure, scoped function in the new module `contracts/logic/src/types/hit.cairo`. It takes the hit's inputs and returns its outcome: missed, blocked (a charge to spend), evaded, or landed with its damage, whether it was critical, and whether FX-19's halving triggered.

- **Where it lives.** The module is in `types/` because CAIRO §7 places there the value types that are never stored on their own; a hit is one.
- **Edges.** Every edge of D-140 and §6 that concerns a hit is tested, and 256 legal random cases run without a panic.
- **Vectors.** A 200-line vector table for the TypeScript mirror is generated from the tests. An independent Python oracle, written outside the repository, reproduced all 200 outcomes.
- **Cost.** One hit costs 46,460 L2 gas on every path. A tick computes at most 15 hits (fix loop 1: FX-35 counts a bomb's 7), which adds 696,900 to CBT-02d's 3,447,872: **≤ 4,144,772 a tick (2.82×** the 1,469,435 target). That line is written into ENG-01 §9.2.
- **Pull request:** https://github.com/bal7hazar/grimworld/pull/229. CI is green and the PR is not merged.
- **Model.** This session ran as Claude Opus 5.5, the model the brief names.

### The function and its inputs

`HitTrait::resolve(self: @Hit, target: @HitTarget) -> HitOutcome`

**`Hit`, the hit and its source:**

| Field | Meaning |
|---|---|
| `class` | `HitClass` (CBT-01) |
| `weapon` | weapon class, for the axe |
| `melee` | the weapon's range is 1 |
| `arc` | `Arc`: Front, FrontSide, RearSide, Back. **ENG-02** |
| `in_front` | the target is on the source's front tile, for Blind's miss. **ENG-02** |
| `strength` | strength, by class |
| `base` | base damage, ≤ 33,022 |
| `percent`, `percent_above_half` | the class's `DAMAGE_PERCENT` sums from §7.2 |
| `penetration` | every penetration that applies, summed and capped here |
| `health`, `max_health` | the source's, for the `ABOVE_HALF` guard |
| `weakened`, `blind` | **CBT-04**; **P** |

**`HitTarget`, the target:**

| Field | Meaning |
|---|---|
| `armor` | unguarded armor, `i16` |
| `armor_effects` | its `ARMOR` effects, summed |
| `armor_stance`, `armor_enchanted`, `in_stance`, `enchanted` | the guarded armor sums and whether their guards hold |
| `armor_vs` | `ARMOR_VS` of the hit's damage type |
| `block` | `BLOCK` charges held |
| `evade` | holds `EVADE` (melee) |
| `knocked_down` | **CBT-04** |
| `asleep` | |
| `halve` | `HALVE_FIRST_HEAVY_HIT` held and not spent |
| `health`, `max_health` | its health before the hit |

**`HitOutcome`:** `Missed | Blocked | Evaded | Landed(Landed { damage: u16, critical, halved })`.

**Helpers and checks:**
- `HitTrait::weapon_strength(rank, cap)` is 5 × rank, capped by the level's cap.
- `HitTrait::level_strength(level)` is 3 × level.
- `HitTrait::weapon_base(damage, requirement_met, bonus)` divides by 3 below the requirement, then adds `ATTACK_BONUS`.
- The steps are exposed for CBT-05: `stop`, `is_critical`, `armor`, `percent`, `damage`, and `HitTargetTrait::halve`.
- `HitAssert::assert_valid` refuses a base above 33,022, a health above its max, and a block above 63 charges.
- `errors` holds the messages.

## Files changed

- `contracts/logic/src/types/hit.cairo`: new. The types, `HitTrait`, `HitTargetTrait`, `HitAssert`, `errors`, and 28 tests in the module.
- `contracts/logic/src/types.cairo`: the module's line.
- `contracts/logic/tests/test_hit_cost.cairo`: new, benchmarks only. The pair for one hit, the 14 hits of a tick, and the paths check.
- `contracts/logic/vectors/hit.jsonl`: new. 200 vectors.
- `docs/architecture/ENG-01-interfaces.md`: §9.2, this lot's row.
- `contracts/logic/GAS.md` and `docs/BUDGETS.md`: generated.

## Commands run

- `snforge test grimworld_logic::types::hit` (in `contracts/logic`): 28 passed after the fixes below. The first run had two failures:
  - a wrong expectation in my own test (`damage()` clamps, so I asserted an unclamped value instead);
  - `test_vectors` ran out of steps at 500 cases, so I lowered it to 200.
- **Oracle**, `python3 .scratch/oracle.py` (scratch, not committed): an independent implementation of §5.5–§5.6 over `vectors/hit.jsonl` printed `checked 200 bad 0`. The outcomes were Landed 182, Blocked 8, Missed 7 and Evaded 3.
- `snforge test test_hit_cost`:
  ```
  [PASS] test_cost_pair_hit_one  l2_gas: ~60180
  [PASS] test_cost_pair_hit_none l2_gas: ~13720
  one hit: landed 46310, blocked 46420, evaded 46320, missed 46320, spell 46310, bomb 46310
  14 hits: 647440; one hit in a loop: 46310
  ```
- **Path scan** (a scratch test, deleted after use): 65,536 combinations of class, arc, axe, melee, in-front, penetration, the guards, Weakness, Blind, block, evade, knocked down, asleep and negative armor. Every combination cost **61,510** per hit before inlining. That confirms one charge on every path.
- **Optimisation**: inlining `stop`, `armor`, `percent`, `damage`, `halve` and `assert_valid` into `resolve` brought one hit in a loop from 62,210 to 46,310 (−26 %). The vector digest did not change.
- `python3 scripts/gas_budgets.py`: wrote the three `GAS.md` files and `docs/BUDGETS.md`. Only the 32 new rows were added.
- `python3 scripts/gas_budgets.py --check`: `gas check: 795 tests, every budget is ceil(1.05 x measured) or lower, 4 files current`.
- `scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build`: `Finished dev profile target(s) in 29 seconds`.
- `python3 contracts/tools/class_sizes.py`: every class ok. The largest is `Hub` at 45.40 %. Nothing changed, because no contract calls the hit yet.
- `scarb fmt --check`: clean.
- `gh pr checks 229 --watch`: every check passed; `indexer-node` was skipped, as on other PRs.
- The persistent and ephemeral packages' tests ran inside `gas_budgets.py`'s workspace run, and all 795 tests were measured. I did not run them separately.

## Cost

Printed by `python3 scripts/gas_budgets.py --report`. Every other test is unchanged.

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_logic::test_hit_cost::test_cost_hit_paths | — | 1867240 | 1960602 | new |
| grimworld_logic::test_hit_cost::test_cost_hits_per_tick | — | 1029900 | 1081395 | new |
| grimworld_logic::test_hit_cost::test_cost_pair_hit_none | — | 13720 | 14406 | new |
| grimworld_logic::test_hit_cost::test_cost_pair_hit_one | — | 60180 | 63189 | new |
| grimworld_logic::types::hit::tests::test_arcs_weapon | — | 47760 | 50148 | new |
| grimworld_logic::types::hit::tests::test_armor_below_zero | — | 22000 | 23100 | new |
| grimworld_logic::types::hit::tests::test_armor_terms | — | 111250 | 116813 | new |
| grimworld_logic::types::hit::tests::test_axe | — | 55840 | 58632 | new |
| grimworld_logic::types::hit::tests::test_base_refused | — | 15520 | 16296 | new |
| grimworld_logic::types::hit::tests::test_blind_miss | — | 22000 | 23100 | new |
| grimworld_logic::types::hit::tests::test_block_by_arc | — | 39380 | 41349 | new |
| grimworld_logic::types::hit::tests::test_block_knocked_down_or_asleep | — | 31100 | 32655 | new |
| grimworld_logic::types::hit::tests::test_block_refused | — | 15520 | 16296 | new |
| grimworld_logic::types::hit::tests::test_critical_any_arc | — | 39380 | 41349 | new |
| grimworld_logic::types::hit::tests::test_damage_bounds | — | 44210 | 46421 | new |
| grimworld_logic::types::hit::tests::test_evade | — | 77460 | 81333 | new |
| grimworld_logic::types::hit::tests::test_example_10_7 | — | 31200 | 32760 | new |
| grimworld_logic::types::hit::tests::test_example_10_8 | — | 22000 | 23100 | new |
| grimworld_logic::types::hit::tests::test_exponent_clamps | — | 46620 | 48951 | new |
| grimworld_logic::types::hit::tests::test_fuzz_no_panic | — | 515420 | 541191 | new |
| grimworld_logic::types::hit::tests::test_halve_first_heavy_hit | — | 88400 | 92820 | new |
| grimworld_logic::types::hit::tests::test_other_classes_take_no_arc | — | 81180 | 85239 | new |
| grimworld_logic::types::hit::tests::test_penetration | — | 13720 | 14406 | new |
| grimworld_logic::types::hit::tests::test_percent_floor_and_zero_hit | — | 22010 | 23111 | new |
| grimworld_logic::types::hit::tests::test_percents | — | 64320 | 67536 | new |
| grimworld_logic::types::hit::tests::test_source_health_refused | — | 15520 | 16296 | new |
| grimworld_logic::types::hit::tests::test_strength_level | — | 22000 | 23100 | new |
| grimworld_logic::types::hit::tests::test_strength_weapon | — | 13720 | 14406 | new |
| grimworld_logic::types::hit::tests::test_target_health_refused | — | 15520 | 16296 | new |
| grimworld_logic::types::hit::tests::test_vectors | — | 915718555 | 961504483 | new |
| grimworld_logic::types::hit::tests::test_weakness | — | 31100 | 32655 | new |
| grimworld_logic::types::hit::tests::test_weapon_base | — | 13720 | 14406 | new |

**Constant inputs make the unit tests' figures low.** The compiler folds a hit whose inputs are constants, so those figures are not the cost of a hit; the benchmarks are. The benchmarks keep their inputs opaque with `#[inline(never)]` wrappers: inlined, a constant blocked hit "cost" about 1,106.

### The per-tick budget line (AC-4)

| | L2 gas |
|---|---:|
| One hit, costliest path, with its straight-line part (`test_cost_pair_hit_one` − `_none`: 60,180 − 13,720) | **46,460** |
| One hit on each path, in a loop: landed 46,310, blocked 46,420, evaded and missed 46,320, spell and bomb 46,310. The spread of at most 110 is the benchmark loop's own match | ≤ 46,420 |
| The most hits a tick computes, counting the action phase before it: 8 awake goblins, one hit each, + a bomb's 7 | **15** (fix loop 1; was 14) |
| 15 × 46,460 | **+ 696,900** |
| 15 hits measured in one loop (`test_cost_hits_per_tick`) | 693,750 |
| CBT-02d's bound | 3,447,872 |
| **The bound with the hit** | **≤ 4,144,772 (2.82 × 1,469,435)** |

**Why at most 15 hits a tick** (design/19 §5.1–§5.3, §5.14 and FX-35; ENG-01 §9.2):
- Each of the 8 awake goblins makes at most one hit: a weapon attack, an attack skill, or a trap its move enters.
- A goblin whose activation resolves in step 1 does not act in step 2.
- The member's action makes at most 7 hits. A bomb's `DISC_1` hits 7, and FX-35 raises the bound to 7 for a tick that runs one. Cinder Ring's `RING_1` reaches 6, and an attack 1.
- The one instant skill allowed between two ticks deals no hit in the MVP (Brace, Warcry, Sidestep: design/03).
- A member's activation lies inside its own action (FX-3), so the action's hits are those of one carrier.
- `DISC_2` and `DISC_3` have no MVP content (FX-21).

**Not in this line:** applying the outcome (steps 5–9) is CBT-05's cost.

## Acceptance criteria

**AC-1: §5.5 steps 1–4 and §5.6 as one scoped pure function; §5.4's rules tested; the inputs from ENG-02 and CBT-04 named.** Done. The inputs are named in the module documentation and on each field.

| §5.4 rule this lot covers | Test |
|---|---|
| Weapon strength 5 × rank, capped | `test_strength_weapon` |
| Strength 3 × level for spell and trap; a bomb's from its recipe | `test_strength_level` |
| Base after requirement, + `ATTACK_BONUS` | `test_weapon_base` |
| Critical +40 % from the back; axe +25 % from rear-side and back; weapon only (FX-27) | `test_arcs_weapon`, `test_axe`, `test_other_classes_take_no_arc` |
| Critical from any arc on a knocked-down or sleeping target, counted once | `test_critical_any_arc` |
| Block from front and front-side only; the flank and the back ignore it; a ranged hit can be blocked | `test_block_by_arc` |
| Evasion: melee hits, every arc (FX-11) | `test_evade` |
| Blind's miss (P) | `test_blind_miss` |
| A knocked-down target neither blocks nor evades (FX-7); a sleeping target's first hit cannot be blocked | `test_block_knocked_down_or_asleep`, `test_evade` |
| Weakness −33 %; critical while weakened deals 107 % | `test_weakness` |
| `DAMAGE_PERCENT` by class and guard; none for bombs and traps | `test_percents` |
| Penetration for weapon and spell only | `test_penetration` |
| The target's armor, `ARMOR` effects, guarded sums and `ARMOR_VS`, for every class | `test_armor_terms` |
| `HALVE_FIRST_HEAVY_HIT`, weapon only (FX-19) | `test_halve_first_heavy_hit` |
| A spell, a bomb or a trap is never stopped | `test_other_classes_take_no_arc` |

**AC-2: every §6 edge concerning a hit tested; no panic on a legal input.** Done.

| §6 edge | Test |
|---|---|
| Armor below 0: 0 before penetration; a negative term counts before the floor | `test_armor_below_zero` |
| Penetration above 100 | `test_penetration` (300, 65,535) |
| The exponent at both clamps | `test_exponent_clamps` (80 and 765; −160 and far below) |
| Percent sum below −100 | `test_percent_floor_and_zero_hit` |
| Damage at both bounds | `test_damage_bounds` (65,535 clamp, 65,532 just below, 0) |
| A 0-damage hit is a hit | `test_percent_floor_and_zero_hit` |
| A block at 0 charges is ended | `test_block_by_arc` |
| §10.7 | `test_example_10_7` |
| §10.8 | `test_example_10_8` |
| §10.9 | Concerns timing, not the hit's computation: none |
| No panic on a legal input | `test_fuzz_no_panic` (256 runs over every field's legal range) |
| What an input may not be | `test_*_refused` (4 tests) |

**AC-3: a vector table for the TypeScript mirror, generated from the tests.** Done.
- **Where it comes from:** `contracts/logic/vectors/hit.jsonl`, 200 lines, printed by `types::hit::tests::test_vectors`. Regenerate it with `snforge test grimworld_logic::types::hit::tests::test_vectors | grep '^{"id"'`, run in `contracts/logic`.
- **Format:** SPK-4's `{"id","case","ok"}`. `case` is the `Serde` of `(Hit, HitTarget)` and `ok` is the `Serde` of `HitOutcome`, each felt in hex; a negative integer is written as P − |v|.
- **Contents:** 26 hand-written edge cases, then 174 legal cases from seeds 1, 2, …
- **Guard:** a Poseidon digest of every case and outcome is pinned in the test, so a rule change fails CI until the file is regenerated.
- **Check:** the independent oracle reproduced all 200 outcomes.

**AC-4: the per-tick budget line, measured, in the report and in ENG-01 §9.2.** Done. See *The per-tick budget line* above, and the new row in ENG-01 §9.2 under *The tick's share*.

**AC-5: D-143; unit tests in their module (D-167); CI green; `gas_budgets.py --check`; `class_sizes.py`.** Done.
- `Arc`, `Hit`, `HitTarget`, `Landed` and `HitOutcome` sit in `types/`. Behaviour is in `HitImpl of HitTrait` and `HitTargetImpl`, checks in `HitAssert`, messages in `errors`. There is no free function in non-test code.
- The unit tests are in the module. `tests/` holds the benchmarks only.
- CI is green on #229, and both tools pass.

## Deviations from the brief

- **The flank is not a separate input.** design/04 defines the flank as the rear-side arc, so `Hit.arc` carries it. A separate boolean could contradict the arc.
- **The arc enum is defined in this lot.** CBT-01's frozen types have no arcs, so `Arc` is new, in `types/hit.cairo`. It is inside the allowlist and freezes nothing of CBT-01's. CBT-03b and ENG-02 should adopt it or say otherwise.
- **The vector table has 200 cases, not 500.** At 500, `test_vectors` exceeds snforge's default step limit; formatting the hex is what costs. A larger table would need `--max-n-steps` in CI or a split test.
- **Nothing else changed:** no file outside the allowlist, no budget raised, no other test's figure moved.

## Escalations

- **Arcs were not in CBT-01's frozen enumerations.** Decided by the orchestrator in fix loop 1: `Arc` is now in `types/combat.cairo`, as an addition.
- **The bound is now 4,144,772 a tick, 2.82× the target** (fix loop 1). It was 2.35× before; this goes to ENG-07, R-2 and STATUS.md's running estimate, which are not my files.

## Open questions

1. **The axe's +25 % on a knocked-down or sleeping target hit from the front arcs.** The brief's wording, "the arc's critical (+40 %, axe +25 %, from any arc on a knocked-down target)", could be read as giving the axe its bonus from any arc as well. design/04 ties the axe's +25 % to the rear-side and back arcs. I applied design/04: the axe gets +25 % only from rear-side and back, and a knocked-down target hit from the front gets the critical alone (`test_axe`).
2. **A critical strike on a sleeping target.** design/04 *Other sources of critical strikes* says "Target is asleep: critical from any arc; the first hit cannot be blocked". design/19 §5.4–§5.6 names only the unblockable first hit, and the brief lists only the knocked-down critical. I applied design/04's rule, since neither of the other documents contradicts it (`test_critical_any_arc`). This needs a confirmation in design/19.
3. **The order of block and evasion.** A target that holds both a block and an evasion, hit in melee from the front: §5.5 step 2 lists "miss, block, evade", so I block first and a charge is spent (`test_evade`). This needs confirmation.
4. **FX-19's halving truncates** (X-3: every division truncates), so a killing blow of 301 on 300 health becomes 150. design/19 does not say whether the halving applies when the hit would kill; FX-19's formula (`2(h ⊖ d) < max`) includes it, and I followed the formula.

## Fix loop 1

**Input.** The Claude-side quality, organisation and determinism audit ([Opus 5.5], D-170) of revision 955aaab: PASS WITH FINDINGS, with 2 minors and 5 notes. The orchestrator checked the minors and decided minor 2. The fixes are in 36bf2ba, after merging origin/main (f36448b, which changed only `PLAN.md`). CI is green on 36bf2ba.

| # | Finding | Done |
|---|---|---|
| Minor 1 | FX-35 raises the bound to 7 for a tick that runs a bomb; it does not exclude the bomb | Re-derived: 8 awake goblins + the member's action, at most a bomb's 7, gives **15**. I checked the derivation: the one instant skill allowed between two ticks deals no hit in the MVP (Brace, Warcry, Sidestep), and a member's activation lies inside its own action (FX-3). `HITS_PER_TICK = 15` and its comment are in `tests/test_hit_cost.cairo`. ENG-01 §9.2's row now reads **+ 696,900 (15 × 46,460) → ≤ 4,144,772 (2.82×)**, with 693,750 measured for 15 hits in one loop. This report's summary, per-tick line and escalation are updated |
| Minor 2 | `Arc`, a combat type CBT-01 lacks | Moved to `types/combat.cairo` as an addition, with the same variants and order; nothing else in the file changed. `types/hit.cairo` and `tests/test_hit_cost.cairo` import it from there. The vector digest is unchanged, so the encoding is the same |
| Note 4 | `MAX_PENETRATION` has two meanings | Renamed `PENETRATION_CAP` in `types/hit.cairo` |
| Note 5 | `test_example_10_7` checks one case twice | Kept as a smoke test, renamed `test_spell_at_equal_strength_and_armor`, with one target. Its comment says §10.7's point (a guard read once, FX-40) belongs to CBT-05's executor tests |
| Note 7 | The vector's field order is not written down | The module documentation of `types/hit.cairo` lists the 28 felts of `case` and the 1 or 4 felts of `ok`, one line per felt, with the variants' indexes |
| Notes 3, 6 | | Not changed: they go to CBT-05 in PLAN, as instructed |

**Commands:**
- `git merge origin/main`: one commit, `PLAN.md` only.
- `scarb fmt` on the three Cairo files, then `scarb fmt --check`: clean.
- `snforge test hit` (in `contracts/logic`): 36 passed, 0 failed. The vector digest is unchanged. Output: `one hit, every path: 46310 to 46420`; `15 hits: 693750; one hit in a loop: 46310`.
- `python3 scripts/gas_budgets.py`, run twice. The first run flagged the renamed test's budget, 32,760, as loose against its measured 22,000, so I set it to 23,100 and ran again. The tool regenerated the three `GAS.md` files and `docs/BUDGETS.md`.
- `python3 scripts/gas_budgets.py --check`: `795 tests, every budget is ceil(1.05 x measured) or lower, 4 files current`.
- `scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build`: finished. `python3 contracts/tools/class_sizes.py`: all 10 classes ok, and their sizes are unchanged.
- `gh pr checks 229 --watch`: every check passed at 36bf2ba; `indexer-node` was skipped.

**Rows that changed** (from `gas_budgets.py --report`; every other test is unchanged):

| Test | Before (955aaab) | After | Budget | Note |
|---|---:|---:|---:|---|
| `test_hit_cost::test_cost_hits_per_tick` | 1029900 | 1076210 | 1130021 | **raised**: `// gas: raised, 15 hits a tick instead of 14 (FX-35 counts a bomb's 7; fix loop 1, minor 1)`. The old budget, 1,081,395, would have left 0.5 % headroom |
| `types::hit::tests::test_example_10_7` → `test_spell_at_equal_strength_and_armor` | 31200 | 22000 | 23100 | renamed, one case instead of two |

**The raise does not show as "raised" in `--report`.** Against origin/main every row of this lot is still "new", so the tool has nothing to compare with. The reason is written above the attribute.

## Fix loop 2

**Input.** Two Claude Sonnet runs at 36bf2ba: the cost run (`sonnet-cbt-03a-sc.md`, PASS WITH FINDINGS, with 2 minors and 2 notes) and the quality run (`sonnet-cbt-03a-sq.md`, PASS, with 5 notes). Also PLAN's items for this loop, from the review (`CBT-03a-review-fable.md`).

**Merge.** I merged origin/main first (cceb807, 24 commits, docs only; nothing under `contracts/` or `scripts/`). The fixes are in 0249b2d. CI is green on 0249b2d (`ci` and `tooling` success; `indexer-node` skipped).

### Minors and PLAN items

| Item | Done |
|---|---|
| SC minor 1: the comment above `test_cost_hits_per_tick` said 14 | It now says 15 (`tests/test_hit_cost.cairo:117`) |
| SC minor 2: GAS.md's commit column differs within the lot (d810243 against be61643) | **Explained, not changed.** `scripts/gas_budgets.py`'s provenance rule (its docstring, lines 35–38): a row keeps its date and commit while its measure and budget do not change. A row that changes takes the merge base of HEAD and origin/main at the run that changed it. The two rows at d810243 are the two whose figures changed in fix loop 1, which ran when origin/main was d810243: `test_cost_hits_per_tick` (15 hits, 1,076,210 / 1,130,021) and `test_spell_at_equal_strength_and_armor` (renamed, 22,000 / 23,100). The other 30 rows are unchanged since be61643 and keep it. Regenerating this loop left the files byte-identical. `--check` verifies both commits as ancestors of origin/main with their dates. Forcing one commit would mean editing the generated file by hand, which the rule forbids |
| SC minor 2, the `raised` note on a test new in this PR | Kept. It is true and harmless; `--report` shows the row as "new", since main has no figure for it yet |
| Review: the PR body's figures | Updated with `gh pr edit`: 15 hits, + 696,900, ≤ 4,144,772, 2.82×, 693,750 measured, and the row 1,076,210 / 1,130,021. A "Fix loops" section was added, and the audit line now follows D-175 |
| Review: `HitTrait::damage`'s precondition | Documented on `damage`: `percent` ≥ −100 and `armor` ≤ `i32::MAX`, either breach panics. `resolve` always meets both; any other caller must meet them or call `resolve` |
| The vector file's check against the code | Not mine: ENG-02's `contracts/logic/vectors/check.py` will do it |

### The Sonnet runs' notes

**Cost run (SC):**
- **SC 3, the 15-hit count is stated, not tested.** Agreed. The count is a derivation from design/19 and design/03 (no hit-dealing instant skill, one carrier per action, one hit per awake goblin), and only a benchmark constant holds it. An executor-side check belongs to CBT-05, which counts the hits it runs. For PLAN.
- **SC 4, 46,460 covers `resolve` alone.** Agreed, and the report says so: building `Hit` and `HitTarget` from the world, and steps 5–9, are CBT-05's. ENG-07 should read 4,144,772 as a floor for the hit path, not its whole cost. For CBT-05 and ENG-07.

**Quality run (SQ):**
- **SQ 1, a sleeping target can evade.** True. The code follows design/19 §5.6 to the letter: only a knocked-down target loses evasion (FX-7), and a sleeping one loses only the block of its first hit. Whether a sleeper should evade is a design question. A one-line change if decided (`&& !asleep` in `stop`'s evasion), but it moves the vectors. For the orchestrator or the owner.
- **SQ 2, "the first hit" is not modelled.** True. `asleep` stands for "asleep before this hit". After a hit, the target notices (§5.5 step 9) and CBT-05 must clear the flag, so only the first hit is unblockable. For CBT-05's brief.
- **SQ 3, open questions 2–4 are frozen in the vectors.** True: the sleeping critical, block before evasion, and FX-19 halving a killing blow. Each follows a document (design/04's line, §5.5's order, FX-19's formula), but design/19 does not confirm them. They should be confirmed and written into design/19 before the TypeScript mirror consumes the vectors. A change moves the vectors, and `test_vectors`' digest will say so.
- **SQ 4, `weapon_strength` duplicates the snapshot's rule.** Already in PLAN for CBT-05 (fix loop 1's note 3). Unchanged here.
- **SQ 5, `assert_valid` panics where §6 says clamp.** Already in PLAN for CBT-05 (fix loop 1's note 6): the executor clamps the scaled `DAMAGE` and `ATTACK_BONUS` before building a `Hit`. Unchanged here.

### Commands

- `git merge origin/main`: cceb807. The merge brought `docs/CAIRO.md` (D-176) and `docs/briefs/COMMON.md` among its docs.
- `scarb fmt --check` in `contracts/logic`: clean after re-wrapping the new comment.
- `snforge test hit` (in `contracts/logic`): 36 passed, 0 failed. The vector digest is unchanged. Output: `one hit, every path: 46310 to 46420`; `15 hits: 693750; one hit in a loop: 46310`.
- `python3 scripts/gas_budgets.py`, then `--check`: `795 tests, every budget is ceil(1.05 x measured) or lower, 4 files current`. `GAS.md` and `BUDGETS.md` did not change, and no row moved.
- **Not single-threaded.** D-176 (CAIRO.md, merged in this loop) asks measured builds to run with `RAYON_NUM_THREADS=1`. My profile refused both `RAYON_NUM_THREADS=1 python3 scripts/gas_budgets.py` and `env RAYON_NUM_THREADS=1 …`, so the run used `scripts/lock.sh`'s default of 4. The figures equal fix loop 1's and CI's, and FND-10, which puts the pin into the tooling and CI, is still todo.
- `gh pr edit 229 --body-file …`: done.
- `gh pr checks 229 --watch`: every check passed at 0249b2d.

**Rows that changed:** none. The code changes are a comment and a doc comment.
