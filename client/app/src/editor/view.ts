import type { ViewState, ViewTile } from "../render/view";
import { GROUND_KINDS, type MapDocument, WALL, tilesHigh, tilesWide } from "./model";

/** The layers bar (§2.3): what the canvas shows. Objects are CLI-09b's; their box is kept. */
export interface Layers {
  readonly ground: boolean;
  readonly obstacles: boolean;
  readonly objects: boolean;
  readonly outline: boolean;
  readonly seams: boolean;
  readonly grid: boolean;
}

export const LAYER_NAMES: readonly (keyof Layers)[] = [
  "ground",
  "obstacles",
  "objects",
  "outline",
  "seams",
  "grid",
];

export const DEFAULT_LAYERS: Layers = {
  ground: true,
  obstacles: true,
  objects: true,
  outline: true,
  seams: false,
  grid: true,
};

/**
 * The game's view of a map (§2.3): every hex revealed and in sight (no fog, nothing dimmed), the
 * void drawn as the game draws it around a zone or a hub (`void: "water"`), no actor. The
 * renderer is the game's, unchanged.
 *
 * - Ground off: every hex is drawn as grass, so terrain alone reads.
 * - Obstacles off: walls are drawn with the renderer's unrevealed look (a flat dark hex) instead of
 *   their rocks, bushes and trees, so the walkable plane reads at a glance.
 */
export function editorView(doc: MapDocument, layers: Layers): ViewState {
  const width = tilesWide(doc.meta);
  const height = tilesHigh(doc.meta);
  const tiles: ViewTile[] = new Array(width * height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = y * width + x;
      const wall = doc.terrain[i] === WALL;
      const kind = wall ? (layers.obstacles ? "wall" : "unrevealed") : "floor";
      tiles[i] = layers.ground ? { x, y, kind, ground: GROUND_KINDS[doc.ground[i]!] } : { x, y, kind };
    }
  }
  return {
    tiles,
    actors: [],
    adventurerId: -1,
    sight: tiles,
    arcs: null,
    path: [],
    dropped: [],
    selectedTile: null,
    structures: [],
    void: "water",
  };
}
