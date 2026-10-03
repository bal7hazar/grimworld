/* global console, process, fetch, setTimeout, window, document, getComputedStyle */
/* eslint-disable no-empty */
// CLI-03k's keyboard in a real browser, keyboard only (no mouse, no tap) at 1440 × 900, idle
// animations off: a zone (the six keys, the arrows, F and Enter to the hub gate, CLI-03d's offer,
// L and the I-5 dialog with Stay focused, leaving by L, Tab, Enter), the town and the outpost (a
// step, F / Shift+F in the service row's order, Enter to a door, Esc, a digit, the Gate), the
// camera (+, −, 0), the key help (?), the browser's own keys left alone, a text field's keys left
// to it, the focus after each screen change and the ring on every Tab stop. Then AC-7 at
// 375 × 812 with touch: CLI-03f's taps give the same screens and tiles as `main`, and the phone
// layout's buttons are `main`'s. Run by hand: `pnpm --filter @grimworld/app verify:keys`.
//
// Starts the dev server as its own process group and sends SIGTERM to that recorded group in
// `finally`. Shots only with VERIFY_SHOTS=1, into VERIFY_SHOTS_DIR or the untracked `.verify-out/`
// (D-73: never committed). VERIFY_ONLY=phone runs the 375 px pass alone; VERIFY_PHONE_OUT=<file>
// writes its record, VERIFY_PHONE_BASE=<file> compares it with a record made on `main`.
// Env as `verify:hubs`: VERIFY_PORT (default 5198), VERIFY_CHANNEL.
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5198);
const base = `http://127.0.0.1:${port}`;
const only = process.env.VERIFY_ONLY ?? "";
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
  { cwd: join(here, "..", ".."), detached: true, stdio: ["ignore", "pipe", "pipe"] },
);
console.log(`dev server pid ${server.pid}`);
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

// --- the grid ----------------------------------------------------------------------------------

/** The map library's next tile (`placeholders.ts` `neighbour`): 0 E, 1 NE, 2 NW, 3 W, 4 SW, 5 SE. */
function neighbour(t, d) {
  const odd = t.y & 1;
  return [
    { x: t.x - 1, y: t.y },
    { x: t.x - 1 + odd, y: t.y + 1 },
    { x: t.x + odd, y: t.y + 1 },
    { x: t.x + 1, y: t.y },
    { x: t.x + odd, y: t.y - 1 },
    { x: t.x - 1 + odd, y: t.y - 1 },
  ][d];
}
const RING = { KeyQ: 3, KeyW: 2, KeyE: 1, KeyD: 0, KeyS: 5, KeyA: 4 };
const KEY_OF = Object.fromEntries(Object.entries(RING).map(([k, d]) => [d, k]));
const NAMES = ["East", "North-East", "North-West", "West", "South-West", "South-East"];
const key = (t) => `${t.x},${t.y}`;
const parse = (s) => {
  const [x, y] = s.split(",").map(Number);
  return { x, y };
};

/** The room's conversion (`input/coords.ts`): a tile's centre in world pixels. */
const ROW_HEIGHT = (64 / Math.sqrt(3)) * 1.5;
const tileToPixel = (t) => ({ x: -(t.x + (t.y & 1) / 2) * 64, y: -t.y * ROW_HEIGHT });

// --- the page ----------------------------------------------------------------------------------

const screen = (page, name) => page.locator(`[data-screen="${name}"]`);
const room = (page, name) => page.locator(`[data-screen="${name}"] [data-camera]`);

async function tileOf(page, name) {
  return parse(await room(page, name).getAttribute("data-tile"));
}

async function camera(page, name) {
  const [x, y, scale] = (await room(page, name).getAttribute("data-camera")).split(" ").map(Number);
  return { x, y, scale };
}

/** Waits until the adventurer stands still. */
async function stood(page, name) {
  await page.waitForTimeout(120);
  await page.locator(`[data-screen="${name}"] [data-walking="false"]`).waitFor({ timeout: 15_000 });
  await page.waitForTimeout(80);
}

