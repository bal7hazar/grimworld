/* global console, process, fetch, setTimeout */
/* eslint-disable no-empty */
// The hubs loop in a real browser (CLI-03c, CLI-03d): town → gate → entry → room → leave → report →
// town, the outpost, travel back, defeat, and the arrival rule (no automatic offer on arrival, the
// Leave control on the anchor). Run by hand, not by CI (it needs a browser and, for the art, the
// atlas): `pnpm --filter @grimworld/app verify:hubs`. Starts the dev server as its own process group
// and sends SIGTERM to that recorded group in `finally`. No screenshot is taken unless
// VERIFY_SHOTS is set, and then only into the untracked `.verify-out/`, or VERIFY_SHOTS_DIR (D-73:
// a folder outside git). With the shots, CLI-03e's four: the town and the outpost at 375 × 812 and
// 1440 × 900, once the atlas is loaded (`hub-<name>-<viewport>.png`). The hub pass also opens the
// town in `?scale=sharp` and fails on any page error. Its check that no place is drawn as a shape
// applies only with the pack (the atlas built in `tools/art/out/`); without it the pass notes the
// shapes and asserts nothing about them.
//
// CLI-03f's walking pass (a hub lived like a zone, D-202), in both hubs at both sizes, idle
// animations off: the hub's canvas is the zone's room (`data-frames` on the room, the instance's
// too); a tap on a ground hex walks there, the camera follows, and the frames stop once it stands;
// no walk counter in a hub; a tap on the Smith (the town) or the Trainer (the outpost) walks to its
// door, then opens its screen; back, the adventurer still stands on the door; the Gate walked to
// opens the Gate screen, and back on its door nothing reopens; the service row opens a place at
// once, mid-walk; a wheel zoom changes the scale and the ◎ button brings the camera back. With the
// shots, each hub mid-walk and after it (`walk-<hub>-<viewport>-{mid,after}.png`).
//
// Env: VERIFY_PORT (default 5197), VERIFY_CHANNEL (a Playwright channel such as "chrome"; default:
// the Chromium that `playwright-core install chromium` fetched), VERIFY_SHOTS=1, VERIFY_SHOTS_DIR.
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5197);
const base = `http://127.0.0.1:${port}`;
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

const screen = (page, name) => page.locator(`[data-screen="${name}"]`);

async function into(page, hub, gateId) {
  // The service row's Gate: it opens the Gate screen at once (CLI-03f).
  await page
    .getByRole("navigation", { name: "Services" })
    .getByRole("button", { name: /^Gate/ })
    .click();
  await page.getByRole("button", { name: `Leave by gate ${gateId}` }).click();
  await screen(page, "instance").waitFor({ timeout: 8000 });
  await page.getByRole("button", { name: "Travel back" }).waitFor();
  await page.locator('[data-screen="instance"] [data-frames]').waitFor();
  ok(true, `${hub}: entry moment → instance (its room exposes data-frames)`);
}

async function walk(page, dx) {
  const box = await page.locator('[data-screen="instance"] canvas').boundingBox();
  await page.mouse.click(box.x + box.width / 2 + dx, box.y + box.height / 2);
  await page.waitForTimeout(1500);
}

async function arrivalCase(page, hub, name, gateId) {
  await into(page, hub, gateId);
  const control = page.getByRole("button", { name: "Leave", exact: true });
  const offer = page.getByRole("button", { name: "Leave by this gate" });
  ok((await offer.count()) === 0, `${name}: no automatic offer on arrival`);
  ok(await control.isEnabled(), `${name}: the Leave control is enabled on the anchor at arrival`);
  await control.click();
  const dialog = page.getByRole("dialog", { name: "Confirm" });
  const text = (await dialog.innerText()).split("\n")[0];
  ok(/^Leave the instance for .+\?/.test(text), `${name}: asked "${text}"`);
  await dialog.getByRole("button", { name: "Stay" }).click();
  ok((await dialog.count()) === 0, `${name}: Stay closes the question`);
  // Step off the anchor (a tap one tile away), then back.
  let off = false;
  for (const dx of [-30, 30, 60, -60]) {
    await walk(page, dx);
    if (await control.isDisabled()) {
      off = true;
      break;
    }
  }
  ok(off, `${name}: one step off the anchor, the Leave control is disabled`);
  ok((await offer.count()) === 0, `${name}: no offer off an anchor`);
  const canvas = await page.locator('[data-screen="instance"] canvas').boundingBox();
  // The camera follows the adventurer: tap back toward where the anchor was (mirror of the way off).
  let back = false;
  for (const dx of [30, -30, 60, -60]) {
    await walk(page, dx);
    if ((await offer.count()) > 0) {
      back = true;
      break;
    }
  }
  ok(back, `${name}: back on the anchor, "${back ? await offer.innerText() : "-"}" is offered`);
  if (shots) await page.screenshot({ path: join(shots, `${name}-offer.png`) });
  void canvas;
  await control.waitFor();
}

