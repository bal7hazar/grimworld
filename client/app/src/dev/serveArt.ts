import { readFileSync, realpathSync, statSync } from "node:fs";
import { extname, join, sep } from "node:path";

/**
 * The development server's `/art/` handler (used by `vite.config.ts` only, never by the app): a
 * file of the atlas `tools/art` built, or 404. Only `.json` and `.png`, and only files whose real
 * path (symbolic links resolved) is inside the real root.
 */

const TYPES: Readonly<Record<string, string>> = {
  ".json": "application/json",
  ".png": "image/png",
};

export type ArtResponse =
  { readonly status: 200; readonly type: string; readonly body: Buffer } | { readonly status: 404 };

const NOT_FOUND: ArtResponse = { status: 404 };

/** `url` is the request's path below `/art` (with its query, if any). */
export function serveArt(root: string, url: string): ArtResponse {
  let path: string;
  try {
    path = decodeURIComponent(url.split("?")[0] ?? "/");
  } catch {
    return NOT_FOUND;
  }
  if (path.includes("\0")) return NOT_FOUND;
  let realRoot: string;
  let file: string;
  try {
    realRoot = realpathSync(root);
    file = realpathSync(join(realRoot, path));
  } catch {
    return NOT_FOUND;
  }
  const type = TYPES[extname(file).toLowerCase()];
  if (!type || !file.startsWith(realRoot + sep) || !statSync(file).isFile()) return NOT_FOUND;
  return { status: 200, type, body: readFileSync(file) };
}
