/* global console, process, fetch, setTimeout, document, window, getComputedStyle */
/* eslint-disable no-empty */
// The combat screen in a real browser (CLI-05c, CLI-05 brief §10): the sandbox's fixed fight
// (`?combat=fight`, `?combat=activating`) at 1440 × 900 (mouse, the desktop's three columns) and
// 375 × 812 (touch, the phone's), with the atlas `tools/art/build.py` built (never committed,
// D-73) or, with `--plain`, with no art served (`/art/` answers 404 in the browser). Run by hand,
// not by CI:
//
//   pnpm --filter @grimworld/app verify:combat --shots <folder>
//   pnpm --filter @grimworld/app verify:combat --shots <folder> --plain
//
// Starts the dev server as its own process group and sends SIGTERM to that recorded group in
// `finally`. Options are arguments: `--shots <folder>` writes the shots there (never committed,
// attached or posted: D-73), `--plain` serves no art, `--port <n>` (default 5199).
//
// On each size (§10's acceptance): the bar shows each state of §2.2 (at rest: wrong weapon,
// recharging, ready, short of adrenaline, short of energy and three empty; activating: the
// activating slot and the others not now), the belt §3's three kinds of slot (counts 3 and 1, an
// emptied slot at 0, a slot with no item), the status band Wren's three chips, the log its lines
// (the desktop's panel, the phone's last line); a tap on the hobgoblin shows its activation in the
// target zone; a tap on a slot not ready says its line and arms nothing; a key (desktop) or a tap
// (phone) arms Charge, `Esc` disarms it; a potion addressed to Wren plays on the second tap (its
// count drops by one and the log says so). Every slot is at least 44 CSS px; nothing passes the
// viewport's sides; no page error. The shots: the screen at rest (the hobgoblin selected), a slot
// armed on a FOE skill (Charge), and Wren activating Charge; and the rest at the lowest zoom
// (`far`), where the ring's digit must stay readable.
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");

/** `--shots <folder>`, `--plain`, `--port <n>`: arguments, not variables (the brief's form). */
function readArgs(argv) {
  const out = { shots: null, plain: false, port: 5199 };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--plain") out.plain = true;
    else if (arg === "--shots")
      out.shots = resolve(process.env.INIT_CWD ?? process.cwd(), argv[++i]);
    else if (arg === "--port") out.port = Number(argv[++i]);
    else if (arg !== "--") throw new Error(`unknown argument ${arg}`);
  }
  return out;
}

const args = readArgs(process.argv.slice(2));
const base = `http://127.0.0.1:${args.port}`;
if (args.shots) mkdirSync(args.shots, { recursive: true });
const look = args.plain ? "plain" : "atlas";

const SIZES = [
  { name: "1440x900", viewport: { width: 1440, height: 900 }, touch: false, desktop: true },
  { name: "375x812", viewport: { width: 375, height: 812 }, touch: true, desktop: false },
];
const BAR_REST = [
  "wrong-weapon",
  "recharging",
  "ready",
  "short-adrenaline",
  "short-energy",
  "empty",
  "empty",
  "empty",
];
const BAR_ACTIVATING = [
  "not-now",
  "not-now",
  "activating",
  "not-now",
  "not-now",
  "empty",
  "empty",
  "empty",
];
const BELT = ["some", "some", "none-left", "empty"];
/** The hobgoblin beside Wren (combat/fixture.ts). */
const HOBGOBLIN = { x: 24, y: 7 };

