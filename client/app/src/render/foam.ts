import { Mesh, MeshGeometry, Rectangle, Texture } from "pixi.js";
import { FOAM_SIZE, type FoamPiece } from "./ground";
import type { Tile } from "./view";

/**
 * The foam animated (CLI-03o): the pack's `Water Foam` loop (`foam_c/loop`, 16 frames of 192 px,
 * 10 fps, `tools/art`), drawn over the chunks instead of baked into them, so that a frame changes
 * by rewriting the texture coordinates of a few meshes, never by baking a chunk again.
 *
 * Phase (the orchestrator's rule, reversible): each foam cell is centred under one land hex (its
 * piece's `source`); every source on one diagonal shows the same frame, and each next diagonal is
 * one frame later. World position only: seamless across chunks, stable when the camera moves.
 */

/** The foam's rate when the atlas gives none: the pack's (`Water Foam.aseprite`, 100 ms a frame). */
export const FOAM_FPS = 10;

/**
 * The diagonal the phase runs along, in axial coordinates (`q = x − ⌊y / 2⌋`, `r = y`): sources
 * with the same `q + r` share a frame (CLI-03o's report). `r` alone gives a whole row one frame,
 * so a straight East–West shore (the hubs') would pulse in lockstep; `q` and `q + r` both move one
 * frame per hex along a row and one per two rows up a North–South shore, so every shore shows a
 * wave. `q + r` (`x + ⌈y / 2⌉`) is kept: a crest travels from West to East and from North to
 * South, toward the screen's bottom right.
 */
export type FoamAxis = "q" | "r" | "q+r";
export const FOAM_AXIS: FoamAxis = "q+r";

/** A tile's index along the phase's axis: one more per diagonal. */
export function foamDiagonal(tile: Tile, axis: FoamAxis = FOAM_AXIS): number {
  const q = tile.x - Math.floor(tile.y / 2);
  const r = tile.y;
  return axis === "q" ? q : axis === "r" ? r : q + r;
}

/** The frame a source shows at a clock's frame count (`tick`), over `count` frames. */
export function foamFrame(
  tick: number,
  source: Tile,
  count: number,
  axis: FoamAxis = FOAM_AXIS,
): number {
  return (((tick + foamDiagonal(source, axis)) % count) + count) % count;
}

/** `?water=still`: the foam still (frame 0, as before CLI-03o), to compare; else it loops. */
export type WaterMode = "loop" | "still";

export function readWater(search: string): WaterMode {
  return new URLSearchParams(search).get("water") === "still" ? "still" : "loop";
}

/** The page's `?water=`, or `loop` outside a browser. */
export function pageWater(): WaterMode {
  const search = (globalThis as { location?: { search?: string } }).location?.search;
  return readWater(search ?? "");
}

/**
 * Foam pieces as one mesh: each piece a fan of triangles on its own vertices, so that each carries
 * the texture coordinates of its source's frame. The positions never change; `show` rewrites the
 * coordinates when the frame does. The texture is the frames' whole page: the mesh's coordinates
 * are page coordinates, the frames' rectangles in it.
 */
export class FoamMesh {
  readonly mesh: Mesh<MeshGeometry>;
  /** The pieces' box, in world pixels: whether the mesh is on screen. */
  bounds = new Rectangle();
  pieces: readonly FoamPiece[] = [];
  /** Per vertex: its position in its foam cell, in cell pixels. */
  private local = new Float32Array(0);
  /** Per vertex: its source's diagonal. */
  private diagonal = new Int32Array(0);
  private uvs = new Float32Array(0);
  private shown: number | null | undefined = undefined;

  constructor(
    pieces: readonly FoamPiece[],
    private readonly frames: readonly Texture[],
  ) {
    const page = frames[0] ? new Texture({ source: frames[0].source }) : Texture.EMPTY;
    this.mesh = new Mesh({ geometry: new MeshGeometry({}), texture: page });
    this.setPieces(pieces);
  }

