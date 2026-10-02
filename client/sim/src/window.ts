// The game's geometry on the window (ENG-02, D-173): the mirror of `WindowTrait`
// (`contracts/logic/src/types/window.cairo`, its frozen signature in
// `docs/reports/ENG-02-geometry.md`), held equal to it by `contracts/logic/vectors/window.jsonl`.
//
// A tile is its position `15 y + x` (`x` below 15, `y` below 16; `+1` is West, `+15` is North,
// pointy-top odd-r), 240 and up outside the window. A facing is `0..=5`: East, North-East,
// North-West, West, South-West, South-East. `open` is the walkable bitmap: bit `p` for the tile
// `p`. The rules, their edges and their reasons are the Cairo module's documentation; this file
// names only where the mirror computes differently.

import { panic } from "./felt";

export const WIDTH = 15;
export const HEIGHT = 16;
export const SIZE = 240;
/** The distance of a position outside the window: above every range. */
export const FAR = 255;

/** The ranges of design/04's table, in tiles. */
export const range = {
  TOUCH: 1,
  NEARBY: 2,
  AREA: 3,
  ALERT: 5,
  RANGED: 6,
  EARSHOT: 8,
} as const;

/** The shapes of `effect::shape`. */
export const shapes = {
  SINGLE: 1,
  RING_1: 2,
  DISC_1: 3,
  DISC_2: 4,
  DISC_3: 5,
} as const;

/** `combat::Arc`, by its `Serde` index. */
export const Arc = { Front: 0, FrontSide: 1, RearSide: 2, Back: 3 } as const;
export type Arc = (typeof Arc)[keyof typeof Arc];

export const errors = {
  OPEN: "window: open above 240",
  FACING: "window: facing",
  SHAPE: "window: shape",
} as const;

/** The directions in `(q, r)`, by facing: East, North-East, North-West, West, South-West, South-East. */
const DIRECTIONS: readonly (readonly [number, number])[] = [
  [-1, 0],
  [-1, 1],
  [0, 1],
  [1, 0],
  [1, -1],
  [0, -1],
];

const LIMIT = 1n << BigInt(SIZE);

function u8(value: number): number {
  if (!Number.isInteger(value) || value < 0 || value > 255) {
    throw new RangeError(`not a u8: ${value}`);
  }
  return value;
}

/** Whether a position is a tile of the window. */
export function inside(position: number): boolean {
  return u8(position) < SIZE;
}

/** `WindowAssert::assert_valid_open`: no bit at or above 240. */
export function assertValidOpen(open: bigint): void {
  if (open < 0n) throw new RangeError(`not a bitmap: ${open}`);
  if (open >= LIMIT) panic(errors.OPEN);
}

/** `WindowAssert::direction`: a facing `0..=5`. */
function direction(facing: number): number {
  if (u8(facing) > 5) panic(errors.FACING);
  return facing;
}

/** `(q, r)` of a position of the window: `q = x − ⌊y/2⌋`, `r = y`. */
function axial(position: number): [number, number] {
  const y = Math.floor(position / WIDTH);
  return [(position % WIDTH) - Math.floor(y / 2), y];
}

/** The position of `(q, r)`, or `undefined` outside the window. */
function at(q: number, r: number): number | undefined {
  const x = q + Math.floor(r / 2);
  if (x < 0 || x >= WIDTH || r < 0 || r >= HEIGHT) return undefined;
  return r * WIDTH + x;
}

function delta(from: number, to: number): [number, number] {
  const [qa, ra] = axial(from);
  const [qb, rb] = axial(to);
  return [qb - qa, rb - ra];
}

function length([dq, dr]: [number, number]): number {
  return Math.max(Math.abs(dq), Math.abs(dr), Math.abs(dq + dr));
}

/**
 * The first step of design/04's line along a move that is not zero (`WindowInternal::step`): an
 * axis of largest magnitude moves by its sign; of the two others the larger moves; at a tie the
 * lower tile index, that is the smaller column on one row, else the lower row.
 */
function step([dq, dr]: [number, number]): number {
  const [q, r, s] = [Math.abs(dq), Math.abs(dr), Math.abs(dq + dr)];
  const [qNegative, rNegative] = [dq < 0, dr < 0];
  let moveQ: boolean;
  let moveR: boolean;
  if (r >= q && r >= s) {
    moveQ = q > s || (q === s && qNegative);
    moveR = true;
  } else if (q >= s) {
    moveQ = true;
    moveR = r > s || (r === s && rNegative);
  } else {
    moveR = r > q || (r === q && rNegative);
    moveQ = !moveR;
  }
  if (!moveR) return qNegative ? 0 : 3;
  if (!rNegative) return moveQ ? 1 : 2;
  return moveQ ? 4 : 5;
}

/**
 * The tiles strictly between `from` and `to` on design/04's line, `undefined` when it leaves the
 * window: element `i` of `N` is the tile whose hexagon holds `A + (i / N)(B − A)`, at a tie the
 * lower tile index. Computed by its definition, scaled by `N` (the Cairo tests' oracle, which they
 * hold equal to `hexx`'s line), not by `hexx`'s algorithm.
 */