let failures = 0;
function ok(condition, message) {
  if (!condition) {
    console.log(`  FAIL ${message}`);
    failures += 1;
  }
  return condition;
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
    String(args.port),
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

const ROW_HEIGHT = (64 / Math.sqrt(3)) * 1.5;
const tileToPixel = (t) => ({ x: -(t.x + (t.y & 1) / 2) * 64, y: -t.y * ROW_HEIGHT });

async function tapHex(page, tile) {
  const room = page.locator('[data-screen="instance"] [data-camera]').first();
  const [x, y, scale] = (await room.getAttribute("data-camera")).split(" ").map(Number);
  const box = await room.boundingBox();
  const p = tileToPixel(tile);
  await page.mouse.click(box.x + x + p.x * scale, box.y + y + p.y * scale);
}

const frames = (page) =>
  page.evaluate(
    () => new Promise((r) => window.requestAnimationFrame(() => window.requestAnimationFrame(r))),
  );

/** Opens the fight and waits for its look and its map. */
async function open(page, which) {
  await page.goto(`${base}/?combat=${which}&idle=0`);
  await page.locator('[data-screen="instance"] [data-skill-bar]').waitFor();
  await page
    .waitForFunction(
      (want) => document.querySelector("[data-chrome]")?.getAttribute("data-chrome") === want,
      look,
      { timeout: 10_000 },
    )
    .catch(() => {});
  await page
    .locator(
      args.plain
        ? '[data-screen="instance"] canvas'
        : '[data-screen="instance"] [data-atlas]:not([data-atlas="loading"])',
    )
    .first()
    .waitFor();
  await page.locator('[data-screen="instance"] [data-camera]').first().waitFor();
  await frames(page);
  await page.waitForTimeout(200);
}

/** What the screen shows, read in the page. */
function measure() {
  const box = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return [r.x, r.y, r.width, r.height].map((v) => Math.round(v * 100) / 100);
  };
  const slots = [...document.querySelectorAll("[data-slot]")];
  const belt = [...document.querySelectorAll("[data-belt-slot]")];
  const width = window.innerWidth;
  const overflow = [];
  for (const el of document.querySelectorAll("body *")) {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    if (r.width === 0 || s.visibility === "hidden" || s.display === "none") continue;
    if (el.closest("[data-label]") || el.tagName === "CANVAS") continue;
    if (r.right > width + 0.5 || r.left < -0.5) overflow.push(el.tagName.toLowerCase());
  }
  const band = document.querySelector('section[aria-label="Status"]');
  return {
    chrome: document.querySelector("[data-chrome]")?.getAttribute("data-chrome"),
    layout: document.querySelector("[data-layout]")?.getAttribute("data-layout"),
    bar: slots.map((s) => s.getAttribute("data-state")),
    armed: slots.map((s) => s.getAttribute("aria-pressed") === "true"),
    slotArt: [...new Set([...slots, ...belt].map((s) => s.getAttribute("data-slot-art")))],
    belt: belt.map((s) => s.getAttribute("data-state")),
    counts: belt.map((s) => s.querySelector("[data-count]")?.getAttribute("data-count") ?? null),
    sizes: [...slots, ...belt].map((s) => box(s)),
    chips: [...(band?.querySelectorAll("[data-chip]") ?? [])].map((c) =>
      c.getAttribute("aria-label"),
    ),
    target: document.querySelector('section[aria-label="Target"]')?.getAttribute("data-target"),
    targetBox: box(document.querySelector('section[aria-label="Target"]')),
    activation: document.querySelector("[data-activation]")?.textContent ?? null,
    said: document.querySelector("[data-said]")?.textContent ?? "",
    panelLines: [...document.querySelectorAll('[data-combat-log="panel"] li')].map(
      (l) => l.textContent,
    ),
    lastLine: document.querySelector('[data-combat-log="line"]')?.textContent ?? null,
    overflow,
  };
}

async function shot(page, name, size) {
  if (!args.shots) return;
  const path = join(args.shots, `combat-${name}-${size.name}${args.plain ? "-plain" : ""}.png`);
  await page.screenshot({ path });
  console.log(`  shot ${path}`);
}

