# [GPT-6-Astra] Audit — PR 139 (DES-04) — design, determinism

## Verdict

**FAIL**

Reviewed `4186f53`, including **Fix loop 3** and **For the project manager**.

**No—not as written, even after approving the listed recommendations.** The principal dispatch defects, recovery deadline, potion tag, weapon identity, snapshot packing and signed subtraction are corrected. Two substantive defects remain, plus one executor clarification:

| Missing | Classification | Required disposition |
|---|---|---|
| A consistent rule and representation for **negative guarded armor** | **Document defect, F-20.** The catalogue permits it, but the revised pipeline assumes nonnegative contributions and removes the zero clamp. | Restore signed aggregation and the documented zero floor; specify the guarded aggregate’s encoding and bounds. Prohibiting negative armor instead would require an explicit **PM decision**. |
| A demonstrated **registry-call bound**, including dependency rounds and justified generation bounds | **Document defect, F-16.** Correct record-count arithmetic does not establish the stated call count. | Revise FX-46 with an executable read schedule and its cost. If this is deferred to ENG-05, the **PM must explicitly retain that dependency** rather than approve the current three-call claim as established. |
| Explicit application of false guards to **DAMAGE and TRAP placement** | **Minor document clarification, F-15.** The general guard rule already supplies the intended behavior. | Carry that rule into both executor branches; no new PM design decision is necessary. |

The remaining items are for project-manager disposition after this final loop. The declared field widths fit; that alone does not establish complete semantics or a complete execution budget.

## Coverage

Compared v0.4 with `bd3f35e`, checked all previous findings, read the consolidated PM recommendations, and rechecked the relevant design rules, ENG-01 records, registry interface and implementation. Independently recomputed packing, resource totals and recovery boundaries.

All ten examples’ stated arithmetic checks out. In particular:

- Implicit-hit-first Skullring deals **22**, then applies knock-down.
- The empty-tile Snare placement dispatches independently of actors; its later hit deals **56**, with Crippled through **307**.
- Activated attacks with `(k,n)=(2,1)` and `(3,1)`, started at 50, next act at **52** and **53**.
- The revised guard example retains source health **270** and both targets at **30**.

The examples do not exercise false hit/placement guards or negative armor.

Read-only throughout; no files changed, builds run or independent live CI verification performed.

### Independent recount

| Structure | Recount | Assessment |
|---|---:|---|
| Effect entry | **97 bits** | Correct. |
| Passive | **53 bits** | Correct; two use 106. |
| `SKILL` | **83 + 3×97 = 374 bits** | Fits two parts in the stated limbs. |
| `ITEM` | **72 + 113 = 185 bits** | Fits one part. |
| `MODIFIER` | **8 + 106 = 114 bits** | Fits one part. |
| `ARMOR_SET` | **80 + 106 = 186 bits** | Fits one part. |
| `CASTE` | **243 bits**, including the 32-bit weapon | Correct; fits two parts. |
| `MemberEffects` | **4×56 = 224 bits** | Full `u16` skill ids, four-bit ranks and six-bit charges now coexist with the potion tag. |
| `GoblinTimers` | **124 + 112 + 10 = 246 bits** | Four free bits, 124–127, correctly retained. |
| `MemberBar` | **128 + 8 + 48 + 24 + 24 = 232 bits** | High limb uses 104 of 122; 18 bits remain. |
| `MemberKit` high limb | **75 bits** | 47 remain. |
| Additional type armor in `MemberStats` | **12 low + 42 high = 54 bits** | Fits the stated spaces. |
| Signed damage aggregates | **7×[−18,+18] = [−126,+126]** | Fits `i8` under the declared content restrictions. |

**The proposed packing requires zero additional slots for these declared fields.** F-17’s correction is sound. Optional `MemberMods` would cost **453,524 gas on first allocation**, then **32,072 per overwrite**, plus its unmeasured read cost.

The registry rows also sum correctly:

