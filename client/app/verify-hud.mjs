/* global console, process, fetch, setTimeout, performance, document, window, getComputedStyle, requestAnimationFrame */
/* eslint-disable no-empty */
// The HUD in a real browser (CLI-03l): the status band in the town, the outpost and a zone (the
// instance after the Gate), at 1440 × 900 (mouse) at ratios 1 and 2 and 375 × 812 (touch) at 1, 2
// and 3, each with no `?hud=`, `?hud=low` and `?hud=empty`, with the atlas built by
// `tools/art/build.py` (never committed, D-73). Run by hand, not by CI:
// `pnpm --filter @grimworld/app verify:hud`. Starts the dev server as its own process group and
// sends SIGTERM to that recorded group in `finally`.
//
// On each (AC-6): `data-chrome` and `data-hud` both `atlas`; the band at most 72 CSS px tall and
// nothing past the viewport's sides; each meter's fill = `fillWidth` of its trough within one
// device px (no fill element at 0); the band, the map's box and the instance's control column do
// not overlap; at 1440 the left panel's 96 px portrait; in the town, a tap on Maren opens the
// inspect dialog with her portrait; at a root font size of 200 % no figure is clipped; at 1440 the
// root's and a button's `cursor` name an image, at 375 they do not; no page error.
//
// Then (AC-7, AC-8) a 10-step walk in the zone (VERIFY_RUNS times, default 3) and a building walk
// in the town at both sizes: the tiles walked and the screens opened, the map's boxes, and the zone's
// frame times (every display-frame callback that issued a WebGL draw, timed by a wrapper of
// `requestAnimationFrame` installed before the page's scripts, as `verify-ground.mjs`); and the
// band's renders (`data-hud-renders`) before and after the walk: none.
//
// Modes. VERIFY_MAIN=1: a checkout without the HUD (`origin/main`, VERIFY_ROOT): only the walks,
// boxes and frames are recorded. VERIFY_PLAIN=1: no art (`GRIMWORLD_ART_OUT` on an empty folder):
// `data-chrome` and `data-hud` both `plain`, the plain portrait, CSS bars (AC-9). VERIFY_STALE=1:
// the HUD's entries filtered out of the served `sprites.json`: `data-chrome="atlas"`,
// `data-hud="plain"` (AC-9). VERIFY_OUT: the record as JSON. VERIFY_COMPARE: such a record of
// another run: from `main`, the walks identical, each map box shorter by the band's height
// (± 1 px), the frame figures within +10 % (median) and +25 % (95th percentile); from an atlas run
// (in VERIFY_PLAIN), the band's boxes within 1 px. VERIFY_SHOTS=1: shots into VERIFY_SHOTS_DIR
// (default the untracked `.verify-out/`; D-73: never committed, attached or posted).
//
// Env: VERIFY_PORT (default 5197), VERIFY_CHANNEL, VERIFY_ROOT, VERIFY_MAIN, VERIFY_PLAIN,
// VERIFY_STALE, VERIFY_RUNS, VERIFY_OUT, VERIFY_COMPARE, VERIFY_SHOTS, VERIFY_SHOTS_DIR. The
// server inherits GRIMWORLD_ART_OUT.
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5197);
const base = `http://127.0.0.1:${port}`;
const root = process.env.VERIFY_ROOT ?? join(here, "..", "..");
const mainOnly = process.env.VERIFY_MAIN === "1";
const plain = process.env.VERIFY_PLAIN === "1";
const stale = process.env.VERIFY_STALE === "1";
const runs = Number(process.env.VERIFY_RUNS ?? 3);
const compare = process.env.VERIFY_COMPARE
  ? JSON.parse(readFileSync(process.env.VERIFY_COMPARE, "utf8"))
  : null;
const shots = process.env.VERIFY_SHOTS
  ? (process.env.VERIFY_SHOTS_DIR ?? join(here, ".verify-out"))
  : null;
if (shots) mkdirSync(shots, { recursive: true });

