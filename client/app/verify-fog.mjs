/* global console, process, fetch, setTimeout, performance, window, document, Image, MutationObserver */
/* eslint-disable no-empty */
// Exploration by sight in a real browser (CLI-03n, D-213): the zone at 1440 × 900 and 375 × 812,
// with the atlas built by `tools/art/build.py` (never committed, D-73) and in the plain look (the
// atlas refused: shapes and flat colours). Run by hand, not by CI:
// `pnpm --filter @grimworld/app verify:fog`. Starts the dev server as its own process group and
// sends SIGTERM to that recorded group in `finally`.
//
// For each look and size, a walk West from the entry toward the runts until they come into sight,
// then back East until they are out of it, in hops of a few tiles (the walk stops on a reveal or a
// goblin entering sight, and is tapped on again):
// - `data-fog` (tiles drawn hidden, explored beyond sight, in sight; goblins beyond sight; the
//   explored set's size) after the walk: tiles in each state, the tiles drawn explored or in sight
//   exactly the explored set (no unseen tile drawn), a goblin beyond sight drawn;
// - pixels of the screenshot: a floor tile walked on, now beyond sight, is grey (R = G = B within
//   `GREY_TOLERANCE` on every sampled pixel); a floor tile walked on, in sight, is not;
// - the bake of each step that explored tiles (`data-bake-ms`, the last chunk's bake: its colour
//   and its grayscale twin), and the frame time over the walk, timed as `verify-ground.mjs` does.
//
// With VERIFY_MAIN=1 (a checkout without CLI-03n, `VERIFY_ROOT`): the same walk, frame times only.
// Figures go to VERIFY_MEASURE_OUT (JSON) when it is set. Screenshots go to VERIFY_SHOTS_DIR
// (default the untracked `.verify-out/`; D-73: never committed, attached or posted).
//
// Env: VERIFY_PORT (default 5197), VERIFY_CHANNEL, VERIFY_ROOT, VERIFY_MAIN=1,
// VERIFY_MEASURE_OUT, VERIFY_SHOTS_DIR, VERIFY_LOOKS (`atlas,plain` by default). The server
// inherits GRIMWORLD_ART_OUT.
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5197);
const base = `http://127.0.0.1:${port}`;
const root = process.env.VERIFY_ROOT ?? join(here, "..", "..");
const mainOnly = process.env.VERIFY_MAIN === "1";
const looks = (process.env.VERIFY_LOOKS ?? "atlas,plain").split(",");
const shots = process.env.VERIFY_SHOTS_DIR ?? join(here, ".verify-out");
mkdirSync(shots, { recursive: true });

/** The largest gap between R, G and B that still reads as grey (the bakes are 8-bit). */
const GREY_TOLERANCE = 3;
/** A pixel in colour: its channels differ by more than this. */
const COLOUR_GAP = 12;

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
      if ((await fetch(base)).ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`the dev server did not answer:\n${log}`);
}

/** COOP and COEP: a cross-origin isolated page, whose clock counts in microseconds. */
async function isolate(context) {
  await context.route("**/*", async (route) => {
    const response = await route.fetch();
    await route.fulfill({
      response,
      headers: {
        ...response.headers(),
        "cross-origin-opener-policy": "same-origin",
        "cross-origin-embedder-policy": "require-corp",
      },
    });
  });
}

/** Times every display-frame callback that issued a WebGL draw (as `verify-ground.mjs`). */
function timeFrames() {
  const raf = window.requestAnimationFrame.bind(window);
  window.__frameMs = [];
  window.__draws = 0;
  for (const proto of [
    window.WebGLRenderingContext?.prototype,
    window.WebGL2RenderingContext?.prototype,
  ]) {
    if (!proto) continue;
    for (const name of [
      "drawElements",
      "drawArrays",
      "drawElementsInstanced",
      "drawArraysInstanced",
    ]) {
      const original = proto[name];
      if (!original) continue;
      proto[name] = function (...args) {
        window.__draws += 1;
        return original.apply(this, args);
      };
    }
  }
  window.requestAnimationFrame = (callback) =>
    raf((t) => {
      const draws = window.__draws;
      const start = performance.now();
      try {
        callback(t);
      } finally {
        if (window.__draws > draws) window.__frameMs.push(performance.now() - start);
      }
    });
}

