/* global console, process, fetch, setTimeout, localStorage, Buffer, URL, window, Event, performance, requestAnimationFrame, Image, document */
/* eslint-disable no-empty */
// The map editor in a real browser (CLI-09a, CLI-09a2): at 1440 × 900, with the art and in the plain
// look (the art's `/art/` answered 404), a zone is created with no size, painted away from the
// origin, outlined, its chunks fitted and nudged, saved, opened again from its file and saved
// again: the two files are identical. Also: a format 1 file opens converted, a stroke survives a
// reload within the draft's delay, a blur ends the Space pan mode. CLI-09b: the seed's zone and the
// town, opened from their committed files, validate with no error; each object kind is placed,
// selected and moved, copied and pasted, mirrored; a failing map is fixed; each is walked in the
// preview with the game's keys and taps. CLI-09e part 2: the pack's four menus are opened, a
// building, a character, a prop and a bridge placed, the character turned (R), a building's door
// failed and fixed (E-20), the map saved and opened again from its file. CLI-09c: ENG-08's sample
// zone is refused without its content manifest, opens with it, validates, is exported for the chain
// to the converter's records file, and its grimworld-export JSON opens again and exports the same.
// CLI-09f: the bridge fixture validates; a bridge placed from the menu on a pond's bank spans the
// water (a deck of 3); a character on its deck is refused (R-37) and undone; the walker walks onto
// the deck. Run by hand, not by CI:
// `node verify-editor.mjs`. Starts the dev server as its own process group and sends SIGTERM to that
// recorded group in `finally`. The server inherits GRIMWORLD_ART_OUT (the built atlas, D-73: never
// committed).
//
// Shots of each step into VERIFY_SHOTS_DIR (default the untracked `.verify-out/`; D-73: the shots
// with the art are never committed, attached or posted).
//
// Env: VERIFY_PORT (default 5199), VERIFY_CHANNEL, VERIFY_ROOT (the checkout whose dev server runs;
// default this one), VERIFY_SHOTS_DIR, VERIFY_PACK_ONLY=1 (the pack's phase alone, after the map
// list), VERIFY_EXPORT_ONLY=1 (the export's phase alone), VERIFY_BRIDGE_ONLY=1 (the bridges'
// phase alone).
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";
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
  page.on("pageerror", (e) => errors.push(String(e.stack ?? e)));
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
  const alone = ["VERIFY_PACK_ONLY", "VERIFY_EXPORT_ONLY", "VERIFY_BRIDGE_ONLY"];
  if (alone.some((name) => process.env[name] === "1")) {
    if (process.env.VERIFY_PACK_ONLY === "1") await packPhase(page, look, shot);
    else if (process.env.VERIFY_EXPORT_ONLY === "1") await exportPhase(page, look, shot);
    else await bridgePhase(page, look, shot);
    ok(foreign.length === 0, `no request beyond the page's origin (${foreign.length})`);
    ok(errors.length === 0, `no page error${errors.length ? `: ${errors.join(" | ")}` : ""}`);
    await context.close();
    return;
  }

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

  if (look === "art") await gridPhase(page, look, shot);
  if (process.env.VERIFY_GRID_ONLY === "1") {
    await context.close();
    return;
  }
  await objectsPhase(page, look, shot, text);
  await page.getByRole("button", { name: "◂ Maps" }).click();
  await packPhase(page, look, shot);
  await page.getByRole("button", { name: "◂ Maps" }).click();
  await exportPhase(page, look, shot);
  await page.getByRole("button", { name: "◂ Maps" }).click();
  await bridgePhase(page, look, shot);

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

/** A painted 225 × 225 zone (the largest), floor with a rock in nine, all inside its outline. */
function largestZone() {
  const rows = [];
  for (let y = 0; y < 225; y += 1) {
    let terrain = "";
    for (let x = 0; x < 225; x += 1) terrain += (x * 7 + y * 11) % 9 === 0 ? "#" : ".";
    rows.push({ y, x: 0, terrain, ground: "g".repeat(225), outline: "1".repeat(225) });
  }
  return JSON.stringify({
    format: "grimworld-map",
    version: 2,
    editor: "verify",
    map: {
      kind: "zone",
      name: "Largest",
      location: 9,
      biome: "meadow",
      levelMin: 1,
      levelMax: 1,
      rank: 0,
      spawnTable: 0,
    },
    rows,
    chunks: { x: 0, y: 0, how: "fitted" },
    obstacles: [],
  });
}

const stat = (list) => {
  const s = [...list].sort((a, b) => a - b);
  const at = (q) => s[Math.min(s.length - 1, Math.floor(q * s.length))] ?? NaN;
  return `median ${at(0.5).toFixed(1)} ms, p95 ${at(0.95).toFixed(1)} ms (${s.length} frames)`;
};

