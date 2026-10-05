import { type Camera, ROW_HEIGHT, TILE_WIDTH, type Viewport, tileToPixel } from "../input/coords";
import { hexCorners } from "../render/ground";
import type { Tile } from "../render/view";
import { type Fitted, chunkAt } from "./fit";
import { VIEW_MAX } from "./view";
import {
  CHUNK,
  type MapDocument,
  type TileBox,
  isOutside,
  isZone,
  keyOf,
  sideOf,
  tileOfKey,
} from "./model";

/**
 * The editor's overlays (§2.3): plain shapes over the game's canvas, never art. They are drawn on
 * a 2D canvas laid over the renderer's, in the renderer's camera, after each of its frames: the
 * renderer is the game's, unchanged.
 */

/** Edges as world segments: `x0, y0, x1, y1` each. */
export type Segments = Float64Array;

/**
 * The edges of the hexes `tiles` where `cut(tile, next)` holds, `next` the hex across the side. An
 * edge of side `s` runs between the hex's corners `s` and `s + 1` (`hexCorners`, `acrossSide`).
 */
export function edgesWhere(
  tiles: Iterable<Tile>,
  cut: (tile: Tile, next: Tile) => boolean,
): Segments {
  const out: number[] = [];
  for (const tile of tiles) {
    let corners: number[] | null = null;
    for (let side = 0; side < 6; side++) {
      if (!cut(tile, sideOf(tile, side))) continue;
      corners ??= hexCorners(tileToPixel(tile));
      const a = side * 2;
      const b = ((side + 1) % 6) * 2;
      out.push(corners[a]!, corners[a + 1]!, corners[b]!, corners[b + 1]!);
    }
  }
  return Float64Array.from(out);
}

/**
 * The outline's border (§2.5): between a painted hex inside and a hex outside or unpainted, each
 * edge once (from its inside hex).
 */
export function outlineSegments(doc: MapDocument): Segments {
  if (!isZone(doc)) return new Float64Array(0);
  const inside = (key: number) => {
    const cell = doc.hexes.get(key);
    return cell !== undefined && !isOutside(cell);
  };
  const tiles = [...doc.hexes.keys()].filter(inside).map(tileOfKey);
  return edgesWhere(tiles, (_, next) => !inside(keyOf(next)));
}

/** The fitted grid (D-216): the seams around the chunks of the set, and each chunk's index. */
export interface Seams {
  readonly segments: Segments;
  /** World points of each chunk's top-right corner, with its index. */
  readonly labels: readonly { readonly x: number; readonly y: number; readonly text: string }[];
}

export function seamSegments(fit: Fitted): Seams {
  const inSet = new Set(fit.chunkSet);
  const tiles: Tile[] = [];
  const labels: { x: number; y: number; text: string }[] = [];
  for (const chunk of fit.chunkSet) {
    const cx = chunk % CHUNK;
    const cy = Math.floor(chunk / CHUNK);
    const x = fit.x0 + CHUNK * cx;
    const y = fit.y0 + CHUNK * cy;
    for (let dy = 0; dy < CHUNK; dy++)
      for (let dx = 0; dx < CHUNK; dx++) tiles.push({ x: x + dx, y: y + dy });
    // Its top-right corner: x grows West, y North.
    const corner = tileToPixel({ x, y: y + CHUNK - 1 });
    labels.push({
      x: corner.x + TILE_WIDTH / 2,
      y: corner.y - TILE_WIDTH / 2,
      text: String(chunk),
    });
  }
  const chunkOf = (t: Tile) => chunkAt(t, fit);
  const segments = edgesWhere(tiles, (tile, next) => {
    const a = chunkOf(tile);
    const b = chunkOf(next);
    if (a.cx === b.cx && a.cy === b.cy) return false;
    // Between two chunks of the set, once: from the lower key.
    const bIn =
      b.cx >= 0 && b.cy >= 0 && b.cx < fit.width && b.cy < fit.height && inSet.has(b.chunk);
    return !bIn || keyOf(tile) < keyOf(next);
  });
  return { segments, labels };
}

