// How strong are the vectors? Each mutant is the mirror with one mistake a hand-written mirror
// typically makes (SPK-4's `mutants.ts`), applied as a one-line text replacement to a copy of
// `src/`; the copy replays every table and must diverge on at least one case, by its result or by
// throwing where Cairo returned. A mutant the vectors do not kill is a hole in the vectors: it is
// reported to track game, never closed by editing a table here: it is listed with `survives`
// (what the tables lack), and this test then requires it to survive, so that the day the game's
// cases kill it the mark must go.

import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

type Mutant = { name: string; file: string; from: string; to: string; survives?: string };

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
    survives:
      "no case asks a chunk already revealed: `reveal` of chunks [16, 16], or of 16 once it is revealed, reveals it once",
  },
  {
    name: "an anchor on a corner opened (D-134)",
    file: "reveal.ts",
    from: "return tile === 0 || tile === 14 || tile === 210 || tile === 224;",
    to: "return false;",
    survives: "no anchor lies on a corner: a zone anchor (0, 14) or (0, 210) stays wall",
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
    survives:
      "no mask cuts a whole side that faces a revealable neighbour: a 3 x 1 ruin whose chunk 1 has the columns 0-11 mask, chunk 1 revealed before chunk 2",
  },
  {
    name: "a dungeon side open whatever its seam",
    file: "reveal.ts",
    from: "(!emerging || seam(site, chunk, at, next))",
    to: "true",
    survives:
      "no dungeon chunk faces an outline chunk across a closed seam: a floor whose outline holds two adjacent chunks with no seam between them",
  },
  {
    name: "a South seam keyed on the West axis (D-224)",
    file: "reveal.ts",
    from: "        [chunk - 15, 1],",
    to: "        [chunk - 15, 0],",
    survives:
      "every dungeon South side is copied (the floor is revealed by index, its South neighbour first): a floor chunk revealed before its South neighbour",
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
    survives:
      "every side drawn open is whole: a side drawn open under a mask that keeps part of it (the cut case with chunk 1 revealed first)",
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
    from: "inner = inner | felt(pow(tile) + anchor_line(tile));",
    to: "inner = inner | pow(tile);",
    survives:
      "the only interior anchor (112) lies on the spine: an interior anchor off row 7 and column 7, e.g. tile 48",
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
    survives:
      "no chunk has its centre cut or walled: an interior anchor in a chunk whose mask cuts tile 112",
  },
  {
    name: "a set piece's walls ignored (the base generated)",
    file: "reveal.ts",
    from: "? floor(set[1].walls) & INTERIOR",
    to: "? smoothChunk(felt(base(chunkWord, site.biome) + ring), odd) & INTERIOR",
    survives:
      "case 196 never lays its set piece: the zone has no host above its masks (D-208), so the quota stays owed (`left[0]` 1 after both chunks); its chunk needs the quota's host bit 225",
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
    survives: "sight (12, 9) in 15 x 15: chunks 0, 1, 15, 16 (the mutant drops 16)",
  },
  {
    name: "sight's hexagon of radius 5 across rows",
    file: "reveal.ts",
    from: "if (dr > 12) return false;",
    to: "if (dr > 10) return false;",
    survives: "sight (0, 9) in 15 x 15: chunks 0, 15 (the mutant drops 15)",
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
    survives: "no member from a tile of columns 12-14: member(13, 11, false) is None",
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
    survives:
      "no odd chunk's interior is split in a way the row parity decides: an odd-row set piece whose floor is two parts touching only across a row",
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
    survives:
      "nothing is drawn within 2 of the one interior anchor (112): an interior anchor in a chunk of spawn density 255",
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
      "no mask hosts a quota with nothing left: a site whose chunk hosts quota i (bit 225 + i) with `left[i]` 0",
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
    survives:
      "no dungeon chunk 3 or more from the entry lays a chest or a pack of offset 0: a floor of N 6 with one there",
  },
  {
    name: "the band's distance not held at D",
    file: "reveal/placement.ts",
    from: "const held = Math.min(distance, far);",
    to: "const held = distance;",
    survives:
      "no chunk is farther than D from the entry: a zone whose entry chunk lies outside its rectangle",
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
    survives:
      "the Heart's template (offset +2) reaches the band's top anyway: a Heart in the entry chunk, or a Heart template of offset 0",
  },
  {
    name: "a pack drawn empty (no floor of one goblin)",
    file: "reveal/placement.ts",
    from: "const low = floor === 0 ? 1 : floor;",
    to: "const low = floor;",
    survives:
      "every template has a caste of minimum 1 or more: a template whose minimums are all 0",
  },
  {
    name: "a pack's size capped above 5",
    file: "reveal/placement.ts",
    from: "high = Math.min(high, MAX_PACK_SIZE);",
    to: "",
    survives: "every template's maximums sum to 5 or less: a template of maximums 3 + 3",
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
      "no chunk is offered a fourth object: a set piece of 3 objects in a ruin chunk that rolls a chest or a trap",
  },
  {
    name: "a third pack in a chunk (E-3)",
    file: "reveal/placement.ts",
    from: "if (placement.packs.length >= MAX_PACKS_PER_CHUNK) return false;",
    to: "if (placement.packs.length > MAX_PACKS_PER_CHUNK) return false;",
    survives:
      "no chunk is offered a third pack: a Heart's chunk whose two spawn rolls pass (density 255)",
  },
  {
    name: "a spawn roll equal to the density places",
    file: "reveal/placement.ts",
    from: "if (total !== 0 && roll < site.spawn.density) {",
    to: "if (total !== 0 && roll <= site.spawn.density) {",
    survives:
      "no spawn roll equals the density: a zone of density 0 whose roll is 0 (1 slot in 256)",
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
    survives: "case 196 never lays its set piece (no host bit 225 above the masks, D-208)",
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
];

