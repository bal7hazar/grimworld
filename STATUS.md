# Status — game track

**2026-10-03** — the track runs in herdr (orchestrator: herdr project `grimworld-game`); written by its bookkeeping thread. Earlier text is by `[Opus 5.5] Orchestrateur Grim World (jeu)` (2026-10-01 14:15 UTC).
The live state of the game track only. The programme, the decisions and what waits for the owner
are in [PROGRAMME.md](PROGRAMME.md), written by the project manager.

## 2026-10-07: ENG-05 merged

**Merged**: **ENG-05**, the chunk reveal engine ([#348](https://github.com/bal7hazar/grimworld/pull/348), `9ffd4ff`, 2026-10-07), with D-208 (a zone's quota hosts drawn once at entry, order-free), D-209 (`RevealLibrary` 50.18 % and `Instances` 50.35 %, under their exceptions until ENG-05b), D-210 (`HostsLibrary`, 8.03 %) and D-220 (the complement draw; the worst legal plan 98,153,254). Review t-0081 and randomness re-audit t-0082: PASS WITH FINDINGS. The D-144 ceilings of `enter` and `leave` are in ENG-01 §10.
**The dungeon residue** (re-audits t-0077 and t-0082): a modified client can force a floor's exit 1 chunk from the entry, up to N − 2 = 10 of 12 chunks closer at N = 12, bounded only by N. It blocks any non-test deployment until ENG-10b merges (the Overseer, 2026-10-07); ENG-10a (design) and ENG-10b (engine) remove it, ENG-10b's merge gate a randomness re-audit measuring it at zero. **ENG-10b built, PR open (2026-10-07)**: its zero-residue test on the real path measures 0 chunks and 0 tiles on 22 floors × 7 orders; its D-144 figures are with the project manager; the re-audit is the merge gate.
**Open**: ENG-08, authored zones' format (running, its first commit this bookkeeping). **Next** (the project manager, 2026-10-07): ENG-08, then ENG-08b, ENG-10a and ENG-10b, ahead of CBT-05b and ENG-07; ENG-05b before ENG-07 (D-209).

## 2026-10-03: the lots of 2026-10-02 and 2026-10-03 closed

**Merged** (reports archived in `docs/reports/`, PLAN rows done, CHANGELOG entries written): **CBT-05a**, the executor ([#334](https://github.com/bal7hazar/grimworld/pull/334), `f50c1fc`); **ENG-R1b part 1** ([#320](https://github.com/bal7hazar/grimworld/pull/320), `6887010`); **VEC-01** ([#294](https://github.com/bal7hazar/grimworld/pull/294), `d1f3e93`); **FND-11** Scarb 2.20.1 ([#293](https://github.com/bal7hazar/grimworld/pull/293), `a3c3268`), **FND-12** ([#291](https://github.com/bal7hazar/grimworld/pull/291), `f1a0b41`), **FND-13** ([#303](https://github.com/bal7hazar/grimworld/pull/303), `a97f4f0`), **FND-14** ([#305](https://github.com/bal7hazar/grimworld/pull/305), `33dc4e5`), **FND-15** ([#314](https://github.com/bal7hazar/grimworld/pull/314), `86c0322`), **FND-16** ([#312](https://github.com/bal7hazar/grimworld/pull/312), `8ab3949`), **FND-17** ([#327](https://github.com/bal7hazar/grimworld/pull/327), `aa5bcc1`), **FND-18** ([#322](https://github.com/bal7hazar/grimworld/pull/322), `93eb1b6`), **FND-19** `hexx` rc.2 ([#331](https://github.com/bal7hazar/grimworld/pull/331), `ffef058`), **FND-20** ([#350](https://github.com/bal7hazar/grimworld/pull/350), `ac10593`) and **FND-21** ([#352](https://github.com/bal7hazar/grimworld/pull/352), `53f1095`). The game is on Scarb 2.20.1 and `hexx` 0.1.0-rc.2.
**The tick** (ENG-01 §9.2, measured through `TickLibrary` at CBT-05a's head): the **worst measured tick is 45,999,941** (the member's activation and 8 goblin carriers, 115.0 % of 40 M, 4.18 % of the 1.1×10⁹ cap), accepted as a **one-tick batch** (D-207); **a goblin carrier through the class costs 4,090,351** (the owner's figure). The earlier figures (5,464,542, 3.72×, before the executor; 26,422,703, 17.98×, and 6,051,547, 4.12×, with it, understated) are history. A bomb tick (a `TILE`, `DISC_1` bomb and 8 goblins) may be ≈ 48.8 M (estimated): CBT-05b measures it. `ExecutorLibrary` 80,122 felts (97.81 % of D-200's 80,420, room 298), `TickLibrary` 61.04 % of 75 %.
**Open**: ENG-05 ([#348](https://github.com/bal7hazar/grimworld/pull/348)) is in its fix loop, then a short re-audit on the randomness lens and the delta review before it merges; ENG-R1b part 2 (`Registry`) is running. **Next**: CBT-05b (the action's costs and traps) after ENG-05 merges; ENG-07 after ENG-05; ENG-R1c after ENG-07; the small lots FND-23 and ENG-05b (FND-22, the tooling follow-ups, is in review), and CBT-05c to CBT-05e, are in PLAN.
**S1's running estimate**: ENG-05's entry and leave rises (`enter` +2.76 M to +3.52 M, `leave` +3.76 M to +6.73 M, accepted under D-144) and CBT-05a's tick go into S1's cost in ENG-07's lot (`cost.py`: R-2 is the whole expedition), not before.

## 2026-10-02: the track runs in herdr

**Merged on 2026-10-02**: **ENG-R1a** ([#221](https://github.com/bal7hazar/grimworld/pull/221), `d3ad22d`), **CBT-04** ([#228](https://github.com/bal7hazar/grimworld/pull/228), `81fbd98`),
**ENG-02** ([#246](https://github.com/bal7hazar/grimworld/pull/246), `04e12d6`) and **CBT-03a** ([#229](https://github.com/bal7hazar/grimworld/pull/229), `3b27b9f`); **SPK-15** ([#234](https://github.com/bal7hazar/grimworld/pull/234), `3ccc42e`) merged 2026-10-01. Their reports are
archived in `docs/reports/`, their PLAN rows done, their CHANGELOG entries written. `contracts/logic/vectors/check.py` runs in CI's
`contracts` job; it reads `window.jsonl` (ENG-02) and `hit.jsonl` (CBT-03a).
**The tick's share** (history, 2026-10-02: ENG-01 §9.2 with CBT-03a's hit and CBT-04's rules, before the executor): 5,464,542, 3.72× the 1,469,435 target; replaced by the measured tick above.
**Open**: CBT-05a (the executor, SPK-15's L3) is in progress; ENG-R1a's reading by the owner (ENG-R1b waits for it);
ENG-05 waits for `hexx` rc.2 (track LIB). **Next**: FND-11 (Scarb 2.20.1, the pin kept) after CBT-05a.
**Toolchain** (history, 2026-10-02): `scripts/setup-toolchain.sh` failed its `starknet-devnet` check on the VPS; fixed by FND-14 (devnet found through asdf).
**S1's running estimate**: unchanged (≈ 663 M); none of these lots moves it: ENG-R1a's +0.4 % to +3.8 % a call is on entrypoints S1 prices only
once an expedition, ENG-02 and CBT-04 add per-tick lines (ENG-01 §9.2) that S1 does not count, and SPK-15 says S1 should be judged on a
representative fight tick nobody has measured. The worst tick's levers are in SPK-15's report (6.26 M to 4.74 M with the engineering levers).

## Resumed 2026-09-30 (D-162: the standard roles of Nexus)

Audits and reviews go through `nexus audit` and `nexus review`; VPS implementers still through
`scripts/agent.sh`. **CBT-02** ([#182](https://github.com/bal7hazar/grimworld/pull/182)), **CBT-02b**
([#196](https://github.com/bal7hazar/grimworld/pull/196)) and **SPK-14** ([#202](https://github.com/bal7hazar/grimworld/pull/202))
and **CBT-02c** ([#206](https://github.com/bal7hazar/grimworld/pull/206), unwired, D-168) merged.
**CBT-02e** ([#212](https://github.com/bal7hazar/grimworld/pull/212)) merged: the snapshot is stored at
`set_build` (D-168). **CBT-02d** ([#211](https://github.com/bal7hazar/grimworld/pull/211)) merged: the worst tick
2.35× its target, carried to ENG-07. **CBT-02f** ([#219](https://github.com/bal7hazar/grimworld/pull/219), D-169) merged.
**ENG-R1a** ([#221](https://github.com/bal7hazar/grimworld/pull/221), `Hub` on the pattern, D-167) built, CI green;
its reading list sent to the project manager for the owner. **Codex is unavailable (quota) until
2026-10-04 13:36 UTC** (the jobs' error, 04:00): ENG-R1a's two audits ended `blocked_quota` and resume at
the reset; it merges only after them and Codex's review. Whether to run the quality lens on the Claude
side meanwhile is asked of the project manager. ENG-05 and
ENG-02 wait for `hexx` rc.1.
A nexus auditor resumed on a new revision could not fetch it (its sandbox refused `FETCH_HEAD`): a new
auditor per revision is started instead (reported to the owner here, as the standard asks).

## Where we are

**Phase 0 done** (the gate items are FND-07's). **Phase 1**: ENG-01, ENG-01b, ENG-02a, ENG-03, ENG-04,
ENG-06 done; ENG-05 and ENG-02 (line of sight) wait for the map library's release; ENG-07 after
ENG-05; ENG-R1 (D-143, D-147, D-167) after CBT-02d. **Pulled forward while the engine chain waits (D-150)**:
DES-04 (design/19), CBT-01 (the combat interfaces), CBT-08a (`set_build`), FND-08 (the funding
service), FND-09 (`with-node.sh` on macOS) all done; the tick's cost and the stored snapshot
(CBT-02 to CBT-02f) in progress (see *Orchestrators and agents*).

**S1's running estimate** (300 actions, D-129's $0.50; D-158 asks it kept here):

| Since | Change | S1 |
|---|---|---:|
| ENG-01 §10.2 | the design as frozen | 631.1 M ≈ **$0.556** |
| ENG-03 (D-145) | content reads, 36,000 a slot: about 10 records a batch × 30 batches | +30 M |
| ENG-06 (D-148) | `enter`, `leave`, `travel_back` as measured | +0.7 M |
| CBT-01, CBT-08a (D-158) | the larger snapshot and the belt's worst case, once an expedition | +2.2 M |
| CBT-02e (D-168) | `enter` copies the stored snapshot: 5,233,259 → 4,473,259 net, once an expedition | −0.76 M |
| CBT-02f (D-169) | `enter` checks the flattening epoch: +40,000, once an expedition | +0.04 M |
| **Now** | | **≈ 663 M ≈ $0.584** (E), before ENG-07 measures a tick inside a batch (CB-2, R-2) |

**The worst tick against S1** (D-171, replaced 2026-10-03): the worst tick **measured** is **45,999,941** (CBT-05a, a one-tick batch, D-207), **4,090,351** a goblin carrier through the class; the 1,469,435 an average tick may cost is what S1's $0.50 needs. The figures before the executor (≈ 6,510,212, 4.43×; 6.47 M, 4.4×; the representative tick before the rules' writes, 1,065,651) and 26,422,703 (17.98×) are history. SPK-15 measured the levers; D-207's levers (1) and (3) are in. ENG-07 derives the batch weight from the measured worst tick and re-measures the representative fight with 1-tick weapons first (a 10-tick batch of melee ticks near 369 M estimated reopens D-207 and R-2).

**A tick against its budget** (1,469,435 L2 gas on average, what S1 needs for $0.50): the map library's
part of a worst tick is **1.06–1.11 M** (window, flood at 15 layers, 8 walkers; LIB-05 M1-T9b), which
leaves about 0.4 M for the game's logic and storage. After CBT-02d, proved term by term: **≤ 1,480,363**
the pipeline, **≤ 3,447,872** a tick inside a batch (load, store, the call, content), **2.35×** the
target (CBT-02b: 10.3×); representative **1,065,651** (72.5 %). S1 above does not yet count this: it
rests on ENG-01's per-tick estimate. The next lever (frozen goblins kept as words, ~0.85 M a tick at
the bound) and the batch weight are ENG-07's. **The rules now landing raise it** (each lot's per-tick line, measured, at the MVP's content):
CBT-04 (#228, conditions) +2,368,590 (up to 16 applications on the member at 108,100 each, 7 on goblins);
CBT-03a (#229, one hit) +696,900 (15 hits at 46,460, with the bomb's 7, FX-35). With
both, the worst tick is about **6.47 M, 4.4×** the target, before CBT-05's executor writes the actors.

## What moved

| | |
|---|---|
| **CBT-05a** | [#334](https://github.com/bal7hazar/grimworld/pull/334): the executor in `ExecutorLibrary`; `ITickLibrary::run` gains the class hash and the board; D-179 (asleep no longer evades); worst tick measured 45,999,941, 4,090,351 a goblin carrier |
| **ENG-R1b part 1** | [#320](https://github.com/bal7hazar/grimworld/pull/320): `Instances` and `Market` through a store; typed slots (also `Hub`'s accounts, account_adventurers, packs); `create_adventurer` +0.12 %, `delete_adventurer` +0.26 % |
| **VEC-01** | [#294](https://github.com/bal7hazar/grimworld/pull/294): `fate.jsonl` (218) and `packing.jsonl` (520) in `check.py` |
| **FND-11 to FND-21** | Scarb 2.20.1; class artefacts; prepush and the hook; heavy lock; CI by changed paths; `hexx` rc.2; tests under 8 GB (`--max-threads 2`); the prepush diff base. No game result changed |
| **FND-24** | `hexx` 0.2.0 (L-M2) in place of rc.2; checksum `853a6f70…9b08`; vectors, tests, gas budgets and class sizes unchanged to the felt |
| **FND-24, indexer** | `indexer/emitter/Scarb.lock` (track CV's file, D-149) now pins `hexx` 0.2.0 (checksum `853a6f70…9b08`), regenerated by its own build; no source change, no event changed |
| **CBT-03a** | [#229](https://github.com/bal7hazar/grimworld/pull/229): `HitTrait::resolve`, one hit in 46,460; `hit.jsonl` (200 cases) in `check.py`; worst tick ≤ 5,464,542 with CBT-04 |
| **ENG-02** | [#246](https://github.com/bal7hazar/grimworld/pull/246): the geometry on `hexx` rc.1 (`types::window`); `window.jsonl`, `check.py` in CI |
| **CBT-04** | [#228](https://github.com/bal7hazar/grimworld/pull/228): the five conditions as tested rules; a cure on a dead goblin does nothing |
| **ENG-R1a** | [#221](https://github.com/bal7hazar/grimworld/pull/221): `Hub` through the store, one file a stored model; +0.4 % to +3.8 % a call; `Hub` 45.89 % |
| **SPK-15** | [#234](https://github.com/bal7hazar/grimworld/pull/234): the tick's levers measured; worst tick 6.26 M to 4.74 M (engineering), design levers priced |
| **CBT-02f** | [#219](https://github.com/bal7hazar/grimworld/pull/219): a snapshot stale only when a flattening input or its configuration changed; `enter` 4.51 M net |
| **CBT-02d** | [#211](https://github.com/bal7hazar/grimworld/pull/211): the awake set apart, the content through an index; worst tick ≤ 3.45 M inside a batch (2.35×), representative 1.07 M |
| **CBT-02e** | [#212](https://github.com/bal7hazar/grimworld/pull/212): `FlattenLibrary`; the snapshot stored at `set_build` (3 words), copied by `enter`; `enter` 4.47 M net (D-158 5.25 M); `Hub` 44.71 % |
| **CBT-02c** | [#206](https://github.com/bal7hazar/grimworld/pull/206): design/20's per-record bounds at registration; the flattening linear, unwired (`Hub` 61.15 % wired); CBT-02e stores the snapshot (D-168) |
| **CBT-02b** | [#196](https://github.com/bal7hazar/grimworld/pull/196): levers (a) and (b); the worst tick proved term by term, escalated not accepted; the Hub wiring moved to CBT-02c and CBT-02e (D-166, D-168) |
| **SPK-14** | [#202](https://github.com/bal7hazar/grimworld/pull/202): hexagonal chunks measured against 15 × 15; recommendation keep 15 × 15, the owner decides (D-165) |
| **CBT-08a** | [#170](https://github.com/bal7hazar/grimworld/pull/170): `set_build`; items carry their base's slot and hands; worst case about 3.80M, its target (D-158) |
| **CBT-01** | [#165](https://github.com/bal7hazar/grimworld/pull/165): design/19's data frozen as code; questions A–I decided (D-157) |
| **DES-04** | [#139](https://github.com/bal7hazar/grimworld/pull/139): design/19, the effect catalogue and resolution order (D-155) |
| **FND-08, FND-09** | [#141](https://github.com/bal7hazar/grimworld/pull/141) the funding service, caps decided (D-156); [#152](https://github.com/bal7hazar/grimworld/pull/152) `with-node.sh` on macOS |
| **Events** | **No event of ENG-01 has changed** (D-149: the indexer, lent to track CV, reads them) |
| **Launcher** | Reference `5d14d89`, frozen until the gate of Phase 0 (FND-07). Queues export the systemd user bus (a session's own D-Bus lost systemd at 15:02; nothing on the machine changed) |

## Orchestrators and agents

| Lot (PR) | Built by | Now | Gate (D-177) |
|---|---|---|---|
| CBT-05a the executor ([#334](https://github.com/bal7hazar/grimworld/pull/334)) | Opus 5.5 | merged 2026-10-03 (`f50c1fc`) | done (review and cost audit, D-207) |
| ENG-08 authored zones' format | Opus 5.5 | running (2026-10-07) | review; a short randomness lens on the draws at entry |
| ENG-05 chunk reveal ([#348](https://github.com/bal7hazar/grimworld/pull/348)) | Opus 5.5 | merged 2026-10-07 (`9ffd4ff`) | done (review t-0081, randomness re-audit t-0082) |
| ENG-R1b part 1 ([#320](https://github.com/bal7hazar/grimworld/pull/320)) | Opus 5.5 | merged 2026-10-03 (`6887010`); part 2 (`Registry`) running | done |
| ENG-R1a `Hub` on the pattern ([#221](https://github.com/bal7hazar/grimworld/pull/221)) | Opus 5.5 | merged 2026-10-02 (`d3ad22d`); the owner's reading pending | done |
| CBT-03a one hit ([#229](https://github.com/bal7hazar/grimworld/pull/229)) | Opus 5.5 | merged 2026-10-02 (`3b27b9f`) | done |
| ENG-02 geometry on `hexx` rc.1 ([#246](https://github.com/bal7hazar/grimworld/pull/246)) | Opus 5.5 | merged 2026-10-02 (`04e12d6`) | done |
| CBT-04 conditions ([#228](https://github.com/bal7hazar/grimworld/pull/228)) | Opus 5.5 | merged 2026-10-02 (`81fbd98`) | done |
| SPK-15 tick cost levers ([#234](https://github.com/bal7hazar/grimworld/pull/234)) | Opus 5.5 | merged 2026-10-01 (`3ccc42e`) | done |

**D-177 (owner, 2026-10-01)**: the review is the routine gate; an audit is the exception. **Audits
stopped: 0 queued or running** (the nine Codex audits had ended `blocked_quota`, the nine Claude Sonnet runs
had finished: both stay in the record as additions); **8 planned Opus audits dropped** (CBT-04, CBT-03a and
ENG-02 two each, SPK-15 one, ENG-R1a's security and cost). Merge order: ENG-R1a, CBT-04, CBT-03a, ENG-02,
SPK-15; then CBT-05a. Then FND-10 (one deterministic build, D-176) on a free slot. ENG-R1b waits for the
owner's reading of ENG-R1a; ENG-05 for `hexx` rc.2.

Budget: slots in `~/orchestrator/slots` (`scripts/agent.sh slots`), 3 in total, game 2.

## Next

ENG-05 merged (2026-10-07). ENG-08 running; then ENG-08b, ENG-10a and ENG-10b, ahead of CBT-05b (the action's costs and traps) and ENG-07; ENG-05b before ENG-07 (D-209); ENG-R1b part 2 (`Registry`) running; ENG-R1c after ENG-07. The owner's reading of ENG-R1a (D-167) is done.

## Decisions needed

CBT-05b's, ruled (D-222 and its amendment, the project manager, 2026-10-07): the action phase is `TickLibrary`'s `act` (at most 88 %); a trap's trigger is `TrapLibrary` (at most 78 %), wired into `Instances`; the 286 rises and the bomb through `act`, 45,968,815, accepted; a later shrink of both classes after ENG-07 (PLAN CBT-05g). The two attribute mappings go to CBT-05f (the orchestrator).

None open otherwise. Answered since 2026-09-29: D-141 to D-168.

## Build notes (D-154)

Scarb 2.19.4 builds of the same sources can differ in gas (+0.2 to +1.3 %) and Sierra size: a gas
budget that flakes in CI is recorded here with its run ids, not raised.

| When | What | Where |
|---|---|---|
| 2026-09-29, CBT-08a | `set_build`'s belt case on the local node measured +160,000 on an unchanged path between two runs | [report](docs/reports/CBT-08a-set-build.md), fix loop 1 |
| 2026-10-04, ENG-05 (PR #348) | `test_reveal_cost::test_cost_hosts_direct` and `test_cost_hosts_library_call` (`HostsLibrary`, D-210) read 210,194 / 358,834, then 210,094 / 358,734, so their budgets failed `gas_budgets.py --check` and the two were removed at `1d1e38e`. **Not a determinism fault**: the input is identical (a constant seed and plan, no address) and the figure is the same at every run of the same source; the `#[available_gas(...)]` attribute itself lowers the measure by exactly 100 (with it 210,094 / 358,734, three runs; without it 210,194 / 358,834, two runs). Set a budget from a run with the attribute in place. The same on `test_quota_order_free` (102,518,124 without, 102,518,024 with). | `snforge test --max-threads 2 test_cost_hosts` in `contracts/logic` at `ab7017a`'s test file, with and without the attribute, 2026-10-04 |

## Launcher: for its next change (not before a finding or a task needs one)

L-1 and L-2 of the previous status were done by #58 and #60.

| # | What | Source |
|---|---|---|
| L-3 | Moved to PLAN FND-07 (at the gate of Phase 0) | |

## Blocked

| What | By |
|---|---|
| SPK-6 | Real phones: the owner runs the protocol the orchestrator writes |
| Mainnet | An explicit go from the owner, each time (D-116) |

## Open questions from wave 1 (not blocking)

| # | Question | From | For |
|---|---|---|---|
| ART-1 | **Answered by the owner** (D-146 corrected, #137): the pack's hand-drawn units keep their height; only the generated goblin sheets are reduced (runt about 67–70 px, shaman about 87, hobgoblin about 119), final sizes by eye on CLI-03a; track CV, ART-02 | ART-00 | — |
| ART-2 | Slinger placeholder: the Torch Goblin stands in (the pack's slinger is a gnome) | ART-00 | Owner, at the first commission (ART-01) |
| TC-1 | `CONTEXT.md` §4 and `docs/CAIRO.md` should name Cairo 2.13 / Scarb 2.13.1 / snforge 0.51.2; ADR-0001 option B and ADR-0003's indexer consequence are confirmed by SPK-5 (Slot retired) | SPK-5 | Project manager (documents it owns) |

## MVP and version 1

The MVP is a test version: burner accounts, randomness from the transaction hash, test
networks only, nothing of value, progress may be wiped. Version 1 replaces both providers
behind their interfaces and goes through the hardening phase.

## Design coverage

Written: 19 design documents, the lore premise, 6 ADRs. Still to write before the phases that
need them: effect catalogue, remaining skills, caste sheets, curves, content lists
([PLAN.md](PLAN.md#design-backlog)).

## Verified on the machine

- `claude` CLI on claude-b7r (2.1.283); `codex` 0.155.1; `gh` on bal7hazar.
- SSH access to the private `tiny-swords` repository works: `--with-assets` can initialise
  the submodule in a task worktree.
- scarb 2.19.4 compiles a Dojo 1.8.0 project (dependency from scarbs.xyz, prebuilt
  `dojo_cairo_macros`); `sozo`, `katana`, `torii` are still absent (SPK-5).
- `shellcheck` is not installed on the VPS: it runs in CI.
- **codex's read-only sandbox does not work in a systemd user unit** on this VPS
  (`bwrap: loopback: Failed RTM_NEWADDR`, then `setting up uid map: Permission denied`): the
  kernel restricts unprivileged user namespaces through AppArmor, and only the desktop app's
  profile allows them. The launcher therefore detaches codex with `setsid` inside the app's
  cgroup, keeping the sandbox (OPERATIONS §3); an app restart kills a running audit, which is
  then resumed. A root change (an AppArmor profile for `bwrap`) would let codex run as a unit;
  not needed today. No system setting was changed.
- `sozo`, `katana` and `torii` are still absent (SPK-5); the Sepolia account is in the
  machine's settings since 20:21 UTC (checked by name), given to agents only with
  `--with-sepolia`; the `assets` submodule is not initialised in the
  main checkout (an independent clone of `tiny-swords` is in `~/projects/assets`).

## Not verified

- Latency and cost on mainnet: public data and Sepolia only, no mainnet transaction of ours.
- `origami_hexmap` costs: the library's own benchmarks.
- Phone battery and heat: no measurement exists for any candidate engine.
