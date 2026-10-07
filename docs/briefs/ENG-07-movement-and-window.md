# ENG-07 — Movement, the simulation window, the batch and the instance clock

> PLAN's ENG-07 row (movement, facing, the simulation window of 15 × 16 that follows the adventurer,
> assembled at each tick and never stored, the action queue with its stop conditions, the instance
> clock), with the conditions SPK-7, D-134, D-145, D-172, D-207 and CBT-05a/ENG-05 put on it.
> **Starts after ENG-10b and ENG-05b merge** (PLAN: ENG-07 "todo, after ENG-10b"; ENG-05b "runs
> before ENG-07", D-209). Decisions: ADR-0006 §4 (D-120, D-127, D-134, D-136), D-133, D-140, D-141,
> D-143, D-144, D-145, D-147, D-172, D-200, D-207, D-208, D-209, D-210, D-217, D-222, D-223, D-224, D-225.
> Pins and figures on Linux only (OPERATIONS.md §3). Profile: impl-opus, the VPS.
> **Its Open questions 1 and 2 are decided before the lot starts** (D-222: "ENG-07's brief must decide
> where the act hook lives before start"): below.

## Decided before the lot starts (the orchestrator and the project manager, 2026-10-07)
| # | Ruling | Reversed by |
|---|---|---|
| Q1 | **The act hook in a new class, `AiLibrary`, called once a tick** (candidate C). The lot starts with a size probe and **stops and reports if the class would pass 50 %** (the orchestrator) | the probe showing a per-tick call cost above the per-goblin option's (candidate B) |
| Q1, condition (**D-225**, the project manager) | A call once a tick is a fixed cost on every tick of the expedition (a library call with its loads has cost ≈ 3.4 M, D-225). **The lot measures that per-tick cost first, with the size probe**, and calls the hook **only on ticks where a goblin is in the window** if that is cheaper. The per-tick figure goes to the project manager **before the merge** (it feeds R-2): A13 and the D-144 table | the project manager |
| Q2 | **One `TickLibrary` call per segment, the batch split at reveals.** If `TickLibrary` would pass 88 % (D-222): stop and report to the project manager | that stop's figures, ruled by the project manager |
| Q3 | **`ground` carried across the batch's ticks**, with A6's regression test | the orchestrator |
| Q5 (**D-225**, the project manager) | **E-12's reveal weight measured end to end** by this lot, **set to 3 if the figures say so**, the figures stated in the report | the figures |
| Q6 | **Interact in `play` refused as illegal** until its entrypoints (`open`, `mine`, `barter`) exist | the lot that builds them |
| Q7 (**D-225**; **D-227**, the owner) | **One level and the walkable plane.** Bridges have one level (D-227, ADR-0008, merged in #383): a deck is walkable ground over water, and nothing in ENG-07 changes for bridges beyond walkability | the owner |

Q4 stays this lot's (D-172).

## Decided after the size probe (D-233, the project manager, 2026-10-07)
The probe (the thread's report: `AiLibrary` 78.96 %, `TickLibrary` 99.33 % with the hooks alone, the
call 4,559,107 a tick, a melee tick of 8 step-2 attacks ≈ 42.1 M) stopped the lot at Q1's, Q2's and
D-207's gates. Ruled:

| # | Ruling | Reversed by |
|---|---|---|
| 1 | **`AiLibrary` at most 80 % (65,536 felts)**, all of step 2 inside it, the sequential state exact. **CBT-05b's action phase moves to a new `ActionLibrary`, called only for a combat action** (Attack, Skill, Item); Move, Turn, Wait and the Interact refusal run in process in `TickLibrary`'s segment. `ActionLibrary`'s exception is provisional at 65 % (53,248): measured, the project manager fixes its cap at the measure + 5 %. The call a combat action (2,578,020–3,323,680) is accepted under D-144. `class_sizes.py`: `AiLibrary` 80, `ActionLibrary` 65 for now. **`TickLibrary` stays at most 88 %**: past it, stop | the project manager |
| 2 | `AiLibrary`'s call a tick accepted at **4,559,107**, none on a tick where no goblin is free to act | the project manager |
| 3 | **`Instances`: no exception.** The window's goblins derived from the pack placements (part of `play`) move into the segment's class; `Instances` stays under 50 %. If it cannot, stop and report | the project manager |
| 4 | **D-207 and R-2.** Before E-12's weight is fixed, measured and reported: (a) the representative fight on this placement, end to end: the batch total and how many ticks a batch hit the worst case; (b) the member's activation landing in the same tick as 8 goblin attacks; (c) CBT-05d's levers (fewer goblins attacking a tick, a cheaper goblin carrier), with their figures. **A batch above 369 M: stop and report** (the project manager takes it to the owner) | the owner (R-2) |
| 5 | **`Board`'s origin held plus 15** (escalation 3, the orchestrator): a window near a West or South edge is not clamped (D-134). If `ExecutorLibrary` would pass 80,420, stop and report | the orchestrator |

The other gates are unchanged: D-144 on the node (six runs, the maximum + 5 %), scoped tests, the gas
files regenerated, one push.

**Amended by D-234 (the project manager, 2026-10-07)**, after the thin `play` probe measured `Instances`
at 52.91 % (43,345 felts) before any content, goblin or reveal:

| # | Ruling | Reversed by |
|---|---|---|
| 1 | **`play`'s body in a library class of the ephemeral package, `PlayLibrary`**, called by `library_call` from `Instances`' context: the storage layout and the events unchanged; `Instances.play` keeps its admission checks and one call; no `Instances` exception. `PlayLibrary` stays under 50 %: above, stop and report. Its call, once a batch, is measured and goes in the D-144 rows with the batch total | the project manager |
| 2 | **`ActionLibrary` capped at 57,476 felts (70.16 %)**, its measure (54,739) + 5 %. `TickLibrary` stays at most 88 %: if the 9,987 felts left do not hold the segment loop, the moves and the window, stop and report before any further move | the project manager |
| 3 | **`Board`'s offset origin's cost accepted under D-144**: +23,100 to +43,200 L2 gas a goblin attack (`position` not inlined) | the project manager |

**Amended by D-235 (the project manager, 2026-10-07)**, after the segment measured `TickLibrary` at
82,133 felts (100.26 %) with 9,987 felts of room:

| # | Ruling | Reversed by |
|---|---|---|
| 1 | **Option (b): the segment lives in `PlayLibrary`**, with a fast path: a tick with no living goblin in the window and nothing owed (no activation of the member) runs in `PlayLibrary` without a call; only a tick with a fight calls `TickLibrary`. **The old `run` entrypoint is removed** (read: `TickLibrary` keeps one entrypoint, `ticks`, which runs a fight's ticks with the chunk objects carried, Open question 3) | the project manager |
| 2 | **`PlayLibrary` at most 80 %** (`class_sizes.py`); above, stop | the project manager |
| 3 | **A test runs the fast path and the `TickLibrary` path on the same ticks** and compares their state and events: identical | the project manager |
| 4 | **On the node, six runs + 5 %, each against the same batch on main's path**: an exploration batch end to end; a fight batch end to end, carrying D-233 #4's figures (the worst-case ticks a batch, the member's activation in the same tick as 8 goblin attacks, CBT-05d's levers with figures). **A fight batch above 369 M: stop and report before any further build** (the owner, R-2) | the owner |

## Goal
After this lot `Instances.play` runs a played batch (design/02 *Planned queues and played batches*,
D-133): each action checked against the state it meets, the adventurer's moves with facing, occupancy
and Crippled's 2 ticks, the window of 15 × 16 assembled around the adventurer at each tick from the
chunks read once per batch, the goblins' perception and AI (the **act hook**, design/19 §5.1 steps 0
and 2) with the shared flood stopped at 15 layers, traps triggered on every move into them, a chunk
revealed when sight touches it (zones and dungeons), and the instance clock moved and bounded by
`LAST_TICK`. The batch weight is derived from the worst tick measured (D-207), and every figure the
lot adds to the expedition's path is measured and sent to the project manager (D-144).

## Context
- **design/02**: *The tick*, *One clock per instance* (D-02), *Planned queues and played batches*
  (D-133), *The planned queue and its stop conditions*, *What a batch holds, and what ends one*,
  *Size: 10, bounded by gas*, *Entrypoints*. A played batch has no stop condition but validity: an
  illegal action stops the batch (ADR-0006 §4, last table). **design/04** *Actions* (Move: 1 tick,
  one tile, 6 directions, sets facing; Crippled: 2 ticks a tile). **design/18** (perception, sight
  radius 6). **design/19** §5.1 (the tick's steps), §5.3 (the action phase, CBT-05b), §5.11 (traps),
  §5.14.
- **ADR-0006 §4** (the window): 2 to 4 chunks, no loop over rows, the origin on an even global row
  (the adventurer on local row 7 or 8, column 7), the outer ring wall, one shared flood from the
  adventurer on the occupancy frozen at the tick's start, stopped at 15 layers (D-127: a goblin not
  reached holds its tile), at most 8 awake (the nearest, ties by id), a chunk not revealed is wall
  (D-136), chunks beyond a location's edge or a zone's outline are void constants, never read (D-134).
- **What it calls, as merged** (read the code and reports first; a change of a merged signature is an
  escalation unless this brief lists it):
  - `TickLibrary` (`contracts/logic/src/systems/tick.cairo`): `run(words, content, board, executor,
    ticks)` and CBT-05b's `act(words, content, board, executor, ground, action)`; the hooks
    `Rules::perceive` (step 0) and `Rules::act` (step 2) in `types/world.cairo`, empty today in
    `Delegate` (`types/executor.cairo`). **These two hooks are "the act hook"** of D-222 and of
    CBT-05a's report (*What is planned to join the classes*).
  - `TrapLibrary::trigger` (`systems/trap.cairo`, D-222 amended): "the move's owner (ENG-07) calls
    it … once an actor entered a tile holding an unused trap" (`interface.cairo`).
  - `RevealLibrary::reveal`, `HostsLibrary` (`hosts`, and ENG-10b's `floor`), `PlacementTrait::
    with_hosts`; `Instances`' `begin`, `site`, `chunk_kind`, `instance_region`
    (`contracts/ephemeral/src/systems/instances.cairo`), where `play` is `NOT_IMPLEMENTED` today.
  - ENG-02's `WindowTrait` (`types/window.cairo`, frozen: `facing`, `reach`, `distance`, `sight`) on
    window positions `15 y + x`, 0–239; `TickTrait::awake` (the selection, ENG-01 §9.2); `hexx`'s
    `Bfs::flood` (`None` beyond the cap: the walker holds, D-127).
  - CBT-05b's rulings: Move and Interact are ENG-07's, which calls the trap trigger after each move
    (CBT-05b brief, Open question 2); the caller passes the window's origin (Open question 3).
- **ENG-01**: §1.3 (classes and their ceilings), §3.2 (`Instances` storage: `hosts`, ENG-10b's
  `outline`), §4.1 (`play`'s encoding, `LAST_TICK`), §9.2 (per tick, per batch, the executor's line,
  the bomb, the action phase, the trap), §10 (the D-144 ceilings of ENG-05; the `play` rows), §10.1
  (weight 10, E-12, E-16, E-1, E-21), §10.2 (S1).
- **SPK-7** (`docs/research/SPK-7-chunked-maps.md` §5): `assemble_window` 65,224 in memory (2 or 4
  chunks), the shared flood 26,452 a layer and 634,655 at the capped worst, the flood and 8 steps
  1,150,737. Its audit's finding 3 (deferred here): B′, a stored window, only if fights pay for it,
  with a benchmark of a chunk-set change built from valid deferred ticks.

## Scope
- In:
  1. **`Instances.play`**: the sequence and version checks (ENG-01 §4.1), the batch decoded
     (`actions::decode_batch`), the records the ticks use read once (D-145; the chunks of the union
     of the batch's windows, at most 9, read once per batch, SPK-7), the batch run through the
     classes Open questions 1 and 2 decide, the words and chunk words written back, `BatchPlayed`,
     `GoblinKilled` (ENG-01 §5's events are frozen, D-193: none changes; a change would be an escalation,
     announced in STATUS, since the indexer reads them).
  2. **Movement**: a Move's legality (the tile walkable on the one walkable plane, Open question 7;
     unoccupied; the adventurer able to move, CBT-04's `can_act`, `move_ticks`), its ticks (1, or 2
     Crippled), facing set to the direction (design/04), the occupancy bits of the chunk left and the
     chunk entered (ADR-0006 §4 *Crossing chunks*), then **the trap trigger** through `TrapLibrary`
     when the tile holds an unused trap (scope 5).
  3. **The window**: assembled at each tick around the adventurer, never stored, never clamped (D-134,
     void chunks a constant), its origin on an even global row, the location's axis orientation kept
     (ENG-02 #246: design/04's tie rule, the lower tile index, must agree between the window's index
     and the location's); assembled only when a goblin is awake (SPK-7).
  4. **The act hook** (step 0, step 2) where Open question 1 places it: perception (design/18), the
     awake selection (≤ 8 among more, `TickTrait::awake`; **L4**, perception's one-pass selection,
     D-172: −1.50 M a worst tick), the shared flood capped at 15 layers (D-127), each free awake
     goblin's choice (move toward, attack, skill; a goblin entering a trap ends its act, §5.11, its
     trigger through `TrapLibrary`). A hook after step 0 never wakes or sleeps a goblin (CBT-02d,
     documented). **L1** (frozen goblins kept as words until touched, ≈ 0.85 M a tick at the bound,
     CBT-02d) is decided here on the lot's own count of its hooks' writes to frozen goblins (D-172):
     the report gives the count and the choice.
  5. **Traps in the batch** (CBT-05b review note: `run` builds `Delegate` with `ground: []`, so a
     `TRAP` carrier resolving inside `run` places nothing, silently): Open question 3. Every member
     move into a trap prices `TrapLibrary`'s **3,564,561** with the move (ENG-01 §9.2, accepted under
     D-144 by the project manager, 2026-10-07); a goblin's trigger replaces its carrier of 4,090,351
     (ENG-01 §9.2), measured.
  6. **The in-play reveal**: when sight (radius 6) touches a chunk not revealed, it is revealed in
     the batch through `RevealLibrary` (ENG-05). In a zone `Instances` rebuilds **every revealed
     chunk's mask word with `PlacementTrait::with_hosts`** from the stored bitmaps, else no chunk is a
     host; **`get_hosts` is read only for a quota whose count is non-zero in the current generation**
     (a reused slot keeps the bitmaps of an earlier generation: reading them for a quota with no count
     would host a quota that does not exist) (PLAN's ENG-07 row, from #348's re-audit note 4 and
     review note 2). ENG-10b's review and re-audit restate it: **the in-play reveal writes a 0 hosts
     mask, or reads hosts only for the quotas whose mask this generation wrote**; a reused slot
     otherwise keeps a stale bitmap. In a dungeon the reveal **reads the outline fixed at entry**
     (ENG-10b: the three `outline` felts into `Site`, the hosts as a zone's) and draws nothing: **a
     dungeon's in-play reveal reads the stored outline, and its layout reads only data fixed at create
     (D-229)**. The reveal's weight in the
     batch is Open question 5.
  7. **The clock**: one per instance, moved by each tick; no action runs past `LAST_TICK` (ENG-01
     §4.1, E-4); the refusal tested at the bound.
  8. **The batch weight** (D-172, D-207): the batch stops before a tick that would pass the
     transaction's limit; a worst tick runs alone. Derived from the worst tick **measured**:
     46,517,111 at CBT-05b's head (ENG-01 §9.2, `rep_all` less `rep_fixture`; accepted under D-222),
     the bomb through `act` 45,968,815 (ENG-01 §9.2, D-222 amended). See *D-207* below.
  9. **The representative fight tick** (D-172: "first, a representative fight tick defined and
     measured"; S1 and the design levers are judged on it), with **1-tick weapons first** (*D-207*).
  10. **Step 2's pending-writes lever** (carried from CBT-05a): keep step 2's goblin writes pending
      and rebuild the awake set once, instead of once a goblin. "At stake: at most 7 of 8 such
      rebuilds a step, about 650,000 a tick" (**estimated, not measured**: CBT-05a's report, *L3's
      pairs, re-measured at `ab71732`*, `docs/reports/CBT-05a-executor.md` l.381). It needs the act
      hook to hold the writes, so it is built with scope 4 and measured as a pair (with and without).
  11. **Vectors**: `contracts/logic/vectors/` gains a movement and window table in the JSON-lines
      format `check.py` checks (moves, Crippled, facing, the window's origin and the adventurer's local
      tile for every row parity, a flood capped at 15 layers, the awake selection's ties); the
      TypeScript mirror is track CV's (`client/sim` is lent to CV): a paired CV PR, asked through the
      orchestrator; a few-line mirror update of an existing table is this lot's.
  12. **Documents**: ENG-01 §1.3 (the classes), §9.2 (the move, the window, the AI, the batch
      weight), §10 (`play`'s measured figures beside its targets); PLAN's ENG-07 row; STATUS (S1's
      running estimate, D-158); `GAS.md` and `docs/BUDGETS.md` regenerated.
- Out: anything of bridges beyond a deck's walkability (one level, D-227; ADR-0008); authored zones' reveal (ENG-09); `loot`,
  `open`, `mine`, `barter` as entrypoints (Open question 6 for Interact); the bit-parallel placement
  (ENG-05b); shrinking `TickLibrary` and `TrapLibrary` (CBT-05g, after this lot); the cost-lowering
  design lot (CBT-05d, weighed on this lot's representative tick); B′ unless fights pay for it.

## Files it touches (allowlist) and each part's test command
| Part | Files | Test command (capped, through `scripts/lock.sh`) |
|---|---|---|
| `contracts/logic` | `src/**` (the act hook's class if Open question 1 keeps one, new files welcome; `types/window.cairo` frozen), `tests/**`, `vectors/**` (new table, README), `GAS.md` | `cd contracts && prlimit --as=8589934592 snforge test -p grimworld_logic --max-threads 2`; `python3 contracts/logic/vectors/check.py` |
| `contracts/ephemeral` | `src/systems/instances.cairo`, `src/store.cairo`, its models, `Scarb.toml` (`build-external-contracts` for a new class), `tests/**`, `tools/lifecycle_probe.py` and its output, `GAS.md` | `cd contracts && prlimit --as=8589934592 snforge test -p grimworld_ephemeral --max-threads 2` |
| `contracts/persistent` | only if a registry check the moves need is missing (an escalation first) | `… -p grimworld_persistent --max-threads 2` |
| gas, sizes | `docs/BUDGETS.md`, `contracts/*/GAS.md` regenerated | `python3 scripts/gas_budgets.py --check` (one whole-package run, `--max-threads 2`, FND-20); `python3 contracts/tools/class_sizes.py` |
| S1 | `spikes/SPK-12/cost.py`, `spikes/SPK-12/cost-output.txt` | `python3 spikes/SPK-12/cost.py` |
| documents | `docs/architecture/ENG-01-interfaces.md` §1.3, §9.2, §10; PLAN's ENG-07 row; STATUS | — |

Anything else is an escalation in the report.

## Open questions (each with its decider and a recommendation)
1. **Where the act hook lives (D-222: decided before the start).** *Decider*: the orchestrator,
   before the lot starts (the project manager if the choice needs a class above 50 % or `TickLibrary`
   above 88 %, D-200, D-222). Sizes at CBT-05b's head (#381's body, VPS): `TickLibrary` 71,839 felts
   (87.69 %, ceiling 88 % = 72,090), `TrapLibrary` 63,151 (77.09 %, ≤ 78 %), `ExecutorLibrary` 80,228
   (≤ 80,420), `Instances` 50.54 % (≤ 51 %), `RevealLibrary` 41,109 (50.18 %, ≤ 50.5 %, ENG-01 §1.3),
   `HostsLibrary` 6,580 (8.03 %; 12,436, 15.18 %, in SPK-17's build with ENG-10b's `floor`). ENG-05b
   brings `RevealLibrary` and `Instances` under 50 % before ENG-07 (D-209), so neither has room for
   the hook. **The act hook's own size is an estimate**: 400–700 code lines, 10,000–35,000 felts
   (E), "plus whatever of `hexx`'s flood the class must hold", not estimated (CBT-05a's report, l.315).

   | # | Candidate | Size (E unless marked) | Call cost a tick (E) | Verdict |
   |---|---|---|---|---|
   | A | In `TickLibrary`, in process (`Delegate`'s hooks) | room 251 felts (72,090 − 71,839, M); with the hook 81,839–106,839 (99.90–130.42 %) | none | does not fit: over 88 % and, at the high end, over the limit |
   | B | A new class, one `library_call` per goblin act | 10,000–35,000 + the flood (12.21–42.72 %) | ≈ 0.52 M a call (CBT-05a's route 2: C 117,910 + ≈ 0.40 M of calldata), up to 8: ≈ 4.2 M | fits, too dear; the pending-writes lever (scope 10) cannot work across calls |
   | **C** | **A new class (`AiLibrary`), one call a tick for step 2 (every free awake goblin), step 0 in the same class or in `TickLibrary` as its size allows**; it calls `ExecutorLibrary` per carrier and `TrapLibrary` per trigger as `TickLibrary` does; carries only the awake set, the member and the board (CBT-05a's lever 3) | 10,000–35,000 + the flood (12.21–42.72 %) | one call: C 117,910 + the awake set's calldata, of the order of one goblin carrier's ≈ 0.40 M: ≈ 0.5 M (two calls with step 0: ≈ 1.0 M), not measured | **recommended**: the only shape that holds step 2's writes pending (scope 10, ≈ 650,000 a tick, E), which may pay its call |
   | D | `act` (CBT-05b's action phase) moved out to an `ActionLibrary`, the hook into `TickLibrary` | `TickLibrary` at CBT-05a's `f1a33f4` 45,427 (M, ENG-01 §1.3) + the hook: 55,427–80,427 (67.66–98.18 %) | every action then needs a second call with the whole words: 2,578,020 to 3,323,680 each (ENG-01 §1.3, M) | rejected: dearest per action, over 50 % |
   | E | A second entrypoint of `HostsLibrary` | 6,580 or 12,436 + the hook: 16,580–47,436 (20.24–57.91 %) | as C | fallback only: saves `Instances` one class hash (config, constructor, `set_contracts`, getter, as `trap_library` cost in #381), but mixes the entry's draw with the tick (D-143's organisation, docs/CAIRO.md §7) |

   **Recommendation: C.** Its first step is a size probe: the hook's class built with its flood and
   measured by `class_sizes.py` (under 50 %, else stop: the project manager), and the call measured
   as a pair, before the rest is wired. `Rules::act` is called per goblin today: C needs step 2's hook
   to take the set (one hook for the step); the `Rules` trait is internal to the logic package (no
   frozen interface), the change is in scope. Reversed by the probe (the class above 50 %, or the call
   dearer than B's total), or by the project manager.
   **Decided by the orchestrator, 2026-10-07:** C, a new class `AiLibrary` called once a tick; the lot
   starts with a size probe and stops and reports if the class would pass 50 %. Reversed if the probe
   shows a per-tick call cost above the per-goblin option's (B).
   **Condition (D-225, the project manager, 2026-10-07):** a call once a tick is a fixed cost on every
   tick of the expedition (a library call with its loads has cost ≈ 3.4 M, D-225); the lot measures
   that per-tick cost first, with the size probe, and calls the hook only on ticks where a goblin is
   in the window if that is cheaper; the per-tick figure goes to the project manager before the merge
   (it feeds R-2).
2. **Where the batch loop and the window's assembly live.** *Decider*: the orchestrator, before the
   start (the project manager for any class exception). `play` is not built; one `TickLibrary` call
   carries the whole words (2,578,020 with no kill in, 3,323,680 at every bound, ENG-01 §1.3, M), so a
   loop in `Instances` that calls `TickLibrary` once an action pays that up to 10 times a batch
   (≈ 26–33 M, E). *Recommendation*: **one `TickLibrary` call a segment**: `act` takes the segment's
   actions (Moves included) and runs them in process, the window re-assembled at each tick from the
   chunk words `Instances` passes once (SPK-7: read chunks once per batch); `Instances` splits the
   batch at each reveal (at most 4 a batch, ENG-01 §9.2) and runs the reveal between two segments,
   since it owns the chunk slots. Measured first: `TickLibrary`'s size with the loop, the moves and the
   assembly (251 felts of room today: likely over 88 %); over → stop and send the project manager the
   figures with the fallback measured (the moves and the assembly in C's class, or the loop in
   `Instances` with its per-action cost). Reversed by those figures.
   **Decided by the orchestrator, 2026-10-07:** one `TickLibrary` call per segment, the batch split at
   reveals; if `TickLibrary` would pass 88 % (D-222), stop and report to the project manager.
3. **Traps placed inside `run`.** *Decider*: the orchestrator. A `TRAP` skill with an activation,
   started by `act`, resolves in step 1 of a later tick; if that tick runs in `run`, its `Delegate`
   has `ground: []` and the trap is dropped. *Recommendation*: whatever entrypoint runs a batch's ticks
   (Open question 2) carries the batch's `ground` across all of them (`run` gains a `ground`
   parameter, or is replaced by the segment entrypoint), with a regression test: a `TRAP` skill of
   activation ≥ 1 started in one action resolves in a later tick of the batch and its trap is on the
   tile.
   **Decided by the orchestrator, 2026-10-07:** `ground` is carried across the batch's ticks, with
   A6's regression test.
4. **L1, the frozen goblins kept as words.** *Decider*: this lot, on its own count (D-172); the
   orchestrator reads it in the report.
5. **E-12's reveal weight 2** (ENG-01 §10.1: "a reveal at weight 2 costs about 1.4 M"; ENG-05 measured
   2,830,905 typical and 3,901,320–4,067,457 worst in memory, ENG-01 §10; PLAN: "2.4 M typical a chunk
   against 1.4 M", reopened here). *Decider*: the project manager (the batch weight, D-207).
   *Recommendation*: measure a reveal in play end to end (the `RevealLibrary` call, the slots, the
   hosts' masks, and the extra segment call of Open question 2) in a zone and a dungeon, and propose
   the weight that keeps the worst reveal batch under the transaction's limit with D-207's one-tick
   rule; 3 if the measure says so.
   **Decided by the project manager, 2026-10-07 (D-225):** this lot measures the reveal weight end to
   end, sets it to 3 if the figures say so, and states them.
6. **Interact in `play`.** *Decider*: the orchestrator. `open`, `mine` and `barter` are their own
   entrypoints (ENG-01 §4.1), not built. *Recommendation*: an Interact in a batch is refused as
   illegal (the batch stops) until the lot that builds those entrypoints; tested.
   **Decided by the orchestrator, 2026-10-07:** Interact in `play` is refused as illegal until its
   entrypoints exist.
7. **Bridges (D-217).** *Decider*: the project manager rules ENG-08b's design; until ENG-08b merges
   ENG-07 **assumes one level: movement, the flood, sight and the window read the walkable plane only,
   and a `BRIDGE` record is ignored** (as the converter's reachability P-1 does, PLAN's ENG-08b row: a
   map whose only crossing is a bridge is refused).
   **Decided by the project manager, 2026-10-07 (D-225):** one level and the walkable plane until
   ENG-08b merges. **Settled by the owner, 2026-10-07 (D-227):** bridges have one level (ADR-0008,
   merged in #383): a deck is walkable ground over water, entered and left like any walkable tile.
   Nothing in ENG-07 changes for bridges beyond walkability.

## D-144: the expedition-path figures it adds, and the ceilings in force
Every rise of an expedition-path figure, whatever its size, goes to **the project manager before the
merge** (D-144 strictly, the project manager 2026-10-02), with its cause. Measured on the node by
`lifecycle_probe.py` (at least six runs, the maximum, as ENG-05b resets the ceilings) where the node
can run it, else snforge pairs.

| Figure | Ceiling or reference in force | Source | ENG-07 gives |
|---|---:|---|---|
| `play`, weight 10, the cap of 16 goblins, ticks as alone | target 47,336,950 initialised, 48,537,162 cold | ENG-01 §10, the `play` row | the node's figure of the worst batch |
| `play`, one 3-tick action, 42 goblins (E-21) | 20,556,791 initialised, 57,612,495 cold; the class bound 58 M cold (D-141) | ENG-01 §10, §9.2 | measured |
| The worst tick, a one-tick batch | 46,517,111 (accepted, D-222); the bomb through `act` 45,968,815 | ENG-01 §9.2 | re-measured with the act hook |
| A move (1 tick), no goblin awake; with goblins awake | none; the window 65,224 (memory) to 720,000 a tick (ENG-01 §10.1, SPK-7) | ENG-01 §10.1 | measured, both |
| A member's move into a trap | +3,564,561 through `TrapLibrary` (accepted, D-144) | ENG-01 §9.2 | priced with the move |
| A goblin's move into a trap | replaces its carrier, 4,090,351 | ENG-01 §9.2 | measured: the trigger through the hook's class |
| The awake selection at step 0 | 4,663,510 over 100 candidates; L4 −1.50 M a worst tick (D-172) | ENG-01 §9.2, PLAN | measured with L4 |
| The act hook's call (Open question 1), **per tick of the expedition** (D-225) | none; ≈ 0.5 M a tick (E, this brief); a library call with its loads has cost ≈ 3.4 M (D-225) | this brief, D-225 | measured first, with the size probe, on every tick and on ticks with a goblin in the window only; the cheaper kept; sent to the project manager before the merge (R-2) |
| Step 2's pending writes (scope 10) | −650,000 a tick (E) | CBT-05a's report l.381 | measured as a pair |
| A reveal in play, zone | none; in memory 2,830,905 typical, 3,901,320–4,067,457 worst; the library call 544,510 | ENG-01 §10 | measured end to end |
| A reveal in play, dungeon | none ("measured by ENG-07") | ENG-10b's brief, D-144 table | measured end to end |
| `enter`, `leave` (every row) | ENG-05's ceilings (ENG-01 §10, *The D-144 ceilings of ENG-05*) as ENG-05b and ENG-10b reset them | ENG-01 §10 | unchanged; any move goes to the project manager |

## D-207: the batch weight and the worst ticks' frequency
- The weight is derived from the worst tick measured (46,517,111; the bomb through `act` 45,968,815):
  such a tick runs as a batch of one (D-207), and a batch stops before a tick that would pass the
  limit (D-172).
- **First**, the representative fight with **1-tick weapons**: with them 8 goblin carriers may come
  every melee tick, and a 10-tick batch of melee ticks near **369 M** (estimated, PLAN's ENG-07 row:
  under the 1.1 × 10⁹ cap, 9 × 40 M) **reopens D-207 and R-2** (D-207's reversal test: "worst ticks
  frequent enough to break R-2"). The lot measures the frequency of worst ticks on that fight and
  sends the project manager the figure before it fixes the weight; R-2 is the owner's.
- COST-4 (CBT-02d's re-audit): the awake selection's and `Busy`'s absolute figures differ between
  isolated and full-suite runs (1,230 and 1,430 apart, PLAN); reconciled before the weight uses them.
- D-145: where `bundle`'s 36,000 a slot goes (the call against the read) is measured before the
  weights freeze.

## Entry and leave figures into S1 (`cost.py`)
ENG-05's rises (`enter` +2.76 M to +3.52 M, `leave` +3.76 M to +6.73 M, accepted under D-144; PLAN's
ENG-05 row), ENG-10b's measured dungeon entry, and this lot's representative tick go into S1's cost,
`spikes/SPK-12/cost.py` (R-2 is the whole expedition; STATUS l.18), rerun with its output committed;
STATUS's S1 running estimate updated (D-158).

## Acceptance criteria
| # | Criterion | Shown by |
|---|---|---|
| A1 | The report opens with Open questions 1 and 2 as decided, the size probe's figures (`class_sizes.py`, Linux) and the call's pair | the report |
| A2 | `play` runs a batch of the five combat kinds and Moves; an illegal action stops the batch with nothing written after it; sequence and version refused when stale; `LAST_TICK` refused at the bound | `contracts/ephemeral/tests/`, snforge |
| A3 | Moves: walkable, unoccupied, Crippled 2 ticks, facing, the occupancy bits across a chunk seam; every row of the movement vector table | snforge; `check.py` |
| A4 | The window: origin on an even row, the adventurer at local (7, 7) or (7, 8), never clamped at a location's edge (void constants), a chunk not revealed is wall, the tie rule equal in the window's index and the location's (ENG-02 #246) | snforge; `check.py` |
| A5 | The act hook: ≤ 8 awake by distance then id, the flood stopped at 15 layers with a walker beyond it holding its tile (D-127), each goblin's choice deterministic; no hook after step 0 wakes or sleeps a goblin | snforge |
| A6 | Traps: a member's move into a trap triggers it once through `TrapLibrary`; a goblin's ends its act; a `TRAP` skill resolving in a later tick of the batch places its trap (Open question 3) | snforge |
| A7 | **A zone's quotas land on their hosts through the in-play reveal path**: through `Instances`, a zone with a quota whose host chunks are not among those the entry reveals; a batch of moves brings sight onto each host chunk; each quota's elements are placed on host chunks only and its count left reaches 0. **And a reused slot**: the slot's earlier generation had that quota with a count, the current one has none, and no element of it is placed (`get_hosts` read only for a quota with a count) | `contracts/ephemeral/tests/`, snforge |
| A8 | A dungeon reveal in play reads ENG-10b's outline and draws nothing: the chunks revealed by moves equal the stored outline's, in two move orders | snforge |
| A9 | The representative fight tick defined and measured, 1-tick weapons first; the worst ticks' frequency on it; the batch weight derived (D-207), with Open question 5's reveal weight | the report, ENG-01 §9.2 |
| A10 | Step 2's pending-writes lever measured as a pair (kept or not, with the figure) | the report |
| A11 | Every figure of the D-144 table measured and sent to the project manager before the merge; S1 rerun (`cost.py`) | the report, ENG-01 §10, STATUS |
| A12 | Every class within its ceiling (`class_sizes.py`); D-143's organisation (docs/CAIRO.md §7); unit tests in their modules (D-167); every test with a gas budget; CI green; `gas_budgets.py --check` | CI, the report |
| A13 | **`AiLibrary`'s per-tick cost (D-225)**, measured first with the size probe: the call on every tick, and only on ticks with a goblin in the window; the cheaper kept, with a test that a tick with no goblin in the window makes no call if that one is kept; the figure sent to the project manager before the merge (R-2) | the report, ENG-01 §9.2 |

## The rules this lot follows
- **Memory.** Every Cairo build and test is capped: `prlimit --as=8589934592`, through
  `scripts/lock.sh`, with `snforge … --max-threads 2` (CBT-05b's workspace run, capped and at 2
  threads, peaked at 2.83 GB, #381; SPK-17's suite 2.83–2.92 GB). A run whose peak is unknown (a new
  class, a large vector or window test) is measured first, capped (`/usr/bin/time -v`). Above about
  8 GB: stop and report, never rerun uncapped on the VPS. Keep generated tests and vectors small
  (FND-23: split by seeds, oracles in modules). A CI job killed out of memory is a stop signal, not a
  reason to rerun locally.
- **Scoped tests.** Run the tests of the packages touched (the table above); the gas files are
  regenerated once, by one whole-package run each (`gas_budgets.py`, FND-20). Every pinned figure
  (gas, class sizes) comes from Linux (the VPS or CI), never the Mac; no class hash is pinned.
- **Git.** `git rebase origin/main` only before the first push, alone in its call; after a push,
  merge `origin/main`. Push with `git -c core.sshCommand='ssh -o ServerAliveInterval=30 -o
  ServerAliveCountMax=40' push …` (the pre-push hook can run long). Never skip hooks, never
  force-push. Untracked files of the worktree are removed with `git clean -f -- <exact path>` only,
  never with `-d`, `-x` or `-X`.
- **Signals.** A test of timeouts or interruption signals only processes it started, by recorded pid.
- **Escalations.** A design gap stops that part; the question goes in the report under *Escalations*.

## Audit
Expected: **one cost lens** (D-177: the batch weight, the representative tick and the worst ticks'
frequency feed R-2 and D-207, and only a measurement proves them). The orchestrator decides at the
close.

## Report
The repository's thread report (docs/briefs/COMMON.md §7): the two placements and their probes, each
acceptance criterion with its evidence, the class sizes, the D-144 table with the measured figures,
the representative tick and the weight, the L1 count, the pending-writes pair, S1's rerun, the gas
table of every test.
