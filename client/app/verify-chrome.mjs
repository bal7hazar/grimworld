/* global console, process, fetch, setTimeout, document, window, getComputedStyle, requestAnimationFrame */
/* eslint-disable no-empty */
// The client's chrome in a real browser (CLI-03i): every screen of the loop at 375 × 812 (touch)
// and 1440 × 900, each at device pixel ratios 1, 2 and 3, with the atlas built by
// `tools/art/build.py` (never committed, D-73). Run by hand, not by CI:
// `pnpm --filter @grimworld/app verify:chrome`. Starts the dev server as its own process group and
// sends SIGTERM to that recorded group in `finally`.
//
// Screens: the town and the outpost, one service stub, the Gate screen, the entry moment (a long
// `?entry=`), the instance, its confirmation dialog, the closing report (returned and defeated);
// at 1440 the desktop's side panels are on every screen. On each (AC-6): `data-chrome="atlas"`;
// every button at least 44 × 44 CSS px; nothing overflows the viewport horizontally (the place
// names, which follow the camera, apart); no label clipped (`scrollWidth ≤ clientWidth` on every
// plate and button); Tab reaches every button and shows the focus outline; a pointer-down on a
// blue or red button swaps its image (`border-image-source`) and moves its label by the drop;
// no page error. Then (AC-9) the hub and the confirmation with `forcedColors: "active"`: every
// control keeps a border and its text.
//
// Modes. VERIFY_MAIN=1: a checkout without the chrome (`origin/main`, VERIFY_ROOT): only the boxes
// are recorded. VERIFY_PLAIN=1: no art (`GRIMWORLD_ART_OUT` on an empty folder): every screen
// must say `data-chrome="plain"` (AC-8). VERIFY_BOXES_OUT: the boxes (map, header, service row,
// side panels, each button, per screen, size and ratio) as JSON. VERIFY_COMPARE: such a file from
// `main`: with the art, the map's box is the same or larger and no button left the viewport or
// lies under another (AC-7); plain, every box within 1 px (AC-8). VERIFY_SHOTS=1: shots of every
// screen at both sizes at ratio 2 and of the town at 1 and 3, into VERIFY_SHOTS_DIR (default the
// untracked `.verify-out/`; D-73: never committed, attached or posted).
//
// Env: VERIFY_PORT (default 5199), VERIFY_CHANNEL, VERIFY_ROOT (the checkout whose dev server
// runs; default this one), VERIFY_MAIN, VERIFY_PLAIN, VERIFY_BOXES_OUT, VERIFY_COMPARE,
// VERIFY_SHOTS, VERIFY_SHOTS_DIR. The server inherits GRIMWORLD_ART_OUT.
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5199);
const base = `http://127.0.0.1:${port}`;
const root = process.env.VERIFY_ROOT ?? join(here, "..", "..");
const mainOnly = process.env.VERIFY_MAIN === "1";
const plain = process.env.VERIFY_PLAIN === "1";
const compare = process.env.VERIFY_COMPARE
  ? JSON.parse(readFileSync(process.env.VERIFY_COMPARE, "utf8"))
  : null;
const shots = process.env.VERIFY_SHOTS
  ? (process.env.VERIFY_SHOTS_DIR ?? join(here, ".verify-out"))
  : null;
if (shots) mkdirSync(shots, { recursive: true });
const SIZES = [
  { name: "375x812", viewport: { width: 375, height: 812 }, touch: true },
  { name: "1440x900", viewport: { width: 1440, height: 900 }, touch: false },
];
const RATIOS = [1, 2, 3];
const LONG_ENTRY = 10000; // the longest `?entry=` (params.ts ENTRY_RANGE)

let failures = 0;
const notes = [];
function ok(condition, message) {
  if (!condition) console.log(`  FAIL ${message}`);
  if (!condition) failures += 1;
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

const screenOf = (page, name) => page.locator(`[data-screen="${name}"]`).first();

/** Waits for the screen, its map's atlas when it has a map, and the chrome's mode. */
async function settle(page, name) {
  await screenOf(page, name).waitFor();
  if (name === "hub" || name === "instance") {
    await page.locator('[data-atlas]:not([data-atlas="loading"])').first().waitFor();
  }
  if (!mainOnly) {
    await page
      .waitForFunction(
        (want) => document.querySelector("[data-chrome]")?.getAttribute("data-chrome") === want,
        plain ? "plain" : "atlas",
        { timeout: 10000 },
      )
      .catch(() => {});
  }
  // Two frames: the place names are placed after a frame of the map.
  await page.evaluate(
    () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))),
  );
}

