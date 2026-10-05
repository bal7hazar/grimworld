/* global console, process, fetch, setTimeout, window, document, Image, MutationObserver */
/* eslint-disable no-empty */
// The foam animated in a real browser (CLI-03o part 2), and CLI-03n's frontier (its follow-up).
// Run by hand, not by CI: `pnpm --filter @grimworld/app verify:water`, with the atlas built by
// `tools/art/build.py` (GRIMWORLD_ART_OUT; never committed, D-73). Starts the dev server as its own
// process group and sends SIGTERM to that recorded group in `finally`.
//
// In the zone, the town and the outpost, at 1440 × 900 and 375 × 812, idle animations off, zoomed
// in (4 tiles across) and dragged onto the nearest foam:
// - the foam in colour is rebuilt in the page from the same modules the renderer uses (`ground.ts`
//   through Vite) and the atlas's 16 frames are read from `/art/`; screen pixels covered by exactly
//   one foam piece, well inside an art pixel, are compared with each frame of the atlas. The phase
//   law (frame = clock + diagonal) must explain at least 90 % of them for one clock, and explain
//   more than the other laws (all in step, the other axes): neighbouring diagonals one frame apart;
// - two captures about 100 ms apart differ, and only on pixels on or by a foam piece;
// - with `?water=still`, and in the plain look (the atlas refused: no foam), two captures are equal.
// The frontier (CLI-03n follow-up): the zone at 1440 × 900, zoom 21, the hero walked to (36, 8),
// then (40, 6) (t-0124's cases): the luminance drop at a land hex's side facing a water hex never
// seen (5 points 1.5 px inside the side against 5 at 12 px) must be small, as beside land, while
// a side facing water in sight keeps its lip (the positive control).
//
// Env: VERIFY_PORT (default 5199), VERIFY_CHANNEL, VERIFY_SHOTS_DIR (default the untracked
// `.verify-out/`; D-73: never committed, attached or posted), VERIFY_PLACES (`zone,town,outpost`),
// VERIFY_FRONTIER=0 to skip the frontier, VERIFY_ROOT (the checkout whose dev server runs; the
// frontier alone runs on a checkout without CLI-03o). The server inherits GRIMWORLD_ART_OUT.
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5199);
const base = `http://127.0.0.1:${port}`;
const root = process.env.VERIFY_ROOT ?? join(here, "..", "..");
const places = (process.env.VERIFY_PLACES ?? "zone,town,outpost").split(",").filter(Boolean);
const shots = process.env.VERIFY_SHOTS_DIR ?? join(here, ".verify-out");
mkdirSync(shots, { recursive: true });

/** The phase law must explain this share of the samples, for one clock. */
const LAW_SHARE = 0.9;
/** A channel within this of the expected colour matches (the bakes and the GPU are 8-bit). */
const TOLERANCE = 6;
/** The frontier: a drop at most this is no lip; the positive control's is above `LIP_DROP`. */
const NO_LIP = 15;
const LIP_DROP = { colour: 30, grey: 20 };

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

const ROW_HEIGHT = (64 / Math.sqrt(3)) * 1.5;
const tileToPixel = (t) => ({ x: -(t.x + (t.y & 1) / 2) * 64, y: -t.y * ROW_HEIGHT });

async function camera(room) {
  const [x, y, scale] = (await room.getAttribute("data-camera")).split(" ").map(Number);
  return { x, y, scale };
}

/** The canvas's box: `data-camera` is tile (0, 0)'s centre on the canvas. */
const canvasBox = (room) => room.locator("canvas").first().boundingBox();

async function onScreen(room, point) {
  const c = await camera(room);
  const box = await canvasBox(room);
  return { x: box.x + c.x + point.x * c.scale, y: box.y + c.y + point.y * c.scale };
}

const tileOf = async (room) => {
  const [x, y] = (await room.getAttribute("data-tile")).split(",").map(Number);
  return { x, y };
};

async function opened(page, look) {
  await page.waitForTimeout(1200);
  const viewport = page.viewportSize();
  // A frame after the room's listener writes its data (as `verify-fog.mjs`).
  await page.setViewportSize({ width: viewport.width, height: viewport.height + 1 });
  await page.waitForTimeout(300);
  await page.setViewportSize(viewport);
  const room = page.locator("[data-camera]").first();
  await room.waitFor();
  await page.locator('[data-atlas]:not([data-atlas="loading"])').first().waitFor();
  await page.waitForTimeout(600);
  const atlas = await room.getAttribute("data-atlas");
  ok(atlas === (look === "plain" ? "none" : "loaded"), `atlas ${atlas}`);
  return room;
}

