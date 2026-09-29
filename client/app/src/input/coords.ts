import type { Tile } from "../render/view";

/**
 * Pixels to tiles and back: presentation only (ORCH-client-visual §6.4).
 *
 * Hexes are pointy-top (D-11), in the offset layout of the map library `hexx-cairo`
 * (`crates/hexx/src/board/layout.cairo`: "Pointy-top, odd-r offset, row-major: i = y * width + x";
 * `direction.cairo`: "Odd rows are drawn shifted half a tile toward increasing x"), which is the
 * layout of `origami_hexmap` the contracts use. The library's printer draws "rows top (y = H - 1)
 * to bottom, x = 0 on the right" (`printer.cairo`), and its directions agree: East is `i - 1`,
 * North-East `i + width - 1` on an even row. So on screen:
 *
 * - `x` grows toward the **left** (West), `y` grows **up** (North);
 * - odd rows are shifted half a tile to the left.
 *
 * World pixels are art pixels: a hex is `TILE_WIDTH` wide, the width of an art tile (design/10).
 * World `x` grows to the right and world `y` down, as on screen.
 */

/** Width of a hex, flat side to flat side, in art pixels (the art's 64 × 64 tile). */
export const TILE_WIDTH = 64;
/** Centre to corner. */
export const HEX_RADIUS = TILE_WIDTH / Math.sqrt(3);
/** Vertical distance between the centres of two rows. */
export const ROW_HEIGHT = HEX_RADIUS * 1.5;

export interface Point {
  readonly x: number;
  readonly y: number;
}

export interface Viewport {
  readonly width: number;
  readonly height: number;
}

/** What the screen shows: the world point at the viewport's centre, and CSS pixels per art pixel. */
export interface Camera {
  readonly centre: Point;
  readonly scale: number;
}

/** The centre of a tile, in world pixels. */
export function tileToPixel(tile: Tile): Point {
  return { x: -(tile.x + (tile.y & 1) / 2) * TILE_WIDTH, y: -tile.y * ROW_HEIGHT };
}

/** Squared distances closer than this (world px²) are equal: a point on a boundary. */
const TIE = 1e-6;

/**
 * The tile whose hex holds a world point: the tile with the nearest centre. **A point on the
 * boundary of two or three hexes goes to the lowest tile index** (`y`, then `x`), the tie-break of
 * design/04 *Ranges* ("when the line passes exactly between two tiles, the lower tile index is
 * taken").
 */
export function pixelToTile(point: Point): Tile {
  const row = Math.round(-point.y / ROW_HEIGHT);
  let best: Tile = { x: 0, y: 0 };
  let bestDistance = Infinity;
  for (let y = row - 1; y <= row + 1; y++) {
    const column = Math.round(-point.x / TILE_WIDTH - (y & 1) / 2);
    for (let x = column - 1; x <= column + 1; x++) {
      const centre = tileToPixel({ x, y });
      const distance = (centre.x - point.x) ** 2 + (centre.y - point.y) ** 2;
      const closer = distance < bestDistance - TIE;
      const tied = Math.abs(distance - bestDistance) <= TIE;
      if (closer || (tied && (y < best.y || (y === best.y && x < best.x)))) {
        best = { x, y };
        bestDistance = Math.min(distance, bestDistance);
      }
    }
  }
  return best;
}

export function worldToScreen(camera: Camera, viewport: Viewport, point: Point): Point {
  return {
    x: (point.x - camera.centre.x) * camera.scale + viewport.width / 2,
    y: (point.y - camera.centre.y) * camera.scale + viewport.height / 2,
  };
}

export function screenToWorld(camera: Camera, viewport: Viewport, point: Point): Point {
  return {
    x: (point.x - viewport.width / 2) / camera.scale + camera.centre.x,
    y: (point.y - viewport.height / 2) / camera.scale + camera.centre.y,
  };
}

export function tileToScreen(camera: Camera, viewport: Viewport, tile: Tile): Point {
  return worldToScreen(camera, viewport, tileToPixel(tile));
}

export function screenToTile(camera: Camera, viewport: Viewport, point: Point): Tile {
  return pixelToTile(screenToWorld(camera, viewport, point));
}

/**
 * The scale at which a hexagon of `across` tiles on its widest row (13 for sight of radius 6)
 * fits the viewport: by its width on a phone in portrait, by its height on a desktop (ADR-0006 §5).
 */
export function fitScale(viewport: Viewport, across: number): number {
  const width = across * TILE_WIDTH;
  const height = (across - 1) * ROW_HEIGHT + 2 * HEX_RADIUS;
  return Math.min(viewport.width / width, viewport.height / height);
}