| Assumptions | Records | Record parts | Read estimate | Capacity batches |
|---|---:|---:|---:|---:|
| `C=5, T=10` | **71** | **119** | **4,284,000** | **3** |
| `C=5, T=0` | **61** | **99** | **3,564,000** | **2** |

Those last figures are batches of **already-known requests**, not demonstrated execution-call bounds. Discovering the requests introduces dependencies, detailed below.

Counting FX-0b separately, the PM checklist contains **44 entries: 38 starred and six unstarred**. The report’s 37-star count groups FX-0b with FX-0; both decisions must be recorded.

## Findings

Historical severity is retained for resolved findings. F-15’s remaining issue is downgraded to minor.

| # | Severity | Final status | Location | Evidence / finding | Required correction or disposition |
|---|---|---|---|---|---|
| **F-1** | major | **Resolved** | 19 §3.4, §3.6, §8 | Generic Skill and Capture remain explicitly represented, with deferred behavior identified. | Decide the listed escalations. |
| **F-2** | major | **Resolved** | 19 §2.1–2.2, §7.2 | The 97-bit entry, signed value-carried durations, empty entries and compound passives remain coherent. | Preserve validation through rank 15. |
| **F-3** | major | **Resolved** | 19 §5.4–5.6 | Weapon-only modifiers and rewards remain separated from spell, item and trap hits. | Preserve the class matrix. |
| **F-4** | major | **Resolved** | 19 §2.4, §10.7 | Guard subjects and the once-per-carrier snapshot are defined; the reordered example remains correct. | Decide FX-40; see F-15 for dispatch clarification. |
| **F-5** | major | **Resolved** | 19 §5.7 | Identity, complete-application refresh, incoming-on-tie and slot eviction remain ordered. | Decide FX-6/13/30/42. |
| **F-6** | major | **Resolved** | [19 §5.2](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:339), §10.9 | The corrected transition yields next act `T+max(k,n+1)`. Checking `k=1…15`, `n=1…20` found no boundary mismatch. Perception, fixed membership and lazy lapse remain specified. | Preserve the completion-tick prohibition alongside the recovery formula. |
| **F-7** | major | **Resolved** | 19 §5.10 | Mining checks interruption after each tick, including tick three, and retains its early stop. | No additional correction. |
| **F-8** | major | **Resolved** | 19 §5.11, §5.14, §10.10 | Placement now dispatches without an actor; payload execution waits for the entrant. Trigger timing, dead-placer lookup and movement-cost sampling remain defined. | Apply the placement guard explicitly, F-15. |
| **F-9** | major | **Resolved** | 19 §2.3; FX-18/35 | Addressing, filtering, clipping and disc counts remain explicit. The new potion-only DISC_1 restriction is escalated under FX-35. | PM must approve that restriction and its budget consequences. |
| **F-10** | major | **Resolved** | 19 §5.8, §5.12 | Counter transitions, independent quick-cast counters, interruption consumption and decay order remain defined. | Decide FX-12/39/43. |
| **F-11** | major | **Previously cited losses resolved; overall inventory qualified by F-20** | [19 §7.2](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:640), §7.3 | The potion tag no longer consumes a skill-id bit; weapon class and damage type are separate; both signed damage bounds are supplied. Scoped sums, quick-cast pairs and caste regeneration remain represented. | The claimed lossless inventory still needs the signed guarded-armor case in F-20. |
| **F-12** | major | **Resolved for previously cited omissions** | 19 §9; REPORT PM checklist | Previously unnumbered choices are escalated. New hit-first ordering and potion-only DISC_1 restrictions are explicitly within FX-45/35. | Do not treat assumed generation bounds as established facts merely by approving FX-46. |
| **F-13** | minor | **Resolved** | 19 §10 | Ten examples now include recovery and actor-free placement; their numerical results check out. | They are examples, not proof of every permitted carrier or passive. |
| **F-14** | major | **Resolved** | 19 §3.4, §5.5, §10.8 | Charge-only oils have unreachable time expiry and consume charges on lethal qualifying hits. | No additional correction. |
| **F-15** | **minor remaining** | **Core defects resolved; clarification remains** | [19 executor](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:565) | Implicit hits, hit-first order, matching modifier sets and actor-free placement are now explicit. However, steps 2 and 5 dispatch placement and damage without mentioning their captured guard; only modifiers and subsequent entries explicitly check it. §2.1 already says an entry applies only when its guard holds. | State that a false DAMAGE guard suppresses that hit, while other independently eligible entries continue; a false TRAP guard places nothing and does not execute its payload. This implements the existing rule, rather than requiring another design choice. |
| **F-16** | major | **Partially resolved** | [19 read bound](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:709); [registry API](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/contracts/logic/src/interface.cairo:96) | **The three-call proof is invalid.** `bundle` accepts explicit `(kind,id)` requests and does not follow references. A fresh reveal can require `LOCATION → SPAWN_TABLE → PACK → CASTE → SKILL`; the next ids come from the preceding response. Neither a cache nor a pre-supplied dependency list is specified. `ceil(records/32)` therefore does not bound calls. Additionally, the one-LANDMARK-per-reveal assumption is not derived from ENG-01’s allowance of three objects per chunk or the quota rules. | Supply a dependency-aware read schedule and justified per-kind bounds, then recost FX-46. ENG-05 confirmation is a remaining dependency, not a completed proof. Any new caching, request-list interface or content restriction needs explicit approval. |
| **F-17** | minor | **Resolved** | 19 §7.2 | The unnecessary-word claim is withdrawn. MemberBar’s spare space accommodates the 96-bit payload, and optional-word allocation/overwrite costs are corrected. | Retain zero-slot repacking as the recommendation, subject to complete field semantics. |
| **F-18** | major | **Resolved** | 19 X-3, §2.2, §5.5 | Scaling differences and the damage exponent are explicitly signed; the exponent clamps to `[−160,+80]`. The interrupt example correctly produces 22 rather than 27. | The newly introduced armor assumption is a separate defect, F-20. |
| **F-19** | minor | **Resolved** | design/15:123 | The passive-catalogue fragment now matches the heading. | No additional correction. |
| **F-20** | major | **New: negative armor contradicts the revised pipeline and inventory** | [passive 41](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:247), [hit step 3](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:405), §6, §7.2 | Passive ARMOR still permits **± armor**, including IN_STANCE and ENCHANTED guards. The hit pipeline now calls every contribution nonnegative, and §6 replaces armor’s zero floor with “cannot happen”. A permitted aggregate such as base armor **35** plus active guarded armor **−40** disproves that assertion even with zero penetration. The two eight-bit guarded snapshot fields have no corresponding signed range/encoding proof. | Restore signed aggregation and `max(0,total armor)` before penetration, preserving design/04. Define the guarded aggregates’ signed representation and validated bounds. Alternatively, restricting the catalogue to exclude these values is a **PM question**, not something CBT-01 may silently decide. |

