import { type Camera, type Viewport, tileToPixel } from "../input/coords";
import { isMirrored } from "../render/facing";
import type { SpriteLibrary } from "../render/sprites";
import type { Facing, Tile } from "../render/view";
import type { MapDocument } from "./model";
import { kindOf } from "./objects";
import { isPack } from "./pack";
import { type ThumbArt, kindOf as packKindOf } from "./palette";

/**
 * The pack's art the renderer does not draw in the editor (CLI-09e part 2), on the overlay's 2D
 * canvas, at the renderer's scale (one art pixel a world pixel) and anchored as the renderer
 * anchors a still (`defaultAnchor`, the art's baseline):
 *
 * - characters, always: the renderer's structures play stills only and the editor's view sends no
 *   actor (`view.ts`), so a character is drawn at its idle animation's frame 0;
 * - on a zone, the buildings, props and bridges too: the editor's view sends a town's structures
 *   alone (`view.ts`, `editorView`).
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

/** The sprite a character draws: its idle frame, mirrored on the West facings. */
export function npcSprite(type: string, at: Tile, facing: number): PackSprite | null {
  const kind = packKindOf(type);
  if (kind?.category !== "npc") return null;
  return {
    sprite: kind.sprite,
    animation: kind.animation,
    at,
    mirror: isMirrored(facing as Facing),
  };
}

/**
 * The pack's sprites of a map the overlay draws: its characters, and with `stills` (a zone) its
 * buildings, props and bridges as their kind's look draws them.
 */
export function packSprites(doc: MapDocument, stills: boolean): PackSprite[] {
  const out: PackSprite[] = [];
  for (const [, object] of [...doc.objects].sort(([a], [b]) => a - b)) {
    if (!isPack(object)) continue;
    if (object.kind === "npc") {
      const sprite = npcSprite(object.type, object.at, object.facing);
      if (sprite) out.push(sprite);
      continue;
    }
    if (!stills) continue;
    const look = kindOf(object).look?.(object);
    if (!look) continue;
    const mirror = look.mirror ?? ("mirror" in object && object.mirror);
    out.push({ sprite: look.sprite, animation: "still", at: object.at, mirror });
  }
  return out;
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
