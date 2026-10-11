// How strong are the vectors? Each mutant is the mirror with one mistake a hand-written mirror
// typically makes (SPK-4's `mutants.ts`), applied as a one-line text replacement to the mirror
// (FND-MUT: in a worker thread, from memory, `parity/mutate.ts`); the mutant replays every table
// and must diverge on at least one case, by its result or by throwing where Cairo returned. A throw
// that is a crash (a TypeError, a ReferenceError) kills only with a `crash` mark saying why it is
// the mutant's own divergence, not a broken mutant. A mutant no input tells from the mirror is
// marked `equivalent`: nothing may kill it, and it is no hole. A mutant the vectors do not kill is
// a hole in the vectors: it is reported to track game, never closed by editing a table here: it is
// listed with `survives` (what the tables lack), and this test then requires it to survive, so that
// the day the game's cases kill it the mark must go. A mutant that drops a refusal (`refusal`,
// CLI-02g-B1) is another kind: no row of any table records a panic of `GoblinTrait::load` or of
// `assert_awake`, so the tables cannot kill it, and this test requires that they do not; the unit
// tests' cases (`parity/refusals.ts`, the list `segment/goblin.test.ts` runs) must. A mutant of the
// seam of the classes (`seam`, CLI-02g-C) is the same: no row records an Illegal refusal whose call
// changed the ground, nor a class that mutates its inputs; `parity/seam.ts`' cases (the list
// `segment/unported.test.ts` runs) must kill it. So is a mutant of the trap class (`trap`,
// CLI-02g-D) that reads another goblin's caste than the placer's: the table's goblins share one
// caste; `parity/trapcases.ts`' cases (the list `trap.test.ts` runs) must kill it. 
import { readFileSync } from "node:fs";
import { availableParallelism } from "node:os";
import { Worker } from "node:worker_threads";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Job, Kill, Verdict } from "./mutate";

type Mutant = {
  name: string;
  file: string;
  from: string;
  to: string;
  survives?: string;
  /** A refusal no row records: the tables must not kill it, `parity/refusals.ts` must. */
  refusal?: true;
  /** A case of the seam no row records: the tables must not kill it, `parity/seam.ts` must. */
  seam?: true;
  /** A case of the trap class no row records: the tables must not kill it, `parity/trapcases.ts` must. */
  trap?: true;
  /**
   * Why its kill is a crash (a TypeError, a ReferenceError, a SyntaxError) and still the mutant's own
   * divergence: a crash of a mutant without it fails, as a broken copy, not a kill.
   */
  crash?: string;
  /**
   * Why no input tells it from the mirror: neither the tables nor any unit tests' cases may kill
   * it; not a hole of the tables, never reported to track game.
   */
  equivalent?: string;
};