/**
 * The grid's cost (the owner's feedback, 2026-10-05): a painted 225 × 225 zone at the widest zoom,
 * panned then zoomed in and out for 240 frames each; the frame interval (requestAnimationFrame)
 * and the overlay's drawing time, median and p95.
 */
async function gridPhase(page, look, shot) {
  console.log(`--- ${look}: the grid's cost on a 225 × 225 map ---`);
  await page.locator("[data-open-file]").setInputFiles({
    name: "largest.grimmap.json",
    mimeType: "application/json",
    buffer: Buffer.from(largestZone()),
  });
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor();
  await page.waitForFunction(() => window.__editor !== undefined);
  // The widest zoom (out to the zoom's bound), then 120 across (about 8 CSS px a hex, the widest
  // zoom that draws the grid).
  for (let i = 0; i < 40; i += 1) await page.keyboard.press("-");
  let figures;
  for (const at of ["widest", 120]) {
    if (at !== "widest") {
      await page.evaluate((n) => {
        window.__editor.canvas.renderer.zoomTo(n);
        window.__editor.canvas.cameraMoved();
      }, at);
    }
    await page.waitForTimeout(1500);
    const across = (await page.locator("[data-status]").innerText()).match(/zoom (\d+) across/)[1];
    figures = await page.evaluate(async () => {
      const { canvas } = window.__editor;
      const renderer = canvas.renderer;
      const frames = (n, move) =>
        new Promise((done) => {
          const gaps = [];
          let last = performance.now();
          const first = last;
          let k = 0;
          const tick = (now) => {
            gaps.push(now - last);
            last = now;
            move(k);
            canvas.cameraMoved();
            k += 1;
            // At most 30 s a sequence: a slow grid yields fewer frames, never a hung check.
            if (k < n && now - first < 30_000) requestAnimationFrame(tick);
            else done(gaps.slice(5));
          };
          requestAnimationFrame(tick);
        });
      canvas.overlayMs.length = 0;
      const pan = await frames(240, (k) =>
        renderer.pan(k % 120 < 60 ? 6 : -6, 2 * Math.sin(k / 9)),
      );
      const panOverlay = [...canvas.overlayMs];
      canvas.overlayMs.length = 0;
      const { viewport } = renderer.cameraState();
      const mid = { x: viewport.width / 2, y: viewport.height / 2 };
      const zoom = await frames(240, (k) => renderer.zoomAt(k % 40 < 20 ? 1.03 : 1 / 1.03, mid));
      const zoomOverlay = [...canvas.overlayMs];
      return { pan, panOverlay, zoom, zoomOverlay };
    });
    console.log(
      `  ${across} across, pan: frame ${stat(figures.pan)}; overlay ${stat(figures.panOverlay)}`,
    );
    console.log(
      `  ${across} across, zoom: frame ${stat(figures.zoom)}; overlay ${stat(figures.zoomOverlay)}`,
    );
    await shot(`12-largest-${at}`);
  }
  ok(figures.pan.length > 10 && figures.zoom.length > 10, "frames measured");
}

/** The canvas's page point of a hex of the editor's plane. */
const hexAt = (page, tile) => page.evaluate((t) => window.__editor.canvas.tileOnScreen(t), tile);
const objectsOf = (page) =>
  page.evaluate(() => [...window.__editor.session.doc.objects].map(([id, o]) => ({ id, ...o })));
const light = (page) => page.locator(".ed-light").getAttribute("data-light");

async function clickHex(page, tile, options = {}) {
  const p = await hexAt(page, tile);
  await page.mouse.click(p.x, p.y, options);
}

async function openFixture(page, name) {
  await page.locator("[data-open-file]").setInputFiles(join(here, "src/editor/fixtures", name));
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor();
  await page.waitForFunction(() => window.__editor !== undefined);
  await page.waitForTimeout(400);
}

