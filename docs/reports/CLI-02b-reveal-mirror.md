# CLI-02b — The reveal mirror in client/sim

Lot CLI-02b part 2, track CV, 2026-10-10. Part 1 (#329) mirrored Fate and the packing. This part
mirrors ENG-05's reveal of a chunk (ENG-05 #348, ENG-05b #388, ENG-10b #385, as ENG-07 #392 and
ENG-07b #395 play it) in `client/sim`, against `contracts/logic/vectors/reveal.jsonl` (197 cases),
replayed in place like the other tables (`src/parity/`). Branch from `main` at 0bf80ab.

## What is mirrored

| `fn` | Cases | Cairo | Mirror |
|---|---|---|---|
| `word` | 18 | `fate::EntropyTrait::word` | `reveal.ts`: `word` (on `fate.ts`'s `derive`, `domain`) |
| `feed` | 15 | `EntropyTrait::feed` | `reveal.ts`: `feed` |
| `base` | 12 | `reveal/board.cairo`: `BoardTrait::base` (two `hades` permutations, the biome's density) | `reveal/board.ts`: `base` |
| `sight` | 12 | `SightTrait::chunks`, `touches` | `reveal.ts`: `chunks`, `touches` |
| `member` | 114 | `models/chunk.cairo`: `PackPlacementTrait::member` | `reveal.ts`: `member` |
| `reveal` | 26 | `RevealTrait::reveal`, `generate`, `decide`, `openings`, `opening`, `piece`, `root`; `SiteTrait`; `reveal/board.cairo` (`copy`, `lines`, `anchor_line`, `smooth`, `cut`, `component`, `dilate`, `near_openings`); `reveal/placement.cairo` (`slot`, `due`, `level`, `pack_level`, `tile`, `take`, `object`, `pack`, `near`, `offset`, `place`, `spend`); `PackTrait::bounds`, `SpawnTableTrait::weight`, `pick`; `EntropyTrait::outline`; `hexx` 0.2.0's `RngTrait` (`new`, `mix`, `draw`, `draw6`, `draw_byte`, `refill`), `CaverTrait::smooth` (N-1) and `keep_component` | `reveal.ts`, `reveal/board.ts`, `reveal/placement.ts`, `hexx.ts` |

Also mirrored, without a vector: `RevealTrait::kind` and `revealable`, `EntropyTrait::hosts`. Not
mirrored: what `create` computes once and the reveal reads as input (`PlacementTrait::hosts`,
`floor_hosts`, `plan`, `subset`, `with_hosts`; `OutlineTrait::draw`, `layers`): a quota's hosts
reach the reveal above each chunk's mask in `Site.masks`, the outline in `Site.chunk_set`, `west`,
`north`. ENG-07's use of the reveal in a batch (stopping when sight touches an unrevealed chunk,
an unrevealed chunk walled in the window, D-136) is the tick's, CLI-02c's and CLI-03's.

Where the mirror computes differently from the Cairo code (the files say it at their head):
- Every product and difference the Cairo code computes in the field is computed modulo `P`, the
  same operands in the same order, so a sum that carries in Cairo carries here (one does, below).
- The automaton's rule runs on the whole bitmap where `hexx` runs it per `u128` limb: each step is
  bitwise or a sum of disjoint sets, so no carry crosses bit 128.
- `keep_component` is a breadth-first search tile by tile where `hexx` dilates limbs; it returns the
  same set, the component of the source.
- `hades_permutation` is `@scure/starknet` 1.1.0's `poseidonSmall` (already a dependency); no
  dependency added.

## How the table is replayed

`src/parity/tables.ts` has one entry, `reveal.jsonl` with floor 197, and an adapter per `fn`. A
`reveal` case is decoded from its Cairo `Serde` (`revealFromFelts`: `Site` with its spans, quotas,
spawn table, pack templates, set pieces; `Progress`; the instance; `known`; the chunks) and the
result re-encoded (`progressToFelts`, `revealedToFelts`); the whole `ok` is compared.
`src/parity/parity.test.ts` checks the count per `fn` (`word` 18, `feed` 15, `base` 12, `sight` 12,
`member` 114, `reveal` 26), so a case added to the table fails the test until the count moves.

Parity: 197 of 197 cases, no divergence.

## Mutants

72 mutants for the reveal (one per rule, `src/parity/mutants.test.ts`, rows 50 to 121 of its
table); 48 are killed. 24 survive: each is marked `survives` with the case that would kill it, for
track game. Two mutants were written and dropped as equivalent, since no case can kill them: the
quotas' stream (`mix(word, 2)`) is drawn but never read since D-208 (each quota is due on its hosts
alone), so neither moving that stream nor dropping its draws changes any result.

| # | Mutant | Killed by |
|---|---|---|
| 50 | a chunk's word from the wrong derive index | vectors/reveal.jsonl id 0 (word) |
| 51 | feed hashes the entropy with the fact instead of adding it | vectors/reveal.jsonl id 18 (feed) |
| 52 | a dungeon's seam streams seeded by the hosts' word (chunk 225, not 227) | vectors/reveal.jsonl id 187 (reveal) |
| 53 | a chunk outside the zone's chunk set revealed (D-134's void chunks) | vectors/reveal.jsonl id 184 (reveal) |
| 54 | a revealed chunk revealed again | **survives**: no case asks a chunk already revealed: `reveal` of chunks [16, 16], or of 16 once it is revealed, reveals it once |
| 55 | an anchor on a corner opened (D-134) | **survives**: no anchor lies on a corner: a zone anchor (0, 14) or (0, 210) stays wall |
| 56 | a copied side takes the neighbour's same side, not its facing one | vectors/reveal.jsonl id 172 (reveal) |
| 57 | a copied edge reads the neighbour's same edge, not the facing one | vectors/reveal.jsonl id 188 (reveal) |
| 58 | ENG-05's unread border draw dropped (the ring's stream moves) | vectors/reveal.jsonl id 171 (reveal) |
| 59 | a side the mask cuts whole still drawn open | **survives**: no mask cuts a whole side that faces a revealable neighbour: a 3 x 1 ruin whose chunk 1 has the columns 0-11 mask, chunk 1 revealed before chunk 2 |
| 60 | a dungeon side open whatever its seam | **survives**: no dungeon chunk faces an outline chunk across a closed seam: a floor whose outline holds two adjacent chunks with no seam between them |
| 61 | a South seam keyed on the West axis (D-224) | **survives**: every dungeon South side is copied (the floor is revealed by index, its South neighbour first): a floor chunk revealed before its South neighbour |
| 62 | a dungeon seam's openings from the chunk's stream (D-224) | vectors/reveal.jsonl id 186 (reveal) |
| 63 | one opening a side, never two | vectors/reveal.jsonl id 171 (reveal) |
| 64 | an opening drawn once before the exact draw | **survives**: every side drawn open is whole: a side drawn open under a mask that keeps part of it (the cut case with chunk 1 revealed first) |
| 65 | an opening drawn on a corner (D-134) | vectors/reveal.jsonl id 171 (reveal) |
| 66 | a zone chunk writes its edges | vectors/reveal.jsonl id 171 (reveal) |
| 67 | an interior anchor not joined to the spine | **survives**: the only interior anchor (112) lies on the spine: an interior anchor off row 7 and column 7, e.g. tile 48 |
| 68 | an anchor on the ring not opened | vectors/reveal.jsonl id 184 (reveal) |
| 69 | the flood's source not the first interior anchor when the centre is wall | **survives**: no chunk has its centre cut or walled: an interior anchor in a chunk whose mask cuts tile 112 |
| 70 | a set piece's walls ignored (the base generated) | **survives**: case 196 never lays its set piece: the zone has no host above its masks (D-208), so the quota stays owed (`left[0]` 1 after both chunks); its chunk needs the quota's host bit 225 |
| 71 | the cut by the zone's tile mask skipped | vectors/reveal.jsonl id 185 (reveal) |
| 72 | the centre's component not kept | vectors/reveal.jsonl id 176 (reveal) |
| 73 | a revealed chunk not recorded in the progress | vectors/reveal.jsonl id 171 (reveal) |
| 74 | a chunk revealed in a call not known to the next ones | vectors/reveal.jsonl id 184 (reveal) |
| 75 | sight's chunk columns shifted by the near row, not the tile's | **survives**: sight (12, 9) in 15 x 15: chunks 0, 1, 15, 16 (the mutant drops 16) |
| 76 | sight's hexagon of radius 5 across rows | **survives**: sight (0, 9) in 15 x 15: chunks 0, 15 (the mutant drops 15) |
| 77 | a goblin's tile ignores the row's parity | vectors/reveal.jsonl id 64 (member) |
| 78 | a member one column past the chunk's side kept | **survives**: no member from a tile of columns 12-14: member(13, 11, false) is None |
| 79 | meadow at the cave's density | vectors/reveal.jsonl id 33 (base) |
| 80 | forest without its fifth bitmap | vectors/reveal.jsonl id 34 (base) |
| 81 | ruin at the cave's density | vectors/reveal.jsonl id 36 (base) |
| 82 | the base's second permutation from the first's input | vectors/reveal.jsonl id 34 (base) |
| 83 | the base not restricted to the interior | vectors/reveal.jsonl id 33 (base) |
| 84 | the smoothing ignores the chunk's global row parity | vectors/reveal.jsonl id 171 (reveal) |
| 85 | two generations of the automaton | vectors/reveal.jsonl id 171 (reveal) |
| 86 | the spine not laid | vectors/reveal.jsonl id 171 (reveal) |
| 87 | a West opening's line one tile short of the spine | vectors/reveal.jsonl id 171 (reveal) |
| 88 | an odd chunk flooded on the even layout | **survives**: no odd chunk's interior is split in a way the row parity decides: an odd-row set piece whose floor is two parts touching only across a row |
| 89 | placement allowed at 2 from an opening (one dilation) | vectors/reveal.jsonl id 171 (reveal) |
| 90 | the interior anchors not kept clear of placement | **survives**: nothing is drawn within 2 of the one interior anchor (112): an interior anchor in a chunk of spawn density 255 |
| 91 | the dilation ignores the chunk's global row parity | vectors/reveal.jsonl id 173 (reveal) |
| 92 | every floor tile survives the automaton (no S2) | vectors/reveal.jsonl id 171 (reveal) |
| 93 | a wall born with 2 floor neighbours (B2, not B4) | vectors/reveal.jsonl id 171 (reveal) |
| 94 | the pool refilled below 2^63, not 2^64 | vectors/reveal.jsonl id 183 (reveal) |
| 95 | a quota laid off its hosts (D-208) | vectors/reveal.jsonl id 186 (reveal) |
| 96 | a quota with nothing left laid again | **survives**: no mask hosts a quota with nothing left: a site whose chunk hosts quota i (bit 225 + i) with `left[i]` 0 |
| 97 | the quotas placed not spent | vectors/reveal.jsonl id 187 (reveal) |
| 98 | a task's landmark not placed | vectors/reveal.jsonl id 194 (reveal) |
| 99 | the band's distance Chebyshev, not Manhattan | vectors/reveal.jsonl id 171 (reveal) |
| 100 | a dungeon's band over its rectangle, not N - 1 | **survives**: no dungeon chunk 3 or more from the entry lays a chest or a pack of offset 0: a floor of N 6 with one there |
| 101 | the band's distance not held at D | **survives**: no chunk is farther than D from the entry: a zone whose entry chunk lies outside its rectangle |
| 102 | a pack's level not held in the location's band | vectors/reveal.jsonl id 194 (reveal) |
| 103 | a Heart's pack at the band's level, not its top (D-208) | **survives**: the Heart's template (offset +2) reaches the band's top anyway: a Heart in the entry chunk, or a Heart template of offset 0 |
| 104 | a pack drawn empty (no floor of one goblin) | **survives**: every template has a caste of minimum 1 or more: a template whose minimums are all 0 |
| 105 | a pack's size capped above 5 | **survives**: every template's maximums sum to 5 or less: a template of maximums 3 + 3 |
| 106 | a pack always at its largest size | vectors/reveal.jsonl id 171 (reveal) |
| 107 | a goblin's row parity local, not global | vectors/reveal.jsonl id 171 (reveal) |
| 108 | goblin 0 not on the pack's tile (offset 9) | vectors/reveal.jsonl id 171 (reveal) |
| 109 | a goblin's offset index one row off | vectors/reveal.jsonl id 171 (reveal) |
| 110 | every pack asleep, its alert not drawn | vectors/reveal.jsonl id 171 (reveal) |
| 111 | a tile drawn once before the exact draw | vectors/reveal.jsonl id 171 (reveal) |
| 112 | a fourth object in a chunk (E-3) | **survives**: no chunk is offered a fourth object: a set piece of 3 objects in a ruin chunk that rolls a chest or a trap |
| 113 | a third pack in a chunk (E-3) | **survives**: no chunk is offered a third pack: a Heart's chunk whose two spawn rolls pass (density 255) |
| 114 | a spawn roll equal to the density places | **survives**: no spawn roll equals the density: a zone of density 0 whose roll is 0 (1 slot in 256) |
| 115 | the spawn's template not drawn by weight | vectors/reveal.jsonl id 171 (reveal) |
| 116 | a chest 1 chunk in 5 | vectors/reveal.jsonl id 171 (reveal) |
| 117 | a chest's param not the band's level | vectors/reveal.jsonl id 179 (reveal) |
| 118 | a gathering node in a dungeon | vectors/reveal.jsonl id 187 (reveal) |
| 119 | a terrain trap in a meadow or a forest | vectors/reveal.jsonl id 171 (reveal) |
| 120 | a dungeon's exit drawn among every allowed tile, not the core | vectors/reveal.jsonl id 191 (reveal) |
| 121 | a set piece's quota not spent | **survives**: case 196 never lays its set piece (no host bit 225 above the masks, D-208) |

