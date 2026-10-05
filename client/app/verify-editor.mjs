/* global console, process, fetch, setTimeout, localStorage, Buffer, URL */
/* eslint-disable no-empty */
// The map editor in a real browser (CLI-09a, CLI-09a2): at 1440 × 900, with the art and in the plain
// look (the art's `/art/` answered 404), a zone is created with no size, painted away from the
// origin, outlined, its chunks fitted and nudged, saved, opened again from its file and saved
// again: the two files are identical. Also: a format 1 file opens converted, a stroke survives a
// reload within the draft's delay, a blur ends the Space pan mode. Run by hand, not by CI:
// `node verify-editor.mjs`. Starts the dev server as its own process group and sends SIGTERM to that
// recorded group in `finally`. The server inherits GRIMWORLD_ART_OUT (the built atlas, D-73: never
// committed).
//
// Shots of each step into VERIFY_SHOTS_DIR (default the untracked `.verify-out/`; D-73: the shots
// with the art are never committed, attached or posted).
//
// Env: VERIFY_PORT (default 5199), VERIFY_CHANNEL, VERIFY_ROOT (the checkout whose dev server runs;
// default this one), VERIFY_SHOTS_DIR.
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5199);
const base = `http://127.0.0.1:${port}`;
const root = process.env.VERIFY_ROOT ?? join(here, "..", "..");
const shots = process.env.VERIFY_SHOTS_DIR ?? join(here, ".verify-out");
mkdirSync(shots, { recursive: true });

let failures = 0;
function ok(condition, message) {
  console.log(`  ${condition ? "ok  " : "FAIL"} ${message}`);
  if (!condition) failures += 1;
}

const server = spawn(
  "pnpm",
  [
    "--filter",
    "@grimworld/app",
    "dev",
    "--host",
    "127.0.0.1",
    "--port",
    String(port),
    "--strictPort",
  ],
  { cwd: root, detached: true, stdio: ["ignore", "pipe", "pipe"] },
);
console.log(`dev server pid ${server.pid} (${root})`);
let log = "";
server.stdout.on("data", (d) => (log += d));
server.stderr.on("data", (d) => (log += d));

