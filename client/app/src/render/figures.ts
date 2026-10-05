import { Rectangle, type Texture } from "pixi.js";
import { foamDiagonal } from "./foam";
import type { Tile } from "./view";

/**
 * The characters' idle loop (CLI-09e part 3): a structure with an `animation` plays its frames at
 * the sprite's fps, on the actors' idle path (`IDLE_MAX_FPS`, nothing while the page is hidden,
 * `?idle=0` stops it). Its phase comes from its hex, as the foam's (`foam.ts`): world position only,
 * stable when the camera moves.
 *
 * The phase is `q + 3r` in axial coordinates: two neighbouring hexes differ by 1, 2 or 3 frames
 * (the six steps give ±1, ±3 and ±2), never by a whole loop of 4 frames or more (the pack's
 * characters have 6 to 12), so two characters side by side never breathe in step.
 */
export function figurePhase(tile: Tile): number {
  return foamDiagonal(tile, "q") + 3 * tile.y;
}

/** The frame a figure shows at `now` (ms), over `count` frames at `fps`, from its phase. */
export function figureFrame(now: number, fps: number, phase: number, count: number): number {
  if (count < 2) return 0;
  const tick = Math.floor((now * fps) / 1000 + 1e-6);
  return (((tick + phase) % count) + count) % count;
}

/** When the next frame of a loop at `fps` is due after `now` (ms): every figure shares it. */
export function nextFrameAt(now: number, fps: number): number {
  return ((Math.floor((now * fps) / 1000 + 1e-6) + 1) * 1000) / fps;
}

/** A structure that loops an animation, as the renderer keeps it. */
export interface FigureNode {
  readonly textures: readonly Texture[];
  readonly fps: number;
  readonly phase: number;
  /** Its art's box in the world: it asks for frames only while this is on the screen. */
  readonly bounds: Rectangle;
  /** Drawn and in colour: else it shows frame 0 and asks for nothing. */
  animates: boolean;
  /** Under fog beyond sight: frame 0 in grayscale. */
  grey: boolean;
}

/** The world box of a sprite of `width` × `height` anchored at (`ax`, `ay`) on `base`. */
export function spriteBounds(
  base: { readonly x: number; readonly y: number },
  width: number,
  height: number,
  ax: number,
  ay: number,
): Rectangle {
  // A mirror flips about the anchor: the wider side either way.
  const half = Math.max(ax, 1 - ax) * width;
  return new Rectangle(base.x - half, base.y - ay * height, 2 * half, height);
}