const MUTANTS: readonly Mutant[] = [
  {
    name: "the line's tie across rows takes the higher index",
    file: "window.ts",
    from: "for (let r = r0 - 1; r <= r0 + 2 && chosen === undefined; r++) {",
    to: "for (let r = r0 - 1; r <= r0 + 2; r++) {",
  },
  {
    name: "the line's tie on a row takes the higher column",
    file: "window.ts",
    from: "          break;",
    to: "",
  },
  {
    name: "the facing turns the other way on a tie (the line's first step)",
    file: "window.ts",
    from: "moveQ = q > s || (q === s && qNegative);",
    to: "moveQ = q > s || (q === s && !qNegative);",
  },
  {
    name: "the arc's variant order (rear-side and back swapped)",
    file: "window.ts",
    from: "export const Arc = { Front: 0, FrontSide: 1, RearSide: 2, Back: 3 } as const;",
    to: "export const Arc = { Front: 0, FrontSide: 1, RearSide: 3, Back: 2 } as const;",
  },
  {
    name: "a wall at an end of the line does not block",
    file: "window.ts",
    from: "return [from, to, ...between].every(",
    to: "return between.every(",
  },
  {
    name: "FAR returned as the true distance outside the window",
    file: "window.ts",
    from: "if (!(inside(from) && inside(to))) return FAR;",
    to: "if (!(inside(from) && inside(to))) return length(delta(from, to));",
  },
  {
    name: "the shape not clipped to the window (a row wraps into the next)",
    file: "window.ts",
    from: "Math.min(last, WIDTH - 1)",
    to: "last",
  },
  {
    name: "reach's range off by one",
    file: "window.ts",
    from: "if (length(delta(from, to)) > u8(range)) return false;",
    to: "if (length(delta(from, to)) >= u8(range)) return false;",
  },
  {
    name: "the front tile's direction table (North-East read as North-West)",
    file: "window.ts",
    from: "  [-1, 1],",
    to: "  [0, 1],",
  },
  {
    name: "the window's origin row ignores the adventurer's row parity",
    file: "movement.ts",
    from: "const movedY = y + odd + 7;",
    to: "const movedY = y + 7;",
  },
  {
    name: "the window's origin off by one column",
    file: "movement.ts",
    from: "const moved = x + 8;",
    to: "const moved = x + 7;",
  },
  {
    name: "Crippled's deadline exclusive",
    file: "movement.ts",
    from: "return t0 <= crippled && !movement ? CRIPPLED_MOVE_TICKS : 1;",
    to: "return t0 < crippled && !movement ? CRIPPLED_MOVE_TICKS : 1;",
  },
  {
    name: "a MOVEMENT effect does not lift Crippled",
    file: "movement.ts",
    from: "return t0 <= crippled && !movement ? CRIPPLED_MOVE_TICKS : 1;",
    to: "return t0 <= crippled ? CRIPPLED_MOVE_TICKS : 1;",
  },
  {
    name: "the flood one layer past its cap",
    file: "movement.ts",
    from: "for (let count = depth - 1; ; count--) {",
    to: "for (let count = depth; ; count--) {",
  },
  {
    name: "a walker on the last layer at the cap gets a step (D-25)",
    file: "movement.ts",
    from: "if (k === flood.layers.length - 1 && capped(flood) && !source(flood, position)) return undefined;",
    to: "",
  },
  {
    name: "the flood's step takes the highest index on a tie",
    file: "movement.ts",
    from: "return tiles(set & -set)[0]!;",
    to: "return tiles(set).at(-1)!;",
  },
  {
    name: "the flood's distance is the neighbours' layer, not plus one",
    file: "movement.ts",
    from: "return found === undefined ? undefined : found[0] + 1;",
    to: "return found === undefined ? undefined : found[0];",
  },
  {
    name: "the flood walks the window's ring",
    file: "movement.ts",
    from: "let free = grid & INTERIOR & ~obstacles & ~bit(from);",
    to: "let free = grid & ~obstacles & ~bit(from);",
  },
  {
    name: "the awake set's ties by the highest entity",
    file: "movement.ts",
    from: "distances[i]! * 0x10000 + goblin.entity",
    to: "distances[i]! * 0x10000 + (0xffff - goblin.entity)",
  },
  {
    name: "a sleeping goblin joins the awake set",
    file: "movement.ts",
    from: "goblin.alive && !goblin.asleep ?",
    to: "goblin.alive ?",
  },
  {
    name: "an awake set of 9",
    file: "movement.ts",
    from: "export const MAX_AWAKE = 8;",
    to: "export const MAX_AWAKE = 9;",
  },
  {
    name: "a negative modifier applied as a delta truncated toward zero",
    file: "hit.ts",
    from: "const damage = (scaled * multiplier) / 100n;",
    to: "const damage = scaled + (scaled * percent) / 100n;",
  },
  {
    name: "modifiers applied in sequence instead of summed (D-140 #3)",
    file: "hit.ts",
    from: "const damage = (scaled * multiplier) / 100n;",
    to: "const damage = terms.reduce((d, t) => (d * (100n + t)) / 100n, scaled);",
  },
  {
    name: "the sum of the percents not floored at -100",
    file: "hit.ts",
    from: "const percent = sum < MIN_PERCENT ? MIN_PERCENT : sum;",
    to: "const percent = sum;",
  },
  {
    name: "armor not floored at 0",
    file: "hit.ts",
    from: "if (a <= 0n) return 0n;",
    to: "if (a <= 0n) return a;",
  },
  {
    name: "penetration not capped at 100",
    file: "hit.ts",
    from: "hit.penetration > PENETRATION_CAP ? PENETRATION_CAP : hit.penetration",
    to: "hit.penetration",
  },
  {
    name: "the hit not saturated at 65,535",
    file: "hit.ts",
    from: "return damage > MAX_DAMAGE ? MAX_DAMAGE : damage;",
    to: "return damage;",
  },
  {
    name: "a sleeping target blocks its first hit",
    file: "hit.ts",
    from: "&& front && open && !target.asleep)",
    to: "&& front && open)",
  },
  {
    name: "evasion takes ranged hits too",
    file: "hit.ts",
    from: "if (target.evade && hit.melee && open && !target.asleep)",
    to: "if (target.evade && open && !target.asleep)",
  },
  {
    name: "critical from the rear-side arc too",
    file: "hit.ts",
    from: "return hit.arc === Arc.Back ||",
    to: "return hit.arc >= Arc.RearSide ||",
  },
  {
    name: "the axe's bonus from every arc",
    file: "hit.ts",
    from: "(hit.arc === Arc.RearSide || hit.arc === Arc.Back)",
    to: "true",
  },
  {
    name: "the above-half guard holds at exactly half",
    file: "hit.ts",
    from: "if (hit.health * 2n > hit.max_health)",
    to: "if (hit.health * 2n >= hit.max_health)",
  },
  {
    name: "FX-19's halving triggers at exactly half after the hit",
    file: "hit.ts",
    from: "after * 2n < target.max_health",
    to: "after * 2n <= target.max_health",
  },
  {
    name: "a wrong domain separator (ENTRY's short string)",
    file: "fate.ts",
    from: 'export const ENTRY = shortString("fate:entry");',
    to: 'export const ENTRY = shortString("fate-entry");',
  },
  {
    name: "domain's argument order (counter and purpose swapped)",
    file: "fate.ts",
    from: "[feltArg(subject), feltArg(counter), feltArg(purpose)]",
    to: "[feltArg(subject), feltArg(purpose), feltArg(counter)]",
  },
  {
    name: "derive's argument order (word and domain swapped)",
    file: "fate.ts",
    from: "[feltArg(word), feltArg(domain), arg(u32, BigInt(index))]",
    to: "[feltArg(domain), feltArg(word), arg(u32, BigInt(index))]",
  },
  {
    name: "derive drops its index (one value per domain)",
    file: "fate.ts",
    from: "[feltArg(word), feltArg(domain), arg(u32, BigInt(index))]",
    to: "[feltArg(word), feltArg(domain)]",
  },
  {
    name: "split's boundary off by one (a high limb of exactly LIVE kept)",
    file: "packing.ts",
    from: "return high < LIVE_HIGH ? [low, high] : [low, high - LIVE_HIGH];",
    to: "return high <= LIVE_HIGH ? [low, high] : [low, high - LIVE_HIGH];",
  },
  {
    name: "limbs' subtraction not wrapped modulo P",
    file: "packing.ts",
    from: "return wide((((feltArg(word) - LIVE) % P) + P) % P);",
    to: "return wide(feltArg(word) - LIVE);",
  },
  {
    name: "join accepts a high limb of exactly 2^122",
    file: "packing.ts",
    from: "if (arg(u128, high) >= LIVE_HIGH) panic(errors.HIGH);",
    to: "if (arg(u128, high) > LIVE_HIGH) panic(errors.HIGH);",
  },
  {
    name: "peel returns the quotient as the field",
    file: "packing.ts",
    from: "return [arg(u128, rest) % size, rest / size];",
    to: "return [arg(u128, rest) / size, rest % size];",
  },
  {
    name: "fits accepts a value equal to its size",
    file: "packing.ts",
    from: "if (!(arg(u128, value) < arg(u128, size))) panic(message);",
    to: "if (!(arg(u128, value) <= arg(u128, size))) panic(message);",
  },
  {
    name: "field reads the size before the shift",
    file: "packing.ts",
    from: "return (limb / toNonZero(shift)) % toNonZero(size);",
    to: "return (limb % toNonZero(size)) / toNonZero(shift);",
  },
  {
    name: "a lane width of 15 bits when packing Lanes16",
    file: "packing.ts",
    from: "if (i < 8) low += lane * P16 ** BigInt(i);",
    to: "if (i < 8) low += lane * 2n ** (15n * BigInt(i));",
  },
  {
    name: "Lanes16's high limb starting at lane 7",
    file: "packing.ts",
    from: "if (i < 8) low += lane * P16 ** BigInt(i);\n    else high += lane * P16 ** BigInt(i - 8);",
    to: "if (i < 7) low += lane * P16 ** BigInt(i);\n    else high += lane * P16 ** BigInt(i - 7);",
  },
  {
    name: "Lanes32's lane 3 not packed",
    file: "packing.ts",
    from: "const low = a + b * P32 + c * P32 ** 2n + d * P32 ** 3n;",
    to: "const low = a + b * P32 + c * P32 ** 2n + 0n * d;",
  },
  {
    name: "the Bitmap's limbs in the wrong order",
    file: "packing.ts",
    from: "return { bits: low + high * TWO_POW_128 };",
    to: "return { bits: high + low * TWO_POW_128 };",
  },
  {
    name: "the Bitmap's guard at bit 251 instead of 250",
    file: "packing.ts",
    from: "if (high >= LIVE_HIGH) panic(errors.BITMAP);",
    to: "if (high >= 2n * LIVE_HIGH) panic(errors.BITMAP);",
  },
  {
    name: "a Counter overflow not refused (unpack reads the low limb unchecked)",
    file: "packing.ts",
    from: "return { value: narrow(u64, low) };",
    to: "return { value: low };",
    survives:
      "no unpack_counter word has a low limb above u64::MAX (the table records no panic data, so such a row needs an `err` field)",
  },
  {
    name: "a chunk's word from the wrong derive index",
    file: "reveal.ts",
    from: "return derive(entropy, domain(instance_id, BigInt(chunk), REVEAL), 0);",
    to: "return derive(entropy, domain(instance_id, BigInt(chunk), REVEAL), 1);",
  },
  {
    name: "feed hashes the entropy with the fact instead of adding it",
    file: "reveal.ts",
    from: "return felt(feltArg(entropy) + poseidonHashMany(fact.map(feltArg)));",
    to: "return poseidonHashMany([entropy, ...fact].map(feltArg));",
  },
  {
    name: "a dungeon's seam streams seeded by the hosts' word (chunk 225, not 227)",
    file: "reveal.ts",
    from: "return word(entropy, instance_id, 227);",
    to: "return word(entropy, instance_id, 225);",
  },
  {
    name: "a chunk outside the zone's chunk set revealed (D-134's void chunks)",
    file: "reveal.ts",
    from: "return site.chunk_set === 0n || has(site.chunk_set, chunk);",
    to: "return true;",
  },
  {
    name: "a revealed chunk revealed again",
    file: "reveal.ts",
    from: "return !has(progress.revealed, chunk) && inside(site, chunk);",
    to: "return inside(site, chunk);",
  },
  {
    name: "an anchor on a corner opened (D-134)",
    file: "reveal.ts",
    from: "return tile === 0 || tile === 14 || tile === 210 || tile === 224;",
    to: "return false;",
  },
  {
    name: "a copied side takes the neighbour's same side, not its facing one",
    file: "reveal.ts",
    from: "ring = felt(ring + copy(at, floor(terrain.walls)));",
    to: "ring = felt(ring + copy(opposite(at), floor(terrain.walls)));",
  },
  {
    name: "a copied edge reads the neighbour's same edge, not the facing one",
    file: "reveal.ts",
    from: "if (isOpen(terrain.edges, opposite(at))) edges += pow2(at);",
    to: "if (isOpen(terrain.edges, at)) edges += pow2(at);",
  },
  {
    name: "ENG-05's unread border draw dropped (the ring's stream moves)",
    file: "reveal.ts",
    from: "      draw(draws, BORDER);\n",
    to: "",
  },
  {
    name: "a side the mask cuts whole still drawn open",
    file: "reveal.ts",
    from: "if ((sideMask(at) & tiles) !== 0n && (!emerging || seam(site, chunk, at, next))) {",
    to: "if (!emerging || seam(site, chunk, at, next)) {",
  },
  {
    name: "a dungeon side open whatever its seam",
    file: "reveal.ts",
    from: "(!emerging || seam(site, chunk, at, next))",
    to: "true",
  },
  {
    name: "a South seam keyed on the West axis (D-224)",
    file: "reveal.ts",
    from: "        [chunk - 15, 1],",
    to: "        [chunk - 15, 0],",
  },
  {
    name: "a dungeon seam's openings from the chunk's stream (D-224)",
    file: "reveal.ts",
    from: "const stream = rngNew(poseidonHashMany([seams, BigInt(low!), BigInt(axis!)]));",
    to: "const stream = draws;",
  },
  {
    name: "one opening a side, never two",
    file: "reveal.ts",
    from: "if (two) ring = ring | pow(opening(allowed, at, draws));",
    to: "",
  },
  {
    name: "an opening drawn once before the exact draw",
    file: "reveal.ts",
    from: "for (let tries = 0; tries < TRIES; tries++) {",
    to: "for (let tries = 0; tries < 1; tries++) {",
  },
  {
    name: "an opening drawn on a corner (D-134)",
    file: "reveal.ts",
    from: "const tile = first + step * (1 + draw(draws, 13));",
    to: "const tile = first + step * draw(draws, 13);",
  },
  {
    name: "a zone chunk writes its edges",
    file: "reveal.ts",
    from: "edges: site.target !== 0 ? edges : 0,",
    to: "edges,",
  },
  {
    name: "an interior anchor not joined to the spine",
    file: "reveal.ts",
    from: "inner = inner | anchor_line(tile);",
    to: "inner = inner | pow(tile);",
  },
  {
    name: "an anchor on the ring not opened",
    file: "reveal.ts",
    from: "      ring = ring | pow(tile);\n",
    to: "",
  },
  {
    name: "the flood's source not the first interior anchor when the centre is wall",
    file: "reveal.ts",
    from: "return anchors.find((tile) => has(interior, tile));",
    to: "return undefined;",
  },
  {
    name: "a set piece's walls ignored (the base generated)",
    file: "reveal.ts",
    from: "? floor(set[1].walls) & INTERIOR",
    to: "? smoothChunk(felt(base(chunkWord, site.biome) + ring), odd) & INTERIOR",
  },
  {
    name: "the cut by the zone's tile mask skipped",
    file: "reveal.ts",
    from: "const kept = cut(felt(grid + ring), tiles);",
    to: "const kept = felt(grid + ring);",
  },
  {
    name: "the centre's component not kept",
    file: "reveal.ts",
    from: "if (source !== undefined) floorTiles = component(floorTiles, source, odd);",
    to: "",
  },
  {
    name: "a revealed chunk not recorded in the progress",
    file: "reveal.ts",
    from: "progress.revealed = felt(progress.revealed + pow(chunk));",
    to: "",
  },
  {
    name: "a chunk revealed in a call not known to the next ones",
    file: "reveal.ts",
    from: "terrains.push([chunk, revealed.terrain]);",
    to: "",
  },
  {
    name: "sight's chunk columns shifted by the near row, not the tile's",
    file: "reveal.ts",
    from: "const left = column * 15 + 6 + Math.floor(y / 2);",
    to: "const left = column * 15 + 6 + Math.floor(nearY / 2);",
  },
  {
    name: "sight's hexagon of radius 5 across rows",
    file: "reveal.ts",
    from: "if (dr > 12) return false;",
    to: "if (dr > 10) return false;",
  },
  {
    name: "a goblin's tile ignores the row's parity",
    file: "reveal.ts",
    from: "const half = odd ? Math.floor((dr + 1) / 2) : Math.floor(dr / 2);",
    to: "const half = Math.floor(dr / 2);",
  },
  {
    name: "a member one column past the chunk's side kept",
    file: "reveal.ts",
    from: "if (x < 3 || x > 17 || y < 2 || y > 16) return undefined;",
    to: "if (x < 3 || x > 18 || y < 2 || y > 16) return undefined;",
  },
  {
    name: "meadow at the cave's density",
    file: "reveal/board.ts",
    from: "fill = a | (b & c);",
    to: "fill = a & (b | c);",
  },
  {
    name: "forest without its fifth bitmap",
    file: "reveal/board.ts",
    from: "fill = a & (b | c | (d | e));",
    to: "fill = a & (b | c | d);",
  },
  {
    name: "ruin at the cave's density",
    file: "reveal/board.ts",
    from: "fill = a & (b | (c & d));",
    to: "fill = a & (b | c);",
  },
  {
    name: "the base's second permutation from the first's input",
    file: "reveal/board.ts",
    from: "const [d, e] = hades(word, 1n, 2n);",
    to: "const [d, e] = hades(word, 0n, 2n);",
  },
  {
    name: "the base not restricted to the interior",
    file: "reveal/board.ts",
    from: "return felt(fill & INTERIOR);",
    to: "return felt(fill & BOARD);",
  },
  {
    name: "the smoothing ignores the chunk's global row parity",
    file: "reveal/board.ts",
    from: "return smooth(grid, 15, 15, GENERATIONS, 0n, odd);",
    to: "return smooth(grid, 15, 15, GENERATIONS, 0n, false);",
  },
  {
    name: "two generations of the automaton",
    file: "reveal/board.ts",
    from: "export const GENERATIONS = 1;",
    to: "export const GENERATIONS = 2;",
  },
  {
    name: "the spine not laid",
    file: "reveal/board.ts",
    from: "return felt(east | west | (south | north) | SPINE);",
    to: "return felt(east | west | (south | north));",
  },
  {
    name: "a West opening's line one tile short of the spine",
    file: "reveal/board.ts",
    from: "const west = felt(felt((ring & WEST) * INV_7) * 0x7fn);",
    to: "const west = felt(felt((ring & WEST) * INV_7) * 0x3fn);",
  },
  {
    name: "an odd chunk flooded on the even layout",
    file: "reveal/board.ts",
    from: "? [felt(interior * ROW_UP), 16, root + 15, INV_15]",
    to: "? [interior, 15, root, 1n]",
  },
  {
    name: "placement allowed at 2 from an opening (one dilation)",
    file: "reveal/board.ts",
    from: "return dilate(dilate(tiles, odd), odd);",
    to: "return dilate(tiles, odd);",
  },
  {
    name: "the interior anchors not kept clear of placement",
    file: "reveal/board.ts",
    from: "for (const tile of anchors) tiles = tiles | pow(tile);",
    to: "",
  },
  {
    name: "the dilation ignores the chunk's global row parity",
    file: "reveal/board.ts",
    from: "const [evenRows, oddRows] = odd ? [ODD_ROWS, EVEN_ROWS] : [EVEN_ROWS, ODD_ROWS];",
    to: "const [evenRows, oddRows] = [EVEN_ROWS, ODD_ROWS];",
  },
  {
    name: "every floor tile survives the automaton (no S2)",
    file: "hexx.ts",
    from: "return (c12 + x3) | survive;",
    to: "return (c12 + x3) | grid;",
  },
  {
    name: "a wall born with 2 floor neighbours (B2, not B4)",
    file: "hexx.ts",
    from: "return (c12 + x3) | survive;",
    to: "return (c12 + x3) | b1;",
  },
  {
    name: "the pool refilled below 2^63, not 2^64",
    file: "hexx.ts",
    from: "if (rng.pool < TWO_POW_64) refill(rng);",
    to: "if (rng.pool < TWO_POW_64 / 2n) refill(rng);",
  },
  {
    name: "a quota laid off its hosts (D-208)",
    file: "reveal/placement.ts",
    from: "if (left[i] !== 0 && has(mask, host)) due += bit;",
    to: "if (left[i] !== 0) due += bit;",
  },
  {
    name: "a quota with nothing left laid again",
    file: "reveal/placement.ts",
    from: "if (left[i] !== 0 && has(mask, host)) due += bit;",
    to: "if (has(mask, host)) due += bit;",
    survives:
      "no legal input: a host cannot be unrevealed while `left` is 0 (hosts are drawn at most `count`, and PlayLibrary zeroes the hosts it spent, CBT-05g)",
  },
  {
    name: "the quotas placed not spent",
    file: "reveal/placement.ts",
    from: "return left.map((value, i) => u8sub(value, (placed >> i) & 1));",
    to: "return [...left];",
  },
  {
    name: "a task's landmark not placed",
    file: "reveal/placement.ts",
    from: "return task.kind === CRITERION_REACH_LANDMARK ? [quota.LANDMARK, task.param] : [0, 0];",
    to: "return [0, 0];",
  },
  {
    name: "the band's distance Chebyshev, not Manhattan",
    file: "reveal/placement.ts",
    from: "const distance = Math.abs(cx - ex) + Math.abs(cy - ey);",
    to: "const distance = Math.max(Math.abs(cx - ex), Math.abs(cy - ey));",
  },
  {
    name: "a dungeon's band over its rectangle, not N - 1",
    file: "reveal/placement.ts",
    from: "const far = site.target !== 0 ? site.target - 1 : site.width + site.height - 2;",
    to: "const far = site.width + site.height - 2;",
  },
  {
    name: "the band's distance not held at D",
    file: "reveal/placement.ts",
    from: "const held = Math.min(distance, far);",
    to: "const held = distance;",
    survives:
      "no legal input: it needs an entry chunk outside the rectangle, which ENG-R1c's content rule makes illegal; R-41 (ENG-R1c-1) refuses such a gate on the content side",
  },
  {
    name: "a pack's level not held in the location's band",
    file: "reveal/placement.ts",
    from: "return Math.min(Math.max(sum, site.level_min), site.level_max);",
    to: "return sum;",
  },
  {
    name: "a Heart's pack at the band's level, not its top (D-208)",
    file: "reveal/placement.ts",
    from: "    else if (kind === quota.HEART) {\n      const band = placement.level;\n      placement.level = site.level_max;",
    to: "    else if (kind === quota.HEART) {\n      const band = placement.level;",
  },
  {
    name: "a pack drawn empty (no floor of one goblin)",
    file: "reveal/placement.ts",
    from: "const low = floor === 0 ? 1 : floor;",
    to: "const low = floor;",
  },
  {
    name: "a pack's size capped above 5",
    file: "reveal/placement.ts",
    from: "high = Math.min(high, MAX_PACK_SIZE);",
    to: "",
  },
  {
    name: "a pack always at its largest size",
    file: "reveal/placement.ts",
    from: "const size = u8add(low, draw(rng, u8sub(high, low) + 1));",
    to: "const size = high;",
  },
  {
    name: "a goblin's row parity local, not global",
    file: "reveal/placement.ts",
    from: "const odd = (row % 2 === 1) !== placement.odd;",
    to: "const odd = row % 2 === 1;",
  },
  {
    name: "goblin 0 not on the pack's tile (offset 9)",
    file: "reveal/placement.ts",
    from: "let offsets = 9n;",
    to: "let offsets = 0n;",
  },
  {
    name: "a goblin's offset index one row off",
    file: "reveal/placement.ts",
    from: "const start = [1, 5, 10, 15][dr] ?? 19;",
    to: "const start = [0, 4, 9, 14][dr] ?? 18;",
  },
  {
    name: "every pack asleep, its alert not drawn",
    file: "reveal/placement.ts",
    from: "const alert = draw(rng, 2);",
    to: "const alert = 0;",
  },
  {
    name: "a tile drawn once before the exact draw",
    file: "reveal/placement.ts",
    from: "for (let tries = 0; found === undefined && tries < TRIES; tries++) {",
    to: "for (let tries = 0; found === undefined && tries < 1; tries++) {",
  },
  {
    name: "a fourth object in a chunk (E-3)",
    file: "reveal/placement.ts",
    from: "if (placement.objects.length >= MAX_OBJECTS_PER_CHUNK) return false;",
    to: "if (placement.objects.length > MAX_OBJECTS_PER_CHUNK) return false;",
    survives:
      "no legal input: a fourth object cannot arise (features() keeps 3 objects, and the hosts' caps keep quota objects off a full set-piece chunk)",
  },
  {
    name: "a third pack in a chunk (E-3)",
    file: "reveal/placement.ts",
    from: "if (placement.packs.length >= MAX_PACKS_PER_CHUNK) return false;",
    to: "if (placement.packs.length > MAX_PACKS_PER_CHUNK) return false;",
  },
  {
    name: "a spawn roll equal to the density places",
    file: "reveal/placement.ts",
    from: "if (total !== 0 && roll < site.spawn.density) {",
    to: "if (total !== 0 && roll <= site.spawn.density) {",
  },
  {
    name: "the spawn's template not drawn by weight",
    file: "reveal/placement.ts",
    from: "const picked = total === 0 ? 0 : draw(rng, total);",
    to: "const picked = 0;",
  },
  {
    name: "a chest 1 chunk in 5",
    file: "reveal/placement.ts",
    from: "const chest = draw(rng, 6) === 0;",
    to: "const chest = draw(rng, 5) === 0;",
  },
  {
    name: "a chest's param not the band's level",
    file: "reveal/placement.ts",
    from: "if (chest) placeObject(placement, rng, object.CHEST, placement.level);",
    to: "if (chest) placeObject(placement, rng, object.CHEST, 0);",
  },
  {
    name: "a gathering node in a dungeon",
    file: "reveal/placement.ts",
    from: "if (node && site.target === 0) placeObject(placement, rng, object.NODE, 0);",
    to: "if (node) placeObject(placement, rng, object.NODE, 0);",
  },
  {
    name: "a terrain trap in a meadow or a forest",
    file: "reveal/placement.ts",
    from: "if (trap && (site.biome === RUIN || site.biome === CAVE)) {",
    to: "if (trap) {",
  },
  {
    name: "a dungeon's exit drawn among every allowed tile, not the core",
    file: "reveal/placement.ts",
    from: "      placement.allowed = core;\n",
    to: "",
  },
  {
    name: "a set piece's quota not spent",
    file: "reveal/placement.ts",
    from: "    placement.placed += bit(pieceSlot);\n",
    to: "",
  },
  {
    name: "a signed felt decoded as unsigned",
    file: "felt.ts",
    from: "const value = type.min < 0n && felt > P / 2n ? felt - P : felt;",
    to: "const value = felt;",
  },
  {
    name: "the table's clamp removed",
    file: "exp2.ts",
    from: "const clamped = Math.min(Math.max(x, EXP2_LOW), EXP2_HIGH);",
    to: "const clamped = x;",
    crash: "an exponent outside the table reads past it: a TypeError where Cairo clamps",
  },
  {
    name: "E-16's cap of 17 records",
    file: "batch.ts",
    from: "export const MAX_RECORDS = 16;",
    to: "export const MAX_RECORDS = 17;",
  },
  {
    name: "the 16th record cut (the cap exclusive)",
    file: "batch.ts",
    from: "BigInt(fresh))) > MAX_RECORDS",
    to: "BigInt(fresh))) >= MAX_RECORDS",
  },
  {
    name: "a first record weighs nothing more (no +1)",
    file: "batch.ts",
    from: "const total = Number(add(u8, BigInt(cost), BigInt(firsts)));",
    to: "const total = cost;",
  },
  {
    name: "the invocation's first action is bound too (E-21)",
    file: "batch.ts",
    from: "if (ran && (Number(",
    to: "if ((Number(",
  },
  {
    name: "a Move's owed ticks are not counted with the next action",
    file: "parity/tables.ts",
    from: "Number(owed! + fresh!),",
    to: "Number(fresh!),",
  },
  {
    name: "a reveal's weight is taken before the Move, not after",
    file: "parity/tables.ts",
    from: "revealed(after, Number(chunks!))",
    to: "revealed(small(weight!), Number(chunks!))",
  },
  {
    name: "a reveal weighs 3 a chunk",
    file: "batch.ts",
    from: "export const CHUNK_WEIGHT = 2;",
    to: "export const CHUNK_WEIGHT = 3;",
  },
  {
    name: "a reveal's weight is not floored at 0",
    file: "batch.ts",
    from: "return weight > cost ? weight - cost : 0;",
    to: "return weight - cost;",
  },
  {
    name: "E-1's weight stop dropped from admit",
    file: "batch.ts",
    from: "|| total > weight)) {",
    to: ")) {",
  },
  {
    name: "the owed ticks of the last Move are not run first",
    file: "segment.ts",
    from: "  ticks(world, rules, segment.owed);\n",
    to: "",
  },
  {
    name: "a reveal Move's ticks run in this segment",
    file: "segment.ts",
    from: "    if (!reveal) ticks(world, rules, n);",
    to: "    ticks(world, rules, n);",
  },
  {
    name: "the window does not follow a Move that reveals nothing",
    file: "segment.ts",
    from: "        rules.board = board(area, at.x, at.y);\n",
    to: "",
  },
  {
    name: "a Move into another chunk does not end the segment",
    file: "segment.ts",
    from: "reveal = to_reveal(area, world) || chunk(world) !== start;",
    to: "reveal = to_reveal(area, world);",
  },
  {
    name: "sight onto an unrevealed chunk does not end the segment",
    file: "segment.ts",
    from: "reveal = to_reveal(area, world) || chunk(world) !== start;",
    to: "reveal = chunk(world) !== start;",
  },
  {
    name: "the actions after a reveal Move run",
    file: "segment.ts",
    from: "      done.reveal = true;\n      break;",
    to: "      done.reveal = true;",
  },
  {
    name: "a reveal Move's owed ticks are not returned",
    file: "segment.ts",
    from: "      done.owed = n;",
    to: "      done.owed = 0;",
  },
  {
    name: "a Turn costs its 0 ticks, not max(1, ticks)",
    file: "segment.ts",
    from: "const cost = n === 0 ? 1 : n;",
    to: "const cost = n;",
  },
  {
    name: "run's cost > weight check dropped (a Wait over the weight runs)",
    file: "segment.ts",
    from: "    if (cost > done.weight) {\n      done.heavy = true;\n      break;\n    }\n",
    to: "",
  },
  {
    name: "turn's weight check dropped (a Turn at weight 0 is written)",
    file: "segment.ts",
    from: '  if (weight === 0) return { halt: "heavy" };\n',
    to: "",
  },
  {
    name: "step's weight check dropped (a Move over the weight is written)",
    file: "segment.ts",
    from: '  if (n > weight) return { halt: "heavy" };\n',
    to: "",
  },
  {
    name: "ran ignores the invocation's earlier segments",
    file: "segment.ts",
    from: "const ran = area.ran || done.played > 0;",
    to: "const ran = done.played > 0;",
  },
  {
    name: "ran ignores the actions played in this segment",
    file: "segment.ts",
    from: "const ran = area.ran || done.played > 0;",
    to: "const ran = area.ran;",
  },
  {
    name: "fits ignores the records of the earlier segments",
    file: "segment.ts",
    from: "admit(changed.length, fresh.length, firsts, cost, ran, weight)",
    to: "admit(0, fresh.length, firsts, cost, ran, weight)",
  },
  {
    name: "fits' refusal does not ask to undo",
    file: "segment.ts",
    from: "      done.undo = true;\n",
    to: "",
  },
  {
    name: "LAST_TICK one later (Clock)",
    file: "segment.ts",
    from: "export const LAST_TICK = 0xfffffff - 0xffff - 10;",
    to: "export const LAST_TICK = 0xfffffff - 0xffff - 9;",
  },
  {
    name: "a Move past LAST_TICK is legal (Clock)",
    file: "segment.ts",
    from: "  if (c > LAST_TICK) return { halt: { illegal: Illegal.Clock } };\n",
    to: "",
  },
  {
    name: "a Turn past LAST_TICK is legal (Clock)",
    file: "segment.ts",
    from: '  if (weight === 0) return { halt: "heavy" };\n  if (world.clock > LAST_TICK) return { halt: { illegal: Illegal.Clock } };',
    to: '  if (weight === 0) return { halt: "heavy" };',
  },
  {
    name: "a Wait past LAST_TICK is legal (Clock)",
    file: "segment.ts",
    from: "function wait(world: World): Result {\n  if (world.clock > LAST_TICK) return { halt: { illegal: Illegal.Clock } };\n",
    to: "function wait(world: World): Result {\n",
  },
  {
    name: "an adventurer at 0 health is alive (Absent)",
    file: "segment/words.ts",
    from: "member.status === 0 && member.health > 0;",
    to: "member.status === 0;",
  },
  {
    name: "an adventurer down is alive (Absent)",
    file: "segment/words.ts",
    from: "member.status === 0 && member.health > 0;",
    to: "member.health > 0;",
  },
  {
    name: "a knocked-down Move is legal (Knocked)",
    file: "segment.ts",
    from: "  if (!can_act(member, t0)) return { halt: { illegal: Illegal.Knocked } };\n",
    to: "",
  },
  {
    name: "a knocked-down Turn is legal (Knocked)",
    file: "segment.ts",
    from: "  if (!can_act(member, u32add(world.clock, 1))) return { halt: { illegal: Illegal.Knocked } };\n",
    to: "",
  },
  {
    name: "a knocked-down Wait is refused (Knocked)",
    file: "segment.ts",
    from: "  if (!is_alive(adventurer(world))) return { halt: { illegal: Illegal.Absent } };\n  return { ticks: 1 };",
    to: "  if (!is_alive(adventurer(world))) return { halt: { illegal: Illegal.Absent } };\n  if (!can_act(adventurer(world), u32add(world.clock, 1))) return { halt: { illegal: Illegal.Knocked } };\n  return { ticks: 1 };",
  },
  {
    name: "a Move onto a wall is legal (Blocked)",
    file: "segment.ts",
    from: "shape(on.open, shapes.SINGLE, to) === 0n || occupied(world, on, to)",
    to: "occupied(world, on, to)",
  },
  {
    name: "a second Turn between two ticks is legal (Turned)",
    file: "segment.ts",
    from: "  if ((member.flags & flag.TURNED) !== 0) return { halt: { illegal: Illegal.Turned } };\n",
    to: "",
  },
  {
    name: "a tick does not clear the turned flag",
    file: "segment.ts",
    from: "      for (const member of world.members) member.flags &= KEPT;\n",
    to: "",
  },
  {
    name: "Interact runs as a Wait (Kind)",
    file: "segment.ts",
    from: "        result = { halt: { illegal: Illegal.Kind } };",
    to: "        result = wait(world);",
  },
  {
    name: "Illegal's Serde index of Blocked off by one",
    file: "segment/serde.ts",
    from: "  Blocked: 14,",
    to: "  Blocked: 15,",
  },
  {
    name: "a defeated world runs the next action (defeated)",
    file: "segment.ts",
    from: "    if (world.defeated) break;\n",
    to: "",
  },
  {
    name: "a member down is not defeated (defeated)",
    file: "segment.ts",
    from: "  world.defeated = true;\n}",
    to: "  world.defeated = false;\n}",
  },
  {
    name: "a Move onto a living actor is legal (occupied)",
    file: "segment.ts",
    from: "shape(on.open, shapes.SINGLE, to) === 0n || occupied(world, on, to)",
    to: "shape(on.open, shapes.SINGLE, to) === 0n",
  },
  {
    name: "a dead goblin is alive (occupied, idle)",
    file: "segment.ts",
    from: "world.goblins.filter(is_goblin_alive)",
    to: "world.goblins.filter(() => true)",
  },
  {
    name: "a companion does not block a Move (companions)",
    file: "trap.ts",
    from: "    if (is_alive(member) && boardPosition(board, x, y) === position) return true;",
    to: "    if (member === world.members[0] && boardPosition(board, x, y) === position) return true;",
  },
  {
    name: "a companion down blocks a Move (companions)",
    file: "trap.ts",
    from: "    if (is_alive(member) && boardPosition(board, x, y) === position) return true;",
    to: "    if (boardPosition(board, x, y) === position) return true;",
  },
  {
    name: "only the adventurer regenerates on the fast path (companions)",
    file: "segment.ts",
    from: "      for (const member of world.members) {\n        if (member.status === status.INSIDE",
    to: "      for (const member of world.members.slice(0, 1)) {\n        if (member.status === status.INSIDE",
  },
  {
    name: "health regeneration ignored on the fast path (regeneration)",
    file: "segment/tick.ts",
    from: "let pips = member.health_regen + degeneration(",
    to: "let pips = 0 + degeneration(",
  },
  {
    name: "health regenerates past its max (regeneration)",
    file: "segment/tick.ts",
    from: "  return Math.min(health + change, max);",
    to: "  return health + change;",
  },
  {
    name: "Bleeding ends a tick early (regeneration)",
    file: "segment/tick.ts",
    from: "  if (t <= bleeding) pips -= 3;",
    to: "  if (t < bleeding) pips -= 3;",
  },
  {
    name: "energy does not regenerate on the fast path (regeneration)",
    file: "segment/tick.ts",
    from: "  member.energy = Math.min(u16add(member.energy, member.energy_regen), member.max_energy);\n",
    to: "",
  },
  {
    name: "adrenaline does not decay on the fast path (regeneration)",
    file: "segment/tick.ts",
    from: "  if (!engaged) member.adrenaline = decay(member.adrenaline);\n",
    to: "",
    survives:
      "no row ticks the fast path with a member's adrenaline above 0 (the fixture's member holds none, and no class call leaves one before a fast-path tick)",
  },
  {
    name: "a held MOVEMENT effect is ignored (movement)",
    file: "segment.ts",
    from: "move_ticks(crippled(member), t0, movement(member, rules.sheets, c))",
    to: "move_ticks(crippled(member), t0, false)",
  },
  {
    name: "a MOVEMENT effect held through its deadline (movement)",
    file: "segment.ts",
    from: "c < effect.deadline",
    to: "c <= effect.deadline",
  },
  {
    name: "the trap of the tile entered is not triggered (trap)",
    file: "segment.ts",
    from: "  trap(world, rules, to);\n",
    to: "",
  },
  {
    name: "a used trap triggers (trap)",
    file: "segment.ts",
    from: "object.state === 0 && object.tile === tile",
    to: "object.tile === tile",
  },
  {
    name: "a placed trap's goblin is not sent with the call (trap)",
    file: "segment.ts",
    from: "const goblins = index < 0 ? [] : [storeGoblin(world.goblins[index]!)];",
    to: "const goblins: never[] = [];",
  },
  {
    name: "a goblin in the window keeps the fast path (ticks)",
    file: "segment.ts",
    from: "    return position(on, x, y) >= FAR;",
    to: "    return true;",
  },
  {
    name: "a goblin awake outside the window keeps the fast path (ticks)",
    file: "segment.ts",
    from: "  world.goblins.every((goblin) => !goblin.awake) &&\n",
    to: "",
  },
  {
    name: "the ticks call is sent 1 tick whatever n (a digest)",
    file: "segment.ts",
    from: "    ground: copyGround(rules.ground),\n    n,\n",
    to: "    ground: copyGround(rules.ground),\n    n: 1,\n",
  },
  {
    name: "the act call is sent a Wait (a digest)",
    file: "segment.ts",
    from: "    ground: copyGround(rules.ground),\n    action,\n",
    to: '    ground: copyGround(rules.ground),\n    action: { kind: "wait" },\n',
  },
  {
    name: "an action's 0 ticks with no weight left run (combat)",
    file: "segment.ts",
    from: " || (out.outcome.ticks === 0 && weight === 0)",
    to: "",
  },
  {
    name: "a Heavy refusal keeps ActionLibrary's ground (combat)",
    file: "segment.ts",
    from: '    result = { halt: "heavy" };\n',
    to: '    rules.ground = out.ground;\n    result = { halt: "heavy" };\n',
  },
  {
    name: "a combat action over the weight is kept (combat)",
    file: "segment.ts",
    from: "  } else if (out.outcome.ticks > weight ||",
    to: "  } else if (false ||",
  },
  {
    name: "an untouched goblin engaged and nothing else is counted (fits)",
    file: "segment.ts",
    from: "    if (untouched && engaged) return;\n",
    to: "",
  },
  {
    name: "a first record weighs nothing more (fits)",
    file: "segment.ts",
    from: "    if (untouched) firsts = u8add(firsts, 1);\n",
    to: "",
  },
  {
    name: "fits compares with the goblins before the segment (fits)",
    file: "segment.ts",
    from: "    before = fit.after;\n",
    to: "",
    survives:
      "no row changes a goblin twice in a segment that one action left unrecorded (an untouched goblin engaged and nothing else, row 22's 249, which no later action changes): every other goblin changed is in `changed` already",
  },
  {
    name: "a caste missing from the content is not refused (NO_CASTE)",
    file: "segment/words.ts",
    from: "  if (at === undefined) panic(errors.NO_CASTE);\n",
    to: "",
    crash: "the missing caste is read all the same: a TypeError where Cairo refuses",
    refusal: true,
  },
  {
    name: "a caste skill missing from the content is not refused (assert_kit)",
    file: "segment/goblin.ts",
    from: "  assert_kit(sheets.kits[caste_at]!);\n",
    to: "",
    refusal: true,
  },
  {
    name: "more than 8 awake goblins are not refused (assert_awake)",
    file: "segment/world.ts",
    from: "  assert_awake(goblins.flatMap((goblin, at) => (goblin.awake ? [at] : [])));\n",
    to: "",
    refusal: true,
  },
  {
    name: "a regeneration above an i8 is not refused (assert_pips)",
    file: "segment/goblin.ts",
    from: "  assert_pips(effect_regen);\n",
    to: "",
    refusal: true,
  },
  {
    name: "the line rounds down, not toward zero",
    file: "effect.ts",
    from: "return v0 + Math.trunc(((v12 - v0) * rank) / 12);",
    to: "return v0 + Math.floor(((v12 - v0) * rank) / 12);",
  },
  {
    name: "the line takes rank 15 as past MAX_RANK",
    file: "effect.ts",
    from: "  if (!(rank <= MAX_RANK)) panic(errors.RANK);\n  return v0",
    to: "  if (!(rank < MAX_RANK)) panic(errors.RANK);\n  return v0",
  },
  {
    name: "the duration's line rounds down, not toward zero",
    file: "effect.ts",
    from: "return entry.d0 + Math.trunc(((entry.d12 - entry.d0) * rank) / 12);",
    to: "return entry.d0 + Math.floor(((entry.d12 - entry.d0) * rank) / 12);",
  },
  {
    name: "value reads v12 as v0",
    file: "effect.ts",
    from: "line(entry.v0, entry.v12, rank)",
    to: "line(entry.v12, entry.v0, rank)",
  },
  {
    name: "DAMAGE classed Instant (KindClass Hit)",
    file: "effect.ts",
    from: "if (k === kind.DAMAGE) return KindClass.Hit;",
    to: "if (k === kind.DAMAGE) return KindClass.Instant;",
  },
  {
    name: "HIT_PENETRATION not a hit modifier (KindClass HitModifier)",
    file: "effect.ts",
    from: "if (k === kind.ATTACK_BONUS || k === kind.HIT_PENETRATION) return KindClass.HitModifier;",
    to: "if (k === kind.ATTACK_BONUS) return KindClass.HitModifier;",
  },
  {
    name: "MOVEMENT not holding (KindClass Holding, its last kind)",
    file: "effect.ts",
    from: "(k >= kind.BLOCK && k <= kind.MOVEMENT)",
    to: "(k >= kind.BLOCK && k < kind.MOVEMENT)",
  },
  {
    name: "NEXT_SPELL_COST not holding (KindClass Holding, its range's first kind)",
    file: "effect.ts",
    from: "(k >= kind.NEXT_SPELL_COST && k <= kind.PENETRATION)",
    to: "(k > kind.NEXT_SPELL_COST && k <= kind.PENETRATION)",
  },
  {
    name: "TRAP classed Instant (KindClass Placement)",
    file: "effect.ts",
    from: "if (k === kind.TRAP) return KindClass.Placement;",
    to: "if (k === kind.TRAP) return KindClass.Instant;",
  },
  {
    name: "the first kind after the MVP classed Instant (KindClass Instant's bound)",
    file: "effect.ts",
    from: "if (k === kind.EMPTY || k > kind.LAST_MVP) return undefined;",
    to: "if (k === kind.EMPTY || k > kind.LAST_MVP + 1) return undefined;",
  },
  {
    name: "Instant and Placement's Serde indices swapped",
    file: "effect.ts",
    from: "Instant: 3, Placement: 4 }",
    to: "Instant: 4, Placement: 3 }",
  },
  {
    name: "is_hit_modifier misses HIT_PENETRATION",
    file: "effect.ts",
    from: "entry.kind === kind.ATTACK_BONUS || entry.kind === kind.HIT_PENETRATION;",
    to: "entry.kind === kind.ATTACK_BONUS;",
  },
  {
    name: "pack puts the scope one bit low",
    file: "effect.ts",
    from: "BigInt(entry.scope) * two(95)",
    to: "BigInt(entry.scope) * two(94)",
  },
  {
    name: "pack writes v12 in v0's field",
    file: "effect.ts",
    from: "bits16(entry.v0) * two(16)",
    to: "bits16(entry.v12) * two(16)",
  },
  {
    name: "unpack reads the guard as 2 bits",
    file: "effect.ts",
    from: "const guard = small(take(8n));",
    to: "const guard = small(take(4n));",
  },
  {
    name: "the duration's percent bonus not capped at 50",
    file: "body/infliction.ts",
    from: "Math.min(bonus_percent, MAX_DURATION_BONUS_PERCENT)",
    to: "bonus_percent",
  },
  {
    name: "the duration's flat bonus not capped at 3",
    file: "body/infliction.ts",
    from: "Math.min(flat, MAX_DURATION_FLAT)",
    to: "flat",
  },
  {
    name: "the duration rounds, not truncates",
    file: "body/infliction.ts",
    from: "const scaled = u32op(div, u32op(mul, base, u32op(add, 100, percent)), 100);",
    to: "const scaled = Math.round((base * (100 + percent)) / 100);",
  },
  {
    name: "a value below 1 not clamped to 1",
    file: "body/infliction.ts",
    from: "v < 1 ? 1 :",
    to: "v < 0 ? 1 :",
  },
  {
    name: "a value above 32,767 not clamped",
    file: "body/infliction.ts",
    from: "v > MAX_VALUE_DURATION ? MAX_VALUE_DURATION : v",
    to: "v",
  },
  {
    name: "CONDITION_DURATION's percent applies to every condition",
    file: "body/infliction.ts",
    from: "c === source.condition ? source.percent : 0",
    to: "source.percent",
  },
  {
    name: "KNOCKDOWN_FLAT applies to every condition",
    file: "body/infliction.ts",
    from: "c === condition.KNOCKED_DOWN ? source.knockdown : 0",
    to: "source.knockdown",
  },
  {
    name: "refreshed's deadline is t0 + d",
    file: "segment/tick.ts",
    from: "const deadline = u32sub(u32add(t0, d), 1);",
    to: "const deadline = u32add(t0, d);",
  },
  {
    name: "refreshed takes the new deadline over a later one",
    file: "segment/tick.ts",
    from: "return deadline > old ? deadline : old;",
    to: "return deadline;",
  },
  {
    name: "cured's held is old > t0",
    file: "segment/tick.ts",
    from: "(old >= t0 ? u32sub(t0, 1) : old)",
    to: "(old > t0 ? u32sub(t0, 1) : old)",
  },
  {
    name: "cured ends at t0, not t0 − 1",
    file: "segment/tick.ts",
    from: "(old >= t0 ? u32sub(t0, 1) : old)",
    to: "(old >= t0 ? t0 : old)",
  },
  {
    name: "the recharge deadline is t0 + r",
    file: "segment/tick.ts",
    from: "=> u32sub(u32add(t0, r), 1);",
    to: "=> u32add(t0, r);",
  },
  {
    name: "a condition held until before its deadline (t0 < D)",
    file: "segment/tick.ts",
    from: "export const held = (deadline: number, t0: number): boolean => t0 <= deadline;",
    to: "export const held = (deadline: number, t0: number): boolean => t0 < deadline;",
  },
  {
    name: "a goblin Dead counts as alive (GoblinTrait::is_alive)",
    file: "segment/goblin.ts",
    from: "goblin.ai < DEAD;",
    to: "goblin.ai <= DEAD;",
  },
  {
    name: "halves ignores HALVED (spent)",
    file: "body/member.ts",
    from: "field(kitHigh(member), two(74), 2n) === 1n && (member.flags & flag.HALVED) === 0;",
    to: "field(kitHigh(member), two(74), 2n) === 1n;",
  },
  {
    name: "halves reads MemberKit bit 201",
    file: "body/member.ts",
    from: "two(74), 2n",
    to: "two(73), 2n",
  },
  {
    name: "a member's armor_vs refuses type 9 (the last)",
    file: "body/member.ts",
    from: "if (damage_type === 0 || damage_type > damage.LAST) return 0;",
    to: "if (damage_type === 0 || damage_type >= damage.LAST) return 0;",
  },
  {
    name: "a member's armor_vs reads type 2 in the high lanes",
    file: "body/member.ts",
    from: "if (damage_type <= 2) return",
    to: "if (damage_type < 2) return",
  },
  {
    name: "a member's armor_vs of types 3–9 one lane off",
    file: "body/member.ts",
    from: "two(72 + 6 * (damage_type - 3))",
    to: "two(72 + 6 * (damage_type - 2))",
  },
  {
    name: "infliction's percent one bit off",
    file: "body/member.ts",
    from: "percent: small(field(high, two(20), 0x40n)),",
    to: "percent: small(field(high, two(21), 0x40n)),",
  },
  {
    name: "infliction's knockdown one bit off",
    file: "body/member.ts",
    from: "knockdown: small(field(high, two(72), 4n)),",
    to: "knockdown: small(field(high, two(73), 4n)),",
  },
  {
    name: "infliction's condition one bit off",
    file: "body/member.ts",
    from: "condition: small(field(high, two(16), 0x10n)),",
    to: "condition: small(field(high, two(17), 0x10n)),",
  },
  {
    name: "enchant_percent one bit off",
    file: "body/member.ts",
    from: "small(field(kitHigh(member), two(26), 0x40n));",
    to: "small(field(kitHigh(member), two(27), 0x40n));",
  },
  {
    name: "Crippled written one bit off (a member)",
    file: "body/member.ts",
    from: "delta(crippled(member), deadline, two(160))",
    to: "delta(crippled(member), deadline, two(161))",
  },
  {
    name: "set_effect writes the deadline and pips of slot 0",
    file: "body/member.ts",
    from: "const lane = Math.min(slot, 3);",
    to: "const lane = 0;",
  },
  {
    name: "set_effect drops the potion tag",
    file: "body/member.ts",
    from: "delta(tag(old.potion), tag(held.potion), base * two(23)) +",
    to: "",
  },
  {
    name: "the recharge lanes of bar slots 4–7 not past the high limb's base",
    file: "body/member.ts",
    from: "base: two(28 * s + (s >= 4 ? 16 : 0))",
    to: "base: two(28 * s)",
    survives:
      "no row interrupts a member activating bar slot 4–7 (`inflict` 153–159 use bar slot 1): `recharge_at`'s high-limb lanes are not vectored",
  },
  {
    name: "a member's interrupt runs with no activation",
    file: "body/member.ts",
    from: "  if (member.act_slot === NO_SLOT) return;\n",
    to: "",
  },
  {
    name: "a member's interrupt counts the recharge from A, not t0",
    file: "body/member.ts",
    from: "set_recharge(member, member.act_slot, recharge_deadline(t0, r));",
    to: "set_recharge(member, member.act_slot, recharge_deadline(member.act_deadline, r));",
  },
  {
    name: "a member's interrupt keeps the activation",
    file: "body/member.ts",
    from: "  set_recharge(member, member.act_slot, recharge_deadline(t0, r));\n  clear(member);\n",
    to: "  set_recharge(member, member.act_slot, recharge_deadline(t0, r));\n",
  },
  {
    name: "a member's cure of Crippled writes Knocked down",
    file: "body/member.ts",
    from: "  else if (c === condition.CRIPPLED) set_crippled(member, deadline);\n  else member.knocked = deadline;",
    to: "  else member.knocked = deadline;",
  },
  {
    name: "a member's Crippled read as Knocked down (cure)",
    file: "body/member.ts",
    from: "  if (c === condition.CRIPPLED) return crippled(member);\n  return member.knocked;",
    to: "  return member.knocked;",
  },
  {
    name: "hold's step 1: a carrier held to t not held (deadline > t)",
    file: "body/member.ts",
    from: "    if (old.deadline >= t && old.potion === held.potion) {",
    to: "    if (old.deadline > t && old.potion === held.potion) {",
    survives:
      "no row holds again a carrier held to exactly T (193–196 hold skill 5 over itself held to 60 or 49; 197 holds skill 6 beside skill 5 held to 50): step 1's `old.deadline ≥ t` is not vectored at `t`",
  },
  {
    name: "hold's step 1: a skill and a potion of one carrier number are the same",
    file: "body/member.ts",
    from: "    if (old.deadline >= t && old.potion === held.potion) {",
    to: "    if (old.deadline >= t) {",
  },
  {
    name: "hold's step 1: a tie keeps the old application",
    file: "body/member.ts",
    from: "if (held.deadline >= old.deadline) put(",
    to: "if (held.deadline > old.deadline) put(",
  },
  {
    name: "hold's step 1: a potion is the same by its belt slot, not its item",
    file: "body/member.ts",
    from: "        ? belt_item(member, old.carrier) === item\n",
    to: "        ? old.carrier === held.carrier\n",
    survives:
      "the table's belt holds four different items (100 to 103), so a belt slot and its item always agree (203, 204, 324): no row holds a potion whose item another belt slot also holds, so step 1's comparison of the items, not the slots, is not vectored",
  },
  {
    name: "hold's step 2 skipped (a stance does not replace the stance)",
    file: "body/member.ts",
    from: "  if (stance) {",
    to: "  if (false) {",
  },
  {
    name: "hold's step 2: a potion's slot taken as a stance's",
    file: "body/member.ts",
    from: "      if (old.deadline >= t && !old.potion && old.carrier !== 0) {",
    to: "      if (old.deadline >= t && old.carrier !== 0) {",
  },
  {
    name: "hold's step 2: a lapsed stance replaced",
    file: "body/member.ts",
    from: "      if (old.deadline >= t && !old.potion && old.carrier !== 0) {",
    to: "      if (!old.potion && old.carrier !== 0) {",
  },
  {
    name: "hold's step 2: any skill's slot taken as a stance's",
    file: "body/member.ts",
    from: "at(sheets.skills, there).kind === skill_kind.STANCE",
    to: "at(sheets.skills, there).kind !== 0",
  },
  {
    name: "hold's step 3: a slot held to t taken as free",
    file: "body/member.ts",
    from: "    if (deadline < t) {",
    to: "    if (deadline <= t) {",
  },
  {
    name: "hold's step 4: a tie evicts the highest slot",
    file: "body/member.ts",
    from: "    if (deadline < earliest_deadline) {",
    to: "    if (deadline <= earliest_deadline) {",
  },
  {
    name: "put: a potion's pips 0",
    file: "body/member.ts",
    from: "    pips = at(sheets.potions, position).regen;",
    to: "    pips = 0;",
  },
  {
    name: "put: a skill's pips at rank 12",
    file: "body/member.ts",
    from: "    pips = line(skill.regen0, skill.regen12, held.rank);",
    to: "    pips = line(skill.regen0, skill.regen12, 12);",
  },
  {
    name: "put: the carrier's position not written",
    file: "body/member.ts",
    from: "  member.effect_at = member.effect_at.with(slot, position);\n",
    to: "",
  },
  {
    name: "a member above its adrenaline cap is brought down to it",
    file: "body/member.ts",
    from: "  if (member.adrenaline < member.adrenaline_cap) {\n    member.adrenaline = min16(",
    to: "  {\n    member.adrenaline = min16(",
  },
  {
    name: "a member's adrenaline not capped",
    file: "body/member.ts",
    from: "min16(u16add(member.adrenaline, quarters), member.adrenaline_cap)",
    to: "u16add(member.adrenaline, quarters)",
  },
  {
    name: "ADRENALINE_EVERY_N 0 counts hits",
    file: "body/member.ts",
    from: "  if (every > 0) {",
    to: "  if (every >= 0) {",
  },
  {
    name: "the N-th hit gives 4 quarters",
    file: "body/member.ts",
    from: "      quarters = 8;",
    to: "      quarters = 4;",
  },
  {
    name: "the hits counter not reset at N",
    file: "body/member.ts",
    from: "      set_hits(member, 0);",
    to: "      set_hits(member, next);",
  },
  {
    name: "the hits counter not written",
    file: "body/member.ts",
    from: "      set_hits(member, next);",
    to: "",
  },
  {
    name: "a member at 0 health gains adrenaline when struck",
    file: "body/member.ts",
    from: "  if (member.health > 0) gain_adrenaline(member, 1);",
    to: "  gain_adrenaline(member, 1);",
  },
  {
    name: "a member not alive takes a condition (apply)",
    file: "body/member.ts",
    from: "  if (!is_alive(member)) return;\n  const d = duration(source, c, v);",
    to: "  const d = duration(source, c, v);",
  },
  {
    name: "a member not alive is knocked down",
    file: "body/member.ts",
    from: "  if (!is_alive(member)) return;\n  const d = duration(source, condition.KNOCKED_DOWN, v);",
    to: "  const d = duration(source, condition.KNOCKED_DOWN, v);",
  },
  {
    name: "a member's Bleeding written as Poison (condition 1)",
    file: "body/member.ts",
    from: "  if (c === condition.BLEEDING) member.bleeding = refreshed(member.bleeding, t0, d);",
    to: "  if (c === condition.BLEEDING) member.poison = refreshed(member.poison, t0, d);",
  },
  {
    name: "a member's Poison written as Burning (condition 2)",
    file: "body/member.ts",
    from: "  else if (c === condition.POISON) member.poison = refreshed(member.poison, t0, d);",
    to: "  else if (c === condition.POISON) member.burning = refreshed(member.burning, t0, d);",
  },
  {
    name: "a member's Burning written as Bleeding (condition 3)",
    file: "body/member.ts",
    from: "  else if (c === condition.BURNING) member.burning = refreshed(member.burning, t0, d);",
    to: "  else if (c === condition.BURNING) member.bleeding = refreshed(member.bleeding, t0, d);",
  },
  {
    name: "a member's Crippled written as Knocked down (condition 4)",
    file: "body/member.ts",
    from: "    set_crippled(member, refreshed(crippled(member), t0, d));",
    to: "    member.knocked = refreshed(member.knocked, t0, d);",
  },
  {
    name: "a member's knock-down does not interrupt",
    file: "body/member.ts",
    from: "  member.knocked = refreshed(member.knocked, t0, d);\n  interrupt(member, t0, sheets);",
    to: "  member.knocked = refreshed(member.knocked, t0, d);",
  },
  {
    name: "energize in energy, not thirds",
    file: "body/member.ts",
    from: "mul(i32, BigInt(v), BigInt(ENERGY_THIRDS))",
    to: "BigInt(v)",
  },
  {
    name: "energize not floored at 0",
    file: "body/member.ts",
    from: "  if (v < low) return low;\n",
    to: "",
  },
  {
    name: "energize not capped at the max",
    file: "body/member.ts",
    from: "  if (v > high) return high;\n",
    to: "",
  },
  {
    name: "a goblin's armor_vs refuses type 9 (the last)",
    file: "body/goblin.ts",
    from: "if (damage_type === 0 || damage_type > 9) return 0;",
    to: "if (damage_type === 0 || damage_type >= 9) return 0;",
  },
  {
    name: "a goblin's armor_vs one lane off",
    file: "body/goblin.ts",
    from: "(1n << BigInt(6 * (damage_type - 1)))",
    to: "(1n << BigInt(6 * damage_type))",
  },
  {
    name: "a goblin's interrupt ignores caste slot 3 (LAST_SLOT)",
    file: "body/goblin.ts",
    from: "if (slot > activation.LAST_SLOT) return;",
    to: "if (slot >= activation.LAST_SLOT) return;",
    survives:
      "no row knocks down a goblin activating caste slot 3 (153–159 use slot 2): `LAST_SLOT`'s bound is not vectored",
  },
  {
    name: "a goblin recovering is interrupted",
    file: "body/goblin.ts",
    from: "  if (slot > activation.LAST_SLOT) return;\n",
    to: "",
  },
  {
    name: "a goblin's interrupt keeps the activation",
    file: "body/goblin.ts",
    from: "  set_recharge(goblin, slot, recharge_deadline(t0, r));\n  clear(goblin);\n",
    to: "  set_recharge(goblin, slot, recharge_deadline(t0, r));\n",
  },
  {
    name: "a goblin's interrupt writes no recharge",
    file: "body/goblin.ts",
    from: "  set_recharge(goblin, slot, recharge_deadline(t0, r));\n",
    to: "",
  },
  {
    name: "a dead goblin is cured",
    file: "body/goblin.ts",
    from: "  if (!is_alive(goblin)) return;\n  set_condition(",
    to: "  set_condition(",
  },
  {
    name: "a goblin's cure of Crippled writes Knocked down",
    file: "body/goblin.ts",
    from: "  else if (c === condition.CRIPPLED) set_crippled(goblin, deadline);\n",
    to: "",
  },
  {
    name: "a dead goblin holds an effect",
    file: "body/goblin.ts",
    from: "  if (!is_alive(goblin)) return;\n  const old = effect_of(goblin);",
    to: "  const old = effect_of(goblin);",
  },
  {
    name: "a goblin's hold: another carrier refreshes, not replaces",
    file: "body/goblin.ts",
    from: "old.deadline >= t && old.carrier === held.carrier && held.deadline < old.deadline",
    to: "old.deadline >= t && held.deadline < old.deadline",
  },
  {
    name: "a goblin's hold: a tie keeps the old application",
    file: "body/goblin.ts",
    from: "old.carrier === held.carrier && held.deadline < old.deadline",
    to: "old.carrier === held.carrier && held.deadline <= old.deadline",
  },
  {
    name: "a goblin's hold: an effect held to t lapsed",
    file: "body/goblin.ts",
    from: "if (old.deadline >= t && old.carrier",
    to: "if (old.deadline > t && old.carrier",
  },
  {
    name: "a goblin's hold: pips at rank 12",
    file: "body/goblin.ts",
    from: "  const pips = line(skill.regen0, skill.regen12, held.rank);",
    to: "  const pips = line(skill.regen0, skill.regen12, 12);",
  },
  {
    name: "a goblin's hold: the carrier's position not written",
    file: "body/goblin.ts",
    from: "  goblin.effect_at = position;\n",
    to: "",
  },
  {
    name: "a goblin above its cap is brought down to it",
    file: "body/goblin.ts",
    from: "if (goblin.adrenaline < cap) goblin.adrenaline",
    to: "goblin.adrenaline",
  },
  {
    name: "a goblin's weapon hit gives 3 quarters",
    file: "body/goblin.ts",
    from: "gain_adrenaline(goblin, 4, sheets);",
    to: "gain_adrenaline(goblin, 3, sheets);",
  },
  {
    name: "a dead goblin gains adrenaline when struck",
    file: "body/goblin.ts",
    from: "  if (is_alive(goblin) && goblin.health > 0) gain_adrenaline(goblin, 1, sheets);",
    to: "  if (goblin.health > 0) gain_adrenaline(goblin, 1, sheets);",
  },
  {
    name: "a goblin at 0 health gains adrenaline when struck",
    file: "body/goblin.ts",
    from: "  if (is_alive(goblin) && goblin.health > 0) gain_adrenaline(goblin, 1, sheets);",
    to: "  if (is_alive(goblin)) gain_adrenaline(goblin, 1, sheets);",
  },
  {
    name: "a dead goblin takes a condition (apply)",
    file: "body/goblin.ts",
    from: "  if (!is_alive(goblin)) return;\n  const d = duration(source, c, v);",
    to: "  const d = duration(source, c, v);",
  },
  {
    name: "a dead goblin is knocked down",
    file: "body/goblin.ts",
    from: "  if (!is_alive(goblin)) return;\n  const d = duration(source, condition.KNOCKED_DOWN, v);",
    to: "  const d = duration(source, condition.KNOCKED_DOWN, v);",
  },
  {
    name: "a goblin's Bleeding written as Poison (condition 1)",
    file: "body/goblin.ts",
    from: "  if (c === condition.BLEEDING) goblin.bleeding = refreshed(goblin.bleeding, t0, d);",
    to: "  if (c === condition.BLEEDING) goblin.poison = refreshed(goblin.poison, t0, d);",
  },
  {
    name: "a goblin's Poison written as Burning (condition 2)",
    file: "body/goblin.ts",
    from: "  else if (c === condition.POISON) goblin.poison = refreshed(goblin.poison, t0, d);",
    to: "  else if (c === condition.POISON) goblin.burning = refreshed(goblin.burning, t0, d);",
  },
  {
    name: "a goblin's Burning written as Bleeding (condition 3)",
    file: "body/goblin.ts",
    from: "  else if (c === condition.BURNING) goblin.burning = refreshed(goblin.burning, t0, d);",
    to: "  else if (c === condition.BURNING) goblin.bleeding = refreshed(goblin.bleeding, t0, d);",
  },
  {
    name: "a goblin's Crippled written as Knocked down (condition 4)",
    file: "body/goblin.ts",
    from: "    set_crippled(goblin, refreshed(crippled(goblin), t0, d));",
    to: "    goblin.knocked = refreshed(goblin.knocked, t0, d);",
  },
  {
    name: "a goblin's knock-down does not interrupt",
    file: "body/goblin.ts",
    from: "  goblin.knocked = refreshed(goblin.knocked, t0, d);\n  interrupt(goblin, t0, sheets);",
    to: "  goblin.knocked = refreshed(goblin.knocked, t0, d);",
  },
  {
    name: "a goblin at 0 health alive",
    file: "body/index.ts",
    from: "goblinModel.is_alive(x) && x.health > 0",
    to: "goblinModel.is_alive(x)",
  },
  {
    name: "a goblin on watch asleep",
    file: "body/index.ts",
    from: "(x) => x.ai === ai.ASLEEP,",
    to: "(x) => x.ai <= ai.WATCH,",
  },
  {
    name: "a goblin's slots 4",
    file: "body/index.ts",
    from: '(unit.kind === "M" ? 4 : 1)',
    to: "4",
  },
  {
    name: "an empty member slot's position kept as ABSENT_LANE",
    file: "body/index.ts",
    from: "at: position === ABSENT_LANE ? ABSENT : position,",
    to: "at: position,",
  },
  {
    name: "wound floors at 0 one point early (damage ≥ health − 1)",
    file: "body/index.ts",
    from: "actor.health = damage >= actor.health ? 0 : actor.health - damage;",
    to: "actor.health = damage >= actor.health - 1 ? 0 : actor.health - damage;",
  },
  {
    name: "heal not capped at the max",
    file: "body/index.ts",
    from: "actor.health = next > actor.max_health ? actor.max_health : next;",
    to: "actor.health = next;",
  },
  {
    name: "heal reaches a member not alive",
    file: "body/index.ts",
    from: "    if (!is_alive(unit.member)) return;\n  } else",
    to: "  } else",
  },
  {
    name: "heal reaches a goblin at 0 health",
    file: "body/index.ts",
    from: " || unit.goblin.health === 0) {",
    to: ") {",
  },
  {
    name: "energize caps a goblin at its energy, not its max",
    file: "body/index.ts",
    from: "const max = goblinModel.max_energy(goblin, sheets);",
    to: "const max = goblin.energy;",
  },
  {
    name: "struck sets no HIT flag",
    file: "body/index.ts",
    from: "    unit.member.flags |= flag.HIT;\n",
    to: "",
  },
  {
    name: "a goblin on watch does not engage when struck",
    file: "body/index.ts",
    from: "(goblin.ai === ai.ASLEEP || goblin.ai === ai.WATCH)",
    to: "goblin.ai === ai.ASLEEP",
  },
  {
    name: "a goblin at 0 health engages when struck",
    file: "body/index.ts",
    from: "if (goblin.health > 0 && (goblin.ai",
    to: "if ((goblin.ai",
  },
  {
    name: "halved sets no HALVED flag",
    file: "body/index.ts",
    from: '  if (unit.kind === "M") unit.member.flags |= flag.HALVED;\n',
    to: "",
  },
  {
    name: "a member's Knocked down applied as a condition (condition 5)",
    file: "body/index.ts",
    from: "    if (c === condition.KNOCKED_DOWN) m.knock(unit.member, v, source, t, sheets);",
    to: "    if (c === 0) m.knock(unit.member, v, source, t, sheets);",
  },
  {
    name: "a goblin's Knocked down applied as a condition (condition 5)",
    file: "body/index.ts",
    from: "  } else if (c === condition.KNOCKED_DOWN) {\n    g.knock(",
    to: "  } else if (c === 0) {\n    g.knock(",
  },
  {
    name: "a member not alive is cured",
    file: "body/index.ts",
    from: "    if (is_alive(unit.member)) m.cure(unit.member, c, t);",
    to: "    m.cure(unit.member, c, t);",
  },
  {
    name: "a member not alive holds an effect",
    file: "body/index.ts",
    from: "    if (is_alive(unit.member)) m.hold(",
    to: "    m.hold(",
  },
  {
    name: "a goblin holds a potion's effect",
    file: "body/index.ts",
    from: "  } else if (!held.potion) {\n    g.hold(",
    to: "  } else {\n    g.hold(",
  },
  {
    name: "spend runs with no charges",
    file: "body/index.ts",
    from: "  if (held.charges === 0) return;\n",
    to: "",
  },
  {
    name: "spend ends the effect at t, not t − 1",
    file: "body/index.ts",
    from: "next.deadline = Number(sub(u32, BigInt(t), 1n));",
    to: "next.deadline = t;",
  },
  {
    name: "spend writes slot 0's pips",
    file: "body/index.ts",
    from: "const pips = unit.member.effect_regen[slot];",
    to: "const pips = unit.member.effect_regen[0];",
  },
  {
    name: "an Illegal refusal keeps ActionLibrary's ground",
    file: "segment.ts",
    from: "    result = { halt: { illegal: out.outcome.illegal } };\n",
    to: "    result = { halt: { illegal: out.outcome.illegal } };\n    rules.ground = out.ground;\n",
    seam: true,
  },
  {
    name: "ActionLibrary is passed the ground itself, not a copy",
    file: "segment.ts",
    from: "    ground: copyGround(rules.ground),\n    action,",
    to: "    ground: rules.ground,\n    action,",
    seam: true,
  },
  {
    name: "ActionLibrary is passed the words themselves, not a copy",
    file: "segment.ts",
    from: "    words: copyWords(words),",
    to: "    words,",
    seam: true,
  },

  {
    name: "the window's last position read as inside (locate)",
    file: "trap.ts",
    from: "if (position >= FAR || position >= 240) return undefined;",
    to: "if (position > 240) return undefined;",
    survives:
      "position 240 (row 16) lands on chunk 15's tile 15, which no row's ground holds: row 42 with chunk 15 holding a trap on tile 15",
  },
  {
    name: "a chunk column past the location is in it (locate)",
    file: "trap.ts",
    from: "if (chunk >= MAX_CHUNKS || cx >= CHUNK_SIDE) return undefined;",
    to: "if (chunk >= MAX_CHUNKS) return undefined;",
    survives:
      "column 16 wraps to the next row's chunk, which no row's ground holds: row 47 with chunk 16 (cy 0, cx 16) holding a trap on its tile",
  },
  {
    name: "a chunk row past the location is in it (locate)",
    file: "trap.ts",
    from: "if (chunk >= MAX_CHUNKS || cx >= CHUNK_SIDE) return undefined;",
    to: "if (cx >= CHUNK_SIDE) return undefined;",
    survives:
      "chunk row 16 is chunk 240 and up, which no row's ground holds: row 48 with chunk 240 holding a trap on its tile",
  },
  // `locate`'s guard of a tile before the location's first, which Cairo has too, before its
  // `x - ORIGIN` would underflow. West: not killed by any row (RV-03a2). South: equivalent
  {
    name: "a tile West of the location is in it (locate)",
    file: "trap.ts",
    from: "if (x < ORIGIN || y < ORIGIN) return undefined;",
    to: "if (y < ORIGIN) return undefined;",
    survives:
      "no row's board reaches West of `ORIGIN`: with x < ORIGIN and y ≥ ORIGIN + 15, TS finds a real tile of chunk 15·cy − 1 where Cairo returns none: a trigger row with such a board, its ground holding a trap on that tile",
  },
  {
    name: "a tile South of the location is in it (locate)",
    file: "trap.ts",
    from: "if (x < ORIGIN || y < ORIGIN) return undefined;",
    to: "if (x < ORIGIN) return undefined;",
    equivalent:
      "with y < ORIGIN and x ≥ ORIGIN, the chunk is 15·cy + cx ≤ −1, which no ground holds: both callers (`trigger`, `armed`) find nothing, as for none",
  },
  {
    name: "the chunk's tile transposed (locate)",
    file: "trap.ts",
    from: "return [chunk, ly * CHUNK_SIDE + lx];",
    to: "return [chunk, lx * CHUNK_SIDE + ly];",
  },
  {
    name: "any used object is spent, not only a trap (free)",
    file: "trap.ts",
    from: "const spent = is_trap(o) && o.state === USED;",
    to: "const spent = o.state === USED;",
  },
  {
    name: "an empty object on the tile refuses it (free)",
    file: "trap.ts",
    from: "if (o.kind !== object.NONE && !spent && o.tile === tile) return undefined;",
    to: "if (!spent && o.tile === tile) return undefined;",
  },
  {
    name: "the highest free index, not the lowest (free)",
    file: "trap.ts",
    from: "if (found === undefined && (o.kind === object.NONE || spent)) found = k;",
    to: "if (o.kind === object.NONE || spent) found = k;",
  },
  {
    name: "a used trap's index is not free (free)",
    file: "trap.ts",
    from: "if (found === undefined && (o.kind === object.NONE || spent)) found = k;",
    to: "if (found === undefined && o.kind === object.NONE) found = k;",
  },
  {
    name: "a terrain trap is no trap (is_trap)",
    file: "trap.ts",
    from: "o.kind === object.TRAP || o.kind === object.PLACED_TRAP",
    to: "o.kind === object.PLACED_TRAP",
  },
  {
    name: "the chunk's last entry in the ground, not its first (trigger)",
    file: "trap.ts",
    from: "const at = ground.findIndex(([c]) => c === chunk);",
    to: "const at = ground.findLastIndex(([c]) => c === chunk);",
  },
  {
    name: "a used trap triggers again (trigger)",
    file: "trap.ts",
    from: "(o) => is_trap(o) && o.state !== USED && o.tile === tile,",
    to: "(o) => is_trap(o) && o.tile === tile,",
  },
  {
    name: "a trap on another tile of the chunk triggers (trigger)",
    file: "trap.ts",
    from: "(o) => is_trap(o) && o.state !== USED && o.tile === tile,",
    to: "(o) => is_trap(o) && o.state !== USED,",
  },
  {
    name: "a terrain trap triggers on a goblin (FX-34)",
    file: "trap.ts",
    from: `    if (!on_member) return untouched;
    source = terrain(`,
    to: "    source = terrain(",
  },
  {
    name: "a member's trap triggers on its own side",
    file: "trap.ts",
    from: `      if (on_member) return untouched;
`,
    to: "",
  },
  {
    name: "a goblin's trap triggers on its own side",
    file: "trap.ts",
    from: `      if (!on_member) return untouched;
      source = by_goblin(`,
    to: "      source = by_goblin(",
  },
  {
    name: "the trigger's clock is not the world's",
    file: "trap.ts",
    from: `    world.clock,
`,
    to: `    0,
`,
  },
  {
    name: "the trap not marked used",
    file: "trap.ts",
    from: "write(ground, at, index, { ...trap, state: USED })",
    to: "write(ground, at, index, { ...trap })",
  },
  {
    name: "the object written at index 0 whatever its index (write)",
    file: "trap.ts",
    from: "(i === Math.min(index, 2) ? o : old)",
    to: "(i === 0 ? o : old)",
  },
  {
    name: "the call's level, not the source's",
    file: "trap.ts",
    from: `    source.level,
`,
    to: `    level,
`,
  },
  {
    name: "a terrain trap's level fixed, not the band's (terrain)",
    file: "trap.ts",
    from: "return { payload, rank: 0, level, held: ALL_HELD, infliction: NONE };",
    to: "return { payload, rank: 0, level: 20, held: ALL_HELD, infliction: NONE };",
  },
  {
    name: "a skill the content lacks is the last (terrain)",
    file: "trap.ts",
    from: `  if (payload < 0) return undefined;
`,
    to: "",
  },
  {
    name: "a placer member past the world's count (by_member)",
    file: "trap.ts",
    from: "if (i >= world.members.length) return undefined;",
    to: "if (i > world.members.length) return undefined;",
    crash: "the member past the count is read all the same: a TypeError where Cairo finds none",
  },
  {
    name: "an empty bar slot is a payload (by_member)",
    file: "trap.ts",
    from: `  if (payload === ABSENT_LANE) return undefined;
`,
    to: "",
  },
  {
    name: "a member placer's rank of slot 0, not of its slot (by_member)",
    file: "trap.ts",
    from: "rank: executor.rank(member, slot),",
    to: "rank: executor.rank(member, 0),",
  },
  {
    name: "a member placer adds nothing to conditions (by_member)",
    file: "trap.ts",
    from: "infliction: m.infliction(member),",
    to: "infliction: NONE,",
  },
  {
    name: "a member placer's guards all held (by_member)",
    file: "trap.ts",
    from: 'const held = guards({ kind: "M", member }, entries(sheets, payload));',
    to: "const held = 7;",
  },
  {
    name: "a goblin placer the call does not carry (by_goblin)",
    file: "trap.ts",
    from: `  if (i === undefined) return undefined;
  const goblin`,
    to: "  const goblin",
    crash: "the goblin not carried is read all the same: a TypeError where Cairo finds none",
  },
  {
    name: "the kit of another goblin's caste, not the placer's (by_goblin)",
    file: "trap.ts",
    from: "const kit = sheets.kits[goblin.caste_at];",
    to: "const kit = sheets.kits[world.goblins[0]!.caste_at];",
    trap: true,
  },
  {
    name: "the rank of another goblin's caste, not the placer's (by_goblin)",
    file: "trap.ts",
    from: "const rank = sheets.castes[goblin.caste_at]!.rank;",
    to: "const rank = sheets.castes[world.goblins[0]!.caste_at]!.rank;",
    trap: true,
  },
  {
    name: "the level of another goblin, not the placer's (by_goblin)",
    file: "trap.ts",
    from: "level: goblinLevel(goblin),",
    to: "level: goblinLevel(world.goblins[0]!),",
    trap: true,
  },
  {
    name: "a goblin placer's guards all held (by_goblin)",
    file: "trap.ts",
    from: 'const held = guards({ kind: "G", goblin }, entries(sheets, payload));',
    to: "const held = 7;",
    survives:
      "no goblin placer's payload is guarded: a row with a `BELOW_HALF` caste trap skill, its placer above and below half",
  },
  {
    name: "a goblin placer's caste slot fixed at 2 (from_param)",
    file: "trap.ts",
    from: "slot: Math.floor(rest / 0x1000),",
    to: "slot: 2,",
  },
  {
    name: "a member placer is member 0 (from_param)",
    file: "trap.ts",
    from: 'return { kind: "M", member: param % 8, slot };',
    to: 'return { kind: "M", member: 0, slot };',
  },
  {
    name: "an entrant past the members is member (actor)",
    file: "executor.ts",
    from: 'return entity < world.members.length ? { kind: "M", i: entity } : undefined;',
    to: 'return entity <= world.members.length ? { kind: "M", i: entity } : undefined;',
  },
  {
    name: "the goblins' search turned the wrong way (find)",
    file: "executor.ts",
    from: "if (found < entity) low = middle + 1;",
    to: "if (found > entity) low = middle + 1;",
  },
  {
    name: "a guarded hit lands whatever its guard (trigger)",
    file: "executor.ts",
    from: "if ((held & bit(k)) !== 0) damage = e;",
    to: "damage = e;",
  },
  {
    name: "every entry after the hit is entry 0's set (trigger)",
    file: "executor.ts",
    from: "bits += bit(k);",
    to: "bits += 1;",
  },
  {
    name: "the hit's strength from the rank, not the level (trigger)",
    file: "executor.ts",
    from: "level_strength(BigInt(level))",
    to: "level_strength(BigInt(rank))",
  },
  {
    name: "an entrant killed by the hit takes the other entries (trap)",
    file: "executor.ts",
    from: `  return body.alive(target);
`,
    to: `  return true;
`,
    survives:
      "equivalent alone: `entries` stops at a dead entrant too, so either check masks the other (rows 7 and 30 kill the two together); `on` (lot E) runs `entries` without `trap`'s check",
  },
  {
    name: "a trap's hit of class Weapon (blocked, evaded, arced)",
    file: "executor.ts",
    from: "spell(HitClass.Trap, strength, damage, 0, 0, 0, context)",
    to: "spell(HitClass.Weapon, strength, damage, 0, 0, 0, context)",
  },
  {
    name: "a trap's base at rank 0 (spell)",
    file: "executor.ts",
    from: "base: clamp(value(e, context.rank), 0, MAX_VALUE),",
    to: "base: clamp(value(e, 0), 0, MAX_VALUE),",
  },
  {
    name: "a trap's damage of no type (spell)",
    file: "executor.ts",
    from: "damage_type: e.param,",
    to: "damage_type: 0,",
    survives:
      "no entrant has an `ARMOR_VS` of the payload's type: a trap row on an entrant with earth armor",
  },
  {
    name: "a landed hit not struck (strike)",
    file: "executor.ts",
    from: `    body.struck(target, sheets);
`,
    to: "",
  },
  {
    name: "a block's charge not spent (strike)",
    file: "executor.ts",
    from: `    body.spend(target, defence.block_slot, t);
`,
    to: "",
    survives:
      "only a weapon hit reads it (a trap's hit is never blocked or evaded, `ExecutorTrait::trap`): `act`'s rows (RV-03b, lot E)",
  },
  {
    name: "a knocked-down target read standing (strike)",
    file: "executor.ts",
    from: "knocked: body.knocked(target, t),",
    to: "knocked: false,",
    survives:
      "only a weapon hit reads it (a trap's hit is never blocked or evaded, `ExecutorTrait::trap`): `act`'s rows (RV-03b, lot E)",
  },
  {
    name: "a sleeping target read awake (strike)",
    file: "executor.ts",
    from: "asleep: body.asleep(target),",
    to: "asleep: false,",
    survives:
      "only a weapon hit reads it (a trap's hit is never blocked or evaded, `ExecutorTrait::trap`): `act`'s rows (RV-03b, lot E)",
  },
  {
    name: "the block's charges not capped (resolve)",
    file: "executor.ts",
    from: "const block = BigInt(defence.block) > MAX_BLOCK ? MAX_BLOCK : BigInt(defence.block);",
    to: "const block = BigInt(defence.block);",
    survives: "a `BLOCK` above 63 charges, and a weapon hit: `act`'s rows (RV-03b, lot E)",
  },
  {
    name: "the target's ARMOR effects ignored (resolve)",
    file: "executor.ts",
    from: "armor_effects: BigInt(defence.effects),",
    to: "armor_effects: 0n,",
    survives: "no entrant holds an `ARMOR` effect: a trap row on an entrant holding one",
  },
  {
    name: "the member's cached defence read whatever the tick (Levered)",
    file: "executor.ts",
    from: "if (c.at === t + 1 && c.member === index) return c.defence;",
    to: "if (c.member === index) return c.defence;",
    survives:
      "the table's members have no armor, stance or enchanted sum, and a trap's hit reads no block or evasion: a trap row on a member with armor",
  },
  {
    name: "an expired effect still defends (DefenceTrait::member)",
    file: "executor.ts",
    from: "if (held.deadline >= t && position !== ABSENT_LANE) {",
    to: "if (position !== ABSENT_LANE) {",
    survives:
      "no member entrant holds an expired effect whose holding entry is `ARMOR`: a trap row on one",
  },
  {
    name: "an expired effect still defends (DefenceTrait::goblin)",
    file: "executor.ts",
    from: "if (held.deadline >= t && goblin.effect_at !== ABSENT) {",
    to: "if (goblin.effect_at !== ABSENT) {",
    survives: "no goblin entrant holds an `ARMOR` effect, expired or not: a trap row on one",
  },
  {
    name: "an ARMOR effect not clamped at 0 (DefenceTrait::add)",
    file: "executor.ts",
    from: "defence.effects += clamp(value(e, held.rank), 0, MAX_ARMOR_EFFECT);",
    to: "defence.effects += value(e, held.rank);",
    survives: "no entrant holds an `ARMOR` effect: a trap row on an entrant holding a negative one",
  },
  {
    name: "an entrant dead after an entry takes the next (entries)",
    file: "executor.ts",
    from: `      if (!body.alive(target)) break;
`,
    to: "",
    survives:
      "no trap payload holds an entry that kills before a later one: only the hit kills, and `trap` stops the entries after it",
  },
  {
    name: "an entry's guard ignored (entries)",
    file: "executor.ts",
    from: "if ((bits & held & b) !== 0 && op.kind !== kind.EMPTY) {",
    to: "if ((bits & b) !== 0 && op.kind !== kind.EMPTY) {",
    survives:
      "no payload holds a guarded entry other than its hit: a trap skill whose condition is `BELOW_HALF`, its placer above half",
  },
  {
    name: "a condition through no infliction (entries)",
    file: "executor.ts",
    from: "body.inflict(target, op.param, op.v, context.infliction, t, sheets);",
    to: "body.inflict(target, op.param, op.v, { condition: 0, percent: 0, knockdown: 0 }, t, sheets);",
  },
  {
    name: "a condition's value at rank 0 (ops)",
    file: "executor.ts",
    from: "return { ...nothing(), kind: e.kind, param: e.param, v: value(e, r) };",
    to: "return { ...nothing(), kind: e.kind, param: e.param, v: value(e, 0) };",
  },
  {
    name: "a HEAL entry applies nothing (ops)",
    file: "executor.ts",
    from: "return { ...nothing(), kind: e.kind, v: clamp(value(e, r), 0, MAX_VALUE) };",
    to: "return nothing();",
    survives: "no trap payload holds a `HEAL` entry",
  },
  {
    name: "a CURE entry applies nothing (ops)",
    file: "executor.ts",
    from: "if (e.kind === kind.CURE) return { ...nothing(), kind: e.kind, param: e.param };",
    to: "if (e.kind === kind.CURE) return nothing();",
    survives: "no trap payload holds a `CURE` entry",
  },
  {
    name: "a holding entry applies nothing (ops)",
    file: "executor.ts",
    from: `    if (is_holding(e)) {
`,
    to: `    if (false) {
`,
    survives: "no trap payload holds a holding entry",
  },
  {
    name: "BELOW_HALF held at exactly half (guards)",
    file: "executor.ts",
    from: "health * 2 < max)) held += b;",
    to: "health * 2 <= max)) held += b;",
  },
  {
    name: "BELOW_HALF never held (guards)",
    file: "executor.ts",
    from: "if (e.guard === guard.ALWAYS || (e.guard === guard.BELOW_HALF && health * 2 < max)) held += b;",
    to: "if (e.guard === guard.ALWAYS) held += b;",
  },
  {
    name: "a goblin killed by a trap not in killed (put)",
    file: "executor.ts",
    from: `    world.killed.push(goblin.entity);
`,
    to: "",
  },
  {
    name: "a dead goblin at 0 health killed again (put)",
    file: "executor.ts",
    from: "if (goblinModel.is_alive(goblin) && goblin.health === 0) {",
    to: "if (goblin.health === 0) {",
    survives:
      "no goblin entrant is dead already: `actor` finds a dead goblin's record, a trap row with one entering",
  },
];