/**
 * In the page: the foam drawn in colour at the place's opening, rebuilt from the render modules
 * (as `Renderer.syncFoam` builds it), kept on `window.__foam`; the atlas's loop frames, as pixels,
 * on `window.__frames`. Returns the number of pieces.
 */
async function prepare(page, place) {
  return page.evaluate(async (place) => {
    const wiring = await import("/src/sandbox/wiring.ts");
    const ground = await import("/src/render/ground.ts");
    const foam = await import("/src/render/foam.ts");
    const coords = await import("/src/input/coords.ts");
    let world;
    if (place === "zone") {
      const fixtures = await import("/src/sandbox/fixtures/index.ts");
      world = fixtures.fixtureNamed("zone");
    } else {
      const hubs = await import("/src/sandbox/fixtures/hubs.ts");
      const hubWorld = await import("/src/sandbox/fixtures/hubWorld.ts");
      const view = hubs.HUB_VIEWS.get(hubs.HUB_NAMES[place]);
      world = hubWorld.hubWorld(view, hubs.HUB_PATHS.get(view)?.[0] ?? { x: 0, y: 0 });
    }
    const view = wiring.toView(wiring.initialState(world));
    const key = (t) => `${t.x},${t.y}`;
    const chain = view.revealed ?? view.tiles;
    const shown = new Map(view.tiles.map((t) => [key(t), t]));
    const hidden = new Set(
      chain
        .filter((t) => t.kind !== "unrevealed" && shown.get(key(t))?.kind === "unrevealed")
        .map(key),
    );
    const chainAt = new Map(chain.map((t) => [key(t), t]));
    const around = (t) => {
      const c = chainAt.get(key(t));
      if (!c) return view.void ?? null;
      return c.kind === "unrevealed" ? null : (c.ground ?? "grass");
    };
    let pieces = [
      ...ground.waterFoam(chain, { around, hidden }),
      ...ground.voidFoam(view.tiles, view.void, true),
    ];
    if (view.fog) {
      const inSight = new Set(view.sight.map(key));
      const hero = view.actors.find((a) => a.id === view.adventurerId).tile;
      for (const hex of ground.hexesWithin(hero, view.fog.sightRadius)) {
        if (!shown.has(key(hex))) inSight.add(key(hex));
      }
      pieces = pieces.filter((p) => inSight.has(key(p.over)));
    } else if (hidden.size > 0) {
      pieces = pieces.filter((p) => !hidden.has(key(p.over)));
    }
    const byHex = new Map();
    for (const p of pieces) {
      const k = key(p.over);
      if (!byHex.has(k)) byHex.set(k, []);
      byHex.get(k).push(p);
    }
    // The atlas's loop frames, as pixels.
    const index = await (await fetch("/art/sprites.json")).json();
    const frames = [];
    for (const page of index.pages) {
      const json = await (await fetch(`/art/${page.json}`)).json();
      const names = Object.keys(json.frames).filter((n) => n.startsWith("foam_c/loop/"));
      if (names.length === 0) continue;
      const image = new Image();
      image.src = `/art/${page.image}`;
      await image.decode();
      const canvas = document.createElement("canvas");
      canvas.width = image.width;
      canvas.height = image.height;
      const g = canvas.getContext("2d");
      g.drawImage(image, 0, 0);
      for (const name of names.sort()) {
        const f = json.frames[name].frame;
        frames.push(g.getImageData(f.x, f.y, f.w, f.h));
      }
      const water = json.frames["water_c/still/00"]?.frame;
      if (water) window.__water = [...g.getImageData(water.x + 8, water.y + 8, 1, 1).data];
    }
    window.__frames = frames;
    window.__foam = { pieces, byHex, hidden };
    window.__geo = { coords, foam, ground, key };
    return { pieces: pieces.length, frames: frames.length, water: window.__water };
  }, place);
}