async function ready() {
  for (let i = 0; i < 100; i += 1) {
    try {
      if ((await fetch(`${base}/editor.html`)).ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`the dev server did not answer:\n${log}`);
}

/** A saved file's counts: floors, inside and outside hexes, and the painted box. */
function countFile(text) {
  const file = JSON.parse(text);
  let floors = 0;
  let inside = 0;
  let outside = 0;
  let x0 = Infinity;
  let x1 = -Infinity;
  let y0 = Infinity;
  let y1 = -Infinity;
  for (const row of file.rows) {
    floors += row.terrain.split(".").length - 1;
    inside += row.outline.split("1").length - 1;
    outside += row.outline.split("0").length - 1;
    x0 = Math.min(x0, row.x);
    x1 = Math.max(x1, row.x + row.terrain.length - 1);
    y0 = Math.min(y0, row.y);
    y1 = Math.max(y1, row.y);
  }
  return { file, floors, inside, outside, box: { x0, x1, y0, y1 } };
}

async function saveWith(page, path) {
  const [download] = await Promise.all([
    page.waitForEvent("download"),
    page.keyboard.press("Control+s"),
  ]);
  await download.saveAs(path);
  return readFileSync(path, "utf8");
}

/** A CLI-09a file (format 1): one chunk, walls, a floor row. */
function format1(name) {
  const rows = (row, other) => Array.from({ length: 15 }, (_, y) => (y === 3 ? row : other));
  return JSON.stringify({
    format: "grimworld-map",
    version: 1,
    editor: "cli-09a",
    map: {
      kind: "zone",
      name,
      location: 2,
      width: 1,
      height: 1,
      biome: "cave",
      start: "wall",
      levelMin: 1,
      levelMax: 1,
      rank: 0,
      spawnTable: 0,
    },
    layers: {
      terrain: rows(".".repeat(15), "#".repeat(15)),
      ground: rows("g".repeat(15), "g".repeat(15)),
      outline: rows("1".repeat(15), "1".repeat(15)),
    },
    obstacles: [],
  });
}

/** One look: "art" (the atlas served) or "plain" (`/art/` answers 404). */
async function run(browser, look) {
  console.log(`=== ${look} ===`);
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    acceptDownloads: true,
  });
  const foreign = [];
  await context.route("**/*", (route) => {
    const url = new URL(route.request().url());
    if (url.origin !== base) {
      foreign.push(url.href);
      return route.abort();
    }
    if (look === "plain" && url.pathname.startsWith("/art/")) {
      return route.fulfill({ status: 404, body: "" });
    }
    return route.continue();
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  // The plain look's `/art/` answers 404 on purpose: the browser logs it, the page does not fail.
  page.on("console", (m) => {
    const expected = look === "plain" && m.text().includes("status of 404");
    if (m.type() === "error" && !expected) errors.push(m.text());
  });
  const shot = (name) => page.screenshot({ path: join(shots, `editor-${look}-${name}.png`) });
  const text = (selector) => page.locator(selector).innerText();

  await page.goto(`${base}/editor.html`);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.locator('[data-screen="list"]').waitFor();
  ok(await page.getByText("No draft yet.").isVisible(), "the map list opens, no draft");

  // Create: no size in the dialog (D-216).
  await page.locator("[data-new-map]").click();
  ok((await page.locator('input[name="width"]').count()) === 0, "the new map dialog asks no size");
  await page.locator("#ed-name").fill(`Verify ${look}`);
  await page.locator("[data-confirm]").click();
  const canvas = page.locator("[data-canvas]");
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor();
  const atlas = await canvas.getAttribute("data-atlas");
  ok(atlas === (look === "art" ? "loaded" : "none"), `the art: ${atlas}`);
  ok((await text("[data-topbar]")).includes("0 hexes"), "an empty zone is open");
  ok((await text("[data-origin]")).includes("No chunk grid yet"), "no chunk grid while painting");
  await page.waitForTimeout(500);
  await shot("1-create");

  // Away from the origin: pan West eight quarter views and North three.
  for (let i = 0; i < 8; i += 1) await page.keyboard.press("ArrowLeft");
  for (let i = 0; i < 3; i += 1) await page.keyboard.press("ArrowUp");

  // Paint: walls with brush 4 in four strokes, floor inside, then water.
  const box = await canvas.boundingBox();
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;
  await page.locator('[data-swatch="terrain-wall"]').click();
  for (let i = 0; i < 3; i += 1) await page.keyboard.press("]");
  ok((await text("[data-armed]")).includes("brush 4"), "brush 4 from ]");
  for (const dy of [-150, -90, -30, 30, 90, 150]) {
    await page.mouse.move(cx - 330, cy + dy);
    await page.mouse.down();
    await page.mouse.move(cx + 330, cy + dy, { steps: 30 });
    await page.mouse.up();
  }
  await page.locator('[data-swatch="terrain-floor"]').click();
  for (const dy of [-60, 0, 60]) {
    await page.mouse.move(cx - 250, cy + dy);
    await page.mouse.down();
    await page.mouse.move(cx + 250, cy + dy, { steps: 30 });
    await page.mouse.up();
  }
  await page.locator('[data-swatch="ground-water"]').click();
  await page.mouse.move(cx, cy - 120);
  await page.mouse.down();
  await page.mouse.move(cx + 80, cy - 120, { steps: 8 });
  await page.mouse.up();
  await page.waitForTimeout(500);
  await shot("2-paint");
  // Undo the water, redo it.
  await page.keyboard.press("Control+z");
  await page.keyboard.press("Control+Shift+z");

  // Outline: from the floor, then a right drag marks some outside.
  await page.keyboard.press("t");
  await page.locator("[data-outline-from-floor]").click();
  await page.keyboard.press("[");
  await page.mouse.move(cx - 240, cy);
  await page.mouse.down({ button: "right" });
  await page.mouse.move(cx - 200, cy, { steps: 6 });
  await page.mouse.up({ button: "right" });

  // Fit chunks (Shift+0): the grid shown, the counts given.
  await page.keyboard.press("Shift+Digit0");
  const fittedText = await text("[data-fit]");
  ok(/^\d+ chunks, \d+ partly filled$/.test(fittedText), `fitted: ${fittedText}`);
  ok((await text("[data-origin]")).endsWith("fitted"), `origin: ${await text("[data-origin]")}`);
  ok(await page.locator('[data-layer="seams"]').isChecked(), "the fitted grid's layer is on");
  const chunkSet = await text("[data-chunk-set]");
  ok(/^\d+ chunks in the set, \d+ on the border$/.test(chunkSet), `outline: ${chunkSet}`);
  await page.keyboard.press("0");
  await page.waitForTimeout(800);
  await shot("3-fit");

  // Nudge: a key and the control; the counts follow.
  const fittedOrigin = await text("[data-origin]");
  await page.keyboard.press("Shift+ArrowLeft");
  await page.locator('[data-nudge="▴"]').click();
  const nudgedOrigin = await text("[data-origin]");
  const nudgedText = await text("[data-fit]");
  ok(
    nudgedOrigin.endsWith("nudged") && nudgedOrigin !== fittedOrigin,
    `nudged: ${fittedOrigin} → ${nudgedOrigin}; ${fittedText} → ${nudgedText}`,
  );
  await page.waitForTimeout(500);
  await shot("4-nudge");

  // Save: the draft, and a download.
  const first = await saveWith(page, join(shots, `editor-${look}-1.grimmap.json`));
  const a = countFile(first);
  ok(a.file.format === "grimworld-map" && a.file.version === 2, "the file's format and version 2");
  ok(a.floors > 300, `painted: ${a.floors} floor hexes`);
  ok(a.inside > 0 && a.outside > 0, `outlined: ${a.inside} inside, ${a.outside} outside`);
  ok(
    a.box.x0 > 30 && a.box.y0 > 15,
    `away from the origin: x ${a.box.x0}..${a.box.x1}, y ${a.box.y0}..${a.box.y1}`,
  );
  ok(
    a.file.chunks?.how === "nudged",
    `the file keeps the origin: ${JSON.stringify(a.file.chunks)}`,
  );
  ok((await text("[data-save-state]")).startsWith("Saved"), "saved (draft)");

  // Reload the page: the draft is listed.
  await page.reload();
  await page.locator('[data-screen="list"]').waitFor();
  ok((await page.locator("[data-draft]").count()) === 1, "after a reload, the draft is listed");

  // Open the saved file, save it again: identical.
  await page
    .locator("[data-open-file]")
    .setInputFiles(join(shots, `editor-${look}-1.grimmap.json`));
  await page.locator('[data-editor="map"], [role="alert"]').first().waitFor();
  const refused = page.locator('[data-screen="list"] [role="alert"]');
  if (await refused.count())
    throw new Error(`the saved file was refused: ${await refused.innerText()}`);
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor();
  ok((await text("[data-origin]")) === nudgedOrigin, "the origin is back, nudged");
  ok((await text("[data-fit]")) === nudgedText, "the counts are back");
  await page.locator('[data-layer="seams"]').check();
  await page.waitForTimeout(800);
  await shot("5-reload");
  const second = await saveWith(page, join(shots, `editor-${look}-2.grimmap.json`));
  ok(second === first, "reloaded from the file and saved again: the same file, byte for byte");

  // Space pan mode ends on a blur (CLI-09a's minor b).
  const overlay = page.locator("[data-overlay]");
  await page.keyboard.down("Space");
  ok((await overlay.evaluate((e) => e.style.cursor)) === "grab", "Space held: pan mode");
  await page.evaluate(() => window.dispatchEvent(new Event("blur")));
  ok((await overlay.evaluate((e) => e.style.cursor)) === "crosshair", "a blur ends the pan mode");
  await page.keyboard.up("Space");

  // A file of a newer version is refused, and the open map is untouched.
  const newer = JSON.stringify({ ...a.file, version: 3 });
  await page.locator("[data-open-file]").setInputFiles({
    name: "newer.grimmap.json",
    mimeType: "application/json",
    buffer: Buffer.from(newer),
  });
  await page.getByRole("alert").waitFor();
  ok((await page.getByRole("alert").innerText()).includes("newer"), "a newer file is refused");
  ok((await text("[data-map-name]")) === `Verify ${look}`, "the open map stays");

  // A CLI-09a file (format 1) opens, converted, with a note.
  await page.locator("[data-open-file]").setInputFiles({
    name: "old.grimmap.json",
    mimeType: "application/json",
    buffer: Buffer.from(format1("Old one")),
  });
  await page.locator("[data-note]").waitFor();
  ok((await text("[data-map-name]")) === "Old one", "a format 1 file opens");
  ok((await text("[data-note]")).includes("Converted from format 1"), "with its note");
  ok((await text("[data-fit]")) === "1 chunks, 0 partly filled", "its chunk at (0, 0)");

  // A stroke then a reload at once, inside the draft's 400 ms: the draft keeps it (minor a).
  await page.locator('[data-tool="paint"]').click();
  const before = Number((await text("[data-topbar]")).match(/(\d+) hexes/)[1]);
  // A right drag erases: the count moves.
  await page.mouse.move(cx - 60, cy);
  await page.mouse.down({ button: "right" });
  await page.mouse.move(cx + 60, cy, { steps: 4 });
  await page.mouse.up({ button: "right" });
  const after = Number((await text("[data-topbar]")).match(/(\d+) hexes/)[1]);
  await page.reload();
  await page.locator('[data-screen="list"]').waitFor();
  const row = await page.locator("[data-draft]", { hasText: "Old one" }).innerText();
  ok(
    after < before && row.split(/\s+/).includes(String(after)),
    `a reload within the debounce keeps the stroke: ${before} → ${after} hexes, listed: ${row.replace(/\s+/g, " ")}`,
  );

  // Below 700 px: one line.
  await page.setViewportSize({ width: 600, height: 900 });
  ok(
    await page.getByText("The map editor needs a desktop window.").isVisible(),
    "below 700 px: the one line",
  );

  ok(foreign.length === 0, `no request beyond the page's origin (${foreign.length})`);
  ok(errors.length === 0, `no page error${errors.length ? `: ${errors.join(" | ")}` : ""}`);
  await context.close();
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}`);
  await run(browser, "art");
  await run(browser, "plain");
} catch (e) {
  failures += 1;
  console.log(`FAIL ${e}`);
} finally {
  await browser?.close();
  try {
    process.kill(-server.pid, "SIGTERM");
    console.log(`dev server process group ${server.pid} sent SIGTERM`);
  } catch {}
}
console.log(failures === 0 ? "ALL CHECKS PASSED" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
