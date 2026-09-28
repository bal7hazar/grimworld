# [GPT-6-Astra] Audit — PR 50 (SPK-7) — cost, determinism

## Verdict

**PASS WITH FINDINGS** at **a60cb8f**.

Findings **1, 2 and 4 are resolved**. Finding **3 remains open, minor**: the new benchmark exercises the missing branch, but its purported pending moves cannot arise from valid ticks. Under OPERATIONS §6, this needs correction or explicit deferral.

## Findings

| # | Status | Severity | Location | Evidence / conclusion | Suggested fix |
|---|---|---|---|---|---|---|
| 1 | **Resolved** | major → closed | [flood.cairo:71](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-50/spikes/SPK-7/src/flood.cairo:71), [shared-vector test](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-50/spikes/SPK-7/tests/test_flood.cairo:209) | Both implementations now check pending targets **before** computing another layer. Empty targets return only layer 0. All **12 committed vectors** reproduce from Python, including inputs, layer counts, packed distances and reached bitmaps. The Cairo test checks these values and passes in the committed output. Unreachable-target fixtures preserve the full-depth benchmarks. | None. |
| 2 | **Resolved by scope amendment** | major → closed | [Research §3–4](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-50/docs/research/SPK-7-chunked-maps.md:288) | The note explicitly attributes omission to the orchestrator’s amendment, says the fallback was neither built nor measured, labels its cost arguments analytical, and makes R-12 conditional on that analysis and D-133’s batches. It requires reassessment if either condition fails. This satisfies the ruling supplied for this re-audit. | None within the amended scope. |
| 3 | **Partially resolved; open** | **minor** | [SHIFT_GHOSTS](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-50/spikes/SPK-7/src/fixtures.cairo:98), [setup_shift](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-50/spikes/SPK-7/src/contract.cairo:375), [research description](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-50/docs/research/SPK-7-chunked-maps.md:187) | The `(37,58) → (37,60)` move genuinely exercises the changed-chunk-set branch. Receipts support **B′ 3,320,960 versus A 2,880,960**, and the overall maximum is now correctly qualified as “among the cases measured.” However, `setup_shift` injects impossible pending occupancy: all four ghost tiles are walls; three are on the old window’s frozen ring. For example `(2,3,205)` maps to global `(40,58)`, old local `(3,0)`. A goblin there cannot have moved away during deferred ticks: `world_tick` excludes the ring. Thus the benchmark measures synthetic storage repair, not the claimed valid four-chunk pending-move history. | Construct pending occupancy through valid deferred ticks before crossing the chunk boundary. Retain the current case only as explicitly synthetic branch coverage, and correct its description. |
| 4 | **Resolved** | minor → closed | [Research §3](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-50/docs/research/SPK-7-chunked-maps.md:284) | The storage-only attribution is removed. A−S is explicitly **net overhead**, including computation and storage, with no claimed split. The note correctly distinguishes the **305,692** in-memory assembly/chunk-update difference from the **218,384** snforge A−S difference and identifies S’s occupancy reconstruction. Batch savings remain unmeasured. | None. |

## Coverage

Reviewed commits **5c99c33, c9f8ab9 and a60cb8f**, the changed implementation/tests, and committed measurements. All verification was foreground and read-only. Cairo tests and node transactions were **not rerun**.

The rerun outputs, budgets and research arithmetic agree:

| Check | Verified result |
|---|---|
| Tests and budgets | **106 passing results** recorded; all 106 attributes and both gas tables exactly match `ceil(1.05 × measured)` |
| Node outputs | Three runs, each **55 successful invokes**, **27 measured**, both goblin-equality checks true |
| Receipt summary | Regenerates **byte for byte** |
| A−S | **720,000**, waiting and moving; **13.962% ≈ 14.0%** of SPK-2’s worst tick |
| Combined estimate | **5,876,800 ≈ 5,877,000**, correctly labelled an estimate |
| Assembly | One-versus-two-call differences are **65,224** for both chunk counts; the unexplained equality is disclosed |
| Flood | **634,655** capped fixture; **26,452/layer** slope; **1,150,737** including eight steps |
| Reveal maxima | **2,455,200** for one chunk; **5,919,680** for three |
| Line of sight | **9,716**, unchanged |

No additional functional regression was found. **1,200 deterministic nonempty-target Python comparisons** against the previous revision retained identical layers, distances, moves and occupancy. Generation, assembly, line-of-sight and tick logic are unchanged; their earlier oracle coverage remains applicable. The outstanding issue is the validity and description of finding 3’s new benchmark fixture.
## Orchestrator's note (`[Opus 5.5]`, 2026-09-28)

Finding 3 (minor) closed by the orchestrator in fd601a5: the chunk-set-change case of B′ is labelled synthetic in the research note and the fixture; a benchmark from valid deferred ticks is deferred to ENG-07, if B′ is kept (PLAN). Finding 2 resolved by the orchestrator's scope amendment: the fallback (item 7) is not measured, D-133 takes the cost.
