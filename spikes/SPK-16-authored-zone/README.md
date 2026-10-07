# SPK-16 — An authored zone's on-chain format, measured

ENG-08 (`docs/briefs/ENG-08-authored-zones-format.md`), D-214 (zones authored with the map editor),
D-215 (the project manager's rulings), D-216 (any chunk set at a chosen origin), D-217 (bridges on
two levels), D-220 (the bound on a zone's draws). A spike: nothing here is production code. ENG-09
builds the records, the checks and the authored reveal from it and promotes `map-format/` to
`tools/map-format/` (D-215 ruling 9). Built on `origin/main` with ENG-05 merged (`9ffd4ff`), its two
packages by path.

| Path | What |
|---|---|
| `src/zone_chunk.cairo` | `ZONE_CHUNK` (kind 26): the walkable plane and the features, packed and unpacked |
| `src/records.cairo` | `BRIDGE` (27), `CANDIDATES` (28), the `LOCATION` marker |
| `src/checks.cairo` | The Registry's checks of an authored zone (`ZoneAssert`), the codes of `map-format/checks.json` |
| `src/authored.cairo` | The draws at entry (hosts among candidates, spawn points' level and count) and the reveal of an authored chunk |
| `src/library.cairo` | `AuthoredLibrary`, the authored path as a class (its size), and `ChunkSlots` (the copy's two slots) |
| `tests/` | `test_format` (bits, round trips, the golden file), `test_checks` (every refusal), `test_draws` (randomness, order), `test_corners` (D-134), `test_cost` (the pairs) |
| `map-format/` | `schema.json` (the export, JSON Schema 2020-12), `kinds.json` (the kind table), `checks.json` (the one table of checks), `convert.py` (export → records, seed rows, golden file), `records.py` (the packers and the checks in Python), `schema_check.py` (a validator of the schema's keywords), `tests/` |
| `samples/` | `zone.json` (the test region's zone drawn as an authored 3 × 2 zone), `town.json`, `set_piece.json`, `manifest.json`; the converter's outputs `*.records.json`, `zone.golden.json` (read by the Cairo tests), `zone.seed.json`; `make_samples.py` draws them |
| `pairs.py`, `pairs.txt`, `snforge-test-output-{1,2}.txt` | The measures: two clean builds and their pairs |

## Run it

```
cd spikes/SPK-16-authored-zone
prlimit --as=8589934592 ../../scripts/lock.sh --heavy scarb build
scarb clean && prlimit --as=8589934592 -- /usr/bin/time -v ../../scripts/lock.sh --heavy snforge test   # twice (D-154)
python3 pairs.py snforge-test-output-1.txt snforge-test-output-2.txt > pairs.txt
python3 samples/make_samples.py
python3 map-format/convert.py samples/zone.json --manifest samples/manifest.json \
    --out samples/zone.records.json --golden samples/zone.golden.json --seed samples/zone.seed.json
python3 map-format/convert.py samples/town.json --manifest samples/manifest.json --out samples/town.records.json
python3 map-format/convert.py samples/set_piece.json --manifest samples/manifest.json --out samples/set_piece.records.json
python3 -m unittest discover -s map-format/tests -p 'test_*.py'
```

Output, on the VPS (Linux, Scarb 2.20.1, snforge 0.64.0), 2026-10-07, after review t-0084's
fixes: both clean runs `Tests: 75 passed, 0 failed`, peak resident memory 1,792,868 kB and
1,805,056 kB (`/usr/bin/time -v`, capped at 8 GiB), 39 s and 36 s; every one of the 22 pairs equal
to the unit in both (`pairs.txt`). The
converter: `14 records -> zone.records.json`, `1 records -> town.records.json`, `1 records ->
set_piece.records.json`; `Ran 39 tests … OK`. The spike's class sizes, from the same build's
artifacts: `AuthoredLibrary` 20,437 CASM felts (24.95 %), `ChunkSlots` 631, `Registry` 29,568
(36.09 %, as main's).

## Method

- **Pairs** (CBT-02d's method): `test_pair_<group>_<what>` against `test_base_<group>`, two tests
  that differ by the measured call alone (`pairs.py` names each base). snforge's figure of a test
  is its whole L2 gas (M). A figure derived by arithmetic is marked E with its terms.
- **Proxies**: `Registry` and `library_call` are measured as they are; a proposed kind is written
  through an existing kind of its part count: `ZONE_CHUNK` (2 parts) as `SET_PIECE` (its
  `SetPieceAssert`, the corners walled, included), `CANDIDATES` (3) as `BOOK` (no check), `BRIDGE`
  (1) as `OUTLINE` (composite, its location read). The checks of the proposed kinds are measured
  apart, in memory (`test_pair_memory_*`). A multicall is measured as the writes in one test,
  without the account's `__execute__` and the outer calldata.
- **Two clean builds** (D-154): `scarb clean` then `snforge test`, twice; the figures are equal.

## The format

The layouts are in ENG-01 §3.5 (*Authored zones*), proposed. In short: one `ZONE_CHUNK` a chunk,
two felts (the walkable plane, 225 tile bits with 25 reserved bits and `LIVE`; the features:
two spawn points, three objects, a candidate tile per quota, the bridge count, two anchored gates);
`CANDIDATES`, the chunks of each quota (one or two 3-part records a zone); `BRIDGE`, one felt a
bridge (deck, two ends); the `LOCATION` marker at bits 144–151. A later plane is a third part of
`ZONE_CHUNK`, flagged in part 0's reserved bits, so the first plane never moves.

**The origin** (D-216): the editor paints on an unbounded plane (odd-r rows, `x` growing West, `y`
North, within ±32,767) and lays the 15 × 15 grid afterwards. The export carries the origin, the
fitted map's global `(0, 0)` on the editor's plane: **its `y` even** (moving by an odd number of rows
would flip every row's neighbours, the window's parity rule of ADR-0006 §4), its `x` free; the
map's chain coordinates are the painted hex less the origin, within `[0, 15 width) × [0, 15
height)`, `width` and `height` 1 to 15. Any chunk set within that rectangle is valid: the outline
need not start at `(0, 0)` and need not be a rectangle (`OUTLINE`'s chunk set and masks).

**The editor's objects** (track CV, decided by the orchestrator under D-215): NPCs, buildings and
props are in the export and the schema; on chain they reach only the walkable plane. A building's
footprint is unwalkable but its door, which must be on the footprint's border (the converter refuses
otherwise); a prop of a blocking kind makes its hex unwalkable. The kind table (`kinds.json`) is
CLI-09e §4's proposal as merged (#367): 14 props with their `blocks`, 47 buildings, 23 NPCs, 2
bridges; from now on the schema owns it.

**Bridges** (D-217): the bridge plane is reserved in version 1, in the export (`bridges`: deck
hexes and two ends) and on chain (`BRIDGE`); a one-hex deck with its two ends is valid; a bridge
lies in one chunk in version 1. Its storage: **818,840** L2 gas a bridge written (1 felt), plus
its share of the chunk's count. Its rules are ENG-08b's: the reveal of version 1 does not read it.
The sample's bridge stands over a stream that a ford also crosses, so that reachability (P-1) does
not depend on the deck's rules: P-1 reads the walkable plane only, so **a map whose only crossing
is a bridge is refused (`pipeline: unreachable tile`) until ENG-08b** gives the deck its rules.

## The checks (deliverable 2)

`map-format/checks.json` is the one table: the registry's 26 cases (R-11 … R-35, CLI-09 §5's ids
kept; three of them reverse checks, below), the pipeline's 3 (P-1 reachability, P-2 seams, P-3 a
deck connected) and the export's 20 (every code the converter refuses with: the hex outside the
size, unequal row lengths, a missing field, an unknown name, the format, the version, the set
piece's, and `export: malformed` for anything else, never a traceback).
Every registry case is a mutation of the sample, refused with its code by `tests/test_checks.cairo`
(`test_refuse_<case>`, snforge) and by the converter (`map-format/tests/test_convert.py`, which
also checks that each Cairo test exists with that code). The sample passes every check on both
sides. ENG-01 §3.5 lists them with the record that checks each, what it reads, and **its reverse
check**, what the other record's write re-runs, so that no rewrite lets a breach through (review
t-0084, minor 1). ENG-09 builds every reverse check; two are prototyped here: a `CANDIDATES` write
re-runs R-12, R-13, R-27, R-29 and R-30 against `QUOTAS` and R-14, R-15 against the chunks whose
candidacy changed (`assert_candidates_write`; `test_refuse_candidates_rewrite_count`, the review's
scenario, and `_tile`), and a `PACK` write a Heart names re-runs R-27 (`assert_pack_write`).

**R-30, the bound of D-220**: ENG-05's worst legal plan (six passes of 112 draws, 98,153,254) **with
the snapshot's eight task quotas** measures **99,673,404**: 0.33 % under D-220's 100,000,000, legal
today. R-30 bounds the location's quotas to 640 draws together; with the tasks the worst plan then
measures **95,799,175** (`test_pair_plan_bound_hosts`). On the authored path (tasks place nothing
there), six quotas of 640 draws among 225 candidates measure **95,035,380**
(`test_pair_hosts_bound_authored`). It binds generated zones too (D-221, ENG-R1c).

## Costs (deliverable 3)

| What | L2 gas (M) |
|---|---:|
| `ZONE_CHUNK` written new (proxy `SET_PIECE`) · rewritten (features part) | 2,389,631 · 706,081 |
| `CANDIDATES` new (proxy `BOOK`) · `BRIDGE` new (proxy `OUTLINE`) | 2,591,040 · 818,840 |
| Checks in memory: a chunk (R-14, R-15, R-20, R-24) · `QUOTAS` (R-12, R-13, R-27, R-29, R-30) | 403,317 · 137,832 |
| The sample zone, 14 records | 18,964,435 |
| 225 chunk records (the largest zone's) | 341,295,595 (1,516,869 a record, E) |
| Records a multicall holds under 1.1 × 10⁹ (E: cap ÷ 1,516,869, the account's share and ~41,000 of calldata a call not measured) | about 700 |
| `bundle` of a chunk · of a chunk and `CANDIDATES` | 93,220 · 221,010 |
| Decode a chunk · reveal the entry chunk · the fullest (every candidate hosted) · E-3's worst | 87,840 · 312,321 · 2,243,843 · 2,000,515 (+ decode) |
| The library call of the fullest chunk | 2,701,253 (the call 457,410, E) |
| The two words written into new slots (ruling 2) | 948,560 |
| Hosts among candidates: the sample · R-15's worst (5 × 112 of 225) · R-30's bound (6 quotas, 640 draws) | 359,085 · 83,829,748 · 95,035,380 |

Against ENG-05 at its merge (ENG-01 §10): a generated chunk in memory costs 2,830,905 typical,
3.90–4.07 M worst; an authored one 0.31–2.24 M on the sample, 2.09 M at E-3's worst (E). In
`create` an authored chunk costs **1.35 M to 3.13 M** (E: read + reveal + two slots) against
ENG-05's 2.0–2.1 M a chunk with nothing to place. **Class**: `AuthoredLibrary` 24.95 % as its own
class (proposed); not inside `RevealLibrary` nor `Instances` (D-209); what `Instances` gains is
ENG-09's to measure, after ENG-05b.

## Randomness (deliverable 4)

The hosts: `derive(entropy, domain(instance, 226, REVEAL), 0)`, then ENG-05's draw
(`PlacementTrait::subset`) among each quota's candidates, once at `create`; the spawn points:
`derive(entropy, domain(instance, 256 + chunk, REVEAL), 0)`, one level a chunk, uniform in the
band (every spawn point of the chunk takes it), each point's count in its template's bounds (at
least 1); a Heart at the band's top (D-208). Counters 226 and
256–480 are no chunk's word (0–224) and not ENG-05's hosts (225) (`test_domains_apart`).
`test_authored_reveal_order_free`: the five chunks revealed in six orders over eight entropies give
the same words; `test_authored_reveal_places_as_drawn`: over 16 entropies every quota placed exactly
its count on its candidate tile. The order test calls a pure function, so it holds the design rather
than catching a fault: the real path's order-freeness rests on ENG-09 keeping `reveal` pure and the
hosts drawn once (review t-0084, note 5), which the randomness lens reads. **What a modified client can still gain in an authored zone: 0
chunks and 0 placements — no order of moves or reveals changes where a quota lands, which chunk's
spawn points hold what level or count, or any tile, since the hosts are fixed at entry and every other
draw is keyed by its chunk; what remains is the entry itself (a new instance, a new draw), as in
every location.**

## Corners (D-134, ruling 5)

`grep -rn -i corner contracts/{logic,ephemeral,persistent}/src` (code lines, comments left out):
`types/reveal.cairo` (`corner()` in the generation, its invariant test), `types/reveal/board.cairo`
(`SIDES` holds no corner, its test), `models/set_piece.cairo` (`SetPieceAssert`, its test); in
`persistent`, a doc comment of `registry.cairo` only; nothing in `ephemeral` (`Instances`), the
window (`types/window.cairo`), the tick or the flood. `test_corners.cairo`: an authored chunk with
open corners passes `ZoneAssert` and its reveal keeps them; `SetPieceAssert` still refuses them;
the window's rules (sight, shapes) read walls only, a corner being a tile like any other. **Ruling
5 applied**: D-134's corners are lifted for authored chunks (R-16), kept for generated chunks and
set pieces.

## Questions this spike raises

In ENG-08's report and its decision record, each with its decider and a recommendation.
