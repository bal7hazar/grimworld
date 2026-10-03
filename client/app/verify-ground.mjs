/* global console, process, fetch, setTimeout, performance, window */
/* eslint-disable no-empty */
// The textured ground in a real browser (CLI-03g1): the zone and both hubs at 375 × 812 and
// 1440 × 900, with the atlas built by `tools/art/build.py` (never committed, D-73). Run by hand,
// not by CI: `pnpm --filter @grimworld/app verify:ground`. Starts the dev server as its own process
// group and sends SIGTERM to that recorded group in `finally`.
//
// For each location and size: the ground is drawn from the atlas's cells (`data-ground`), a walk,
// the camera follows, no frame once the walk ends, no page error. In the zone, the frame time at
// the default zoom over a 10-step walk (AC-8): every display-frame callback is timed by a wrapper
// of `requestAnimationFrame` installed before the page's scripts, so the same measure runs on a
// branch without CLI-03g1's `FrameStats` (`VERIFY_MAIN=1`: measures only, no ground check). The
// median and 95th percentile go to `VERIFY_MEASURE_OUT` (JSON) when it is set; the last chunk's
// bake (`data-bake-ms`) is printed. Headless Chromium renders in software: compare runs on the
// same machine, not the figures alone.
//
// With VERIFY_SHOTS=1, shots into VERIFY_SHOTS_DIR (default the untracked `.verify-out/`; D-73:
// never committed, attached or posted): each location at each size, and the zone at the four zoom
// presets in `continuous`, `snap` and `sharp` (AC-9, looked at by eye).
//
// Env: VERIFY_PORT (default 5198), VERIFY_CHANNEL, VERIFY_ROOT (the checkout whose dev server runs;
// default this one), VERIFY_MAIN=1, VERIFY_MEASURE_OUT, VERIFY_RUNS (walks per size, default 3),
// VERIFY_SHOTS=1, VERIFY_SHOTS_DIR. The server inherits GRIMWORLD_ART_OUT.
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5198);
const base = `http://127.0.0.1:${port}`;
const root = process.env.VERIFY_ROOT ?? join(here, "..", "..");
const mainOnly = process.env.VERIFY_MAIN === "1";
const runs = Number(process.env.VERIFY_RUNS ?? 3);
const shots = process.env.VERIFY_SHOTS
  ? (process.env.VERIFY_SHOTS_DIR ?? join(here, ".verify-out"))
  : null;
if (shots) mkdirSync(shots, { recursive: true });

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

/**
 * Serves every response with COOP and COEP, so that the page is cross-origin isolated and its
 * clock counts in microseconds, not in Chromium's coarsened 100 µs: the frames last about that.
 */
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

/** Times every display-frame callback, before the page's own scripts run. */
function timeFrames() {
  const raf = window.requestAnimationFrame.bind(window);
  window.__frameMs = [];
  window.requestAnimationFrame = (callback) =>
    raf((t) => {
      const start = performance.now();
      try {
        callback(t);
      } finally {
        window.__frameMs.push(performance.now() - start);
      }
    });
}

const ROW_HEIGHT = (64 / Math.sqrt(3)) * 1.5;
const tileToPixel = (t) => ({ x: -(t.x + (t.y & 1) / 2) * 64, y: -t.y * ROW_HEIGHT });

/** The room on a page: the sandbox's root (a room, or a hub's screen). */
const roomOf = (page, hub) =>
  page.locator(hub ? '[data-screen="hub"] [data-camera]' : "[data-camera]").first();

async function camera(room) {
  const [x, y, scale] = (await room.getAttribute("data-camera")).split(" ").map(Number);
  return { x, y, scale };
}

async function tapHex(page, room, tile) {
  const c = await camera(room);
  const box = await room.boundingBox();
  const p = tileToPixel(tile);
  await page.mouse.click(box.x + c.x + p.x * c.scale, box.y + c.y + p.y * c.scale);
}

const tileOf = async (room) => (await room.getAttribute("data-tile")).split(",").map(Number);

async function stood(page, room) {
  await page.waitForTimeout(80);
  for (let i = 0; i < 150; i += 1) {
    if ((await room.getAttribute("data-walking")) !== "true") return;
    await page.waitForTimeout(50);
  }
}

/** One step to a neighbour on the same row; the step back next time. True when it moved. */
async function step(page, room, dx) {
  const [x, y] = await tileOf(room);
  await tapHex(page, room, { x: x + dx, y });
  await page.waitForTimeout(60);
  await stood(page, room);
  await page.waitForTimeout(350); // the camera's pan (260 ms) ends
  const [nx, ny] = await tileOf(room);
  return nx === x + dx && ny === y;
}

