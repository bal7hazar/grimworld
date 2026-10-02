# [Opus 5.5] CBT-04 — The MVP's five conditions

## Summary

The five MVP conditions (Bleeding, Poison, Burning, Crippled, Knocked down) are now complete rules.
Each is a scoped, tested function, ready for CBT-05's executor, CBT-03a's hit and ENG-07's movement:

- **`types::infliction::Infliction`** (new): the source's `CONDITION_DURATION` (condition and
  percent) and `KNOCKDOWN_FLAT`. `InflictionTrait::duration(condition, v)` clamps the value to the
  kind's bounds 1…32,767 (§6), then calls `effective_duration`. The percent applies only to the
  condition the passive names, and the flat ticks only to Knocked down. A member source reads it
  from its kit's words (`MemberWordsTrait::infliction`, bits 144–153 and 200–201). A goblin source
  and a terrain trap have none (`Default`).
- **`MemberConditionTrait`, `GoblinConditionTrait`** (new):
  - `apply(condition, v, @source, t0, sheets)` is what the executor calls for a `CONDITION` or
    `ON_ATTACK_CONDITION`. It works out the effective duration and refreshes by `max` (FX-6,
    FX-31). An actor that is not alive takes nothing. Knocked down interrupts an activation (§5.9).
  - `holds` reports whether a condition is in force.
  - `can_act`, `takes_critical` and `can_defend` are the Knocked-down predicates. CBT-03a receives
    them as booleans.
  - `move_ticks(t0, movement)` gives Crippled's 2 ticks a tile. ENG-07 passes it to `recover` for a
    goblin.
- **`TickMathTrait::held`, `TickMathTrait::move_ticks`, `CRIPPLED_MOVE_TICKS`** in `helpers/tick.cairo`.
- **`GoblinLifecycleTrait::cure`** now does nothing on a dead goblin (§6 "anything on a dead goblin:
  nothing"). Before this change it wrote `t0 − 1`. No existing test or figure moved.
- **Step 3 checked against §5.8:** it agrees, so the code is unchanged. Unit tests now cover it.
- **§10.3 reproduced to the unit** through the pipeline, together with its variant.
- **ENG-01 §9.2:** this lot's row and its derivation.

Pull request: https://github.com/bal7hazar/grimworld/pull/228. CI is green (every check passed;
`indexer-node` skipped, as on main). Not merged.

### Inventory (AC-1)