/** The boxes and facts of the screen as it stands, measured in the page. */
function measure() {
  const box = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return [r.x, r.y, r.width, r.height].map((v) => Math.round(v * 100) / 100);
  };
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== "hidden" && s.display !== "none";
  };
  const nameOf = (el) => (el.getAttribute("aria-label") || el.textContent || "").trim();
  const buttons = [...document.querySelectorAll("button, a[href]")].filter(visible);
  const width = window.innerWidth;
  const overflow = [];
  for (const el of document.querySelectorAll("body *")) {
    if (!visible(el) || el.closest("[data-label]") || el.tagName === "CANVAS") continue;
    const r = el.getBoundingClientRect();
    if (r.right > width + 0.5 || r.left < -0.5) {
      overflow.push(`${el.tagName.toLowerCase()}.${el.className || ""} ${box(el)}`);
    }
  }
  const clipped = [...document.querySelectorAll("button, .gw-ribbon, [data-label]")]
    .filter(visible)
    .filter((el) => el.scrollWidth > el.clientWidth + 0.5)
    .map((el) => `${nameOf(el)} (${el.scrollWidth} > ${el.clientWidth})`);
  const map = document.querySelector("[data-screen] [data-camera]");
  const asides = [...document.querySelectorAll("aside")];
  return {
    chrome: document.querySelector("[data-chrome]")?.getAttribute("data-chrome") ?? null,
    dpr: document.querySelector("[data-chrome]")?.getAttribute("data-chrome-dpr") ?? null,
    boxes: {
      map: box(map),
      header: box(document.querySelector("[data-screen] header, header")),
      nav: box(document.querySelector('nav[aria-label="Services"]')),
      "aside-left": box(asides[0]),
      "aside-right": box(asides[1]),
      ...Object.fromEntries(buttons.map((el) => [`button:${nameOf(el)}`, box(el)])),
    },
    small: buttons
      .filter((el) => {
        const r = el.getBoundingClientRect();
        return r.width < 44 - 0.01 || r.height < 44 - 0.01;
      })
      .map((el) => `${nameOf(el)} ${box(el)}`),
    overflow,
    clipped,
    scrollWidth: document.documentElement.scrollWidth,
    width,
    buttons: buttons.map(nameOf),
  };
}

/** Tab through the page: every button reached, each with a visible outline when focused. */
async function tabbing(page, names) {
  await page.evaluate(() => document.activeElement?.blur?.());
  await page.mouse.click(1, 1).catch(() => {});
  const reached = new Map();
  for (let i = 0; i < names.length + 12; i += 1) {
    await page.keyboard.press("Tab");
    const info = await page.evaluate(() => {
      const el = document.activeElement;
      if (!el || el === document.body) return null;
      const s = getComputedStyle(el);
      return {
        name: (el.getAttribute("aria-label") || el.textContent || "").trim(),
        outline: s.outlineStyle !== "none" && parseFloat(s.outlineWidth) >= 3,
      };
    });
    if (info && !reached.has(info.name)) reached.set(info.name, info.outline);
  }
  return reached;
}

/** A pointer-down on a blue or red button: its image and its label's position, before and during. */
async function pressing(page) {
  const target = page.locator(".gw-button-action:not(:disabled), .gw-button-commit").first();
  if ((await target.count()) === 0) return null;
  const read = () =>
    target.evaluate((el) => ({
      image: getComputedStyle(el).borderImageSource,
      label: el.querySelector(".gw-label").getBoundingClientRect().top,
      drop: parseFloat(getComputedStyle(el).getPropertyValue("--drop")),
      name: (el.getAttribute("aria-label") || el.textContent || "").trim(),
    }));
  const before = await read();
  const b = await target.boundingBox();
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
  await page.mouse.down();
  const during = await read();
  // Leave the button before releasing: no click, the screen stays.
  await page.mouse.move(1, 1);
  await page.mouse.up();
  return { before, during };
}