/**
 * The world point to bring to the canvas's centre: among the in-colour foam pieces, the one whose
 * window of the canvas's size holds the most diagonals of foam (so that neighbouring diagonals are
 * on the screen), the nearest to the centre among equals.
 */
async function nearestFoam(page, room) {
  const c = await camera(room);
  const box = await canvasBox(room);
  const view = { w: box.width / c.scale, h: box.height / c.scale };
  const centre = { x: (box.width / 2 - c.x) / c.scale, y: (box.height / 2 - c.y) / c.scale };
  return page.evaluate(
    ({ centre, view }) => {
      const { foam } = window.__geo;
      const middles = window.__foam.pieces.map((p) => {
        const n = p.points.length / 2;
        let x = 0;
        let y = 0;
        for (let i = 0; i < n; i++) {
          x += p.points[2 * i] / n;
          y += p.points[2 * i + 1] / n;
        }
        return { x, y, d: foam.foamDiagonal(p.source) };
      });
      let best = null;
      for (const m of middles) {
        const diagonals = new Set();
        for (const o of middles) {
          if (Math.abs(o.x - m.x) < view.w * 0.4 && Math.abs(o.y - m.y) < view.h * 0.4)
            diagonals.add(o.d);
        }
        const d = Math.hypot(m.x - centre.x, m.y - centre.y);
        if (!best || diagonals.size > best.n || (diagonals.size === best.n && d < best.d))
          best = { n: diagonals.size, d, x: m.x, y: m.y };
      }
      return best;
    },
    { centre, view },
  );
}

/** Drags the map so that a world point comes to the screen's centre. */
async function bringToCentre(page, room, point) {
  const box = await canvasBox(room);
  const from = await onScreen(room, point);
  const to = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  // Small drags, from points away from the HUD.
  const steps = 4;
  for (let i = 0; i < steps; i++) {
    const start = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
    const dx = (to.x - from.x) / steps;
    const dy = (to.y - from.y) / steps;
    await page.mouse.move(start.x - dx / 2, start.y - dy / 2);
    await page.mouse.down();
    await page.mouse.move(start.x + dx / 2, start.y + dy / 2, { steps: 12 });
    await page.mouse.up();
    await page.waitForTimeout(120);
  }
  await page.waitForTimeout(400);
}

/**
 * In the page, on a screenshot (`png`, base64): samples every few device pixels covered by one
 * in-colour foam piece, well inside an art pixel and a pixel or more from the piece's edges; for
 * each, which of the 16 frames its colour matches. Returns the samples' sources and matches.
 */
