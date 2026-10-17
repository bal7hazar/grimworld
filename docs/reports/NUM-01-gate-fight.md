# NUM-01: the numbers that let each MVP profession win the gate fight (D-311)

Each MVP profession (Vanguard, Warden, Arcanist), at level 1 with its creation kit, fights the gate
pack (`PACK` 5: 3 Runts and 2 Slingers, the Heart of `LOCATION` 5) in `scripts/gate2_sim.mjs`, on
track CV's mirror of the tick. The target was at least 16 wins of 20 in the case `kit` / `today`.
Only content numbers changed: no code, no AI, no pack, level or potion.

## The changed numbers

Four numbers of `contracts/seed/test-region.json`. The reasons are in the design documents named.

| Record | Field | Before | After | Reason (in) |
|---|---|---:|---:|---|
| `CASTE` 1, Runt | health multiplier, % | 50 | 25 | design/20 §2.2's NUM-01 note: §2.1's "about 4 hits" counted the sword at 18; the kit's axe does 9, 6 to a level-1 Runt: 5 hits at 25 |
| `CASTE` 2, Slinger | health multiplier, % | 40 | 20 | design/20 §2.2: 4 axe hits at level 1 |
| `CASTE` 2, Slinger | weapon damage | 21 | 11 | design/20 §2.2: 21 is the bow at requirement 9, a level-20 hit with no level curve yet (DS-11); 11 is the bow at requirement 0 (`BASE` 2) |
| `SKILL` 14, Ember Bolt | `DAMAGE` value at rank 0 (`e1_v0`) | 15 | 25 | design/03 *MVP starter skills*: with the goblins above and the bolt at 15 the Arcanist runs out of energy (6/20); at 25 it wins 17/20. Rank 12 stays 60 |

