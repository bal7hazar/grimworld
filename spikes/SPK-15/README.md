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
  (`snforge-test-output-1.txt`, `-2.txt`). Every one of the 61 pairs is equal to the unit in both
  (`pairs.txt`). Build-to-build drift seen on the way: the build before the last six tests were added
  measured the pairs that read words, write the world or build the index 1,060 to 1,460 higher (main's
  load and store 10,571,730 against 10,570,470); the figures here are the final build's.
- **Checks.** Main's figures reproduce: CBT-04's member application 108,100 and goblin application
  76,820 to the unit; main's load and store at the bound 10,570,470 (CBT-02d: 10,570,470); the
  representative tick 636,067 (CBT-02d: 636,067); the costliest tick at 8 awake 1,477,717 (CBT-02d:
  1,475,797, +1,920, the drift above); perception's selection 4,597,710 from no set (CBT-02d:
  4,596,270). Every alternative is checked against the code it replaces (`test_alternatives_match_*`,
  `test_awake_*_matches_main`, `test_selection_agrees`, `test_executor_*_agree`).
- **Sources copied** (the branches are not merged; never edited): `src/cbt04.cairo` from
  `feat/cbt-04-conditions` at `b5f4069` (`types/infliction.cairo`, the member's and goblin's
  `apply` and predicates, `TickMathTrait::held`, `move_ticks`); `src/cbt03a.cairo` from
  `feat/cbt-03a-hit` at `36bf2ba` (`types/hit.cairo` above its tests, and `Arc`). Their bodies are
  unchanged but for `scarb fmt` and the `use` lines. `tests/fixtures.cairo` copies main's
  `contracts/logic/tests/test_tick.cairo` fixtures at `d4b5cdc`.
- **Counts of a worst tick** are CBT-04's and CBT-03a's (ENG-01 §9.2): 8 goblin carriers (a hit and
  2 applications on the member each), the member's one carrier (7 goblins hit, 7 applications), 9
  predicate sets; a goblin carrier reads at most 4 entries (its skill's 3, its held effect's 1), the
  member's at most 7.
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
| A frozen goblin a hook touches (read, written back) | 674,470 | 477,720 | 196,750 each (§9.2: ≤ 6 an action) |
| The representative words (8 goblins, all awake) | 1,292,290 | 1,324,840 | −32,550 (a cost: 3,255 a tick) |

- `lazy_load` decodes the members and the awake set only, and keeps each goblin's AI state (one
  field of its words) for perception; `lazy_store` copies every frozen word unchanged.
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
| A goblin's hit on the member: the inputs gathered (4 effect slots decoded) · gathered with the member's guard given · the guard | 245,596 · 23,716 · 223,390 |
| A goblin's weapon hit end to end (read, gather, CBT-03a's `resolve`, outcome, write back) · the same with the guard read before | 475,576 · 254,796 |
| A bomb on 7 awake goblins (hit, `CONDITION`, kill), each goblin written after its own · the 7 written together (`flush`) | 2,479,950 · 2,031,320 |
| A `CONDITION` on the member, read and written · on an awake goblin | 125,010 · 191,770 |
| An entry decoded from its 97 bits | 30,920 |

- **The executor as CBT-05 would write it naively (E):** 8 goblin hits at 475,576 less the hit
  (46,250), the bomb's 2,479,950 less its 7 hits and 7 applications and the kit, 39 entries decoded
  at 30,920: **6,239,928 a tick**, on top of every line above.
- **Levered (E):** the member's guard read once a tick (its defence terms change only when the
  executor holds, spends or ends an effect), a carrier's goblins written in one rebuild, the
  content's entries decoded once a call with the sheets (118 entries, 364,856 a tick):
  **3,407,424 a tick (−2,832,504)**. The guarded hit leaves the world the unguarded one leaves.
