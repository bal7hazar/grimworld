import type { ViewState, ViewTile } from "../render/view";
import {
  CHUNK,
  GROUND_KINDS,
  type MapDocument,
  type TileBox,
  WALL,
  groundOfCell,
  keyOf,
  paintedBox,
  terrainOf,
  tileOfKey,
} from "./model";
import { townStructures } from "./walkWorld";

/** The layers bar (§2.3): what the canvas shows. Objects are CLI-09b's; their box is kept. */
export interface Layers {
  readonly ground: boolean;
  readonly obstacles: boolean;
  readonly objects: boolean;
  readonly outline: boolean;
  /** The last fitted chunk grid (D-216): off while painting, shown by "Fit chunks". */
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
 * Unpainted hexes this far around the painted box are sent as the void's water, so that a gap in
 * the painting reads as the void beyond it: the renderer draws its void only outside its tiles' box
 * shrunk by two hexes (`voidHole`).
 */
export const VOID_PAD = 3;

/**
 * The most tiles one view sends to the renderer. Past it (a far zoom over painted hexes thousands of
 * hexes apart), the window's painted hexes alone are sent, up to this many, and the void's bands
 * draw the water between them.
 */
export const VIEW_MAX = 250_000;

/**
 * The tiles sent to the renderer for a view of `visible` (D-216: only what is near the view): the
 * visible tiles grown by half the view on each side, snapped outward to whole multiples of 15 so
 * that the renderer's baked chunks (`BAKE_CHUNK`) keep their keys while the camera moves inside.
 */
export function viewWindow(visible: TileBox): TileBox {
  const padX = Math.ceil((visible.x1 - visible.x0) / 2) + 1;
  const padY = Math.ceil((visible.y1 - visible.y0) / 2) + 1;
  const down = (n: number) => Math.floor(n / CHUNK) * CHUNK;
  const up = (n: number) => Math.floor(n / CHUNK) * CHUNK + CHUNK - 1;
  return {
    x0: down(visible.x0 - padX),
    y0: down(visible.y0 - padY),
    x1: up(visible.x1 + padX),
    y1: up(visible.y1 + padY),
  };
}

/** Whether a window still holds the visible tiles: else the view is rebuilt. */
export function holds(window: TileBox, visible: TileBox): boolean {
  return (
    visible.x0 >= window.x0 &&
    visible.y0 >= window.y0 &&
    visible.x1 <= window.x1 &&
    visible.y1 <= window.y1
  );
}

/**
 * The game's view of the map around a window (§2.3): every hex revealed and in sight (no fog,
 * nothing dimmed), the void drawn as the game draws it around a zone or a hub (`void: "water"`), no
 * actor. The renderer is the game's, unchanged. Only the window's part of the painted box (grown by
 * `VOID_PAD`) is sent: its painted hexes, and its unpainted ones as the void's water.
 *
 * - Ground off: every painted hex is drawn as grass, so terrain alone reads.
 * - Obstacles off: walls are drawn with the renderer's unrevealed look (a flat dark hex) instead of
 *   their rocks, bushes and trees, so the walkable plane reads at a glance.
 * - Every placed object's hex is in sight, so that none is drawn dimmed (CLI-09h).
 * - The map's buildings, props and bridges (a town's and the pack's, CLI-09b and CLI-09e) stand as
 *   the game draws them, with the objects layer, on a zone as on a town; its characters stand in
 *   their idle loop (CLI-09e part 3). The renderer draws them all: the overlay draws none.
 */
export function editorView(doc: MapDocument, layers: Layers, window: TileBox): ViewState {
  const box = paintedBox(doc);
  const tiles: ViewTile[] = [];
  if (box) {
    const x0 = Math.max(window.x0, box.x0 - VOID_PAD);
    const x1 = Math.min(window.x1, box.x1 + VOID_PAD);
    const y0 = Math.max(window.y0, box.y0 - VOID_PAD);
    const y1 = Math.min(window.y1, box.y1 + VOID_PAD);
    const painted = (x: number, y: number, cell: number): ViewTile => {
      const wall = terrainOf(cell) === WALL;
      const kind = wall ? (layers.obstacles ? "wall" : "unrevealed") : "floor";
      return layers.ground
        ? { x, y, kind, ground: GROUND_KINDS[groundOfCell(cell)] }
        : { x, y, kind };
    };
    if ((x1 - x0 + 1) * (y1 - y0 + 1) <= VIEW_MAX) {
      for (let y = y0; y <= y1; y++) {
        for (let x = x0; x <= x1; x++) {
          const cell = doc.hexes.get(keyOf({ x, y }));
          tiles.push(
            cell === undefined ? { x, y, kind: "wall", ground: "water" } : painted(x, y, cell),
          );
        }
      }
    } else {
      for (const [key, cell] of doc.hexes) {
        if (tiles.length >= VIEW_MAX) break;
        const { x, y } = tileOfKey(key);
        if (x >= x0 && x <= x1 && y >= y0 && y <= y1) tiles.push(painted(x, y, cell));
      }
    }
  }
  const structures = layers.objects ? townStructures(doc) : [];
  // The renderer dims a structure whose hex is not in sight: every placed object's hex counts as
  // seen, on an unpainted hex or beyond the window as well (the window's painted tiles alone
  // would dim it).
  const sight = structures.length > 0 ? [...tiles, ...structures.map((s) => s.at)] : tiles;
  return {
    tiles,
    actors: [],
    adventurerId: -1,
    sight,
    arcs: null,
    path: [],
    dropped: [],
    selectedTile: null,
    structures,
    void: "water",
  };
}