/** The walk (§2.8): the game's taps and keys move the walker; P leaves, the camera kept. */
async function walkPhase(page, look, shot, name, tap) {
  const camera = () =>
    page.evaluate(() => {
      const { centre, scale } = window.__editor.canvas.renderer.cameraState().camera;
      return [centre.x, centre.y, scale].map((n) => n.toFixed(3)).join(" ");
    });
  const cameraBefore = await camera();
  await page.keyboard.press("p");
  await page.locator("[data-walk]").waitFor();
  await page.waitForFunction(() => window.__editorWalk !== undefined);
  await page.waitForTimeout(600);
  const start = await page.evaluate(() => window.__editorWalk.walkerTile());
  const p = await page.evaluate((t) => window.__editorWalk.tileOnScreen(t), tap);
  await page.mouse.click(p.x, p.y);
  const arrived = await page
    .waitForFunction(
      (t) => {
        const w = window.__editorWalk?.walkerTile();
        return w && w.x === t.x && w.y === t.y;
      },
      tap,
      { timeout: 10_000 },
    )
    .then(() => true)
    .catch(() => false);
  if (!arrived) {
    const where = await page.evaluate(() => window.__editorWalk.walkerTile());
    const said = await page.locator("[data-walk-said]").innerText();
    throw new Error(`${name}: the walker is at (${where.x}, ${where.y}): ${said}`);
  }
  ok(true, `${name}: walked by a tap from (${start.x}, ${start.y}) to (${tap.x}, ${tap.y})`);
  await page.keyboard.press("d");
  await page.waitForTimeout(400);
  const stepped = await page.evaluate(() => window.__editorWalk.walkerTile());
  ok(
    stepped.x === tap.x - 1 || stepped.x === tap.x,
    `${name}: the game's D steps East: (${stepped.x}, ${stepped.y})`,
  );
  ok(
    (await page.locator("[data-walk-said]").innerText()).length > 0,
    `${name}: the wiring's line: ${await page.locator("[data-walk-said]").innerText()}`,
  );
  // The editor's keys are off while walking: B arms nothing, U selects nothing.
  await page.keyboard.press("b");
  await page.waitForTimeout(800);
  await shot(`${name}-walk`);
  if (await page.locator("input[data-walk-fog]").count()) {
    await page.locator("input[data-walk-fog]").check();
    await page.waitForTimeout(800);
    ok(
      (await page.locator("[data-walk]").getAttribute("data-walk-fog")) === "on",
      `${name}: fog on`,
    );
    await shot(`${name}-walk-fog`);
  }
  await page.keyboard.press("p");
  await page.locator("[data-walk]").waitFor({ state: "detached" });
  await page.waitForTimeout(500);
  const cameraAfter = await camera();
  ok(
    cameraAfter === cameraBefore,
    `${name}: back to editing, the same camera (${cameraBefore} → ${cameraAfter})`,
  );
  ok(
    !(await text_(page, "[data-armed]")).includes("Paint"),
    `${name}: B pressed while walking armed nothing`,
  );
}

const text_ = (page, selector) => page.locator(selector).innerText();