/** The camera's centre off the adventurer, in px. */
async function offCentre(page, name) {
  const c = await camera(page, name);
  const box = await room(page, name).boundingBox();
  const p = tileToPixel(await tileOf(page, name));
  return Math.hypot(c.x + p.x * c.scale - box.width / 2, c.y + p.y * c.scale - box.height / 2);
}

/** What has the focus: its screen root, or its role and accessible name. */
function focused(page) {
  return page.evaluate(() => {
    const e = document.activeElement;
    if (!e) return "none";
    if (e.dataset?.screen) return `screen:${e.dataset.screen}`;
    const name = e.getAttribute("aria-label") || (e.textContent ?? "").trim();
    return `${e.tagName.toLowerCase()}:${name}`;
  });
}

const live = (page) => page.locator("[data-key-live]").innerText();

/** Presses a key; the adventurer's hex once it stands. */
async function stepBy(page, name, code) {
  await page.keyboard.press(code);
  await stood(page, name);
  return tileOf(page, name);
}

// --- a zone ------------------------------------------------------------------------------------

async function intoZone(page) {
  await page.goto(`${base}/?hub=town&entry=300&idle=0`);
  await screen(page, "hub").waitFor();
  ok((await focused(page)) === "screen:hub", `town: the hub's root has the focus on opening`);
  // The Gate by keys: Shift+F selects the last place of the row (the Gate), Enter walks there.
  await page.keyboard.press("Shift+KeyF");
  ok(/^Gate selected/.test(await live(page)), `town: Shift+F → "${await live(page)}"`);
  await page.keyboard.press("Enter");
  await screen(page, "gate").waitFor({ timeout: 15_000 });
  ok((await focused(page)) === "screen:gate", "Gate screen: its root has the focus");
  // Its Leave by gate 1 is reached by Tab, pressed by Enter.
  let reached = false;
  for (let i = 0; i < 12 && !reached; i += 1) {
    await page.keyboard.press("Tab");
    reached = (await focused(page)) === "button:Leave by gate 1";
  }
  ok(reached, "Gate screen: Tab reaches Leave by gate 1");
  await page.keyboard.press("Enter");
  await screen(page, "entry")
    .waitFor({ timeout: 2000 })
    .catch(() => {});
  await screen(page, "instance").waitFor({ timeout: 8000 });
  await page.locator('[data-screen="instance"] [data-atlas]:not([data-atlas="loading"])').waitFor();
  await page.waitForTimeout(300);
  ok((await focused(page)) === "screen:instance", "instance: its root has the focus on opening");
}