const quantile = (values, q) => {
  const sorted = [...values].sort((a, b) => a - b);
  if (sorted.length === 0) return NaN;
  const i = (sorted.length - 1) * q;
  const lo = Math.floor(i);
  const hi = Math.ceil(i);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - lo);
};

const SIZES = [
  ["375x812", { width: 375, height: 812 }, true],
  ["1440x900", { width: 1440, height: 900 }, false],
];

const LOCATIONS = [
  ["zone", "/?fixture=zone&idle=0", false],
  ["town", "/?hub=town&idle=0", true],
  ["outpost", "/?hub=outpost&idle=0", true],
];

const measures = {};

async function location(browser, size, viewport, touch, [name, url, hub]) {
  const label = `${name} ${size}`;
  const context = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch });
  await context.addInitScript(timeFrames);
  await isolate(context);
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  await page.goto(base + url);
  const room = roomOf(page, hub);
  await room.waitFor();
  await page.locator('[data-atlas]:not([data-atlas="loading"])').first().waitFor();
  await page.waitForTimeout(800);
  if (name === "zone") {
    const isolated = await page.evaluate(() => window.crossOriginIsolated);
    ok(isolated, `${label}: cross-origin isolated (a fine clock)`);
  }
  const atlas = await room.getAttribute("data-atlas");
  ok(atlas === "loaded", `${label}: atlas ${atlas}`);
  if (!mainOnly) {
    const ground = await room.getAttribute("data-ground");
    ok(ground === "atlas", `${label}: the ground drawn from the atlas's cells (${ground})`);
    console.log(`  note ${label}: last chunk's bake ${await room.getAttribute("data-bake-ms")} ms`);
  }
  if (shots) await page.screenshot({ path: join(shots, `ground-${name}-${size}.png`) });
  // The walk: steps back and forth on a row, timed frame by frame (the zone's figures, AC-8).
  let dx = -1;
  if (!(await step(page, room, dx))) {
    dx = 1;
    ok(await step(page, room, dx), `${label}: a first step (one way or the other)`);
  }
  const steps = name === "zone" ? 10 * runs : 2;
  await page.evaluate(() => (window.__frameMs = []));
  let moved = 0;
  for (let i = 0; i < steps; i += 1) {
    dx = -dx;
    if (await step(page, room, dx)) moved += 1;
  }
  const frameMs = await page.evaluate(() => window.__frameMs);
  ok(moved === steps, `${label}: walked ${moved} of ${steps} steps`);
  const c = await camera(room);
  const box = await room.boundingBox();
  const [x, y] = await tileOf(room);
  const p = tileToPixel({ x, y });
  const off = Math.hypot(c.x + p.x * c.scale - box.width / 2, c.y + p.y * c.scale - box.height / 2);
  ok(off < 2, `${label}: the camera followed (${off.toFixed(1)} px off the centre)`);
  const frames = Number(await room.getAttribute("data-frames"));
  await page.waitForTimeout(1000);
  ok(
    Number(await room.getAttribute("data-frames")) === frames,
    `${label}: no frame once the walk ends (${frames})`,
  );
  if (name === "zone") {
    const figures = {
      frames: frameMs.length,
      median: quantile(frameMs, 0.5),
      p95: quantile(frameMs, 0.95),
    };
    measures[size] = figures;
    console.log(
      `  measure ${label}: ${figures.frames} frame callbacks over ${moved} steps, median ${figures.median.toFixed(3)} ms, p95 ${figures.p95.toFixed(3)} ms`,
    );
  }
  if (shots) await page.screenshot({ path: join(shots, `ground-${name}-${size}-walked.png`) });
  ok(errors.length === 0, `${label}: no page error`);
  for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  await context.close();
}

/** AC-9: the zone at the four zoom presets in each scale mode, for the eye. */
async function zoomShots(browser, size, viewport, touch) {
  const context = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  for (const mode of ["continuous", "snap", "sharp"]) {
    for (const across of [13, 9, 25, 4]) {
      await page.goto(`${base}/?fixture=zone&idle=0&zoom=${across}&scale=${mode}`);
      await page.locator('[data-atlas]:not([data-atlas="loading"])').first().waitFor();
      await page.waitForTimeout(600);
      await page.screenshot({ path: join(shots, `zoom-${size}-${mode}-${across}.png`) });
    }
  }
  ok(errors.length === 0, `zoom shots ${size}: no page error`);
  await context.close();
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}${mainOnly ? " (measures only)" : ""}`);
  for (const [size, viewport, touch] of SIZES) {
    console.log(`=== ${size} ===`);
    for (const loc of mainOnly ? LOCATIONS.slice(0, 1) : LOCATIONS) {
      await location(browser, size, viewport, touch, loc);
    }
    if (shots && !mainOnly) await zoomShots(browser, size, viewport, touch);
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
