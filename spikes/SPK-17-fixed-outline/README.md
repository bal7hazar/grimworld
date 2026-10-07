# SPK-17 — A dungeon floor's outline fixed at entry, measured

ENG-10a (D-208's PLAN item; the Overseer's rule of 2026-10-07: the dungeon residue blocks any
non-test deployment until ENG-10b merges, and ENG-10b's merge gate is a re-audit measuring it at
zero). A spike: nothing here is production code; ENG-10b builds from it
(`docs/briefs/ENG-10b-fixed-dungeon-outline.md`). The design is in ADR-0006 §3 (*A dungeon floor's
outline, fixed at entry*) and ENG-01 §1.3, §3.2, §10, marked "ENG-10a, proposed". Built on
`origin/main` at `44961f2` (ENG-05 and ENG-08 merged), `grimworld_logic` by path.

| Path | What |
|---|---|
| `src/outline.cairo` | The draw at `create` (`draw_winding`, the law, D-223; `draw` and `draw_frontier`, measured and not kept), the layers by distance (`layers`), the distances through the open seams (`far`, `distance`), the outline read back from revealed edges (`from_edges`), and the rejected two-felt layout (`pack`, `unpack`) |
| `src/engine.cairo`, `src/engine/placement.cairo` | ENG-05's engine (`grimworld_logic::types::reveal` at `44961f2`, its tests left out) with ENG-10a's changes, each marked `ENG-10a` |
| `src/library.cairo` | `FloorLibrary` (`HostsLibrary` with the floor's call), `FixedRevealLibrary` (`RevealLibrary` on the changed engine), `Slots` (the new slots apart) |
| `tests/test_residue.cairo` | **The zero-residue test** (`test_zero_residue_*`) and the negative control on ENG-05's merged engine (`test_residue_eng05`) |
| `tests/test_outline.cairo` | The outline's properties over 64 entropies a size; the layout's round trip |
| `tests/test_cost.cairo` | The pairs |
| `pairs.py`, `pairs.txt`, `sizes.py`, `snforge-test-output-{1,2}.txt` | The measures |

## Run it

```
cd spikes/SPK-17-fixed-outline
prlimit --as=8589934592 ../../scripts/lock.sh --heavy scarb build && python3 sizes.py
scarb clean && prlimit --as=8589934592 -- /usr/bin/time -v ../../scripts/lock.sh --heavy snforge test --max-threads 2   # twice (D-154)
python3 pairs.py snforge-test-output-1.txt snforge-test-output-2.txt > pairs.txt
```

`--max-threads 2` is needed, and each test kept small: without the flag a capped run aborted on a 512 MB allocation (`memory
allocation of 536870912 bytes failed`, the 8 GiB address-space cap). Output, on the VPS (Linux, Scarb
2.20.1, snforge 0.64.0), 2026-10-07: both clean runs `Tests: 48 passed, 0 failed`, peak resident
memory 2,921,368 kB and 2,826,584 kB; every one of the 16 pairs equal to the unit in
both (`pairs.txt`). `sizes.py` on the same tree's build: `FixedRevealLibrary` 40,220 CASM felts
(49.10 %), `FloorLibrary` 12,436 (15.18 %), `Slots` 1,563; ENG-05's `RevealLibrary` 41,109 (50.18 %)
and `HostsLibrary` 6,580 (8.03 %), equal to ENG-01 §1.3.

## The zero-residue test (deliverable 2)

For 8 entropies at `N` = 6 and 8 at `N` = 12 (`test_zero_residue_n6_*`, `_n12_*`), and for 6 floors
whose farthest layer is one chunk with a set piece (2 packs, 3 objects) listed before the exit and
the Heart (`test_zero_residue_piece_*`, review t-0088's major 1), a floor is created as ENG-10b's
`create` would (the winding outline, its layers, the hosts with the exit's and the Heart's drawn
first, the masks), then revealed in seven orders, the entry first: by index, backward, nearest
first, farthest first, two drawn, and t-0077's forcing order (the entry's first neighbour kept for the
last reveal). Every order must give the same chunk set (the outline), one exit and one Heart on the
same chunks (in the farthest layer), the same exit-to-entry distance in chunks read back from the
revealed edges (the farthest distance), and the same edges in every chunk. It passes: 22 floors, 154
orders. The test calls the engine and the draw as pure functions, so it proves the design, not
ENG-10b's wiring: ENG-10b's `test_zero_residue` runs the same comparison on the real path (its brief,
A1, A2).

**In tiles** (review t-0088, minor 2; **D-224**): each order's walked distance from the entry tile
to the exit's tile (a bit-parallel breadth-first walk on the revealed floor, `fixtures::walk`) is
asserted equal too. With D-224 prototyped (a seam's openings from the seam's own stream,
`engine.cairo` `decide`, `openings`), it is equal in every order on the 22 floors. **Without D-224**
(`a2d740b`, the openings drawn by the chunk revealed first): measured at most 24 tiles over 22 floors
and 7 orders (73 to 97 on one floor of 12), the spreads 1 to 24, the walks 29 to 124 tiles.

**The set-piece fixture** (review t-0089, note 2): each floor asserts where the set piece went
(quota 0, never on the farthest chunk; printed: chunks 111, 112, 63, 96, 112, 111).
`test_piece_old_order` runs the same quotas in c240f76's order (the list's, the farthest layer only):
3 of 32 floors of 6 whose farthest layer is one chunk leave the exit and the Heart with no host; the
new order hosts both on all 32.

**A zone's hosts** (review t-0089, minor 1): `test_pair_hosts_zone_*`, the same plan on
`origin/main`'s `PlacementTrait::hosts` and the spike's: 1,403,404 against 1,547,934 (+144,530), the
same masks (`test_hosts_zone_unchanged`).

**On ENG-05's merged engine** (`test_zero_residue_on_eng05_*`, a floor a test): the seven orders as
strategies over what ENG-05 makes revealable, the same comparison: it fails on 4 of 4 floors at `N` =
12 (5, 5, 5 and 6 of the six other orders differ from the first). `test_residue_eng05` prints the
honest order against the forcing one over 8 floors: the forcing order puts the exit 1 chunk from the
entry on **8 of 8**; the honest order put it at 11, 7, 10, 11 and 11 chunks on five of them (**45
chunks gained in all**), and at 1 on the other three. The first measure of the residue (the
re-audits' figure was a hand trace).

## Costs (deliverable 3)

| What | L2 gas (M) |
|---|---:|
| The outline, uniform growth (not kept) at `N` = 6 · at 12 · **winding at 12, the law (D-223)** · uniform over the frontier at 12 | 1,212,496 · 2,801,446 · 2,393,509 · 3,893,301 |
| `create`'s floor in memory (winding outline, layers, three hosts, the exit's and the Heart's first, a mask) · through `FloorLibrary` | 3,896,696 · 4,062,126 |
| Three outline felts and three hosts' bitmaps written new | 2,854,060 |
| Rejected: two felts written · packed · unpacked | 948,660 · 3,307,641 · 5,367,187 |
| One chunk next to the entry: ENG-05 · changed engine | 3,804,989 · 2,204,650 |
| The other 11 chunks: ENG-05 (with the test's search) · changed engine | 65,643,780 · 37,230,390 |

The outline's shape, 64 entropies a size (`test_outline_*`): the farthest distance 2–5 at `N` = 6
(mean 2.81), 2–6 at 9 (3.56), 3–6 at 12 (4.20); winding 2–5 at 6 (3.38), 3–9 at 12 (5.16).
