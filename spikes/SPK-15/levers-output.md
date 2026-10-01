## The measured pairs used

- load and store, main / lazy (bound words): 10,570,470 / 3,128,940
- load and store, main / lazy (representative words): 1,292,290 / 1,324,840
- a frozen goblin touched, main / lazy: 674,470 / 477,720
- the content's index: 557,210
- perception over 100, main / lazy single pass (worst of formed, kept): 4,657,300 / 3,566,290
- the selection alone, 8 scans / one pass: 2,562,050 / 1,071,130
- member: CBT-04 / source given / kit read / in place / knock / 1–4 / 1–3: 108,100 / 91,000 / 19,020 / 57,180 / 55,280 / 31,940 / 24,200
- goblin: CBT-04 / in place: 76,820 / 47,900
- a goblin's hit end to end / guarded / the guard: 475,576 / 254,796 / 223,390
- a bomb on 7, each / flushed: 2,479,950 / 2,031,320
- an entry decoded: 30,920
- the costliest tick at 8 / 6 / 4 / 0 awake: 1,477,717 / 1,090,071 / 751,785 / 207,133
- load and store at 100 / 60 / 40 goblins, main: 10,570,650 / 6,713,050 / 4,784,250
- the same, lazy: 3,129,120 / 2,521,120 / 2,217,120

## Engineering levers (per tick, worst inside a batch of 10)

- CBT-04's line re-measured: 2,368,590 -> 2,114,010 (−254,580)
- L1 frozen goblins as words: −744,153; representative 3,255 (a cost); S1 ceiling 223.2 M ($0.197)
- L2 applications in place, by condition: −773,960; S1 ceiling 232.2 M ($0.205)
- L3 the executor: naive 6,239,928 (E) -> levered 3,407,424 (E): −2,832,504; S1 ceiling 849.8 M ($0.749)
- L4 perception: 4,657,300 -> 3,566,290: −1,091,010; S1 ceiling 327.3 M ($0.288)

- The brief's basis (CBT-02d + CBT-04 + CBT-03a): 6,510,212 cited; 6,255,632 re-measured (4.26x) -> 4,737,519 with L1 and L2 (3.22x)
- Everything counted (+ executor, perception, the map): 18,259,526 (12.43x) -> 12,817,899 (8.72x)

## Design levers (per tick, after the engineering levers)

- awake 8 -> 6: tick −387,646 (D), carriers −753,212 (E), walkers −169,388 (E): −1,310,246; S1 ceiling 393.1 M ($0.346)
- awake 8 -> 4: tick −725,932 (D), carriers −1,506,424 (E), walkers −338,776 (E): −2,571,132; S1 ceiling 771.3 M ($0.680)
- one application on the member a goblin carrier (16 -> 8): −442,240 (E); S1 ceiling 132.7 M ($0.117)
- a carrier's targets 7 -> 3 (FX-35's bomb): −1,034,204 (E, 258,551 a target); S1 ceiling 310.3 M ($0.273)
- window 4 -> 2 chunks and flood 15 -> 10 layers: 20 goblins fewer in the call (−30,400 lazy, −192,880 main), assembly −32,117 (E), flood −113,730, perception −214,220 (E): −390,467; S1 ceiling 117.1 M ($0.103)
- 5 ticks a batch: the per-call part 2,446,712 a tick (+1,223,356 against 10)
- 8 ticks a batch: the per-call part 1,529,195 a tick (+305,839 against 10)
- 10 ticks a batch: the per-call part 1,223,356 a tick (−0 against 10)
- 20 ticks a batch: the per-call part 611,678 a tick (−611,678 against 10)

## The table

| Lever | Kind | Worst tick | Representative tick | S1 (representative × 300) | S1 if every tick were the worst | Cost in code | Frozen interfaces | Lots |
|---|---|---:|---:|---:|---:|---|---|---|
| CBT-04's line re-measured (not a lever: the member's kit read once a carrier, not once an application) | measure | −254,580 | −0 | −0.0 M ($0.000) | −76.4 M ($0.067) | none | none | CBT-04 (its ENG-01 row) |
| L1 frozen goblins kept as words | engineering | −744,153 | +3,255 | +1.0 M ($0.001) | −223.2 M ($0.197) | `load`/`store` and perception over words; the index kept for the call | `load`'s contract with perception (ENG-07); no stored layout | ENG-07 (with perception) |
| L2 an application in place, by condition | engineering | −773,960 | −0 | −0.0 M ($0.000) | −232.2 M ($0.205) | one inlined function a condition kind; the executor dispatches | none (CBT-04's results kept) | CBT-04 fix or CBT-05 |
| L3 the executor: the member's guard once a tick, a carrier's goblins flushed once, entries with the sheets | engineering | −2,832,504 | −0 | −0.0 M ($0.000) | −849.8 M ($0.749) | CBT-05's design; entries decoded into the sheets | the call's content (`Sheets` grows by the entries) | CBT-05 |
| L4 perception: one-pass selection, AI states kept at load | engineering | −1,091,010 | not measured | — | −327.3 M ($0.288) | the selection and the AI states (with L1) | none | ENG-07 |
| D1 awake 8 -> 6 (design/02, D-133, D-141) | design | −1,310,246 | −127,866 | −38.4 M ($0.034) | −393.1 M ($0.346) | a constant | `MAX_AWAKE` | ENG-07; design/02 |
| D1 awake 8 -> 4 (design/02, D-133, D-141) | design | −2,571,132 | −255,732 | −76.7 M ($0.068) | −771.3 M ($0.680) | a constant | `MAX_AWAKE` | ENG-07; design/02 |
| D2 one application on the member a goblin carrier (design/19 §5.14, §8) | design | −442,240 | −0 | −0.0 M ($0.000) | −132.7 M ($0.117) | a check in the executor | none | CBT-05; design/19 |
| D2' a carrier's targets 7 -> 3 (FX-35's bomb, `DISC_1`) | design | −1,034,204 | −0 | −0.0 M ($0.000) | −310.3 M ($0.273) | content (a smaller shape) | none | CNT-01; design/19 |
| D3 window 4 -> 2 chunks, flood 15 -> 10 layers (design/18) | design | −390,467 | −145,847 | −43.8 M ($0.039) | −117.1 M ($0.103) | the window's constants | ENG-01's goblin bound (`MAX_GOBLINS`) | ENG-07, LIB-05; design/18 |
| D4 20 ticks a batch instead of 10 (design/02's weight) | design | −611,678 | −212,473 | −63.7 M ($0.056) | −183.5 M ($0.162) | a constant | the batch's 40 M (ENG-01 §10.1) | ENG-07; design/02 |