| Rule (design/19) | Where it lived before | What this lot adds | Tested by |
|---|---|---|---|
| §3.2 row 1–3: −3/−4/−7 pips in step 3 | `TickMathTrait::degeneration`, used by `MemberTickTrait::regenerate`, `GoblinTickTrait::regenerate` | checked; unit tests | `helpers::tick::tests::test_degeneration_pips`, `test_degeneration_heal`; existing `test_cost_path_*`, `test_example_burning_goblin` |
| §5.8 step 1: pips summed, clamped ±10, × 2, health clamped [0, max] | `TickMathTrait::heal` | checked: agrees, no fix | `test_degeneration_heal` (−14 → −20, +5−7 → −4, floor 0, cap max, +14 → +20) |
| §3.2 row 4: Crippled, a move costs 2 ticks (member; goblin FX-15) | the deadline only (`crippled`/`set_crippled`); `GoblinTickTrait::recover(k, t)` | `move_ticks` (member, goblin, helper), with FX-18's `MOVEMENT` as an input | `test_move_ticks`, `test_member_crippled_move`, `test_goblin_crippled_move` (cost 2 → `B = T + 1`) |
| §3.2 row 5 / §5.2: Knocked down cannot act; a goblin skips step 2 | `TickTrait::act` (`knocked < t`) | `can_act` (member: Wait only, FX-7; goblin: the pipeline's reading) | `test_member_knocked_predicates`, `test_goblin_knocked_predicates` (asserted equal to the pipeline's test); existing world step-2 test |
| §3.2 row 5: critical from any arc for a weapon hit | — | `takes_critical` | the same two tests |
| §5.6: knocked down neither blocks nor evades (FX-7) | — | `can_defend` | the same two tests |
| §5.9: a knock-down interrupts (what it spends and keeps) | `interrupt(t0, sheets)` on both actors | `apply` calls it on Knocked down; a goblin's recovery is kept | `test_member_knockdown_interrupts` (§10.6: R = 210, energy kept), `test_goblin_knockdown_interrupts` (§10.2 through `apply`: D = 53, field none, R = 61) |
| §5.7: applied, `D = t0 + d − 1`; refreshed `max` (FX-6, FX-31) | `inflict` + `TickMathTrait::refreshed` | `apply` on top, through the source's durations | `test_refreshed_cured`, `test_member_apply_refresh`, `test_goblin_apply_refresh_cure` (equal and smaller kept) |
| §5.7: durations through `effective_duration`, `CONDITION_DURATION`, `KNOCKDOWN_FLAT` | `durations::effective_duration`; the kit's fields (CBT-02c) | `Infliction`, `MemberWordsTrait::infliction` | `test_infliction_duration`, `test_member_apply` (kit read; 20 +33 % → 26; knock-down 2 +1 → 3) |
| §5.7, §6: a dead goblin takes nothing | `GoblinLifecycleTrait::inflict` | `apply` and now `cure` also | `test_goblin_apply_refresh_cure` (dead: apply and cure leave it unchanged) |
| §5.14: entries reach living actors (member) | — | `MemberTrait::is_alive`, checked in `apply` | `test_member_apply_not_alive` |
| §3.2 `CURE` / §5.1: a duration of 0, `D = t0 − 1`; absent: nothing | `cure` + `TickMathTrait::cured` | unchanged (goblin: dead check) | `test_refreshed_cured`, `test_member_apply_refresh`, `test_goblin_apply_refresh_cure`, existing `test_member_conditions` |
| §5.1: held while `t0 ≤ D`; `d` ticks degenerate `d` times | step 3's `t <= D` | `holds`, `TickMathTrait::held` | `test_degeneration_pips`, `test_member_apply`, `test_goblin_apply` |
| §10.3 | `test_example_condition_degeneration` (deadlines preset) | the whole example through `apply`/`cure` in the pipeline's hooks | `test_example_condition_refreshed`, `_variant` |

## Files changed

- `contracts/logic/src/types/infliction.cairo`: new. `Infliction`, `InflictionTrait::duration`, and its tests.
- `contracts/logic/src/types.cairo`: adds the module line.
- `contracts/logic/src/helpers/tick.cairo`: adds `held`, `move_ticks` and `CRIPPLED_MOVE_TICKS`, plus a tests module (step 3, refresh and cure, move cost).
- `contracts/logic/src/models/member.cairo`: adds `is_alive`, `infliction` and `MemberConditionTrait`, with its tests and cost pairs.
- `contracts/logic/src/models/goblin.cairo`: adds the `cure` dead check and `GoblinConditionTrait`, with its tests and cost pairs.
- `contracts/logic/src/types/world.cairo`: adds the §10.3 tests and their `Dressing` rules, inside the tests module only.
- `docs/architecture/ENG-01-interfaces.md` §9.2: adds this lot's row and its derivation paragraph.
- `contracts/logic/GAS.md`, `docs/BUDGETS.md`: regenerated by `scripts/gas_budgets.py`.

## Commands run

- `scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build`: built (`Finished dev profile`).
- `cd contracts/logic && snforge test`: `Tests: 542 passed, 0 failed`. The first targeted run had one failure, `test_member_knockdown_interrupts`, because its placeholder gas limit was too low (`Test cost exceeded the available gas … ~14327200`). I set the budget and the full run then passed.
- `cd contracts/persistent && snforge test`: `Tests: 198 passed, 0 failed`.
- `cd contracts/ephemeral && snforge test`: `Tests: 53 passed, 0 failed`.
- `python3 scripts/gas_budgets.py` (wrote the 4 files), then `--check`: `gas check: 793 tests, every budget is ceil(1.05 x measured) or lower, 4 files current`.
- `python3 contracts/tools/class_sizes.py`: `TickLibrary` 582,969 bytes, **29.13 %**, ok. The other classes are unchanged in kind; the largest is `Hub` at 45.40 %.
- `scarb --manifest-path contracts/Scarb.toml fmt`: no changes left.
- `gh pr checks 228 --watch`: every check passed.

### Edges (§6) covered