async function objectsPhase(page, look, shot, text) {
  console.log(`--- ${look}: objects, validation, walk (CLI-09b) ---`);
  // The seed's zone.
  await openFixture(page, "seed-zone.grimmap.json");
  ok((await light(page)) === "clear", `the seed's zone validates: ${await text(".ed-light")}`);
  ok(
    (await objectsOf(page)).length === 10,
    "its entry, 2 gates, 4 quota places, 2 spawns, a chest",
  );
  await page.waitForTimeout(500);
  await shot("6-zone");

  // Place each kind of a zone. A spawn point first: no template, a failing map.
  const place = async (swatch, tile) => {
    await page.locator(`[data-swatch="object-${swatch}"]`).click();
    await clickHex(page, tile);
  };
  await place("spawn", { x: 5, y: 9 });
  await page.waitForTimeout(400);
  ok(
    (await light(page)) === "error",
    `a spawn point without a template: ${await text(".ed-light")}`,
  );
  await page.keyboard.press("y");
  await page.locator('[data-finding="E-19"]').waitFor();
  ok(true, "Y opens the panel: E-19 listed");
  await shot("7-failing");
  await page.locator('[data-finding="E-19"] [data-show]').click();
  ok(
    (await page.evaluate(() => window.__editor.session.selection.objects.size)) === 1,
    "Show selects the spawn point",
  );
  // Fix it in the inspector: the panel closes, the template typed.
  await page.locator('.ed-validation button[aria-label="Close the panel"]').click();
  await page.locator('input[name="spawn-template"]').fill("4");
  await page.locator('input[name="spawn-template"]').press("Enter");
  await page.waitForTimeout(400);
  ok((await light(page)) === "clear", `fixed: ${await text(".ed-light")}`);
  await shot("8-fixed");
  await place("feature-node", { x: 10, y: 3 });
  await place("candidate-0", { x: 12, y: 9 });
  await place("gate", { x: 0, y: 10 });
  await place("entry", { x: 0, y: 7 });
  const kinds = new Set((await objectsOf(page)).map((o) => o.kind));
  ok(
    ["entry", "gate", "candidate", "feature", "spawn"].every((k) => kinds.has(k)),
    `every zone kind placed: ${[...kinds].join(", ")}`,
  );
  await page.waitForTimeout(400);
  ok((await light(page)) === "clear", `still valid: ${await text(".ed-light")}`);

  // Select and move: the node dragged two hexes West (x grows West) and a row up.
  await page.keyboard.press("u");
  await clickHex(page, { x: 10, y: 3 });
  const from = await hexAt(page, { x: 10, y: 3 });
  const to = await hexAt(page, { x: 12, y: 4 });
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(to.x, to.y, { steps: 6 });
  await page.mouse.up();
  const node = (await objectsOf(page)).find((o) => o.kind === "feature" && o.feature === "node");
  ok(node?.at.x === 12 && node?.at.y === 4, `moved: the node at (${node?.at.x}, ${node?.at.y})`);

  // Copy and paste: a box with the node, pasted onto an even row elsewhere.
  const a = await hexAt(page, { x: 11, y: 2 });
  const b = await hexAt(page, { x: 13, y: 4 });
  await page.mouse.move(a.x, a.y);
  await page.mouse.down();
  await page.mouse.move(b.x, b.y, { steps: 5 });
  await page.mouse.up();
  const picked = await page.evaluate(() => window.__editor.session.selection.hexes.size);
  await page.keyboard.press("Control+c");
  await page.keyboard.press("Control+v");
  await clickHex(page, { x: 25, y: 21 });
  const nodes = (await objectsOf(page)).filter((o) => o.kind === "feature" && o.feature === "node");
  ok(
    nodes.length === 2 && nodes[1].at.y % 2 === nodes[0].at.y % 2,
    `pasted: ${picked} hexes and the node, at (${nodes[1]?.at.x}, ${nodes[1]?.at.y}): the row's parity kept`,
  );
  await page.waitForTimeout(500);
  await shot("9-paste");
  await page.keyboard.press("Control+z");
  await page.keyboard.press("Escape");

  await walkPhase(page, look, shot, "zone", { x: 4, y: 8 });

  // The town.
  await openFixture(page, "town-a.grimmap.json");
  ok((await light(page)) === "clear", `the town validates: ${await text(".ed-light")}`);
  await page.waitForTimeout(400);
  await shot("10-town");
  // On the island's free grass behind the castle (rows 14 and 15).
  await place("decor", { x: 8, y: 14 });
  await place("prop", { x: 1, y: 14 });
  await page.keyboard.press("h");
  const prop = (await objectsOf(page)).at(-1);
  ok(prop?.kind === "prop" && prop.mirror === true, "a prop placed and mirrored (H)");
  await place("figure", { x: 3, y: 14 });
  await place("arrival", { x: 3, y: 0 });
  // A second vault: E-14 fails, then Delete fixes it.
  await place("place-vault", { x: 5, y: 15 });
  await page.waitForTimeout(400);
  ok((await light(page)) === "error", `a second vault: ${await text(".ed-light")}`);
  await page.keyboard.press("Delete");
  await page.waitForTimeout(400);
  const townKinds = new Set((await objectsOf(page)).map((o) => o.kind));
  ok(
    ["place", "decor", "prop", "figure", "arrival"].every((k) => townKinds.has(k)),
    `every town kind on the map: ${[...townKinds].join(", ")}`,
  );
  const lit = await light(page);
  ok(lit !== "error", `the vault deleted: ${await text(".ed-light")}`);
  await page.waitForTimeout(400);
  await shot("11-town-pieces");
  // A door in view of the arrival at the game's zoom: the market's.
  const doors = await page.evaluate(() =>
    [...window.__editor.session.doc.objects.values()]
      .filter((o) => o.kind === "place" && o.target === "market")
      .map((o) => o.at),
  );
  await walkPhase(page, look, shot, "town", doors[0]);
}

/** The E findings of a check listed in the validation panel, after Y. */
async function listed(page, check) {
  await page.keyboard.press("y");
  await page.locator(".ed-validation").waitFor();
  const n = await page.locator(`[data-finding="${check}"]`).count();
  await page.locator('.ed-validation button[aria-label="Close the panel"]').click();
  return n;
}

/**
 * CLI-09e part 2: the pack's palette. A new zone, a floor block painted (set up through the
 * session); each menu opened; a building, a character, a prop and a bridge placed from the menus;
 * the character turned with R; the building's door failed (a wall painted under it) and fixed (R
 * takes the next door); the map saved, opened again from its file, and its pack objects kept.
 */
