import { type Camera, ROW_HEIGHT, TILE_WIDTH, type Viewport, tileToPixel } from "../input/coords";
import { hexCorners } from "../render/ground";
import type { Tile } from "../render/view";
import { CHUNK, sideTable } from "./model";

/**
 * The editor's overlays (§2.3): plain shapes over the game's canvas, never art. They are drawn on
 * a 2D canvas laid over the renderer's, in the renderer's camera, after each of its frames: the
 * renderer is the game's, unchanged.
 */

/** Edges as world segments: `x0, y0, x1, y1` each. */
export type Segments = Float64Array;

/**
 * The edges between neighbouring hexes of a `width × height` map where `cut(a, b)` holds (an index
 * against another, or -1 beyond the map), each drawn once. An edge of side `s` runs between the
 * hex's corners `s` and `s + 1` (`hexCorners`, `acrossSide`).
 */
export function edgesWhere(
  width: number,
  height: number,
  cut: (index: number, other: number) => boolean,
): Segments {
  const table = sideTable(width, height);
  const out: number[] = [];
  for (let i = 0; i < width * height; i++) {
    let corners: number[] | null = null;
    for (let side = 0; side < 6; side++) {
      const other = table[i * 6 + side]!;
      // Each inner edge once: from its lower index.
      if (other >= 0 && other < i) continue;
      if (!cut(i, other)) continue;
      corners ??= hexCorners(tileToPixel({ x: i % width, y: Math.floor(i / width) }));
      const a = side * 2;
      const b = ((side + 1) % 6) * 2;
      out.push(corners[a]!, corners[a + 1]!, corners[b]!, corners[b + 1]!);
    }
  }
  return Float64Array.from(out);
}

/** The seams between chunks (§2.3), inside the map. */
export function seamSegments(width: number, height: number): Segments {
  const chunk = (i: number) =>
    Math.floor((i % width) / CHUNK) + 100 * Math.floor(i / width / CHUNK);
  return edgesWhere(width, height, (i, other) => other >= 0 && chunk(i) !== chunk(other));
}

/** The outline's border (§2.5): between an inside hex and an outside one or the map's edge. */
export function outlineSegments(width: number, height: number, outline: Uint8Array): Segments {
  return edgesWhere(width, height, (i, other) =>
    other < 0 ? outline[i] === 1 : outline[i] !== outline[other],
  );
}

/** The map's tiles whose hexes the viewport may show, as an index range per row. */
export function visibleRange(
  camera: Camera,
  viewport: Viewport,
  width: number,
  height: number,
): { x0: number; x1: number; y0: number; y1: number } {
  const halfW = viewport.width / 2 / camera.scale;
  const halfH = viewport.height / 2 / camera.scale;
  const { x: cx, y: cy } = camera.centre;
  // World x grows right and tile x left: x = -wx / TILE_WIDTH; y = -wy / ROW_HEIGHT.
  const x0 = Math.max(0, Math.floor(-(cx + halfW) / TILE_WIDTH) - 1);
  const x1 = Math.min(width - 1, Math.ceil(-(cx - halfW) / TILE_WIDTH) + 1);
  const y0 = Math.max(0, Math.floor(-(cy + halfH) / ROW_HEIGHT) - 1);
  const y1 = Math.min(height - 1, Math.ceil(-(cy - halfH) / ROW_HEIGHT) + 1);
  return { x0, x1, y0, y1 };
}

/** What one overlay frame draws. */
export interface OverlayScene {
  readonly width: number;
  readonly height: number;
  /** Inside the outline per hex (a zone with the outline layer on), else null. */
  readonly outline: Uint8Array | null;
  readonly outlineEdges: Segments | null;
  readonly seams: Segments | null;
  readonly grid: boolean;
  /** The hexes under the brush at the pointer. */
  readonly brush: readonly Tile[];
  readonly hover: Tile | null;
}

/** Below this hex width on screen (CSS px), the grid is not drawn: it would be a grey wash. */
export const GRID_MIN_PX = 7;
/** Below this hex width on screen (CSS px), the outside is shaded by runs of a row. */
export const RUN_BELOW_PX = 14;

const COLOURS = {
  outside: "rgba(8, 8, 14, 0.55)",
  outline: "#ffd23f",
  seam: "rgba(255, 255, 255, 0.7)",
  grid: "rgba(0, 0, 0, 0.28)",
  brush: "#ffffff",
  label: "rgba(255, 255, 255, 0.85)",
} as const;