async function zone(page) {
  console.log("--- a zone, keys only ---");
  await intoZone(page);
  const offer = page.getByRole("button", { name: "Leave by this gate" });
  const dialog = page.getByRole("dialog", { name: "Confirm" });
  const anchor = await tileOf(page, "instance");
  ok((await offer.count()) === 0, `zone: on the anchor ${key(anchor)} at arrival, no offer`);

  // L on the anchor: the dialog, Stay focused; Esc closes it, the instance stays.
  await page.keyboard.press("KeyL");
  await dialog.waitFor({ timeout: 2000 });
  ok(
    (await focused(page)) === "button:Stay",
    "zone: L on the anchor opens the dialog, Stay focused",
  );
  if (shots) await page.screenshot({ path: join(shots, "keys-dialog-stay-1440x900.png") });
  // Tab and Shift+Tab stay inside it.
  const stops = [];
  for (const k of ["Tab", "Tab", "Shift+Tab", "Shift+Tab"]) {
    await page.keyboard.press(k);
    stops.push(await focused(page));
  }
  ok(
    stops.join(" ") === "button:Leave button:Stay button:Leave button:Stay",
    `zone: Tab stays inside the dialog (${stops.join(", ")})`,
  );
  // The map's keys are inert under it.
  await page.keyboard.press("KeyQ");
  await page.waitForTimeout(400);
  ok(
    key(await tileOf(page, "instance")) === key(anchor),
    "zone: a step key under the dialog moves nothing",
  );
  await page.keyboard.press("Escape");
  await page.waitForTimeout(100);
  ok((await dialog.count()) === 0, "zone: Esc closes the dialog (Stay)");
  ok((await screen(page, "instance").count()) === 1, "zone: the instance is still open");

  // The six keys: each one hex its way, then back by the opposite key. First two hexes West, into
  // the chunk (the anchor sits on the location's edge).
  await stepBy(page, "instance", "KeyQ");
  const at = await stepBy(page, "instance", "KeyQ");
  ok(true, `zone: two West steps from the anchor: ${key(at)}`);
  for (const [code, d] of Object.entries(RING)) {
    const from = await tileOf(page, "instance");
    const expected = neighbour(from, d);
    const to = await stepBy(page, "instance", code);
    ok(
      key(to) === key(expected),
      `zone: ${code.slice(3)} from ${key(from)} → ${key(to)} (${NAMES[d]}, expected ${key(expected)})`,
    );
    const back = await stepBy(page, "instance", KEY_OF[(d + 3) % 6]);
    ok(key(back) === key(from), `zone: and back to ${key(back)}`);
  }
  ok((await offer.count()) === 0, "zone: off the anchor, no offer");

  // L off the anchor opens nothing.
  await page.keyboard.press("KeyL");
  await page.waitForTimeout(300);
  ok((await dialog.count()) === 0, "zone: L off the anchor opens nothing");

  // Arrows: ← West, → East; ↑ ↓ on the side faced, on both row parities.
  let facing = null;
  for (const [code, kind] of [
    ["ArrowRight", 0],
    ["ArrowUp", "up"],
    ["ArrowDown", "down"],
    ["ArrowLeft", 3],
    ["ArrowUp", "up"],
    ["ArrowDown", "down"],
  ]) {
    const from = await tileOf(page, "instance");
    let d = kind;
    if (typeof kind === "string") {
      const east = facing === 0 || facing === 1 || facing === 5;
      d = kind === "up" ? (east ? 1 : 2) : east ? 5 : 4;
    }
    const expected = neighbour(from, d);
    const to = await stepBy(page, "instance", code);
    ok(
      key(to) === key(expected),
      `zone: ${code} from ${key(from)} (row ${from.y & 1 ? "odd" : "even"}) → ${key(to)} (${NAMES[d]})`,
    );
    facing = d;
  }

  // F selects the hub gate; Enter walks to its anchor; the offer appears (the adventurer left one).
  await page.keyboard.press("KeyF");
  ok(
    /^Gate to .+ selected, Enter to go$/.test(await live(page)),
    `zone: F → "${await live(page)}"`,
  );
  const marker = page.locator('[data-screen="instance"] .gw-key-marker');
  ok(await marker.isVisible(), "zone: a ring marks the gate's anchor");
  if (shots) await page.screenshot({ path: join(shots, "keys-zone-gate-selected-1440x900.png") });
  await page.keyboard.press("Enter");
  await stood(page, "instance");
  await page.waitForTimeout(200);
  ok(
    key(await tileOf(page, "instance")) === key(anchor),
    `zone: Enter walked to the anchor ${key(anchor)}`,
  );
  ok(
    (await offer.count()) === 1,
    `zone: back on the anchor, "${await offer.innerText().catch(() => "-")}" is offered`,
  );

  // The offer is reached by Tab like any button.
  let reached = false;
  for (let i = 0; i < 10 && !reached; i += 1) {
    await page.keyboard.press("Tab");
    reached = (await focused(page)) === "button:Leave by this gate";
  }
  ok(reached, "zone: Tab reaches the offer");

  // L, Tab, Enter: leave (asked twice); the report, its button focused; Enter → the town.
  await page.keyboard.press("KeyL");
  await dialog.waitFor({ timeout: 2000 });
  ok((await focused(page)) === "button:Stay", "zone: L opens the dialog on Stay");
  await page.keyboard.press("Tab");
  ok((await focused(page)) === "button:Leave", "zone: Tab → Leave");
  await page.keyboard.press("Enter");
  await screen(page, "report").waitFor({ timeout: 3000 });
  ok(/^button:On to /.test(await focused(page)), `report: "${await focused(page)}" has the focus`);
  await page.keyboard.press("Enter");
  await screen(page, "hub").waitFor({ timeout: 3000 });
  ok((await focused(page)) === "screen:hub", "report: Enter → the town, its root focused");
}

