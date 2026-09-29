# [GPT-6-Astra] Audit — PR 179 (DES-06) — design, consistency

## Verdict

**PASS.** Re-audited `f3706f3`. DES06-1 through DES06-7 are resolved; no new findings.

**Yes: D-157 G’s design-level capacity proof is complete once the escalations are decided consistently with the proved B bounds.** Current CBT-01 acceptance does not guarantee that every aggregate fits. The approved restrictions, flattening checks and acceptance tests must still be implemented before production snapshots. An alternative that expands B requires its corresponding proof to be revised.

## Coverage

Reviewed the fix-loop-2 diff and implementer’s report against the brief, D-157, the referenced design documents, CBT-01’s source and carrier validators, snapshot packing, caste packing, duration arithmetic, and ephemeral state layouts.

Independently recounted the totals using the checked-in integer exponent table. All 15 caste comparison rows in §2.4 reproduce exactly. All eleven castes have sheets; remaining skill values, behavior and phase gaps are explicitly escalated. The design/05 and design/19 edits remain consistent cross-references plus D-157 E’s already-approved decay constant.

No files were written. `git diff --check origin/main...HEAD` passed. Contract tests and gas measurements were not rerun; this is a documentation audit.

The material capacity results are:

| Quantity | Independent recount | Capacity conclusion |
|---|---|---|
| Sources | 15 two-passive modifiers + 2 single-passive set bonuses = **17 sources, 32 passives** | Includes held slots, fixed boss modifiers, insignias and runes |
| Unrestricted passive sum under A | **−1,048,576…+1,048,544** | Explains the required restrictions |
| Health | A **−1,048,476…+1,049,024**; B equipment **−525…+575**, total **−425…+1,055** | Upper end fits `u16`; DS-2 resolves the floor, DS-3 the unsigned equipment field |
| Attainable health | **1,020** with piece-specific insignias; **1,055** under DS-23(b) | Both fixtures explicitly depend on the decision |
| Energy / energy regeneration | B **−15…130** energy; **390 thirds**; regeneration **−5…7** | Fits after DS-2’s floor policy |
| Snapshot health regeneration | B **−7…2**, encoded **3…12** | Fits the intended encoding |
| Member regeneration in play | A **−64…285**; B **−61…42** | `i16` before clamping; `i8` cannot cover A |
| Goblin regeneration in play | Packed A **−34…255**; legally restricted **−34…20** | `i16` before clamping |
| Armor | Unguarded **−8,160…8,720**; guarded buckets **±126** | Fits the checked `i16` and two `i8` fields |
| Armor at a hit | **−8,412…10,055**; packed-field envelope **−10,247…11,330** | `i32` covers both |
| Armor by type | A **1,048,574**; B **149**, saturated to **63** | Wide sum before six-bit storage |
| Ranks / weapon damage / strength | Rank **15**; personalized maul **32**, one-handed maximum **21**; weapon strength **75**, spell/trap strength through byte levels **765** | Fits stored fields or the specified wide computation |
| Damage percentages | Each bucket **±126**; both guards together **±216**; hit total **−249…281** | Stored `i8` buckets; `i16` at use |
| Penetration | Stored **252**; hit total **967** | `u8` storage, `u16` computation, clamp to 100 |
| On-hit gains | Life steal **25**; energy **5** | Fits bytes |
| Duration bonuses | A condition **65,534**; enchantment and knock-down **1,048,544** each | DS-5’s wide sums and saturation to **50 / 50 / 3** fit |
| Glyphs / skill energy cost | Four glyphs **1,020**; B cost **−1,035…255** | `i32`, then floor |
| Adrenaline | Member **1,020** quarters; goblin **252** | Fits `u16` / `u8`; DS-18 checks goblin skill costs |
| Goblin health | A **3,394,713**; B **51,800**; multiplication **339,471,300** | DS-18 makes health fit `u16`; intermediate fits `u32` |
| Goblin energy / armor | Energy **255 thirds**, pre-clamp regeneration addition **510**; armor **573** | Widen before addition |
| Hit base and product | A base **163,836**, product **42,948,624,384**; B base **98,556**, product **23,691,581,172** | `u64` required |
| Restricted hit / damage entry | DS-20(b) product **8,656,519,168**; `DAMAGE` product **8,589,672,448** | Both still require `u64` |
| Subsequent damage arithmetic | After shift **655,344**; percentage product **249,686,064** | Fits the stated intermediate before final damage clamp |
| Remaining state | Charges **63**, held rank **15**, counters through **255** before reset; effective durations **65,535 / 49,153**; deadline **268,435,455** | Fits the documented fields and clock guard |

The remaining discrete fields—quick-cast pairs, potion tags and belt slots, belt counts, activation states, weapon ticks/range, skill headers, trap parameters and caste identifiers—also fit their inventoried layouts.

## Findings — final status

Severity below is the finding’s severity entering this re-audit; all are closed.

