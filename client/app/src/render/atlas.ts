import { Assets, type Spritesheet } from "pixi.js";
import { type SpriteLibrary, libraryFrom, readSpritesIndex } from "./sprites";

/**
 * Where the development server serves `tools/art/out/` when it exists (`vite.config.ts`). Nothing
 * of the art is imported by a module or bundled: without it, the sandbox draws shapes.
 */
export const ART_BASE = "/art/";

export interface AtlasLoaders {
  fetchJson(url: string): Promise<unknown>;
  loadSheet(url: string): Promise<Pick<Spritesheet, "animations" | "textureSource">>;
}

const browserLoaders: AtlasLoaders = {
  async fetchJson(url) {
    const response = await fetch(url);
    if (!response.ok) return null;
    // A server without the art may answer with its HTML page: not an index.
    return response.json().catch(() => null);
  },
  // Absolute, resolved against the page: PixiJS resolves a path from the root against an
  // http(s) origin only, so in the iOS shell `/art/…` would become `capacitor://art/…` (CV-03).
  loadSheet: (url) => Assets.load<Spritesheet>(new URL(url, document.baseURI).href),
};

/**
 * The sprite library from the atlas `tools/art` built, or null when there is none. Textures are
 * scaled nearest-neighbour (pixel art).
 */
export async function loadAtlas(
  base = ART_BASE,
  loaders: AtlasLoaders = browserLoaders,
): Promise<SpriteLibrary | null> {
  let json: unknown;
  try {
    json = await loaders.fetchJson(`${base}sprites.json`);
  } catch {
    return null;
  }
  if (json === null || json === undefined) return null;
  const read = readSpritesIndex(json);
  if ("problem" in read) {
    console.error(`[sandbox] sprites.json refused (${read.problem}); drawing shapes`);
    return null;
  }
  const { index } = read;
  const sheets = await Promise.all(index.pages.map((page) => loaders.loadSheet(base + page.json)));
  for (const sheet of sheets) sheet.textureSource.scaleMode = "nearest";
  return libraryFrom(index, sheets);
}