async function samplePhase(page, png, cam, box) {
  return page.evaluate(
    async ({ png, cam, box, TOLERANCE }) => {
      const { coords, foam, key } = window.__geo;
      const image = new Image();
      image.src = `data:image/png;base64,${png}`;
      await image.decode();
      const canvas = document.createElement("canvas");
      canvas.width = image.width;
      canvas.height = image.height;
      const g = canvas.getContext("2d");
      g.drawImage(image, 0, 0);
      const data = g.getImageData(0, 0, image.width, image.height).data;
      const k = image.width / window.innerWidth;
      const inside = (points, x, y, margin) => {
        const n = points.length / 2;
        let sign = 0;
        for (let i = 0; i < n; i++) {
          const [ax, ay] = [points[2 * i], points[2 * i + 1]];
          const [bx, by] = [points[(2 * i + 2) % (2 * n)], points[(2 * i + 3) % (2 * n)]];
          const len = Math.hypot(bx - ax, by - ay);
          const cross = ((bx - ax) * (y - ay) - (by - ay) * (x - ax)) / len;
          if (Math.abs(cross) < margin) return false;
          const s = Math.sign(cross);
          if (sign === 0) sign = s;
          else if (s !== sign) return false;
        }
        return true;
      };
      const water = window.__water;
      const samples = [];
      const step = Math.max(1, Math.round(k));
      for (let dy = 0; dy < image.height; dy += step) {
        for (let dx = 0; dx < image.width; dx += step) {
          const css = { x: (dx + 0.5) / k, y: (dy + 0.5) / k };
          // The canvas only (a hub's sits between its HUD and its menu), a few pixels in.
          if (css.x < box.x + 4 || css.y < box.y + 4) continue;
          if (css.x > box.x + box.width - 4 || css.y > box.y + box.height - 4) continue;
          const w = {
            x: (css.x - box.x - cam.x) / cam.scale,
            y: (css.y - box.y - cam.y) / cam.scale,
          };
          const over = coords.pixelToTile(w);
          const candidates = (window.__foam.byHex.get(key(over)) ?? []).filter((p) =>
            inside(p.points, w.x, w.y, -1e-6),
          );
          if (candidates.length === 0) continue;
          // Well inside every covering piece, and inside an art pixel of each cell.
          if (!candidates.every((p) => inside(p.points, w.x, w.y, 1.5))) continue;
          const locals = candidates.map((p) => [w.x - p.origin.x, w.y - p.origin.y]);
          const centred = locals.every(([lx, ly]) =>
            [lx, ly].every((v) => v - Math.floor(v) >= 0.25 && v - Math.floor(v) <= 0.75),
          );
          if (!centred) continue;
          const i = 4 * (dy * image.width + dx);
          const seen = [data[i], data[i + 1], data[i + 2]];
          const pixel = (f, [lx, ly]) => {
            const frame = window.__frames[f];
            const j = 4 * (Math.floor(ly) * frame.width + Math.floor(lx));
            return frame.data[j + 3] === 0 ? null : [...frame.data.slice(j, j + 3)];
          };
          // The pieces over one hex are drawn in the plan's order: the last opaque one shows.
          const laws = { "q+r": "q+r", q: "q", r: "r", step: null };
          const matches = {};
          for (const [name, axis] of Object.entries(laws)) {
            matches[name] = Array.from({ length: 16 }, (_, t) => {
              let want = water;
              for (let c = candidates.length - 1; c >= 0; c--) {
                const d = axis ? foam.foamDiagonal(candidates[c].source, axis) : 0;
                const got = pixel((((t + d) % 16) + 16) % 16, locals[c]);
                if (got) {
                  want = got;
                  break;
                }
              }
              return want.slice(0, 3).every((v, ch) => Math.abs(v - seen[ch]) <= TOLERANCE);
            });
          }
          // A sample most clocks explain under the law (water in most) tells little of the phase.
          if (matches["q+r"].filter(Boolean).length > 8) continue;
          samples.push({
            diagonals: candidates.map((p) => foam.foamDiagonal(p.source, "q+r")),
            matches,
          });
        }
      }
      return samples;
    },
    { png, cam, box, TOLERANCE },
  );
}

/** The share of samples a law explains at its best clock, and that clock. */
function fit(samples, law) {
  let best = { share: 0, tick: 0 };
  for (let t = 0; t < 16; t++) {
    const share = samples.filter((s) => s.matches[law][t]).length / samples.length;
    if (share > best.share) best = { share, tick: t };
  }
  return best;
}

/**
 * In the page: the device pixels that differ between two screenshots, and those of them not on or
 * within 1.5 art px of an in-colour foam piece.
 */
async function diffOnFoam(page, a, b, cam, box) {
  return page.evaluate(
    async ({ a, b, cam, box }) => {
      const { coords, key, ground } = window.__geo;
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
      const near = (points, x, y, margin) => {
        const n = points.length / 2;
        for (let i = 0; i < n; i++) {
          const [ax, ay] = [points[2 * i], points[2 * i + 1]];
          const [bx, by] = [points[(2 * i + 2) % (2 * n)], points[(2 * i + 3) % (2 * n)]];
          const len = Math.hypot(bx - ax, by - ay);
          const cross = ((bx - ax) * (y - ay) - (by - ay) * (x - ax)) / len;
          if (cross < -margin) return false;
        }
        return true;
      };
      let differ = 0;
      let off = 0;
      const offAt = [];
      for (let i = 0; i < A.data.length; i += 4) {
        if (
          A.data[i] === B.data[i] &&
          A.data[i + 1] === B.data[i + 1] &&
          A.data[i + 2] === B.data[i + 2]
        )
          continue;
        differ += 1;
        const p = i / 4;
        const css = { x: ((p % A.w) + 0.5) / k, y: (Math.floor(p / A.w) + 0.5) / k };
        const w = {
          x: (css.x - box.x - cam.x) / cam.scale,
          y: (css.y - box.y - cam.y) / cam.scale,
        };
        const hex = coords.pixelToTile(w);
        const hexes = ground.hexesWithin(hex, 1);
        const onFoam = hexes.some((h) =>
          (window.__foam.byHex.get(key(h)) ?? []).some((piece) =>
            near(piece.points, w.x, w.y, 1.5),
          ),
        );
        if (!onFoam) {
          off += 1;
          if (offAt.length < 5) offAt.push(`${css.x.toFixed(0)},${css.y.toFixed(0)}`);
        }
      }
      return { differ, off, offAt };
    },
    { a, b, cam, box },
  );
}

