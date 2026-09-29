# [GPT-6-Astra] Audit — PR 100 (ENG-04) — security, quality, organisation

## Verdict

**PASS WITH FINDINGS.** F-1–F-4 are closed. Earlier security conclusions stand: no reachable ownership bypass, account takeover, partial ownership transfer, record loss, or packed-field corruption was found.

Two **minor organisation findings** remain. Under OPERATIONS §6, they require correction or an explicit orchestrator deferral with a PLAN entry before merge.

Reviewed `e88832da6b2fc49fd4426cc86e32da1c186a7141`, including fix loop `0191c57` and the D-143 refactor. D-144 and the updated cost rule were read from `origin/main`; they are newer than this checkout.

## Findings

This table gives the final disposition of every finding.

| # | Severity | Status | Location | Finding and evidence | Suggested fix / disposition |
|---|---|---|---|---|---|
| F-1 | major | **Closed** | D-144, Decision; `cost-budget.md §2`; report, “Fix loop 1” | The report’s figures and scenarios match those expressly accepted by D-144. Both extrapolated cases remain identified as estimates. | No reopening of the accepted targets. ENG-06 must remeasure transfer with the real `set_controller`. |
| F-2 | minor | **Closed** | [Deletion tests](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-100/contracts/persistent/tests/test_accounts.cairo:573) | Tests now delete the second of three and seventh of eight, exercising the longest searches for those fixtures while asserting three and four overwritten keys. Negative-delta and final-page regressions are present. | Satisfied for the requested scenarios. |
| F-3 | note | **Closed by decision** | D-144, Decision item 4 | D-144 settles the account cap at seven, enforced where slots are granted. Registration still grants three; this PR adds no purchase path. | Carry enforcement into the future slot-granting implementation. No transfer-loop change is required here. |
| F-4 | note | **Closed** | [Controller test](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-100/contracts/persistent/tests/test_accounts.cairo:812), [rollback test](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-100/contracts/persistent/tests/test_accounts.cairo:867), [node probe](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-100/contracts/tools/accounts_probe.py:91) | Controllers are initialised to the old owner and asserted as **0 N / 7 O / 0 zeroed**. A reverting double leaves all 112 watched Hub keys unchanged and preserves both ownership mappings. The probe and successful receipt-derived output are committed. | Satisfied. Watched-key snapshots remain finite; the probe supplies full-Hub state-diff counts for its exercised transactions. |
| F-5 | **minor** | **Open** | [Hub entrypoints](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-100/contracts/persistent/src/systems/hub.cairo:260), [WordImpl](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-100/contracts/persistent/src/systems/hub.cairo:675), [layering rule](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-100/docs/CAIRO.md:108) | **Scoping is improved, but the task-added code does not satisfy the requested store/system separation.** Entrypoints directly access maps and packed storage; `WordImpl` performs raw storage syscalls inside `systems/hub.cairo`; swap-removal behaviour remains there. `store.cairo` is only a placeholder. §7 reserves storage access for the store and systems for entrypoints/access control; §8 repeats this requirement. The report’s arithmetic-cost justification does not itself establish an exception to that boundary. | Move task-added persistence behind the store and list behaviour into its owning abstraction, preserving packed arithmetic where justified; alternatively record an explicit deferral covering these accesses and behaviour. Store-event emission remains outside this audit’s requirements. |
| F-6 | **minor** | **Open** | [Inline list check](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-100/contracts/persistent/src/systems/hub.cairo:406), [lane failures](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-100/contracts/persistent/src/models/account.cairo:152) | **Some task-added checks/errors escaped the Assert/error-module refactor.** `assert(i != last, 'not in the account list')` remains inline in the system. `AdventurerListImpl::{unit,get,set}` each retain a literal `'lane above 6'` panic outside an Assert impl and outside `errors`. These are internal invariant failures, not reachable ownership exploits, but they contradict the requested organisation rule. | Route these failures through the appropriate Assert impl and named `errors` constants, retaining their messages and evaluation points. |

## Coverage

**D-144 comparison.** The accepted scenarios and figures match the report:

| Scenario | Reported measurement / estimate | Accepted target |
|---|---:|---:|
| Register | 2,636,720 | 2,650,000 |
| Create, cold | 4,694,960 | 4,700,000 |
| Create, initialised | 4,332,960 | 4,350,000 |
| Delete, second of three | 1,555,840 measured | 1,750,000 deletion target |
| Delete, seventh of eight | 1,731,242 estimated | 1,750,000 |
| Transfer, seven inside | 3,646,034 estimated with double | 3,700,000 |

The estimates reproduce exactly: deletion adds the **143,330** snforge difference and one **32,072** overwrite; transfer adds **1,498,570** and seven overwrites. These are the cases D-144 accepted, not newly substituted measurements.

**Regression coverage.** The negative-delta test exercises `[3,2] → [2]`, checks every stored lane, then appends ID 4. The final-page test deletes the ninth of ten, verifies page zero is unchanged and only three keys change, then exercises positive and negative cross-page swaps and retention of `LIVE` on the emptied page. The rollback test verifies Hub rollback on a failed controller call; it does not exercise a later failure after an earlier controller update succeeds.

**Behaviour and refusal order.** Source comparison confirms unchanged frozen Hub interfaces, storage declarations, event enum, account/adventurer fields, and packers. Refusals remain ordered as follows:

- Creation: account → name → profession → capacity.
- Transfer: current owner → nonzero recipient → recipient without an account.
- Ownership helper: existence → ownership → deletion status → inside status.
- Inventory: balances → packed equipment → worn equipment → gold.

Some reads now precede the grouped Assert call. This increases refusal-path cost but does not change the selected refusal under valid stored-state invariants.

Registration uniqueness, monotonic IDs, reverse-map consistency, controller updates, deleted-list exclusion, the four emptiness checks, tombstone preservation, views, and arithmetic safety retain the earlier security conclusions. The same dependencies remain: inventory writers must maintain `pack_lanes` and compact equipment lists.

**Organisation and arithmetic.** No new production free function remains; pre-existing functions and packers were excluded from this organisation audit. Test helpers have a written scaffolding justification. Model/profession methods now have scoped names, and the ordinary player refusals reside in Assert impls and `errors` modules. F-5/F-6 identify the remaining gaps.

`test_stored_words` still compares the arithmetic methods and constants against the typed packers, including the newly extracted `without_adventurer`. Profession conversion preserves IDs 1–3; public creation still accepts `u8`.

**Gas and verification limits.** Static checks confirmed that all **32 account tests’ recorded measurements** fit their annotations and the 5% ceiling. The report records unchanged accepted worst-case call costs; the first-of-three deletion rises by only 100 snforge gas, while refusal paths increase as disclosed.

`git diff --check` passed. The foreground `snforge` attempt timed out after 20 seconds without output; no build artifacts were available. Cairo execution, CI, class size, and the post-refactor node rerun therefore remain implementer-reported. The committed probe/output and estimate arithmetic were inspected, not rerun. No files were written, and no command remains pending.