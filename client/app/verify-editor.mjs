/* global console, process, fetch, setTimeout, localStorage, Buffer, URL */
/* eslint-disable no-empty */
// The map editor in a real browser (CLI-09a): at 1440 × 900, with the art and in the plain look
// (the art's `/art/` answered 404), a 15 × 15-chunk zone is created, painted, outlined, saved,
// opened again from its file and saved again: the two files are identical. Run by hand, not by CI:
// `node verify-editor.mjs`. Starts the dev server as its own process group and sends SIGTERM to that
// recorded group in `finally`. The server inherits GRIMWORLD_ART_OUT (the built atlas, D-73: never
// committed).
//
// Shots of each step into VERIFY_SHOTS_DIR (default the untracked `.verify-out/`; D-73: the shots
// with the art are never committed, attached or posted).
//
// Env: VERIFY_PORT (default 5199), VERIFY_CHANNEL, VERIFY_ROOT (the checkout whose dev server runs;
// default this one), VERIFY_SHOTS_DIR.
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5199);
const base = `http://127.0.0.1:${port}`;
const root = process.env.VERIFY_ROOT ?? join(here, "..", "..");
const shots = process.env.VERIFY_SHOTS_DIR ?? join(here, ".verify-out");
mkdirSync(shots, { recursive: true });

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

/** Counts a saved file's floors and outline hexes. */
function countFile(text) {
  const file = JSON.parse(text);
  const count = (rows, ch) => rows.join("").split(ch).length - 1;
  return {
    file,
    floors: count(file.layers.terrain, "."),
    inside: count(file.layers.outline, "1"),
    outside: count(file.layers.outline, "0"),
  };
}

async function saveWith(page, path) {
  const [download] = await Promise.all([
    page.waitForEvent("download"),
    page.keyboard.press("Control+s"),
  ]);
  await download.saveAs(path);
  return readFileSync(path, "utf8");
}