/** The screens of one pass, in order: [name, how to reach it]. */
function screens() {
  const click = (page, name, scope) =>
    (scope ? page.locator(scope) : page).getByRole("button", { name, exact: true }).first().click();
  const leaveTown = async (page) => {
    await page.locator('nav[aria-label="Services"]').getByRole("button", { name: /^Gate/ }).click();
    await screenOf(page, "gate").waitFor();
    await page
      .getByRole("button", { name: /^Leave by gate/ })
      .first()
      .click();
  };
  return [
    ["town", "hub", (page) => page.goto(`${base}/?hub=town&entry=${LONG_ENTRY}`)],
    ["service", "service", (page) => click(page, "Vault", 'nav[aria-label="Services"]')],
    [
      "gate",
      "gate",
      async (page) => {
        await click(page, "Back");
        await screenOf(page, "hub").waitFor();
        await page
          .locator('nav[aria-label="Services"]')
          .getByRole("button", { name: /^Gate/ })
          .click();
      },
    ],
    [
      "entry",
      "entry",
      (page) =>
        page
          .getByRole("button", { name: /^Leave by gate/ })
          .first()
          .click(),
    ],
    [
      "instance",
      "instance",
      async (page) => {
        // The entry may have completed while it was measured.
        const skip = page.getByRole("button", { name: "Skip ▸", exact: true });
        if (await skip.count()) await skip.click().catch(() => {});
      },
    ],
    ["confirm", "instance", (page) => click(page, "Travel back")],
    [
      "report-returned",
      "report",
      (page) =>
        page
          .getByRole("dialog", { name: "Confirm" })
          .getByRole("button", { name: "Travel back" })
          .click(),
    ],
    [
      "report-defeated",
      "report",
      async (page) => {
        await page.getByRole("button", { name: /^On to/ }).click();
        await screenOf(page, "hub").waitFor();
        await leaveTown(page);
        await click(page, "Skip ▸");
        await screenOf(page, "instance").waitFor();
        await page.getByRole("button", { name: /debug: defeat now/ }).click();
      },
    ],
    ["outpost", "hub", (page) => page.goto(`${base}/?hub=outpost&entry=${LONG_ENTRY}`)],
  ];
}

const record = {};

async function pass(browser, size, dpr) {
  const label = `${size.name}@${dpr}x`;
  const context = await browser.newContext({
    viewport: size.viewport,
    deviceScaleFactor: dpr,
    hasTouch: size.touch,
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e.stack ?? e)));
  const facts = { pressed: 0, tabbed: 0 };
  for (const [name, screen, reach] of screens()) {
    await reach(page);
    await settle(page, screen);
    if (name === "confirm") await page.getByRole("dialog", { name: "Confirm" }).waitFor();
    if (name.startsWith("report")) {
      const outcome = await screenOf(page, "report").getAttribute("data-outcome");
      ok(outcome === name.slice("report-".length), `${label} ${name}: outcome ${outcome}`);
    }
    const m = await page.evaluate(measure);
    record[`${label} ${name}`] = m.boxes;
    if (shots && (dpr === 2 || name === "town")) {
      await page.screenshot({ path: join(shots, `chrome-${name}-${label}.png`) });
    }
    if (mainOnly) continue;
    const where = `${label} ${name}`;
    ok(m.chrome === (plain ? "plain" : "atlas"), `${where}: data-chrome ${m.chrome}`);
    if (!plain) ok(Number(m.dpr) === dpr, `${where}: data-chrome-dpr ${m.dpr}`);
    ok(m.small.length === 0, `${where}: buttons under 44 px: ${m.small.join("; ")}`);
    ok(
      m.overflow.length === 0 && m.scrollWidth <= m.width,
      `${where}: horizontal overflow (${m.scrollWidth} > ${m.width}): ${m.overflow.slice(0, 4).join("; ")}`,
    );
    ok(m.clipped.length === 0, `${where}: clipped labels: ${m.clipped.join("; ")}`);
    if (plain) continue;
    if (name !== "confirm") {
      const reached = await tabbing(page, m.buttons);
      const missing = m.buttons.filter((n) => !reached.has(n));
      const bare = [...reached].filter(([, outline]) => !outline).map(([n]) => n);
      ok(missing.length === 0, `${where}: Tab never reaches ${missing.join(", ")}`);
      ok(bare.length === 0, `${where}: no focus outline on ${bare.join(", ")}`);
      facts.tabbed += reached.size;
    }
    const press = name === "confirm" ? null : await pressing(page);
    if (press) {
      const moved = press.during.label - press.before.label;
      ok(
        press.during.image !== press.before.image,
        `${where}: pressing ${press.before.name} swaps its image`,
      );
      ok(
        // Within a layout unit (1/64 CSS px): Chromium snaps positions to it.
        Math.abs(moved - press.before.drop) <= 1 / 64 + 1e-6 && press.before.drop > 0,
        `${where}: pressing ${press.before.name} moves its label by the drop (${moved} vs ${press.before.drop})`,
      );
      facts.pressed += 1;
    }
  }
  ok(errors.length === 0, `${label}: no page error`);
  for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  console.log(
    `  ${label}: ${screens().length} screens measured` +
      (mainOnly || plain ? "" : `, ${facts.tabbed} focus stops, ${facts.pressed} presses`),
  );
  await context.close();
}