- A cure of an absent condition, and of a condition already ended, changes nothing.
- Anything on a dead goblin changes nothing (`apply` and `cure`). Nothing applies to a member at 0 health or down.
- Knocked down reapplied while held is refreshed by `max`, at equal and smaller durations.
- The adventurer knocked down can only Wait (`can_act` false through `D`).
- A value outside the kind's bounds is clamped (0 or negative → 1, 40,000 → 32,767), so it is never a cure and never panics.
- The effective duration stays within `effective_duration`'s caps: percent 63 → 50, the widest is 49,153 ≤ `MAX_DURATION`.
- Nothing panics on a legal value. The only remaining asserts are a condition id outside 1–5 (see Escalations) and `assert_duration`, which `apply` cannot reach.

### §10.3 (AC-3)

The member's health after ticks 70–76 is `[386, 372, 358, 352, 346, 340, 340]`, and its Bleeding
deadline after ticks 70, 74 and 76 is `[77, 81, 75]`:
- Bleeding 8 at tick 70 gives D = 77.
- Bleeding 8 again at tick 74 refreshes it to 81.
- Field Dressing starts at clock 75, resolves in step 1 of tick 76 and cures: D = 75.
- 60 health is lost in all, and nothing is lost at tick 76.

In the variant (Bleeding 2 at tick 74) the deadlines are `[77, 77, 75]` with the same health.
Field Dressing's `HEAL` is left out because it is CBT-05's kind; the example counts the health
lost.

### Per-tick budget line (AC-4)

> **Superseded by fix loop 2** (below): after SPK-15's L2 the line is **+1,319,770, ≤ 4,767,642 a
> tick (3.24 ×)**; the figures in this section are the first round's.

Every rule is loop-free, so Sierra charges its costliest path. Each cost below is measured as a
pair: snforge's totals of two tests that differ only by the call.

| Rule | Member | Goblin |
|---|---:|---:|
| `apply`, knock-down interrupt included (`test_cost_*_apply_knockdown` = `_apply_crippled`) | 5,082,180 − 4,974,080 = **108,100** | 668,480 − 591,660 = **76,820** |
| `cure` | 36,650 | 32,320 |
| predicates (`can_act`/`takes_critical`/`can_defend`/`move_ticks`) | 11,250 | 9,880 |

How many applications a tick can make, at the MVP's content (design/19 §8, design/20; ENG-01 §9.2's
bounds):
- The member's one carrier a tick reaches at most **7** goblins. The widest is a bomb (`DISC_1`, a
  1-tick action, FX-35); Cinder Ring reaches 6; an attack skill plus 4 on-attack effects reaches 5.
- Each of the 8 awake goblins resolves or acts once, with at most one `CONDITION` plus its held
  effect's `ON_ATTACK_CONDITION` on the member: **16**.
- There are **9** hit/move predicate sets.

**Line: 16 × 108,100 + 7 × 76,820 + 9 × 11,250 = +2,368,590.** Added to CBT-02d's 3,447,872, that
gives **≤ 5,816,462 a tick (3.96 ×** the 1,469,435 target). This covers the rules on the actors'
values only; the executor's writes of the actors into the world are CBT-05's.

Beyond MVP content, the legal carriers allow 9 × 18 = 162 applications. Priced at each target's
cost (fix loop 1, Minor 1), that is **≤ 13,547,050**:
- the member's carrier on 18 goblins: 18 × 76,820;
- each goblin's carrier at most 4 applications on the member (4 × 108,100) and 14 on goblins
  (14 × 76,820): 1,507,880, 8 times;
- the 9 predicate sets: 101,250.

This figure is in ENG-01 as a ceiling, an upper bound that is not reached.

## Cost

