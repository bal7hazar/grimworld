# [GPT-6-Astra] Audit — PR 81 (ENG-01) — design, security

## Verdict

**FAIL — F-3 and F-4 remain major; F-2 remains minor.** Reviewed HEAD `4a1ba2b`, including fix loop 3 and the class-size CI addition.

The requested repairs substantially improve the accounting. Two reachable cases still lack their complete write/call sets. These are gaps in ENG-01’s **frozen cost specification**, not gas figures that can only be measured during ENG-02…ENG-07. AC-2 therefore remains incomplete. After the third loop, the remaining majors go to the project manager under OPERATIONS §6.

**No remaining security finding in the interface/stub scope.** This does not establish the safety of future gameplay implementations.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| F-3 | **major** | [budget_table.py:271](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-81/contracts/tools/budget_table.py:271); [interfaces §4.1](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-81/docs/architecture/ENG-01-interfaces.md:509), §9.3, E-8 | **Standalone branches still omit objectives completed by their world ticks.** The price-refusal branch of `barter` also omits its exchange call. **Frozen cost-specification gap.** | A burning/poisoned Rift Heart can die while the adventurer mines or opens a chest. The required Rift-board write is absent from every `tick_branches` branch; dungeon completion likewise needs its counter/event. Unlike `play_branches`, this builder never unions `report_objective()`. Applying the script’s own objective envelope raises modeled `mine` maxima to **57,844,498 cold** and **20,666,710 initialised**. Separately, discovering insufficient payment requires `Hub.barter`, but the combined interruption/refusal branch counts only registry and report calls. | Compose objective results with completion, interruption and defeat where reachable. Distinguish price refusal from interruption before exchange. Regenerate E-8 and the tables. The gameplay interfaces already carry the necessary results; the missing accounting is determinable now. |
| F-4 | **major** | [budget_table.py:232](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-81/contracts/tools/budget_table.py:232); [design/17:61](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-81/docs/design/17-rifts.md:61); interfaces §9.3–10 | **`enter_rift` covers only an adventurer whose slot already exists.** Its first-entry branch is missing. **Frozen cost-specification gap.** | Wood-rank adventurers can enter Wood Rifts; no rule requires an earlier ordinary instance. Nevertheless, the sole Rift branch calls `create_keys(first_entry=False)`. A first instance entered through the day’s first board action requires first-slot initialisation and `I.next_slot`. Using the existing builders and prices gives **20 N / 7 O, 12,457,710**, versus the listed later-entry **7 N / 19 O, 6,946,762**. | Add the first-slot Rift branch and derive the selector’s cold maximum from both branches. Retain the later-entry figure separately. This requires no gameplay benchmark or interface redesign. |
| F-2 | **minor** | [budget_table.py:305](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-81/contracts/tools/budget_table.py:305); [interfaces §10.1](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-81/docs/architecture/ENG-01-interfaces.md:1070) | **The universal slot-bound claim is not established by the reveal model.** **Frozen accounting/documentation gap; non-critical to the currently modeled gas maximum.** | §10.1 says “at most 64 keys” while its reveal row reports **66**. Revealed feature words use identities `revealed0`… separately from the nine window-feature identities, although §9.2 bounds their combined physical set by nine chunks. The reveal branch also lacks objective/defeat combinations. Separately, §9.2’s assertion that E-1(b) keeps every invocation below 40 M contradicts §10.1’s **47.33 M initialised** case: dropping cold-write costs cannot remove that case. | Model revealed and tick-updated chunks with shared physical identities and correct transaction-start classifications; include closing/objective unions; derive the slot maximum independently of the gas maximum. Qualify the 40 M statement. |

The specific F-4 repairs requested for this loop **are correct**: first hint, modifier lift without a stone where the item survives, trade’s eight-page union and two external calls, and calldata at 5,120 per felt. F-4 remains open because of the uncovered first-entry Rift branch above.

## Coverage