const ROW_HEIGHT = (64 / Math.sqrt(3)) * 1.5;
const tileToPixel = (t) => ({ x: -(t.x + (t.y & 1) / 2) * 64, y: -t.y * ROW_HEIGHT });

/** Hex distance on the odd-r grid (the placeholders' `distance`). */
function distance(a, b) {
  const aq = a.x - (a.y - (a.y & 1)) / 2;
  const bq = b.x - (b.y - (b.y & 1)) / 2;
  const dq = aq - bq;
  const dr = a.y - b.y;
  return (Math.abs(dq) + Math.abs(dr) + Math.abs(dq + dr)) / 2;
}

/** The zone fixture's runts (`fixtures/zone.ts`), asleep: they never move. */
const RUNTS = [
  { x: 20, y: 9 },
  { x: 22, y: 9 },
  { x: 21, y: 11 },
];

async function camera(room) {
  const [x, y, scale] = (await room.getAttribute("data-camera")).split(" ").map(Number);
  return { x, y, scale };
}

async function onScreen(room, tile) {
  const c = await camera(room);
  const box = await room.boundingBox();
  const p = tileToPixel(tile);
  return { x: box.x + c.x + p.x * c.scale, y: box.y + c.y + p.y * c.scale };
}

const tileOf = async (room) => {
  const [x, y] = (await room.getAttribute("data-tile")).split(",").map(Number);
  return { x, y };
};

async function stood(page, room) {
  await page.waitForTimeout(80);
  for (let i = 0; i < 200; i += 1) {
    if ((await room.getAttribute("data-walking")) !== "true") return;
    await page.waitForTimeout(50);
  }
}

/** The zone fixture's rocks (`fixtures/zone.ts`), but on the runts' tiles. */
const rock = (t) =>
  (t.x * 7 + t.y * 11) % 9 === 0 && !RUNTS.some((r) => r.x === t.x && r.y === t.y);

/**
 * Walks to `target` in hops of at most `HOP` tiles along its row, each a floor tile in sight (a
 * tile never seen is hidden, and a tap there plans nothing); a hop a stop ended is tapped again.
 */
const HOP = 4;
async function walkTo(page, room, target) {
  for (let i = 0; i < 30; i += 1) {
    const at = await tileOf(room);
    if (at.x === target.x && at.y === target.y) return true;
    const dx = Math.max(-HOP, Math.min(HOP, target.x - at.x));
    const y = Math.abs(target.x - at.x) <= HOP ? target.y : at.y;
    let hop = { x: at.x + dx, y };
    if (rock(hop)) hop = { x: hop.x, y: hop.y + 1 };
    const p = await onScreen(room, hop);
    await page.mouse.click(p.x, p.y);
    await page.waitForTimeout(60);
    await stood(page, room);
    await page.waitForTimeout(350); // the camera's pan (260 ms) ends
  }
  const at = await tileOf(room);
  return at.x === target.x && at.y === target.y;
}

const fogOf = async (room) => {
  const [hidden, explored, inSight, goblinsBeyond, exploredSet] = (
    (await room.getAttribute("data-fog")) ?? ""
  )
    .split(" ")
    .map(Number);
  return { hidden, explored, inSight, goblinsBeyond, exploredSet };
};

/** Records every value the room's `data-bake-ms`, `data-fog` and `data-tile` take. */
function watchRoom() {
  const room = document.querySelector("[data-camera]");
  window.__bakes = [];
  window.__fogs = [];
  window.__tiles = [];
  new MutationObserver((records) => {
    for (const r of records) {
      const value = room.getAttribute(r.attributeName);
      if (r.attributeName === "data-bake-ms") window.__bakes.push(Number(value));
      if (r.attributeName === "data-fog") window.__fogs.push(value);
      if (r.attributeName === "data-tile") window.__tiles.push(value);
    }
  }).observe(room, {
    attributes: true,
    attributeFilter: ["data-bake-ms", "data-fog", "data-tile"],
  });
}