const SIZES = [
  { name: "1440x900", viewport: { width: 1440, height: 900 }, touch: false, ratios: [1, 2] },
  { name: "375x812", viewport: { width: 375, height: 812 }, touch: true, ratios: [1, 2, 3] },
];
const HUDS = ["", "low", "empty"];
const FIGURES = { "": [160, 20, 0], low: [37, 5, 3], empty: [0, 0, 0] };
const MAX = [160, 20];
const HUD_ENTRIES = [
  "bar_big",
  "bar_big_fill",
  "bar_small",
  "bar_small_fill_energy",
  "icon_sword",
  "portrait_vanguard",
  "portrait_warden",
  "portrait_cleric",
  "cursor_arrow",
  "cursor_hand",
];
const want = plain ? ["plain", "plain"] : stale ? ["atlas", "plain"] : ["atlas", "atlas"];

let failures = 0;
function ok(condition, message) {
  if (!condition) console.log(`  FAIL ${message}`);
  if (!condition) failures += 1;
  return condition;
}

/** chrome/scale.ts `fillWidth`, copied: the check does not import the client's modules. */
function fillWidth(trackDevicePx, current, max) {
  if (!(max > 0) || !(trackDevicePx > 0) || !Number.isFinite(current)) return 0;
  return Math.round((trackDevicePx * Math.min(Math.max(current, 0), max)) / max);
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
  for (let i = 0; i < 150; i += 1) {
    try {
      if ((await fetch(base)).ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`the dev server did not answer:\n${log}`);
}

/** Times every display-frame callback that drew, before the page's own scripts run. */
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

/**
 * Every response with COOP and COEP (a cross-origin isolated page: a clock in microseconds); in
 * VERIFY_STALE, `sprites.json` without the HUD's entries.
 */
async function serve(context) {
  await context.route("**/*", async (route) => {
    const response = await route.fetch();
    const headers = {
      ...response.headers(),
      "cross-origin-opener-policy": "same-origin",
      "cross-origin-embedder-policy": "require-corp",
    };
    if (stale && route.request().url().endsWith("/art/sprites.json")) {
      const index = await response.json();
      for (const name of HUD_ENTRIES) delete index.sprites[name];
      await route.fulfill({ response, headers, body: JSON.stringify(index) });
      return;
    }
    await route.fulfill({ response, headers });
  });
}

const screenOf = (page, name) => page.locator(`[data-screen="${name}"]`).first();
const roomOf = (page, name) => page.locator(`[data-screen="${name}"] [data-camera]`).first();
const frames = (page) =>
  page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));

/** Opens a location: a hub by its URL, the zone by the town's Gate (the instance). */
async function open(page, location, hud) {
  const q = `&entry=0&idle=0${hud ? `&hud=${hud}` : ""}`;
  const hub = location === "zone" ? "town" : location;
  await page.goto(`${base}/?hub=${hub}${q}`);
  await screenOf(page, "hub").waitFor();
  if (location === "zone") {
    await page.locator('nav[aria-label="Services"]').getByRole("button", { name: /^Gate/ }).click();
    await screenOf(page, "gate").waitFor();
    await page
      .getByRole("button", { name: /^Leave by gate/ })
      .first()
      .click();
    const skip = page.getByRole("button", { name: "Skip ▸", exact: true });
    await Promise.race([
      screenOf(page, "instance").waitFor(),
      skip.waitFor().then(() => skip.click().catch(() => {})),
    ]);
    await screenOf(page, "instance").waitFor();
  }
  const screen = location === "zone" ? "instance" : "hub";
  await page
    .locator(`[data-screen="${screen}"] [data-atlas]:not([data-atlas="loading"])`)
    .first()
    .waitFor();
  if (!mainOnly) {
    await page
      .waitForFunction(
        ([chrome, hud]) =>
          document.querySelector("[data-chrome]")?.getAttribute("data-chrome") === chrome &&
          document.querySelector("[data-hud]")?.getAttribute("data-hud") === hud,
        want,
        { timeout: 10000 },
      )
      .catch(() => {});
  }
  await frames(page);
  await page.waitForTimeout(150);
  return screen;
}