async function packPhase(page, look, shot) {
  console.log(`--- ${look}: the pack's palette (CLI-09e part 2) ---`);
  // The foam still (`?water=still`): in part 3's captures, only the characters move.
  await page.goto(`${base}/editor.html?water=still`);
  await page.locator('[data-screen="list"]').waitFor();
  await page.locator("[data-new-map]").click();
  await page.locator("#ed-name").fill(`Pack ${look}`);
  await page.locator("[data-confirm]").click();
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor();
  await page.waitForFunction(() => window.__editor !== undefined);
  await page.evaluate(() => {
    const s = window.__editor.session;
    s.choose("terrain", 0);
    const tiles = [];
    for (let y = 0; y < 16; y += 1) for (let x = 0; x < 24; x += 1) tiles.push({ x, y });
    s.strokeStart({ x: 0, y: 0 }, { erase: false, alt: false });
    s.strokeMove(tiles);
    s.strokeEnd();
  });
  await page.waitForTimeout(300);
  await page.keyboard.press("0");
  await page.waitForTimeout(400);

  // Each menu: its kinds, with their thumbnails when the atlas is served.
  const menus = [
    ["building", "Buildings"],
    ["npc", "Characters"],
    ["prop", "Props"],
    ["bridge", "Bridges"],
  ];
  for (const [category, label] of menus) {
    await page.locator(`[data-category="${category}"]`).click();
    const grid = page.locator(`.ed-palette-grid[data-menu="${category}"]`);
    await grid.waitFor();
    const kinds = await grid.locator("[data-kind]").count();
    const thumbs = await grid.locator("canvas").count();
    ok(
      kinds > 0 && (look === "art" ? thumbs === kinds : thumbs === 0),
      `${label}: ${kinds} kinds, ${thumbs} thumbnails`,
    );
    await shot(`12-menu-${category}`);
  }

  const pick = async (category, kind, tile) => {
    await page.locator(`[data-category="${category}"]`).click();
    await page.locator(`.ed-palette-grid [data-kind="${kind}"]`).click();
    const armed = await page
      .locator(".ed-palette-grid [aria-pressed='true']")
      .getAttribute("data-kind");
    const p = await hexAt(page, tile);
    await page.mouse.move(p.x, p.y);
    await page.waitForTimeout(150);
    if (category === "building") await shot("13-preview");
    await page.mouse.click(p.x, p.y);
    return armed;
  };
  const anchor = { x: 8, y: 4 };
  ok((await pick("building", "barracks", anchor)) === "barracks", "Place armed with the barracks");
  await pick("npc", "pawn", { x: 4, y: 10 });
  await page.keyboard.press("r");
  await page.keyboard.press("r");
  await pick("prop", "tree", { x: 16, y: 10 });
  await page.keyboard.press("h");
  await pick("bridge", "stone_bridge", { x: 20, y: 3 });
  const objects = await objectsOf(page);
  const of = (kind) => objects.find((o) => o.kind === kind);
  ok(
    of("building")?.type === "barracks" && of("building")?.at.x === 8,
    "a building placed: barracks at (8, 4)",
  );
  ok(
    of("npc")?.type === "pawn" && of("npc")?.facing === 2,
    `a character placed and turned twice (R): facing ${of("npc")?.facing}`,
  );
  ok(
    of("scenery")?.type === "tree" && of("scenery")?.mirror === true,
    "a prop placed, mirrored (H)",
  );
  ok(of("bridge")?.type === "stone_bridge", "a bridge placed");
  ok((await listed(page, "E-20")) === 0, "the building's door is walkable: no E-20");
  ok((await listed(page, "E-21")) === 0, "the character stands on floor: no E-21");
  await page.waitForTimeout(300);
  await shot("14-placed");
  if (look === "art") await idlePhase(page, shot, of("npc"));

  // Fail the door: a wall painted on it. Fix it: the building selected, R takes the next door.
  await page.locator('[data-swatch="terrain-wall"]').click();
  await clickHex(page, anchor);
  await page.waitForTimeout(400);
  ok((await listed(page, "E-20")) === 1, "a wall under the door: E-20 fails");
  await page.keyboard.press("y");
  await page.locator('[data-finding="E-20"]').waitFor();
  await shot("15-door-fails");
  await page.locator('.ed-validation button[aria-label="Close the panel"]').click();
  await page.keyboard.press("u");
  await clickHex(page, anchor);
  await page.keyboard.press("r");
  await page.waitForTimeout(400);
  const door = (await objectsOf(page)).find((o) => o.kind === "building")?.door;
  ok((await listed(page, "E-20")) === 0, `the door turned to ${door}: E-20 passes`);
  await shot("16-door-fixed");

  // Save, then open the file again.
  const path = join(shots, `pack-${look}.grimmap.json`);
  const saved = JSON.parse(await saveWith(page, path));
  const packed = saved.objects.filter((o) =>
    ["building", "npc", "scenery", "bridge"].includes(o.kind),
  );
  ok(packed.length === 4, `saved: ${packed.map((o) => `${o.kind} ${o.type}`).join(", ")}`);
  const before = JSON.stringify((await objectsOf(page)).map((o) => ({ ...o, id: 0 })));
  await page.locator("[data-open-file]").setInputFiles(path);
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor();
  await page.waitForFunction(() => window.__editor !== undefined);
  await page.waitForTimeout(500);
  const after = JSON.stringify((await objectsOf(page)).map((o) => ({ ...o, id: 0 })));
  ok(after === before, "opened again from its file: the same objects");
  await shot("17-reloaded");
}

/**
 * CLI-09f: bridges of one level (D-227, ADR-0008). The committed fixture (two ponds, a stone bridge
 * North over 3 deck hexes, a covered bridge West over 2) validates; its stone bridge removed and
 * placed again from the menu on the pond's southern bank spans the water; a character placed on its
 * deck fails R-37 and is undone; the walker walks onto the deck, a water hex under it.
 */
