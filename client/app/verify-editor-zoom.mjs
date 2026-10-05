/* global console, process, fetch, setTimeout, localStorage, Buffer, URL, window, performance, requestAnimationFrame, PerformanceObserver */
/* eslint-disable no-empty */
// The map editor's zoom and pan cost (CLI-09g), in a real browser, headless (software rendering): a
// painted 225 × 225 zone (the largest) at the widest zooms, with the art when GRIMWORLD_ART_OUT
// names the built atlas (D-73: read only, never committed). Per sequence: the frame interval
// (requestAnimationFrame), median, p95 and max, and where the time went: the view's window rebuilt
// (`refreshView`: `editorView` and the renderer's `setView`) and the chunks' bakes
// (`bakeTerrain`). Run by hand, not by CI: `node verify-editor-zoom.mjs`. Starts the dev server as
// its own process group and sends SIGTERM to that recorded group in `finally`.
//
// Env: VERIFY_PORT (default 5288), VERIFY_CHANNEL, VERIFY_ROOT (the checkout whose dev server runs;
// default this one), VERIFY_ZOOM_BEFORE=1 (the renderer's defaults, as before CLI-09g: every chunk
// baked again in the frame its zoom's resolution changes), VERIFY_ZOOM_BUDGET=<n> (another
// `bakesPerFrame` than the editor's, to compare), VERIFY_ZOOM_GRID=0 (the grid's layer off, to
// tell its share), VERIFY_ZOOM_SIDE=<n> (a painted n × n map instead of 225 × 225: past the
// widest view, the window is rebuilt as the camera moves), VERIFY_ZOOM_TARGET=1 fails the run past the target (zooming: p95 under 100 ms,
// no frame over 250 ms).
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5288);
const base = `http://127.0.0.1:${port}`;
const root = process.env.VERIFY_ROOT ?? join(here, "..", "..");

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

/**
 * A painted `side` × `side` zone (225: the largest), floor with a rock in nine, as
 * `verify-editor.mjs`'s.
 */
function largestZone(side) {
  const rows = [];
  for (let y = 0; y < side; y += 1) {
    let terrain = "";
    for (let x = 0; x < side; x += 1) terrain += (x * 7 + y * 11) % 9 === 0 ? "#" : ".";
    rows.push({ y, x: 0, terrain, ground: "g".repeat(side), outline: "1".repeat(side) });
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

const before = process.env.VERIFY_ZOOM_BEFORE === "1";
const budget = process.env.VERIFY_ZOOM_BUDGET ? Number(process.env.VERIFY_ZOOM_BUDGET) : null;

const loadavg = () => readFileSync("/proc/loadavg", "utf8").split(" ").slice(0, 3).join(" ");

const quantile = (list, q) => {
  const s = [...list].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor(q * s.length))] ?? NaN;
};

/**
 * One sequence in the page: `n` frames (at most 30 s), `move(k)` before each; the frame gaps and,
 * by wrapping the canvas's and the renderer's methods, the time of each window rebuild and bake.
 */
