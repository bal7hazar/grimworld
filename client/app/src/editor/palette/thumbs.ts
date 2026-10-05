import type { SpriteLibrary } from "../../render/sprites";
import type { Kind } from "./kinds";

/**
 * The palette's thumbnails (CLI-09e): one frame of the atlas the editor already loaded (`loadAtlas`,
 * the game's pages), cut from its page image. Nothing of the art is bundled: without an atlas, a
 * kind shows its label alone.
 */

/** One frame of a page: its image and its rectangle on it, in page pixels. */
export interface ThumbArt {
  readonly image: CanvasImageSource;
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;
}

/** A sprite's frame of an animation, or null when the atlas has none. */
export type ThumbLookup = (sprite: string, animation: string, frame: number) => ThumbArt | null;

/**
 * What a kind's thumbnail shows, facing East (unmirrored): an NPC's idle frame 0, a prop's first
 * sprite (a facing prop's East one), a building's or a bridge's still.
 */
export function thumbOf(kind: Kind): {
  readonly sprite: string;
  readonly animation: string;
  readonly frame: number;
} {
  switch (kind.category) {
    case "npc":
      return { sprite: kind.sprite, animation: kind.animation, frame: 0 };
    case "prop":
      return { sprite: kind.art[0]!, animation: "still", frame: 0 };
    default:
      return { sprite: kind.sprite, animation: "still", frame: 0 };
  }
}

/**
 * The lookup over a loaded library: a texture's frame on its page (PixiJS 8: `texture.frame`, in
 * the source's pixels; `texture.source.resource`, the page's image).
 */
export function thumbsFromLibrary(library: SpriteLibrary): ThumbLookup {
  return (sprite, animation, frame) => {
    const texture = library.get(sprite)?.animations[animation]?.textures[frame];
    if (!texture) return null;
    const image = texture.source.resource as CanvasImageSource | undefined;
    if (!image) return null;
    const { x, y, width, height } = texture.frame;
    return { image, x, y, w: width, h: height };
  };
}

/**
 * Where a frame of `w × h` goes in a square box of `box` px: whole multiples of a pixel when it
 * fits at 1 or more (pixel art stays crisp), else shrunk to fit; centred, its base on the box's
 * bottom (a building stands, a prop lies).
 */
export function thumbFit(
  w: number,
  h: number,
  box: number,
): {
  readonly scale: number;
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;
} {
  const fit = Math.min(box / w, box / h);
  const scale = fit >= 1 ? Math.floor(fit) : fit;
  const dw = w * scale;
  const dh = h * scale;
  return { scale, x: (box - dw) / 2, y: box - dh, w: dw, h: dh };
}

/** Draws a frame into a box's 2D context, nearest neighbour, mirrored when asked. */
export function drawThumb(
  ctx: CanvasRenderingContext2D,
  art: ThumbArt,
  box: number,
  mirrored = false,
): void {
  const at = thumbFit(art.w, art.h, box);
  ctx.clearRect(0, 0, box, box);
  ctx.imageSmoothingEnabled = false;
  ctx.save();
  if (mirrored) {
    ctx.translate(box, 0);
    ctx.scale(-1, 1);
  }
  ctx.drawImage(art.image, art.x, art.y, art.w, art.h, at.x, at.y, at.w, at.h);
  ctx.restore();
}
