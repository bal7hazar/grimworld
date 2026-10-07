# SPK-18 — Bridges on two levels (ENG-08b, D-217)

A spike for `docs/architecture/ADR-0008-bridges.md`: the movement check with a level against the
check of one level, the cost of keeping a level beside a position, and the converter's reachability
(P-1) with bridges. Nothing here is production code; the lot that builds the rules in play (ADR-0008
Open question 4) and ENG-09 (the converter) build from it.

| Part | What | Tests |
|---|---|---|
| `src/level.cairo` | A position's level: `MemberState` bit 176, `GoblinState` bit 240 (its memory's 241); today's reads and writes of a position (`place`, `moved`) and the same with the level | `tests/test_rules.cairo` (round trips, no other bit touched) |
| `src/movement.cairo` | `Ground`: the one-level check ENG-07 builds under D-225 (prototyped here; not on main). `Bridged`: ADR-0008 rule 2 (the climb, along the deck, the descent, under, the cut, the railings, two occupancies) | `tests/test_rules.cairo`: every path, both occupancies, a two-tile deck, the window's edge, and `test_no_deck_is_one_level` (equal to `Ground` on all 240 tiles × 6 directions) |
| `tests/test_cost.cairo` | One call = `test_twice_<what>` − `test_once_<what>` (ENG-02's method), inputs opaque | `pairs.py` |
| `reach.py`, `test_reach.py` | P-1 over the two-level graph and R-37 (ADR-0008 rule 8), on global tiles as SPK-16's converter | `python3 reach.py` (8 tests) |

The boards are the editor's bridge (CLI-09e §1: one deck tile, the southern end South-West of it,
the northern end North-West of it) at the window's centre, over a road (the ground beneath walkable)
and over a river (a wall), and a two-tile deck.

## Measured (Linux, the VPS, two clean builds)

    cd spikes/SPK-18-bridges
    scarb clean
    prlimit --as=8589934592 -- /usr/bin/time -v ../../scripts/lock.sh --heavy snforge test --max-threads 2 > snforge-test-output-1.txt 2>&1
    scarb clean
    prlimit --as=8589934592 -- /usr/bin/time -v ../../scripts/lock.sh --heavy snforge test --max-threads 2 > snforge-test-output-2.txt 2>&1
    python3 pairs.py snforge-test-output-1.txt snforge-test-output-2.txt > pairs.txt

43 tests passed in each run; peak resident memory 1,339,428 and 1,351,620 kB (capped at 8 GiB).
`pairs.txt`, both runs equal:

| Call | L2 gas | Against today |
|---|---:|---|
| `ground_step`: the one-level check, a move | 19,396 | the base |
| `bridged_none`, `_ground`, `_under`, `_climb`, `_descend`: the two-level check | 36,868 on every path | +17,472 (×1.90) |
| `either_none`: the branch on "a deck in the window" in the caller, no deck | 21,456 | +2,060 (×1.11) |
| `either_climb`: the same, a deck in the window | 36,568 | +17,172 |
| `member_place` → `member_place_level`: read a member's position, with its level | 11,440 → 14,870 | +3,430 |
| `member_moved` → `member_moved_level`: write a member's move, with its level | 1,400 → 2,700 | +1,300 |
| `goblin_place` → `goblin_place_level` | 9,960 → 13,390 | +3,430 |
| `goblin_moved` → `goblin_moved_level` | 1,300 → 2,600 | +1,300 |

**Every path of `Bridged::step` costs the same**: snforge charges a function's branches at their
dearest side when they merge, so the cheap path (no deck) costs what the climb costs inside one
function. Moved into the caller (`either`), the branch lets a window with no deck pay 21,456. Hence
ADR-0008's recommendation to branch in the caller (per move, or per batch on the union of its
windows).

**Not measured (E in ADR-0008)**: the two-level flood (rule 3), the combat window `open | deck`
(rule 5), reading the `BRIDGE` records in a batch (rule 9). "Today's movement" does not exist on main
(ENG-07 builds it): the base is this spike's `Ground`, and ENG-07's real check may differ.

## The P-1 prototype

    python3 reach.py

Ran 8 tests, OK: a river crossed only by a two-tile bridge (refused by today's P-1, accepted with
the bridge, both deck tiles reached aloft and not on the ground); the editor's bridge over a road
(the deck's tile reached under and on) and over a river; the cut leaving the ground under a deck
unreachable when only the ends touch it; R-37's three refusals.
