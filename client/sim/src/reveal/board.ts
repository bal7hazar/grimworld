// The board steps of a reveal: the mirror of `contracts/logic/src/types/reveal/board.cairo`
// (`BoardTrait`, ENG-05), whose documentation holds the rules and their reasons. A chunk is the
// 15 × 15 board of `hexx`, bit `15 row + column` 1 for a floor tile, `+1` West, `+15` North, `odd`
// when its local row 0 is a global odd row.
//
// Every product and difference the Cairo code computes in the field is computed here modulo `P`
// (`felt`), the same operands in the same order, so that a sum that would carry in Cairo carries
// here too; an AND or an OR of bitmaps is the `bigint`'s.

import { felt, has, inverse, keep_component, nth, popcount, pow, smooth, hades } from "../hexx";

export const MEADOW = 1;
export const FOREST = 2;
export const CAVE = 3;
export const RUIN = 4;

/** The 225 tiles. */
export const BOARD = 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffffffffn;
/** The 169 tiles inside the ring. */
export const INTERIOR = 0x1fff3ffe7ffcfff9fff3ffe7ffcfff9fff3ffe7ffcfff9fff0000n;
/** The 13 tiles of each side that are not a corner: West (column 14), East (column 0), South, North. */
export const WEST = 0x20004000800100020004000800100020004000800100020000000n;
export const EAST = 0x8001000200040008001000200040008001000200040008000n;
export const SOUTH = 0x3ffen;
export const NORTH = 0xfff80000000000000000000000000000000000000000000000000000n;
/** Row 7 and column 7 of the interior. */
export const SPINE = 0x4000800100020004000807ffc02000400080010002000400000n;
/** The centre `(7, 7)`. */
export const CENTRE = 112;
const LINE_EAST = 0xfen;
const LINE_SOUTH = 0x200040008001000200040008000n;
const COLUMN_7 = 0x40008001000200040008001n;
const EVEN_ROWS = 0x1fffc0007fff0001fffc0007fff0001fffc0007fff0001fffc0007fffn;
const ODD_ROWS = 0x3fff8000fffe0003fff8000fffe0003fff8000fffe0003fff8000n;
const NOT_COLUMN_0 = 0x1fffbfff7ffefffdfffbfff7ffefffdfffbfff7ffefffdfffbfff7ffen;
const NOT_COLUMN_14 = 0xfffdfffbfff7ffefffdfffbfff7ffefffdfffbfff7ffefffdfffbfffn;
const NOT_ROW_0 = 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffff8000n;
const ROW_UP = 0x8000n;
const INV_1 = inverse(2n);
const INV_7 = inverse(pow(7));
const INV_14 = inverse(pow(14));
const INV_15 = inverse(pow(15));
const INV_16 = inverse(pow(16));
const INV_105 = inverse(pow(105));
const INV_210 = inverse(pow(210));
const P14 = pow(14);
const P210 = pow(210);
/** Generations of the automaton, every biome. */
export const GENERATIONS = 1;

/** The side mask of edge `side` (0 West, 1 East, 2 South, 3 North). */
export function side(side: number): bigint {
  return [WEST, EAST, SOUTH][side] ?? NORTH;
}

/** The floor of a chunk's walls: the board less the walls. */
export function floor(walls: bigint): bigint {
  return felt(BOARD - walls);
}

/** `a & !b`, as `a − (a & b)`. */
export function minus(a: bigint, b: bigint): bigint {
  return felt(a - (a & b));
}

/** The base of a word at the biome's density, interior only (five bitmaps of two permutations). */
export function base(word: bigint, biome: number): bigint {
  const [a, b, c] = hades(word, 0n, 2n);
  let fill: bigint;
  if (biome === MEADOW) {
    fill = a | (b & c);
  } else if (biome === CAVE) {
    fill = a & (b | c);
  } else {
    const [d, e] = hades(word, 1n, 2n);
    if (biome === FOREST) {
      fill = a & (b | c | (d | e));
    } else {
      fill = a & (b | (c & d));
    }
  }
  return felt(fill & INTERIOR);
}

/** The tiles of `side` facing a revealed neighbour's open facing tiles (`floor`, its floor). */
export function copy(side: number, floor: bigint): bigint {
  switch (side) {
    case 0:
      return felt((floor & EAST) * P14);
    case 1:
      return felt((floor & WEST) * INV_14);
    case 2:
      return felt((floor & NORTH) * INV_210);
    default:
      return felt((floor & SOUTH) * P210);
  }
}

/** The lines from every open ring tile to the spine, and the spine. */
export function lines(ring: bigint): bigint {
  const east = felt((ring & EAST) * LINE_EAST);
  const west = felt(felt((ring & WEST) * INV_7) * 0x7fn);
  const south = felt((ring & SOUTH) * LINE_SOUTH);
  const north = felt(felt((ring & NORTH) * INV_105) * COLUMN_7);
  return felt(east | west | (south | north) | SPINE);
}

/** An interior anchor's line, along its row to column 7. */
export function anchor_line(tile: number): bigint {
  const row = Math.floor(tile / 15);
  const column = tile % 15;
  const [low, high] = column < 7 ? [column, 7] : [7, column];
  return felt(pow(row * 15) * (pow(high + 1) - pow(low)));
}

/** One pass of the automaton per generation, the ring held. */
export function smoothChunk(grid: bigint, odd: boolean): bigint {
  return smooth(grid, 15, 15, GENERATIONS, 0n, odd);
}

/** `grid` cut by a tile mask: what is outside the mask is wall, the ring included. */
export function cut(grid: bigint, mask: bigint): bigint {
  return felt(grid & (mask & BOARD));
}

/** The interior floor connected to `root`; an odd chunk flooded one row up on a 15 × 16 board. */
export function component(interior: bigint, root: number, odd: boolean): bigint {
  const [grid, height, from, back] = odd
    ? [felt(interior * ROW_UP), 16, root + 15, INV_15]
    : [interior, 15, root, 1n];
  return felt(keep_component(grid, 15, height, from) * back);
}

/** `tiles` and their hex neighbours on the chunk, ring included, with the global row parity. */
export function dilate(tiles: bigint, odd: boolean): bigint {
  const [evenRows, oddRows] = odd ? [ODD_ROWS, EVEN_ROWS] : [EVEN_ROWS, ODD_ROWS];
  const evens = tiles & evenRows;
  const odds = tiles & oddRows;
  const west = felt((tiles & NOT_COLUMN_14) * 2n);
  const east = felt((tiles & NOT_COLUMN_0) * INV_1);
  const north =
    felt(tiles * ROW_UP) | (felt((evens & NOT_COLUMN_0) * P14) | felt((odds & NOT_COLUMN_14) * 0x10000n));
  const rows = tiles & NOT_ROW_0;
  const south =
    felt(rows * INV_15) |
    (felt((evens & NOT_ROW_0 & NOT_COLUMN_0) * INV_16) |
      felt((odds & NOT_ROW_0 & NOT_COLUMN_14) * INV_14));
  const around = west | east | (north | south);
  return felt((around | tiles) & BOARD);
}

/** The tiles within 2 of every open ring tile and of `anchors`: two dilations. */
export function near_openings(ring: bigint, anchors: readonly number[], odd: boolean): bigint {
  let tiles = ring;
  for (const tile of anchors) tiles = tiles | pow(tile);
  return dilate(dilate(tiles, odd), odd);
}

export { has, nth, pow, popcount as count };