## Escalations: the auditor's view

Recommendations to the project manager. Agreement is with the stated rule, not with an unproven implementation or cost claim.

| Escalation | Auditor’s view |
|---|---|
| **FX-0 ★** | Agree with the ordering conventions; apply entry guards consistently throughout dispatch. |
| **FX-0b ★** | Choose extrapolation through rank 15, with every scaled bound validated. |
| **FX-1 ★** | Choose step 1, preserving design/02’s pipeline. |
| **FX-2 ★** | Start recharge at resolution, interruption or logical lapse. |
| **FX-3 ★** | Run remaining skill ticks after interruption; retain mining’s separate early stop. |
| **FX-4 ★** | Interrupted adrenaline remains spent. |
| **FX-5 ★** | Choose maximum weapon/activation cost and the proposed landing times, with the now-correct goblin scheduling rule. |
| **FX-6 ★** | Keep the maximum condition deadline. |
| **FX-7 ★** | Choose Wait only, with neither blocking nor evasion while knocked down. |
| **FX-8 ★** | Agree with terminal zero health, complete step-3 processing and mandatory finalization. |
| **FX-9 ★** | Choose summed percentage penetration capped at 100; retain armor’s zero floor before applying it. |
| **FX-10 ★** | Count every unstopped damaging hit, including zero damage and traps. |
| **FX-11 ★** | Choose evasion from every arc; flank bypasses blocks. |
| **FX-12 ★** | Agree with the caps, combat test and decay phase, using a named balance constant. |
| **FX-13 ★** | Choose earliest deadline, lowest slot on ties, and replacement of the goblin’s sole slot. |
| **FX-14 ★** | Agree with single-use traps lasting until trigger/closure and invalid full-chunk placement. |
| **FX-15 ★** | Choose recovery in the activation field; the corrected formula and boundary cases now agree. |
| **FX-16** | Rime Shard should apply Crippled. |
| **FX-17** | Use two heals with the predicate captured before either applies. |
| **FX-18 ★** | Choose movement option (a), tile-targeted bombs with range/LOS, and post-MVP revive/reveal. |
| **FX-19 ★** | Choose final-damage halving on the specified downward crossing, with safe prospective-health subtraction. |
| **FX-20** | Use ARMOR for Shaman shields; defer the other mechanics explicitly. |
| **FX-21** | Exclude larger areas until their complete execution cost is measured. |
| **FX-22 ★** | Add one condition word per member and goblin when the four deferred conditions ship. |
| **FX-23 ★** | Keep all nine armor types; approve the 63 saturation cap explicitly. |
| **FX-24 ★** | Prefer zero-slot repacking, but approve it as lossless only after F-20’s signed guarded-armor representation is settled. |
| **FX-25 ★** | Generic Skill is interruptible without spell-specific Dazed, glyph or quick-cast behavior. |
| **FX-26** | Still prefer immediate seal replacement, matching design/03; price the snapshot exception when Capture is designed. |
| **FX-27 ★** | Agree with weapon-only arcs and default WEAPON scope. |
| **FX-28 ★** | Use recipe-fixed bomb strength and `3 × level` for traps. |
| **FX-29 ★** | Choose lazy logical expiry with recharge dated from `A`, without frozen-actor scans or writes. |
| **FX-30 ★** | Retain the complete later-deadline application, incoming on ties. |
| **FX-31 ★** | Refresh knock-down like other conditions. |
| **FX-32** | Defer the trigger decision; keep the effect non-executable until specified. |
| **FX-33 ★** | Choose centered discs of 19/37 tiles, retaining RING_1 for adjacent foes. |
| **FX-34 ★** | Terrain traps should affect members only. |
| **FX-35 ★** | Accept seven-target bombs and the explicit potion-only DISC_1 restriction, with complete cold/warm budgeting. |
| **FX-36–38** | Unused; no separate decision. |
| **FX-39 ★** | Count eligible casts at start and consume the bonus on interruption. |
| **FX-40 ★** | Choose one guard snapshot before the carrier executes. |
| **FX-41 ★** | Choose perception before selection, fixed membership and no replacement after deaths. |
| **FX-42 ★** | Identify held effects by skill or potion item, independent of caster and belt slot. |
| **FX-43 ★** | Agree with scoped sums and the rune/type/counter exceptions; preserve signed ARMOR semantics. |
| **FX-44** | Unused; no separate decision. |
| **FX-45 ★** | Agree with one hit, hit-first execution, one holding entry and deferred trap payloads; make false-guard dispatch explicit. |
| **FX-46 ★** | Prefer calls containing at most 32 requests, but **do not approve the three-call maximum or quoted total overhead** until dependency rounds and generation bounds are established. |