const shot = async (page) => (await page.screenshot()).toString("base64");

const SIZES = [
  ["1440x900", { width: 1440, height: 900 }, false],
  ["375x812", { width: 375, height: 812 }, true],
];

/** Close enough to read art pixels, wide enough to hold several diagonals of foam. */
const ZOOM = { "1440x900": 6, "375x812": 4 };

const url = (place, size, extra = "") =>
  place === "zone"
    ? `${base}/?fixture=zone&idle=0&zoom=${ZOOM[size]}${extra}`
    : `${base}/?hub=${place}&entry=0&idle=0&zoom=${ZOOM[size]}${extra}`;

/** Captures where q + r explained more than either other axis by 10 points or more. */
let axesTold = 0;

async function animated(browser, place, size, viewport, touch) {
  const label = `${place} ${size}`;
  const context = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  await page.goto(url(place, size));
  const room = await opened(page, "atlas");
  const prepared = await prepare(page, place);
  ok(
    prepared.frames === 16 && prepared.pieces > 0,
    `${label}: ${prepared.pieces} foam pieces in colour, ${prepared.frames} frames in the atlas, water ${prepared.water?.slice(0, 3)}`,
  );
  const target = await nearestFoam(page, room);
  if (target) await bringToCentre(page, room, target);
  const cam = await camera(room);
  const box = await canvasBox(room);
  // Two captures about 100 ms apart.
  const a = await shot(page);
  await page.waitForTimeout(100);
  const b = await shot(page);
  ok((await camera(room)).x === cam.x, `${label}: the camera stood still between the captures`);
  const diff = await diffOnFoam(page, a, b, cam, box);
  ok(
    diff.differ > 0 && diff.off === 0,
    `${label}: the captures differ on ${diff.differ} device pixels, ${diff.off} of them off the foam${diff.off ? ` (e.g. ${diff.offAt.join(" ")})` : ""}`,
  );
  await page.screenshot({ path: join(shots, `water-${place}-${size}.png`) });
  // The phase, on both captures.
  for (const [n, png] of [
    ["first", a],
    ["second", b],
  ]) {
    const samples = await samplePhase(page, png, cam, box);
    const laws = Object.fromEntries(["q+r", "q", "r", "step"].map((l) => [l, fit(samples, l)]));
    const diagonals = new Set(samples.flatMap((s) => s.diagonals)).size;
    const others = Math.max(laws.q.share, laws.r.share, laws.step.share);
    console.log(
      `  measure ${label} ${n}: ${samples.length} samples over ${diagonals} diagonals; explained by q+r ${(100 * laws["q+r"].share).toFixed(1)} % (clock ${laws["q+r"].tick}), q ${(100 * laws.q.share).toFixed(1)} %, r ${(100 * laws.r.share).toFixed(1)} %, all in step ${(100 * laws.step.share).toFixed(1)} %`,
    );
    ok(
      samples.length >= 30 && diagonals >= 3,
      `${label} ${n}: enough samples (${samples.length}) over several diagonals (${diagonals})`,
    );
    // Along one row of sources (a hub's straight shore) q and q + r differ by a constant, a clock
    // shift: they cannot be told apart there; the run must tell them apart somewhere (below).
    ok(
      laws["q+r"].share >= LAW_SHARE &&
        laws["q+r"].share >= others &&
        laws["q+r"].share >= laws.step.share + 0.1,
      `${label} ${n}: frame = clock + (q + r) explains ${(100 * laws["q+r"].share).toFixed(1)} % (≥ ${100 * LAW_SHARE} %, ≥ every other law, ≥ all in step + 10 points: ${(100 * laws.step.share).toFixed(1)} %)`,
    );
    if (laws["q+r"].share > Math.max(laws.q.share, laws.r.share) + 0.1) axesTold += 1;
  }
  ok(errors.length === 0, `${label}: no page error`);
  for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  await context.close();
}

