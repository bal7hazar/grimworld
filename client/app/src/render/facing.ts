import type { Facing } from "./view";

/**
 * Facing on screen (design/10 *Facing*). The numbering is the map library's `Direction`
 * (`hexx-cairo`, `crates/hexx/src/board/direction.cairo`: East 0, NorthEast 1, NorthWest 2,
 * West 3, SouthWest 4, SouthEast 5), counter-clockwise from East; with the library's layout drawn
 * as `input/coords.ts` draws it, direction `d` points at `d × 60°` counter-clockwise from the
 * screen's right.
 */

/** PixiJS rotation (clockwise, radians) of something drawn pointing right, to point along `d`. */
export function facingRotation(facing: Facing): number {
  return (-facing * Math.PI) / 3;
}

/** Sprites face right; West, North-West and South-West show the mirrored sprite. */
export function isMirrored(facing: Facing): boolean {
  return facing === 2 || facing === 3 || facing === 4;
}

/** The wedge on an actor's tile, pointing right, in art pixels from the tile's centre. */
export const WEDGE: readonly number[] = [27, 0, 13, -11, 13, 11];