/** The pixels of a square of `size` CSS px centred on `point`, from a screenshot of the page. */
async function pixels(page, point, size = 5) {
  const png = (await page.screenshot()).toString("base64");
  return page.evaluate(
    async ({ png, x, y, size }) => {
      const image = new Image();
      image.src = `data:image/png;base64,${png}`;
      await image.decode();
      const canvas = document.createElement("canvas");
      canvas.width = image.width;
      canvas.height = image.height;
      const g = canvas.getContext("2d");
      g.drawImage(image, 0, 0);
      const k = image.width / window.innerWidth;
      const half = Math.floor((size * k) / 2);
      const data = g.getImageData(
        Math.round(x * k) - half,
        Math.round(y * k) - half,
        2 * half + 1,
        2 * half + 1,
      ).data;
      const out = [];
      for (let i = 0; i < data.length; i += 4) out.push([data[i], data[i + 1], data[i + 2]]);
      return out;
    },
    { png, x: point.x, y: point.y, size },
  );
}

const gap = ([r, g, b]) => Math.max(r, g, b) - Math.min(r, g, b);
const hex = ([r, g, b]) => `#${[r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")}`;

const quantile = (values, q) => {
  const sorted = [...values].sort((a, b) => a - b);
  if (sorted.length === 0) return NaN;
  const i = (sorted.length - 1) * q;
  const lo = Math.floor(i);
  const hi = Math.ceil(i);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - lo);
};

const SIZES = [
  ["1440x900", { width: 1440, height: 900 }, false],
  ["375x812", { width: 375, height: 812 }, true],
];

const measures = {};

