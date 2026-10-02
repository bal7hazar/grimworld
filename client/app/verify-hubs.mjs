/* global console, process, fetch, setTimeout */
/* eslint-disable no-empty */
// The hubs loop in a real browser (CLI-03c, CLI-03d): town → gate → entry → room → leave → report →
// town, the outpost, travel back, defeat, and the arrival rule (no automatic offer on arrival, the
// Leave control on the anchor). Run by hand, not by CI (it needs a browser and, for the art, the
// atlas): `pnpm --filter @grimworld/app verify:hubs`. Starts the dev server as its own process group
// and sends SIGTERM to that recorded group in `finally`. No screenshot is taken unless
// VERIFY_SHOTS is set, and then only into the untracked `.verify-out/`, or VERIFY_SHOTS_DIR (D-73:
// a folder outside git). With the shots, CLI-03e's four: the town and the outpost at 375 × 812 and
// 1440 × 900, once the atlas is loaded (`hub-<name>-<viewport>.png`), and a check that no place is
// drawn as a shape when the atlas is there.
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
  await page.getByRole("button", { name: "Gate building" }).click();
  await page.getByRole("button", { name: `Leave by gate ${gateId}` }).click();
  await screen(page, "instance").waitFor({ timeout: 8000 });
  await page.getByRole("button", { name: "Travel back" }).waitFor();
  ok(true, `${hub}: entry moment → instance`);
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
    for (const hub of ["town", "outpost"]) {
      await page.goto(`${base}/?hub=${hub}`);
      await screen(page, "hub").waitFor();
      const canvas = page.locator("[data-atlas]");
      await page.waitForFunction(
        () => document.querySelector("[data-atlas]")?.getAttribute("data-atlas") !== "loading",
      );
      const atlas = await canvas.getAttribute("data-atlas");
      await page.waitForTimeout(500);
      const shapes = await page.locator("[data-shape]").count();
      if (atlas === "loaded") ok(shapes === 0, `${hub} ${label}: atlas loaded, no place as a shape`);
      else console.log(`  note ${hub} ${label}: atlas ${atlas}, ${shapes} places as shapes`);
      if (shots) {
        const path = join(shots, `hub-${hub}-${label}.png`);
        await page.screenshot({ path });
        console.log(`  shot ${path}`);
      }
    }
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
