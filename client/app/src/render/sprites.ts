import type { Texture } from "pixi.js";

/**
 * The art as the renderer uses it: per sprite (a caste or a profession), its animations' frames and
 * rates, and its display scale. Read from `tools/art/out/sprites.json` and the atlas pages
 * (tools/art/README.md); the pixel sizes come from there, never from this code.
 */

/** `sprites.json`, as `tools/art` writes it. `scale` is optional: 1 when absent. */
export interface SpritesIndex {
  readonly pages: readonly { readonly json: string; readonly image: string }[];
  readonly sprites: Readonly<Record<string, SpriteEntry>>;
}

export interface SpriteEntry {
  readonly role: string;
  readonly page: number;
  readonly cell: { readonly w: number; readonly h: number };
  readonly baseline: number;
  readonly scale?: number;
  readonly animations: Readonly<
    Record<string, { readonly frames: number; readonly fps: number; readonly loop: boolean }>
  >;
}

export interface SpriteAnimation {
  readonly textures: readonly Texture[];
  readonly fps: number;
  readonly loop: boolean;
}

export interface SpriteArt {
  readonly name: string;
  readonly role: string;
  readonly cell: { readonly w: number; readonly h: number };
  readonly baseline: number;
  /** The scale `sprites.json` gives (1 when it gives none): the starting point of the panel. */
  readonly scale: number;
  readonly animations: Readonly<Record<string, SpriteAnimation>>;
}

export type SpriteLibrary = ReadonlyMap<string, SpriteArt>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** Checks the shape of `sprites.json`; null when it is not one. */
export function readSpritesIndex(json: unknown): SpritesIndex | null {
  if (!isRecord(json) || !Array.isArray(json.pages) || !isRecord(json.sprites)) return null;
  for (const page of json.pages) {
    if (!isRecord(page) || typeof page.json !== "string") return null;
  }
  for (const entry of Object.values(json.sprites)) {
    if (!isRecord(entry) || typeof entry.page !== "number" || typeof entry.baseline !== "number")
      return null;
    if (!isRecord(entry.cell) || !isRecord(entry.animations)) return null;
  }
  return json as unknown as SpritesIndex;
}

/** The library from the index and each page's parsed animations (`Spritesheet.animations`). */
export function libraryFrom(
  index: SpritesIndex,
  pages: readonly { readonly animations: Readonly<Record<string, Texture[]>> }[],
): SpriteLibrary {
  const library = new Map<string, SpriteArt>();
  for (const [name, entry] of Object.entries(index.sprites)) {
    const page = pages[entry.page];
    if (!page) continue;
    const animations: Record<string, SpriteAnimation> = {};
    for (const [anim, info] of Object.entries(entry.animations)) {
      const textures = page.animations[`${name}/${anim}`];
      if (textures && textures.length > 0) {
        animations[anim] = { textures, fps: info.fps, loop: info.loop };
      }
    }
    library.set(name, {
      name,
      role: entry.role,
      cell: entry.cell,
      baseline: entry.baseline,
      scale: typeof entry.scale === "number" && entry.scale > 0 ? entry.scale : 1,
      animations,
    });
  }
  return library;
}