function measure(page, name, n) {
  return page.evaluate(
    async ({ name, n }) => {
      const { canvas } = window.__editor;
      const renderer = canvas.renderer;
      const { viewport } = renderer.cameraState();
      const mid = { x: viewport.width / 2, y: viewport.height / 2 };
      const moves = {
        // The grid phase's zoom: in by 3 % a frame for 20 frames, out for 20.
        zoom: (k) => renderer.zoomAt(k % 40 < 20 ? 1.03 : 1 / 1.03, mid),
        // Out by 3 % a frame for 30 frames, then back in: from 120 across to the widest and back.
        sweep: (k) => renderer.zoomAt(k % 60 < 30 ? 1 / 1.03 : 1.03, mid),
        pan: (k) => renderer.pan(k % 120 < 60 ? 6 : -6, 2 * Math.sin(k / 9)),
        // A wheel's notches: in by 3 % a frame for 10 frames, then 20 still (the chunks are baked
        // at the new zoom then); the next 30 out, and so on.
        steps: (k) => {
          if (k % 30 < 10) renderer.zoomAt(Math.floor(k / 30) % 2 === 0 ? 1.03 : 1 / 1.03, mid);
        },
      };
      const move = moves[name];
      const spent = { rebuild: [], source: [], setView: [], bake: [], draw: [], overlay: [] };
      let baked = 0;
      const wrap = (object, key, list, after) => {
        const original = object[key];
        object[key] = function (...args) {
          const start = performance.now();
          const result = original.apply(this, args);
          list.push(performance.now() - start);
          after?.(result);
          return result;
        };
        return () => (object[key] = original);
      };
      // Every texture baked (a chunk's colour or grey, a still in grey).
      const bakeOriginal = renderer.surface.bake.bind(renderer.surface);
      renderer.surface.bake = (...args) => {
        baked += 1;
        return bakeOriginal(...args);
      };
      const undo = [
        wrap(canvas, "refreshView", spent.rebuild),
        wrap(canvas, "source", spent.source),
        wrap(renderer, "setView", spent.setView),
        wrap(renderer, "bakeTerrain", spent.bake),
        // The renderer's whole frame on the CPU (bakes included), and the editor's overlay.
        wrap(renderer, "draw", spent.draw),
        wrap(canvas, "drawOverlay", spent.overlay),
      ];
      // The main thread's long frames (Long Animation Frames API): script, style and layout.
      const long = [];
      // Script time in long frames by what ran it: the frame callbacks (the renderer, the
      // overlay), and the page's messages (React's scheduler: the editor's screen rendered again).
      const scriptBy = { frame: 0, message: 0, other: 0 };
      const observer = new PerformanceObserver((list) => {
        for (const e of list.getEntries()) {
          for (const s of e.scripts) {
            const by = s.invoker.startsWith("FrameRequestCallback")
              ? "frame"
              : s.invoker.startsWith("MessagePort")
                ? "message"
                : "other";
            scriptBy[by] += s.duration;
          }
          const scripts = [...e.scripts].sort((a, b) => b.duration - a.duration);
          long.push({
            duration: e.duration,
            script: e.scripts.reduce((t, s) => t + s.duration, 0),
            layout: e.renderStart ? e.startTime + e.duration - e.styleAndLayoutStart : 0,
            top: scripts[0] ? `${scripts[0].invoker} ${scripts[0].duration.toFixed(0)} ms` : "",
          });
        }
      });
      observer.observe({ type: "long-animation-frame", buffered: false });
      const gaps = [];
      const across = [];
      // Per frame: the textures baked since the last frame callback.
      const bakedPerFrame = [];
      let bakedBefore = 0;
      await new Promise((done) => {
        let last = performance.now();
        const first = last;
        let k = 0;
        const tick = (now) => {
          gaps.push(now - last);
          bakedPerFrame.push(baked - bakedBefore);
          bakedBefore = baked;
          last = now;
          move(k);
          canvas.cameraMoved();
          across.push(renderer.zoomInfo().across);
          k += 1;
          if (k < n && now - first < 30_000) requestAnimationFrame(tick);
          else done();
        };
        requestAnimationFrame(tick);
      });
      observer.disconnect();
      for (const f of undo) f();
      renderer.surface.bake = bakeOriginal;
      const sum = (l) => l.reduce((a, b) => a + b, 0);
      const max = (l) => (l.length ? Math.max(...l) : 0);
      const parts = Object.fromEntries(
        Object.entries(spent).map(([k, l]) => [k, { count: l.length, total: sum(l), max: max(l) }]),
      );
      // The five longest frames: the gap, the textures baked in it and in the one before (the GPU's
      // work of a bake may land in the next frame), the zoom.
      const slowest = gaps
        .map((gap, i) => ({
          gap,
          baked: bakedPerFrame[i] + (bakedPerFrame[i - 1] ?? 0),
          across: across[i - 1] ?? NaN,
        }))
        .slice(5)
        .sort((a, b) => b.gap - a.gap)
        .slice(0, 5);
      return {
        gaps: gaps.slice(5),
        slowest,
        long: long.sort((a, b) => b.duration - a.duration).slice(0, 3),
        scriptBy,
        parts,
        baked,
        across: [Math.min(...across), Math.max(...across)],
        tiles: renderer.view?.tiles.length ?? 0,
        chunks: renderer.chunks.size,
      };
    },
    { name, n },
  );
}