function line(from: number, to: number): number[] | undefined {
  const [qa, ra] = axial(from);
  const [qb, rb] = axial(to);
  const n = length([qb - qa, rb - ra]);
  const tiles: number[] = [];
  for (let i = 1; i < n; i++) {
    const pq = n * qa + i * (qb - qa);
    const pr = n * ra + i * (rb - ra);
    const ps = -pq - pr;
    const [q0, r0] = [Math.floor(pq / n), Math.floor(pr / n)];
    let chosen: [number, number] | undefined;
    // Candidates in ascending index: rows, then columns (the column grows with `q` on a row)
    for (let r = r0 - 1; r <= r0 + 2 && chosen === undefined; r++) {
      for (let q = q0 - 2; q <= q0 + 2; q++) {
        const [dq, dr, ds] = [pq - n * q, pr - n * r, ps + n * (q + r)];
        if (Math.abs(dq - dr) <= n && Math.abs(dr - ds) <= n && Math.abs(ds - dq) <= n) {
          chosen = [q, r];
          break;
        }
      }
    }
    const tile = at(...chosen!);
    if (tile === undefined) return undefined;
    tiles.push(tile);
  }
  return tiles;
}

function walkable(open: bigint, position: number): boolean {
  return ((open >> BigInt(position)) & 1n) === 1n;
}

/** Both ends and every tile between them on the line are walkable; false when it leaves the window. */
function seen(open: bigint, from: number, to: number): boolean {
  const between = line(from, to);
  if (between === undefined) return false;
  return [from, to, ...between].every((tile) => walkable(open, tile));
}

/** The hex distance between two tiles (walls ignored); `FAR` when either is outside the window. */
export function distance(from: number, to: number): number {
  if (!(inside(from) && inside(to))) return FAR;
  return length(delta(from, to));
}

/** Whether `from` sees `to`: both ends and every tile between them walkable (design/04). */
export function sight(open: bigint, from: number, to: number): boolean {
  assertValidOpen(open);
  if (!(inside(from) && inside(to))) return false;
  return seen(open, from, to);
}

/** Whether `to` is within `range` of `from` and in its sight. */
export function reach(open: bigint, from: number, to: number, range: number): boolean {
  assertValidOpen(open);
  if (!(inside(from) && inside(to))) return false;
  if (length(delta(from, to)) > u8(range)) return false;
  return seen(open, from, to);
}

/**
 * The arc of the target's facing a hit from `source` arrives from: `(d − facing) mod 6`, `d` the
 * first step of the line from the target toward the source. `undefined` (Cairo's `None`) for the
 * same tile or a position outside the window.
 */
export function arc(source: number, target: number, facing: number): Arc | undefined {
  direction(facing);
  if (!(inside(source) && inside(target)) || source === target) return undefined;
  const turn = (step(delta(target, source)) + 6 - facing) % 6;
  if (turn === 0) return Arc.Front;
  if (turn === 1 || turn === 5) return Arc.FrontSide;
  if (turn === 3) return Arc.Back;
  return Arc.RearSide;
}

/** Whether `target` stands on the front tile of `source` facing `facing` (Blind's miss). */
export function front(source: number, target: number, facing: number): boolean {
  direction(facing);
  if (!(inside(source) && inside(target))) return false;
  const [q, r] = axial(source);
  const [dq, dr] = DIRECTIONS[facing]!;
  return at(q + dq, r + dr) === target;
}

/** The facing of an actor on `from` after an action toward `to`: the line's first step. */
export function facing(from: number, to: number, facing: number): number {
  direction(facing);
  if (!(inside(from) && inside(to)) || from === to) return facing;
  return step(delta(from, to));
}

/** `2^first + … + 2^last`. */
function span(first: number, last: number): bigint {
  return (1n << BigInt(last + 1)) - (1n << BigInt(first));
}

/** The tiles within `radius` of `centre`, clipped to the window, one row segment per row. */
function disc(centre: number, radius: number): bigint {
  const [y, x] = [Math.floor(centre / WIDTH), centre % WIDTH];
  const half = Math.floor(y / 2);
  let tiles = 0n;
  for (let dr = -radius; dr <= radius; dr++) {
    const row = y + dr;
    if (row < 0 || row >= HEIGHT) continue;
    // `dq` in `[max(−R, −R − dr), min(R, R − dr)]`, at the column `x + dq + ⌊y'/2⌋ − ⌊y/2⌋`
    const start = x + Math.floor(row / 2) - half;
    const first = start + Math.max(-radius, -radius - dr);
    const last = start + Math.min(radius, radius - dr);
    if (last < 0 || first > WIDTH - 1) continue;
    tiles += span(row * WIDTH + Math.max(first, 0), row * WIDTH + Math.min(last, WIDTH - 1));
  }
  return tiles;
}

/** The tiles of a shape centred on `centre`, clipped to the window and its walls, as a bitmap. */
export function shape(open: bigint, shape: number, centre: number): bigint {
  assertValidOpen(open);
  if (!inside(centre)) {
    if (shape < shapes.SINGLE || shape > shapes.DISC_3) panic(errors.SHAPE);
    return 0n;
  }
  let tiles: bigint;
  if (shape === shapes.SINGLE) tiles = 1n << BigInt(centre);
  else if (shape === shapes.RING_1) tiles = disc(centre, 1) - (1n << BigInt(centre));
  else if (shape === shapes.DISC_1) tiles = disc(centre, 1);
  else if (shape === shapes.DISC_2) tiles = disc(centre, 2);
  else if (shape === shapes.DISC_3) tiles = disc(centre, 3);
  else panic(errors.SHAPE);
  return tiles & open;
}

/** The positions of a bitmap of the window, ascending. */
export function tiles(mask: bigint): number[] {
  if (mask < 0n) throw new RangeError(`not a bitmap: ${mask}`);
  const positions: number[] = [];
  for (let p = 0; mask >> BigInt(p) !== 0n; p++) {
    if (walkable(mask, p)) positions.push(p);
  }
  return positions;
}