async function bridgePhase(page, look, shot) {
  console.log(`--- ${look}: bridges, one level (CLI-09f) ---`);
  const exported = JSON.parse(
    readFileSync(join(here, "src/editor/fixtures/bridge-zone.export.json"), "utf8"),
  );
  const [stone] = exported.bridges;
  const [south] = stone.ends.map(([x, y]) => ({ x, y }));
  const deck = stone.deck.map(([x, y]) => ({ x, y }));
  const middle = deck[1];
  await openFixture(page, "bridge-zone.grimmap.json");
  for (const check of ["R-37", "E-24", "E-25", "R-34", "E-7"]) {
    ok((await listed(page, check)) === 0, `the bridge fixture: no ${check}`);
  }
  await shot("18-bridges");

  // The stone bridge removed, then placed again from the menu on the pond's southern bank.
  await page.evaluate((at) => {
    const s = window.__editor.session;
    const [id] = [...s.doc.objects].find(
      ([, o]) => o.kind === "bridge" && o.at.x === at.x && o.at.y === at.y,
    );
    s.select({ hexes: new Set(), objects: new Set([id]) });
    s.deleteSelection();
  }, south);
  ok(
    (await objectsOf(page)).filter((o) => o.kind === "bridge").length === 1,
    "the stone bridge removed",
  );
  await page.locator('[data-category="bridge"]').click();
  await page.locator('.ed-palette-grid [data-kind="stone_bridge"]').click();
  const p = await hexAt(page, south);
  await page.mouse.move(p.x, p.y);
  await page.waitForTimeout(300);
  await shot("19-bridge-preview");
  await page.mouse.click(p.x, p.y);
  await page.waitForTimeout(300);
  const placed = (await objectsOf(page)).find(
    (o) => o.kind === "bridge" && o.at.x === south.x && o.at.y === south.y,
  );
  ok(
    placed?.type === "stone_bridge" && placed.deck === deck.length,
    `placed on the bank: it spans the pond, a deck of ${placed?.deck} hexes`,
  );
  for (const check of ["R-37", "E-24", "E-25", "R-34"]) {
    ok((await listed(page, check)) === 0, `placed: no ${check}`);
  }
  await shot("20-bridge-placed");

  // Refused: a character on the deck (R-37), then undone.
  await page.locator('[data-category="npc"]').click();
  await page.locator('.ed-palette-grid [data-kind="pawn"]').click();
  await clickHex(page, middle);
  await page.waitForTimeout(400);
  ok((await listed(page, "R-37")) === 1, "a character on the deck: R-37 fails");
  await page.keyboard.press("y");
  await page.locator('[data-finding="R-37"]').waitFor();
  await shot("21-bridge-r37");
  await page.locator('.ed-validation button[aria-label="Close the panel"]').click();
  await page.keyboard.press("Escape");
  await page.keyboard.press("Control+z");
  await page.waitForTimeout(400);
  ok((await listed(page, "R-37")) === 0, "undone: R-37 passes");

  // The walk: onto the deck, over the water.
  await walkPhase(page, look, shot, "bridge", middle);
}

/** ENG-08's samples (track game's, read only). */
const SAMPLES = join(here, "../../spikes/SPK-16-authored-zone/samples");

/** A download the click starts, saved and read. */
async function downloaded(page, selector, path) {
  const [download] = await Promise.all([
    page.waitForEvent("download"),
    page.locator(selector).click(),
  ]);
  await download.saveAs(path);
  return { name: download.suggestedFilename(), text: readFileSync(path, "utf8") };
}

/**
 * Export for the chain (CLI-09c): ENG-08's sample zone, its manifest, the records file the
 * converter writes, and the export JSON opened again.
 */