| # | Severity | Location | Finding / status | Evidence | Suggested fix |
|---|---|---|---|---|---|
| DES06-1 | major | [§1.6](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-179/docs/design/20-castes.md:169) | **Resolved:** hit arithmetic covers accepted entry combinations. | Three `ATTACK_BONUS` entries and the caste’s `u16` weapon produce base 163,836; the recomputed product requires `u64`. DS-20 explicitly carries the possible restriction. | None in DES-06. |
| DES06-2 | major | [§1.4](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-179/docs/design/20-castes.md:152) | **Resolved:** simultaneous damage guards are counted. | Five modifiers can each contribute 18 to both guards; two single-passive set bonuses give ±216, then −249…281 with combat rules. | None in DES-06. |
| DES06-3 | minor | [§1.9](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-179/docs/design/20-castes.md:220) | **Resolved:** the omitted state quantities are inventoried. | Charges, held ranks, counters, durations, deadlines, activation states, ticks/range and headers now have field-based bounds. Replacement semantics prevent charge accumulation; endpoint validation bounds scaled values. §6.10 adds boundary vectors. | None in DES-06. |
| DES06-4 | major | [§3.1](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-179/docs/design/20-castes.md:410), §4, DS-22 and DS-30–33 | **Resolved:** caste skill values are specified or escalated. | Stone Skin’s range is included; Warcry’s magnitude/addressing, Second Wind’s extra heal, Snare’s missing values and Brace’s duration are explicit decisions. Proposed rank-15 values reproduce as **35, 23, 82, 9, 16**. Deferred caste mechanics remain identified. | None in DES-06. |
| DES06-5 | minor | [§2.4](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-179/docs/design/20-castes.md:348) | **Resolved:** balance comparisons include damage-type armor. | All 15 rows reproduce with the checked-in exponent table, integer truncation and rounded-up hit counts. | None in DES-06. |
| DES06-6 | minor | [§6.2](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-179/docs/design/20-castes.md:545) | **Resolved:** extremal fixtures are separate and valid under their stated B decisions. | An Arcanist may hold a sword and off-hand, providing five held modifier slots and energy **130**. Health fixtures correctly distinguish **1,020 / 1,055** by DS-23. The maul fixture requires no off-hand. | None in DES-06. |
| DES06-7 | major | [§1.4, G6 and DS-29](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-179/docs/design/20-castes.md:148) | **Resolved:** regeneration covers what packing accepts today; the restriction and cost are escalated. | [Snapshot validation](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-179/contracts/logic/src/snapshot.cairo:46) does not restrict regeneration; [caste packing](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-179/contracts/logic/src/models/caste.cairo:146) likewise omits the legal-only ≤20 check. The revised A totals fit `i16`. DS-29 names both checks, their unmeasured comparison cost and absence of added storage or tick work. | None in DES-06; implement the approved policy in the follow-up. |

## Escalations: the auditor's view

- **DS-1:** Adopt per-source aggregate checks plus flattening checks; the latter must enforce whole-build legality.
- **DS-2:** Prefer signed computation followed by build rejection at floors 1 / 0 / 0.
- **DS-3:** Prefer freeing `health_bonus` and storing the final maximum; signed `i16` also fits.
- **DS-4:** Adopt (a) for all three passives; the current B proof covers that option.
- **DS-5:** Adopt saturation at 50 / 50 / 3 after wide summation.
- **DS-6:** Accept the paired on-hit gains and regeneration costs as initial bounds.
- **DS-7:** Accept the proposed primary-attribute and light-armor bounds; they complete the relevant totals.
- **DS-8:** Prefer rank 15 and correct design/15 after approval.
- **DS-9:** Decide the level cap before flattening; the uncapped comparison remains an explicit assumption.
- **DS-10:** Accept profile IDs 1–7 in the documented order.
- **DS-11:** The proposed curve is sufficiently specified; preserve its single final division and validate balance separately.
- **DS-12:** Accept fixed caste ranks initially, supported by the endpoint comparisons.
- **DS-13:** Accept separate boss records, triple health and distinct loot tables.
- **DS-14:** Prefer deferring MVP phases; the proposed later fields fit without another word.
- **DS-15:** Prefer state-sensitive usability, including equal-deadline replenishment.
- **DS-16:** Accept deferral; resolve placement and fallback together with DS-32’s trap range.
- **DS-17:** Use the analogue profession for goblin-only skills.
- **DS-18:** Adopt the caste bounds and cross-record adrenaline checks.
- **DS-19:** Accept bow-class rules with blunt damage for the Slinger.
- **DS-20:** Prefer at most one `ATTACK_BONUS`; the unrestricted alternative is also correctly bounded.
- **DS-21:** Accept summing and consuming all held glyphs; 1,020 covers their contribution.
- **DS-22:** Accept Stone Skin 10…30 and range 6 as initial content; rank 15 gives 35.
- **DS-23:** Prefer preserving 15 / 10 / 5 with piece eligibility checks; the matching health maximum is 1,020.
- **DS-24:** Retain per-guard bounds and use the proved wider sum at a hit.
- **DS-25:** Accept deferral until intermediate-tile collision and trap triggering are specified.
- **DS-26:** Accept deferral; the proposed start-of-skill trigger now identifies timing and damage semantics.
- **DS-27:** Prefer an ally-targeted catalogue skill with boss-first targeting; complete its content values before seeding.
- **DS-28:** Accept alert-based reinforcements initially; summons still require their own complete design.
- **DS-29:** Add ≤20 checks to both packer validators and retain `i16`; the stated cost is appropriately marked unmeasured.
- **DS-30:** Accept self-only Warcry 5…20 initially; allied coverage should remain a separate explicit choice.
- **DS-31:** Accept the additional guarded heal 20…70; its rank-15 value is 82.
- **DS-32:** Accept piercing, Crippled 3…8 and range 1, coordinated with the eventual Trapper placement rule.
- **DS-33:** Accept duration 8…15 with charge exhaustion; a fixed duration of 60 would still impose a time limit.