/** The band and its parts as they stand, measured in the page. */
function measureBand() {
  const box = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return [r.x, r.y, r.width, r.height].map((v) => Math.round(v * 100) / 100);
  };
  const band = document.querySelector('section[aria-label="Status"]');
  const meters = [...(band?.querySelectorAll('[role="meter"]') ?? [])].map((m) => {
    const track = m.querySelector(".gw-bar-track");
    const fill = m.querySelector(".gw-bar-fill");
    return {
      label: m.getAttribute("aria-label"),
      now: Number(m.getAttribute("aria-valuenow")),
      max: Number(m.getAttribute("aria-valuemax")),
      box: box(m),
      track: box(track),
      trackPx: Number(track?.getAttribute("data-track-px")),
      fill: box(fill),
    };
  });
  const width = window.innerWidth;
  const overflow = [];
  for (const el of document.querySelectorAll("body *")) {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    if (r.width === 0 || s.visibility === "hidden" || s.display === "none") continue;
    if (el.closest("[data-label]") || el.tagName === "CANVAS") continue;
    if (r.right > width + 0.5 || r.left < -0.5) {
      overflow.push(`${el.tagName.toLowerCase()}.${el.className || ""}`);
    }
  }
  const figures = [...(band?.querySelectorAll("[data-figure]") ?? [])];
  const leave = [...document.querySelectorAll("button")].find((b) => b.textContent === "Leave");
  const rootEl = document.querySelector("[data-chrome]");
  const button = [...document.querySelectorAll("button")].find((b) => !b.disabled);
  return {
    dpr: window.devicePixelRatio,
    chrome: rootEl?.getAttribute("data-chrome") ?? null,
    hud: band?.getAttribute("data-hud") ?? null,
    renders: Number(band?.getAttribute("data-hud-renders") ?? NaN),
    band: box(band),
    portrait: band?.querySelector(".gw-portrait")?.getAttribute("data-portrait") ?? null,
    portraitBox: box(band?.querySelector(".gw-portrait")),
    adrenaline: band?.querySelector('[aria-label^="Adrenaline"]')?.getAttribute("aria-label"),
    meters,
    map: box(document.querySelector("[data-camera]")),
    controls: box(leave?.parentElement),
    side: box(document.querySelector('aside[aria-label="Character sheet and build"] .gw-portrait')),
    sidePortrait:
      document
        .querySelector('aside[aria-label="Character sheet and build"] .gw-portrait')
        ?.getAttribute("data-portrait") ?? null,
    clipped: figures.filter((f) => f.scrollWidth > f.clientWidth + 0.5).length,
    overflow,
    cursor: rootEl ? getComputedStyle(rootEl).cursor : null,
    buttonCursor: button ? getComputedStyle(button).cursor : null,
  };
}

const record = { boxes: {}, walks: {}, frames: {} };

