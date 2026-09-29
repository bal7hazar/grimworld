# [GPT-6-Astra] Audit — PR 139 (DES-04) — final check

## Verdict

**PASS WITH FINDINGS**

At `be82bf5`, the requested D-155 corrections are present. **Within this final pass’s scope, 19-effects is ready for CBT-01**, with F-16 explicitly retained as ENG-05’s dependency. No further DES-04 fix is requested.

## Coverage

Checked only F-20, F-15, incorporation of the D-155 decisions and F-16’s disposition, against the final-pass report. Earlier closed findings were not reopened.

Independent recount:

- Guarded armor: two `i8` aggregates, each bounded to **−126…126**.
- Unguarded armor: `i16` at MemberBar bits **232–247**.
- MemberBar: **248 data bits**, including **120/122** high-limb bits; **two bits free**.
- MemberKit high limb: **75 bits**. **Zero additional slots**.
- Section 9 contains **43 distinct decision rows**, with FX-0b included under FX-0; none missing or duplicated.
- No “escalation” or “recommendation” wording remains in 19-effects.

Read-only; no builds or independent CI verification.

## Final findings

| # | Severity | Status | Evidence | Disposition |
|---|---|---|---|---|
| **F-20** | major | **Resolved** | [Signed armor pipeline](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:408) sums negative and positive contributions before `max(0,a)`, then applies penetration. [Encoding](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:706) specifies bounded `i8` guarded sums and an `i16` unguarded aggregate. For example, `35−40+20=15`; 25% penetration leaves **12**, preserving the negative contribution until the final aggregate. | Closed; minor bound-documentation note below. |
| **F-15** | minor | **Resolved** | [Executor branches](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:571) explicitly suppress false-guard TRAP placement and its payload, retaining costs. A false DAMAGE guard suppresses the hit while independently eligible entries continue. | Closed. |
| **F-16** | major | **Deferred to ENG-05 under D-155** | [§7.2](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:763) explicitly calls the count an estimate, acknowledges dependency rounds and assumed generation bounds, and assigns the read schedule to ENG-05. FX-46 repeats this qualification. | Satisfies this pass; the three-call maximum remains unproved. CBT-01 must not encode it as a guaranteed bound. |
| **D-155 decisions** | — | **Verified** | [§9](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/design/19-effects.md:841) records all 43 references as decided. FX-26 is explicitly post-MVP in the skill kind, effect kind, coverage row and decision table. | No remaining recommendation or escalation in 19-effects. |
| **F-21** | note | **CBT-01 handoff** | The unguarded-armor expression separately includes personalisation, but its **9,945** bound sums only `255+255+37×255`. | Clarify whether the two 255 limits include personalisation; otherwise include its uplift. This does not threaten `i16` capacity or require another slot. |
| **F-22** | note | **CBT-01 handoff** | The [decision record](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-139/docs/decisions/2026-09-29-des-04-effects.md:38) still says **Pending**, as the implementer acknowledges. | Synchronize the archive with the approved D-155 decision. This check follows the decision stated in your instruction; no renewed approval is requested. |