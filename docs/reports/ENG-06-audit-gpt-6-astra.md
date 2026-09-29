# [GPT-6-Astra] Audit — PR 120 (ENG-06) — security, quality, organisation

## Verdict

**PASS WITH FINDINGS**

Reviewed `b9cf43c4d9d7ccf0a70bb0f43a1ac8e25307f382`, including fix-loop commits `02cab98` and `b9cf43c` and merge `4234faf`.

**F-1 is closed. F-2 remains deferred to ENG-R1 and does not block this merge. No new findings.**

## Findings

| # | Severity | Final status | Location | Evidence | Required follow-up |
|---|---|---|---|---|---|
| F-1 | major | **Closed** | [test_generation_isolation](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-120/contracts/ephemeral/tests/test_lifecycle.cairo:654) | All eight member words now receive stale values. Re-entry supplies a different snapshot and Bob as controller. The test compares all eight words against the new generation’s expected values in both `instance_state` and storage. Alice’s `travel_back` and `leave` revert with `not controller`; Bob successfully returns, reporting the new instance and belt. Existing header, task, revealed-set, roster-masking and stale-ID assertions remain. | None for this finding. |
| F-2 | minor | **Deferred — non-blocking** | [PLAN, ENG-R1 at #125](https://github.com/bal7hazar/grimworld/blob/1e280f14e2630198f9a464ffbc2f76f2c7ec48d2/PLAN.md#L187) | Verified commit `1e280f1` explicitly assigns Instances’ raw storage syscalls, lifecycle map access and `Hub.change_pack` aggregation to ENG-R1. This record is present on `origin/main`; the audited branch’s older PLAN copy predates it. | Complete the recorded store/model separation in ENG-R1. |

## Coverage

**D-148 matches the code.**

- [design/03](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-120/docs/design/03-adventurer.md:63) now specifies flat class armor until BAL-01. `ProfessionTrait::armor` returns **80/70/60**, and snapshot construction uses that value without level scaling.
- [design/02](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-120/docs/design/02-core-loop.md:420) now requires standing on the gate’s anchor tile. `GateTrait::can_leave` requires exact coordinate equality; existing tests accept the anchor and reject adjacent tiles. Previously disclosed unsupported gate types remain outside implemented coverage.

**Earlier coverage stands.** The only production-source change since `5e4bfc2` removes an unused import. The earlier conclusions on ownership, cross-contract callers, generation isolation, entry randomness, refusals, settlement, E-15/E-20, placement and duplicate-closing protection remain unchanged. No lifecycle or settlement exploit was identified. Earlier scope and integration-test limitations remain applicable.

**Verification.** `git diff --check` passed. The revised test’s recorded measurement **45,572,993** correctly yields budget **47,851,643**; all **225** recorded budgets satisfy the reported measurement-plus-5% bound. Other recorded figures are unchanged.

A foreground attempt to run `snforge test test_generation_isolation` timed out after 20 seconds without output, so this re-audit does **not** independently confirm execution or the reported CI result. No files were changed.