### What track game is asked (the survivors' cases)

1. **The set-piece case lays no piece.** Case 196 (README: "a set piece laid by quota, then its
   neighbour") reveals both chunks with `left[0]` still 1: its zone has no host above its masks
   (D-208), so the set-piece quota is never due. A host bit 225 on one chunk's mask would lay it.
   Mutants 70, 121.
2. Cases for each other survivor above, as written in its row: a chunk asked twice (54); an anchor
   on a corner (55); a mask that cuts a whole side facing a revealable neighbour, and a side drawn
   open under a partial mask (59, 64); a dungeon chunk revealed before its South neighbour, and an
   outline with two adjacent chunks and no seam between them (60, 61); an interior anchor off the
   spine, and one in a chunk whose centre is cut (67, 69, 90); sight (12, 9) and sight (0, 9)
   (75, 76); member(13, 11, false) (78); an odd-row chunk whose floor parity splits (88); a host bit
   with `left[i]` 0 (96); a dungeon chunk 3 or more from the entry with a chest or an offset-0 pack
   (100); a chunk farther than D (101); a Heart in the entry chunk or of offset 0 (103); pack
   templates of minimums 0 or maximums above 5 (104, 105); a fourth object and a third pack offered
   (112, 113); a spawn roll equal to the density (114).
3. **A carry in `generate`, to confirm as intended.** `inner = BoardTrait::or(inner,
   BoardTrait::pow(tile) + BoardTrait::anchor_line(tile))`: `anchor_line` already holds the
   anchor's own tile, so the sum doubles that bit and carries. For tile 112 (the dungeon's entry
   anchor) `inner` is bit 113, not 112; for a column-3 anchor the run 3–7 plus bit 3 is bit 8 alone.
   The spine hides it at 112; an anchor off the spine would not be joined to it. The mirror
   reproduces the carry (it decides no rule); `BoardTrait::or` instead of `+` would remove it.

