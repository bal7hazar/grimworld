Archived at the merge of #334, f50c1fc.

## Report

### The delta review and cost re-audit, pushed at `5b412fe`

- `7e4ea53`: the review's four items (route (c) potion test, first-record lookup, shared keys, reworded comments) and the re-audit's notes (N-1 "the worst tick measured" and a bomb's ≈ 48.8 M (E); N-2 the row renamed; N-5 the step-2 bound's scope). §9.2 keeps the audited figures (`ba56f53`) and gives this head's: worst tick measured 45,890,031, a goblin carrier through the class 4,079,671.
- `5b412fe`: `origin/main` merged (FND-20, `ac10593`). A full workspace run under `prlimit --as=8589934592` (`--max-threads 2`): 1,009 passed; `gas_budgets.py --check` passes; no budget moved. `TickLibrary` 49,947 felts (60.97 %), `ExecutorLibrary` 80,122.
- The push ran the hook uncapped (the orchestrator, 2026-10-03: the gas check peaks at 4.88 GB, the client suite at 467 MB; node aborts under `--as`). The first attempt passed every check but GitHub closed the connection during its 514 s; one retry with an SSH keepalive for that command only pushed `7596b9e..5b412fe`.
- An earlier capped full run (before FND-20) failed on "memory allocation of 268435456 bytes failed" in `grimworld_logic`'s unit tests (the heavy vector tests, unchanged by this lot); FND-20 resolved it.

### D-207: option (3)'s levers in, the worst tick measured, pushed at `7596b9e`

**Measured on the VPS through `TickLibrary`** (`test_tick::test_cost_rep_*`, each less its fixture): **worst tick 45,999,941** (the member's activation and 8 goblin carriers together; 115.0 % of 40 M, 4.18 % of 1.1×10⁹), accepted as a one-tick batch by the project manager, 2026-10-03 (D-207). The 8 goblin carriers alone 36,895,379. **For the owner: 4,090,351 a goblin carrier through the class.** The member's Cinder Ring 9,102,352; the idle tick 4,172,567.

| | Baseline | Lever (1) | Lever (2), reverted | **Lever (3)** |
|---|---:|---:|---:|---:|
| A goblin's carrier | 6,495,595 | 6,190,565 | 7,250,510 | **4,090,351** |
| The member's Cinder Ring | 9,405,232 | 9,069,972 | 10,129,392 | **9,102,352** |
| The 8 goblin carriers' tick | 56,137,329 | 53,697,089 | 62,181,249 | **36,895,379** |
| `ExecutorLibrary` (≤ 80,420) | 80,122 | 80,122 | 79,349 | **80,122 (97.81 %)** |
| `TickLibrary` (≤ 75 %) | — | 60.49 % | 62.12 % | **61.04 %** |

Commits pushed in one push (`ba2ec04..7596b9e`):
- `eba845a` the library-call figures marked as fixture artefacts;
- `f1288eb` the review's fixes (behavioural test, the entry's target, the TRAP early return) and F-2's fixtures, one goblin a tile;
- `4443a4f` lever (1); `ba56f53` lever (3) (lever (2) measured and reverted, its diff kept in the scratchpad);
- `89c9fdd` `test_cost_rep_all`, the worst tick as one state;
- `7596b9e` ENG-01 §9.2 measured (26,422,703 kept as the earlier, understated figure; the action phase's immediate carrier and ENG-07's step-2 carriers named as not in it), the parity hashes re-taken for F-2, every budget regenerated.

Checks at this head:
- one `snforge test --workspace --fuzzer-seed 1` on the VPS: **1,008 passed, 0 failed**; `gas_budgets.py --check` (from that run): every budget current, 4 files current;
- `class_sizes.py`: ok with D-200's thresholds;
- `check.py` under `prlimit --as=8589934592`: window 2,065, hit 203, fate 218, packing 520 cases, as computed;
- `scripts/prepush.sh` by hand, capped: all checks passed (the lock-bound checks skipped there, lock busy; run above);
- the push ran its hook under the same cap.

The parity hashes: `test_parity_states` (7 of 8), `_terms_one` (13), `_terms_eight` (10), `_terms_mixed` (7) moved; F-2's words carry each goblin's tile. With the positions zeroed all five parity tests passed at lever (3)'s code; `test_parity_examples` did not move.

The D-144 list (`library/D-144-budget-rises.md`): 325 rises; 272 on the expedition's path, 59 above +10 %; 53 off it, all ≤ +5.91 %. Accepted under D-207 for route (c) with levers 1 and 3 and F-2. The 835–932 M library-call figures are gone (now 36.8 M to 67.7 M), kept in the notes as the earlier head's fixture artefacts.

Memory (the new rule): the one build I measured, `check.py`'s hit vectors, held 1.1 GB resident, 4.0 GB virtual; I saw none above that. Every build since runs capped.