// --- the hubs ----------------------------------------------------------------------------------

async function serviceNames(page) {
  return page
    .getByRole("navigation", { name: "Services" })
    .getByRole("button")
    .evaluateAll((bs) => bs.map((b) => b.innerText.replace("▸", "").trim()));
}

async function hub(page, name) {
  console.log(`--- ${name}, keys only ---`);
  await page.goto(`${base}/?hub=${name}&idle=0`);
  await screen(page, "hub").waitFor();
  await page.locator('[data-screen="hub"] [data-atlas]:not([data-atlas="loading"])').waitFor();
  await page.waitForTimeout(300);
  const atlas = await room(page, "hub").getAttribute("data-atlas");
  console.log(
    `  note ${name}: atlas ${atlas}${atlas === "loaded" ? "" : " (the check runs on shapes)"}`,
  );
  ok((await focused(page)) === "screen:hub", `${name}: the root has the focus`);

  // A direction key walks one hex.
  let moved = false;
  for (const [code, d] of Object.entries(RING)) {
    const from = await tileOf(page, "hub");
    const to = await stepBy(page, "hub", code);
    if ((await screen(page, "hub").count()) === 0) break;
    if (key(to) !== key(from)) {
      ok(
        key(to) === key(neighbour(from, d)),
        `${name}: ${code.slice(3)} walks one hex ${key(from)} → ${key(to)}`,
      );
      moved = true;
      break;
    }
  }
  ok(moved, `${name}: a direction key walked`);

  // F / Shift+F through the places in the row's order; the name's ring and the live line move.
  const row = await serviceNames(page);
  const seen = [];
  const lines = [];
  for (let i = 0; i < row.length; i += 1) {
    await page.keyboard.press("KeyF");
    await page.waitForTimeout(60);
    seen.push(await page.locator("[data-selected]").getAttribute("data-label"));
    lines.push(await live(page));
  }
  ok(seen.join(",") === row.join(","), `${name}: F walks the row's order (${seen.join(", ")})`);
  ok(new Set(lines).size === row.length, `${name}: the live line changes (${lines[0]} …)`);
  await page.keyboard.press("KeyF");
  ok(
    (await page.locator("[data-selected]").getAttribute("data-label")) === row[0],
    `${name}: F wraps`,
  );
  await page.keyboard.press("Shift+KeyF");
  ok(
    (await page.locator("[data-selected]").getAttribute("data-label")) === row.at(-1),
    `${name}: Shift+F goes back, wrapping`,
  );
  const outline = await page
    .locator("[data-selected]")
    .evaluate((e) => getComputedStyle(e).outlineStyle);
  ok(outline !== "none", `${name}: the selected name shows the ring (${outline})`);
  if (shots && name === "town")
    await page.screenshot({ path: join(shots, "keys-town-place-selected-1440x900.png") });
  // Esc clears the selection.
  await page.keyboard.press("Escape");
  ok((await page.locator("[data-selected]").count()) === 0, `${name}: Esc clears the selection`);

  // F to the first place, Enter: walks to its door, its screen opens; Esc → the hub, on the door.
  await page.keyboard.press("KeyF");
  const first = page.locator("[data-selected]");
  const door = await first.getAttribute("data-door");
  const label = await first.getAttribute("data-label");
  await page.keyboard.press("Enter");
  await screen(page, "service").waitFor({ timeout: 15_000 });
  ok(
    (await screen(page, "service").getAttribute("data-service")) === label.toLowerCase(),
    `${name}: Enter on ${label} walked to its door and opened it`,
  );
  ok((await focused(page)) === "screen:service", `${name}: the service's root has the focus`);
  await page.keyboard.press("Escape");
  await screen(page, "hub").waitFor();
  await page.waitForTimeout(200);
  ok(key(await tileOf(page, "hub")) === door, `${name}: Esc → the hub, on ${label}'s door ${door}`);

  // 3: the third service at once.
  await page.keyboard.press("Digit3");
  await screen(page, "service").waitFor({ timeout: 1000 });
  ok(
    (await screen(page, "service").getAttribute("data-service")) === row[2].toLowerCase(),
    `${name}: 3 opens ${row[2]} at once`,
  );
  await page.keyboard.press("Escape");
  await screen(page, "hub").waitFor();
  await page.waitForTimeout(200);

  // The Gate by F … Enter, closed by Esc.
  const walked = [];
  for (let i = 0; i < row.length; i += 1) {
    await page.keyboard.press("KeyF");
    walked.push(await live(page));
  }
  ok(/^Gate/.test(walked.at(-1)), `${name}: F … reaches the Gate (${walked.join(" / ")})`);
  await page.keyboard.press("Enter");
  await screen(page, "gate").waitFor({ timeout: 15_000 });
  await page.keyboard.press("Escape");
  await screen(page, "hub").waitFor();
  ok(true, `${name}: the Gate opened by Enter, closed by Esc`);

  // The camera: +, −, then off the adventurer (a selection far away), and 0.
  const c0 = await camera(page, "hub");
  await page.keyboard.press("Equal");
  await page.waitForTimeout(200);
  const c1 = await camera(page, "hub");
  ok(c1.scale > c0.scale, `${name}: + zooms in (${c0.scale.toFixed(3)} → ${c1.scale.toFixed(3)})`);
  await page.keyboard.press("Minus");
  await page.waitForTimeout(200);
  const c2 = await camera(page, "hub");
  ok(c2.scale < c1.scale, `${name}: − zooms out (→ ${c2.scale.toFixed(3)})`);
  for (let i = 0; i < 4; i += 1) await page.keyboard.press("Equal");
  let panned = 0;
  for (let i = 0; i < row.length && panned < 40; i += 1) {
    await page.keyboard.press("KeyF");
    await page.waitForTimeout(400);
    panned = await offCentre(page, "hub");
  }
  console.log(
    `  note ${name}: a far place selected, the camera ${panned.toFixed(0)} px off the adventurer`,
  );
  await page.keyboard.press("Escape");
  await page.keyboard.press("Digit0");
  await page.waitForTimeout(600);
  const centre = await offCentre(page, "hub");
  ok(centre < 2, `${name}: 0 brings the camera back to the adventurer (${centre.toFixed(1)} px)`);

  // The key help: ? lists the screen's bindings; Esc closes it.
  await page.keyboard.press("?");
  const help = page.getByRole("dialog", { name: "Keys" });
  await help.waitFor({ timeout: 1000 });
  const rows = await help
    .locator("[data-binding]")
    .evaluateAll((r) => r.map((e) => e.dataset.binding));
  const expected = [
    "Q",
    "W",
    "E",
    "D",
    "S",
    "A",
    "← →",
    "↑ ↓",
    "F / Shift+F",
    "Enter",
    "1–9",
    "Esc",
    "0",
    "+ / −",
    "?",
  ];
  ok(rows.join("|") === expected.join("|"), `${name}: ? lists the hub's ${rows.length} bindings`);
  ok((await focused(page)) === "button:Close the keys", `${name}: the help's ✕ has the focus`);
  if (shots && name === "town")
    await page.screenshot({ path: join(shots, "keys-help-1440x900.png") });
  await page.keyboard.press("Escape");
  ok((await help.count()) === 0, `${name}: Esc closes the help`);
  ok((await focused(page)) === "screen:hub", `${name}: the focus goes back to the hub`);
}

