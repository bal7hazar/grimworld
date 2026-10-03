import type { Tile } from "./view";

/**
 * The obstacle objects of a zone's wall hexes (CLI-03h, design/10): the pack's rocks, bushes,
 * stumps and trees, stills of role `prop` (`tools/art/manifest.toml`). Each wall hex draws one,
 * chosen by a hash of its coordinates: presentation only, never a rule, no randomness from the game
 * (the same hex always shows the same still). Without the atlas the shaped rock stays.
 */

export interface Obstacle {
  /** The still's name in the atlas. */
  readonly sprite: string;
  /** How often it is chosen, against the others' weights. */
  readonly weight: number;
}

/**
 * The stills a wall hex may show, proposed (the owner's eye): rocks and bushes most often, stumps
 * and trees (three hexes wide, the trees) one wall in eight each, so that a meadow stays open.
 */
export const OBSTACLES: readonly Obstacle[] = [
  ...["rock1", "rock2", "rock3", "rock4"].map((sprite) => ({ sprite, weight: 3 })),
  ...["bush1", "bush2", "bush3", "bush4"].map((sprite) => ({ sprite, weight: 3 })),
  ...["stump1", "stump2", "stump3", "stump4"].map((sprite) => ({ sprite, weight: 1 })),
  ...["tree1", "tree2", "tree3", "tree4"].map((sprite) => ({ sprite, weight: 1 })),
];

/** A 32-bit hash of a hex's coordinates (a multiply-xorshift mix): the same hex, the same value. */
export function hexHash(tile: Tile): number {
  let h = Math.imul(tile.x | 0, 0x27d4eb2d) ^ Math.imul(tile.y | 0, 0x165667b1);
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  return (h ^ (h >>> 16)) >>> 0;
}

/**
 * The still a wall hex shows, among `choices` (the obstacles the atlas has), by weight, and whether
 * it is mirrored; null when there is no choice (the shaped rock).
 */
export function obstacleOf(
  tile: Tile,
  choices: readonly Obstacle[],
): { readonly sprite: string; readonly mirror: boolean } | null {
  const total = choices.reduce((sum, o) => sum + o.weight, 0);
  if (total <= 0) return null;
  const hash = hexHash(tile);
  let pick = hash % total;
  for (const obstacle of choices) {
    if (pick < obstacle.weight) return { sprite: obstacle.sprite, mirror: hash >>> 31 === 1 };
    pick -= obstacle.weight;
  }
  return null;
}
