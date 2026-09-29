# [GPT-6-Astra] Audit — PR 165 (CBT-01) — design, determinism, organisation

## Verdict

**FAIL pending project-manager disposition** at `a50772fff34965d430b7573d5f7bff0349a234cd`.

The outstanding defects in CBT-1, CBT-2 and CBT-8 are fixed. CBT-3 through CBT-7 remain resolved. One **minor test-oracle defect** remains; no new runtime or packing defect was found. Under OPERATIONS §6, the minor needs correction or formal deferral. This is the final audit handoff, not a request for another automatic fix loop.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| CBT-9 | minor | [passive.cairo:199](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-165/contracts/logic/src/types/passive.cairo:199), [test_capacity.cairo:165](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-165/contracts/logic/tests/test_capacity.cairo:165) | The flattening oracle rejects a newly accepted, representable collection. | A prefix with benefit `CONDITION_DURATION(BLEEDING,33)` and fixed cost `CONDITION_DURATION(BLEEDING,10)` passes validation: `conflicts` correctly permits matching conditions. The oracle collects two entries and fails `conditions.len() <= 1`. Design/19 §4 requires summing **per condition**; the correct snapshot is Bleeding, 43%. | Aggregate matching conditions before applying the duration cap. Test 33+10→43 and a sum exceeding 50→50, retaining refusal of different conditions. This is confined to the test oracle; the example fits the existing snapshot. |

The counterexample follows directly from the validator and oracle branches; it was not executed in Cairo.

## Coverage

**CBT-1 — resolved.** `ENERGY_COST` now permits `−32768…0`. Tests accept −1, zero and the full non-positive interval; they refuse +1 and a range crossing zero. This implements the signed-delta interpretation of design/19’s “− energy”. Escalation I explicitly records the alternative encoding.

**CBT-2 — overlap defect resolved.** Applicability now matches §5.4:

- Plain weapon: `WEAPON`, `ALL`.
- Attack skill: `WEAPON`, `ATTACK_SKILL`, `ALL`.
- Spell: `SPELL`, `ALL`.

The contribution check evaluates both range endpoints, per guard and actual hit class. Five modifier sources plus two set bonuses therefore remain within ±126 damage and 252 penetration.

I independently checked all twelve scope/class combinations and recalculated the new worst-overlap vectors:

| Sum | Plain weapon | Attack skill | Spell |
|---|---:|---:|---:|
| Damage, above half | 81 | 126 | 36 |
| Penetration | 162 | 252 | 72 |

The tests cover both overlap orderings, rejection of penetration 36+36, rejection of damage 18+1, acceptance of bounded overlaps, and the original single-`WEAPON` example `[18,18,0]`.

The oracle shares `applies_to` with validation, so it is not wholly independent; its literal expected vectors nevertheless detect the earlier scope error. CBT-9 qualifies the broader claim that the oracle handles every accepted collection. Escalation G remains outside the demonstrated capacity guarantee.

**CBT-8 — resolved.** The unguarded-armor restriction is removed. The original rune `+5/−2` is accepted. The new flattening test covers two armor passives on every slot plus set bonuses: **32 contributions**, reaching **8,720** with personalised ratings or **−8,160** without ratings, both inside ±9,995. Safe same-sum guarded pairs are also accepted.

**Earlier coverage stands.** No packing implementation changed in this loop; the snapshot change is explanatory comments. The previous entry/record bit counts, limb boundaries, part counts, `LIVE`, signed encodings, width refusals and `content::Record<T>` conclusions remain valid. F-21 remains **9,995**, safely held by `i16`.

ENG-06’s member/goblin writes, reset behavior and generation isolation are unchanged. There remain zero additional snapshot storage slots and a 21-felt create-time serialization increase. The organisation fixes remain intact.

**Verification:** the checkout was clean and `git diff --check` passed. The foreground `snforge` attempt failed before compilation because Scarb could not open its lockfile on the read-only filesystem. The reported 198 logic tests, 375 workspace tests and green CI were not independently reproduced. No files were written.

Final disposition of every finding:

| Finding | Severity | Final status |
|---|---|---|
| CBT-1 — passive domains | major | **Resolved:** `ENERGY_COST` sign constrained; boundary tests added. |
| CBT-2 — source restrictions and capacity | major | **Resolved for documented bounded sums:** overlap fixed and worst-overlap tests checked; G remains a design dependency, CBT-9 a separate oracle defect. |
| CBT-3 — attack hit-modifier filter | major | **Resolved; unchanged.** |
| CBT-4 — preparation duration across ranks | major | **Resolved; unchanged.** |
| CBT-5 — non-potion empty entry | minor | **Resolved; unchanged.** |
| CBT-6 — organisation | minor | **Resolved; checks, mappings and named errors remain appropriately scoped.** |
| CBT-7 — unsettled mappings implemented as rules | major | **Resolved; catalogue constraints and explicit escalations remain intact.** |
| CBT-8 — unjustified benefit/cost restrictions | major | **Resolved; original armor counterexample accepted and aggregate extremes tested.** |
| CBT-9 — same-condition flattening | minor | **Open:** oracle rejects two accepted bonuses for the same condition; project-manager disposition required. |

## Escalations: the auditor's view

- **A — Attribute identity:** Genuine mapping decision; global content IDs mapped to build-local indices is reasonable. Correct the report’s count: design/03 names **26**, not 27, attributes.
- **B — Quick-cast slot:** Genuine content choice; any one permitted slot preserves the count bound, and inscription is a reasonable recommendation.
- **C — Damage-type placement:** Genuine integration dependency; prefix simplifies enforcement, while suffix/inscription requires an item-context check excluding off-hands.
- **D — Health-rune identity:** Genuine grouping decision; modifier ID works only if separately authored IDs cannot represent the same non-stacking rune family.
- **E — Adrenaline decay:** Genuine missing value; BAL-01 should settle it before CBT-02 uses it.
- **F — Create serialization:** Legitimate optimisation decision for measured integration work; the 63-felt replacement and four remaining belt-count felts are correctly stated.
- **G — Undefined capacities:** Material design dependency, not a completed guarantee; assign explicit decisions and acceptance tests before accepting these records into production snapshot construction.
- **H — Professions:** Keep the six defined IDs; MVP content selection does not justify narrowing the enumeration.
- **I — Energy-cost encoding:** The signed-delta implementation resolves CBT-1; positive magnitude would be an explicit interface change, not a necessary further fix.

The member-flag count and missing chunk-kind comment remain documentation handoffs; post-MVP exclusions remain justified. Also clarify design/19’s per-item passive-count wording: the new 32-contribution proof is sound, but calling its “five per item” figure a count of modifier slots is an interpretation.

The production snapshot builder must preserve the checked hit-class semantics and documented saturation rules, resolve G, and aggregate matching condition bonuses correctly.