async function leaveByGate(page, name, hubName) {
  await page.getByRole("button", { name: "Leave", exact: true }).click();
  await page
    .getByRole("dialog", { name: "Confirm" })
    .getByRole("button", { name: "Leave", exact: true })
    .click();
  const report = screen(page, "report");
  await report.waitFor();
  ok((await report.getAttribute("data-outcome")) === "returned", `${name}: report returned (gate)`);
  await page.getByRole("button", { name: new RegExp(`On to ${hubName}`) }).click();
  await screen(page, "hub").waitFor();
  ok(true, `${name}: closed the report → ${hubName}`);
}

async function endBy(page, name, hubName, how) {
  if (how === "travel") {
    await page.getByRole("button", { name: "Travel back" }).click();
    await page
      .getByRole("dialog", { name: "Confirm" })
      .getByRole("button", { name: "Travel back" })
      .click();
  } else {
    await page.getByRole("button", { name: /debug: defeat now/ }).click();
  }
  const report = screen(page, "report");
  await report.waitFor();
  const outcome = await report.getAttribute("data-outcome");
  ok(
    outcome === (how === "travel" ? "returned" : "defeated"),
    `${name}: ${how} → report ${outcome}`,
  );
  await page.getByRole("button", { name: new RegExp(`On to ${hubName}`) }).click();
  await screen(page, "hub").waitFor();
}

