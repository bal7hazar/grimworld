# SPK-2 — Cost spike

## Agent
Title: `[Opus 5.5] SPK-2 cost spike` · Profile: implement · Branch: `chore/spk-2-cost`

## Goal
After this task we know, from our own measurements and not from public figures, what the
heaviest ordinary actions of the game cost in L2 gas and in money, and whether ADR-0001's
threshold holds: **an expedition of 300 actions for at most $0.50, fully sponsored**. The
result decides whether option A (Starknet mainnet) is kept (risk R-2) and feeds the budgets
FND-04 writes. It also says whether the rarity signature of alchemy (D-52) is cheap enough to
keep.

## Context
- ADR-0001 (*Validation — Phase 0 spikes*, SPK-2 row; option B is the fallback); design/02
  (*The tick*: world tick order; *Simulation budget*: the window follows the adventurer,
  at most 8 awake goblins, **one flood per tick shared by all goblins**; *Action batching*: the queue and
  its stop conditions); design/04 (*Actions*, *Damage formula* with its lookup table, *Goblin
  AI* determinism rules); design/07 (*Discovery algorithm*, *Rarity signatures*: "the step
  budget of brewing is measured in SPK-2 and the feature is kept only if its overhead is
  negligible"); design/17 (*Supply*: **5 Rifts a day per account**, D-101); docs/CAIRO.md in
  full; docs/needs/hexmap.md (answers of 2026-09-28: one flood on the occupancy frozen at the
  start of the tick).
- The window and sight: ADR-0006 §1 and §4 and docs/decisions/2026-09-28-window-follows.md
  (D-120, 2026-09-28): the window follows the adventurer, 15 × 16, never stored.
- Depends on: SPK-5 (merged): Cairo 2.13, Scarb 2.13.1, snforge 0.51.2, `dojo` 1.8.0,
  `scripts/with-katana.sh`; `spikes/SPK-5/` is the working reference for manifests.
- Runs in parallel with FND-01: do not touch `contracts/` or `client/`.
- PLAN's SPK-2 row says "10 Rifts"; the accepted decision is **5 a day** (D-101). Use 5 and
  say so in the report.

## Scope
- In: a throwaway Dojo world in `spikes/SPK-2/`, as close to the design as a spike needs to
  be to give honest numbers, **not** production code:
  1. **Worst-case tick**: the **15 columns × 16 rows** window of D-120 (ADR-0006 §4, origin on
     an even row, the adventurer on local `(7, 7)` or `(7, 8)`), given already assembled —
     **its assembly from chunks is SPK-7's measurement, not yours** — with walls, the
     adventurer, **8 awake goblins**;
     one breadth-first flood from the adventurer on the window shared by all goblins
     (`origami_hexmap` 1.8.0's flood if it builds on Cairo 2.13, otherwise a plain bitboard
     flood of your own, stated as such); each goblin, in ascending id order, steps to its
     free neighbour closest to the adventurer or attacks if adjacent (damage through the
     `2^(x/40)` lookup table of design/04); conditions and regeneration applied; state read
     and written as models the way a real system would (one write per model per
     transaction, docs/CAIRO.md §5).
  2. **A queue of 10 moves** in one transaction, with the tick after each move and the stop
     conditions checked (design/02 *Action batching*).
  3. **A brewing step** (design/07 *Discovery algorithm*), with and without the rarity
     signature, so that the overhead of D-52 is a measured difference.
  4. **Hub actions** of a typical day: accept a quest, claim it, enter an instance (entry
     draw through a stand-in for `fate(domain)` reading the transaction hash), leave.
- Measure each as **snforge tests with gas budgets** (docs/CAIRO.md §2) **and** as real
  transactions on a local Katana through `scripts/with-katana.sh` (fee and gas from the
  receipts), and compare the two.
- **Money**: read the current L2 gas price of Starknet Sepolia and mainnet from public RPC
  endpoints (read-only JSON-RPC calls with `curl`, no account, no transaction) and the STRK
  price from a public source; give both with their time and source. Compute: cost of one
  action of each kind; of an expedition of 300 actions under stated assumptions (share of
  moves, fights, loot, queue length); of **an active player per day** (5 Rifts, quests, hub
  actions; state the assumptions); compare with the $0.50 threshold.
- `docs/research/SPK-2-cost.md`: what was built and how far it is from the design; every
  figure with its command and raw output; the money computation with its inputs; the verdict
  on ADR-0001's threshold and on D-52; what would change the numbers (the fallback of D-120,
  sight 5 on a 13 × 14 window; fewer awake goblins; queue length; the assembly cost SPK-7
  measures, to be added per tick); open questions for FND-04 and SPK-7.
- Out: chunk reveal and window assembly (SPK-7); verifiable randomness (SPK-3); latency
  (SPK-1); any deployment outside a local Katana; any transaction on Sepolia or mainnet;
  `contracts/`, `client/`.
- Allowlist: `spikes/SPK-2/**`, `docs/research/SPK-2-cost.md`. Anything else is an
  escalation.

## Interfaces
Throwaway: none that later tasks consume. Name the systems after what they measure
(`tick_worst_case`, `queue_moves`, `brew`, …).

## Acceptance criteria
- [ ] AC-1 The worst-case tick runs with 8 awake goblins and one shared flood; its test has a
      gas budget, and the flood is checked against a plain, obviously correct version kept in
      the tests (docs/CAIRO.md §2, *Oracles*).
- [ ] AC-2 The 10-move queue, the brewing step with and without signature, and the hub
      actions each have a test with a gas budget.
- [ ] AC-3 The same actions sent as transactions on a local Katana; the report puts snforge
      and Katana figures side by side.
- [ ] AC-4 The money table: gas price and STRK price with time and source; cost per action,
      per 300-action expedition, per active player per day; verdict against $0.50.
- [ ] AC-5 The D-52 overhead is a number, with a recommendation to keep or drop it.

## Verification
From the worktree root:
```
scripts/lock.sh sozo build --manifest-path spikes/SPK-2/Scarb.toml
scripts/lock.sh sozo test --manifest-path spikes/SPK-2/Scarb.toml
scripts/with-katana.sh <the command that migrates and sends the measured transactions>
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7, with the cost table of every measured action
(snforge gas, Katana gas and fee, budget) and the money table.