async function pass(browser, size) {
  const context = await browser.newContext({
    viewport: size.viewport,
    deviceScaleFactor: 2,
    hasTouch: size.touch,
    isMobile: size.touch,
  });
  if (args.plain) await context.route("**/art/**", (route) => route.fulfill({ status: 404 }));
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  const label = size.name;

  // At rest, the hobgoblin selected: every state of the bar, the belt, the chips, the log.
  await open(page, "fight");
  let m = await page.evaluate(measure);
  ok(m.chrome === look, `${label}: data-chrome ${m.chrome}, want ${look}`);
  ok(m.layout === (size.desktop ? "desktop" : "phone"), `${label}: layout ${m.layout}`);
  ok(JSON.stringify(m.bar) === JSON.stringify(BAR_REST), `${label}: the bar ${m.bar}`);
  ok(JSON.stringify(m.belt) === JSON.stringify(BELT), `${label}: the belt ${m.belt}`);
  ok(JSON.stringify(m.counts) === JSON.stringify(["3", "1", "0", null]), `${label}: ${m.counts}`);
  ok(m.chips.length === 3 && m.chips[0] === "Bleeding, 4 ticks left", `${label}: ${m.chips}`);
  ok(
    m.sizes.every((b) => b[2] >= 44 && b[3] >= 44),
    `${label}: every slot at least 44 px (${m.sizes.map((b) => b[2])})`,
  );
  ok(m.overflow.length === 0, `${label}: nothing past the sides (${m.overflow.slice(0, 3)})`);
  if (size.desktop) ok(m.panelLines.length === 15, `${label}: ${m.panelLines.length} log lines`);
  else ok(m.lastLine?.includes("Not enough energy."), `${label}: the last line ${m.lastLine}`);
  console.log(`  ${label}: slots drawn ${m.slotArt.join("/")}`);
  ok(m.target === "", `${label}: the target zone empty before a selection`);
  const zoneBefore = m.targetBox;
  await tapHex(page, HOBGOBLIN);
  await page.locator('section[aria-label="Target"][data-target="8"]').waitFor({ timeout: 5000 });
  m = await page.evaluate(measure);
  ok(
    m.activation === "Overhead Smash — 2 ticks, on you",
    `${label}: the hobgoblin's activation ${m.activation}`,
  );
  ok(
    JSON.stringify(m.targetBox) === JSON.stringify(zoneBefore),
    `${label}: the target zone keeps its box (${zoneBefore} → ${m.targetBox})`,
  );
  await frames(page);
  await shot(page, "rest", size);

  // The lowest zoom (the most tiles across): zoomed out by its key until the scale stops moving,
  // the hobgoblin's ring and its digit drawn there (review t-0260, note 3).
  const scaleOf = async () =>
    Number(
      (
        await page
          .locator('[data-screen="instance"] [data-camera]')
          .first()
          .getAttribute("data-camera")
      ).split(" ")[2],
    );
  let scale = await scaleOf();
  for (let i = 0; i < 40; i += 1) {
    await page.keyboard.press("Minus");
    await page.waitForTimeout(60);
    const next = await scaleOf();
    if (Math.abs(next - scale) < 1e-9) break;
    scale = next;
  }
  await page.waitForTimeout(400);
  await frames(page);
  console.log(`  ${label}: lowest zoom, ${scale.toFixed(3)} CSS px per art px`);
  await shot(page, "far", size);
  if (args.shots) {
    // The ring and its digit at that zoom, cropped around the hobgoblin, at the screen's own pixels.
    const room = page.locator('[data-screen="instance"] [data-camera]').first();
    const [x, y, k] = (await room.getAttribute("data-camera")).split(" ").map(Number);
    const box = await room.boundingBox();
    const p = tileToPixel(HOBGOBLIN);
    const cx = box.x + x + p.x * k;
    const cy = box.y + y + p.y * k;
    const path = join(args.shots, `combat-far-ring-${size.name}${args.plain ? "-plain" : ""}.png`);
    await page.screenshot({ path, clip: { x: cx - 60, y: cy - 60, width: 120, height: 120 } });
    console.log(`  shot ${path}`);
  }
  // Back to the default zoom, the hobgoblin selected again.
  await open(page, "fight");
  await tapHex(page, HOBGOBLIN);
  await page.locator('section[aria-label="Target"][data-target="8"]').waitFor({ timeout: 5000 });

  // A slot not ready says its line and arms nothing.
  await page.locator('[data-slot="1"]').click();
  m = await page.evaluate(measure);
  ok(m.said === "Recharging: 3 ticks.", `${label}: ${m.said}`);
  ok(!m.armed.some(Boolean), `${label}: nothing armed`);
  // The refused slot keeps no focus ring in the next shot (it would read as a second armed slot).
  await page.evaluate(() => document.activeElement?.blur?.());

  // Charge armed (a FOE skill): by its key on desktop, by a tap on the phone.
  if (size.desktop) await page.keyboard.press("3");
  else await page.locator('[data-slot="2"]').click();
  m = await page.evaluate(measure);
  ok(m.armed[2] === true, `${label}: Charge armed by ${size.desktop ? "its key" : "a tap"}`);
  await frames(page);
  await shot(page, "armed", size);
  await page.keyboard.press("Escape");
  m = await page.evaluate(measure);
  ok(!m.armed.some(Boolean), `${label}: Esc disarms`);

  // A potion addressed to Wren plays on the second tap.
  await page.locator('[data-belt-slot="0"]').click();
  await page.locator('[data-belt-slot="0"]').click();
  m = await page.evaluate(measure);
  ok(m.counts[0] === "2", `${label}: the healing potion's count ${m.counts[0]}`);
  const last = size.desktop ? m.panelLines.at(-1) : m.lastLine;
  ok(last?.includes("You drank a Healing potion"), `${label}: the log's last line ${last}`);

  // Wren activating Charge: the activating slot, the rest not now.
  await open(page, "activating");
  m = await page.evaluate(measure);
  ok(JSON.stringify(m.bar) === JSON.stringify(BAR_ACTIVATING), `${label}: activating ${m.bar}`);
  ok(
    m.belt.slice(0, 2).every((s) => s === "not-now"),
    `${label}: the belt not now while activating`,
  );
  await shot(page, "activating", size);

  ok(errors.length === 0, `${label}: no page error`);
  for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  await context.close();
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()} (${look})`);
  for (const size of SIZES) {
    console.log(`=== ${size.name} ===`);
    await pass(browser, size);
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