/** The browser's keys, a text field's keys, and the ring on every Tab stop. */
async function leftAlone(page) {
  console.log("--- what the keyboard leaves alone ---");
  await page.goto(`${base}/?hub=town&idle=0`);
  await screen(page, "hub").waitFor();
  await page.locator('[data-screen="hub"] [data-atlas]:not([data-atlas="loading"])').waitFor();
  await page.evaluate(() => {
    window.__prevented = [];
    // On the window, after the page's own listeners: whether one prevented the key.
    window.addEventListener("keydown", (e) => {
      if (/^(Control|Meta|Shift|Alt)(Left|Right)$/.test(e.code)) return;
      window.__prevented.push(
        `${e.ctrlKey ? "Control+" : ""}${e.metaKey ? "Meta+" : ""}${e.code}:${e.defaultPrevented}`,
      );
    });
  });
  for (const k of ["Control+Equal", "Meta+KeyF", "Control+KeyW", "KeyF"])
    await page.keyboard.press(k);
  const prevented = await page.evaluate(() => window.__prevented);
  ok(
    prevented.slice(0, 3).every((p) => p.endsWith(":false")) && prevented[3] === "KeyF:true",
    `browser keys not prevented, F prevented (${prevented.join(", ")})`,
  );
  await page.keyboard.press("Escape");

  // Typing into the debug panel's field moves nothing.
  await page.getByRole("button", { name: "debug" }).focus();
  await page.keyboard.press("Enter");
  const field = page.getByRole("spinbutton").first();
  await field.focus();
  const before = key(await tileOf(page, "hub"));
  await page.keyboard.type("qweasd");
  await page.waitForTimeout(500);
  ok(
    key(await tileOf(page, "hub")) === before,
    "typing qweasd into the debug panel's field moves nothing",
  );
  await page.getByRole("button", { name: "× debug" }).focus();
  await page.keyboard.press("Enter");

  // Every Tab stop shows the ring.
  await screen(page, "hub").focus();
  const bare = [];
  const names = [];
  for (let i = 0; i < 16; i += 1) {
    await page.keyboard.press("Tab");
    const [name, style] = await page.evaluate(() => {
      const e = document.activeElement;
      // Past the last stop the focus leaves the page (the body): not a stop.
      if (e === document.body) return ["(page)", "page"];
      return [
        e.getAttribute("aria-label") || e.textContent.trim(),
        getComputedStyle(e).outlineStyle,
      ];
    });
    if (style === "page") continue;
    names.push(name);
    if (style === "none") bare.push(name);
  }
  ok(
    bare.length === 0,
    `every Tab stop shows the ring (${names.join(", ")})${bare.length ? `; none on ${bare.join(", ")}` : ""}`,
  );
}

