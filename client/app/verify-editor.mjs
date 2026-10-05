/* global console, process, fetch, setTimeout, localStorage, Buffer, URL, window, Event */
/* eslint-disable no-empty */
// The map editor in a real browser (CLI-09a, CLI-09a2): at 1440 × 900, with the art and in the plain
// look (the art's `/art/` answered 404), a zone is created with no size, painted away from the
// origin, outlined, its chunks fitted and nudged, saved, opened again from its file and saved
// again: the two files are identical. Also: a format 1 file opens converted, a stroke survives a
// reload within the draft's delay, a blur ends the Space pan mode. CLI-09b: the seed's zone and the
// town, opened from their committed files, validate with no error; each object kind is placed,
// selected and moved, copied and pasted, mirrored; a failing map is fixed; each is walked in the
// preview with the game's keys and taps. Run by hand, not by CI:
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

  await objectsPhase(page, look, shot, text);

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
