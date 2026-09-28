// Headless check (ART-00, AC-4): the atlases of ../out parse in PixiJS 8, and every animation of
// every sprite resolves to frames. Parsing is done by PixiJS's own `Spritesheet`, the class
// `Assets.load` hands a .json atlas to; the texture is a stand-in of the PNG's real size, since
// Node has no image decoding for the GPU. Run: pnpm --dir tools/art/check check
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Spritesheet, Texture, TextureSource } from 'pixi.js';

const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'out');
const index = JSON.parse(readFileSync(join(out, 'sprites.json'), 'utf8'));
const problems = [];
const fail = (message) => problems.push(message);

/** Width and height from a PNG's IHDR chunk. */
function pngSize(path) {
  const head = readFileSync(path);
  if (head.toString('latin1', 1, 4) !== 'PNG') throw new Error(`${path}: not a PNG`);
  return { w: head.readUInt32BE(16), h: head.readUInt32BE(20) };
}

let frames = 0;
let animations = 0;
for (const [n, page] of index.pages.entries()) {
  const data = JSON.parse(readFileSync(join(out, page.json), 'utf8'));
  const png = pngSize(join(out, page.image));
  if (png.w !== data.meta.size.w || png.h !== data.meta.size.h) {
    fail(`${page.json}: meta.size ${data.meta.size.w}x${data.meta.size.h} differs from the PNG ${png.w}x${png.h}`);
  }
  const source = new TextureSource({ width: png.w, height: png.h, label: page.image });
  const sheet = new Spritesheet(new Texture({ source }), data);
  await sheet.parse();

  for (const [key, f] of Object.entries(data.frames)) {
    const t = sheet.textures[key];
    if (!t) { fail(`${page.json}: frame ${key} did not parse`); continue; }
    frames += 1;
    const { frame, sourceSize } = f;
    if (t.frame.width !== frame.w || t.frame.height !== frame.h || t.frame.x !== frame.x || t.frame.y !== frame.y) {
      fail(`${key}: texture frame differs from the JSON`);
    }
    if (t.orig.width !== sourceSize.w || t.orig.height !== sourceSize.h) {
      fail(`${key}: orig ${t.orig.width}x${t.orig.height} is not the cell ${sourceSize.w}x${sourceSize.h}`);
    }
    if (!t.defaultAnchor || t.defaultAnchor.x !== f.anchor.x || t.defaultAnchor.y !== f.anchor.y) {
      fail(`${key}: anchor lost`);
    }
  }

  // Every animation of every sprite of this page, as the index (sprites.json) declares them.
  for (const [name, sprite] of Object.entries(index.sprites)) {
    if (sprite.page !== n) continue;
    for (const [anim, info] of Object.entries(sprite.animations)) {
      const key = `${name}/${anim}`;
      const textures = sheet.animations[key];
      animations += 1;
      if (!textures || textures.length === 0) { fail(`${key}: no frames`); continue; }
      if (textures.length !== info.frames) fail(`${key}: ${textures.length} frames, expected ${info.frames}`);
      if (textures.some((t) => !t || t.frame.width === 0)) fail(`${key}: an empty frame`);
      if (textures.some((t) => t.orig.width !== sprite.cell.w || t.orig.height !== sprite.cell.h)) {
        fail(`${key}: frames do not all have the sprite's cell size`);
      }
    }
  }
  if (Object.keys(sheet.animations).length !== Object.keys(data.animations).length) {
    fail(`${page.json}: PixiJS resolved ${Object.keys(sheet.animations).length} animations of ${Object.keys(data.animations).length}`);
  }
  sheet.destroy?.(false);
}

if (problems.length) {
  console.error(problems.join('\n'));
  process.exit(1);
}
console.log(`PixiJS 8: ${index.pages.length} page(s), ${frames} frames, ${animations} animations parsed; every animation resolves to frames`);