/** `?water=still` and the plain look: two captures 100 ms apart are the same. */
async function still(browser, place, size, viewport, touch, look) {
  const label = `${place} ${size} ${look}`;
  const context = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch });
  if (look === "plain") await context.route("**/art/**", (route) => route.fulfill({ status: 404 }));
  const page = await context.newPage();
  await page.goto(url(place, size, look === "still" ? "&water=still" : ""));
  const room = await opened(page, look);
  if (look === "still") {
    await prepare(page, place);
    const target = await nearestFoam(page, room);
    if (target) await bringToCentre(page, room, target);
  }
  const frames = Number(await room.getAttribute("data-frames"));
  const a = await shot(page);
  await page.waitForTimeout(100);
  const b = await shot(page);
  await page.waitForTimeout(1000);
  const after = Number(await room.getAttribute("data-frames"));
  ok(a === b, `${label}: two captures 100 ms apart are the same`);
  ok(after === frames, `${label}: no frame drawn in a second standing still (${after - frames})`);
  await page.screenshot({ path: join(shots, `water-${place}-${size}-${look}.png`) });
  await context.close();
}

// --- the frontier (CLI-03n follow-up) ------------------------------------------------------

/** The zone fixture's rocks (`fixtures/zone.ts`), but on the runts' tiles (as `verify-fog.mjs`). */
const RUNTS = [
  { x: 20, y: 9 },
  { x: 22, y: 9 },
  { x: 21, y: 11 },
];
const rock = (t) =>
  (t.x * 7 + t.y * 11) % 9 === 0 && !RUNTS.some((r) => r.x === t.x && r.y === t.y);

async function stood(page, room) {
  await page.waitForTimeout(80);
  for (let i = 0; i < 200; i += 1) {
    if ((await room.getAttribute("data-walking")) !== "true") return;
    await page.waitForTimeout(50);
  }
}

/** Walks to `target` in hops of at most four tiles, as `verify-fog.mjs` does. */
async function walkTo(page, room, target) {
  for (let i = 0; i < 40; i += 1) {
    const at = await tileOf(room);
    if (at.x === target.x && at.y === target.y) return true;
    const dx = Math.max(-4, Math.min(4, target.x - at.x));
    const dy = Math.max(-2, Math.min(2, target.y - at.y));
    let hop = { x: at.x + dx, y: Math.abs(target.x - at.x) <= 4 ? target.y : at.y + dy };
    if (rock(hop)) hop = { x: hop.x, y: hop.y + 1 };
    const p = await onScreen(room, tileToPixel(hop));
    await page.mouse.click(p.x, p.y);
    await page.waitForTimeout(60);
    await stood(page, room);
    await page.waitForTimeout(350);
  }
  const at = await tileOf(room);
  return at.x === target.x && at.y === target.y;
}

/** Records every tile the hero stands on (`data-tile`). */
function watchTiles() {
  const room = document.querySelector("[data-camera]");
  window.__tiles = [room.getAttribute("data-tile")];
  new MutationObserver(() => window.__tiles.push(room.getAttribute("data-tile"))).observe(room, {
    attributes: true,
    attributeFilter: ["data-tile"],
  });
}

/**
 * In the page: the zone's grounds, the tiles explored by the tiles stood on (their sight) and the
 * tiles in sight now; every side between a land hex seen and a water hex on the screen, as the
 * screen points 1.5 and 12 CSS px inside the land hex along that side (5 each), with what each hex
 * is to the player. `listed` pairs (t-0124's) are described too.
 */