async function run(browser, look, size, viewport, touch) {
  const label = `${look} ${size}`;
  const context = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch });
  await context.addInitScript(timeFrames);
  await isolate(context);
  // The plain look: the atlas refused, so the sandbox draws shapes and flat colours.
  if (look === "plain") await context.route("**/art/**", (route) => route.fulfill({ status: 404 }));
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  // Zoomed out (21 tiles across) so that a tile 8 steps away is on the screen at both sizes.
  await page.goto(`${base}/?fixture=zone&idle=0&zoom=21`);
  // The room's data are written by a frame after its listener: without the atlas no later frame
  // comes by itself, so a resize asks for one.
  await page.waitForTimeout(1200);
  await page.setViewportSize({ width: viewport.width, height: viewport.height + 1 });
  await page.waitForTimeout(300);
  await page.setViewportSize(viewport);
  const room = page.locator("[data-camera]").first();
  await room.waitFor();
  await page.locator('[data-atlas]:not([data-atlas="loading"])').first().waitFor();
  await page.waitForTimeout(800);
  const atlas = await room.getAttribute("data-atlas");
  ok(atlas === (look === "atlas" ? "loaded" : "none"), `${label}: atlas ${atlas}`);
  await page.evaluate(watchRoom);
  await page.screenshot({ path: join(shots, `fog-${look}-${size}-start.png`) });
  const entry = await tileOf(room);
  await page.evaluate(() => (window.__frameMs = []));
  // West along the entry's row toward the runts; the rocks are walked around by the finder.
  const out = { x: 16, y: entry.y + 1 };
  ok(await walkTo(page, room, out), `${label}: walked West to (${out.x}, ${out.y})`);
  // Halfway back the runt seen stands beyond sight, still on the screen: a shot for the eye.
  const half = { x: 12, y: entry.y };
  ok(await walkTo(page, room, half), `${label}: walked back to (${half.x}, ${half.y})`);
  if (!mainOnly) {
    const fog = await fogOf(room);
    ok(
      fog.goblinsBeyond > 0,
      `${label}: at (12, ${entry.y}), ${fog.goblinsBeyond} runt beyond sight drawn`,
    );
  }
  await page.screenshot({ path: join(shots, `fog-${look}-${size}-goblin-beyond.png`) });
  const back = { x: entry.x + 2, y: entry.y };
  ok(await walkTo(page, room, back), `${label}: walked back East to (${back.x}, ${back.y})`);
  const frameMs = await page.evaluate(() => window.__frameMs);
  const figures = {
    frames: frameMs.length,
    median: quantile(frameMs, 0.5),
    p95: quantile(frameMs, 0.95),
  };
  console.log(
    `  measure ${label}: ${figures.frames} frames over the walk, median ${figures.median.toFixed(3)} ms, p95 ${figures.p95.toFixed(3)} ms`,
  );
  if (!mainOnly) {
    const fog = await fogOf(room);
    console.log(`  note ${label}: data-fog ${JSON.stringify(fog)}`);
    ok(fog.hidden > 0 && fog.explored > 0 && fog.inSight > 0, `${label}: tiles in every state`);
    ok(
      fog.explored + fog.inSight === fog.exploredSet,
      `${label}: the tiles drawn explored or in sight are the explored set (${fog.explored} + ${fog.inSight} = ${fog.exploredSet}): no unseen tile drawn`,
    );
    const hero = await tileOf(room);
    // The tiles stepped on are floor, explored, and hold no actor now.
    const walked = (await page.evaluate(() => window.__tiles))
      .filter(Boolean)
      .map((t) => t.split(",").map(Number))
      .map(([x, y]) => ({ x, y }));
    // A runt was seen when it stood within sight (6) of a tile stepped on; never seen, never drawn.
    const seen = RUNTS.filter((r) => walked.some((t) => distance(r, t) <= 6));
    const beyond = seen.filter((r) => distance(r, hero) > 6).length;
    ok(
      beyond > 0 && fog.goblinsBeyond === beyond,
      `${label}: the runts seen (${seen.length} of ${RUNTS.length}), now beyond sight, drawn (${fog.goblinsBeyond} of ${beyond})`,
    );
    const far =
      walked.find((t) => distance(t, hero) === 8) ?? walked.find((t) => distance(t, hero) === 9);
    const near = walked.find((t) => distance(t, hero) >= 2 && distance(t, hero) <= 3);
    ok(far && near, `${label}: a walked tile beyond sight and one in sight`);
    if (far && near) {
      const grey = await pixels(page, await onScreen(room, far));
      const colour = await pixels(page, await onScreen(room, near));
      const maxGrey = Math.max(...grey.map(gap));
      const minColour = Math.min(...colour.map(gap));
      ok(
        maxGrey <= GREY_TOLERANCE,
        `${label}: (${far.x}, ${far.y}) beyond sight is grey: ${grey.length} pixels, largest R/G/B gap ${maxGrey} (e.g. ${hex(grey[0])})`,
      );
      ok(
        minColour > COLOUR_GAP,
        `${label}: (${near.x}, ${near.y}) in sight is in colour: smallest R/G/B gap ${minColour} (e.g. ${hex(colour[0])})`,
      );
    }
    // The bakes of the steps that explored: every change of `data-bake-ms` is a new bake.
    const bakes = await page.evaluate(() => window.__bakes);
    const fogs = await page.evaluate(() => window.__fogs);
    const grew = fogs.filter((f, i) => i > 0 && f.split(" ")[4] !== fogs[i - 1].split(" ")[4]);
    figures.bakes = bakes.length;
    figures.bakeMedian = quantile(bakes, 0.5);
    figures.bakeMax = Math.max(...bakes);
    figures.exploringSteps = grew.length;
    console.log(
      `  measure ${label}: ${grew.length} steps explored tiles; ${bakes.length} bakes seen (a chunk, colour and grey), median ${figures.bakeMedian.toFixed(2)} ms, max ${figures.bakeMax.toFixed(2)} ms`,
    );
  }
  measures[`${look} ${size}`] = figures;
  await page.screenshot({ path: join(shots, `fog-${look}-${size}-walked.png`) });
  ok(errors.length === 0, `${label}: no page error`);
  for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  await context.close();
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}${mainOnly ? " (measures only)" : ""}`);
  for (const look of looks) {
    for (const [size, viewport, touch] of SIZES) {
      console.log(`=== ${look} ${size} ===`);
      await run(browser, look, size, viewport, touch);
    }
  }
  if (process.env.VERIFY_MEASURE_OUT) {
    writeFileSync(process.env.VERIFY_MEASURE_OUT, JSON.stringify(measures, null, 2));
  }
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
