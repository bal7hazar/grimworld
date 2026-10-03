Archived at the merge of #320, 6887010.

## Report

Model: Opus 5.5 (`claude-opus-5-5`)

### Pushed: the review fixes at 241bf9a

- The clone's config was repaired by the owner, and `core.hooksPath` is removed until FND-17.
- `scripts/prepush.sh`, run by hand at 241bf9a, passed every check: fmt, `gas_budgets.py --self-test`, the contracts build, `gas_budgets.py --check` (221 s, files current), `class_sizes.py`.
- Pushed as a fast-forward, 9e9411b..241bf9a. **The PR's head is 241bf9a.** No gas figure moved.
- The project manager accepted `create_adventurer` +0.12 % and `delete_adventurer` +0.26 % under D-144. The ENG-01 §3.3 line goes in the orchestrator's next documents PR.

Earlier incident (for the record): with the pre-push hook enabled, a retry under `GIT_WORK_TREE` let `gas_budgets.py --self-test` write to the repository. That probably left the shared clone's `core.bare` and `core.worktree` broken. It is fixed by the owner. FND-17 is to make the hook and the self-test safe in worktrees.

### Summary
- ENG-R1b part 1 is open as PR #320. **New head 9e9411b**, pushed once with every fix.
- **Fixes applied in that push:**
  - the review at f480134 (Sonnet): its two text notes, in REPORT.md and the PR body;
  - the organisation audit t-0046 (Opus): F-1, F-2, F-3, F-6, F-7 and F-8. F-5 goes to ENG-R1c.
- `origin/main` (0d465bf) was merged in first. It brought `prepush.sh` and CI changes; no Cairo source or budget changed.
- **F-1:** the six free functions are scoped in traits:
  - `EffectPackingTrait` (private): `pack_effect`, `unpack_effect`;
  - `DeadlinesTrait`: `pack_four28`, `unpack_four28`;
  - `MemberTimersTrait::empty`: `empty_member_timers`;
  - `RosterTrait::mask`: `mask_roster_page`.

  Their callers are updated, including `models/goblin.cairo`'s two calls (its own free functions are left for ENG-R1c). AC-2 is re-ticked.
- **No gas figure moved.** A full workspace run gave 953 tests passed, and `gas_budgets.py --check` reports the 4 generated files current.
- `Instances` and `Market` read and write their storage only through a store: `InstancesStoreTrait` and `MarketStoreTrait`.
- `Instances`' checks are in `Assert` impls. The unit tests of every module this lot touched are in that module (D-167).
- The probe gained `--scope r1b`. Its "before" stream, `lifecycle-stream-before-r1b.json`, was recorded on main before any code change. It was recorded again on main after FND-11 (fe5ed0c) and is byte-identical.

**Note 4, measured:**
- **`Instances`: typed slots kept for every slot.** `Stored<M>` and `StoredMember` keep the layout and both probe streams equal, and every entrypoint falls:
  - `create`: −8,540 l2 gas;
  - `leave`: −3,800 to −8,030;
  - `travel_back`: −5,800;
  - `set_controller`: −2,000.
- **`Hub` (step 2), fully typed, raised the expedition's path:**
  - `enter`: +300 without a belt, +3,940 with 4 belt pages;
  - the closing `report` with 4 pages credited: +3,940;
  - `travel`: +200.
- **So, per step 3, `adventurers` and `balances` keep their offset access**, with the measure written above it. `accounts`, `account_adventurers` and `packs` stay typed.
- **At the head, no figure on the expedition's path rises:**
  - `enter`, `report` and `travel` are unchanged against main;
  - the `Instances` calls fall.
- **Rises elsewhere** (for you under D-144, both under +10 %): `create_adventurer` +0.12 % at most and `delete_adventurer` +0.26 % at most. The account list's typed pages cause them.
  - These are per-call figures: `get_available_gas` around the single call in `test_accounts`.
  - The whole-test rows of BUDGETS.md mix several calls: `test_create_adventurer` −0.01 %, `test_delete_within_the_final_page` +0.016 %.
- **The path's drop comes from merging reads and writes under one address hash, not from the typed slots.** Alone, the typed slots cost slightly more: entering +1,800, snapshot +600.

The merge no longer waits for the owner's reading, as you said; the PR body has no waiting line. The `Registry` part waits for CBT-05a, on this branch.