async function frontierFacts(page, hero, listed, cam, box) {
  return page.evaluate(
    async ({ hero, listed, cam, box }) => {
      const fixtures = await import("/src/sandbox/fixtures/index.ts");
      const places = await import("/src/sandbox/placeholders.ts");
      const coords = await import("/src/input/coords.ts");
      const ground = await import("/src/render/ground.ts");
      const { terrain } = fixtures.fixtureNamed("zone");
      const key = (t) => `${t.x},${t.y}`;
      const inside = (t) => t.x >= 0 && t.y >= 0 && t.x < terrain.width && t.y < terrain.height;
      const groundOf = (t) =>
        inside(t) ? (terrain.ground?.[t.y * terrain.width + t.x] ?? "grass") : "void";
      const explored = new Set();
      for (const s of window.__tiles.filter(Boolean)) {
        const [x, y] = s.split(",").map(Number);
        for (const t of places.tilesInSight(terrain, { x, y })) explored.add(key(t));
      }
      const inSight = new Set(places.tilesInSight(terrain, hero).map(key));
      const state = (t) =>
        inSight.has(key(t)) ? "inSight" : explored.has(key(t)) ? "explored" : "unseen";
      const screen = (w) => ({
        x: box.x + cam.x + w.x * cam.scale,
        y: box.y + cam.y + w.y * cam.scale,
      });
      const onCanvas = (p) =>
        p.x > box.x + 20 &&
        p.y > box.y + 20 &&
        p.x < box.x + box.width - 20 &&
        p.y < box.y + box.height - 20;
      const describe = (land, other) => {
        const a = coords.tileToPixel(land);
        const b = coords.tileToPixel(other);
        const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
        const normal = { x: (a.x - mid.x) / 32, y: (a.y - mid.y) / 32 };
        const along = { x: -normal.y, y: normal.x };
        const side = 64 / Math.sqrt(3);
        const point = (t, inward) =>
          screen({
            x: mid.x + along.x * t * side + (normal.x * inward) / cam.scale,
            y: mid.y + along.y * t * side + (normal.y * inward) / cam.scale,
          });
        const ts = [-0.3, -0.15, 0, 0.15, 0.3];
        return {
          land,
          other,
          landGround: groundOf(land),
          otherGround: groundOf(other),
          landState: state(land),
          otherState: state(other),
          edge: ts.map((t) => point(t, 1.5)),
          inner: ts.map((t) => point(t, 12)),
        };
      };
      const sides = [];
      for (let y = 0; y < terrain.height; y++) {
        for (let x = 0; x < terrain.width; x++) {
          const land = { x, y };
          const g = groundOf(land);
          if (g === "water" || state(land) === "unseen") continue;
          if (!onCanvas(screen(coords.tileToPixel(land)))) continue;
          for (let s = 0; s < 6; s++) {
            const other = ground.acrossSide(land, s);
            if (!inside(other)) continue;
            const og = groundOf(other);
            // A side toward water, or toward land never seen (the negative control).
            if (og === "water" || state(other) === "unseen") sides.push(describe(land, other));
          }
        }
      }
      const counts = {
        explored: explored.size,
        inSight: inSight.size,
        stood: window.__tiles.length,
      };
      return { sides, counts, listed: listed.map(([l, o]) => describe(l, o)) };
    },
    { hero, listed, cam, box },
  );
}

async function luminance(page, points, png) {
  return page.evaluate(
    async ({ png, points }) => {
      const image = new Image();
      image.src = `data:image/png;base64,${png}`;
      await image.decode();
      const canvas = document.createElement("canvas");
      canvas.width = image.width;
      canvas.height = image.height;
      const g = canvas.getContext("2d");
      g.drawImage(image, 0, 0);
      const k = image.width / window.innerWidth;
      return points.map((p) => {
        const [r, gr, b] = g.getImageData(Math.floor(p.x * k), Math.floor(p.y * k), 1, 1).data;
        return { l: 0.299 * r + 0.587 * gr + 0.114 * b, hex: [r, gr, b] };
      });
    },
    { png, points },
  );
}

const median = (values) => {
  const s = [...values].sort((a, b) => a - b);
  if (s.length === 0) return NaN;
  return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
};

/** The pairs t-0124 measured on main (land hex → water hex never seen), by the hero's tile. */
const FRONTIER = [
  {
    hero: { x: 36, y: 8 },
    pairs: [
      [
        { x: 33, y: 14 },
        { x: 32, y: 15 },
      ],
      [
        { x: 36, y: 14 },
        { x: 35, y: 15 },
      ],
      [
        { x: 38, y: 14 },
        { x: 37, y: 15 },
      ],
      [
        { x: 36, y: 14 },
        { x: 36, y: 15 },
      ],
    ],
  },
  {
    hero: { x: 40, y: 6 },
    pairs: [
      [
        { x: 41, y: 6 },
        { x: 42, y: 6 },
      ],
      [
        { x: 41, y: 7 },
        { x: 42, y: 7 },
      ],
      [
        { x: 41, y: 9 },
        { x: 42, y: 9 },
      ],
      [
        { x: 41, y: 10 },
        { x: 42, y: 10 },
      ],
    ],
  },
];

