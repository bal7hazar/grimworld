# ENG-01's escalations: the rules the frozen interfaces leave to decide

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from ENG-01 ([interfaces](../architecture/ENG-01-interfaces.md) §11, [report](../reports/ENG-01-core-interfaces.md), audit `[GPT-6-Astra]`, [#81](https://github.com/bal7hazar/grimworld/pull/81)) |
| To be answered by | `[Fable 5.1]` project manager (D-128); game rules go to design/, cost departures to cost-budget.md |
| Needed by | ENG-07 (`play`'s weights and caps: E-1, E-16, E-21), ENG-02/ENG-04 (the hub's settlement: E-15, E-20), ENG-05 (the roster: E-2) |

ENG-01 froze the five contracts' interfaces, layouts and events, and priced every entrypoint from
the union of its physical keys. The code follows a **default** for each open choice; none of these
blocks the merge, but ENG-02 to ENG-07 implement against them. The figures are L2 gas, from
§9–§10 of the interfaces document; "cold" means the key was never written in that instance slot, in
any generation (instance slots are reused, a zeroed key costs as new, so records are never zeroed).

## 0. The merge: two majors left after three fix loops (OPERATIONS §6)

The final `[GPT-6-Astra]` re-audit at `4a1ba2b` ([audit](../reports/ENG-01-audit-gpt-6-astra.md))
resolves F-1, F-5 to F-14 (generation isolation and the class-size gate included) and finds **no
security finding** in the interfaces and stubs. Two majors and one minor remain, all in the cost
accounting (`contracts/tools/budget_table.py` and the document's §9–§10), none in the code the next
tasks build on:

| # | Gap | Effect on the figures |
|---|---|---|
| F-3 (major) | Standalone actions do not union an objective their ticks can complete (a burning Rift Heart dying while the adventurer mines); `barter`'s price refusal omits its `Hub.barter` call | `mine` cold 57.31 M → 57.84 M; initialised 20.56 M → 20.67 M |
| F-4 (major) | `enter_rift` has no first-entry branch (an adventurer's first instance can be a Rift) | its cold maximum 6.95 M → 12.46 M (as `enter`'s first entry, 11.77 M) |
| F-2 (minor) | Reveals use separate key identities from the window's, so §10.1's "at most 64 keys" meets a 66-key reveal row; one sentence on E-1 (b) overstates | wording, and the slot bound |

| Option | Cost |
|---|---|
| (a) **merge #81 now**, and close the three gaps in a follow-up, **ENG-01b** (Sonnet 5, the accounting script and §9–§10 only, `[GPT-6-Astra]` audit), run beside FND-05; ENG-07, which sets `play`'s weights from these tables, depends on ENG-01b | the frozen interfaces reach main now; FND-05 and ENG-02 start today |
| (b) a fourth fix loop on #81, then merge | one more loop and audit (about an hour); FND-05 and ENG-02 wait |
| (c) keep #81 open until the design decisions below | blocks Phase 0's engine track |

**Recommendation: (a).** The gaps are precise (the auditor gives the missing branches and their
figures), confined to one script and two sections, and change no interface, layout or event; the
next tasks implement against the interfaces, not against these maxima. ENG-01b touches no file
FND-05 touches.

## A. Decisions expected (game rules, or a design rule the cost breaks)

| # | Question | Options and cost | Recommendation |
|---|---|---|---|
| **E-16** | How many goblins one invocation of `play` may change. Uncapped, a batch can change 140 (280 words: 8.98 M initialised, 127 M cold), and 40 M cannot hold | (a) cap at **16 distinct goblin records** an invocation: the batch stops before the action that would pass it (`Stop::Weight`), the client counting as the contract; worst branch 64 keys, 47.33 M (40.78 M with the window at its low end). (b) cap at 24: +0.51 M. (c) no cap | **(a)**, a rule of `play` (ENG-07) |
| **E-1** | A goblin's first record in a slot is a new key (+0.84 M over an overwrite). Cold, the worst capped batch costs 62.01 M against 47.33 M, and no weight counts the difference | (a) **weigh it**: +1 weight per goblin record written for the first time in the slot. (b) one word per goblin: loses the activation (telegraphed skills and their interruption, design/04), the five conditions and the effect, a change of the combat design. (c) accept the overrun | **(a)**: counted by the client as by the contract, no design loss |
| **E-21** | One action that cannot be split (a 3-tick skill, `mine`) can change 42 goblins: 20.55 M initialised, **57.60 M cold** | (a) **it runs**: caps and weights bind from the second action of an invocation; the class has its own bound. (b) it is refused: in a cold slot keys warm only by running, so it can stay refused (a stall) | **(a)**, with a cold bound of 58 M for that class |
| **E-15** | What happens to the belt's unused potions on **defeat** (the reserve is debited at entry, credited back unused on return). design/07 keeps loot on defeat; design/02's D-04 says defeat costs "the instance, nothing else" | (a) credited back as on return (≤ 4 pack pages, 0.13 M). (b) lost on defeat. (c) lost only in a sealed Red Rift | **(a)**: it reads D-04 as written; (b) or (c) is a tuning choice for BAL-01 later. ENG-02's hub rule waits for this |
| **E-20** | What of a member carries through a gate within one expedition (next zone, next floor). Default: nothing but the belt's reserve | (a) nothing. (b) health, energy, adrenaline carry. (c) also conditions, effects and recharges, deadlines rebased on the new clock. No cost difference: the same 4 member words are written | **(a)** for the MVP (a descent heals); (b) is a design choice design/02 should state either way |
| **E-2** | The roster of displaced goblins (alive, or dead and unlooted, away from their spawn chunk) holds 60 entries. What of a 61st? | (a) a goblin does not leave its spawn chunk while the roster is full (it holds at the chunk's edge). (b) its remains are not left when it dies away. (c) a larger roster (+1 page each 15) | **(a)**: no loot is lost, and a goblin away from its spawn is already on the roster, so the one rule covers both cases |
| **E-7**, **E-8** | Budgets passed. `enter` 3.73 M against 1.9 M (the belt's reserve, the snapshot, two events). Standalone Fate actions against 2.9 M: `open` 9.13 M, `barter` 8.94 M, `loot` 3.68 M, `mine` 20.56 M initialised (57.31 M cold, E-21), all with goblins near; 2.5–3.0 M with none | (a) accept per-branch budgets (§9.3). (b) `enter`: the snapshot as calldata against a hash, −3 slots, but `instance_state` no longer holds it (design/02) | **(a)**: the overrun is the ticks the action runs among goblins, which design/02 requires |
| **E-18** | `mine` draws nothing (design/17) yet design/02 sends it alone | (a) standalone, as frozen: one more transaction floor (0.82 M) a vein. (b) an *Interact* inside `play` (weight 3) | **(a)** until ENG-07 measures the tick in a batch; (b) is the lever if S1 misses $0.50 |
| **E-5** | Play reads the registry (one `bundle` call an invocation, 0.14 M); a content update during a live instance changes its outcomes | (a) as is. (b) mirror play's content in `Instances`. (c) (a) plus a content version fixed at entry and checked at each invocation | **(a)** with an operating rule: content changes only in a release that no live instance spans; (c) if ENG-03 finds the check costs one read |

**The cost target.** With these defaults, S1 (300 actions) is estimated at **631.1 M ≈ $0.556**,
above $0.50 (the best row of cost-budget §3 was $0.537), plus about $0.053 once for an adventurer's
first expedition. Whether S1 meets $0.50 turns on CB-2 (whether a tick inside a batch shares its
reads and writes), which ENG-07 measures. No decision is asked on it now; it is the figure to watch.

## B. Recorded, no decision asked (the default stands unless you say otherwise)

| # | Default |
|---|---|
| E-3 | A chunk holds at most 2 packs of 5 goblins and 3 objects (ENG-05 caps its generation) |
| E-4 | Every deadline ≤ 2^28 − 1 ticks; an action past `LAST_TICK` is invalid (8.5 years at a tick a second) |
| E-6 | `barter` calls `Hub.barter` in the transaction (the collector's price is in the pack) |
| E-9 | Version 1's attempt-stable Fate (a request, a later draw) is ADR-0002's, not Phase 0's |
| E-10 | Class sizes checked in CI: added by the orchestrator to #81 (every class passes; `Instances` at 7.82 % of the limit) |
| E-11 | Market lots are new slots (ids never reused); a trade side ≤ 7 entities and ≤ 2 balances |
| E-12 | A reveal weighs 2 in the bound (about 1.4 M the first time, 0.6 M after); ENG-05 may lower it to 1 |
| E-13 | design/02's tests that need game logic (batch = singles = multicall, the gas proof, the region and generation cases) move to ENG-05, ENG-06 and ENG-07 |
| E-14 | quiver's components are not embedded yet (ARC-03c/04) |
| E-17 | The per-action events (`GoblinKilled`, `ChunkRevealed` among them) are kept (up to 1.1 M a worst batch) |
| E-19 | `set_account_owner` zeroes the old owner's entry (a later reuse of that address pays a new key; rare) |

## Decision

By the project manager on 2026-09-29, under D-128 (D-141).

### The merge

**Option (a): pull request #81 is merged now.** The two majors and the minor left by the
audit are in the cost accounting, not in the interfaces, layouts or events, and the audit
finds no security finding. They become task **ENG-01b** (Sonnet 5.5, the accounting script
and §9–§10 only, audit `[GPT-6-Astra]`), run beside FND-05. ENG-07 depends on ENG-01b.

### The design decisions

| # | Decision | Note |
|---|---|---|
| E-16 | **(a)** At most 16 distinct goblin records changed by one invocation of `play`; the batch stops before the action that would pass it; the client counts as the contract | A rule of the transaction, not of the game: the player sees a batch leave earlier, nothing else |
| E-1 | **(a)** A goblin record written for the first time in a slot weighs 1 more | |
| E-21 | **(a)** An action that cannot be split runs, whatever it changes; its class has its own bound, 58M cold | A refusal could never be lifted: a rule never blocks a legal action (D-140) |
| E-15 | **(a)** On defeat the belt's unused potions are credited back, as on return | D-04: defeat costs the instance, nothing else. Whether a Red Rift should cost more is a question for the balance simulator, later |
| E-20 | **(a)** Nothing of a member carries through a gate but the belt's reserve: health, energy, conditions and recharges start anew in the next instance | It is the baseline's rule (a new area restores the character), and the belt, filled once for the expedition, is what wears down over the floors of a dungeon. **A choice of design the owner may reverse**: carrying health and energy would make a dungeon a test of endurance |
| E-2 | **(a)** While the roster of displaced goblins is full, a goblin does not leave its spawn chunk | No loot is lost |
| E-7, E-8 | **(a)** Budgets per branch | The overrun is the ticks an action runs among goblins, which the design requires |
| E-18 | **(a)** `mine` is sent alone, until ENG-07 measures a tick in a batch | The lever to pull first if the worst expedition misses the target |
| E-5 | **Not (a): a content version.** The registry carries a version number, returned by the `bundle` call that every invocation already makes. The client states the version its batch was computed under; if it differs, the batch is refused whole, without executing, and the client reloads the content and computes again. The instance goes on under the new content | The operating rule proposed with (a), "content changes only when no live instance spans the release", cannot hold: the world waits, and an instance may stay open for weeks (design/02). Content will change under live instances; what must not happen is a batch computed under one content and executed under another. ENG-03 measures the cost (one compared value, one felt of calldata) |

### Section B

The eleven defaults stand. E-14: `quiver_quest` 0.1.0 is published since; the quest
component is embedded by GLD-02.

### The cost

The worst expedition is estimated at $0.556 with these defaults, for a target of $0.50;
the mixed one is under it. No decision is taken on it before ENG-07 measures a tick inside
a batch. The levers, in the order they would be pulled: `mine` inside `play` (E-18), the
snapshot of `enter` as calldata (E-7), the per-action events (E-17), then the target itself
with the business model.

**Added by D-145** ([ENG-03's registry](2026-09-29-eng-03-registry.md)): reading content costs about
36,000 L2 gas a slot (`bundle`, measured by ENG-03), which §10 counted as one call. At 10 records a
batch that is about +30M on S1, **about +$0.026**. The lever: an invocation reads only the records
its ticks use, and, if ENG-06 and ENG-07 find the call between contracts is most of the 36,000, a
batch reads its records in one call.

