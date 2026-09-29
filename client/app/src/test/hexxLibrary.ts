import type { Facing, Tile } from "../render/view";

/**
 * The map library's neighbour table, transcribed for tests only, so that the client's geometry is
 * checked against the library and not against itself.
 *
 * Source: `bal7hazar/hexx-cairo`, `crates/hexx/src/board/direction.cairo`, `Direction::next`
 * ("Hexagonal directions, pointy-top, odd-r offset layout"), on a board of width `W` with
 * `i = y * W + x`. `Direction` into `u8`: East 0, NorthEast 1, NorthWest 2, West 3, SouthWest 4,
 * SouthEast 5.
 *
 * | Direction | even row  | odd row   |
 * |-----------|-----------|-----------|
 * | East      | i - 1     | i - 1     |
 * | NorthEast | i + W - 1 | i + W     |
 * | NorthWest | i + W     | i + W + 1 |
 * | West      | i + 1     | i + 1     |
 * | SouthWest | i - W     | i - W + 1 |
 * | SouthEast | i - W - 1 | i - W     |
 */
const W = 15;
const NEXT: readonly (readonly [even: number, odd: number])[] = [
  [-1, -1],
  [W - 1, W],
  [W, W + 1],
  [1, 1],
  [-W, -W + 1],
  [-W - 1, -W],
];

/** The library's `next` applied to a global tile, on a window whose origin row is even (D-120). */
export function libraryNext(tile: Tile, direction: Facing): Tile {
  const ox = tile.x - 7;
  const oy = tile.y - 8 + (tile.y & 1);
  const position = (tile.y - oy) * W + (tile.x - ox);
  const local = (tile.y - oy) & 1;
  const offsets = NEXT[direction] as readonly [number, number];
  const next = position + offsets[local];
  return { x: ox + (next % W), y: oy + Math.floor(next / W) };
}

export const LIBRARY_DIRECTIONS: readonly Facing[] = [0, 1, 2, 3, 4, 5];

export const LIBRARY_NEXT: readonly ((tile: Tile) => Tile)[] = LIBRARY_DIRECTIONS.map(
  (d) => (tile: Tile) => libraryNext(tile, d),
);
