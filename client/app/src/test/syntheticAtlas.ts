import { BufferImageSource, Spritesheet, type SpritesheetData, Texture } from "pixi.js";
import type { SpritesIndex } from "../render/sprites";

/**
 * A small atlas made in the test, in the format of `tools/art` (TexturePacker "hash" with
 * `animations`, and `sprites.json`), on a texture of plain colours. Nothing of the art pack.
 * One sprite, `runt`: idle (4 frames, 12 fps) and move (2 frames, 12 fps), cells of 32 × 40 with
 * the feet at 36.
 */
export const SYNTHETIC_INDEX: SpritesIndex = {
  pages: [{ json: "atlas-0.json", image: "atlas-0.png" }],
  sprites: {
    runt: {
      role: "caste",
      page: 0,
      cell: { w: 32, h: 40 },
      baseline: 36,
      animations: {
        idle: { frames: 4, fps: 12, loop: true },
        move: { frames: 2, fps: 12, loop: true },
      },
    },
  },
};

export function syntheticSheetJson(): SpritesheetData & {
  meta: { size: { w: number; h: number } };
} {
  const frames: SpritesheetData["frames"] = {};
  const animations: Record<string, string[]> = {};
  let x = 0;
  for (const [anim, count] of [
    ["idle", 4],
    ["move", 2],
  ] as const) {
    animations[`runt/${anim}`] = [];
    for (let i = 0; i < count; i++) {
      const key = `runt/${anim}/${String(i).padStart(2, "0")}`;
      frames[key] = {
        frame: { x, y: 0, w: 32, h: 40 },
        rotated: false,
        trimmed: false,
        spriteSourceSize: { x: 0, y: 0, w: 32, h: 40 },
        sourceSize: { w: 32, h: 40 },
        anchor: { x: 0.5, y: 0.9 },
      };
      animations[`runt/${anim}`]!.push(key);
      x += 32;
    }
  }
  return {
    frames,
    animations,
    meta: { image: "atlas-0.png", format: "RGBA8888", size: { w: x, h: 40 }, scale: "1" },
  };
}

/** The synthetic page, parsed by PixiJS's own `Spritesheet`, on a plain-colour buffer. */
export async function syntheticSheet(): Promise<Spritesheet> {
  const json = syntheticSheetJson();
  const { w, h } = json.meta.size;
  const pixels = new Uint8Array(w * h * 4);
  for (let i = 0; i < pixels.length; i += 4) pixels.set([200, 60, 60, 255], i);
  const source = new BufferImageSource({ resource: pixels, width: w, height: h });
  const sheet = new Spritesheet(new Texture({ source }), json);
  await sheet.parse();
  return sheet;
}