const SRC = new URL("../", import.meta.url);

/** At most this many mutants run at once, each worker its own thread (`parity/mutate.ts`). */
const WORKERS = Math.max(1, Math.min(4, availableParallelism() - 1));
/** A worker runs this many mutants, then exits: its memory grows with each, and is freed then. */
const PER_WORKER = 24;
/** A batch takes a few seconds; one not answered in this time is stopped and fails (a hang). */
const DEADLINE = 60_000;

const NONE = { tables: null, unit: null } as const;

/** Runs every job on a bounded pool of workers; the verdict of each, by its index. */
function pool(jobs: readonly Job[]): Map<number, Promise<Verdict>> {
  const settle = new Map<number, (verdict: Verdict) => void>();
  const verdicts = new Map(
    jobs.map((job) => [job.index, new Promise<Verdict>((done) => settle.set(job.index, done))]),
  );
  const queue = [...jobs];
  const start = () => {
    const batch = queue.splice(0, PER_WORKER);
    if (batch.length === 0) return;
    const worker = new Worker(new URL("./mutate.ts", import.meta.url));
    const waiting = new Set(batch.map((job) => job.index));
    let ended = false;
    // A worker that dies, exits or overruns its deadline leaves jobs unanswered: each is answered
    // as not loaded, a failure; then the worker is stopped and the next batch starts
    const end = (why: string) => {
      if (ended) return;
      ended = true;
      clearTimeout(timer);
      for (const index of waiting) settle.get(index)!({ index, ...NONE, load: why });
      waiting.clear();
      void worker.terminate().then(start);
    };
    const timer = setTimeout(() => end(`no answer within ${DEADLINE / 1000} s`), DEADLINE);
    worker.on("error", (error) => end(String(error)));
    worker.on("exit", (code) => end(`the worker exited (code ${code}) before answering`));
    worker.on("message", (verdict: Verdict) => {
      settle.get(verdict.index)!(verdict);
      waiting.delete(verdict.index);
      if (waiting.size === 0) end("");
    });
    for (const job of batch) worker.postMessage(job);
  };
  for (let i = 0; i < WORKERS; i++) start();
  return verdicts;
}