- **What dominates what remains:** writing an awake goblin back rebuilds the awake set's 8 goblins
  of 24 felts (114,670); a lighter value (its derived fields apart) and step 2's own writes kept
  pending to one rebuild (the bomb's flush saves 64,090 a goblin) are the next levers. Not measured.

### Lever 4 — perception and the content's index

- **Perception is not in the 6.51 M.** ENG-07's step 0 selects the awake set every tick: over 100
  candidates main's selection costs **4,657,300** (the set kept; 4,597,710 formed). Its 8 scans of
  the keys cost 2,562,050 of it; one pass costs 1,071,130 (`SelectionTrait::single`, the same set).
  With the frozen goblins' AI states kept at load (lever 1): **3,566,290** at worst (formed; kept
  3,264,270), **−1,091,010 a tick**.
- **The content's index** (once a call): 557,210, 55,721 a tick; it is inside load and store above.
  With lever 1 it serves the member and at most 8 goblins (and perception's wakings).

## The table

Per tick, inside a batch of 10. Each saving is against the line it acts on, after the levers above
it in the table (the design levers after all engineering levers).

| Lever | Kind | Worst tick | Representative tick | S1 (representative × 300) | S1 if every tick were the worst | Cost in code | Frozen interfaces | Lots |
|---|---|---:|---:|---:|---:|---|---|---|
| CBT-04's line re-measured (the member's kit read once a carrier, not once an application) | measure | −254,580 | 0 | 0 | −76.4 M ($0.067) | none | none | CBT-04 (its ENG-01 row) |
| **L1** frozen goblins kept as words | engineering | **−744,153** | +3,255 (a cost) | +1.0 M (+$0.001) | −223.2 M ($0.197) | `load`, `store`, perception over words; the index kept for the call | `load`'s contract with perception; no stored layout | ENG-07 |
| **L2** an application in place, by condition | engineering | **−773,960** | 0 | 0 | −232.2 M ($0.205) | one inlined function a condition kind | none (CBT-04's results kept) | CBT-04's fix loop or CBT-05 |
| **L3** the executor: the guard once a tick, a carrier's goblins flushed once, entries with the sheets | engineering | **−2,832,504** (E) | 0 | 0 | −849.8 M ($0.749) | CBT-05's design | the call's content (`Sheets` gains the entries) | CBT-05 |
| **L4** perception: one pass, AI states kept at load | engineering | **−1,091,010** | not measured | — | −327.3 M ($0.288) | the selection; the AI states (with L1) | none | ENG-07 |
| D1 awake 8 → 6 | design | −1,310,246 (E) | −127,866 | −38.4 M ($0.034) | −393.1 M ($0.346) | a constant | `MAX_AWAKE` | ENG-07; design/02, D-133, D-141 |
| D1 awake 8 → 4 | design | −2,571,132 (E) | −255,732 | −76.7 M ($0.068) | −771.3 M ($0.680) | a constant | `MAX_AWAKE` | ENG-07; design/02, D-133, D-141 |
| D2 one condition application on the member a goblin carrier | design | −442,240 (E) | 0 | 0 | −132.7 M ($0.117) | a check in the executor | none | CBT-05; design/19 §5.14, §8 |
| D2′ a carrier's targets 7 → 3 (FX-35's bomb) | design | −1,034,204 (E) | 0 | 0 | −310.3 M ($0.273) | content | none | CNT-01; design/19 §9, FX-35 |
| D3 window 4 → 2 chunks, flood 15 → 10 layers | design | −390,467 (E) | −145,847 (E) | −43.8 M ($0.039) | −117.1 M ($0.103) | the window's constants | `MAX_GOBLINS` (ENG-01 §9.2) | ENG-07, LIB-05; design/18 |
| D4 20 ticks a batch instead of 10 | design | −611,678 (E) | −212,473 (E) | −63.7 M ($0.056) | −183.5 M ($0.162) | a constant | the batch's 40 M (ENG-01 §10.1) | ENG-07; design/02 |

How the E figures are made:
- **D1:** the costliest tick measured at 8, 6 and 4 awake (1,477,717; 1,090,071; 751,785), plus each
  goblin carrier fewer (2 applications at 55,280, its predicates 11,250, its guarded hit 254,796:
  376,606), plus each walker fewer (the map library's 8 walkers, (1,106,666 − 64,234 − 364,878) / 8 =
  84,694, C). The representative figures are measured (636,067; 508,201; 380,335).