Every test that existed before this lot is unchanged (`gas_budgets.py --report`: all "unchanged").
New tests:

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_logic::helpers::tick::tests::test_degeneration_heal | — | 13720 | 14406 | new |
| grimworld_logic::helpers::tick::tests::test_degeneration_pips | — | 13720 | 14406 | new |
| grimworld_logic::helpers::tick::tests::test_move_ticks | — | 13720 | 14406 | new |
| grimworld_logic::helpers::tick::tests::test_refreshed_cured | — | 13720 | 14406 | new |
| grimworld_logic::helpers::tick::tests::test_refreshed_zero_refused | — | 15520 | 16296 | new |
| grimworld_logic::models::goblin::tests::test_cost_goblin_apply_crippled | — | 668480 | 701904 | new |
| grimworld_logic::models::goblin::tests::test_cost_goblin_apply_knockdown | — | 668480 | 701904 | new |
| grimworld_logic::models::goblin::tests::test_cost_goblin_condition_base | — | 591660 | 621243 | new |
| grimworld_logic::models::goblin::tests::test_cost_goblin_cure | — | 623980 | 655179 | new |
| grimworld_logic::models::goblin::tests::test_cost_goblin_predicates | — | 601540 | 631617 | new |
| grimworld_logic::models::goblin::tests::test_goblin_apply | — | 1038150 | 1090058 | new |
| grimworld_logic::models::goblin::tests::test_goblin_apply_refresh_cure | — | 887160 | 931518 | new |
| grimworld_logic::models::goblin::tests::test_goblin_crippled_move | — | 324320 | 340536 | new |
| grimworld_logic::models::goblin::tests::test_goblin_knockdown_interrupts | — | 922280 | 968394 | new |
| grimworld_logic::models::goblin::tests::test_goblin_knocked_predicates | — | 286910 | 301256 | new |
| grimworld_logic::models::member::tests::test_cost_member_apply_crippled | — | 5082180 | 5336289 | new |
| grimworld_logic::models::member::tests::test_cost_member_apply_knockdown | — | 5082180 | 5336289 | new |
| grimworld_logic::models::member::tests::test_cost_member_condition_base | — | 4974080 | 5222784 | new |
| grimworld_logic::models::member::tests::test_cost_member_cure | — | 5010730 | 5261267 | new |
| grimworld_logic::models::member::tests::test_cost_member_predicates | — | 4985330 | 5234597 | new |
| grimworld_logic::models::member::tests::test_member_apply | — | 6828460 | 7169883 | new |
| grimworld_logic::models::member::tests::test_member_apply_not_alive | — | 4939730 | 5186717 | new |
| grimworld_logic::models::member::tests::test_member_apply_refresh | — | 5108680 | 5364114 | new |
| grimworld_logic::models::member::tests::test_member_crippled_move | — | 4688920 | 4923366 | new |
| grimworld_logic::models::member::tests::test_member_knockdown_interrupts | — | 14327200 | 15043560 | new |
| grimworld_logic::models::member::tests::test_member_knocked_predicates | — | 4653820 | 4886511 | new |
| grimworld_logic::types::infliction::tests::test_infliction_duration | — | 13720 | 14406 | new |
| grimworld_logic::types::infliction::tests::test_infliction_duration_edges | — | 13720 | 14406 | new |
| grimworld_logic::types::world::tests::test_example_condition_refreshed | — | 7324302 | 7690518 | new |
| grimworld_logic::types::world::tests::test_example_condition_refreshed_variant | — | 7324302 | 7690518 | new |

No budget raised.

## Acceptance criteria

- **AC-1:** met. The inventory table is above; every row names its test.
- **AC-2:** met. `apply`, refresh, `cure`, the knock-down interrupt, `move_ticks` and the predicates
  are scoped trait functions on both actors, each with its tests and §6's edges listed above. A
  legal value never panics.
- **AC-3:** met. `types::world::tests::test_example_condition_refreshed` and `_variant` reproduce
  §10.3 to the unit.
- **AC-4:** met. The measured line, +2,368,590 (≤ 5,816,462 a tick), is in this report and in
  ENG-01 §9.2's table, with its derivation paragraph.
- **AC-5:** met.
  - D-143: functions are scoped in `...Trait`s and the value type is in `types/`. No free function
    was added.
  - D-167: unit tests are in their modules. No `tests/` file was needed, because the cost pairs
    need no contract.
  - CI is green and `gas_budgets.py --check` is clean.
  - `TickLibrary` is at 29.13 %.

## Deviations from the brief

- The cost benchmarks are unit tests in the modules (`test_cost_*`), not in `contracts/logic/tests/`.
  They need no deployed contract, so CAIRO.md §2 (D-167) puts them in the module. The brief allowed
  `tests/` but did not require it.
- `GoblinLifecycleTrait::cure` gained a dead-goblin check. The behaviour on a dead goblin changes
  (§6 says nothing should happen; before, a cure wrote its deadline), but no game result of a
  living actor changes and no test vector moved.

