// The moves of a played batch (ENG-07): the window's board around the adventurer
// (`SegmentTrait::board` in `contracts/logic/src/types/play.cairo`, `BoardTrait::position` in
// `types/executor.cairo`, `hexx`'s `AssemblyTrait::origin`), a Move's ticks
// (`TickMathTrait::move_ticks`, `helpers/tick.cairo`), the tick's flood (`hexx`'s `Bfs::flood`,
// `FloodTrait::next_step` and `distance`) and step 0's awake set (`TickTrait::awake`,
// `types/world.cairo`), held equal to them by `contracts/logic/vectors/movement.jsonl`. A Move's
// tile is `window.ts`'s `neighbor`.
//
// Positions are the window's (`window.ts`): `15 y + x`, `+1` West, `+15` North. The rules, their
// edges and their reasons are the Cairo modules' documentation; this file names only where the
// mirror computes differently: the flood's layers are bitmaps built tile by tile, where `hexx`
// dilates limbs.

import { add, narrow, panic, u8 } from "./felt";
import { HEIGHT, SIZE, WIDTH, inside, neighbor, tiles } from "./window";

/** What `Board`'s fields hold above the origin, so that an origin down to −15 holds (D-134). */
export const ORIGIN = 15;
/** A Move's ticks while Crippled (FX-15). */
export const CRIPPLED_MOVE_TICKS = 2;
/** The largest awake set (design/02). */
export const MAX_AWAKE = 8;

export const errors = {
  NOT_INSIDE: "Asserter: position not inside",
  NOT_WALKABLE: "Bfs: position not walkable",
  DISTANCES: "tick: one distance a goblin",
} as const;

/** `hexx`'s `Origin`: the chunk `(cx, cy)` of the window's origin and its offset in it. */
export type Origin = { cx: number; cy: number; ox: number; oy: number };

/** `AssemblyTrait::origin`: the window of an adventurer on the location's tile `(x, y)`. */
export function origin(x: number, y: number): Origin {
  const moved = x + 8;
  const odd = y % 2;
  const movedY = y + odd + 7;
  return {
    cx: Math.floor(moved / 15) - 1,
    cy: Math.floor(movedY / 15) - 1,
    ox: moved % 15,
    oy: movedY % 15,
  };
}

/** `Board`'s origin: the location's tile of the window's position 0, each plus `ORIGIN`. */
export type Board = { x: number; y: number };

/** The origin of `SegmentTrait::board` for an adventurer on `(x, y)` (its walkable bitmap aside). */
export function board(x: number, y: number): Board {
  const { cx, cy, ox, oy } = origin(x, y);
  return {
    x: Number(narrow(u8, BigInt(15 * (cx + 1) + ox))),
    y: Number(narrow(u8, BigInt(15 * (cy + 1) + oy))),
  };
}

/** `BoardTrait::position`: the window's position of the location's tile `(x, y)`; `FAR` outside. */
export function position(board: Board, x: number, y: number): number {
  const gx = Number(add(u8, BigInt(x), BigInt(ORIGIN)));
  const gy = Number(add(u8, BigInt(y), BigInt(ORIGIN)));
  if (gx < board.x || gy < board.y) return 255;
  const dx = gx - board.x;
  const dy = gy - board.y;
  if (dx >= WIDTH || dy >= HEIGHT) return 255;
  return WIDTH * dy + dx;
}

/** A Move's ticks at `t0`: 2 while Crippled (deadline `crippled`) unless `MOVEMENT` is held, else 1. */
export function move_ticks(crippled: number, t0: number, movement: boolean): number {
  return t0 <= crippled && !movement ? CRIPPLED_MOVE_TICKS : 1;
}

/** `hexx`'s `Flood`: `layers[k]` the tiles at path distance `k`, each not empty; `layers[0]` the source. */
export type Flood = { cap: number; layers: readonly bigint[] };

const bit = (position: number): bigint => 1n << BigInt(position);

/** The window's interior: its ring (columns 0 and 14, rows 0 and 15) cleared. */
const INTERIOR = (() => {
  let interior = 0n;
  for (let p = 0; p < SIZE; p++) {
    const x = p % WIDTH;
    const y = Math.floor(p / WIDTH);
    if (x !== 0 && x !== WIDTH - 1 && y !== 0 && y !== HEIGHT - 1) interior |= bit(p);
  }
  return interior;
})();