**Accounting verification.** Ran `python3 -B contracts/tools/budget_table.py` normally and with `--keys`. Both outputs match their committed files **byte-for-byte**. Checked key builders against the storage declarations and frozen action semantics, including cold/initialised classifications, closing settlement, compact roster pages, Counter records with `LIVE`, calldata and event shapes. Event prices are appropriately labelled estimates.

The four non-reveal batch branches now include open, objective, defeat and their union. Their reported initialised counts—**56, 58, 62 and 64**—and corresponding figures reproduce. The unsplittable-action estimates also reproduce. The lifetime calculation is correctly presented as an **upper bound**: 201 floor indexes plus six zone-only indexes gives 207 indexes and 4,575 keys; 4,971 remains the absolute layout bound.

**Generation isolation.** Rechecked `create`, gate transitions, all instance-facing selectors and both views against §2.1. The specification gates reads by generation, member/task counts, revealed chunks and touched goblins; resets transient member words for the new clock; and masks every roster-page read. `empty_member_timers()` now supplies `NO_SLOT`, and the new test pins `LIVE + 255` for member and goblin timers. No new stale-generation reachability was found. End-to-end enforcement remains an explicitly deferred E-13 implementation test.

**Other security checks.** The 89 unimplemented bodies remain unconditional `not implemented` reverts. Cross-contract caller restrictions remain specified. `TxHashFate` checks `SN_MAIN` at construction and every call; no other production source currently draws randomness. Codec bounds, malformed-input rejection, encoder validation and deadline-packing protections remain intact.

**Validation limits.** The foreground build through `scripts/lock.sh` failed immediately because Scarb could not open its lockfile on the read-only filesystem. No fresh Cairo test pass is claimed. `class_sizes.py` found no local artifacts, so class sizes could not be independently remeasured. The new [CI step](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-81/.github/workflows/ci.yml:109) correctly runs the existing size gate after the contracts build; **F-11 is resolved**. No files were written.

Full tick computation, shared batch savings, event/call estimates on the target network and completed class sizes remain legitimate later-task measurements under E-13. Those uncertainties are distinct from the omitted branches above.

## Final status of every finding

| Finding | Status | Evidence / disposition |
|---|---|---|
| F-1 — Belt settlement | **Resolved** | Reservation debited at entry; unused counts returned on closing; consumed counts gone; transitions carry the reserve. Defeat policy remains explicitly E-15, with refund costs modeled. |
| F-2 — Tick, batch and lifetime bounds | **Open — minor** | Main branch recomputation and lifetime upper-bound correction verified. Reveal-set/global-bound inconsistencies remain above. E-16/E-21 remain proposed decisions. |
| F-3 — Standalone actions | **Open — major** | Actual ticks, draws, interruption and defeat now represented; objective unions and barter price-refusal call remain missing. |
| F-4 — Complete write sets and costs | **Open — major** | Named loop-3 repairs verified. First-slot `enter_rift` remains uncovered. |
| F-5 — Selector inventory and view limits | **Resolved** | Inventory and bounded views retained, including external spawn-chunk gating reads. |
| F-6 — Displaced remains | **Resolved** | Remains stay discoverable through the gated, masked roster until looted; implementation regression case remains E-13. |
| F-7 — Per-action events | **Resolved** | Events retained; frozen shapes priced and labelled E. |
| F-8 — Registry allocation | **Resolved** | Allocation/update rules and per-kind counters retained. |
| F-9 — Deadlines and packing | **Resolved** | Effective-duration caps, clock headroom and rejecting packers retained. |
| F-10 — Encoder validation | **Resolved** | Invalid directions and slots rejected before encoding; batch validation retained. |
| F-11 — Class-size CI gate | **Resolved** | Added by `4a1ba2b`; fresh execution not verified locally. |
| F-12 — Generation transition reset | **Resolved** | Every transition specifies all four transient words reset; alternative carry rules remain E-20. |
| F-13 — Roster masking | **Resolved** | Internal/view masking requirement and stale-lane test retained. |
| F-14 — Empty timer sentinel | **Resolved** | Helpers and packing test use `NO_SLOT = 255`, stored as `LIVE + 255`. |