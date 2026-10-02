import { copyFileSync, mkdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, extname, join, relative, sep } from "node:path";

/**
 * The atlas copied into a production build's `dist/art/` (CV-03, used by `vite.config.ts` only,
 * never by the app). D-73: a local build of the Mac only, for the shell on the owner's phone; never
 * in CI's `dist/`, never committed, never distributed.
 */

/** `GRIMWORLD_EMBED_ART=1` turns the copy on; with `CI` set it is refused (thrown). */
export function embedArtWanted(env: Readonly<Record<string, string | undefined>>): boolean {
  if (env.GRIMWORLD_EMBED_ART !== "1") return false;
  if (env.CI) {
    throw new Error(
      "GRIMWORLD_EMBED_ART is refused when CI is set: the atlas never enters CI's dist/ (D-73)",
    );
  }
  return true;
}

const TYPES = new Set([".json", ".png"]);

/** A `.json` or `.png` file whose real path (symbolic links resolved) is inside the real root. */
function inside(realRoot: string, name: string): string {
  if (name.includes("\0") || !TYPES.has(extname(name).toLowerCase())) {
    throw new Error(`art: ${JSON.stringify(name)} is not a .json or .png of the atlas`);
  }
  let file: string;
  try {
    file = realpathSync(join(realRoot, name));
  } catch {
    throw new Error(`art: ${JSON.stringify(name)} is missing`);
  }
  if (!file.startsWith(realRoot + sep) || !statSync(file).isFile()) {
    throw new Error(`art: ${JSON.stringify(name)} is outside ${realRoot} or not a file`);
  }
  return file;
}

/**
 * The files of the atlas, relative to `root`: `sprites.json` and the pages it names (each page's
 * spritesheet `.json` and its `.png`), nothing else. Throws when the atlas is not built or a page
 * points out of the root.
 */
export function artFiles(root: string): string[] {
  let realRoot: string;
  try {
    realRoot = realpathSync(root);
  } catch {
    throw new Error(`art: ${root} not built (run tools/art, or set GRIMWORLD_ART_OUT)`);
  }
  let index: unknown;
  try {
    index = JSON.parse(readFileSync(inside(realRoot, "sprites.json"), "utf8"));
  } catch (error) {
    throw new Error(`art: ${root}/sprites.json unreadable (${(error as Error).message})`, {
      cause: error,
    });
  }
  const pages = (index as { pages?: unknown }).pages;
  if (!Array.isArray(pages)) throw new Error("art: sprites.json has no pages");
  const names = new Set(["sprites.json"]);
  for (const page of pages) {
    const { json, image } = (page ?? {}) as { json?: unknown; image?: unknown };
    if (typeof json !== "string") throw new Error("art: a page has no json");
    names.add(json);
    if (image !== undefined) {
      if (typeof image !== "string") throw new Error("art: a page's image is not a name");
      names.add(image);
    }
  }
  for (const name of names) inside(realRoot, name);
  return [...names].map((name) => relative(realRoot, join(realRoot, name)));
}

/** Copies `artFiles(root)` into `target` (a build's `dist/art/`); the names copied. */
export function embedArt(root: string, target: string): string[] {
  const realRoot = realpathSync(root);
  const names = artFiles(root);
  for (const name of names) {
    const to = join(target, name);
    mkdirSync(dirname(to), { recursive: true });
    copyFileSync(inside(realRoot, name), to);
  }
  return names;
}
