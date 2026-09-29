# [GPT-6-Astra] Audit — PR 93 (ENG-01b) — cost, quality

## Verdict

**PASS WITH FINDINGS — F-2 retains one minor documentation contradiction. All other findings are resolved. No new findings.**

Reviewed `873bf27`, including `8db96ad`, `a61c490` and the merges from main. The standalone content-version refinement matches D-141 and design/02. No generation-isolation regression was found.

Under OPERATIONS §6, the remaining minor requires correction or explicit deferral with a PLAN entry.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| F-2 | **minor** | [ENG-01-interfaces.md:1270](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-81/docs/architecture/ENG-01-interfaces.md:1270), E-1 | **E-1 still says the initialised batch costs the same with one goblin word or two.** | The option-(b) text retains: “the initialised batch, 47.34 M, is the same.” The corrected §9.2 and §10.1 correctly explain that removing 16 overwritten words saves **513,152**, giving approximately **46.82 M** under unchanged computation assumptions. | Replace the stale E-1 clause with the corrected explanation. This is documentation consistency, not a measurement required from ENG-07; the alternative remains rejected. |

The other parts of F-2 are fixed: gas maxima and new-key counts are distinguished, first-record weighting no longer claims to forbid new words, and the 70-key bound remains derived independently of the gas maximum.

## Coverage

**Accounting.** Ran both commands; each output matches its committed file **byte-for-byte**:

- `python3 -B contracts/tools/budget_table.py`
- `python3 -B contracts/tools/budget_table.py --keys`

All generated table rows also appear in the architecture document. Independent enumeration of mixed reveal/first-record cases within the model retains **48,537,162** as the capped batch’s cold maximum. The capped slot bound remains **70**.

| Verified case | Initialised L2 gas | Cold L2 gas |
|---|---:|---:|
| `open`, worst branch | 9,250,416 | 24,326,472 |
| `mine`, worst branch | 20,671,830 | **57,849,618** |
| `barter`, worst branch | 9,054,200 | 22,022,996 |
| Version refusal of each | 1,194,187 | 1,194,187 |
| `Registry.set_record` | 1,058,019 | 3,165,279 |

Each standalone version-refusal branch includes five calldata felts, one registry call and `Refused`, with **zero physical keys written**. The modeled unsplittable maximum is **150,382 below 58 M**. These remain estimates pending implementation measurements.

**Version interfaces and tests.** `open`, `mine` and `barter` consistently take `version: u32` immediately after `sequence` in their traits and implementations. Their specification refuses a mismatch before any tick or draw, changing nothing.

The [event test](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-81/contracts/ephemeral/tests/test_events.cairo:47) now explicitly verifies:

- `Stop::Version` in a refusal-shaped `BatchPlayed`, with stop **6** and a distinct content-version value **7**.
- Every `Stop` ordinal, **0–6**.
- `Refusal::Version` in `Refused`, with reason **8** and unchanged sequence.
- Every `Refusal` ordinal, **0–8**.

This resolves F-15. These tests pin serialization; gameplay enforcement remains for the implementation tasks.

Leaving `loot`, `leave`, `travel_back` and `enter` unversioned is correct under the adopted design/02 classification: they execute no client-computed ticks, price or path; their draw or next-instance state is determined by the chain.

**Orchestrator answers.** The pre-deployment exception for this `BatchPlayed` change is recorded in both `events.cairo` and §5, including the absence of an old deployed layout. The registry/interface comments consistently specify automatic increment for **every changed record**, without a separate administrator version setter. `content_version()` is inventoried as a one-read view; `bundle` has the **97-read** bound. Its write key is present as `first` in `set_record`.

The `IFate` comment now specifies `poseidon(word, domain, index)`, agreeing with ADR-0002 and the merged `grimworld_logic::fate::derive`.

**Regression checks.** Generation-isolation §2.1 is unchanged byte-for-byte. Instance layouts, masking/reset helpers, codec, deadline protections and `TxHashFate` are unchanged. Gameplay and instance views remain reverting stubs. FND-05’s merged administrator setters check the current administrator and touch configuration only; they introduce no path to old instance records. The class-size CI gate remains intact.

**Validation limits.** `git diff --check` passed. All **72 committed measurements** fit their declared budgets. The build through `scripts/lock.sh` failed immediately because Scarb could not open its lockfile on the read-only filesystem; class-size measurement found no local artifacts. Therefore, no fresh Cairo test pass, class-size measurement or independent green-CI verification is claimed. No files were written.

## Final status of every finding

| Finding | Status | Evidence / disposition |
|---|---|---|
| F-1 — Belt settlement | **Resolved** | Reservation and defeat-refund accounting retained. |
| F-2 — Bounds and explanations | **Open — minor** | Calculations and §9.2/§10.1 corrected; stale E-1 clause remains. |
| F-3 — Standalone branches | **Resolved** | Objective unions and barter price-refusal call retained; version refusal added correctly. |
| F-4 — Original complete write sets | **Resolved** | First-entry Rift and earlier repairs retained. |
| F-5 — Selector inventory/views | **Resolved** | Getter inventoried; `bundle` bound corrected to 97. |
| F-6 — Displaced remains | **Resolved** | Roster discovery and gating unchanged. |
| F-7 — Per-action events | **Resolved** | Retained and priced. |
| F-8 — Registry allocation | **Resolved** | Allocation rules unchanged. |
| F-9 — Deadlines/packing | **Resolved** | Protections unchanged. |
| F-10 — Encoder validation | **Resolved** | Unchanged. |
| F-11 — Class-size CI gate | **Resolved** | Gate retained; local remeasurement unavailable. |
| F-12 — Generation reset | **Resolved** | Reset specification and helpers unchanged. |
| F-13 — Roster masking | **Resolved** | Masking requirement and test retained. |
| F-14 — Empty timer sentinel | **Resolved** | `NO_SLOT` helpers and packing test retained. |
| F-15 — Version-stop regression test | **Resolved** | Version event and every Stop ordinal explicitly pinned; Refusal ordinals also pinned. |
| F-16 — Registry version write cost | **Resolved** | Physical version key included; regenerated costs verified. |