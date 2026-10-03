Archived at the merge of #293, a3c3268.

## Report

Model: Sonnet 5.5

### Summary
The game builds, tests, measures and runs on the local node on Scarb 2.20.1 and starknet-foundry 0.64.0; every budget is re-measured; the single-threaded build pin is applied with a CI check of 3 clean builds (CASM and Sierra felt counts, not class hashes: SPK-13b, #283). CI result: see Next.

### Files changed
`.tool-versions`, `contracts/Scarb.toml`/`Scarb.lock`, `.github/ci/install-snforge.sh` (0.64.0 SHA-256), `.github/ci/build_stable.py` (new), `.github/workflows/ci.yml` (RAYON pin, timeout 30, the 3-build step), `scripts/gas_budgets.py` (the pin), `GAS.md` x3 and `docs/BUDGETS.md` (generated), `#[available_gas]` values in the packages' tests and unit tests (no code), ENG-01 §1.3 table, ADR-0007, CAIRO.md, COMMON.md, contracts/README.md, setup-toolchain.sh comment.

### Commands run
- scarb build (RAYON=1): 81 s; `gas_budgets.py`: first run 895 passed / 40 failed (budgets exceeded by the new compiler), then 935 passed after re-measuring; `gas_budgets.py --self-test` OK and `--check`: "935 tests, every budget is ceil(1.05 x measured) or lower, 4 files current".
- `class_sizes.py`: Hub 37,589 CASM felts (45.89 %), all ok.
- `scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect …`: `{"stream": "equal", "transactions": 85, "events": 38}`.
- `.github/ci/build_stable.py` x3 clean builds: 11 classes, one CASM and one Sierra size each.
- Compiler time per build: 30 s with 8 threads, 53 s with 1.

### Acceptance criteria
- AC-1: pins in place; devnet 0.10.0 was already installed (only missing from PATH, nothing installed); CI result below. The snforge 0.64.0 SHA-256 was computed from the HTTPS download (no published checksum file; `gh api` digest cross-check was refused to me).
- AC-2: budgets above; cause the compiler. Logic 400 falls/0 rises; ephemeral 28/24; persistent 82/145 (largest +18.5 %, −56 %). Cost rows: `set_build` worst case budget 8,501,927 → 9,100,742 (8,667,373 measured); `enter` tests +4 to +6 %; tick benchmarks −7,730 each. ENG-01 §9.2's 5,464,542 is NOT recomputed (CBT-05a touches it): recompute at the second merge.
- AC-3: probe stream equal.
- AC-4: RAYON_NUM_THREADS=1 on CI cairo jobs and gas_budgets; 3-build check. No script in the repository declares (the probes only use the node), so none to pin.
- AC-5: nothing global touched; `indexer/emitter/` untouched (needs: Scarb 2.20.1 and its own lock when IDX-01 moves).

### Rises on create, leave, travel_back (PM condition 1)
Command: BUDGETS.md of origin/main against this branch, tests whose name has play/create/leave/travel with measured up. No test named `play` exists. Others (test, old, new, %):
- ephemeral test_lifecycle::test_create_first_entry 31790192 32575012 2.5%
- ephemeral test_lifecycle::test_create_refusals 33039406 33860776 2.5%
- ephemeral test_lifecycle::test_create_reuses_the_slot 44105551 45690521 3.6%
- ephemeral test_lifecycle::test_create_sealed 25877196 26583366 2.7%
- ephemeral test_lifecycle::test_create_without_tasks 27805866 28512036 2.5%
- ephemeral test_lifecycle::test_leave_to_a_hub 33228136 34221056 3.0%
- ephemeral test_lifecycle::test_leave_to_a_location 39224907 41012107 4.6%
- ephemeral test_lifecycle::test_travel_back 31536609 32510779 3.1%
- persistent test_accounts::test_create_adventurer 23924760 24718590 3.3%
- persistent test_accounts::test_create_bad_profession_refused 9286710 9660880 4.0%
- persistent test_accounts::test_create_empty_name_refused 9296770 9666540 4.0%
- persistent test_accounts::test_create_no_free_slot_refused 19504540 20381910 4.5%
- persistent test_accounts::test_create_without_account_refused 7654840 7954210 3.9%
- persistent test_lifecycle::test_travel 35630367 37310737 4.7%

The acceptance is recorded in `docs/BUDGETS.md` ("Accepted rises", written by the generator) and in the PR description. Head: aba6d53 (re-review by Opus: PASS; all checks green on this head (18 pass, indexer-node skipped); 386efec had all checks green incl. class-artefacts, build-root.json scarb 2.20.1). The 14 rises are listed in BUDGETS.md's Accepted rises.

### Single-call margins (no call crosses a limit)
The tests above 30 M are **whole-test totals** (deploys, registry content, setup, several calls). Per call, on this machine: the node probe (`lifecycle_probe.py`, the real 2.20.1 classes on starknet-devnet 0.10.0, one transaction each) and the figures the tests print themselves (`gas … (doubles)`, snforge).

Limits: **40 M**, the project's bound for one transaction/batch (design/02; ENG-01 §10.1; SPK-15's batch limit, `docs/decisions/2026-10-01-spk-15-levers.md`). **Starknet's per-transaction cap: 1.1 × 10⁹ L2 gas** per docs.starknet.io (Chain info, https://docs.starknet.io/learn/cheatsheets/chain-info); the repository does not record it (ENG-01 and OPERATIONS cite the 40 M only), so this one is external and not re-verified by me beyond that page.

| Call | Gas per call, node probe | In-test (snforge) | vs 40 M: margin | vs 1.1 B: margin |
|---|---:|---:|---:|---:|
| `create_adventurer`, cold / initialised | 4,894,960 / 4,532,960 | 987,890 / 1,012,810 | 35.1 M | 1.095 B |
| `enter`, first entry (new slot) | 9,488,400 | 3,022,966 (create) | 30.5 M | 1.09 B |
| `enter`, later; belt worst case | 3,942,400; 4,702,400 | 2,930,306; 2,304,500 | 35.3 M | 1.095 B |
| `leave` to a hub / to a location | 2,502,400 / 3,272,640 | 1,666,460 / 2,794,076 | 36.7 M | 1.097 B |
| `leave`, belt credited back (4 pages) | 3,262,400 | — | 36.7 M | 1.097 B |
| `travel_back` / with the belt | 2,297,280 / 3,057,280 | 1,450,613 | 36.9 M | 1.097 B |
| `travel` | 1,226,560 | 312,133 | 38.8 M | 1.099 B |

The costliest single call is the first `enter` at 9.49 M (23.7 % of 40 M). No single call crosses either limit. The 40 M and 45.7 M totals are tests that deploy the world and make several calls.


### Deviations from the task
- 3-build check compares CASM and Sierra felt counts, not a class hash (PM, #283). No class hash is pinned or compared anywhere.
- Edited `#[available_gas]` attributes in `contracts/logic/src/**` (400 falls) because the compiler forces them; no code. Expect a merge conflict or regeneration with CBT-05a.

### Escalations
- `scripts/lock.sh` defaults RAYON_NUM_THREADS to 4, so agents' local builds via the lock are not single-threaded (shared file, not mine).
- STATUS.md/§9.2 figure and CHANGELOG are the orchestrator's.

## Next
Ready to merge at aba6d531be3a6ed38d6c0a903f168899095bb4d7
Remove the worktree and branch after the merge