async function exportPhase(page, look, shot) {
  console.log("  export for the chain (CLI-09c)");
  const sample = join(SAMPLES, "zone.json");
  // Without the manifest: refused, the page as it was.
  await page.locator("[data-open-file]").setInputFiles(sample);
  const refused = page.locator(".ed-problem", { hasText: "content manifest" });
  await refused.waitFor();
  ok(await refused.isVisible(), "an export opened with no manifest is refused, with the reason");
  await page.locator("[data-manifest-file]").setInputFiles(join(SAMPLES, "manifest.json"));
  await page.locator("[data-load-manifest]", { hasText: "manifest.json" }).first().waitFor();
  ok(true, "the content manifest loaded");
  await page.locator("[data-open-file]").setInputFiles(sample);
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor();
  await page.waitForFunction(() => window.__editor !== undefined);
  await page.waitForTimeout(500);
  ok(
    (await page.locator("[data-map-name]").innerText()) === "Meadow Edge",
    "the sample zone opens",
  );
  await shot("18-sample-zone");

  await page.locator("[data-export]").click();
  await page.locator('[data-dialog="export"]').waitFor();
  const validation = await page.locator("[data-export-validation]").innerText();
  ok(/: 0 errors/.test(validation), `it validates: ${validation}`);
  const verdict = await page.locator("[data-export-verdict]").innerText();
  ok(/records/.test(verdict), `the converter accepts it: ${verdict}`);
  await shot("19-export-dialog");
  const json = await downloaded(page, "[data-export-json]", join(shots, `export-${look}.json`));
  const records = await downloaded(
    page,
    "[data-confirm]",
    join(shots, `export-${look}.records.json`),
  );
  const golden = readFileSync(join(SAMPLES, "zone.records.json"), "utf8");
  const source = JSON.parse(records.text).source;
  ok(
    records.text.replace(`"source": "${source}"`, '"source": "zone.json"') === golden,
    `the records file is the converter's, text for text (${records.name}, ${JSON.parse(golden).writes.length} writes)`,
  );
  const exported = JSON.parse(json.text);
  const expected = JSON.parse(readFileSync(sample, "utf8"));
  delete exported.editor;
  delete expected.editor;
  ok(isDeepStrictEqual(exported, expected), `the export JSON is the sample (${json.name})`);

  // The export JSON opened again: the same records.
  await page.locator("[data-open-file]").setInputFiles(join(shots, `export-${look}.json`));
  await page.waitForTimeout(800);
  await page.waitForFunction(() => window.__editor !== undefined);
  await page.locator("[data-export]").click();
  await page.locator('[data-dialog="export"]').waitFor();
  const again = await downloaded(
    page,
    "[data-confirm]",
    join(shots, `export-${look}-2.records.json`),
  );
  ok(again.text === records.text, "opened from its export, it exports the same records");
}

/** In the page: the device pixels that differ between two PNG screenshots, and their box (CSS px). */
async function diffShots(page, a, b) {
  return page.evaluate(
    async ({ a, b }) => {
      const decode = async (png) => {
        const image = new Image();
        image.src = `data:image/png;base64,${png}`;
        await image.decode();
        const canvas = document.createElement("canvas");
        canvas.width = image.width;
        canvas.height = image.height;
        const g = canvas.getContext("2d");
        g.drawImage(image, 0, 0);
        return { w: image.width, data: g.getImageData(0, 0, image.width, image.height).data };
      };
      const [A, B] = [await decode(a), await decode(b)];
      const k = A.w / window.innerWidth;
      let differ = 0;
      const box = { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity };
      for (let i = 0; i < A.data.length; i += 4) {
        if (
          A.data[i] === B.data[i] &&
          A.data[i + 1] === B.data[i + 1] &&
          A.data[i + 2] === B.data[i + 2]
        )
          continue;
        differ += 1;
        const p = i / 4;
        const x = (p % A.w) / k;
        const y = Math.floor(p / A.w) / k;
        box.x0 = Math.min(box.x0, x);
        box.y0 = Math.min(box.y0, y);
        box.x1 = Math.max(box.x1, x + 1 / k);
        box.y1 = Math.max(box.y1, y + 1 / k);
      }
      return { differ, box };
    },
    { a: a.toString("base64"), b: b.toString("base64") },
  );
}

/** In the page: a structure's sprite box on the screen (CSS px): PixiJS's bounds, on the canvas. */
const spriteBox = (page, key) =>
  page.evaluate((key) => {
    const canvas = window.__editor.canvas;
    const node = canvas.renderer.structureSprite(key);
    if (!node) return null;
    const rect = canvas.overlay.getBoundingClientRect();
    const b = node.sprite.getBounds();
    return {
      loops: node.loops,
      x0: rect.left + b.x,
      x1: rect.left + b.x + b.width,
      y0: rect.top + b.y,
      y1: rect.top + b.y + b.height,
    };
  }, key);

/**
 * CLI-09e part 3: the placed character loops its idle in the renderer. Two captures 100 ms apart
 * differ on it and nowhere else (the foam is still: `?water=still`). Then 50 characters on the
 * screen: the frames a second and the script time a frame standing still, and the renderer's
 * frame time while panning, with the objects layer on and off.
 */