Nothing the reveal needs is missing on `main`: every input is in the case.

## Time per chunk (Node)

Not committed (no pin): `bench/` is outside this lot's allowlist (escalated), so the measurement ran
from a scratch file, given here whole. The site of the table's first `reveal` case (a zone with its
spawn table and two pack templates), widened to 15 × 15 and revealed whole by index for each of the
four biomes, each chunk reading its revealed West and South neighbours; one `reveal` call a chunk,
timed alone; the first call left out of the median.

```ts
import { it } from "vitest";
import { readTable } from "<worktree>/client/sim/src/parity/table";
import { type Terrain, reveal, revealFromFelts } from "<worktree>/client/sim/src/reveal";

it("the reveal of a chunk", { timeout: 300_000 }, () => {
  const first = readTable("reveal.jsonl").find((vector) => vector.fn === "reveal")!;
  const samples: number[] = [];
  let cold = 0;
  for (let biome = 1; biome <= 4; biome++) {
    const [site, progress, instance] = revealFromFelts(first.case);
    Object.assign(site, { biome, width: 15, height: 15 });
    Object.assign(progress, { entropy: BigInt(biome), revealed: 0n, count: 0 });
    const known: [number, Terrain][] = [];
    for (let chunk = 0; chunk < 225; chunk++) {
      const start = performance.now();
      const [out] = reveal(site, progress, instance, known, [chunk]);
      const elapsed = (performance.now() - start) * 1000;
      if (biome === 1 && chunk === 0) cold = elapsed;
      else samples.push(elapsed);
      known.push([chunk, out!.terrain]);
    }
  }
  const sorted = [...samples].sort((a, b) => a - b);
  const at = (q: number) => sorted[Math.floor(sorted.length * q)]!;
  console.log(`reveal: median ${at(0.5).toFixed(0)} µs a chunk, p95 ${at(0.95).toFixed(0)} µs, ` +
    `min ${sorted[0]!.toFixed(0)} µs, max ${sorted.at(-1)!.toFixed(0)} µs (${samples.length} chunks); ` +
    `first call ${cold.toFixed(0)} µs`);
});
```

