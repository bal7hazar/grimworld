import { type Camera, type Viewport, tileToPixel } from "../input/coords";
import type { SpriteLibrary } from "../render/sprites";
import type { Tile } from "../render/view";
import type { ThumbArt } from "./palette";

/**
 * The placement's preview of a pack object (CLI-09e part 2), on the overlay's 2D canvas, at the
 * renderer's scale (one art pixel a world pixel) and anchored as the renderer anchors a still
 * (`defaultAnchor`, the art's baseline). The objects placed are the renderer's (CLI-09e part 3:
 * `editorView` sends them as structures, characters in their idle loop): the overlay draws only the
 * preview, a character at its idle animation's frame 0.
 */

/** A frame of a page, with the anchor the renderer gives it (fractions of the frame). */
export interface SpriteArt extends ThumbArt {
  readonly ax: number;
  readonly ay: number;
}

export type SpriteLookup = (sprite: string, animation: string, frame: number) => SpriteArt | null;

/** The lookup over a loaded library (PixiJS 8: the texture's frame, page and anchor). */
export function spritesFromLibrary(library: SpriteLibrary): SpriteLookup {
  return (sprite, animation, frame) => {
    const texture = library.get(sprite)?.animations[animation]?.textures[frame];
    const image = texture?.source.resource as CanvasImageSource | undefined;
    if (!texture || !image) return null;
    const { x, y, width, height } = texture.frame;
    const anchor = texture.defaultAnchor;
    return { image, x, y, w: width, h: height, ax: anchor?.x ?? 0.5, ay: anchor?.y ?? 1 };
  };
}

/** One sprite to draw on a hex. */
export interface PackSprite {
  readonly sprite: string;
  readonly animation: string;
  readonly at: Tile;
  readonly mirror: boolean;
}

/** Draws sprites in the camera, the farther (higher on screen) first, as the renderer sorts. */
export function drawSprites(
  ctx: CanvasRenderingContext2D,
  camera: Camera,
  viewport: Viewport,
  sprites: readonly PackSprite[],
  lookup: SpriteLookup,
  alpha = 1,
): void {
  const { scale, centre } = camera;
  const ox = viewport.width / 2 - centre.x * scale;
  const oy = viewport.height / 2 - centre.y * scale;
  const placed = sprites
    .map((s) => ({ s, p: tileToPixel(s.at) }))
    .sort((a, b) => a.p.y - b.p.y || a.p.x - b.p.x);
  ctx.imageSmoothingEnabled = false;
  ctx.globalAlpha = alpha;
  for (const { s, p } of placed) {
    const art = lookup(s.sprite, s.animation, 0);
    if (!art) continue;
    const w = art.w * scale;
    const h = art.h * scale;
    const x = p.x * scale + ox;
    const y = p.y * scale + oy;
    if (x + w < 0 || x - w > viewport.width || y - h > viewport.height || y + h < 0) continue;
    ctx.save();
    ctx.translate(x, y);
    if (s.mirror) ctx.scale(-1, 1);
    ctx.drawImage(art.image, art.x, art.y, art.w, art.h, -art.ax * w, -art.ay * h, w, h);
    ctx.restore();
  }
  ctx.globalAlpha = 1;
}