async function idlePhase(page, shot, npc) {
  console.log("--- art: the characters' idle loop (CLI-09e part 3) ---");
  // The pointer off the map: no hover change between the captures.
  await page.mouse.move(2, 2);
  await page.waitForTimeout(400);
  const box = await spriteBox(page, `npc:${npc.id}`);
  ok(box?.loops === true, "the character is the renderer's, and it loops");
  const a = await page.screenshot();
  await page.waitForTimeout(100);
  const b = await page.screenshot();
  const { differ, box: changed } = await diffShots(page, a, b);
  const margin = 1;
  const inside =
    differ > 0 &&
    changed.x0 >= box.x0 - margin &&
    changed.x1 <= box.x1 + margin &&
    changed.y0 >= box.y0 - margin &&
    changed.y1 <= box.y1 + margin;
  ok(
    inside,
    `two captures 100 ms apart: ${differ} device px differ, in ` +
      `[${changed.x0.toFixed(0)}, ${changed.x1.toFixed(0)}] × [${changed.y0.toFixed(0)}, ${changed.y1.toFixed(0)}], ` +
      `the character's box [${box.x0.toFixed(0)}, ${box.x1.toFixed(0)}] × [${box.y0.toFixed(0)}, ${box.y1.toFixed(0)}]`,
  );
  await shot("14b-idle");

  // 50 characters on the screen, one every other hex of the block's rows, every kind in turn.
  const placed = await page.evaluate(() => {
    const s = window.__editor.session;
    const types = [
      "pawn",
      "pawn_axe",
      "pawn_gold",
      "pawn_hammer",
      "pawn_knife",
      "pawn_meat",
      "pawn_pickaxe",
      "pawn_wood",
      "lancer",
      "trainee",
      "laborer",
      "expert",
      "master",
      "sheep",
      "pig",
    ];
    let n = 0;
    for (let y = 6; y < 16 && n < 50; y += 2) {
      for (let x = 1; x < 23 && n < 50; x += 2) {
        if (x >= 6 && x <= 11 && y <= 7) continue;
        s.choosePlace({ kind: "npc", type: types[n % types.length] });
        s.strokeStart({ x, y }, { erase: false, alt: false, shift: false });
        s.strokeEnd();
        n += 1;
      }
    }
    return n;
  });
  await page.mouse.move(2, 2);
  await page.waitForTimeout(800);
  const figures = await page.evaluate(() => window.__editor.canvas.renderer["figures"].size);
  ok(
    figures >= 50,
    `${placed} characters placed, 51 with the first: the renderer loops ${figures}`,
  );
  await shot("14c-fifty");

  // Timing the renderer's own work: its advance and draw, per frame.
  const measure = (ms, pan) =>
    page.evaluate(
      async ({ ms, pan }) => {
        const r = window.__editor.canvas.renderer;
        const times = [];
        const advance = r.advance;
        const draw = r.draw;
        let t0 = 0;
        r.advance = function (now) {
          t0 = performance.now();
          return advance.call(this, now);
        };
        r.draw = function () {
          draw.call(this);
          times.push(performance.now() - t0);
        };
        const start = performance.now();
        if (pan) {
          await new Promise((done) => {
            let n = 0;
            const step = () => {
              // 3 px a frame, back and forth every second: the characters stay on the screen.
              const c = window.__editor.canvas;
              c.renderer.pan(Math.floor(n++ / 60) % 2 === 0 ? -3 : 3, 0);
              c.cameraMoved();
              if (performance.now() - start < ms) requestAnimationFrame(step);
              else done();
            };
            requestAnimationFrame(step);
          });
        } else {
          await new Promise((done) => setTimeout(done, ms));
        }
        const seconds = (performance.now() - start) / 1000;
        delete r.advance;
        delete r.draw;
        const sorted = [...times].sort((x, y) => x - y);
        const at = (q) => sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))] ?? 0;
        return {
          frames: times.length,
          fps: times.length / seconds,
          mean: times.reduce((x, y) => x + y, 0) / Math.max(1, times.length),
          median: at(0.5),
          p95: at(0.95),
        };
      },
      { ms, pan },
    );
  const loadavg = () => readFileSync("/proc/loadavg", "utf8").split(" ")[0];
  const still = await measure(4000, false);
  console.log(
    `  standing still, 50 characters: ${still.fps.toFixed(1)} frames/s, script ` +
      `${still.mean.toFixed(2)} ms a frame (median ${still.median.toFixed(2)}, p95 ${still.p95.toFixed(2)}); load ${loadavg()}`,
  );
  ok(still.fps <= 15.5, `idle frames at most 15 a second: ${still.fps.toFixed(1)}`);
  ok(still.fps >= 10, `the characters loop standing still: ${still.fps.toFixed(1)} frames/s`);
  const panOn = await measure(3000, true);
  await page.locator('[data-layer="objects"]').uncheck();
  await page.waitForTimeout(300);
  const noneStill = await measure(2000, false);
  const panOff = await measure(3000, true);
  await page.locator('[data-layer="objects"]').check();
  // The 50 characters undone, one step each: the map as the pack phase left it.
  await page.evaluate((n) => {
    for (let i = 0; i < n; i++) window.__editor.session.undo();
  }, placed);
  await page.waitForTimeout(300);
  console.log(
    `  panning, 50 characters: ${panOn.frames} frames, renderer ${panOn.median.toFixed(2)} / ${panOn.p95.toFixed(2)} ms ` +
      `(median / p95); objects off: ${panOff.median.toFixed(2)} / ${panOff.p95.toFixed(2)} ms; load ${loadavg()}`,
  );
  ok(noneStill.frames === 0, `objects off, standing still: ${noneStill.frames} frames`);
  ok(panOn.p95 < 16.7, `panning with 50 characters: p95 ${panOn.p95.toFixed(2)} ms under 16.7`);
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
