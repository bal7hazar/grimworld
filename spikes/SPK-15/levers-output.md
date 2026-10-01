## The measured pairs used

- load and store, main / L1 (bound words): 10,570,470 / 3,128,940
- load and store, main / L1 (representative words): 1,292,290 / 1,324,840
- a frozen goblin a hook touches, main / L1: 674,470 / 477,720
- the content's index: 557,210
- the selection alone, 8 scans / one pass: 2,562,050 / 1,071,130
- member: CBT-04 / source given / kit read / in place / knock / 1–4 / 1–3: 108,100 / 91,000 / 19,020 / 57,180 / 55,280 / 31,940 / 24,200
- goblin: CBT-04 / in place: 76,820 / 47,900
- a goblin's hit end to end / guarded / the guard: 541,656 / 322,816 / 228,110
- a bomb on 7, each / flushed; on 3, flushed: 2,479,950 / 2,031,320; 935,540
- an entry decoded: 30,920
- the costliest tick at 8 / 6 / 4 / 0 awake: 1,477,717 / 1,090,071 / 751,785 / 207,133
- the representative tick at 8 / 6 / 4: 636,067 / 508,201 / 380,335
- load and store at 100 / 60 / 40 goblins, main: 10,570,650 / 6,713,050 / 4,784,250
- the same, L1: 3,129,120 / 2,521,120 / 2,217,120

## Perception over 100 candidates, by state (D)

| Representation | formed | kept_end | kept_start | replaced | Worst |
|---|---:|---:|---:|---:|---:|
| main | 4,596,450 | 4,656,050 | 4,663,690 | 4,655,170 | **4,663,690** |
| decoded_scan | 4,593,150 | 4,652,750 | 4,660,390 | 4,651,870 | **4,660,390** |
| decoded_single | 3,101,190 | 3,160,790 | 2,582,390 | 3,159,910 | **3,160,790** |
| lazy_scan | 5,397,410 | 5,063,770 | 4,972,970 | 5,528,370 | **5,528,370** |
| lazy_single | 3,567,850 | 3,264,450 | 2,587,610 | 3,729,050 | **3,729,050** |

Main's worst taken as 4,663,690 (measured 4,663,690; ENG-01 4,663,510).

## Everything counted, per worst tick (as it stands)

- the brief's basis, CBT-04 re-measured: 6,255,632 (4.26x)
- CBT-05's executor, naive (E): 6,768,568 (4.61x)
- ENG-07's perception: 4,663,690 (3.17x)
- the map library (C): 1,106,666 (0.75x)
- the hooks' writes to frozen goblins, 6 (C count, D each): 4,046,820 (2.75x)
- **everything counted**: 22,841,376 (15.54x)

## Engineering levers, each priced on everything counted

- CBT-04's line re-measured: 2,368,590 -> 2,114,010 (−254,580), a measure
- L1 alone: load and store −744,153, perception +864,680, hooks −1,180,500: **−1,059,973** (without the hooks +120,527)
- L2 alone: **−773,960**
- L3 alone: naive 6,768,568 -> levered 3,956,304: **−2,812,264** (E)
- L4 alone: perception 4,663,690 -> 3,160,790: **−1,502,900**
- L1 and L4 together: **−2,859,293**; L1 given L4 −1,356,393 (without the hooks −175,893); L4 given L1 −1,799,320
- All four: 22,841,376 -> 16,395,859 (11.16x)
- The brief's basis alone: 6,510,212 cited, 6,255,632 re-measured (4.26x) -> 4,737,519 with L1's load and store and L2 (3.22x)

## Design levers (per worst tick, after the engineering levers)

- awake 8 -> 6: tick −387,646 (D), carriers −889,252 (E), walkers −169,388 (E): **−1,446,286**
- awake 8 -> 4: tick −725,932 (D), carriers −1,778,504 (E), walkers −338,776 (E): **−2,843,212**
- one application on the member a goblin carrier (16 -> 8): −442,240 (E); at 4 awake (8 -> 4) −221,120
- a carrier's targets 7 -> 3: 273,945 a target (D: the 7- and 3-target bombs), fixed part 113,705: **−1,095,780**
- window 4 -> 2 chunks, flood 15 -> 10 layers: call −30,400 (L1; main −192,880), assembly −32,117 (E), flood −113,730, perception −214,220 (E): **−390,467**
- 4 awake, one application a carrier, 3 targets, the smaller window and flood (D4 excluded: no batch of 10 holds a worst tick): 11,845,280 (8.06x) (E)

## A worst batch against 40 M (per-call part once a batch)

- the entries decoded once a call: 118 × 30,920 = 3,648,560 (per-call, with L3)
- the batch's writes (E): initialised 4,436,950, cold 5,637,162
- as it stands: a tick 20,873,867 without the per-call part 19,675,090: worst ticks a 40 M batch holds: initialised **0** (24,112,040; 44,985,907 for 1); cold **0** (25,312,252; 46,186,119 for 1)
- after L1–L4: a tick 14,807,647 without the per-call part 15,882,120: worst ticks a 40 M batch holds: initialised **1** (35,126,717; 49,934,364 for 2); cold **1** (36,326,929; 51,134,576 for 2)
- and the design levers: a tick 10,287,468 without the per-call part 15,578,120: worst ticks a 40 M batch holds: initialised **1** (30,302,538; 40,590,006 for 2); cold **1** (31,502,750; 41,790,218 for 2)

## The table

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