### Files changed
- `contracts/ephemeral/src/store.cairo`, `helpers/stored.cairo`, `systems/instances.cairo`, `models/member.cairo`, `models/instance.cairo`; `tests/test_layout.cairo` and `tests/test_lifecycle.cairo` (budgets lowered).
- `contracts/persistent/src/store.cairo`, `systems/hub.cairo` (the `Storage` struct), `systems/market.cairo`, `models/market.cairo`, `models/account.cairo`, `models/lanes.cairo`, `models/stored_record.cairo`. In `tests/`: `test_layout.cairo` removed; budgets and raise notes in `test_accounts.cairo`, `test_build.cairo` and `test_lifecycle.cairo`.
- `contracts/tools/lifecycle_probe.py`, `contracts/tools/lifecycle-stream-before-r1b.json`.
- `docs/architecture/ENG-01-interfaces.md` §3.2 and §3.4; `docs/BUDGETS.md` and the `GAS.md` files (generated).

### Commands run
All figures were taken on Scarb 2.20.1 and snforge 0.64.0, after merging `origin/main` (0b157e0).

```
lifecycle_probe.py --expect lifecycle-stream-before.json             stream equal (85 tx, 38 events, 97 hub keys)
lifecycle_probe.py --scope r1b --expect lifecycle-stream-before-r1b.json
                                                                     stream equal (85 tx, 21 events, 83 + 43 keys, 6 drawn)
snforge test --workspace --fuzzer-seed 1 (RAYON_NUM_THREADS=1)       69 + 652 + 232 passed, 0 failed
gas_budgets.py --check                                               953 tests, 4 files current
class_sizes.py                                                       Instances 28.92 %, Hub 45.90 %, all ok
check.py                                                             vectors as computed
scarb fmt --check --workspace                                        clean
```

Before the push, `scripts/prepush.sh` failed only on `pnpm test`: one indexer CLI test hit its 5 s timeout (8.9 s on the loaded machine). The indexer is untouched here, and that test file passes alone (5/5 in 4.5 s). Its build-lock-bound steps were skipped, as the script allows; I had run the workspace and `gas_budgets.py --check` myself just before, on the same tree, and they passed. CI: not polled since the push.

### Acceptance criteria
- **AC-1** No storage access left in `instances.cairo` or `market.cairo` outside tests. The one grep hit, `record.entry()`, is the gate's tile, not storage. `registry.cairo` is untouched: that is part 2.
- **AC-2** `InstancesAssert`, `PlacementAssert` and `MemberAssert`, with their `errors` modules. `market_key` is scoped as `LotTrait::market_key`.
- **AC-3** The three layout tests are equal, and both `--expect` runs are equal.
- **AC-4** The note-4 test pairs, the per-call tables and the rule's outcome per slot are in REPORT.md and the PR. Both stores' module docs say which slots are typed and which are not, and why.
- **AC-5** `--check` passes. No rise on the expedition's path. Every class is under 50 %.
- **AC-6** Tracking table: no model tracked, with the reason for each. Tests are in their modules. The gate scripts pass. CI: pending.
- **AC-7** The owner's reading list opens REPORT.md and the PR body.

### Deviations from the task
- The `Registry` part is held for CBT-05a, as the task says.
- `Hub`'s typed declaration is partial, by the rule's step 3.
- FND-11 merged during the lot. The baseline was re-recorded from main and is identical.

### Escalations
1. ENG-01 §3.3 (`Hub` storage) is not in the allowlist. It needs one line saying that `accounts`, `account_adventurers` and `packs` are now declared as typed slots.
2. The probe's r1b scope should join the planned CI job for `--expect` (open question 3).
3. Done (audit F-1). Only `models/goblin.cairo`'s own free functions remain, for ENG-R1c.
4. starknet-devnet 0.10.0 is installed, with its hash matching the pin, but asdf's shims are not on the session's PATH. The probe ran with `PATH=$HOME/.asdf/shims:$PATH`.

## Next
Run the delta review of #320 at 241bf9a
Check #320's CI at 241bf9a when the pr-followup routine reports it
Have FND-17 make gas_budgets.py --self-test unset GIT_DIR and GIT_WORK_TREE
Prompt me for the Registry part after CBT-05a merges

## Remember
- Never run a git hook under a forced `GIT_WORK_TREE`/`GIT_DIR`: a script that runs `git init` or commits in fixtures then writes to the shared clone (19:22, `core.bare`/`core.worktree`).
- A typed storage member access costs about +100 l2 gas against `read_at_offset`. Reading several fields of one entry costs much more unless its sub-pointers are taken once (`sub_pointers`/`sub_pointers_mut`); then the reads merge under one address hash.
- A long `snforge` or `with-node` run on the VPS can wait on the shared heavy lock for a long time. Run it with `run_in_background` and the longest timeout, not under a 10-minute foreground limit.
- `set_budgets.py` can drop a test's trailing budget note ("kept: …"). Check its diff on files outside the lot.