Not done: `origin/main` is not merged (14 commits behind; FND-19's hexx 0.1.0-rc.2 among them changed no budget on main). CI checks the head commit.

**Goblin weapon hit, measured:** **2,103,191** L2 gas through `ExecutorLibrary` (route (c), at `f1a33f4`, the same at the PR's head); **937,961** levered and **1,129,193** naive in one class.

**Decisions this lot carries:**
- Route (c), option (2), decided by the project manager, 2026-10-02 (D-200).
- The per-hit cost through ExecutorLibrary (2,103,191 measured at f1a33f4) accepted by the owner, 2026-10-02 (D-198, D-200).
- Option (3), the cost-lowering design lot, is a later PLAN row, after CBT-05a.

**Step 5, done:**
- `origin/main` merged, with FND-17's fixed hook (`aa5bcc1`, confirmed an ancestor of the head).
- Every budget regenerated from a workspace run on the VPS, and `gas_budgets.py --check` passing (994 tests).
- `class_sizes.py` with D-200's thresholds: `ExecutorLibrary` 80,122 felts (97.81 %), `TickLibrary` 45,427 (55.45 %).
- `check.py`: `hit.jsonl` at 203 cases (ids 200–202 for track CV).
- The D-144 list, `library/D-144-budget-rises.md`: 323 rises; 270 on the expedition's path, 59 of them above +10 %; 53 off it, all ≤ +5.91 %.
- ENG-01 §1.3 (D-200) and §9.2 (the combined share recomputed on 2.20.1: 6,051,547, 4.12×; with the executor, 26,422,703, 17.98×).
- The inventory, the vectors README, the `client/sim/` changes.
- `scripts/prepush.sh` all green by hand, then **one push**, `ba2ec04`.

**Incident (2026-10-03):** my earlier push ran the old pre-push hook (my branch predated FND-17). Its `gas_budgets.py --self-test` ran with git's `GIT_DIR` and set `core.bare = true` in the shared clone. The owner repaired it; the fixed hook is now in the branch, and the clone was intact after the final push.

Model: Opus 5.5 (claude-opus-5-5)

### Option (2), done so far
1. **`78731a4` reverted** (`62f4973`). The code is `2a49f47`'s, plus track CV's three hit cases (`3ae73ad`).
2. **The scope cut:** the executor's shape call is `WindowTrait::near` (`SINGLE`, `RING_1`, `DISC_1`, by `shape`'s own rule). `DISC_2` and `DISC_3`'s `disc` leaves `ExecutorLibrary`.
   - It is limited to what the MVP's content does not use: those shapes have no MVP source (FX-21) and the validators have refused them since CBT-01. `test_near_agrees` checks `near` against `shape` at every centre.
   - **Deviation, accepted by the orchestrator:** the brief allows `types/window.cairo` for a combined call only; `near` is a second function there, serving the brief's own scope cut. One line in the PR.
3. **The rewire:** `TickLibrary`'s step-1 hook (`types::executor::Delegate`) calls `ExecutorLibrary::conclude` once a carrier.
   - It carries the words of every member, the source, the addressed goblin, and the goblins within one tile of the source or of the address (exact for the MVP's shapes, radius 1 at most).
   - It loads back what returns through the call's index, kept for the call (`WordsTrait::indexed`), and appends the kills in resolution order.
   - `ITickLibrary::run` takes the executor's class hash (`executor: ClassHash`) besides `board`. The pipeline's rules are bound by `Destruct` (the index is a dictionary).
   - The in-class executor (`Executor` rules) stays for the tests only; `TickLibrary` no longer reaches it.

### Earlier: the final table before option (2)
 (measured unless marked E)
| sha | Step | ExecutorLibrary felts | % of 81,920 | Room | TickLibrary felts | % | Hit through the class | In-class levered | In-class naive |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `d889419` | after option (ii) | 92,681 | 113.14 % | −10,761 | 111,571 | 136.20 % | 1,936,878 | 784,188 | 973,630 |
| `2a49f47` | 1. one actor type (`Unit`) | 82,113 | 100.24 % | −193 | 101,003 | 123.29 % | 2,094,071 | 937,961 | 1,129,193 |
| `0931bd8` | 2. shared readers not inlined (reverted, `4dff937`) | 82,924 | 101.23 % | −1,004 | 101,814 | 124.28 % | 2,248,211 | 1,092,101 | 1,283,333 |
| `d7b3611` | 3. `shape` behind one call (reverted, `90ad422`) | 82,800 | 101.07 % | −880 | 101,690 | 124.13 % | 2,249,671 | 1,093,561 | 1,284,793 |
| **`78731a4`** | **change 1: the actors' in-call values across the call, not their words** | **77,623** | **94.75 %** | **4,297** | 101,003 | 123.29 % | **2,879,300** | 937,961 | 1,129,193 |
| — | change 2: a `Unit` of the hot fields only | nothing to remove (below) | | | | | | | |
| — | change 3: the trap trigger out of the class | nothing to remove (below) | | | | | | | |

- **The room CBT-05b's resolution parts need in `ExecutorLibrary` (E): 5,000–15,000**; the stop rule asks 15,000. At `78731a4` the room is 4,297.
- **The logic suite at `78731a4`:** 612 passed, 75 failed: 74 gas budgets, and `test_vectors` (the hit cases' digest, regenerated by `check.py` at step 3). Nothing else.

### (a) Why the hit through the class rose by 785,229 with change 1
The call now carries more, both ways, and the class does more with it:
- **The actors' in-call values instead of their words.** A `Member` is 7 words plus about 25 hot and derived fields (`models/index.cairo:268–305`); a `Goblin` is 2 words plus about 23. A member's words were 7 felts and a goblin's 4 (with its entity and flag). So each call's calldata grows by about 25 felts for the member and 21 for the goblin, in and out.
- **The whole content.** Before, the test passed the 12 sheets the actors' loads needed. The actors' in-call values hold positions in the content they were derived from, so the call must now carry that content: the test's 26 skills, both castes, their kits' sources. The class rebuilds its sheets: the index, the kits, and every skill's entries decoded (L3's once-a-call decode now runs once a carrier).
- **What it saves:** the loads and stores of the actors (the fixture fell by 177,020 too, as the arguments are cheaper to build).
- The split of the 785,229 among calldata, the index and the decode is not measured apart. By construction most of it is the content's sheets rebuilt at each call; a real call would carry the batch's content, up to 38 skills (ENG-01 §9.2).

### (b) `TickLibrary` at 101,003 on this branch
- **Yes, it still compiles the in-class executor**, through the step-1 hook, not the tests' harness: `TickLibrary::run` builds `ExecutorTrait::new(board)` (`contracts/logic/src/systems/tick.cairo:25`); `ExecutorRules::resolve` calls `ExecutorTrait::conclude` (`types/executor.cairo:1150`), which calls `execute`. That is route (a)'s wiring, kept while the routes were measured.
- **`TickLibrary` under route (c), with the executor behind the call: not measured.** The only figure is 27,023 (32.99 %) with the `Idle` rules, Scarb 2.19, `ab71732`'s probe. Route (c) adds to that the hook's call to `ExecutorLibrary` (the class hash as an argument of `run` or as configuration, and the actors' values gathered and written back), not yet built.
- My estimate for `TickLibrary` under route (c): **about 30,000–35,000 felts (E)**, 37–43 %, so about 47,000–52,000 of room for ENG-07's act hook and CBT-05b's action phase, which I estimated at 22,500–75,000 together.

### (c) Changes 2 and 3: nothing to remove
The evidence, with file and line, is in *Continuing from `2a49f47`* below.

### (d) Judgment of what is left
- **Route (c) fits the hard limit now** (77,623, 94.75 %), but not with the room the stop rule asks for CBT-05b (4,297 against 15,000). Its hit through the class is 2,879,300 at `78731a4`; it was 2,094,071 at `2a49f47` without the room.
- **No further rework I can name with confidence closes the room and keeps the hit.** The next candidates are a different contract between the two classes (only the carrier's sheets across the call, positions translated; the snapshot words split out of the actors), which is a design change, not a rework.
- **The decisions left, for the project manager:**
  - accept about 4,300 felts of room in `ExecutorLibrary` and place CBT-05b's resolution parts in `TickLibrary` or a third class;
  - keep `2a49f47`'s shape (82,113, over the limit by 193) and cut scope further;
  - or take the design change above to a lot of its own.
  - In each case the hit through the class (about 2.1–2.9 M) goes to the owner with ENG-07 (R-2).

### Continuing from `2a49f47` (the project manager, 2026-10-02)
- **Reverts:** `0931bd8` and `d7b3611` reverted by new commits (`90ad422`, `4dff937`). The code equals `2a49f47`, plus track CV's three hit cases (`3ae73ad`).
- **Change 1, `78731a4`:** the actors' in-call values across the class call instead of their words (no load or store of an actor in `ExecutorLibrary`). Pending the Mac's measure.
- **Change 2, a `Unit` holding only the hot fields: nothing to remove, not built.** Evidence:
  - `Member` (`contracts/logic/src/models/index.cairo:268–305`) and `Goblin` (`:321` on) hold the hot fields and the words.
  - The executor's member paths write inside the words: the recharges at `contracts/logic/src/models/member.cairo:317` (an interrupt through `knock`), Crippled in `MemberTimers` at `:377` and `:854` (`apply`), the `hits` counter in `MemberState` at `:388` (`land_weapon_hit`), the held effects in `MemberEffects` at `:437` (`set_effect`, through `hold`, `put`, a spent charge).
  - They read the snapshot words at every hit: `MemberBar` at `:340`, `MemberKit` at `:393`, `:401`, `:411`, `MemberStats` at `:477`, `:485`, `:506` (`MemberSnapshotTrait`).
  - The goblin's paths write its two words: `GoblinState` at `contracts/logic/src/models/goblin.cairo:248` (recharges), `GoblinTimers` at `:263`, `:284`, `:540` (Crippled, the held effect).
  - On a member only `health_regen` and `energy_regen` go unread by the executor: 2 of about 32 felts.
  - A lean view would need the words split into their fields: a model change across the tick, not this rework.
- **Change 3, the trap trigger out of the class: nothing to remove, not built.** Evidence:
  - `ExecutorTrait::trigger` and `trap` sit at `contracts/logic/src/types/executor.cairo:1486` and `:1552`.
  - `ExecutorLibrary`'s one entrypoint calls only `ExecutorTrait::execute` (`contracts/logic/src/systems/executor.cairo:35`).
  - `TickLibrary`'s rules (`contracts/logic/src/systems/tick.cairo:25`, `ExecutorTrait::new`) reach the executor through `ExecutorRules::resolve` → `ExecutorTrait::conclude` (`executor.cairo:1150`) → `execute`.
  - The only caller of `trigger` is a test (`executor.cairo:2759`, inside `#[cfg(test)]`).
  - Sierra keeps the code reachable from a class's entrypoints only, so neither class holds `trigger` or `trap`. CBT-05b adds them when it wires the trigger.

### History: route (c)'s first table
| sha | Rework | ExecutorLibrary felts | % of 81,920 | TickLibrary felts | % | Hit through the class | In-class levered | In-class naive |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `d889419` | reference (after option (ii)) | 92,681 | 113.14 % | 111,571 | 136.20 % | 1,936,878 | 784,188 | 973,630 |
| `2a49f47` | 1. one actor type (`Unit`) | **82,113** | **100.24 %** | 101,003 | 123.29 % | 2,094,071 | 937,961 | 1,129,193 |
| `0931bd8` | 2. shared readers not inlined | 82,924 | 101.23 % | 101,814 | 124.28 % | 2,248,211 | 1,092,101 | 1,283,333 |
| `d7b3611` | 3. `shape` behind one call | 82,800 | 101.07 % | 101,690 | 124.13 % | 2,249,671 | 1,093,561 | 1,284,793 |

Fixtures: class 12,200,304; in-class 10,401,734. Hits over 6.

### Why reworks 2 and 3 cost more, and rework 1 cost gas
- **Rework 1 (−10,568 felts, +157,193 a hit):** `Unit`'s methods take the enum whole. Each `ref self: Unit` call moves the `Member` or `Goblin` it holds (about 25–30 felts) out of the enum, matches on it and rebuilds the enum. The compiler inlined those methods into their callers, which kept the size down, but every method call now pays the moves and the match: gas went up.
- **Rework 2 (+811 felts, +154,140 a hit):** with `#[inline(never)]` on `Unit`'s methods and the snapshot readers, every call site gains a call frame and the arguments' moves; for a method taking `@Unit` or `ref Unit` that is the whole actor. The compiler also lost what inlining let it remove: a match on `Unit` whose variant is known at the call site, unused results, branches. The bodies saved were smaller than the frames and moves added, so size grew a little and gas a lot.
- **Rework 3 (−124 felts, +1,460 a hit):** ENG-02's `shape` was in the executor only twice; one wrapper saved one copy, less its frame.

### Can another change bring `ExecutorLibrary` under 81,920 with room for CBT-05b? (all estimates)
**Room CBT-05b needs in this class (E):** only its resolution parts would join `ExecutorLibrary`: the placement's write of a kind-9 object, and the trigger's detection on a move. About **5,000–15,000 felts**, a part of the 12,500–40,000 estimated for all of CBT-05b. The action phase's legality and costs belong in `TickLibrary`.

| Change | Felts (E) | Hit through the class (E) | Why |
|---|---:|---:|---|
| Start from `2a49f47`, reverting reworks 2 and 3 | 82,113 (measured) | 2,094,071 (measured) | the best size |
| Pass the actors' hot views to `ExecutorLibrary` instead of their words (no `MemberTrait::load`/`store` or `GoblinTrait::load`/`store` in that class) | −6,000 to −12,000 | −300,000 to −600,000 | the class loads and stores the member's 7 words and the goblin's 2 at each call; the views are what the executor reads |
| `Unit` holding only the hot fields the executor reads and writes (not the whole actor), written back once | −4,000 to −10,000 | −100,000 to −200,000 | the moves above are of whole actors |
| A trap's trigger and placement out of `ExecutorLibrary` (CBT-05b's own class, or `TickLibrary`) | −3,000 to −6,000 | none | `trigger` and `trap` are a second entry path with their own `Unit` handling |
| **All three from `2a49f47`** | **about 54,000–69,000** | **about 1.3 M–1.7 M** | |

- With all three, `ExecutorLibrary` would come to about 66–84 % of the limit, leaving about 13,000–28,000 felts of room: enough for CBT-05b's resolution parts at the estimate above.
- **This is an estimate with a wide range, not a measure.** The first two are the views rework done fully (actors' views across the call and inside), a rework of the class's argument shape and of `Unit`; the third moves code CBT-05b would otherwise add.
- **`TickLibrary` with route (c):** without the executor it was 27,023 felts (2.19 probe), so about 54,900 of room for ENG-07's act hook and CBT-05b's action phase, estimated at 22,500–75,000 together. It fits at the lower half of that range; above it, ENG-07 is short.

### If the route continues
- Keep **`2a49f47`** (revert `0931bd8` and `d7b3611`): the smallest `ExecutorLibrary` (82,113), and its hit (2,094,071) is the least of the three reworks.
- Then build the three changes above in that order, each measured.

### Earlier: the final table before route (c)
 (measured unless marked E)
| Route | Class | CASM felts | Share of 81,920 | Room left | Room needed for CBT-05b and ENG-07's act hook (E) | Goblin weapon hit, levered | Naive |
|---|---|---:|---:|---:|---:|---:|---:|
| (a) one class | `TickLibrary` with the executor | 111,571 | 136.20 % | **−29,651** | 22,500–75,000 | **784,188** | 973,630 |
| (c) own class | `ExecutorLibrary` | 92,681 | 113.14 % | **−10,761** | CBT-05b's resolution parts (E) | **1,936,878** (at `d889419`: 23,821,574 − 12,200,304, over 6; 1,947,253 at `78201b3`) | — |
| (c) | `TickLibrary` without the executor | 27,023 (2.19, `ab71732`'s probe) | 32.99 % | 54,897 | 22,500–75,000 | — | — |
| (c') one call a tick | — | — | — | — | — | out on paper (`docs/design/19-effects.md:293`; `types/world.cairo:278–280, 308–310, 345–347`) | — |

**Steps, measured:**

| Step | TickLibrary felts | ExecutorLibrary felts | Hit, levered | Naive |
|---|---:|---:|---:|---:|
| Baseline `78201b3` | 118,847 | 100,133 | 794,793 | 983,795 |
| R1 `b43292b` | 117,062 | 98,348 | 801,368 | 990,370 |
| R2 `a6a4206` | 115,499 | 96,785 | 807,838 | 996,840 |
| R3 `d03841e` | 114,067 | 95,177 | 793,528 | 982,970 |
| (ii) `87a756f` | **111,571** | **92,681** | **784,188** | **973,630** |

- The full suites at `87a756f`: logic 613 passed, 73 failed; persistent 230 passed, 2 failed. Every failure is a gas budget (not yet regenerated); none is of another kind.

### The nameable reworks, and where they would leave route (c) (E)
| Rework | Saving (E) | Basis |
|---|---:|---|
| One uniform target type (the per-target code compiled once, not for a member and a goblin) | 8,000–15,000 | the goblin-source path's probe was 20,037 |
| Shared, non-generic snapshot readers and actor-list scans | 2,000–5,000 | the area scan's probe was 1,917 |
| Hexx's geometry called rather than inlined (more gas a hit) | up to 5,000 | the geometry is 11,094 in all |
| **All of them** | **15,000–25,000** | |

- **Route (c) with all of them: `ExecutorLibrary` at about 67,700–77,700 felts (E)**, 82–95 % of the limit, so about 4,200–14,200 felts of room. CBT-05b's resolution parts may join it; ENG-07's act hook belongs in `TickLibrary`, whose room is about 54,900.
- **Route (a) with all of them: about 86,600–96,600 felts (E)**, still over the limit before CBT-05b and ENG-07.
- **The hit through route (c): 1,936,878 a goblin hit (measured at `d889419`)**, against 784,188 in one class: the call's overhead is 1,152,690 a hit (measured, by difference).

**Judgment: option (ii) is not enough, as expected.** Route (a) cannot hold CBT-05b and ENG-07 under 81,920 with any rework I can name. Route (c) can fit with the reworks above, at **1,936,878 a goblin hit** (measured), against 784,188 in one class. That cost goes to the owner with ENG-07 (R-2).

### Option (ii), the scope deferral (the project manager, 2026-10-02): what the MVP's content uses
**Sources:**
- design/19 §8's coverage table (its MVP rows);
- design/03's starter skills;
- design/07's potions (restoratives, draughts, oils, bombs);
- design/20's five MVP castes and their skills (Runt, Slinger, Skirmisher, Shaman, Hobgoblin; §3.2–§3.3: Mend Kin, Overhead Smash);
- CNT-01 and CNT-03 seed from these; `contracts/seed` holds a test region only.

| Kept | Used by |
|---|---|
| implicit weapon hit (attacks) | every weapon attack; Cleave, Rending Cut, Skullring, Aimed Shot, Hamstring Shot, Overhead Smash |
| 1 `DAMAGE` | Ember Bolt, Cinder Ring, Rime Shard, Static Lash, Snare's payload, bombs |
| 2 `ATTACK_BONUS` | Cleave, Aimed Shot, Overhead Smash |
| 3 `HEAL` | Second Wind (two, the second `BELOW_HALF`), Field Dressing, Mend Kin (the Shaman) |
| 5 `REGENERATION` | restoratives, draughts |
| 6 `CONDITION` | Rending Cut, Skullring, Hamstring Shot, Cinder Ring, Rime Shard, Snare, the Skirmisher, bombs |
| 7 `CURE` | Field Dressing, restoratives |
| 8 `ENERGY` | restoratives |
| 9 `NEXT_SPELL_COST` | Deep Draw |
| 10 `ARMOR` | Stone Skin (the Shaman's "shields", FX-20), draughts |
| 11 `PENETRATION` | Warcry |
| 12 `HIT_PENETRATION` | Static Lash |
| 13 `BLOCK` | Brace |
| 14 `EVADE` | Sidestep |
| 15 `ON_ATTACK_CONDITION` | Venom Coat (`d`), oils (charges) |
| 16 `MOVEMENT` | draughts |
| 18 `TRAP` | Snare |
| shape `SINGLE` | most |
| shape `RING_1` | Cinder Ring |
| shape `DISC_1` | bombs (FX-35) |
| guard `ALWAYS` | most |
| guard `BELOW_HALF` | Second Wind |
| addressing `SELF`, `FOE`, `ALLY`, `TILE` | self skills, attacks, Mend Kin and Stone Skin on an ally, Snare and bombs |

**Deferred, for a PLAN row "executor kinds beyond the MVP's content"** (built when content needs them; they stay in design/19). Each is refused by `set_record` and tested (`test_set_record_deferred_kinds_and_guards`; `test_entry_*_deferred`):

| Deferred | Its first source after the MVP |
|---|---|
| 4 `LIFE_STEAL` | the Gravecaller (design/03); no MVP source in §8 |
| 17 `INTERRUPT` | Disrupting Chop, the Champion's (design/20 §3.2, §4) |
| entry guard 1 `ABOVE_HALF` | none named; passive guards are unaffected |
| entry guard 3 `IN_STANCE` | none named |
| entry guard 4 `ENCHANTED` | none named |
| already refused before this lot | `DISC_2`, `DISC_3` (FX-21), kinds 19–23 (§3.6), conditions 6–9 (FX-22) |

- **What would reverse it:** MVP content needing a deferred kind or guard, or the owner.
- §10.7's test keeps FX-40's point with a `HEAL` on the source in place of the example's `LIFE_STEAL`.
- **Expected saving (E): small, about 1,000–3,000 felts.** The deferred kinds' code is small. The shapes the content uses (`RING_1`, `DISC_1`) keep the area path. The step's measure (`87a756f`) decides.

### Final route table (measured unless marked E)
| Route | Class | CASM felts | Share of 81,920 | Room left (81,920 − felts) | Room needed for CBT-05b and ENG-07's act hook (E) | Goblin weapon hit, levered | Naive |
|---|---|---:|---:|---:|---:|---:|---:|
| (a) one class | `TickLibrary` with the executor (`d03841e`) | 114,067 | 139.24 % | **−32,147** | 22,500–75,000 | **793,528** | 982,970 |
| (c) own class | `ExecutorLibrary` (`d03841e`) | 95,177 | 116.18 % | **−13,257** | CBT-05b's resolution parts | **1,947,253** (at `78201b3`, before R1–R3, a library call a carrier) | — |
| (c) | `TickLibrary` without the executor | 27,023 (2.19, `ab71732`'s probe) | 32.99 % | 54,897 | 22,500–75,000 | — | — |
| (c') one call a tick | — | — | — | — | — | out on paper: carriers depend on each other's results (`docs/design/19-effects.md:293`; `types/world.cairo:278–280, 308–310, 345–347`) | — |

- **Both routes are over the hard limit before CBT-05b and ENG-07 join.** Route (a) is 32,147 felts over; route (c)'s `ExecutorLibrary` is 13,257 over.
- Route (c)'s hit costs about 2.45 times route (a)'s. The overhead it measures is loading and storing the actors inside the class, plus the call and its calldata.

### Judgment: can a further rework close the gap?
Reworks I can name, with my estimated saving (E):

| Rework | Saving (E) | Basis |
|---|---:|---|
| One uniform target type: the per-target code (`on`, `strike`, `entries`) compiled once, not for a member and a goblin | 8,000–15,000 | the goblin-source path's probe was 20,037 |
| The snapshot readers and the actor list's two scans folded into shared, non-generic helpers | 2,000–5,000 | the area scan's probe was 1,917 |
| Hexx's geometry called rather than inlined (`shape`, `arc`, `front`, `reach`) | up to 5,000, with more gas a hit | the geometry is 11,094 in all |
| **All of them** | **15,000–25,000** | |

- With all of them, route (a)'s `TickLibrary` would be about 89,000–99,000 felts: still over the hard limit, with no room for CBT-05b or ENG-07.
- Route (c)'s `ExecutorLibrary` would be about 70,000–80,000: under the limit, but with about 2,000–12,000 felts of room, and a goblin hit of about 1.95 M.
- R1–R3 cut 4,780 felts in all: the size lies in the executor's work itself (the kinds of §3, §5.5–§5.14), not in removable duplication.
- **Plainly: no rework I can name brings either route under 81,920 with room for CBT-05b and ENG-07 and the hit at or below 794,793.**
- What is left is a design or budget decision, the project manager's:
  - split the executor across classes by carrier kind, each paying about 1.15 M a call (measured overhead);
  - reduce what the MVP's executor covers (kinds or shapes);
  - change ENG-01 §1.3's class rules or the hit target.

### Both routes measured on Scarb 2.20.1 (after merging `origin/main` with FND-11 at `78201b3`; before the views rework)
| Route | Class | CASM felts | Share of 81,920 | Goblin weapon hit, levered | Naive |
|---|---|---:|---:|---:|---:|
| (a) one class | `TickLibrary` with the executor | 118,847 | 145.08 % | **794,793** | 983,795 |
| (c) own class | `ExecutorLibrary` (load, the executor, store) | 100,133 | 122.23 % | **1,947,253** (a library call a carrier) | — |
| (c) | `TickLibrary` without the executor | 27,023 (on 2.19; to re-measure) | 32.99 % | — | — |

- **Route (a):** `test_cost_hits_levered` 15,184,894 − `test_cost_hits_fixture` 10,416,134, over 6; naive 16,318,904 − 10,416,134, over 6.
- **Route (c):** `test_cost_class_hits` 23,900,624 − its fixture 12,217,104, over 6. The arguments are the source's and the member's words, and the sheets their loads need (8 bar skills, the caste and its 4 skills), in and out.
- **The call's measured overhead is about 1.15 M a goblin hit.** It replaces my earlier estimate of 0.40 M, which counted calldata only, not loading and storing the actors inside the class.

**(c') one call a tick or a phase: out on paper.** Each carrier must see the state the previous one left, and the tick stops after any carrier that downs the adventurer (`docs/design/19-effects.md:293`, step 2: "each sees the state the previous ones left"; `contracts/logic/src/types/world.cairo:278–280, 308–310, 345–347`: `world.is_down()` checked after every `rules.resolve` and `rules.act`). One call holding all of a tick's carriers would have to hold the pipeline and the AI too: it would be `TickLibrary` itself.

### The views rework (measures on the Mac, SPK-13b)
| Step | Commit | What | TickLibrary felts | ExecutorLibrary felts | Goblin hit, levered | Naive |
|---|---|---|---:|---:|---:|---:|
| Baseline (2.20.1) | `78201b3` | — | 118,847 | 100,133 | 794,793 | 983,795 |
| R1 | `b43292b` | the hit on a view of its target (`Struck`), resolved once, not generic | 117,062 (142.90 %) | 98,348 (120.05 %) | 801,368 | 990,370 |
| R2 | `a6a4206` | the dispatch on entry kind outside the target code (`Op`, built once a carrier) | 115,499 (140.99 %) | 96,785 (118.15 %) | 807,838 | 996,840 |
| R3 | `d03841e` | the lighter awake goblin value (4 caste-derived fields read from the sheets at use) | **114,067 (139.24 %)** | **95,177 (116.18 %)** | **793,528** | **982,970** |

- R1 and R2: measured on the Mac (t-0037, Scarb 2.20.1, snforge 0.64.0, aarch64; SPK-13b: platform-free). Together they cut 3,348 felts and cost 13,045 gas a goblin hit.
- R3 vs R2: −1,432 and −1,608 felts, −14,310 gas a hit. At `d03841e` the full suites run: logic 609 passed, 73 failed; ephemeral 50 passed, 3 failed. Every failure is a gas budget, still to be regenerated; none is of another kind.
- **R3's reach:** step 3's regeneration (`TickTrait::regenerate`, which gets the sheets), the goblin's adrenaline gains (`gain_adrenaline`, `land_weapon_hit`, `take_hit`), three `Body` methods, both goblin fixtures and about eight tests in `logic` and `ephemeral`. It trims 4 of the goblin's 25 felts in each copy.
- **R3 is sequenced after R1 and R2's figures:** if they leave the executor far from the targets, R3 cannot close the gap; if they come close, it is worth its reach.

### What is planned to join the classes: size estimates (E, not measured)
- **Method:** code lines times felts a line, the ratio measured on this branch.
  - The executor at `ab71732`: about 92,100 felts for 1,764 code lines (without tests and comments), about 52 felts a line. It is generic-heavy; R1–R3 aim to lower that ratio.
  - The pipeline: main's `TickLibrary` is 23,860 felts for `world.cairo`'s 539 code lines plus the actors' loading and storing, about 25–30 felts a line.
- **CBT-05b** (`docs/briefs/CBT-05b-action-and-traps.md`, *Scope*): the action phase's legality list, costs (energy, glyph, adrenaline, recharges, belt counts, quick-cast counters), facing through `WindowTrait::facing`, placing traps as chunk objects, and detecting a trigger on a move.
  - **Estimate: 500–800 code lines, so 12,500–40,000 felts** (at 25 to 50 a line).
- **ENG-07's act hook** (PLAN's ENG-07 row): the AI choosing a goblin's carrier, its movement, with the map library's flood and walkers called from the hook. Perception and the window's assembly are also ENG-07's, but outside the act hook.
  - **Estimate: 400–700 code lines, so 10,000–35,000 felts**, plus whatever of `hexx`'s flood the class must hold. That part is not estimated: LIB-05 can measure it.
- **Planned additions in all: about 22,500–75,000 felts (E).** A class at the hard limit with less room than that cannot take CBT-05b.

### The rework (go-ahead of 2026-10-02): stopped before coding, both targets have a floor above them
- **Route 1, the executor inside `TickLibrary` at 50 % or less.**
  - The headroom is 40,960 − 27,023 (`TickLibrary` without the executor) = **13,937 felts**.
  - Two parts every carrier needs, measured by stubbing them on the 130k build, already exceed it: the geometry (`arc`, `front`, `reach`, `shape`: 130,954 − 119,860 = **11,094**) and CBT-03a's `resolve` (130,831 − 125,165 = **5,666**). Together they are **16,760**.
  - Smaller per-target views cannot remove either part.
- **Route 2, its own class called from `TickLibrary`.** That means one library call per carrier, since the resolve and act hooks run one carrier at a time.
  - The syscall alone is **C = 117,910** (ENG-01 §2.3, measured).
  - Calldata (estimate): a goblin carrier carries about 170 felts in and out (both actors' values, its skill and caste sheets, the board, the cache). ENG-01's measured call cost 3,323,680 for about 1,350 felts, so about 2,370 a felt, or **about 0.40 M**.
  - Overhead per goblin hit: **about 0.52 M**. Under the 794,793 target, the in-class hit would have to cost at most about 0.27 M. The hit's core alone (offence, geometry, `resolve`, the damage) measures **302,345** (`test_cost_part_strike`).
  - So this route misses the gas target even before its size target (the executor alone is about 92,100 felts, 112 %; the target is 41,000).
- **Split by carrier kind (the next option asked for).** Each class still pays one call per carrier, the same floor as route 2. It only lowers each class's size.
- **What would work, for the project manager:**
  - (a) A single class with the views rework, aiming at the hard limit (100 %, 81,920 felts) instead of 50 %. The executor would have to come down from about 92,100 to about 54,900, which I judge reachable but have not measured. The 50 % rule would need a waiver for `TickLibrary`.
  - (b) Shrink `TickLibrary`'s own pipeline (27,023 today), together with (a).
  - (c) Accept the gas cost of route 2 or of a split.
  - Each is a decision on ENG-01 §1.3's rule or on the hit target, so it is the project manager's.

### The shrink (the project manager's route, 2026-10-02): stopped, neither route reaches 50 %
Each step measured on this machine (`RAYON_NUM_THREADS=1 scarb build`, `class_sizes.py`, and the goblin-hit pair):

| Step | TickLibrary CASM felts | Share | Goblin hit, levered |
|---|---:|---:|---:|
| Start (`5240a8c`, each actor read once) | 130,831 | 159.71 % | 810,603 |
| 1. `#[inline(never)]` on the executor's 25 helpers | 130,954 | 159.86 % | not measured alone |
| 2. The target-side code generic over the target only (the source's on-hit side gathered once a carrier, `OnAttack`; the source's gain applied by the caller) | **119,109** | **145.40 %** | **794,793** |
| For reference: TickLibrary without the executor | 27,023 | 32.99 % | — |

Probes (each measured, then reverted):

| Probe | TickLibrary felts | What it shows |
|---|---:|---|
| No goblin-source path | 110,794 | that path is about 20,000 |
| The hit's `resolve` stubbed | 125,165 | the hit is about 5,700 |
| The geometry stubbed | 119,860 | the geometry is about 11,000 |
| The entries stubbed | 112,479 | the entries are about 18,000 |
| The on-hit steps 7–8 stubbed | 115,925 | they are about 15,000 |

**Judgment.**
- The executor alone is about 92,100 felts (119,109 − 27,023), **112 % of the limit**.
- Route 1 needs it at about 14,000 felts, so that `TickLibrary` stays at 50 %.
- Route 2, its own class, needs it at 41,000 or less.
- Neither is in reach by trimming. The bulk is the per-target code: each `Member` (about 30 felts) or `Goblin` (about 26) value travels whole through every branch of `on`, `strike`, `entries` and `hold`, for both target types.
- Fitting needs a different shape: small per-target views, read once and written back once, and a dispatch on entry kind outside the target code. That is a rework of the executor's core, not another trimming step.
- I did not start it. The budgets, §9.2, the inventory, the three CV hit cases and the PR wait for that decision.

### Breakdown of one goblin weapon hit (levered, step 0's code, per hit; pairs against `hits_state`'s fixture)
| Part | L2 gas |
|---|---:|
| The source goblin read and written back (one rebuild of the awake set) | 92,905 |
| The member target read and written back | 42,415 |
| The actor list (§5.14 step 4) | 141,618 |
| The hit: defence (kept), `arc` and `front`, the offence, `resolve`, the damage and the hit recorded | 302,345 |
| The rest (reading the carrier, guards, modifiers, context, the run's own frame) | about 231,000 |

- **Against SPK-15's 322,816:** SPK-15 priced a hit with placeholder inputs and no actor list, geometry, offence or reading of the carrier.
- **The executor's share of the gap:** the actor list (142,000) and the run's overhead (231,000).
- **The design's share:** the geometry (`arc`, `front`, about 37,000 by ENG-02's figures) and the real offence and defence terms, which SPK-15 did not price.

### L3's pairs, re-measured at `ab71732` (snforge totals)
- **Cinder Ring on 6 of 8 awake goblins** (fixture 10,983,344): naive 14,609,726; entries decoded once 14,538,176 (−71,550); one rebuild 14,504,226 (−105,500); all levered 14,458,956 (−150,770).
- **6 goblin weapon hits on the member** (fixture 10,423,644): naive 16,326,414; the defence kept for the tick 15,096,164 (−1,230,250); all levered 15,192,404 (−1,134,010). The one-rebuild lever costs 16,040 a hit when the carrier reaches one goblin: the source's sort and flush cost more than a `set_goblin`.
- **The brief's two unmeasured levers:**
  - A lighter awake goblin value: not built. What is at stake is the 92,905 a goblin carrier spends on its source's rebuild.
  - Step 2's writes kept pending: needs the AI's act hook (ENG-07) to hold the pending writes. At stake: at most 7 of 8 such rebuilds a step, about 650,000 a tick (an estimate from the pair above).

### Track CV
- `hit.jsonl` gains edge id 6 `(sword, asleep + evade)`, which now lands critical where the old rule evaded it (D-179). Later ids shift by one; no kept case changed its outcome.
- The three cases asked for in #292 (an axe from the front or front-side below the clamp; `ABOVE_HALF` at exactly half; FX-19 leaving the target at exactly half) are **not added yet**: they wait with step 4.


### Earlier state (first stop)
**Stopped at AC-6, as the brief says.** I wired the executor into `TickLibrary`, and the class came to **130,831 CASM felts, 159.71 %** of the nearer limit. That is past the 50 % stop line and past the hard limit itself. With the same branch run on `Idle` rules, the class is 27,023 felts (32.99 %). So the executor alone adds about **103,800 felts (127 %)**: it would not fit even as a second library class on its own. It has to shrink first, most likely through less monomorphization: the generic `Body` over member and goblin, source by target, with `#[inline(always)]` geometry and the hit inlined into each instance. Whether to shrink it, split it, or move it to its own class is the project manager's decision.

Branch `hp/grimworld-game/t-0009-cbt-05a-executor`, pushed; now at `ab71732`. **No PR** (the brief asks for a green CI first, and the class-size check cannot pass).

What exists on the branch:
- **The executor** (`contracts/logic/src/types/executor.cairo`) covers §5.14 steps 1–6:
  - guards evaluated once (FX-40); a `TRAP` carrier returns `Place`/`Skipped`, with placement left to CBT-05b; hit modifiers clamped; target sets from ENG-02's `WindowTrait` (`shape`, `arc`, `front`, `reach` before `arc` in `legal`), in ascending position;
  - the hit first, then the entries in order; §5.5 steps 5–9 (`ON_ATTACK_CONDITION`, `LIFE_STEAL_ON_HIT`, `ENERGY_ON_HIT`, adrenaline and `hits`, the +¼ strike, a goblin noticing); §5.7 holding through positions; kills in resolution order;
  - the kinds `HEAL`, `LIFE_STEAL`, `CONDITION` (Knocked down goes to `knock`), `CURE`, `ENERGY`, `INTERRUPT` and every holding kind;
  - `trigger` for a trap's payload; the step-1 hook (`Executor` rules), wired into `TickLibrary::run`, which gains a `board` argument.
- **L3, built as levers** (`Levered` against `Naive`, with test-only impls that each lever one part).
- **26 executor tests, all passing:**
  - design/19 §10.1, §10.2, §10.4, §10.6, §10.7, §10.8, §10.9 (through the pipeline) and §10.10, to the unit;
  - SPK-15's guard across two hits; a stopped hit stops the carrier; targets illegal at resolution; a carrier with no actor; the instant kinds, including nothing on a member at 0; a hold updating the defence; `HIT_PENETRATION`; `ADRENALINE_EVERY_N`; D-179 through the executor.
- **Carried items done:**
  - D-179 (`&& !asleep`); `hit.jsonl` regenerated and `check.py` reports "as computed"; the README's `## hit.jsonl` section;
  - conditions 6–9 refused by `set_record`, with tests in `test_combat` and `test_registry`;
  - one copy of the weapon-strength rule (the snapshot calls `HitTrait::weapon_strength`);
  - `DAMAGE`/`ATTACK_BONUS` clamped before a `Hit` is built;
  - lookups by id replaced by positions (`Member.effect_at`, `Goblin.effect_at`); the scans are removed;
  - each held effect's holding entry is now in the sheets (`Sheets.entries`), so `MOVEMENT` is readable there;
  - the executor counts its hits each tick (`Cache.hits`).

### Files changed
- `contracts/logic/src/types/executor.cairo` (new).
- `types/{tick,hit,effect,world}.cairo`: `tick` (the sheets' new fields, entries decoded once a call), `hit` (D-179), `effect` (the refusal), `world` (`find`, `alive`).
- `models/{member,goblin,index}.cairo`: positions of held effects, the snapshot's readers, `hold`/`put` by position.
- `snapshot.cairo`, `interface.cairo`, `systems/tick.cairo`, `types.cairo`.
- `vectors/{hit.jsonl,README.md}`.
- Tests: `contracts/logic/tests/{test_tick,test_combat}.cairo`, `contracts/persistent/tests/test_registry.cairo`, `contracts/ephemeral/tests/test_tick_words.cairo`.

### Commands run
- `snforge test grimworld_logic::types::executor`: 26 passed, 0 failed.
- `snforge test` (logic, before the last refactor): 611 passed, 65 failed. 63 of the failures are budgets (the sheets and actors grew); the other 2 were the hit vectors (now regenerated) and `test_library_matches_pipeline` (now compares against `Executor`). **The budgets are not reset.**
- `python3 vectors/check.py`: window.jsonl 2065 and hit.jsonl 200 cases, both "as computed".
- `RAYON_NUM_THREADS=1 scarb build` and `class_sizes.py`: `TickLibrary` 130,831 CASM felts (159.71 %, OVER). Without the executor: 27,023 (32.99 %).

### L3's measured pairs (snforge totals; measured before the last commit's "read each actor once" refactor, so to be re-measured)
- **Member's Cinder Ring on 6 of 8 awake goblins** (fixture 10,983,344):
  - naive 14,934,246 (executor 3,950,902);
  - entries decoded once −71,550; one rebuild −106,700; all levered −151,970.
- **6 goblin weapon hits on the member** (fixture 10,423,644):
  - naive 16,891,644 (1,078,000 a hit);
  - defence kept for the tick −1,230,250 (−205,042 a hit);
  - all levered 15,750,434 (887,798 a hit). Levered costs more than the defence lever alone, because the source's sort-and-flush costs more than a `set_goblin` for one goblin: the rebuild lever does not pay for a single-goblin carrier.
- SPK-15 estimated 322,816 a levered goblin hit. This executor is about 2.75 times that, largely struct copies through the generic code.

### Acceptance criteria
- **AC-1:** partly. The steps and kinds are tested. The inventory table is not written.
- **AC-2:** §5.7 through §10.4, §5.12, §5.13 and the named §10 examples are done. §10.3 and §10.5 are not on the brief's list.
- **AC-3:** built and measured as above. The figures need a re-measure.
- **AC-4:** done (`WindowTrait` throughout).
- **AC-5:** done, listed above.
- **AC-6:** **the stop**.
- **AC-7:** not reached: budgets, `gas_budgets.py --check`, CI.

### Deviations from the task
- `ITickLibrary::run` gains `board: Board`, since the executor needs the window. ENG-07 assembles it.
- `INTERRUPT` stays legal and is executed by its rule (§5.9): it is catalogued in §3.5, not among §3.6's post-MVP kinds.
- Readings where the design is silent (the executor's header lists them):
  - a source never hits itself;
  - the lowest slot's `BLOCK` is spent first;
  - a holding entry with no duration and no charges does not stay;
  - a goblin's weapon strength is 5 × rank, uncapped (design/20 §2.4; the cap is BAL-01's);
  - a goblin hit notices (Engaged), while the pack and 8-tile alerts are chunk features left to ENG-07.
- A shout's alert and a glyph's consumption are left to ENG-07 and CBT-05b.

### Escalations
1. **Class size (the stop):** whether to shrink the executor, give it its own class, or both. Even alone it is 127 % of the limit.
2. **Cost:** a levered goblin hit costs about 0.89 M against SPK-15's 0.32 M estimate. The per-tick budget line (executor's worst tick, ENG-01 §9.2) is not written.
3. **CV:** `client/sim/` on `origin/main` mirrors only `exp2`, not the hit, so it is unchanged. **The vectors that moved, for a paired CV PR:** `hit.jsonl` gains edge id 6, `(sword, asleep + evade)`, which now lands critical `[3, 140, 1, 0]` where the old rule evaded it (D-179). Every later id shifts by one, and the last seeded case drops out of the 200. No other case changed its outcome.

### Owed at the PR stage (asks received 2026-10-02)
- **Required (#292 merged on main at `e405340`; CI couples `contracts/logic/vectors` with `client/sim`):** after merging `origin/main`, in the same PR as the three new `hit.jsonl` cases, change in `client/sim/` only:
  - `client/sim/src/hit.ts`: add `&& !target.asleep` to the evade line (D-179);
  - `client/sim/src/parity/mutants.test.ts`: remove the three `survives` marks, and update mutant 17's `from` line.
  CI's `client` job must pass, whichever route the project manager picks.
- The three hit cases for track CV: an axe from the front or front-side below the clamp; `ABOVE_HALF` at exactly half with a non-zero above-half percent; FX-19 leaving the target at exactly half. Give their ids in the PR.
- After merging `origin/main` (FND-11, Scarb 2.20.1, about −7,730 a tick benchmark): recompute ENG-01 §9.2's whole running total on the new compiler (the tick's share, CBT-03a's hits, CBT-04's conditions, the executor's line). Show each sum, and give the new figure and its ratio to 1,469,435 in the PR and the report.
- At the top of the PR and the report: the final goblin weapon hit, levered and naive.
- The final table gets a "room left" column: each class's room for CBT-05b and for ENG-07's act hook, estimated and called estimates.

### `5313ee6` (measured on the Mac) and `f1a33f4`
- **`5313ee6`:** `ExecutorLibrary` 87,734 (107.10 %), `TickLibrary` 37,752 (46.08 %). The logic test build failed: `walled` called without `Fixture::`, in `test_near_agrees`.
- **Why `ExecutorLibrary` grew by 5,621 felts with the rewire:** its second entrypoint, `conclude`, brought in `ExecutorTrait::conclude` and `legal`. `legal` calls ENG-02's `reach` with its line of sight (`hexx`'s line). The entry also adds its own wrapper and serialization. All of that outweighed the `disc` code the trim removed.
- **`f1a33f4`:**
  - `ExecutorLibrary` keeps one entrypoint, `execute`, which returns whether a `TRAP` carrier's guard held.
  - `TickLibrary`'s hook turns the slot into a carrier and checks its target legal at resolution, before the call. That is pipeline work, and `TickLibrary` has the room.
  - The test build is fixed. Pending the Mac's measure.
- **If `ExecutorLibrary` is still above 80,000 at `f1a33f4`:** I see no further cut limited to what the MVP's content does not use. The executor's remaining code serves the kinds and shapes of the MVP's own list above. The project manager's rule then applies: stop.

### Inventory (AC-1): design/19 §5.14's steps and §5.7's rules, where each lives, what this lot added
| Rule | Before CBT-05a | Where it lives now (`contracts/logic/src/…`) | Added by this lot |
|---|---|---|---|
| Step 1's hook: the activation concluded, its target legal (§5.9) | the pipeline cleared the field and set the recharge (`types/world.cairo`, `conclude`); the hook did nothing (`Idle`) | `types/executor.cairo`: `Delegate::resolve` (`TickLibrary`), `ExecutorTrait::carrier`, `legal` (`reach` before any arc) | the carrier from the slot, the legality, the call to `ExecutorLibrary` |
| §5.14 step 1: guards once (FX-40) | — | `ExecutorTrait::guards` (`ALWAYS`, `BELOW_HALF`; the others refused, option (ii)) | all |
| Step 2: placement (a `TRAP` carrier) | — | `ExecutorTrait::run` returns `Executed::Place` (the placement itself is CBT-05b's) | the guard's gate and the result |
| Step 3: hit modifiers | — | `ExecutorTrait::modifiers` (`ATTACK_BONUS`, `HIT_PENETRATION`, clamped) | all |
| Step 4: target sets now, ascending position | — | `ExecutorTrait::actors` on ENG-02's `WindowTrait::near` / `shape` | all |
| Step 5: the hit first, stopped → nothing else | CBT-03a's `HitTrait::resolve` (one hit) | `ExecutorTrait::on`, `strike` (the target's view), `resolve` (the `Hit` and `HitTarget` from the world; the arc and the front tile from ENG-02) | the inputs gathered, the outcome applied |
| §5.5 steps 5–9 | `MemberLifecycleTrait`, `GoblinLifecycleTrait` (`take_hit`, `land_weapon_hit`) | `strike` (damage, the hit flag, FX-19 spent, notice), `on` (step 7: `ON_ATTACK_CONDITION`, `LIFE_STEAL_ON_HIT`), `run` (step 8 on the source: charges, adrenaline, `ENERGY_ON_HIT`), `put` (death at 0) | the order and the source's side, gathered once (`OnAttack`, `Gain`) |
| Step 5: the other entries, in order, on the living | CBT-04's `apply`, `knock`, `cure` | `ExecutorTrait::ops` (values clamped once a carrier), `entries` (applied) | the dispatch and each kind's rule |
| Step 6: carrier-level effects | — | none here: a shout's alert is ENG-07's (packs are chunk features), a glyph and `casts` are §5.3's (CBT-05b) | named |
| A trap's trigger (§5.11) | — | `ExecutorTrait::trigger`, `trap` (not yet reached by either class: CBT-05b wires it) | the payload's run |
| §5.7.1 same carrier: the later deadline, whole | `MemberLifecycleTrait::hold` (CBT-02) | `models/member.cairo` `hold`, `models/goblin.cairo` `hold`; called by `entries` with the `Held` that `ExecutorTrait::hold` builds | lookups by position (`effect_at`), not by id |
| §5.7.2 a stance replaces the stance held | `hold`, through a scan of the content by id | `hold`, through the slot's position | positions |
| §5.7.3 the lowest free slot | `hold` | `hold` | — |
| §5.7.4 eviction: earliest deadline, ties lowest slot | `hold` | `hold` | — |
| A held effect's terms on a hit (`ARMOR`, `BLOCK`, `EVADE`, stance, enchantment) | — | `DefenceTrait` (`member`, `goblin`), kept for the tick (L3's `Cache`) | all |

### For the PR text
- "route (c), option (2), decided by the project manager, 2026-10-02 (D-200); the per-hit cost through ExecutorLibrary (2,103,191 measured at f1a33f4) accepted by the owner, 2026-10-02 (D-198, D-200)".
- Option (3), the cost-lowering design lot: a later PLAN row, after CBT-05a.
- `ITickLibrary::run` takes the executor's class hash (`executor: ClassHash`) and the `board`.

## Next
- Watch PR #334's CI (one poll every 5 minutes at most) and fix what fails in one push
- Add the PLAN row "executor kinds beyond the MVP's content" with the deferral list
- Add the PLAN row for option (3), the cost-lowering design lot, after CBT-05a
- Merge the PR once reviewed and its checks pass
- Remove the worktree and branch once merged

## Remember
- A pre-push hook's test that runs git in a temporary directory must clear GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE: under a hook they point at the real repository.
- Before a push, merge origin/main when the hooks changed there: an old branch carries the old hook.
- Measure a library class's size after the first wired path, before writing tests: a generic executor carrying whole actor structs grew TickLibrary by about 104,000 CASM felts.
- `#[inline(never)]` did not shrink the class; it is the size of the live structs in branches that counts.
- A library call per carrier costs the syscall (117,910) plus its calldata: a route through a second class must be priced per carrier before it is chosen.