/** AC-6 / AC-9 on one location at one size, ratio and `?hud=`. */
async function check(page, label, location, hud, size) {
  const screen = await open(page, location, hud);
  const m = await page.evaluate(measureBand);
  record.boxes[label] = { band: m.band, map: m.map, meters: m.meters.map((x) => x.box) };
  record.boxes[label].portrait = m.portraitBox;
  ok(m.chrome === want[0], `${label}: data-chrome ${m.chrome}, want ${want[0]}`);
  ok(m.hud === want[1], `${label}: data-hud ${m.hud}, want ${want[1]}`);
  ok(m.band && m.band[3] <= 72.01, `${label}: band ${m.band?.[3]} CSS px tall (≤ 72)`);
  ok(m.overflow.length === 0, `${label}: nothing past the sides (${m.overflow.slice(0, 3)})`);
  ok(m.meters.length === 2, `${label}: two meters`);
  const figures = FIGURES[hud];
  m.meters.forEach((meter, i) => {
    ok(meter.now === figures[i] && meter.max === MAX[i], `${label}: ${meter.label} ${meter.now}`);
    const trackPx = Math.round(meter.track[2] * m.dpr);
    ok(Math.abs(trackPx - meter.trackPx) <= 1, `${label}: ${meter.label} trough ${trackPx} px`);
    const fill = fillWidth(meter.trackPx, figures[i], MAX[i]);
    if (fill === 0) ok(meter.fill === null, `${label}: ${meter.label}: no fill element at 0`);
    else {
      const got = (meter.fill?.[2] ?? 0) * m.dpr;
      ok(Math.abs(got - fill) <= 1, `${label}: ${meter.label} fill ${got} device px, want ${fill}`);
      ok(
        Math.abs(meter.fill[1] - meter.track[1]) < 0.01 &&
          Math.abs(meter.fill[0] - meter.track[0]) < 0.01,
        `${label}: ${meter.label} fill at the trough's corner`,
      );
    }
  });
  ok(
    m.adrenaline === `Adrenaline: ${figures[2]} ${figures[2] === 1 ? "strike" : "strikes"}`,
    `${label}: ${m.adrenaline}`,
  );
  ok(
    m.portrait === (want[1] === "atlas" ? "portrait_vanguard" : "plain"),
    `${label}: portrait ${m.portrait}`,
  );
  ok(m.band[1] + m.band[3] <= m.map[1] + 0.5, `${label}: the band above the map, no overlap`);
  if (screen === "instance") {
    const [cx, cy, cw, ch] = m.controls;
    const [mx, my, mw, mh] = m.map;
    ok(
      cx >= mx - 0.5 && cy >= my - 0.5 && cx + cw <= mx + mw + 0.5 && cy + ch <= my + mh + 0.5,
      `${label}: the control column inside the map's box`,
    );
  }
  if (size.name === "1440x900") {
    ok(
      m.side?.[2] === 96 && m.sidePortrait === m.portrait,
      `${label}: the sheet's portrait ${m.side?.[2]} px, ${m.sidePortrait}`,
    );
    if (!plain) {
      ok(/image-set|url\(/.test(m.cursor), `${label}: the root's cursor is the pack's arrow`);
      ok(/image-set|url\(/.test(m.buttonCursor), `${label}: a button's cursor is the hand`);
    }
  } else {
    ok(!/image-set|url\(/.test(m.cursor ?? ""), `${label}: touch: the root's cursor unchanged`);
    ok(!/image-set|url\(/.test(m.buttonCursor ?? ""), `${label}: touch: a button's unchanged`);
  }
  // A larger text size: the band may grow, never clip.
  await page.evaluate(() => (document.documentElement.style.fontSize = "200%"));
  await frames(page);
  const big = await page.evaluate(measureBand);
  ok(big.clipped === 0, `${label}: at 200 %, no figure clipped`);
  ok(
    big.overflow.length === 0,
    `${label}: at 200 %, nothing past the sides (${big.overflow.slice(0, 3)})`,
  );
  await page.evaluate(() => (document.documentElement.style.fontSize = ""));
  await frames(page);
  if (location === "town" && hud === "") {
    // Maren, a Warden, stands in the town (fixtures/hubs.ts): her portrait in the inspect dialog.
    await tapHex(page, "hub", { x: 7, y: 5 });
    const dialog = page.getByRole("dialog", { name: "Adventurer" });
    await dialog.waitFor({ timeout: 5000 }).catch(() => {});
    const inspected = await dialog
      .locator(".gw-portrait")
      .first()
      .getAttribute("data-portrait")
      .catch(() => null);
    ok(
      inspected === (want[1] === "atlas" ? "portrait_warden" : "plain"),
      `${label}: the inspect dialog's portrait ${inspected}`,
    );
  }
  return m;
}

const ROW_HEIGHT = (64 / Math.sqrt(3)) * 1.5;
const tileToPixel = (t) => ({ x: -(t.x + (t.y & 1) / 2) * 64, y: -t.y * ROW_HEIGHT });

async function tapHex(page, screen, tile) {
  const room = roomOf(page, screen);
  const [x, y, scale] = (await room.getAttribute("data-camera")).split(" ").map(Number);
  const box = await room.boundingBox();
  const p = tileToPixel(tile);
  await page.mouse.click(box.x + x + p.x * scale, box.y + y + p.y * scale);
}

const tileOf = async (page, screen) => roomOf(page, screen).getAttribute("data-tile");

async function stood(page, screen) {
  await page.waitForTimeout(80);
  for (let i = 0; i < 150; i += 1) {
    if ((await roomOf(page, screen).getAttribute("data-walking")) !== "true") return;
    await page.waitForTimeout(50);
  }
}

/** One step to a neighbour on the same row. The tile reached. */
async function step(page, dx) {
  const [x, y] = (await tileOf(page, "instance")).split(",").map(Number);
  await tapHex(page, "instance", { x: x + dx, y });
  await page.waitForTimeout(60);
  await stood(page, "instance");
  await page.waitForTimeout(350);
  return tileOf(page, "instance");
}

const quantile = (values, q) => {
  const sorted = [...values].sort((a, b) => a - b);
  if (sorted.length === 0) return NaN;
  const i = (sorted.length - 1) * q;
  const lo = Math.floor(i);
  const hi = Math.ceil(i);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - lo);
};

/** AC-7 / AC-8 at one size: the zone's walk timed, the town's building walk. */
async function walks(browser, size) {
  const context = await browser.newContext({
    viewport: size.viewport,
    hasTouch: size.touch,
    isMobile: size.touch,
  });
  await context.addInitScript(timeFrames);
  await serve(context);
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  const label = `walk ${size.name}`;
  await open(page, "zone", "");
  ok(await page.evaluate(() => window.crossOriginIsolated), `${label}: a fine clock`);
  const start = await tileOf(page, "instance");
  const tiles = [start];
  let dx = -1;
  let first = await step(page, dx);
  if (first === start) {
    dx = 1;
    first = await step(page, dx);
  }
  tiles.push(first);
  const renders = () =>
    page.evaluate(() =>
      Number(document.querySelector("[data-hud-renders]")?.getAttribute("data-hud-renders")),
    );
  const before = await renders();
  await page.evaluate(() => (window.__frameMs = []));
  for (let i = 0; i < 10 * runs; i += 1) {
    dx = -dx;
    tiles.push(await step(page, dx));
  }
  const frameMs = await page.evaluate(() => window.__frameMs);
  const after = await renders();
  if (!mainOnly) ok(after === before, `${label}: the band rendered ${after - before} times`);
  record.frames[size.name] = {
    frames: frameMs.length,
    median: quantile(frameMs, 0.5),
    p95: quantile(frameMs, 0.95),
  };
  const f = record.frames[size.name];
  console.log(
    `  measure ${label}: ${f.frames} frames over ${tiles.length - 2} steps, median ${f.median.toFixed(3)} ms, p95 ${f.p95.toFixed(3)} ms`,
  );
  const screens = [];
  // The town: a building walked to (the Smith above its door), its screen, back.
  await open(page, "town", "");
  const town = [await tileOf(page, "hub")];
  await tapHex(page, "hub", { x: 5, y: 8 });
  await screenOf(page, "service").waitFor({ timeout: 15_000 });
  screens.push(await screenOf(page, "service").getAttribute("data-service"));
  await page.getByRole("button", { name: "Back" }).click();
  await screenOf(page, "hub").waitFor();
  await page.waitForTimeout(300);
  town.push(await tileOf(page, "hub"));
  record.walks[size.name] = { zone: tiles, town, screens };
  ok(errors.length === 0, `${label}: no page error`);
  for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  await context.close();
}

async function pass(browser, size, dpr) {
  const context = await browser.newContext({
    viewport: size.viewport,
    deviceScaleFactor: dpr,
    hasTouch: size.touch,
    isMobile: size.touch,
  });
  await serve(context);
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  for (const location of ["town", "outpost", "zone"]) {
    for (const hud of mainOnly ? [""] : HUDS) {
      const label = `${location} ${size.name}@${dpr}x${hud ? ` hud=${hud}` : ""}`;
      if (mainOnly) {
        await open(page, location, hud);
        const map = await page.evaluate(() => {
          const r = document.querySelector("[data-camera]").getBoundingClientRect();
          return [r.x, r.y, r.width, r.height].map((v) => Math.round(v * 100) / 100);
        });
        record.boxes[label] = { map };
        continue;
      }
      await check(page, label, location, hud, size);
      if (shots && dpr === 2 && hud !== "empty") {
        await open(page, location, hud);
        await page.screenshot({
          path: join(shots, `hud-${location}-${size.name}${hud ? `-${hud}` : ""}.png`),
        });
      }
      if (shots && (dpr === 1 || dpr === 3) && hud === "" && location === "town") {
        await open(page, location, hud);
        await page
          .locator('section[aria-label="Status"]')
          .screenshot({ path: join(shots, `hud-band-${size.name}@${dpr}x.png`) });
      }
    }
  }
  ok(errors.length === 0, `${size.name}@${dpr}x: no page error`);
  for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  await context.close();
}

/** Against `main`'s record (AC-7, AC-8) or, plain, against the atlas's (AC-9). */
function against(other) {
  if (plain || stale) {
    for (const [label, mine] of Object.entries(record.boxes)) {
      const theirs = other.boxes[label];
      if (!theirs?.band) continue;
      const near = (a, b) => a && b && a.every((v, i) => Math.abs(v - b[i]) <= 1);
      ok(near(mine.band, theirs.band), `${label}: the band ${mine.band} vs ${theirs.band}`);
      ok(near(mine.portrait, theirs.portrait), `${label}: the portrait's box`);
      mine.meters.forEach((m, i) =>
        ok(near(m, theirs.meters[i]), `${label}: meter ${i} ${m} vs ${theirs.meters[i]}`),
      );
    }
    return;
  }
  for (const [size, mine] of Object.entries(record.walks)) {
    const theirs = other.walks[size];
    ok(
      JSON.stringify(mine) === JSON.stringify(theirs),
      `walk ${size}: identical to main (${JSON.stringify(mine)})`,
    );
  }
  for (const [label, mine] of Object.entries(record.boxes)) {
    const theirs = other.boxes[label];
    if (!theirs || !mine.band) continue;
    const shorter = theirs.map[3] - mine.map[3];
    ok(
      Math.abs(shorter - mine.band[3]) <= 1 && Math.abs(theirs.map[2] - mine.map[2]) <= 1,
      `${label}: map ${mine.map} vs main ${theirs.map}: shorter by ${shorter.toFixed(2)}, the band ${mine.band[3]}`,
    );
  }
  for (const [size, mine] of Object.entries(record.frames)) {
    const theirs = other.frames[size];
    const median = mine.median / theirs.median;
    const p95 = mine.p95 / theirs.p95;
    console.log(
      `  frames ${size}: median ${mine.median.toFixed(3)} vs ${theirs.median.toFixed(3)} ms (×${median.toFixed(3)}), p95 ${mine.p95.toFixed(3)} vs ${theirs.p95.toFixed(3)} ms (×${p95.toFixed(3)})`,
    );
    ok(median <= 1.1, `frames ${size}: median within +10 %`);
    ok(p95 <= 1.25, `frames ${size}: 95th percentile within +25 %`);
  }
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  const mode = mainOnly ? "main: records only" : plain ? "plain" : stale ? "stale" : "atlas";
  console.log(`browser launched: ${browser.version()} (${mode})`);
  for (const size of SIZES) {
    for (const dpr of size.ratios) {
      console.log(`=== ${size.name} @${dpr}x ===`);
      await pass(browser, size, dpr);
    }
    if (!plain && !stale) await walks(browser, size);
  }
  if (compare) against(compare);
  if (process.env.VERIFY_OUT)
    writeFileSync(process.env.VERIFY_OUT, JSON.stringify(record, null, 1));
} catch (e) {
  failures += 1;
  console.log(`FAIL ${e.stack ?? e}`);
} finally {
  await browser?.close();
  try {
    process.kill(-server.pid, "SIGTERM");
    console.log(`dev server process group ${server.pid} sent SIGTERM`);
  } catch {}
}
console.log(failures === 0 ? "ALL CHECKS PASSED" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