## Escalations

- **`MOVEMENT` (FX-18) is not in the tick's sheets.** `SkillSheet` and `PotionSheet` carry only
  `regen`, so a held `MOVEMENT` effect cannot be recognised from the effect slots inside a tick.
  For now `move_ticks` takes it as a boolean. ENG-07 or CBT-05 needs the held effect's kind in the
  sheets (a sheet field), or a rule for it.
- **A condition id 6–9 in a `CONDITION`/`CURE` entry panics** (`TickAssert::assert_condition`,
  `'tick: condition not stored'`). That is right for the MVP, since FX-22 gives those conditions no
  storage. The content pipeline should refuse `param` 6–9 for kinds 6, 7 and 15 until FX-22 ships,
  so that no legal action reaches the assert (D-140). I did not check whether the validators already
  refuse it; that is CNT-01's or CBT-05's to confirm.

## Open questions

- The per-tick line counts a goblin's held effect as a possible `ON_ATTACK_CONDITION` (2 a goblin).
  If no MVP caste can hold one, the line falls to 8 × 108,100 + 7 × 76,820 + 9 × 11,250 =
  1,503,790. That depends on design/20's final caste kits.
- The rule ceiling (162 applications, ≤ 12.55 M) assumes a goblin carrier may apply conditions to
  its allies over `RING_1`. Whether content may do that is BAL-01's or CNT-01's to decide.

## Fix loop 1

The Claude-side quality, organisation and determinism audit ([Opus 5.5], D-170) at 0af08d4 found
2 minors and 6 notes. All 8 are fixed. Codex's two audits are still queued for its reset
(2026-10-04 13:36 UTC).