/** The tiles whose hexes the viewport may show (unbounded: the plane has no edge). */
export function visibleRange(camera: Camera, viewport: Viewport): TileBox {
  const halfW = viewport.width / 2 / camera.scale;
  const halfH = viewport.height / 2 / camera.scale;
  const { x: cx, y: cy } = camera.centre;
  // World x grows right and tile x left: x = -wx / TILE_WIDTH; y = -wy / ROW_HEIGHT.
  return {
    x0: Math.floor(-(cx + halfW) / TILE_WIDTH) - 1,
    x1: Math.ceil(-(cx - halfW) / TILE_WIDTH) + 1,
    y0: Math.floor(-(cy + halfH) / ROW_HEIGHT) - 1,
    y1: Math.ceil(-(cy - halfH) / ROW_HEIGHT) + 1,
  };
}

/** An object's marker (§2.3): a hex with a one- or two-letter label, never colour alone. */
export interface Marker {
  readonly tile: Tile;
  readonly label: string;
  /** A zone's object, a town's, or one the validation names. */
  readonly tone: "zone" | "town" | "fault";
}

/** What one overlay frame draws. */
export interface OverlayScene {
  /** Whether a hex is painted and outside the outline (a zone with the outline layer on), else null. */
  readonly outside: ((tile: Tile) => boolean) | null;
  readonly outlineEdges: Segments | null;
  readonly seams: Seams | null;
  readonly grid: boolean;
  /** The hexes under the brush at the pointer. */
  readonly brush: readonly Tile[];
  readonly hover: Tile | null;
  /** The objects' markers (the objects layer), a town's footprints shaded. */
  readonly markers?: readonly Marker[];
  readonly footprints?: readonly Tile[];
  /** The selection's hexes and objects' hexes. */
  readonly selected?: readonly Tile[];
  /** Select's box being dragged, between two hexes. */
  readonly box?: { readonly from: Tile; readonly to: Tile } | null;
  /** Where a paste or a move would land. */
  readonly ghost?: readonly Tile[];
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
  footprint: "rgba(120, 60, 20, 0.35)",
  zone: "#f2e9d0",
  town: "#d8ecff",
  fault: "#ff6b5b",
  markerText: "#14141c",
  selected: "#3df2ff",
  ghost: "rgba(61, 242, 255, 0.8)",
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
  const range = visibleRange(camera, viewport);
  const hexPath = (tile: Tile, grow = 0) => {
    const corners = hexCorners(tileToPixel(tile), grow);
    ctx.moveTo(corners[0]! * scale + ox, corners[1]! * scale + oy);
    for (let k = 2; k < 12; k += 2)
      ctx.lineTo(corners[k]! * scale + ox, corners[k + 1]! * scale + oy);
    ctx.closePath();
  };
  const each = (visit: (tile: Tile) => void) => {
    for (let y = range.y0; y <= range.y1; y++) {
      for (let x = range.x0; x <= range.x1; x++) visit({ x, y });
    }
  };
  // Outside the outline: shaded (§2.5), not past `VIEW_MAX` hexes in view (a far zoom's wash).
  // Small hexes are shaded by runs of a row, one rectangle a row high from flat side to flat side:
  // tens of thousands of hexes in a few hundred rectangles.
  const inView = (range.x1 - range.x0 + 1) * (range.y1 - range.y0 + 1);
  if (scene.outside && inView <= VIEW_MAX) {
    const outside = scene.outside;
    ctx.beginPath();
    if (TILE_WIDTH * scale >= RUN_BELOW_PX) {
      each((tile) => {
        if (outside(tile)) hexPath(tile, 0.5);
      });
    } else {
      for (let y = range.y0; y <= range.y1; y++) {
        let x = range.x0;
        while (x <= range.x1) {
          if (!outside({ x, y })) {
            x += 1;
            continue;
          }
          const start = x;
          while (x <= range.x1 && outside({ x, y })) x += 1;
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
    segments(scene.seams.segments);
    ctx.setLineDash([]);
    // Each chunk's index in its top-right corner.
    ctx.fillStyle = COLOURS.label;
    ctx.font = "600 0.75rem system-ui, sans-serif";
    ctx.textAlign = "right";
    ctx.textBaseline = "top";
    for (const label of scene.seams.labels) {
      const sx = label.x * scale + ox - 4;
      const sy = label.y * scale + oy + 4;
      if (sx < 0 || sy < 0 || sx > viewport.width + 40 || sy > viewport.height) continue;
      ctx.fillText(label.text, sx, sy);
    }
  }
  if (scene.outlineEdges) {
    ctx.strokeStyle = COLOURS.outline;
    ctx.lineWidth = Math.max(2, Math.min(4, TILE_WIDTH * scale * 0.08));
    ctx.lineCap = "round";
    segments(scene.outlineEdges);
  }
  const hexPx = TILE_WIDTH * scale;
  const onScreen = (tile: Tile) => {
    const p = tileToPixel(tile);
    const x = p.x * scale + ox;
    const y = p.y * scale + oy;
    return x > -hexPx && y > -hexPx && x < viewport.width + hexPx && y < viewport.height + hexPx;
  };
  if (scene.footprints && scene.footprints.length > 0) {
    ctx.beginPath();
    for (const tile of scene.footprints) if (onScreen(tile)) hexPath(tile, 0.5);
    ctx.fillStyle = COLOURS.footprint;
    ctx.fill();
  }
  if (scene.markers && scene.markers.length > 0) {
    // A marker: an inset hex filled by its tone, outlined dark, its letters in the middle. Below
    // 10 CSS px a hex, a dot.
    const small = hexPx < 10;
    ctx.font = `700 ${Math.max(9, Math.min(15, hexPx * 0.32))}px system-ui, sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    // Several objects on one hex: the labels joined.
    const byHex = new Map<string, Marker[]>();
    for (const m of scene.markers) {
      if (!onScreen(m.tile)) continue;
      const k = `${m.tile.x},${m.tile.y}`;
      byHex.set(k, [...(byHex.get(k) ?? []), m]);
    }
    for (const list of byHex.values()) {
      const tile = list[0]!.tile;
      const tone = list.some((m) => m.tone === "fault") ? "fault" : list[0]!.tone;
      const p = tileToPixel(tile);
      const x = p.x * scale + ox;
      const y = p.y * scale + oy;
      ctx.fillStyle = COLOURS[tone];
      if (small) {
        ctx.beginPath();
        ctx.arc(x, y, 3, 0, Math.PI * 2);
        ctx.fill();
        continue;
      }
      ctx.beginPath();
      hexPath(tile, -hexPx * 0.12 / scale);
      ctx.globalAlpha = 0.85;
      ctx.fill();
      ctx.globalAlpha = 1;
      ctx.strokeStyle = COLOURS.markerText;
      ctx.lineWidth = 1.5;
      ctx.stroke();
      ctx.fillStyle = COLOURS.markerText;
      ctx.fillText(list.map((m) => m.label).join(" "), x, y);
    }
  }
  if (scene.selected && scene.selected.length > 0) {
    ctx.beginPath();
    for (const tile of scene.selected) if (onScreen(tile)) hexPath(tile, -1);
    ctx.strokeStyle = COLOURS.selected;
    ctx.lineWidth = 2.5;
    ctx.stroke();
  }
  if (scene.box) {
    const a = tileToPixel(scene.box.from);
    const b = tileToPixel(scene.box.to);
    const half = TILE_WIDTH / 2;
    const x0 = (Math.min(a.x, b.x) - half) * scale + ox;
    const x1 = (Math.max(a.x, b.x) + half) * scale + ox;
    const y0 = (Math.min(a.y, b.y) - half) * scale + oy;
    const y1 = (Math.max(a.y, b.y) + half) * scale + oy;
    ctx.setLineDash([4, 3]);
    ctx.strokeStyle = COLOURS.selected;
    ctx.lineWidth = 1.5;
    ctx.strokeRect(x0, y0, x1 - x0, y1 - y0);
    ctx.setLineDash([]);
  }
  if (scene.ghost && scene.ghost.length > 0) {
    ctx.beginPath();
    for (const tile of scene.ghost) if (onScreen(tile)) hexPath(tile, -2);
    ctx.setLineDash([3, 3]);
    ctx.strokeStyle = COLOURS.ghost;
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.setLineDash([]);
  }
  if (scene.brush.length > 0) {
    ctx.beginPath();
    for (const tile of scene.brush) hexPath(tile, -1);
    ctx.strokeStyle = COLOURS.brush;
    ctx.lineWidth = 2;
    ctx.stroke();
  }
}