/** AC-9: the hub and the confirmation in forced colours: every control has a border and text. */
async function forced(browser) {
  const context = await browser.newContext({
    viewport: { width: 375, height: 812 },
    deviceScaleFactor: 2,
    forcedColors: "active",
  });
  const page = await context.newPage();
  const check = async (where) => {
    const controls = await page.evaluate(() =>
      [...document.querySelectorAll("button")]
        .filter((el) => el.getBoundingClientRect().width > 0)
        .map((el) => {
          const s = getComputedStyle(el);
          return {
            name: (el.getAttribute("aria-label") || el.textContent || "").trim(),
            border: parseFloat(s.borderTopWidth) > 0 && s.borderTopStyle !== "none",
            image: s.borderImageSource,
            text: s.color !== s.backgroundColor,
          };
        }),
    );
    for (const c of controls) {
      ok(
        c.border && c.image === "none" && c.text,
        `forced colours ${where}: ${c.name} ${JSON.stringify(c)}`,
      );
    }
    console.log(`  forced colours ${where}: ${controls.length} controls`);
  };
  await page.goto(`${base}/?hub=town&entry=0`);
  await settle(page, "hub");
  await check("hub");
  await page.locator('nav[aria-label="Services"]').getByRole("button", { name: /^Gate/ }).click();
  await page
    .getByRole("button", { name: /^Leave by gate/ })
    .first()
    .click();
  await settle(page, "instance");
  await page.getByRole("button", { name: "Travel back", exact: true }).click();
  await page.getByRole("dialog", { name: "Confirm" }).waitFor();
  await check("confirm");
  await context.close();
}

/** AC-7 and AC-8: this run's boxes against `main`'s. */
function compareBoxes() {
  const overlap = (a, b) =>
    a[0] < b[0] + b[2] - 0.5 &&
    b[0] < a[0] + a[2] - 0.5 &&
    a[1] < b[1] + b[3] - 0.5 &&
    b[1] < a[1] + a[3] - 0.5;
  for (const [where, boxes] of Object.entries(record)) {
    const was = compare[where];
    if (!ok(was, `${where}: no box of main to compare`)) continue;
    if (plain) {
      for (const [key, b] of Object.entries(was)) {
        const now = boxes[key];
        const same =
          (b === null && now == null) || (b && now && b.every((v, i) => Math.abs(v - now[i]) <= 1));
        if (!same)
          notes.push(`${where} ${key}: main ${JSON.stringify(b)}, now ${JSON.stringify(now)}`);
        ok(same || key === "button:debug", `${where} ${key}: within 1 px of main`);
      }
      continue;
    }
    const map = boxes.map;
    if (was.map) {
      ok(
        map && map[2] >= was.map[2] - 0.01 && map[3] >= was.map[3] - 0.01,
        `${where}: the map's box ${JSON.stringify(map)} is not smaller than main's ${JSON.stringify(was.map)}`,
      );
    }
    for (const [key, b] of Object.entries(boxes)) {
      if (!key.startsWith("button:") || !b) continue;
      const inside = b[0] >= -0.5 && b[1] >= -0.5 && b[0] + b[2] <= 1440.5;
      ok(inside, `${where} ${key}: inside the viewport`);
      for (const [other, c] of Object.entries(boxes)) {
        if (other <= key || !other.startsWith("button:") || !c) continue;
        ok(!overlap(b, c), `${where}: ${key} and ${other} do not overlap`);
      }
      const old = was[key];
      if (
        old &&
        (Math.abs(old[2] - b[2]) > 1 ||
          Math.abs(old[3] - b[3]) > 1 ||
          Math.abs(old[0] - b[0]) > 1 ||
          Math.abs(old[1] - b[1]) > 1)
      ) {
        notes.push(`${where} ${key}: main ${JSON.stringify(old)}, now ${JSON.stringify(b)}`);
      }
    }
    for (const key of ["header", "nav"]) {
      if (JSON.stringify(was[key]) !== JSON.stringify(boxes[key])) {
        notes.push(
          `${where} ${key}: main ${JSON.stringify(was[key])}, now ${JSON.stringify(boxes[key])}`,
        );
      }
    }
  }
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}`);
  for (const size of SIZES) {
    for (const dpr of RATIOS) await pass(browser, size, dpr);
  }
  if (!mainOnly && !plain) await forced(browser);
  if (process.env.VERIFY_BOXES_OUT) {
    writeFileSync(process.env.VERIFY_BOXES_OUT, JSON.stringify(record, null, 1) + "\n");
    console.log(`boxes written to ${process.env.VERIFY_BOXES_OUT}`);
  }
  if (compare) compareBoxes();
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
if (notes.length) {
  console.log(`differences from main (${notes.length}):`);
  for (const n of notes) console.log(`  ${n}`);
}
console.log(failures === 0 ? "ALL CHECKS PASSED" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
