# CBT-02b: the flattening's wiring into `Hub`, and the tick's proved bound

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from CBT-02b ([#196](https://github.com/bal7hazar/grimworld/pull/196), report *Summary* and *Cost*; its audits through Nexus are running) |
| To be answered by | `[Fable 5.1]` project manager: 1 is D-160's restriction against D-158's targets and ENG-01 §1.3; 2 is the expedition's budget (D-161) |
| Needed by | 1: before any production snapshot (D-160); 2: ENG-07 (the batch's weight and gas bound) |

## 1. Wiring the snapshot's flattening into `Hub` (D-160) does not fit as built

CBT-02b wired it (`set_build` flattens the build, so DS-2's floors and design/20's counts refuse there;
`enter` builds its snapshot through it), measured it, then **reverted it** (`5c437de`; `0607c1d` restores it):

| | Before | With the wiring | Limit |
|---|---:|---:|---:|
| `Hub`'s class | 42.8 % | **79.8 %** | 50 % (ENG-01 §1.3; CI fails) |
| `set_build`, worst case, a transaction | ~3.8 M | **~18.5 M** | 3.8 M (D-158) |
| `enter`, worst case, a transaction (estimate) | 5.38 M | **~20.6 M** | 5.25 M (D-158) |

About 14.5 M of each is **the flattening's capacity checks, quadratic in the passives** (30 passives: each
statistic a pass over them). Moving the flattening into a library class needs its class hash in `Hub`'s
configuration (`set_contracts`, a frozen signature).

| Option | Effect |
|---|---|
| (a) **Check per-source bounds once, at registration** (CAIRO §1): design/20's per-source bounds are properties of content records (a modifier, a rune, a passive): `Registry.set_record` refuses a record past its bound, and `set_build` then only sums the build's sources, a linear pass, with the totals' checks (the floors, the counts) | removes the quadratic part; no frozen interface changes if the checks go in the registry's validators (ENG-03's `RegistryAssert`); the admin pays once per record |
| (b) The flattening as a library class, its hash in `Hub`'s configuration | fixes the class size, not the cost; `set_contracts` changes (a frozen signature) |
| (c) Wire it as built | fails CI's class limit and D-158 four times over |

**Recommendation: (a)**, as a follow-up **CBT-02c** (Opus 5.5): per-record checks in the registry, the
linear flattening wired into `set_build` and `enter`, measured against D-158; (b) only if `Hub` still
passes 50 % after it. D-160's rule holds meanwhile: no production snapshot (nothing is deployed).

## 2. The tick's worst case is proved, and it is 10 times the average target

| Per tick inside a batch of 10 | Representative | Proved upper bound |
|---|---:|---:|
| The tick's share (pipeline, load, store, call, content) | 1,104,546 (75.2 % of 1,469,435) | 15,148,134 (10.3 ×) |

S1 is an average and uses the representative figure (still above target once the rest of `play` is added:
the map library's 1.06–1.11 M a worst tick, the executor, the AI, the writes). **The worst case binds the
batch's gas bound instead**: ten worst ticks cannot fit a transaction, so ENG-07 must derive a batch's
weight from this bound, not from design/02's 40 M. The bound's make-up: 8 rebuilds of the 100-goblin array
(~4.8 M), load's lookups (~5.5 M), step 3's rebuild (1.3 M).

| Lever (CBT-02b's report) | Effect | Changes |
|---|---|---|
| the goblins' array as hot fields apart (D-161's (a) in full) | most of the 4.8 M rebuilds | `World`'s representation (CBT-02's tests rewritten) |
| an index into the content instead of lookups at every load | most of the 5.5 M | the content's in-memory form |
| a smaller goblin array in the window (100 today) | every array term, linearly | the window's rule (a design lever) |

**Recommendation:** merge CBT-02b (levers and proved bound) once its audits and review pass; the two
remaining levers as **CBT-02d**, before ENG-07; ENG-07 then sets the batch's weight from the measured bound,
and (e), the design levers, R-2 after it (D-161).

## Decision

Pending.