async function desktop(browser) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  // No pointer at all on this page: a mouse event fails the run.
  await page.addInitScript(() => {
    for (const type of ["pointerdown", "mousedown", "touchstart"]) {
      window.addEventListener(type, () => (window.__pointer = true), true);
    }
  });
  await zone(page);
  await hub(page, "town");
  await hub(page, "outpost");
  await leftAlone(page);
  ok(!(await page.evaluate(() => window.__pointer === true)), "no pointer event on the page");
  ok(errors.length === 0, "desktop: no page error");
  for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  await context.close();
}

// --- AC-7: 375 px, touch, unchanged -------------------------------------------------------------

async function buttons(page) {
  return page.$$eval("button", (bs) =>
    bs
      .filter((b) => b.offsetParent !== null)
      .map((b) => b.getAttribute("aria-label") || b.textContent.trim())
      .sort(),
  );
}

async function phone(browser) {
  console.log("--- 375 × 812, touch: CLI-03f's taps ---");
  const context = await browser.newContext({
    viewport: { width: 375, height: 812 },
    hasTouch: true,
    isMobile: true,
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  const record = [];
  const note = async (what) => {
    const kind = await page.$eval(
      "[data-screen]",
      (e) => e.dataset.screen + (e.dataset.service ? `:${e.dataset.service}` : ""),
    );
    const tile = await page
      .locator("[data-tile]")
      .getAttribute("data-tile")
      .catch(() => null);
    record.push({ what, screen: kind, tile, buttons: await buttons(page) });
  };
  const hexOnPage = async (name, tile) => {
    const c = await camera(page, name);
    const box = await room(page, name).boundingBox();
    const p = tileToPixel(tile);
    return { x: box.x + c.x + p.x * c.scale, y: box.y + c.y + p.y * c.scale };
  };
  const tap = async (name, tile) => {
    const p = await hexOnPage(name, tile);
    await page.mouse.click(p.x, p.y);
  };
  await page.goto(`${base}/?hub=town&entry=300&idle=0`);
  await screen(page, "hub").waitFor();
  await page.locator('[data-screen="hub"] [data-atlas]:not([data-atlas="loading"])').waitFor();
  await note("arrival");
  await tap("hub", { x: 6, y: 3 });
  await stood(page, "hub");
  await note("ground walk");
  await tap("hub", { x: 5, y: 8 });
  await screen(page, "service").waitFor({ timeout: 15_000 });
  await note("place walk then open");
  await page.getByRole("button", { name: "Back" }).click();
  await screen(page, "hub").waitFor();
  await page.waitForTimeout(300);
  await note("back");
  await tap("hub", { x: 6, y: 3 });
  await page.waitForTimeout(100);
  await page
    .getByRole("navigation", { name: "Services" })
    .getByRole("button", { name: "Vault" })
    .click();
  await screen(page, "service").waitFor({ timeout: 1000 });
  await note("service row mid-walk");
  await page.getByRole("button", { name: "Back" }).click();
  await screen(page, "hub").waitFor();
  await page
    .getByRole("navigation", { name: "Services" })
    .getByRole("button", { name: /^Gate/ })
    .click();
  await page.getByRole("button", { name: "Leave by gate 1" }).click();
  await screen(page, "instance").waitFor({ timeout: 8000 });
  await page.locator('[data-screen="instance"] [data-atlas]:not([data-atlas="loading"])').waitFor();
  await note("instance");
  await page.getByRole("button", { name: "Leave", exact: true }).click();
  await page.getByRole("dialog", { name: "Confirm" }).waitFor();
  await note("Leave on the anchor");
  await page.getByRole("dialog", { name: "Confirm" }).getByRole("button", { name: "Stay" }).click();
  await note("Stay");
  for (const r of record)
    console.log(`  ${r.what}: ${r.screen} ${r.tile ?? "-"} [${r.buttons.join(", ")}]`);
  ok(!record.some((r) => r.buttons.includes("Keys ?")), "375: no Keys ? button");
  ok(errors.length === 0, "375: no page error");
  await context.close();
  if (process.env.VERIFY_PHONE_OUT)
    writeFileSync(process.env.VERIFY_PHONE_OUT, JSON.stringify(record, null, 1));
  if (process.env.VERIFY_PHONE_BASE) {
    const main = JSON.parse(readFileSync(process.env.VERIFY_PHONE_BASE, "utf8"));
    ok(main.length === record.length, `375: as many steps as main (${record.length})`);
    record.forEach((r, i) => {
      const m = main[i] ?? {};
      ok(
        r.screen === m.screen && r.tile === m.tile && r.buttons.join("|") === m.buttons.join("|"),
        `375: ${r.what}: ${r.screen} ${r.tile} and its buttons as on main`,
      );
    });
  }
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}`);
  if (only !== "phone") await desktop(browser);
  await phone(browser);
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