/** The bits of a tile's board neighbours, its ring neighbours included. */
function around(position: number): bigint {
  let set = 0n;
  for (let d = 0; d < 6; d++) {
    const to = neighbor(position, d);
    if (to !== undefined) set |= bit(to);
  }
  return set;
}

/** The neighbours of every tile of a layer. */
function dilate(layer: bigint): bigint {
  let set = 0n;
  for (const tile of tiles(layer)) set |= around(tile);
  return set;
}

/**
 * `Bfs::flood` on the window: from `from`, on the walkable interior tiles of `grid` outside the
 * obstacles, layers 1 to `depth` at most, none past the first empty one.
 */
export function flood(grid: bigint, from: number, obstacles: bigint, depth: number): Flood {
  if (!inside(from)) panic(errors.NOT_INSIDE);
  if ((grid & bit(from)) === 0n) panic(errors.NOT_WALKABLE);
  if ((obstacles & bit(from)) !== 0n) panic(errors.NOT_WALKABLE);
  const layers = [bit(from)];
  if (depth !== 0) {
    let free = grid & INTERIOR & ~obstacles & ~bit(from);
    let layer = around(from) & free;
    free &= ~layer;
    for (let count = depth - 1; ; count--) {
      if (count === 0) {
        // The last layer allowed: kept when not empty, never expanded
        if (layer !== 0n) layers.push(layer);
        break;
      }
      if (layer === 0n) break;
      const next = dilate(layer) & free;
      free &= ~next;
      layers.push(layer);
      layer = next;
    }
  }
  return { cap: depth, layers };
}

/** The least layer touching `set`, by index, with the tiles of `set` it holds. */
function first(flood: Flood, set: bigint): [number, bigint] | undefined {
  for (let k = 0; k < flood.layers.length; k++) {
    const hit = flood.layers[k]! & set;
    if (hit !== 0n) return [k, hit];
  }
  return undefined;
}

const capped = (flood: Flood): boolean => flood.layers.length === flood.cap + 1;
const source = (flood: Flood, position: number): boolean => flood.layers[0] === bit(position);

/** The tile of a set's lowest bit. */
function lowest(set: bigint): number {
  return tiles(set & -set)[0]!;
}

/**
 * `FloodTrait::next_step`: the walker's neighbour in the least layer touching its neighbourhood,
 * lowest index first, not `blocked`; when all are, its free neighbour in the next layer. `undefined`
 * outside the window, beyond the cap (D-25), cut off, or every candidate blocked.
 */
export function next_step(flood: Flood, position: number, blocked: bigint): number | undefined {
  if (!inside(position)) return undefined;
  const near = around(position);
  const found = first(flood, near);
  if (found === undefined) return undefined;
  const [k, hit] = found;
  if (k === flood.layers.length - 1 && capped(flood) && !source(flood, position)) return undefined;
  let free = hit & ~blocked;
  if (free === 0n) {
    const next = flood.layers[k + 1];
    if (next === undefined) return undefined;
    free = next & near & ~blocked;
    if (free === 0n) return undefined;
  }
  return lowest(free);
}

/**
 * `FloodTrait::distance`: a tile's layer, or for a tile in none the least layer of its neighbours
 * plus one (D-26); `undefined` outside the window or when neither it nor a neighbour is in a layer.
 */
export function flood_distance(flood: Flood, position: number): number | undefined {
  if (!inside(position)) return undefined;
  if (source(flood, position)) return 0;
  const found = first(flood, around(position));
  return found === undefined ? undefined : found[0] + 1;
}

/** A goblin as the awake set reads it. */
export type Sleeper = { entity: number; alive: boolean; asleep: boolean };

/**
 * `TickTrait::awake`: the indexes, ascending, of the `MAX_AWAKE` goblins alive and not asleep
 * nearest by `distances` (one per goblin), ties by the lowest entity id.
 */
export function awake(goblins: readonly Sleeper[], distances: readonly number[]): number[] {
  if (distances.length !== goblins.length) panic(errors.DISTANCES);
  const NONE = 0xffffffff;
  const keys = goblins.map((goblin, i) =>
    goblin.alive && !goblin.asleep ? distances[i]! * 0x10000 + goblin.entity : NONE,
  );
  let last = 0;
  let found = 0;
  while (found < MAX_AWAKE) {
    let least = NONE;
    for (const key of keys) {
      if ((found === 0 || key > last) && key < least) least = key;
    }
    if (least === NONE) break;
    last = least;
    found++;
  }
  const woken: number[] = [];
  keys.forEach((key, i) => {
    if (found > 0 && key <= last) woken.push(i);
  });
  return woken;
}