Every value stays inside design/20 §1.5's bounds and design/15's bow range (11 → 21). Ember Bolt
stays inside design/03's 15…60 at both ends. design/20 §2.4's check table is recomputed for the two
castes. Who uses the two caste sheets: packs 1 (Rabble) and 2 (Raiders) through spawn table 1
(locations 2, 3 and 4), pack 5 (location 5's Heart), and pack 3 (Warband, one Slinger, in no spawn
table). The Cairo test that pins one of them is `contracts/persistent/tests/test_seed.cairo` (the
Runt's health, now 25). Track CV's client tests read the seed (the PR body lists them).

## Kit / today, before and after

20 seeds each. Health is out of 100. Before = main at 6493048 (WPN-01).

| Profession | Goblins | Wins before | Wins after | Ticks mean / worst, after | Health left mean / worst, after |
|---|---|---:|---:|---|---|
| Vanguard | full pack (5) | 0/20 | **20/20** | 23.2 / 29 | 75.4 / 48 |
| Warden | full pack (5) | 11/20 | **17/20** | 28.7 / 44 | 66.3 / 0 |
| Arcanist | full pack (5) | 0/20 | **17/20** | 23.2 / 34 | 54.1 / 0 |
| Vanguard | 1 | 20/20 | 20/20 | 9.9 / 16 | 90.8 / 88 |
| Warden | 1 | 20/20 | 20/20 | 9.5 / 15 | 100 / 100 |
| Arcanist | 1 | 20/20 | 20/20 | 8.5 / 14 | 100 / 100 |
| Vanguard | 2 | 20/20 | 20/20 | 11.5 / 18 | 77.2 / 68 |
| Warden | 2 | 20/20 | 20/20 | 13.5 / 25 | 97.6 / 72 |
| Arcanist | 2 | 20/20 | 20/20 | 11.1 / 18 | 97.5 / 70 |

Before, in full (ticks mean / worst, health mean / worst): the full pack gave Vanguard 16.4 / 22,
0 / 0; Warden 48.1 / 76, 14.1 / 0; Arcanist 19.1 / 42, 0 / 0 (the brief's figures, reproduced). One
goblin: Vanguard 11.6 / 18, 82.8 / 80; Warden 11.3 / 17, 100 / 100; Arcanist 13.5 / 19, 89.9 / 71.
Two goblins: Vanguard 16.2 / 23, 68.4 / 48; Warden 19.6 / 33, 84.4 / 51; Arcanist 20.2 / 30,
65.9 / 4.

At 40 seeds (`--seeds 40`, for information) the full pack gives Vanguard 40/40, Warden 33/40,
Arcanist 34/40.

## The other cases, after, full pack (for information)

Wins, then ticks mean / worst and health left mean / worst.

| Weapons | Ranks | Vanguard | Warden | Arcanist |
|---|---|---|---|---|
| inert | today | 0/20 (17.4 / 23, 0 / 0) | 0/20 (13.8 / 19, 0 / 0) | 17/20 (23.2 / 34, 54.1 / 0) |
| inert | a | 0/20 (22.4 / 28, 0 / 0) | 0/20 (15.6 / 21, 0 / 0) | 20/20 (24 / 38, 68 / 18) |
| inert | a+b | 0/20 (22.4 / 28, 0 / 0) | 0/20 (15.6 / 21, 0 / 0) | 20/20 (23.2 / 31, 69.7 / 18) |
| kit | a | 20/20 (22.2 / 29, 67 / 51) | 18/20 (30.5 / 44, 72.8 / 0) | 20/20 (24 / 38, 68 / 18) |
| kit | a+b | 20/20 (22.2 / 29, 67 / 51) | 20/20 (29.2 / 42, 79.5 / 33) | 20/20 (23.2 / 31, 69.7 / 18) |

`inert` (no weapon) leaves the Vanguard and the Warden without an attack, so they cannot win; the
Arcanist has no weapon in either case.

## How the set was chosen

On main the Arcanist died in about 5 ticks once three Runts reached it (8 a tick each at armor 60,
plus the Slingers), and it ran out of its 50 energy long before the pack's 230 health fell. Each
lever was measured alone and in sets (kit / today, 20 seeds, wins for Vanguard, Warden, Arcanist):

| Set | Vanguard | Warden | Arcanist |
|---|---:|---:|---:|
| goblin damage only (Runt 17 → 9, Slinger 21 → 11) | 20 | 16 | 0 |
| goblin health only (Runt 30 %, Slinger 25 %) | 13 | 15 | 0 |
| **NUM-01: health 25 %, 20 %; Slinger damage 11; Ember Bolt 25** | **20** | **17** | **17** |
| NUM-01 without the Slinger's damage change | 18 | 15 | 13 |
| NUM-01 without the Slinger's health change | 20 | 17 | 5 |
| NUM-01 without the Runt's health change | 5 | 16 | 4 |
| NUM-01 without the Ember Bolt change | 20 | 17 | 6 |
| NUM-01 and the Runt's damage 17 → 9 (a fifth change) | 20 | 19 | 20 |

Dropping any one of the four changes leaves a profession under 16/20, and no other set of three
tried reached it (the Ember Bolt at 30 or 35 without the health changes; lower health, 20 % and
15 %, without the bolt: Arcanist 15/20 at best). The fifth change, the Runt's axe at its requirement-0 damage (9), gives more margin but is
not needed: NUM-01 keeps the fewest changes, and BAL-01 may take it.

## Gas, vectors, class sizes

- No Cairo source changed. The persistent package passed whole (`snforge test`, 335 tests, through
  the shim, capped at 8 GiB, 3.59 GB maximum RSS, 3 min 29 s). Its four `test_seed` tests, the only
  ones that read the seed, measured exactly `docs/BUDGETS.md`'s figures (24,244,190, 125,704,146,
  166,368,906 and 191,422,262), on the final seed too (`snforge test test_seed`, 4 passed, 2.02 GB
  maximum RSS): no gas row moved.
- No logic test reads the seed: `contracts/logic/vectors/*.jsonl` and `check.py` are untouched, and
  no class changes, so `class_sizes.py` has nothing to measure.

## Reproduce

```
pnpm install --frozen-lockfile
check-run --node-heap 1024 -- node --test scripts/gate2_sim.mjs     # the full pack, 20 seeds
node scripts/gate2_sim.mjs --seeds 20 --goblins 1
node scripts/gate2_sim.mjs --seeds 20 --goblins 2
```

The default run is 20 seeds (`--seeds 20`), seeds 1 to 20. `check-run` refuses the `--goblins`
form (not a runner form of its grammar), so those two ran bare: they need no Cairo build.