let frontierLeaks = 0;

async function frontier(browser) {
  const label = "frontier zone 1440x900";
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  await page.goto(`${base}/?fixture=zone&idle=0&zoom=21&water=still`);
  const room = await opened(page, "atlas");
  await page.evaluate(watchTiles);
  for (const { hero, pairs } of FRONTIER) {
    const walked = await walkTo(page, room, hero);
    ok(walked, `${label}: the hero walked to (${hero.x}, ${hero.y})`);
    if (!walked) continue;
    await page.waitForTimeout(500);
    const cam = await camera(room);
    const box = await canvasBox(room);
    const { sides, listed, counts } = await frontierFacts(page, hero, pairs, cam, box);
    console.log(`  note ${label}: ${JSON.stringify(counts)}, ${sides.length} sides`);
    await page.screenshot({ path: join(shots, `frontier-${hero.x}-${hero.y}.png`) });
    const png = await shot(page);
    const drop = async (f) => {
      const edge = await luminance(page, f.edge, png);
      const inner = await luminance(page, f.inner, png);
      return {
        drop: median(inner.map((p) => p.l)) - median(edge.map((p) => p.l)),
        edge: edge[2].hex,
      };
    };
    for (const f of listed) {
      const d = await drop(f);
      console.log(
        `  measure ${label} at (${hero.x}, ${hero.y}): t-0124's (${f.land.x}, ${f.land.y}) → (${f.other.x}, ${f.other.y}): land ${f.landState}, ${f.otherGround} ${f.otherState}; drop ${d.drop.toFixed(1)} (edge ${d.edge})`,
      );
    }
    const groups = {};
    for (const f of sides) {
      const kind =
        f.otherGround === "water"
          ? `toward water ${f.otherState === "unseen" ? "never seen" : "seen"}`
          : "toward land never seen";
      const look = f.landState === "inSight" ? "colour" : "grey";
      const group = `${kind}, ${look}`;
      (groups[group] ??= []).push((await drop(f)).drop);
    }
    for (const [group, drops] of Object.entries(groups)) {
      console.log(
        `  measure ${label} at (${hero.x}, ${hero.y}): ${group}: ${drops.length} sides, median drop ${median(drops).toFixed(1)} (min ${Math.min(...drops).toFixed(1)}, max ${Math.max(...drops).toFixed(1)})`,
      );
    }
    for (const look of ["colour", "grey"]) {
      const leak = groups[`toward water never seen, ${look}`];
      const control = groups[`toward water seen, ${look}`];
      if (leak) {
        ok(
          Math.max(...leak) <= NO_LIP,
          `${label} at (${hero.x}, ${hero.y}), ${look}: no lip toward water never seen (${leak.length} sides, max drop ${Math.max(...leak).toFixed(1)} ≤ ${NO_LIP})`,
        );
      }
      if (control) {
        ok(
          median(control) >= LIP_DROP[look],
          `${label} at (${hero.x}, ${hero.y}), ${look}: the lip toward seen water stays (${control.length} sides, median drop ${median(control).toFixed(1)} ≥ ${LIP_DROP[look]})`,
        );
      }
    }
    frontierLeaks += groups["toward water never seen, colour"]?.length ?? 0;
    frontierLeaks += groups["toward water never seen, grey"]?.length ?? 0;
  }
  ok(frontierLeaks > 0, `${label}: ${frontierLeaks} sides toward water never seen were sampled`);
  ok(errors.length === 0, `${label}: no page error`);
  for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  await context.close();
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}`);
  for (const place of places) {
    for (const [size, viewport, touch] of SIZES) {
      console.log(`=== ${place} ${size} ===`);
      await animated(browser, place, size, viewport, touch);
      await still(browser, place, size, viewport, touch, "still");
      await still(browser, place, size, viewport, touch, "plain");
    }
  }
  if (places.length > 0) {
    ok(axesTold > 0, `the axis q + r told apart from q and r on ${axesTold} captures`);
  }
  if (process.env.VERIFY_FRONTIER !== "0") {
    console.log("=== frontier ===");
    await frontier(browser);
  }
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