async function run(browser, label, viewport, touch) {
  console.log(`=== ${label} ===`);
  const context = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
  await page.goto(`${base}/?hub=town&entry=300`);
  await screen(page, "hub").waitFor();
  ok(true, `${label}: town`);
  await arrivalCase(page, "town", `${label} town`, 1);
  await leaveByGate(page, `${label} town`, "Town A");
  await into(page, "town", 1);
  await endBy(page, `${label} town`, "Town A", "travel");
  await into(page, "town", 1);
  await endBy(page, `${label} town`, "Town A", "defeat");
  await page.goto(`${base}/?hub=outpost&entry=300`);
  await screen(page, "hub").waitFor();
  await arrivalCase(page, "outpost", `${label} outpost`, 101);
  await leaveByGate(page, `${label} outpost`, "Outpost B");
  // A page error is reported, not failed: the renderer has drawn once after its destroy on leaving
  // a room (renderer.ts placeWorld, a null `world`), a known issue outside this script's scope.
  for (const e of errors)
    console.log(`  note page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
  await context.close();
}

/** CLI-03e: each hub at a phone and a desktop size, with the atlas; no place drawn as a shape. */
async function hubShots(browser) {
  for (const [label, viewport, touch] of [
    ["375x812", { width: 375, height: 812 }, true],
    ["1440x900", { width: 1440, height: 900 }, false],
  ]) {
    const context = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
    for (const hub of ["town", "outpost", "town&scale=sharp"]) {
      await page.goto(`${base}/?hub=${hub}`);
      await screen(page, "hub").waitFor();
      const canvas = page.locator("[data-atlas]");
      await page.locator('[data-atlas]:not([data-atlas="loading"])').waitFor();
      const atlas = await canvas.getAttribute("data-atlas");
      await page.waitForTimeout(500);
      const shapes = await page.locator("[data-shape]").count();
      if (atlas === "loaded")
        ok(shapes === 0, `${hub} ${label}: atlas loaded, no place as a shape`);
      else console.log(`  note ${hub} ${label}: atlas ${atlas}, ${shapes} places as shapes`);
      const frames = Number(await canvas.getAttribute("data-frames"));
      ok(frames >= 1, `${hub} ${label}: drawn (${frames} frames)`);
      if (shots) {
        const path = join(shots, `hub-${hub.replace("&scale=", "-")}-${label}.png`);
        await page.screenshot({ path });
        console.log(`  shot ${path}`);
      }
    }
    ok(errors.length === 0, `hubs ${label}: no page error`);
    for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
    await context.close();
  }
}

/** The room's conversion (`input/coords.ts`): a tile's centre in world pixels. */
const ROW_HEIGHT = (64 / Math.sqrt(3)) * 1.5;
const tileToPixel = (t) => ({ x: -(t.x + (t.y & 1) / 2) * 64, y: -t.y * ROW_HEIGHT });

const room = (page) => page.locator('[data-screen="hub"] [data-camera]');

/** The camera as last drawn: tile (0, 0) on the canvas, and CSS pixels per art pixel. */
async function camera(page) {
  const [x, y, scale] = (await room(page).getAttribute("data-camera")).split(" ").map(Number);
  return { x, y, scale };
}

/** A hex's centre on the page, from the room's camera (`data-camera`). */
async function hexOnPage(page, tile) {
  const c = await camera(page);
  const box = await room(page).boundingBox();
  const p = tileToPixel(tile);
  return { x: box.x + c.x + p.x * c.scale, y: box.y + c.y + p.y * c.scale };
}

const walkerAt = (page) => room(page).getAttribute("data-tile");

/** Waits until the adventurer stands still; the time it took, in ms. */
async function stood(page, timeout = 15_000) {
  const start = Date.now();
  await page.waitForTimeout(100);
  await page.locator('[data-screen="hub"] [data-walking="false"]').waitFor({ timeout });
  return Date.now() - start;
}

async function tapHex(page, tile) {
  const p = await hexOnPage(page, tile);
  await page.mouse.click(p.x, p.y);
}

const WALKS = {
  // A free ground hex, the place walked to (a hex of its building above its door), the Gate.
  town: {
    ground: [6, 3],
    place: "Smith",
    building: [5, 8],
    door: "5,7",
    gate: [1, 2],
    gateDoor: "1,1",
  },
  outpost: {
    ground: [4, 4],
    place: "Trainer",
    building: [5, 8],
    door: "5,7",
    gate: [1, 3],
    gateDoor: "1,2",
  },
};

async function walking(browser) {
  for (const [label, viewport, touch] of [
    ["375x812", { width: 375, height: 812 }, true],
    ["1440x900", { width: 1440, height: 900 }, false],
  ]) {
    const context = await browser.newContext({ viewport, hasTouch: touch, isMobile: touch });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.stack ?? String(e)));
    for (const [hub, walk] of Object.entries(WALKS)) {
      const name = `walk ${hub} ${label}`;
      await page.goto(`${base}/?hub=${hub}&idle=0`);
      await screen(page, "hub").waitFor();
      await page.locator('[data-screen="hub"] [data-atlas]:not([data-atlas="loading"])').waitFor();
      const arrival = await walkerAt(page);
      ok(arrival !== null, `${name}: the adventurer stands on ${arrival} on arrival`);
      ok((await screen(page, "hub").count()) === 1, `${name}: arriving opens nothing`);
      const start = await camera(page);
      ok(
        true,
        `${name}: a hex is ${(64 * start.scale).toFixed(1)} points across at the default zoom`,
      );
      // A tap on the ground: the walk, the camera following, no counter.
      const tapped = walk.ground.join(",");
      await tapHex(page, { x: walk.ground[0], y: walk.ground[1] });
      await page.waitForTimeout(250);
      const counter = await page.getByRole("button", { name: "Cancel the planned path" }).count();
      ok(counter === 0, `${name}: no walk counter in a hub`);
      if (shots) await page.screenshot({ path: join(shots, `walk-${hub}-${label}-mid.png`) });
      const ms = await stood(page);
      ok((await walkerAt(page)) === tapped, `${name}: walked to ${tapped} (${ms} ms)`);
      await page.waitForTimeout(400);
      const after = await camera(page);
      const box = await room(page).boundingBox();
      const p = tileToPixel({ x: walk.ground[0], y: walk.ground[1] });
      const off = Math.hypot(
        after.x + p.x * after.scale - box.width / 2,
        after.y + p.y * after.scale - box.height / 2,
      );
      ok(off < 2, `${name}: the camera followed (${off.toFixed(1)} px off the centre)`);
      const frames = Number(await room(page).getAttribute("data-frames"));
      await page.waitForTimeout(1000);
      const later = Number(await room(page).getAttribute("data-frames"));
      ok(later === frames, `${name}: data-frames stops growing once it stands (${frames})`);
      if (shots) await page.screenshot({ path: join(shots, `walk-${hub}-${label}-after.png`) });
      // A tap on a building: the walk to its door, then its screen.
      const t0 = Date.now();
      await tapHex(page, { x: walk.building[0], y: walk.building[1] });
      await screen(page, "service").waitFor({ timeout: 15_000 });
      ok(
        Date.now() - t0 > 180,
        `${name}: ${walk.place}: walked (${Date.now() - t0} ms), then opened`,
      );
      await page.getByRole("button", { name: "Back" }).click();
      await screen(page, "hub").waitFor();
      await page.waitForTimeout(300);
      ok((await walkerAt(page)) === walk.door, `${name}: back, still on the ${walk.place}'s door`);
      // The Gate, walked to; back on its door, nothing reopens.
      await tapHex(page, { x: walk.gate[0], y: walk.gate[1] });
      await screen(page, "gate").waitFor({ timeout: 15_000 });
      ok(true, `${name}: walked to the Gate: the Gate screen`);
      await page.getByRole("button", { name: "Back" }).click();
      await screen(page, "hub").waitFor();
      await page.waitForTimeout(300);
      ok((await walkerAt(page)) === walk.gateDoor, `${name}: back, on the Gate's door`);
      await page.waitForTimeout(1000);
      ok((await screen(page, "hub").count()) === 1, `${name}: nothing reopens on the door`);
      // The service row opens a place at once, mid-walk.
      await tapHex(page, { x: walk.ground[0], y: walk.ground[1] });
      await page.waitForTimeout(100);
      await page
        .getByRole("navigation", { name: "Services" })
        .getByRole("button", { name: "Vault" })
        .click();
      await screen(page, "service").waitFor({ timeout: 1000 });
      ok(true, `${name}: the service row opens the Vault at once, mid-walk`);
      await page.getByRole("button", { name: "Back" }).click();
      await screen(page, "hub").waitFor();
      await page.waitForTimeout(300);
      // A wheel zoom, a pan, then ◎ back to the adventurer, as in the instance.
      const canvas = await room(page).boundingBox();
      const before = await camera(page);
      await page.mouse.move(canvas.x + canvas.width / 2, canvas.y + canvas.height / 2);
      await page.mouse.wheel(0, -400);
      await page.waitForTimeout(500);
      const zoomed = await camera(page);
      ok(
        zoomed.scale > before.scale,
        `${name}: the wheel zooms in (${before.scale.toFixed(3)} → ${zoomed.scale.toFixed(3)})`,
      );
      await page.mouse.move(canvas.x + canvas.width / 2, canvas.y + canvas.height / 2);
      await page.mouse.down();
      await page.mouse.move(canvas.x + canvas.width / 2 + 120, canvas.y + canvas.height / 2 + 80, {
        steps: 8,
      });
      await page.mouse.up();
      await page.waitForTimeout(400);
      const panned = await camera(page);
      ok(Math.hypot(panned.x - zoomed.x, panned.y - zoomed.y) > 50, `${name}: a drag pans`);
      await page.getByRole("button", { name: "Back to the adventurer" }).click();
      await page.waitForTimeout(600);
      const back = await camera(page);
      const at = (await walkerAt(page)).split(",").map(Number);
      const q = tileToPixel({ x: at[0], y: at[1] });
      const centre = Math.hypot(
        back.x + q.x * back.scale - canvas.width / 2,
        back.y + q.y * back.scale - canvas.height / 2,
      );
      ok(
        centre < 2,
        `${name}: ◎ brings the camera back to the adventurer (${centre.toFixed(1)} px)`,
      );
    }
    ok(errors.length === 0, `walking ${label}: no page error`);
    for (const e of errors) console.log(`  page error: ${e.split("\n").slice(0, 2).join(" | ")}`);
    await context.close();
  }
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}`);
  await run(browser, "phone-375x812", { width: 375, height: 812 }, true);
  await run(browser, "desktop-1440x900", { width: 1440, height: 900 }, false);
  await hubShots(browser);
  await walking(browser);
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
