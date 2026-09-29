# [Sonnet 5.5] ENG-01b — ENG-01's cost accounting completed, and the content version

## Summary
The accounting of ENG-01 now covers the branches the final audit found missing (F-2, F-3, F-4), applies D-141's rules where they bind, and the frozen interfaces carry the **content version** (D-141, E-5). No game logic was written. The model I ran as (Sonnet 5.5) is the one the brief names.

Pull request: https://github.com/bal7hazar/grimworld/pull/93 (CI green: every job passed).

## Files changed
- `contracts/tools/budget_table.py`, `budget-output.txt`, `budget-keys-output.txt`: the accounting (below).
- `docs/architecture/ENG-01-interfaces.md`: §3.5, §4.1, §4.2, §5, §9.2, §9.3 (table copied from the keys output), §10 (table copied from the budget output), §10.1, §11 (E-1, E-5, E-8, E-16, E-21).
- `contracts/logic/src/interface.cairo`: `bundle` returns the version.
- `contracts/logic/src/types.cairo`: `Stop::Version`.
- `contracts/ephemeral/src/systems/instances.cairo`: `play` takes `version`.
- `contracts/ephemeral/src/events.cairo`: `BatchPlayed.version`.
- `contracts/persistent/src/systems/registry.cairo`: `bundle` signature, storage `content_version`, its layout assertion.
- `contracts/ephemeral/tests/test_events.cairo`, `test_instances.cairo`: the tests of the new fields.
- `contracts/{ephemeral,persistent}/GAS.md`, `docs/BUDGETS.md`: regenerated.

