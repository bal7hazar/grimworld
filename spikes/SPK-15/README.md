# SPK-15 — The tick's cost levers, measured before CBT-05

D-171 (`docs/decisions/2026-10-01-tick-cost-spike.md`), brief `docs/briefs/SPK-15-tick-cost-levers.md`.
A spike: nothing here merges into `contracts/`. It measures what each lever saves on the worst tick
inside a batch (CBT-02d's basis), on the representative tick, and on the expedition S1, and keeps
the **engineering levers** (no rule changes; the project manager decides) apart from the **design
levers** (a rule changes; the owner decides).

## Run it

```
scarb --manifest-path spikes/SPK-15/Scarb.toml build
(cd spikes/SPK-15 && snforge test)
python3 spikes/SPK-15/summarize.py spikes/SPK-15/snforge-test-output-{1,2}.txt   # every pair
python3 spikes/SPK-15/levers.py spikes/SPK-15/snforge-test-output-{1,2}.txt      # the table
python3 spikes/SPK-15/set_budgets.py spikes/SPK-15/snforge-test-output-{1,2}.txt # ceil(1.05 × measured)
```

## Method

- **Pairs.** Every figure is the difference of snforge's totals of two tests that differ by the
  measured call alone (`test_pair_*` against its `*_base` or `*_fixture`; `summarize.py` names each
  pair's base). CBT-02d showed that `get_available_gas` around a call misses its straight-line part.
- **Two clean builds** (D-154): `scarb clean`, then `snforge test`, twice
  (`snforge-test-output-1.txt`, `-2.txt`). Every one of the 76 pairs is equal to the unit in both
  (`pairs.txt`, fix loop 1's build). Build-to-build drift seen on the way: an earlier build measured
  the pairs that read words, write the world or build the index 1,060 to 1,460 higher (main's load and
  store 10,571,730 against 10,570,470); the figures here are the last build's.
- **Checks.** Main's figures reproduce: CBT-04's member application 108,100 and goblin application
  76,820 to the unit; main's load and store at the bound 10,570,470 (CBT-02d: 10,570,470); the
  representative tick 636,067 (CBT-02d: 636,067); the costliest tick at 8 awake 1,477,717 (CBT-02d:
  1,475,797, +1,920, the drift above); perception's selection at its maximum 4,663,690 (ENG-01:
  4,663,510), and the spike's verbatim copy of it (`src/perception.cairo`) 4,660,390. Every alternative
  is checked against the code it replaces (`test_alternatives_match_*`, `test_perc_agree_*`,
  `test_selection_agrees`, `test_executor_*_agree`, `test_executor_guard_two_hits`).
- **Sources copied** (the branches are not merged; never edited): `src/cbt04.cairo` from
  `feat/cbt-04-conditions` at `b5f4069` (`types/infliction.cairo`; the member's `is_alive`,
  `infliction` and its `MemberConditionTrait` whole; of the goblin's `GoblinConditionTrait`, `apply`,
  `takes_critical` and `can_defend` only; `TickMathTrait::held`, `move_ticks`); `src/cbt03a.cairo` from
  `feat/cbt-03a-hit` at `36bf2ba` (`types/hit.cairo` above its tests, and `Arc`). Their bodies are
  unchanged but for `scarb fmt` and the `use` lines. `tests/fixtures.cairo` copies main's
  `contracts/logic/tests/test_tick.cairo` fixtures at `d4b5cdc`; `src/perception.cairo` copies main's
  `TickTrait::awake` from `contracts/logic/src/types/world.cairo` at `d4b5cdc`.
- **Counts of a worst tick** are CBT-04's and CBT-03a's (ENG-01 §9.2): 8 goblin carriers (a hit and
  2 applications on the member each), the member's one carrier (7 goblins hit, 7 applications), 9
  predicate sets; a goblin carrier reads at most 4 entries (its skill's 3, its held effect's 1), the
  member's at most 7; hooks write at most 6 frozen goblins an action (ENG-01 §9.2), counted as 6 in a
  worst tick (an action of one tick).
- **S1** counts 300 ticks (SPK-1 §5's expedition: every action near goblins runs one tick).
  "S1 (representative)" is the representative tick's saving × 300; "S1 if every tick were the worst"
  is the worst tick's × 300, a ceiling, not an estimate. Dollars at cost-budget.md §2: 1 M L2 gas =
  $0.000881.
- **D** measured here; **C** cited (the brief, ENG-01, LIB-05 M1-T9b); **E** derived by arithmetic
  from measured terms. Every E is named below.

## What the measurements show

### Lever 1 — the frozen goblins kept as words (`src/words.cairo`)

| At CBT-02b's costliest words (100 goblins, 8 awake), a call | Main | Kept as words | Saved |
|---|---:|---:|---:|
| Load and store | 10,570,470 | 3,128,940 | 7,441,530 (**744,153 a tick** at 10 ticks a call) |
| A frozen goblin a hook touches (read, written back) | 674,470 | 477,720 | 196,750 each; 6 a worst tick: 1,180,500 |
| The representative words (8 goblins, all awake) | 1,292,290 | 1,324,840 | −32,550 (a cost: 3,255 a tick) |

- `lazy_load` decodes the members and the awake set only, and keeps each goblin's AI state (one
  field of its words) for perception; `lazy_store` copies every frozen word unchanged.
- **Perception with L1 alone** (main's 8 scans over words) is dearer, not cheaper: a goblin it wakes
  is decoded, one it puts to sleep encoded, and each frozen key read from its words. Worst of four
  states: **5,528,370** (replaced) against main's 4,663,690: **+864,680** (lever 4, below).
- **L1 alone, everything counted: −1,059,973 a worst tick** (load and store −744,153, perception
  +864,680, the hooks' 6 frozen writes −1,180,500); **+120,527 (a cost) without the hooks' writes**.
- **What changes:** `load`'s contract with perception. Perception (ENG-07's step 0) reads the frozen
  goblins' AI states, not `Goblin` values; a goblin it wakes is decoded then, one it puts to sleep
  encoded. The content's `Index` lives for the whole call (a goblin can be decoded at any hook).
  No stored layout changes.
- Load and store per goblin in the call: main 96,440, kept as words 15,200 (D: 100, 60 and 40
  goblins).

### Lever 2 — one condition's application (`src/application.cairo`)

| On the member | L2 gas |
|---|---:|
| CBT-04's pair: the member's kit read, then `apply` | 108,100 |
| `apply` with the source given | 91,000 |
| its parts alone: the kit's read · the duration · main's `inflict` · main's `interrupt` · handing the member to a call | 19,020 · 13,250 · 37,820 · 37,900 · 3,600 |
| **in place**: one inlined function, the deadline written to its field | **57,180** |
| split by condition: conditions 1–4 · the knock-down (`knock`) · a degenerating condition only | 31,940 · **55,280** · 24,200 |
| gathered: one application added · the gathered applications written | 22,100 · 54,130 |

| On a goblin | L2 gas |
|---|---:|
| CBT-04's `apply` | 76,820 |
| its parts: `inflict` · `interrupt` · a call | 33,490 · 29,150 · 2,600 |
| **in place** | **47,900** |
| gathered, written | 60,090 |

- **What 108,100 is made of.** 17,100 is the member's own kit read inside CBT-04's pair: the 16
  applications on the member come from goblins, which have no kit. CBT-04's line is therefore
  **2,114,010**, not 2,368,590 (16 × 91,000 + 7 × 76,820 + 9 × 11,250 + one kit read for the member's
  carrier, 19,020). The rest is two non-inlined calls (`inflict`, `interrupt`) charged their
  costliest path: Sierra charges a function without a loop its costliest path, so every
  application pays the knock-down's interrupt and Crippled's word read, whatever the condition.
- **In place, by condition:** the executor already dispatches on the entry's condition. Writing
  the field directly, with Knocked down apart, costs 55,280 at worst (a knock-down), 31,940 for
  conditions 1–4 and 24,200 for Bleeding, Poison or Burning. At the bound (every application a
  knock-down): **−773,960 a tick** (16 × 35,720 + 7 × 28,920).
- **Gathering a tick's applications** (one write per actor) does not pay: 22,100 an application
  plus 54,130 a flush, against 24,200 for a degenerating condition in place. It is also exact only
  if every gathered field is flushed before anything reads it (a hit reads Knocked down, a move
  Crippled, a cure and step 3 the degenerating deadlines).

### Lever 3 — the executor's overhead (`src/executor.cairo`, an estimate of CBT-05)

| Measured on CBT-02's heavy state (100 goblins, 8 awake) | L2 gas |
|---|---:|
| An actor read from the world and written back: the member · an awake goblin · a frozen goblin | 32,930 · 114,670 · 674,470 |
| A goblin's hit on the member: the inputs gathered (4 effect slots decoded) · gathered with the member's guard given · the guard (each slot's charges kept) | 245,596 · 24,216 · 228,110 |
| A goblin's weapon hit end to end (read, gather, CBT-03a's `resolve`, the outcome with a blocked hit's charge spent, write back) · the same with the guard read before and updated at a block | 541,656 · 322,816 |
| A bomb on 3 awake goblins, written together (D2′'s slope: 273,945 a target, 113,705 fixed) | 935,540 |
| A bomb on 7 awake goblins (hit, `CONDITION`, kill), each goblin written after its own · the 7 written together (`flush`) | 2,479,950 · 2,031,320 |
| A `CONDITION` on the member, read and written · on an awake goblin | 125,010 · 191,770 |
| An entry decoded from its 97 bits | 30,920 |

- **The executor as CBT-05 would write it naively (E):** 8 goblin hits at 541,656 less the hit
  (46,250), the bomb's 2,479,950 less its 7 hits and 7 applications and the kit, 39 entries decoded
  at 30,920: **6,768,568 a tick**, on top of every line above. (Fix loop 1: a blocked hit now spends
  its charge, a path Sierra charges every hit: +66,080 a hit.)
- **Levered (E):** the member's guard read once a tick **and updated whenever the executor holds,
  spends or ends an effect** (fix loop 1, finding 3: a guard read once and never updated would block
  a second hit with a charge the first spent; `GuardTrait::spend` updates it at a block, and
  `test_executor_guard_two_hits` checks A blocked, B landing, against the guard read at each hit), a
  carrier's goblins written in one rebuild, the content's entries decoded once a call with the sheets
  (118 entries, 364,856 a tick): **3,956,304 a tick (−2,812,264)**.
- **What dominates what remains:** writing an awake goblin back rebuilds the awake set's 8 goblins
  of 24 felts (114,670); a lighter value (its derived fields apart) and step 2's own writes kept
  pending to one rebuild (the bomb's flush saves 64,090 a goblin) are the next levers. Not measured.

### Lever 4 — perception's selection, alone and with lever 1 (`src/perception.cairo`, `src/words.cairo`)

Perception is not in the 6.51 M: ENG-07's step 0 selects the awake set every tick. Over 100
candidates, by state (D; `tests/bench_perception.cairo`; the worst of each row is the figure used):

| Representation and selection | Formed | Kept (end) | Kept (start, distances rising) | Replaced (8 out, 8 in) | Worst |
|---|---:|---:|---:|---:|---:|
| main (`TickTrait::awake`), as it stands | 4,596,450 | 4,656,050 | 4,663,690 | 4,655,170 | **4,663,690** |
| its verbatim copy (`awake_scan`), a check | 4,593,150 | 4,652,750 | 4,660,390 | 4,651,870 | 4,660,390 |
| **L4 alone**: main's goblins, one pass (`awake_single`) | 3,101,190 | 3,160,790 | 2,582,390 | 3,159,910 | **3,160,790** |
| **L1 alone**: words, main's 8 scans (`LazyTrait::awake`) | 5,397,410 | 5,063,770 | 4,972,970 | 5,528,370 | **5,528,370** |
| **L1 and L4**: words, one pass, AI states kept at load | 3,567,850 | 3,264,450 | 2,587,610 | 3,729,050 | **3,729,050** |

- **L4 does not need L1.** The one pass (1,071,130 against the 8 scans' 2,562,050 alone) works on
  main's decoded goblins: **−1,502,900 a worst tick, alone**, no frozen interface touched.
- **L1 makes perception dearer** (+864,680 with main's 8 scans; +568,260 with the one pass): its
  wakings decode and its sleeps encode. The earlier table credited L4 with what L1 and L4 save
  together and charged L1 nothing for perception; this table prices each alone and together.
- **The content's index** (once a call): 557,210, 55,721 a tick; inside load and store.

## The table

Per worst tick inside a batch of 10, each engineering lever priced on **everything counted** (the
brief's basis, CBT-05's executor, ENG-07's perception, the map library, the hooks' writes to frozen
goblins); L1 and L4 alone, the one given the other, and together. The design levers are priced after
all four engineering levers. Generated by `levers.py` (`levers-output.md`).

| Lever | Kind | Worst tick | Representative tick | S1 (representative × 300) | S1 if every tick were the worst | Cost in code | Frozen interfaces | Lots |
|---|---|---:|---:|---:|---:|---|---|---|
| CBT-04's line re-measured (the member's kit read once a carrier, not once an application) | measure | −254,580 | 0 | 0 | −76.4 M (−$0.067) | none | none | CBT-04 |
| **L1 alone**: frozen goblins kept as words, perception's 8 scans over words | engineering | −1,059,973 | +3,255 | +1.0 M (+$0.001) | −318.0 M (−$0.280) | `load`, `store`, perception over words; the index kept for the call | **`load`'s contract with perception** (ENG-07) | ENG-07 |
| **L2** an application in place, by condition | engineering | −773,960 | 0 | 0 | −232.2 M (−$0.205) | one inlined function a condition kind | none | CBT-04's fix loop or CBT-05 |
| **L3** the executor: the guard once a tick and updated at every effect write, a carrier's goblins flushed once, entries with the sheets | engineering | −2,812,264 | 0 | 0 | −843.7 M (−$0.743) | CBT-05's design | none (`Sheets`, an in-call type, gains the entries) | CBT-05 |
| **L4 alone**: perception's one-pass selection on main's goblins | engineering | −1,502,900 | not measured | — | −450.9 M (−$0.397) | the selection | none | ENG-07 |
| L1 given L4 (L1 and L4 together less L4 alone) | engineering | −1,356,393 | +3,255 | +1.0 M (+$0.001) | −406.9 M (−$0.358) | as L1 | as L1 | ENG-07 |
| L1 and L4 together | engineering | −2,859,293 | not measured | — | −857.8 M (−$0.756) | both | as L1 | ENG-07 |
| D1 awake 8 → 6 | design | −1,446,286 | −127,866 | −38.4 M (−$0.034) | −433.9 M (−$0.382) | a constant | `MAX_AWAKE` | ENG-07; design/02, D-133, D-141 |
| D1 awake 8 → 4 | design | −2,843,212 | −255,732 | −76.7 M (−$0.068) | −853.0 M (−$0.751) | a constant | `MAX_AWAKE` | ENG-07; design/02, D-133, D-141 |
| D2 one application on the member a goblin carrier | design | −442,240 | 0 | 0 | −132.7 M (−$0.117) | a check in the executor | none | CBT-05; design/19 §5.14, §8 |
| D2′ a carrier's targets 7 → 3 (FX-35's bomb) | design | −1,095,780 | 0 | 0 | −328.7 M (−$0.290) | content | none | CNT-01; design/19 §9, FX-35 |
| D3 window 4 → 2 chunks, flood 15 → 10 layers | design | −390,467 | −145,847 | −43.8 M (−$0.039) | −117.1 M (−$0.103) | the window's constants | `MAX_GOBLINS` | ENG-07, LIB-05; design/18 |
| D4 20 ticks a batch instead of 10 (average case only: at the worst no batch holds 10 ticks) | design | not applicable | −212,473 | −63.7 M (−$0.056) | — | a constant | the batch's 40 M (ENG-01 §10.1) | ENG-07; design/02 |

How the E figures are made:
- **L3:** the executor's parts measured (above), assembled by the counts of a worst tick.
- **D1:** the costliest tick measured at 8, 6 and 4 awake (1,477,717; 1,090,071; 751,785), plus each
  goblin carrier fewer (2 applications at 55,280, its predicates 11,250, its guarded hit 322,816:
  444,626), plus each walker fewer (the map library's 8 walkers, (1,106,666 − 64,234 − 364,878) / 8 =
  84,694, C). The representative figures are measured (636,067; 508,201; 380,335). **With 4 awake, a
  7-target bomb reaches 3 frozen goblins** (fix loop 1, note 10): each is a hook's frozen write
  (477,720 with L1, 674,470 without) where an awake target costs 273,945, about +611,325 with L1 (E)
  if the bomb keeps its 7 targets; D2′ (3 targets) removes the interaction.
- **D2:** 8 applications fewer at 55,280 (4 fewer at 4 awake). **D2′:** 4 targets fewer at 273,945
  each, measured as the 7- and 3-target bombs' difference; the bomb's fixed part (one rebuild, the
  member's round trip, the kit's read), 113,705, stays.
- **D3:** 20 goblins fewer in the call at 15,200 a call (lever 1's slope), half the 4-chunk assembly
  (64,234, C), 5 flood layers at 22,746 (C), 20 candidates fewer at the single pass's 10,711 a key.
- **D4:** the representative's per-call part (CBT-02d's 184,105 and 240,840 a tick) over 20 ticks.
  **Not applicable at the worst**: no batch holds even 10 worst ticks (below).

## The worst tick, everything counted

| Per worst tick, inside a batch of 10 | As it stands | With L1–L4 |
|---|---:|---:|
| The brief's basis (CBT-02d's 3,447,872, C; CBT-04's line re-measured, 2,114,010; CBT-03a's 693,750, C) | 6,255,632 (4.26×); 6,510,212 cited | 4,737,519 (3.22×) |
| CBT-05's executor (E) | 6,768,568 | 3,956,304 |
| ENG-07's perception over 100 candidates (worst of four states) | 4,663,690 | 3,729,050 |
| The map library (LIB-05 M1-T9b, C) | 1,106,666 | 1,106,666 |
| The hooks' writes to 6 frozen goblins (ENG-01 §9.2's count, C; each D) | 4,046,820 | 2,866,320 |
| **Everything counted** | **22,841,376 (15.54×)** | **16,395,859 (11.16×)** |

- **With L2, L3 and L4 only** (no frozen interface changed): 17,752,252 (12.08×).
- **With the design levers on top** (4 awake, one application on the member a carrier, 3 targets a
  carrier, the smaller window and flood; D2 counted at 4 carriers; D4 excluded): **11,845,280 a
  worst tick (8.06×), E.** No combination priced here brings the worst tick to 1.47 M.

**A worst batch against 40 M** (fix loop 1, finding 2; corrected in fix loop 2). The per-call part
is paid once a batch:

| | Per-call part | A worst tick without it | Worst ticks a 40 M batch holds |
|---|---:|---:|---:|
| As it stands (load and store, the call, the content) | 19,675,090 | 20,873,867 | **0** |
| After L1–L4 (L1's load and store, the call, the content, L3's 118 entries decoded once a call: 3,648,560) | 15,882,120 | 14,807,647 | **1** (2 would cost 49.93 M) |
| With the design levers too (D3's 20 goblins fewer in the call, 304,000, per-call) | 15,578,120 | 10,287,468 | **1** (2 would cost 40.59 M) |

As it stands, the executor decodes its entries at each use, so they are per tick, not per call.

The batch's own writes are ENG-01 §10.1's 64 keys, both ways (E, each branch less its 10 ticks at
4.29 M): **initialised, 4,436,950** (47,336,950), and **cold, 5,637,162** (48,537,162, +1,200,212).
**The counts are the same with either**. The table's sums are initialised; cold adds 1,200,212 to
each.

The batch-of-10 basis of every per-tick figure above is not reachable at the worst; it is the basis
CBT-02d and the brief price ticks on.

## Recommendation

**Engineering levers, for the project manager, in this order of gain on everything counted:**
1. **L3, CBT-05's executor** (−2.81 M, E): brief CBT-05 with the member's guard read once a tick and
   **updated whenever the executor holds, spends or ends an effect**, a carrier's goblins written in
   one rebuild, and the skills' entries decoded once a call into the sheets. Without them CBT-05 adds
   about 6.77 M a worst tick. No frozen interface changes: `Sheets`, an in-call type, gains the
   entries.
2. **L4, perception's one-pass selection** (−1.50 M), on main's representation: ENG-07's step 0. **No
   frozen interface changes.**
3. **L2, applications in place by condition** (−0.77 M), and CBT-04's line corrected to 2,114,010
   (−0.25 M, a measure): CBT-04's fix loop or CBT-05. No frozen interface changes.
4. **L1, the frozen goblins kept as words: −1.36 M once L4 is in, of which −1.18 M is the 6 hooks'
   writes to frozen goblins a worst tick; −0.18 M without them.** **The only lever that changes a
   frozen interface** (`load`'s contract with perception, ENG-07). Alone it saves −1.06 M with the
   hooks and costs +0.12 M without them. It is worth deciding after ENG-07 says how many frozen
   goblins its hooks write in a tick.

L2, L3 and L4 together take everything counted from 22.84 M to 17.75 M (12.08×); with L1, 16.40 M
(11.16×).

**What remains for the owner's design levers.** After the engineering levers the worst tick is about
14.9 M above its target; the design levers priced here close about 4.6 M of it (to about 11.8 M,
8.06×, E). **The worst tick will not reach 1.47 M by these levers, and a 40 M batch holds 1 worst tick
after the engineering levers, and still 1 with the design levers** (2 would cost 40.59 M). On the representative tick the engineering
levers save almost nothing (it has no hit, no application, no frozen goblin); the design levers save
0.13–0.26 M (D1), 0.15 M (D3) and, in the average case, 0.21 M (D4). S1 rests on the average tick,
which nobody has yet measured with the rules: a representative fight tick is ENG-07's to define, and
S1's gap should be judged on it, with SPK-12 (client-side proving) beside it.

## Not measured

- Perception on the representative tick (8 candidates).
- A goblin's application split by condition (its in-place figure, 47,900, is its knock-down's path).
- A lighter awake goblin value, and step 2's writes kept pending: named under lever 3.
- The library call's cost per goblin in the call (its words through calldata): D3 counts only load
  and store.
- The guard's update when an effect is held or ends (only the block's spend is implemented and
  checked); its cost is a field write, against the 228,110 of reading the guard again.

## History

- **2026-10-01, the lot** (`92779d3`): the levers measured, the table, the recommendation.
- **2026-10-01, fix loop 1** (Claude-side cost and method audit, `[Opus 5.5]`, FAIL: one major, four
  minors, five notes):
  1. major: L1 and L4 priced alone, together and each given the other, everything counted;
     perception measured on main's representation with one pass (`src/perception.cairo`, main's
     `TickTrait::awake` copied verbatim); L4 needs no L1 and no frozen interface; the order of the
     recommendation changed (L4 before L1; L1 the only frozen-interface change);
  2. the batch: the per-call part once a batch and ENG-01 §10.1's writes: 1 worst tick a batch after
     L1–L4, 2 with the design levers (corrected to 1 in fix loop 2); D4 out of every worst-tick
     combination;
  3. the guard updated at every effect write; a blocked hit spends its charge; the two-hit test;
  4. perception's four states on every representation, the worst of each; main's 4,663,690
     (ENG-01: 4,663,510);
  5. the hooks' 6 writes to frozen goblins counted in everything counted;
  6–10. the stale 3,264,270 gone (the table now reads from `levers-output.md`); D2′'s per-target part
     measured apart from its fixed part; the goblin's alternatives checked at three values and dead,
     the one-pass selection's flags and replaced case checked; `cbt04.cairo`'s header names what it
     copied; D1's interaction with a 7-target bomb stated.
- **2026-10-01, fix loop 2** (Claude-side re-audit at `9517865`: every fix loop 1 figure confirmed,
  FAIL on one major):
  1. major: L3's 118 entries (3,648,560) and D3's 20 goblins fewer in the call (304,000) are per-call
     costs. The batch counts are recomputed: 0 as it stands, 1 after L1–L4, **1 (not 2)** with the
     design levers;
  2. L3's frozen-interface cell now reads "none (`Sheets`, an in-call type, gains the entries)", so L1
     is the only lever that changes a frozen interface;
  3. the batch's writes are given both ways, initialised (4,436,950) and cold (5,637,162). The counts
     are the same with either.

  No code or test changed; every figure comes from fix loop 1's committed clean runs.
