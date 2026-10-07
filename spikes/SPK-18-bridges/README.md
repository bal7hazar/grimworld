# SPK-18 — Bridges (ENG-08b)

**D-227 (the owner, 2026-10-07) replaces D-217's two levels**: a bridge has one level, its deck is
walkable ground drawn over water, nobody passes under it (`docs/architecture/ADR-0008-bridges.md`).
What serves that rule here is the P-1 prototype. The Cairo part is the two-level prototype that
D-227 voids: it is **superseded**, kept as history with the figures it measured, and nothing
builds on it.

| Part | What | Status |
|---|---|---|
| `reach.py`, `test_reach.py` | The plane the converter writes (the painted floor and every deck tile, ADR-0008 rule 1), P-1 on it (rule 6), R-37 (no authored content on a deck or an end, rule 5) | **current**: `python3 reach.py`, 5 tests |
| `src/level.cairo`, `src/movement.cairo`, `tests/*.cairo`, `pairs.py`, `pairs.txt`, `snforge-test-output-{1,2}.txt` | The two-level prototype: a position's level beside it, the two-level movement check, against a one-level check | **superseded by D-227**, history |

## The P-1 prototype (current)

    python3 reach.py

Ran 5 tests, OK:
- the editor's bridge geometry (CLI-09e: both ends in one column);
- a river crossed only by a bridge: refused with the deck left as water (SPK-16's converter today), accepted with the deck written walkable;
- a two-tile deck over a two-row river;
- a floor tile beyond the bridge that nothing reaches: refused;
- R-37 on the deck and on each end.

## History: the two-level prototype (superseded by D-227)

Measured on Linux (the VPS) in two clean builds:

    cd spikes/SPK-18-bridges
    scarb clean
    prlimit --as=8589934592 -- /usr/bin/time -v ../../scripts/lock.sh --heavy snforge test --max-threads 2 > snforge-test-output-1.txt 2>&1
    scarb clean
    prlimit --as=8589934592 -- /usr/bin/time -v ../../scripts/lock.sh --heavy snforge test --max-threads 2 > snforge-test-output-2.txt 2>&1
    python3 pairs.py snforge-test-output-1.txt snforge-test-output-2.txt > pairs.txt

43 tests passed in each run; peak resident memory was 1,339,428 and 1,351,620 kB (capped at 8 GiB). One call is `test_twice_<what>` − `test_once_<what>`. In `pairs.txt` both runs are equal:

| Call | L2 gas |
|---|---:|
| `ground_step`: a one-level check, the spike's own prototype (ENG-07's check is not on main) | 19,396 |
| `bridged_*`: the two-level check, every path (equal on every path: measured, cause not established) | 36,868 |
| `either_none` / `either_climb`: the branch on "a deck in the window" in the caller | 21,456 / 36,568 |
| A position read with its level, member and goblin | +3,430 |
| A move written with its level, member and goblin | +1,300 |

None of these apply under D-227: a deck is floor, so play needs no level, no second check and no
branch.