/** One look: "art" (the atlas served) or "plain" (`/art/` answers 404). */
async function run(browser, look) {
  console.log(`=== ${look} ===`);
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    acceptDownloads: true,
  });
  const foreign = [];
  await context.route("**/*", (route) => {
    const url = new URL(route.request().url());
    if (url.origin !== base) {
      foreign.push(url.href);
      return route.abort();
    }
    if (look === "plain" && url.pathname.startsWith("/art/")) {
      return route.fulfill({ status: 404, body: "" });
    }
    return route.continue();
  });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  // The plain look's `/art/` answers 404 on purpose: the browser logs it, the page does not fail.
  page.on("console", (m) => {
    const expected = look === "plain" && m.text().includes("status of 404");
    if (m.type() === "error" && !expected) errors.push(m.text());
  });
  const shot = (name) => page.screenshot({ path: join(shots, `editor-${look}-${name}.png`) });

  await page.goto(`${base}/editor.html`);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.locator('[data-screen="list"]').waitFor();
  ok(await page.getByText("No draft yet.").isVisible(), "the map list opens, no draft");

  // Create.
  await page.locator("[data-new-map]").click();
  await page.locator("#ed-name").fill(`Verify ${look}`);
  await page.locator('input[name="width"]').fill("15");
  await page.locator('input[name="height"]').fill("15");
  await page.getByText("= 225 × 225 tiles").waitFor();
  await page.locator("[data-confirm]").click();
  const canvas = page.locator("[data-canvas]");
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor();
  const atlas = await canvas.getAttribute("data-atlas");
  ok(atlas === (look === "art" ? "loaded" : "none"), `the art: ${atlas}`);
  ok(
    (await page.locator("[data-topbar]").innerText()).includes("15×15 chunks"),
    "a 15 × 15-chunk zone is open",
  );
  await page.waitForTimeout(800);
  await shot("1-create");

  // Paint: floor, brush 4 (radius 3), three strokes across the middle; then water.
  const box = await canvas.boundingBox();
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;
  await page.locator('[data-swatch="terrain-floor"]').click();
  for (let i = 0; i < 3; i += 1) await page.keyboard.press("]");
  ok((await page.locator("[data-armed]").innerText()).includes("brush 4"), "brush 4 from ]");
  // Closer, so that the strokes cover many hexes: zoom in twice.
  await page.keyboard.press("=");
  await page.keyboard.press("=");
  for (const dy of [-60, 0, 60]) {
    await page.mouse.move(cx - 300, cy + dy);
    await page.mouse.down();
    await page.mouse.move(cx + 300, cy + dy, { steps: 30 });
    await page.mouse.up();
  }
  await page.locator('[data-swatch="ground-water"]').click();
  await page.mouse.move(cx, cy - 150);
  await page.mouse.down();
  await page.mouse.move(cx + 80, cy - 150, { steps: 8 });
  await page.mouse.up();
  await page.waitForTimeout(500);
  await shot("2-paint");
  // Undo the water, redo it.
  await page.keyboard.press("Control+z");
  await page.keyboard.press("Control+Shift+z");

  // Outline: from the floor, then a right drag marks some outside.
  await page.keyboard.press("t");
  await page.locator("[data-outline-from-floor]").click();
  await page.keyboard.press("[");
  await page.mouse.move(cx - 300, cy);
  await page.mouse.down({ button: "right" });
  await page.mouse.move(cx - 250, cy, { steps: 6 });
  await page.mouse.up({ button: "right" });
  await page.locator('[data-layer="seams"]').check();
  await page.keyboard.press("0");
  await page.waitForTimeout(800);
  const chunkSet = await page.locator("[data-chunk-set]").innerText();
  ok(
    /^\d+ chunks in the set/.test(chunkSet) && !chunkSet.startsWith("225 "),
    `outline: ${chunkSet}`,
  );
  await shot("3-outline");

  // Save: the draft, and a download.
  const first = await saveWith(page, join(shots, `editor-${look}-1.grimmap.json`));
  const a = countFile(first);
  ok(a.file.format === "grimworld-map" && a.file.version === 1, "the file's format and version");
  ok(a.floors > 500, `painted: ${a.floors} floor hexes`);
  ok(a.inside > 0 && a.outside > 0, `outlined: ${a.inside} inside, ${a.outside} outside`);
  ok((await page.locator("[data-save-state]").innerText()).startsWith("Saved"), "saved (draft)");
  await shot("4-save");

  // Reload the page: the draft is listed.
  await page.reload();
  await page.locator('[data-screen="list"]').waitFor();
  ok((await page.locator("[data-draft]").count()) === 1, "after a reload, the draft is listed");

  // Open the saved file, save it again: identical.
  await page
    .locator("[data-open-file]")
    .setInputFiles(join(shots, `editor-${look}-1.grimmap.json`));
  await page.locator('[data-editor="map"], [role="alert"]').first().waitFor();
  const refused = page.locator('[data-screen="list"] [role="alert"]');
  if (await refused.count())
    throw new Error(`the saved file was refused: ${await refused.innerText()}`);
  await page.locator('[data-canvas]:not([data-atlas="loading"])').waitFor();
  await page.locator('[data-layer="seams"]').check();
  await page.waitForTimeout(800);
  await shot("5-reload");
  const second = await saveWith(page, join(shots, `editor-${look}-2.grimmap.json`));
  ok(second === first, "reloaded from the file and saved again: the same file, byte for byte");

  // A file of a newer version is refused, and the open map is untouched.
  const newer = JSON.stringify({ ...a.file, version: 2 });
  await page.locator("[data-open-file]").setInputFiles({
    name: "newer.grimmap.json",
    mimeType: "application/json",
    buffer: Buffer.from(newer),
  });
  await page.getByRole("alert").waitFor();
  ok((await page.getByRole("alert").innerText()).includes("newer"), "a newer file is refused");
  ok(
    (await page.locator("[data-map-name]").innerText()) === `Verify ${look}`,
    "the open map stays",
  );

  // Below 700 px: one line.
  await page.setViewportSize({ width: 600, height: 900 });
  ok(
    await page.getByText("The map editor needs a desktop window.").isVisible(),
    "below 700 px: the one line",
  );

  ok(foreign.length === 0, `no request beyond the page's origin (${foreign.length})`);
  ok(errors.length === 0, `no page error${errors.length ? `: ${errors.join(" | ")}` : ""}`);
  await context.close();
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}`);
  await run(browser, "art");
  await run(browser, "plain");
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
