import type { Tile } from "../render/view";

/**
 * What a gesture on the map means: a target, never a result (ORCH-client-visual §6.4). Whoever
 * holds the rules decides what a tap on a tile does.
 */
export type Intent =
  /** A tap on a tile (design/11 *Acting*: move, attack, select). */
  | { readonly kind: "tile"; readonly tile: Tile }
  /** A long press, or a right click on a desktop: inspect what is on the tile. */
  | { readonly kind: "inspect"; readonly tile: Tile };