  /**
   * Draws other pieces with the same mesh: its buffers' contents change, the scene does not (no
   * child added or removed, so PixiJS does not rebuild the stage's instructions). The frame shown
   * is kept.
   */
  setPieces(pieces: readonly FoamPiece[]): void {
    this.pieces = pieces;
    let vertices = 0;
    let triangles = 0;
    for (const { points } of pieces) {
      vertices += points.length / 2;
      triangles += points.length / 2 - 2;
    }
    const positions = new Float32Array(2 * vertices);
    this.local = new Float32Array(2 * vertices);
    this.diagonal = new Int32Array(vertices);
    this.uvs = new Float32Array(2 * vertices);
    const indices = new Uint32Array(3 * triangles);
    let v = 0;
    let i = 0;
    let [x0, y0, x1, y1] = [Infinity, Infinity, -Infinity, -Infinity];
    for (const { points, origin, source } of pieces) {
      const first = v;
      const diagonal = foamDiagonal(source);
      for (let k = 0; k < points.length; k += 2) {
        const [x, y] = [points[k]!, points[k + 1]!];
        positions[2 * v] = x;
        positions[2 * v + 1] = y;
        this.local[2 * v] = x - origin.x;
        this.local[2 * v + 1] = y - origin.y;
        this.diagonal[v] = diagonal;
        [x0, y0, x1, y1] = [Math.min(x0, x), Math.min(y0, y), Math.max(x1, x), Math.max(y1, y)];
        v += 1;
      }
      for (let k = 1; k < points.length / 2 - 1; k++) {
        indices[i++] = first;
        indices[i++] = first + k;
        indices[i++] = first + k + 1;
      }
    }
    this.bounds = vertices > 0 ? new Rectangle(x0, y0, x1 - x0, y1 - y0) : new Rectangle();
    const { geometry } = this.mesh;
    geometry.positions = positions;
    geometry.uvs = this.uvs;
    geometry.indices = indices;
    const shown = this.shown;
    this.shown = undefined;
    this.show(shown ?? null);
  }

  /**
   * Shows the frames of a clock's frame count (`tick`), or every source at frame 0 (`null`: still);
   * whether the coordinates changed.
   */
  show(tick: number | null): boolean {
    const count = this.frames.length;
    const key = tick === null || count < 2 ? null : ((tick % count) + count) % count;
    if (key === this.shown) return false;
    this.shown = key;
    const first = this.frames[0];
    if (!first) return true;
    const { width, height } = first.source;
    for (let v = 0; v < this.diagonal.length; v++) {
      const index = key === null ? 0 : (((key + this.diagonal[v]!) % count) + count) % count;
      const { frame } = this.frames[index]!;
      // A cell of FOAM_SIZE art px on a frame of that size: a synthetic atlas's may be smaller.
      this.uvs[2 * v] = (frame.x + (this.local[2 * v]! * frame.width) / FOAM_SIZE) / width;
      this.uvs[2 * v + 1] =
        (frame.y + (this.local[2 * v + 1]! * frame.height) / FOAM_SIZE) / height;
    }
    this.mesh.geometry.getBuffer("aUV").update();
    return true;
  }

  /** The frame count last shown (modulo the frames), or null when still. */
  shownTick(): number | null {
    return this.shown ?? null;
  }

  destroy(): void {
    const page = this.mesh.texture;
    const geometry = this.mesh.geometry;
    this.mesh.destroy({ children: true });
    // PixiJS's mesh leaves its geometry: its buffers go with it here.
    geometry.destroy(true);
    // The page's own texture stays: only the view made for the mesh goes.
    if (page !== Texture.EMPTY) page.destroy(false);
  }
}

/** Whether two rectangles overlap (an edge shared is not an overlap). */
export function overlaps(a: Rectangle, b: Rectangle): boolean {
  return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
}
