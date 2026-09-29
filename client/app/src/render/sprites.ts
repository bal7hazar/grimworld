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

/**
 * Frame rates accepted from `sprites.json`: finite, within 1..30 (ADR-0003's 12–15 inside). A
 * rate outside would schedule frames without pause (negative) or never (0).
 */
export const FPS_RANGE = { min: 1, max: 30 } as const;

const finite = (value: unknown, min: number, max: number): value is number =>
  typeof value === "number" && Number.isFinite(value) && value >= min && value <= max;

/**
 * Checks `sprites.json`: its shape, and every number the renderer schedules or sizes with (frame
 * rates, frame counts, cells, baseline, scale). The first problem found, or the index.
 */
export function readSpritesIndex(
  json: unknown,
): { readonly index: SpritesIndex } | { readonly problem: string } {
  if (!isRecord(json) || !Array.isArray(json.pages) || !isRecord(json.sprites)) {
    return { problem: "not a sprites index (pages, sprites)" };
  }
  for (const page of json.pages) {
    if (!isRecord(page) || typeof page.json !== "string") return { problem: "a page has no json" };
  }
  for (const [name, entry] of Object.entries(json.sprites)) {
    if (!isRecord(entry) || !Number.isInteger(entry.page) || !isRecord(entry.cell)) {
      return { problem: `${name}: no page or cell` };
    }
    if (!finite(entry.cell.w, 1, 4096) || !finite(entry.cell.h, 1, 4096)) {
      return { problem: `${name}: cell out of range` };
    }
    if (!finite(entry.baseline, 0, entry.cell.h))
      return { problem: `${name}: baseline out of range` };
    if (entry.scale !== undefined && !finite(entry.scale, 0.05, 10)) {
      return { problem: `${name}: scale out of range` };
    }
    if (!isRecord(entry.animations)) return { problem: `${name}: no animations` };
    for (const [anim, info] of Object.entries(entry.animations)) {
      if (!isRecord(info)) return { problem: `${name}/${anim}: not an animation` };
      if (!finite(info.fps, FPS_RANGE.min, FPS_RANGE.max)) {
        return {
          problem: `${name}/${anim}: fps ${String(info.fps)} outside ${FPS_RANGE.min}..${FPS_RANGE.max}`,
        };
      }
      if (!Number.isInteger(info.frames) || !finite(info.frames, 1, 1000)) {
        return { problem: `${name}/${anim}: frames out of range` };
      }
    }
  }
  return { index: json as unknown as SpritesIndex };
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
      scale: entry.scale ?? 1,
      animations,
    });
  }
  return library;
}