const text = (kill: Kill | null): string | undefined =>
  kill === null ? undefined : kill.crash ? `${kill.by} (**crash**)` : kill.by;

describe("the mutation check", () => {
  const results: string[] = [];
  let verdicts: Map<number, Promise<Verdict>>;

  beforeAll(() => {
    verdicts = pool(
      MUTANTS.map((mutant, index) => ({
        index,
        file: mutant.file,
        from: mutant.from,
        to: mutant.to,
        kind: mutant.trap
          ? "trap"
          : mutant.seam
            ? "seam"
            : mutant.refusal
              ? "refusal"
              : mutant.equivalent !== undefined
                ? "equivalent"
                : undefined,
      })),
    );
  });

  afterAll(() => {
    console.log(["| # | Mutant | Killed by |", "|---|---|---|", ...results].join("\n"));
  });

  it("has at least 12 mutants", () => {
    expect(MUTANTS.length).toBeGreaterThanOrEqual(12);
  });

  it("kills at least 12 of them", () => {
    const killed = MUTANTS.filter(
      (mutant) => mutant.survives === undefined && mutant.equivalent === undefined,
    );
    expect(killed.length).toBeGreaterThanOrEqual(12);
  });

  MUTANTS.forEach((mutant, index) => {
    const known = mutant.survives;
    const title =
      mutant.equivalent !== undefined
        ? "an equivalent"
        : known === undefined
          ? "kills"
          : "a known survivor";
    it(`${title}: ${mutant.name}`, async () => {
      const source = readFileSync(new URL(mutant.file, SRC), "utf8");
      expect(source.split(mutant.from).length - 1, `"${mutant.from}" once in ${mutant.file}`).toBe(
        1,
      );
      const verdict = await verdicts.get(index)!;
      expect(verdict.load, `${mutant.name}: the mutant does not load`).toBeUndefined();
      const unit = mutant.refusal || mutant.seam || mutant.trap;
      const kill = unit ? verdict.unit : verdict.tables;
      if (kill?.crash) {
        expect(
          mutant.crash,
          `${mutant.name} crashed (${kill.by}): a broken copy, or mark its \`crash\``,
        ).toBeDefined();
      } else {
        expect(
          mutant.crash,
          `${mutant.name} no longer crashes: remove its \`crash\``,
        ).toBeUndefined();
      }
      if (unit) {
        const found = text(verdict.unit);
        results.push(`| ${index + 1} | ${mutant.name} | ${found ?? "**survives**"} |`);
        expect(
          text(verdict.tables),
          `${mutant.name}: the tables record no such case`,
        ).toBeUndefined();
        expect(found, `${mutant.name} survived the unit tests' cases`).toBeDefined();
        return;
      }
      if (mutant.equivalent !== undefined) {
        const found = text(verdict.tables) ?? text(verdict.unit);
        results.push(
          `| ${index + 1} | ${mutant.name} | ${found ?? `**equivalent**: ${mutant.equivalent}`} |`,
        );
        expect(found, `${mutant.name} is killed: it is not equivalent`).toBeUndefined();
        return;
      }
      const found = text(verdict.tables);
      results.push(`| ${index + 1} | ${mutant.name} | ${found ?? `**survives**: ${known}`} |`);
      if (known === undefined) {
        expect(found, `${mutant.name} survived the vectors`).toBeDefined();
      } else {
        expect(found, `${mutant.name} is now killed: remove its \`survives\``).toBeUndefined();
      }
      // The pool runs ahead of the tests; a test waits for its mutant at most this long
    }, 120_000);
  });
});