Command, from `client/sim`, the file in `<dir>`:
`prlimit --as=8589934592 -- /usr/bin/time -v npx vitest run --root <dir> --dir <dir> --silent=false`

Output (the VPS: AMD EPYC 9354P, 8 vCPUs, Node v24.21.0, `@scure/starknet` 1.1.0; load average 5
while other agents ran, so the figures are noisy):

```
reveal: median 3365 µs a chunk, p95 4463 µs, min 2161 µs, max 7818 µs (899 chunks: 4 biomes × 225 of a 15 × 15 zone, the first call left out); first call 9063 µs
Maximum resident set size (kbytes): 160384
```

A second run (no cap): median 3580 µs, p95 5291 µs, first call 10006 µs.

## Commands

```
pnpm --filter @grimworld/sim test        # 171 tests: the parity (197/197 reveal) and the mutation check
pnpm --filter @grimworld/sim lint
pnpm --filter @grimworld/sim typecheck
npx prettier --check client/sim
```

Memory, measured before the runs: the parity file under `prlimit --as=8589934592`, peak 172 MB. The
mutation check aborts under that cap at about 265 MB resident, and `main`'s own mutation check
aborts the same way: V8 reserves virtual memory that the address-space cap counts. It was measured
instead with Node's heap capped (`NODE_OPTIONS=--max-old-space-size=1024`): peak 500 MB, 46 s. The
whole package suite under the same heap cap: peak 496 MB, 50 s.

## Not changed

`contracts/**` (track game's), `client/app/**`, `bench/`, the other mirrors.