- **D2:** 8 applications fewer at 55,280. **D2′:** 4 targets fewer at 258,551 each (a hit 46,250, an
  application 47,900, the flushed bomb's own overhead a target 164,401).
- **D3:** 20 goblins fewer in the call at 15,200 a call (lever 1's slope), half the 4-chunk assembly
  (64,234, C), 5 flood layers at 22,746 (C), 20 candidates fewer at the single pass's 10,711 a key.
- **D4:** the per-call part (load and store with lever 1, 3,128,940; the call, 3,324,580, C; the
  content, 5,780,040, C) spread over 20 ticks instead of 10; the representative's from CBT-02d's
  184,105 and 240,840 a tick. Fewer ticks a batch raises every tick's share (5 ticks: +1,223,356);
  it is what keeps a worst batch under the transaction's 40 M, not a saving.

## The worst tick, everything counted

| Per tick, worst inside a batch of 10 | As it stands | With L1–L4 |
|---|---:|---:|
| CBT-02d's bound (the tick, load and store, the call, the content) | 3,447,872 (C) | 2,703,719 |
| CBT-04's line | 2,114,010 (re-measured; 2,368,590 cited) | 1,340,050 |
| CBT-03a's line | 693,750 (C) | 693,750 |
| **The brief's basis** | **6,255,632 (4.26×)**; 6,510,212 cited | **4,737,519 (3.22×)** |
| CBT-05's executor | 6,239,928 (E) | 3,407,424 (E) |
| ENG-07's perception over 100 candidates | 4,657,300 | 3,566,290 |
| The map library (LIB-05 M1-T9b) | 1,106,666 (C) | 1,106,666 |
| **Everything counted** | **18,259,526 (12.43×)** | **12,817,899 (8.72×)** |

With every design lever on top (4 awake, one application on the member a carrier, 3 targets a
carrier, the smaller window and flood, 20 ticks a batch; D2 counted at 4 carriers, −221,120):
**about 7.99 M a tick (5.44×), E.** No combination measured here brings the worst tick to 1.47 M.

## Recommendation

**Engineering levers, for the project manager — all four, in this order of gain:**
1. **L3, CBT-05's executor** (−2.83 M a worst tick): brief CBT-05 with the member's guard read once a
   tick, a carrier's goblins written in one rebuild, and the skills' entries decoded once a call into
   the sheets. Without them CBT-05 alone adds about 6.24 M a worst tick.
2. **L4, perception's one-pass selection** (−1.09 M; with L1's AI states): ENG-07's step 0.
3. **L2, applications in place by condition** (−0.77 M), and CBT-04's line corrected to 2,114,010
   (−0.25 M, a measure, not a change): CBT-04's fix loop or CBT-05.
4. **L1, the frozen goblins kept as words** (−0.74 M a worst tick, +3,255 on the representative):
   with ENG-07, since it changes `load`'s contract with perception.

Together they take the brief's basis from 6.26 M to 4.74 M (3.22×) and the tick with everything
counted from about 18.3 M to 12.8 M (8.72×).

**What remains for the owner's design levers.** At the worst tick the gap is about 11.3 M after the
engineering levers; the design levers priced here close about 4.8 M of it (to about 8.0 M, 5.44×).
**The worst tick will not reach 1.47 M by these levers.** On the representative tick they matter
less: the levers above save almost nothing there (the representative tick has no hit, no
application, and its 8 goblins are all awake), while the design levers save 0.13–0.26 M (D1), 0.15 M
(D3) and 0.21 M (D4). S1 rests on the average tick, which nobody has yet measured with the rules: a
representative fight tick (its hits, its applications, its perception) is ENG-07's to define, and
S1's gap should be judged on it, with SPK-12 (client-side proving) beside it. The worst tick matters
for the batch's 40 M: at 12.8 M a tick, a worst batch holds 3 ticks, not 10.

## Not measured

- Perception on the representative tick (8 candidates), and from a prior set wholly replaced (8
  goblins decoded and 8 encoded) with lever 1.
- A goblin's application split by condition (its in-place figure, 47,900, is its knock-down's path).
- A lighter awake goblin value, and step 2's writes kept pending: named under lever 3.
- The library call's cost per goblin in the call (its words through calldata): D3 counts only load
  and store.