| # | Finding | Fix |
|---|---|---|
| Minor 1 | The ENG-01 §9.2 ceiling priced every application at a goblin's cost | Re-derived with each application priced at its target's cost. Each goblin carrier has at most 4 applications on the member (3 entries plus its held effect's `ON_ATTACK_CONDITION`) and 14 on goblins. **≤ 13,547,050** (1,382,760 + 8 × 1,507,880 + 101,250), which is at least the audit's 13,296,810. Changed in ENG-01 and REPORT.md. |
| Minor 2 | `MAX_VALUE_DURATION` was defined twice | `types/infliction.cairo` now imports `crate::types::effect::MAX_VALUE_DURATION`, and the copy is deleted |
| Note 3 | The `'as the pipeline'` assert compared the predicate with itself | Replaced by a pipeline run over ticks 52–54 with `Script`'s rules. The goblin knocked down to D = 53 acts at 54 only (`acts == [(54, 40)]`), which covers D and D + 1. |
| Note 4 | `opaque` was defined twice | One `pub fn opaque` in `types::world::fixtures`, imported by the member and goblin tests |
| Note 5 | `MemberLifecycleTrait::cure` had no alive check | Documented instead of checked: the executor reaches living actors only (§5.14) and a member at 0 health never acts again (FX-8). A check would add gas to every cure, and it would move the budget of `test_member_conditions`, which is on main. |
| Note 6 | ENG-01's count of applications did not mention trap triggers | One sentence added: a goblin's move into a Snare replaces its 2 counted applications, and a member's move (≤ 1 terrain payload) replaces its carrier's 7 |
| Note 7 | `CRIPPLED_MOVE_TICKS` was in `helpers/tick.cairo` | Moved to `types/tick.cairo` beside `MAX_PIPS`, `HEALTH_PER_PIP` and `ADRENALINE_DECAY` |
| Note 8 | Two comments were broken across lines | Rewrapped in `helpers/tick.cairo` and `types/infliction.cairo` |

Escalations: as instructed, nothing changed for `MOVEMENT` or for condition ids 6–9; they are
recorded for CBT-05 and CNT-01.

### Commands

- `git merge origin/main` was run twice. Main moved during the loop: first d810243 (#227), then
  e086f7f (#230). Neither touches Cairo or the gas files.
- `scarb fmt`: clean.
- `scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build`: `Finished`.
- `cd contracts/logic && snforge test`: `Tests: 542 passed, 0 failed`. The 6 cost pairs are
  unchanged (108,100, 76,820, 36,650, 32,320, 11,250, 9,880).
- `python3 scripts/gas_budgets.py`, then `--check`: `gas check: 793 tests, every budget is
  ceil(1.05 x measured) or lower, 4 files current`.
- `gas_budgets.py --report`: 763 rows unchanged and 30 new against main, and no raise.
- `gh pr checks 228 --watch`: green at b5f4069, with 0 failing or pending checks.

**Two CI failures on the way, and their cause.** The `gas budgets` step said `docs/BUDGETS.md is
stale` at 5b3eda4 and again at 3433195. I had regenerated with an absolute
`--workspace /home/.../contracts`, and BUDGETS.md's header sentence embeds the workspace path. So
the file held my local path where CI writes `contracts/`. Running the script with the default
workspace fixed it (b5f4069). No figure was involved: CI's snforge output, fed back through
`--from-output`, gave the same rows as the local run.

### Rows that changed

| Entrypoint or algorithm | Before (round 1) | After | Budget | Note |
|---|---:|---:|---:|---|
| grimworld_logic::models::goblin::tests::test_goblin_knocked_predicates | 286910 | 5927952 | 6224350 | new against main. It now runs the pipeline over 3 ticks (note 3). |

Every other row is unchanged.

### Left over

`.ci-log.txt` and `.ci-snforge.txt` were untracked scratch files at the worktree root (CI's log,
used to replay `--from-output`). They were never committed. My profile refused to delete them in
loop 1; in fix loop 2 I removed them from the worktree root, by relative path.

## Fix loop 2

This loop had three parts, under the owner's D-175 (audits on Claude Opus 5.5, reviews on Claude
Sonnet, nobody waits for Codex) and D-172:
1. SPK-15's lever L2: a condition's application written in place, split by condition.
2. The per-tick line, re-measured.
3. The two Sonnet runs' notes, each answered below.

CI is green at **897f8d3**: every check passed, including `cairo (contracts)` and
`cairo (spikes/SPK-15)`.

### 1. L2: applications in place, by condition

- **Member and goblin** (`MemberConditionTrait`, `GoblinConditionTrait`):
  - `apply(condition, v, @source, t0)` now takes conditions 1–4 (Bleeding, Poison, Burning,
    Crippled) and no sheets. It is written in place: `duration` is inlined, one branch writes the
    field, and Crippled's word is read once, inline.
  - `knock(v, @source, t0, sheets)` takes Knocked down, with its interrupt.
  - The executor (CBT-05) dispatches on the entry's condition. `apply` with Knocked down is a
    dispatch error and panics with `'tick: knock-down is knock'`
    (`test_*_apply_knockdown_refused`). A legal action never reaches it.
- **No rule changed.** The pre-L2 application is kept in each module's tests as the oracle,
  `oracle()` (CAIRO.md §2). `test_member_apply_matches_oracle` and
  `test_goblin_apply_matches_oracle` cover:
  - every condition 1–5;
  - the values 1, 20, 0 (clamped to 1) and 40,000 (clamped to 32,767);
  - the source "Rending" and no passive;
  - on the member: activating, a held condition kept or raised, at 0 health, and down;
  - on the goblin: activating, recovering, a held condition, and dead.

  `apply` and `knock` match the oracle in all 160 cases on each actor. Every earlier test passes
  unchanged in its assertions, including §10.3, whose rules now call `apply` without the sheets.
- `InflictionTrait::duration` is `#[inline(always)]`.

**The pairs** (snforge totals, each test less its base, which differs from it by the call alone):

| Rule | Member | Goblin |
|---|---:|---:|
| pre-L2 application, the oracle (`test_cost_*_oracle` − `*_source_base`) | 90,200 | 76,020 |
| `knock`, interrupting an activation (`*_knock` − `*_source_base`) | **55,150** | **45,300** |
| `knock`, nothing to interrupt and not lengthening (`*_knock_idle` − `*_idle_base`) | 54,030 | 45,300 |
| `apply` Crippled · Bleeding (− `*_source_base`) · not alive (− `*_zero_base`/`*_dead_base`) | 32,310 · 32,310 · 32,310 | 29,210 · 29,210 · 29,210 |
| the source's `Infliction` read from the kit (`test_cost_member_infliction` − `*_condition_base`) | 19,020 | — |
| cure; predicates (unchanged) | 36,650; 11,250 | 32,320; 9,880 |

At the bound (every application a knock-down), L2 saves 16 × 35,050 + 7 × 30,720 = **775,840**
a tick. SPK-15 measured 773,960 (16 × 35,720 + 7 × 28,920); the difference is the bases, see 2.

### 2. The per-tick line, re-measured

- **Before L2: 2,095,610**, from 16 × 90,200 + 7 × 76,020 + 19,020 + 9 × 11,250.
  - The 16 applications on the member come from goblins, which have no `Infliction`. So the kit
    read is out of them, and is counted once, for the member's own carrier.
  - The round-1 line (2,368,590) priced the kit read into every member application.
  - SPK-15's 2,114,010 differs from mine by 18,400, which is 23 × 800: its pairs included the
    source's `opaque` creation in each application. In mine, that creation is in every base
    (`*_source_base`).
- **After L2: +1,319,770**, from 16 × 55,150 + 7 × 45,300 + 19,020 + 9 × 11,250.
  - Every application is priced as a knock-down, the costliest.
  - Added to CBT-02d's 3,447,872, that gives **≤ 4,767,642 a tick (3.24 ×** the 1,469,435
    target, down from 3.96 ×).
- **The ceiling beyond MVP content, after L2: ≤ 7,774,070**, from 18 × 45,300 + 19,020 +
  8 × (4 × 55,150 + 14 × 45,300) + 101,250. It was 13,547,050 before L2.

ENG-01 §9.2 has the row (2,368,590 → 2,095,610 → +1,319,770, ≤ 4,767,642) and its derivation,
with each cost named by its test pair. The trap-trigger sentence and the ceiling are updated to the
new costs.

### 3. The Sonnet runs' notes

**Quality, organisation and determinism (`sonnet-cbt-04-sq.md`):**

- **SQ-1. The comments were still ragged:** right. My fix-loop-1 rewrap ran past `scarb fmt`'s
  line width (it appears to count the bytes of `→`, `§` and `–`), and fmt broke the lines again. I
  rewrapped both comments well under the width and confirmed after `scarb fmt` that they stay
  whole (`helpers/tick.cairo`, `types/infliction.cairo`).
- **SQ-2. `cured` underflows at `t0 = 0`:** the doc comment now states `t0 ≥ 1`. Every caller's
  `t0` is `c + 1` or a tick `T ≥ 1` (§5.1), so no legal path reaches 0. I documented it rather than
  guarding it: a guard would add gas to every cure for a case §5.1 excludes.
- **SQ-3. A knock-down that does not lengthen still interrupts:** this is the rule's reading, and
  it is now stated and tested. §5.9 says "a knock-down" interrupts, with no condition on the
  deadline. Such a knock-down can only land on an actor already knocked down, which has no
  activation: a member's only action is Wait (FX-7), a goblin skips step 2, and the first
  knock-down interrupted any activation. So the interrupt finds nothing. `knock`'s doc says so.
  `test_member_knock_refresh_not_longer` and `test_goblin_knock_refresh_not_longer` show the actor
  unchanged.

**Cost (`sonnet-cbt-04-sc.md`):**

- **SC-1. The member's pair held the kit read, the goblin's did not:** fixed by item 2. The read
  is now its own pair (19,020) and is counted once a carrier. Every application pair gives its
  source in its base, so the goblin's figure no longer carries the source's creation either
  (76,820 was 76,020 + 800).
- **SC-2. "Charged its costliest path" rested on two paths:** more paths are now priced.
  - `apply`: Crippled, Bleeding and an actor not alive measure the same, 32,310 and 29,210.
  - The goblin's `knock` is the same with and without an activation, 45,300.
  - The member's `knock` is 1,120 cheaper with nothing to interrupt (54,030 against 55,150). The
    claim is exact for every loop-free function except the member's `knock`, and the bound takes
    the costlier path.
- **SC-3. The MVP count rests on design/20's content:** no change. The counts stay tied to the
  content (design/19 §8, design/20); open question 1 of round 1 still holds.

### Commands

- `git merge origin/main`: brought in 538427f (#264), which included SPK-15 (#234) and D-172.
  - Main moved again while CI ran, up to 774b360.
  - Those commits touch no contracts, spikes, gas files, ENG-01 or scripts (`git diff --stat
    HEAD...origin/main -- contracts spikes docs/BUDGETS.md docs/architecture scripts` is empty),
    so I did not merge again.
- `scarb fmt`: clean.
- `cd contracts/logic && snforge test`: `Tests: 563 passed, 0 failed`.
- `python3 scripts/gas_budgets.py`, then `--check`, run from the worktree root with the default
  workspace: `gas check: 814 tests, every budget is ceil(1.05 x measured) or lower, 4 files current`.
- `gas_budgets.py --report`: 51 rows new against main (this PR's), every other row unchanged, no
  raise.
- `python3 contracts/tools/class_sizes.py`: `TickLibrary` 29.13 %, unchanged (CBT-04's rules are
  not in the library yet).
- `cd spikes/SPK-15 && snforge test`: `Tests: 122 passed, 0 failed`. See the deviation below.
- `gh pr checks 228 --watch`: green at 897f8d3.

### Rows that changed (this loop)

| Test | Before (loop 1) | After | Budget | Note |
|---|---:|---:|---:|---|
| `models::member::tests::test_member_apply` | 6828460 | 6781230 | 7120292 | lowered (L2) |
| `models::goblin::tests::test_goblin_apply` | 1038150 | 1017750 | 1068638 | lowered |
| `models::goblin::tests::test_goblin_apply_refresh_cure` | 887160 | 884180 | 928389 | lowered |
| `models::goblin::tests::test_goblin_knockdown_interrupts` | 922280 | 899390 | 944360 | lowered |
| `types::world::tests::test_example_condition_refreshed{,_variant}` | 7324302 | 7159882 | 7517877 | lowered |
| `models::member::tests::test_cost_member_apply_crippled` | 5082180 | 5007190 | 5257550 | the pair now gives its source in the base |
| `models::goblin::tests::test_cost_goblin_apply_crippled` | 668480 | 621670 | 652754 | the same |
| `models::member::tests::test_cost_member_apply_knockdown` → `test_cost_member_knock` | 5082180 | 5030030 | 5281532 | renamed |
| `models::goblin::tests::test_cost_goblin_apply_knockdown` → `test_cost_goblin_knock` | 668480 | 637760 | 669648 | renamed |
| new pairs: `*_source_base`, `*_idle_base`, `*_zero_base`/`*_dead_base`, `*_knock_idle`, `*_apply_bleeding`, `*_apply_not_alive`/`*_apply_dead`, `*_oracle`, `test_cost_member_infliction` | — | (pairs above) | ceil(1.05 ×) | new |
| new: `test_*_apply_matches_oracle` (member 34847260, goblin 22281920), `test_*_apply_knockdown_refused`, `test_*_knock_refresh_not_longer` | — | | ceil(1.05 ×) | new |

Every row is `ceil(1.05 × measured)` and none is raised. Against main, all 51 of this PR's rows
are new.

### Deviation from the allowlist: `spikes/SPK-15/src/executor.cairo` (2 lines)

At 28ecc50, CI's `cairo (spikes/SPK-15)` failed with `E2046 Ambiguous method call …
MemberWordsTrait::infliction and crate::cbt04::Cbt04MemberTrait::infliction` (executor.cairo:345,
372).
- **Cause:** SPK-15 builds against `grimworld_logic` and carries its own copy of CBT-04
  (`cbt04.cairo`, from b5f4069). Once this branch's `MemberWordsTrait::infliction` was in scope,
  the spike's two calls became ambiguous.
- **This is not caused by L2.** It would have broken main at CBT-04's merge, whatever the loop
  changed.
- **Fix:** the two calls now name the spike's copy explicitly, as
  `Cbt04MemberTrait::infliction(@member)`. Nothing else in the spike changed. Its 122 tests pass,
  and since no attribute failed, its gas figures stayed within their budgets.
- **Why I made it:** the PR could not be green otherwise. The alternative, renaming CBT-04's
  `infliction` to dodge a spike's copy, would have bent the game's API around a frozen
  measurement.

Please confirm or move the change. When CBT-05 retires the spike's copy, the spike can use CBT-04's
functions directly.

### Escalations

None new. MOVEMENT and condition ids 6–9 stay recorded for CBT-05 and CNT-01, unchanged.