function report(label, r) {
  const g = r.gaps;
  const line = (k) => {
    const p = r.parts[k];
    return `${k} ${p.count}× ${p.total.toFixed(0)} ms (max ${p.max.toFixed(0)})`;
  };
  console.log(
    `  ${label}: frame median ${quantile(g, 0.5).toFixed(1)} ms, p95 ${quantile(g, 0.95).toFixed(1)} ms, ` +
      `max ${Math.max(...g).toFixed(1)} ms (${g.length} frames); across ${r.across[0]}–${r.across[1]}; ` +
      `load ${loadavg()}`,
  );
  console.log(
    `    ${line("rebuild")}; ${line("source")}; ${line("setView")}; ${line("bake")}; ` +
      `${line("draw")}; ${line("overlay")}; ` +
      `${r.baked} textures baked; window ${r.tiles} tiles, ${r.chunks} chunks`,
  );
  const slow = r.slowest.map(
    (f) => `${f.gap.toFixed(0)} ms (${f.baked} baked in 2 frames, ${Math.round(f.across)} across)`,
  );
  console.log(`    slowest: ${slow.join(", ")}`);
  const long = r.long.map(
    (f) =>
      `${f.duration.toFixed(0)} ms (script ${f.script.toFixed(0)}, style+layout ${f.layout.toFixed(0)}; ${f.top})`,
  );
  console.log(`    long animation frames: ${long.join(", ") || "none"}`);
  const by = r.scriptBy;
  console.log(
    `    their script: frame callbacks ${by.frame.toFixed(0)} ms, messages (React) ${by.message.toFixed(0)} ms, other ${by.other.toFixed(0)} ms`,
  );
}

let browser;
const results = {};
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}`);
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  await context.route("**/*", (route) =>
    new URL(route.request().url()).origin === base ? route.continue() : route.abort(),
  );
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e.stack ?? e)));
  await page.goto(`${base}/editor.html`);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.locator("[data-open-file]").setInputFiles({
    name: "largest.grimmap.json",
    mimeType: "application/json",
    buffer: Buffer.from(largestZone(Number(process.env.VERIFY_ZOOM_SIDE ?? 225))),
  });
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor({ timeout: 120_000 });
  await page.waitForFunction(() => window.__editor !== undefined);
  if (before) {
    await page.evaluate(() => {
      const renderer = window.__editor.canvas.renderer;
      renderer.bakesPerFrame = Infinity;
      renderer.keepSharper = 1;
      renderer.rescaleAfterMs = 0;
    });
  }
  if (process.env.VERIFY_ZOOM_GRID === "0") await page.locator('[data-layer="grid"]').uncheck();
  if (budget !== null) {
    await page.evaluate((n) => (window.__editor.canvas.renderer.bakesPerFrame = n), budget);
  }
  const bakes = await page.evaluate(() => {
    const { bakesPerFrame, keepSharper, rescaleAfterMs } = window.__editor.canvas.renderer;
    return `bakesPerFrame ${bakesPerFrame}, keepSharper ${keepSharper}, rescaleAfterMs ${rescaleAfterMs}`;
  });
  const grid = await page.locator('[data-layer="grid"]').isChecked();
  console.log(
    `bakes: ${before ? "the renderer's defaults (before)" : "after"}: ${bakes}; grid ${grid ? "on" : "off"}`,
  );
  const atlas = await page.locator("[data-canvas]").getAttribute("data-atlas");
  console.log(
    `atlas: ${atlas}; canvas ${JSON.stringify(await page.evaluate(() => window.__editor.canvas.renderer.cameraState().viewport))}`,
  );
  const at = async (across) => {
    await page.evaluate((n) => {
      const { canvas } = window.__editor;
      if (n === "widest") for (let i = 0; i < 60; i += 1) canvas.zoomBy(-1);
      else {
        canvas.renderer.zoomTo(n);
        canvas.cameraMoved();
      }
    }, across);
    // Every chunk baked at the zoom's resolution before the sequence starts (at most a minute).
    await page
      .waitForFunction(() => !window.__editor.canvas.renderer.bakesLeft, null, { timeout: 60_000 })
      .catch(() => console.log(`  (${across}: chunks still to bake after a minute)`));
    await page.waitForTimeout(2000);
  };
  for (const [where, name, n] of [
    ["widest", "zoom", 240],
    [120, "sweep", 240],
    ["widest", "steps", 240],
    ["widest", "pan", 240],
    [120, "pan", 240],
  ]) {
    await at(where);
    const r = await measure(page, name, n);
    results[`${name}@${where}`] = r;
    report(`${name} from ${where}`, r);
  }
  ok(errors.length === 0, `no page error${errors.length ? `: ${errors.join(" | ")}` : ""}`);
  if (process.env.VERIFY_ZOOM_TARGET === "1") {
    for (const key of ["zoom@widest", "sweep@120"]) {
      const g = results[key].gaps;
      ok(quantile(g, 0.95) < 100, `${key}: p95 ${quantile(g, 0.95).toFixed(1)} ms under 100 ms`);
      ok(Math.max(...g) <= 250, `${key}: max ${Math.max(...g).toFixed(1)} ms at most 250 ms`);
    }
  }
  await context.close();
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