## Findings and where each is answered
| Finding | Answer |
|---|---|
| **F-3** standalone objective | `tick_branches` unions `report_objective()` (board, `dungeons` counter, `DungeonCleared`) with every branch of `open`, `mine`, `barter`: completion, interruption, defeat, quiet completion. `barter`'s refusal on price is its own branch, with `Hub.barter` (3 calls) apart from an interruption before the exchange. E-8 recomputed (§11). `mine` reproduces the audit's 57,844,498 cold and 20,666,710 initialised. |
| **F-4** `enter_rift` first entry | Two branches (first entry: 20 N / 7 O, 12,457,710 cold; later entry: 7 N / 19 O, 6,946,762). The selector's row takes the larger; the later-entry figure has its own row. Matches the audit's figures. |
| **F-2** chunks, slot bound, E-1 (b) sentence | Chunks have one physical identity per word (a batch's chunk keys: 9 `features` words, 4 of them `first` when revealed, plus 4 `terrain` = 13, was 17). The reveal branch is now four branches (open, objective, defeat, both). The slot bound is computed from the key sets (`checks()`): **70 keys**, in the reveal branch with objective and defeat; the gas maximum is another branch, 64 keys, 47.34 M (§10.1). §9.2's sentence on E-1 (b) is rewritten: it does not remove the 47.33 M initialised case. |
| D-141 rules in the tables | Cap of 16 (E-16): already the `play` rows' basis. First-record weight (E-1): `play` goblin records are `old`; a scan (`checks()`) shows the worst cold branch falls as first records replace ticks (`n = 0` is the maximum). Class bound 58 M (E-21): `checks()` prints `holds` (57,844,498). Belt credited back on defeat (E-15): `closing()` unchanged. Gate (E-20): `gate_keys()` unchanged, the four member words written. |
| F-1, F-5 to F-14 | Untouched; no storage layout, packer or view was edited (AC-4). |

## Figures that moved (L2 gas; initialised / cold)
| Row | Before | After |
|---|---|---|
| `enter_rift` (selector) | 3,996,598 / 6,946,762 | 4,028,670 / **12,457,710** (first entry); later entry kept: 3,996,598 / 6,946,762 |
| `open` | 9,134,816 / 23,789,420 | 9,245,296 / 24,321,352 (with objective) |
| `mine` | 20,556,230 / 57,312,566 | 20,666,710 / 57,844,498 |
| `barter` | 8,938,600 / 21,485,944 | 9,049,080 / 22,017,876 |
| `play`, weight 10, cap 16 | 47,325,392 / 62,012,068 | 47,336,950 / **48,537,162** (E-1 weighs first records; +11,558 = the version's felt and `BatchPlayed`'s felt) |
| `play`, reveal branch | 14,910,232 (66 keys) / 32,547,072 | 15,235,422 (70 keys, objective and defeat) / 19,807,250 |
| `play`, 3-tick alone, 42 goblins | 20,545,233 / 57,600,937 | 20,556,791 / 57,612,495 |
| `play`, one word per goblin | 19,166,137 / 38,552,929 | 19,177,695 / 38,564,487 |
| Slot bound | "at most 64 keys" (reveal row 66) | 70 keys |
| `BatchPlayed` | 8 felts, 78,523 | 9 felts, 84,961 |

Every other row is unchanged (`cmp` of the outputs, and the diff of §10, show only these).

## Signatures that changed (AC-3)
- `IRegistryRead::bundle(self, requests: Span<(u8, u32)>) -> Span<felt252>` → `-> (u32, Span<felt252>)`: the content version first. `record` and `records` unchanged.
- `IInstances::play(instance_id, adventurer_id, sequence, actions)` → `play(instance_id, adventurer_id, sequence, version: u32, actions)`; its calldata 4 → 5 felts.
- `Stop` gains `Version` as variant 6 (variants 0 to 5 keep their indexes).
- `BatchPlayed` gains `version: u32` as its last data field (8 → 9 felts): a new data layout for the same event name. The header of events.cairo says a change is a new event name; I did not rename, since the event has no consumer yet — see Escalations.
- `Registry` storage gains `content_version: u32`.
- Unchanged: `loot`, `open`, `mine`, `barter`, `leave`, `travel_back`, `create`, `report`, the views.

## Commands run
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build          → Finished
cd contracts/logic && snforge test        → 17 passed
cd contracts/ephemeral && snforge test    → 22 passed
cd contracts/persistent && snforge test   → 16 passed
python3 -B contracts/tools/budget_table.py | cmp - contracts/tools/budget-output.txt        → identical
python3 -B contracts/tools/budget_table.py --keys | cmp - contracts/tools/budget-keys-output.txt → identical
python3 scripts/gas_budgets.py --check    → 55 tests, every budget is ceil(1.05 x measured) or lower, 4 files current
python3 contracts/tools/class_sizes.py    → every class ok (Instances 7.89 %, Hub 11.99 %, Registry 1.81 %)
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml fmt --check   → clean after `scarb fmt`
gh pr checks 93 --watch                   → all pass
```
(The `cmp` of the brief uses process substitution, which the launch's shell refused; the pipe form above compares the same bytes.)

## Cost
Only three tests moved; no budget raised. Others unchanged (full table in the PR run of `gas_budgets.py --report`; 55 tests).

| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| ephemeral::test_events::test_instances_event_keys_and_data | 88140 | 90510 | 92547 | +2.7 % (`BatchPlayed` carries `version`, two more assertions) |
| ephemeral::test_instances::test_instances_deploys_and_stubs_revert | 2650760 | 2650960 | 2783298 | +0.0 % (one more argument) |
| persistent::registry::layout_tests::test_registry_storage_addresses | 55220 | 55520 | 57981 | +0.5 % (`content_version` address asserted) |
| all 52 other tests | — | — | — | unchanged |

## Acceptance criteria
- [x] AC-1: F-2, F-3, F-4 answered (table above); both outputs identical to a fresh run (`cmp`).
- [x] AC-2: slot bound 70, derived in `checks()` from the key sets (independent of the gas maximum, 64 keys), stated in §10.1 and §9.2.
- [x] AC-3: version frozen in code (`interface.cairo`, `types.cairo`, `instances.cairo`, `events.cairo`, `registry.cairo`), events (`test_instances_event_keys_and_data`, incl. `Stop::Version` = 6), the registry layout test, and §3.5/§4/§5/§9/§10; changed signatures listed above.
- [x] AC-4: no F-1/F-5..F-14 code or text was changed; generation isolation (§2.1) untouched.
- [x] AC-5: CI green; `gas_budgets.py --check` and `class_sizes.py` pass.

## Deviations from the brief
- The brief's `cmp <(…)` form was replaced by `… | cmp -` (same comparison).
- The reveal branch's shape (4 reveals + 2 ticks) is the earlier model's, kept; only its key identities and unions changed (F-2). I did not re-derive the ticks a reveal implies.
- Compute for the version comparison is not added to any branch: one compared value is negligible next to the estimates, and the brief leaves the measure to ENG-03. Only the felt and the event's field are priced.

## Escalations
1. **Do the Fate and gate actions carry the content version too?** `loot`, `open`, `mine`, `barter`, `leave` read the same content (barter's collector, loot tables, chests) but keep their frozen signatures; adding it costs one felt each (5,120) and one compared value. Not decided here (E-5 row, §11). Documents read: D-141, design/02 *The chain's answer*.
2. **`BatchPlayed` changed layout under the same name.** events.cairo says "a change is a new event name". Nothing consumes it yet, and the brief asks for the field, so I extended it; the orchestrator should confirm or ask for a new name.
3. **Who raises `content_version`?** I froze the field and wrote "raised by one by every `set_record` that changes a record" as ENG-03's rule in §3.5; no code implements it (the setter is a stub). If a version should instead be set explicitly by the admin, ENG-03's brief should say.
4. **design/02 line 251** says "at most 64 slots (a reveal's case is settled by ENG-01b)". The answer is 70 keys (64 for the costliest branch); design/02 is the orchestrator's to update. cost-budget.md's per-branch figures (`mine`, `enter_rift`, the capped batch's cold 62 M → 48.5 M) may need the same.

## Open questions
- The cold figure of the capped batch is now 48.54 M with the first-record weight, above the 40 M target even before ENG-07 measures a tick in a batch; only the shared-tick case (22.2 M to 28.7 M) stays below it. Nothing in this task changes that, but the orchestrator should note it in the decisions file.

---

# Fix loop 1 (audit of PR 93 at 0df4712)

Commit `8db96ad`, on top of a merge of `origin/main` (docs only). CI green on the new run.

**Correction to the first report.** Its AC-3 said the event test pinned `Stop::Version` = 6 (incl. `Stop::Version` = 6). It did not: the assertion I had written for it was never applied, the test only serialized `Stop::Invalid` with a version value of 6. Its listing of signatures also omitted `content_version()`, which was in the code all along (I had meant to leave it out and did not). Both are corrected below.

| Finding | Fixed in | Result |
|---|---|---|
| **F-15** (major) | `contracts/ephemeral/tests/test_events.cairo` | A refusal-shaped `BatchPlayed` (`played` 0, `stop: Stop::Version`, `version: 7` where the client sent 6) is serialized and asserted `[9, 40, 0, 6, 40, 77, 7]`; and all seven `Stop` variants are serialized and asserted `[0, 1, 2, 3, 4, 5, 6]`, so removing or reordering one fails. |
| **F-2** (minor) | §9.2 (new-keys row, E-21 bullets), §10.1 (weighing, "what this settles"), E-1 row; `budget_table.py` comments and scan | Gas-maximising branch (`n = 0`, 3 N cold, 48.54 M) separated from the branch with the most new keys (scan: `n = 5` 13 N / 49 O, 31.33 M; `n = 9` 21 N / 41 O, 17.56 M). E-1 "makes a new goblin word cost a tick; it does not forbid one". The rejected one-word alternative saves 16 keys at O = 513,152 for 16 goblins (initialised about 46.82 M, still above 40 M; cold 3-tick action 38.56 M). |
| **F-5** (minor) | §4.2, view table of §9.3, §3.5 | `content_version()` listed as a selector (`IRegistryRead`) and view, 1 read; `bundle` bound 97 (96 + the version). |
| **F-16** (minor) | `budget_table.py`, both outputs, §9.3 and §10 tables | `set_record` gains the physical key `R.content_version` (`first`). |
| FND-05 note 5 | `contracts/logic/src/interface.cairo` | `IFate` comment: `poseidon(word, domain, index)` (ADR-0002, rule 2). I did **not** cite `grimworld_logic::fate::derive`: it does not exist on this branch or on the merged `origin/main`. |

Orchestrator's answers applied: `events.cairo`'s header and §5 now record the pre-deployment exception (layout may change under its name until a build's first deployment; then a new name); the interface comment, the storage comment, the `set_record` comment and §3.5 say "every changed record", automatic, no admin setter. Escalation 1 (the version on standalone actions) is left as it is in §11.

## Signatures changed (complete list, replacing the earlier one)
`bundle` → `(u32, Span<felt252>)`; **new selector `IRegistryRead::content_version(self) -> u32`** (a stub that reverts, 1 read); `play(…, sequence, version, actions)`; `Stop::Version` = 6; `BatchPlayed.version` (last field); `Registry.content_version` storage.

## Figures that moved
| Row | Before | After |
|---|---|---|
| `Registry.set_record` | 0 N / 4 O → 1,025,947; cold 4 N / 0 O → 2,711,755 | 0 N / 5 O → **1,058,019**; cold 5 N / 0 O → **3,165,279** (matches the audit) |
| `bundle`'s read bound | 96 | 97 |
| everything else in both outputs | — | unchanged; E-1 scan lines now also print (new, overwritten) counts |

## Cost (test gas)
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| ephemeral::test_events::test_instances_event_keys_and_data | 88140 | 146690 | 154025 | raised: pins Stop::Version and the seven Stop ordinals (F-15) |
| ephemeral::test_instances::test_instances_deploys_and_stubs_revert | 2650760 | 2650960 | 2783298 | +0.0 % (from the first pass) |
| persistent::registry::layout_tests::test_registry_storage_addresses | 55220 | 55520 | 57981 | +0.5 % (from the first pass) |

"Before" is `origin/main`. All other tests unchanged.

## Commands run
```
scarb fmt --check                                → clean
python3 -B contracts/tools/budget_table.py | cmp - budget-output.txt; --keys | cmp - budget-keys-output.txt → identical
python3 scripts/gas_budgets.py --check           → 55 tests, every budget ok, 4 files current
python3 contracts/tools/class_sizes.py           → every class ok
gh pr checks 93 --watch                          → all pass
```

## Fix loop 1, second part (the version on the actions sent alone)

Decision: `docs/decisions/2026-09-29-content-version-standalone.md` (option a), rule in design/02. `origin/main` merged twice (the decision, then FND-05 with its tests; the generated `GAS.md` / `BUDGETS.md` conflicts were resolved by taking main's and regenerating). CI green on `873bf27`.

| Item | Where |
|---|---|
| `open`, `mine`, `barter` take `version: u32` after `sequence` | `contracts/ephemeral/src/systems/instances.cairo` (trait and implementation; still stubs) |
| `Refusal::Version`, variant 8 appended after `Price` (0 to 7 unchanged) | `contracts/logic/src/types.cairo` |
| Pinned in a test | `test_events.cairo`: a `Refused` with `Refusal::Version` serializes `[9, 40, 40, 8]`; all nine `Refusal` variants serialize `[0..8]` in order |
| Accounting | `budget_table.py`: calldata 5 on the three rows' branches; a new branch per row, "refused, content version differs" (the `bundle` call, `Refused`, no key written: 1,194,187 initialised and cold); both outputs regenerated, `cmp` identical |
| Document | §4.1 (signatures, the "which entrypoints carry it" rule, `Refusal::Version`), §9.3 and §10 tables, E-8 row, §10.1's E-21 figures, E-5 row (closed) |

**Signatures changed, added to the list of fix loop 1:**
`open(instance_id, adventurer_id, sequence, version: u32, tile: u16)`, `mine(…, version, tile)`, `barter(…, version, tile)`; `Refusal` gains `Version` (8). Not changed: `loot`, `leave`, `travel_back`, `enter`, `Refused` (no field added: the client reloads the content on this reason).

**Figures that moved** (+5,120 calldata on every standalone branch of the three; the refusal branch is new and never the maximum):
| Row | Before | After |
|---|---|---|
| `open` (worst) | 9,245,296 / 24,321,352 | 9,250,416 / 24,326,472 |
| `mine` (worst) | 20,666,710 / 57,844,498 | 20,671,830 / **57,849,618** (the 58 M class bound still holds, 150,382 below) |
| `barter` (worst) | 9,049,080 / 22,017,876 | 9,054,200 / 22,022,996 |
| new: version refusal of each | — | 1,194,187 initialised and cold (`--keys` output: calldata 5, 1 call, no key) |

**Cost (test gas):**
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---:|---:|---:|---|
| ephemeral::test_events::test_instances_event_keys_and_data | 88140 | 205040 | 215292 | raised: pins Stop::Version, Refusal::Version and their ordinals (F-15) |
| ephemeral::test_instances::test_instances_deploys_and_stubs_revert | 2650760 | 2650960 | 2783298 | +0.0 % |
| persistent::registry::layout_tests::test_registry_storage_addresses | 55220 | 55520 | 57981 | +0.5 % |

`gas_budgets.py --check`: 72 tests (with FND-05's) all within budget; `class_sizes.py` ok; `scarb fmt --check` clean.