/** Draws the overlays in the renderer's camera. */
export function drawOverlays(
  ctx: CanvasRenderingContext2D,
  camera: Camera,
  viewport: Viewport,
  scene: OverlayScene,
): void {
  const { scale, centre } = camera;
  const ox = viewport.width / 2 - centre.x * scale;
  const oy = viewport.height / 2 - centre.y * scale;
  ctx.clearRect(0, 0, viewport.width, viewport.height);
  const range = visibleRange(camera, viewport, scene.width, scene.height);
  const hexPath = (tile: Tile, grow = 0) => {
    const corners = hexCorners(tileToPixel(tile), grow);
    ctx.moveTo(corners[0]! * scale + ox, corners[1]! * scale + oy);
    for (let k = 2; k < 12; k += 2)
      ctx.lineTo(corners[k]! * scale + ox, corners[k + 1]! * scale + oy);
    ctx.closePath();
  };
  const each = (visit: (tile: Tile, index: number) => void) => {
    for (let y = range.y0; y <= range.y1; y++) {
      for (let x = range.x0; x <= range.x1; x++) visit({ x, y }, y * scene.width + x);
    }
  };
  // Outside the outline: shaded (§2.5). Small hexes are shaded by runs of a row, one rectangle a
  // row high from flat side to flat side: tens of thousands of hexes in a few hundred rectangles.
  if (scene.outline) {
    const outline = scene.outline;
    ctx.beginPath();
    if (TILE_WIDTH * scale >= RUN_BELOW_PX) {
      each((tile, i) => {
        if (!outline[i]) hexPath(tile, 0.5);
      });
    } else {
      for (let y = range.y0; y <= range.y1; y++) {
        let x = range.x0;
        while (x <= range.x1) {
          if (outline[y * scene.width + x]) {
            x += 1;
            continue;
          }
          const start = x;
          while (x <= range.x1 && !outline[y * scene.width + x]) x += 1;
          // x grows West: the run's right edge is its first hex's East side.
          const right = tileToPixel({ x: start, y }).x + TILE_WIDTH / 2;
          const top = tileToPixel({ x: start, y }).y - ROW_HEIGHT / 2;
          const width = (x - start) * TILE_WIDTH;
          ctx.rect(
            (right - width) * scale + ox,
            top * scale + oy,
            width * scale,
            ROW_HEIGHT * scale,
          );
        }
      }
    }
    ctx.fillStyle = COLOURS.outside;
    ctx.fill();
  }
  if (scene.grid && TILE_WIDTH * scale >= GRID_MIN_PX) {
    ctx.beginPath();
    each((tile) => hexPath(tile));
    ctx.strokeStyle = COLOURS.grid;
    ctx.lineWidth = 1;
    ctx.stroke();
  }
  const segments = (s: Segments) => {
    ctx.beginPath();
    for (let k = 0; k < s.length; k += 4) {
      const x0 = s[k]! * scale + ox;
      const y0 = s[k + 1]! * scale + oy;
      const x1 = s[k + 2]! * scale + ox;
      const y1 = s[k + 3]! * scale + oy;
      const out =
        (x0 < 0 && x1 < 0) ||
        (y0 < 0 && y1 < 0) ||
        (x0 > viewport.width && x1 > viewport.width) ||
        (y0 > viewport.height && y1 > viewport.height);
      if (out) continue;
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
    }
    ctx.stroke();
  };
  if (scene.seams) {
    ctx.setLineDash([6, 5]);
    ctx.strokeStyle = COLOURS.seam;
    ctx.lineWidth = 1.5;
    segments(scene.seams);
    ctx.setLineDash([]);
    // Each chunk's index in its top-right corner (tile (15 cx, 15 cy + 14)): x grows West.
    ctx.fillStyle = COLOURS.label;
    ctx.font = "600 0.75rem system-ui, sans-serif";
    ctx.textAlign = "right";
    ctx.textBaseline = "top";
    for (let cy = 0; cy * CHUNK < scene.height; cy++) {
      for (let cx = 0; cx * CHUNK < scene.width; cx++) {
        const corner = tileToPixel({ x: cx * CHUNK, y: cy * CHUNK + CHUNK - 1 });
        const sx = (corner.x + TILE_WIDTH / 2) * scale + ox - 4;
        const sy = (corner.y - TILE_WIDTH / 2) * scale + oy + 4;
        if (sx < 0 || sy < 0 || sx > viewport.width + 40 || sy > viewport.height) continue;
        ctx.fillText(String(CHUNK * cy + cx), sx, sy);
      }
    }
  }
  if (scene.outlineEdges) {
    ctx.strokeStyle = COLOURS.outline;
    ctx.lineWidth = Math.max(2, Math.min(4, TILE_WIDTH * scale * 0.08));
    ctx.lineCap = "round";
    segments(scene.outlineEdges);
  }
  if (scene.brush.length > 0) {
    ctx.beginPath();
    for (const tile of scene.brush) hexPath(tile, -1);
    ctx.strokeStyle = COLOURS.brush;
    ctx.lineWidth = 2;
    ctx.stroke();
  }
}