const SRC = new URL("../", import.meta.url);
const COPIES = new URL("../.mutants/", SRC);
// The copies sit beside `src/`, not in it; `.mutants` is filtered all the same, so that copies left
// by a killed run could never be copied again if they ever moved under `src/`.
const SOURCES = readdirSync(SRC, { recursive: true }).filter(
  (path) => path.endsWith(".ts") && !path.endsWith(".test.ts") && !path.startsWith(".mutants"),
);

type Parity = {
  replay: typeof import("./replay").replay;
  readTable: typeof import("./table").readTable;
  TABLES: typeof import("./tables").TABLES;
};

/** A copy of `src/` with the mutant's one replacement, in `.mutants/<index>/`. */
async function copy(mutant: Mutant, index: number): Promise<Parity> {
  const text = readFileSync(new URL(mutant.file, SRC), "utf8");
  expect(text.split(mutant.from).length - 1, `"${mutant.from}" once in ${mutant.file}`).toBe(1);
  const root = new URL(`${index}/`, COPIES);
  for (const path of SOURCES) {
    const target = new URL(path, root);
    mkdirSync(new URL(".", target), { recursive: true });
    const source =
      path === mutant.file
        ? text.replace(mutant.from, mutant.to)
        : readFileSync(new URL(path, SRC), "utf8");
    writeFileSync(target, source);
  }
  const load = (name: string) => import(/* @vite-ignore */ new URL(`parity/${name}.ts`, root).href);
  const [replay, table, tables] = await Promise.all([
    load("replay"),
    load("table"),
    load("tables"),
  ]);
  return { replay: replay.replay, readTable: table.readTable, TABLES: tables.TABLES };
}

/** The first divergence the vectors find, or `undefined` when the mutant survives. */
function killer(parity: Parity): string | undefined {
  for (const entry of parity.TABLES) {
    try {
      parity.replay(entry, parity.readTable(entry.file));
    } catch (error) {
      return (error as Error).message.split(": case")[0]!.split(": threw")[0];
    }
  }
  return undefined;
}

describe("the mutation check", () => {
  const results: string[] = [];

  // A run that was interrupted or killed leaves its copies behind: start from none.
  beforeAll(() => {
    rmSync(COPIES, { recursive: true, force: true });
  });

  afterAll(() => {
    rmSync(COPIES, { recursive: true, force: true });
    console.log(["| # | Mutant | Killed by |", "|---|---|---|", ...results].join("\n"));
  });

  it("has at least 12 mutants", () => {
    expect(MUTANTS.length).toBeGreaterThanOrEqual(12);
  });

  it("kills at least 12 of them", () => {
    expect(MUTANTS.filter((mutant) => mutant.survives === undefined).length).toBeGreaterThanOrEqual(
      12,
    );
  });

  MUTANTS.forEach((mutant, index) => {
    const known = mutant.survives;
    it(`${known === undefined ? "kills" : "a known survivor"}: ${mutant.name}`, async () => {
      const found = killer(await copy(mutant, index));
      results.push(`| ${index + 1} | ${mutant.name} | ${found ?? `**survives**: ${known}`} |`);
      if (known === undefined) {
        expect(found, `${mutant.name} survived the vectors`).toBeDefined();
      } else {
        expect(found, `${mutant.name} is now killed: remove its \`survives\``).toBeUndefined();
      }
    });
  });
});
