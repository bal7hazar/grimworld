/* global console, process, fetch, setTimeout, document, localStorage */
/* eslint-disable no-empty */
// The chain screen in a real browser (CLI-11c): `?chain=<node url>` on the deployment of a local
// node, a Wait played with `Space` and sent with `B`, the panel's three stages captured. Run by hand,
// not by CI, inside a node that lives for the length of one command (docs/briefs/CLI-11-chain-play.md
// §7): `pnpm --filter @grimworld/app verify:chain`, after the classes are built
// (`scripts/lock.sh --heavy scarb --manifest-path contracts/Scarb.toml build`). The script starts the
// development server as its own process group, with `GRIMWORLD_DEPLOYMENT` (the file
// `scripts/devnet_deploy.py --out` wrote, which holds no key), and sends SIGTERM to that recorded
// group in `finally`. One browser at a time.
//
// It checks (AC of CLI-11c):
// - the chain mode reaches "ready" on a burner's own instance, and the map is drawn;
// - `Space` puts a Wait in the batch, and stage 1 (the mirror) shows at once, with the predicted
//   last tile as a ghost over the map;
// - stage 2 (the simulation) answers by itself, 300 ms after the last input;
// - `B` sends the batch, and stage 3 (the sent batch) shows beside stage 2: the same outcome, with
//   no field of the mirror or of the simulation differing;
// - the batch is empty again after the send, and the map was drawn again from the chain's state;
// - the URL did not change, and nothing the page logged holds the burner's key (D-273);
// - no page error.
//
// Env: GRIMWORLD_DEPLOYMENT (required: the deployment's file), VERIFY_PORT (default 5198),
// VERIFY_CHANNEL (the browser), VERIFY_ROOT (the checkout, the repository's root by default),
// VERIFY_SHOTS_DIR (the captures; default the untracked `.verify-out/`; D-73: never committed,
// attached or posted), VERIFY_TIMEOUT (ms to wait for the setup, default 300000).
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.VERIFY_PORT ?? 5198);
const base = `http://127.0.0.1:${port}`;
const root = process.env.VERIFY_ROOT ?? join(here, "..", "..");
const shots = process.env.VERIFY_SHOTS_DIR ?? join(here, ".verify-out");
const timeout = Number(process.env.VERIFY_TIMEOUT ?? 300_000);
const deploymentPath = process.env.GRIMWORLD_DEPLOYMENT;
if (!deploymentPath) {
  console.log("FAIL GRIMWORLD_DEPLOYMENT is not set: run through `pnpm … verify:chain`");
  process.exit(1);
}
mkdirSync(shots, { recursive: true });
const nodeUrl = JSON.parse(readFileSync(deploymentPath, "utf8")).node_url;

let failures = 0;
function ok(condition, label) {
  console.log(`${condition ? "ok  " : "FAIL"} ${label}`);
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
  {
    cwd: root,
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, GRIMWORLD_DEPLOYMENT: deploymentPath },
  },
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

/** The text of a stage's line, or null when it is not shown. */
const stage = (page, name) =>
  page.evaluate((n) => {
    const element = document.querySelector(`[data-stage="${n}"]`);
    return element ? element.textContent : null;
  }, name);

const text = (page, selector) =>
  page.evaluate((s) => document.querySelector(s)?.textContent ?? null, selector);

async function until(page, label, read, wanted, ms = 20_000) {
  const end = Date.now() + ms;
  let last = null;
  while (Date.now() < end) {
    last = await read();
    if (wanted(last)) return last;
    await page.waitForTimeout(100);
  }
  ok(false, `${label} (last: ${JSON.stringify(last)})`);
  throw new Error(`timed out: ${label}`);
}

let browser;
try {
  await ready();
  browser = await chromium.launch({ channel: process.env.VERIFY_CHANNEL || undefined });
  console.log(`browser launched: ${browser.version()}`);
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  const logged = [];
  const errors = [];
  page.on("console", (message) => logged.push(message.text()));
  page.on("pageerror", (error) => errors.push(String(error)));

  const url = `${base}/?chain=${nodeUrl}`;
  await page.goto(url);
  // The setup registers, creates, builds and enters: it can take a while on a busy machine
  await page.waitForSelector('[data-chain="ready"]', { timeout });
  ok(true, "the chain mode is ready on the burner's instance");
  await page.waitForSelector("canvas", { timeout: 20_000 });
  await until(
    page,
    "the map is drawn",
    () => page.evaluate(() => Number(document.querySelector("[data-frames]")?.dataset.frames ?? 0)),
    (frames) => frames > 0,
  );
  ok(true, "the map is drawn");
  const before = await page.evaluate(() => document.querySelector("[data-tile]")?.dataset.tile);
  ok(typeof before === "string" && before.includes(","), `the adventurer stands on ${before}`);
  ok((await text(page, '[data-panel="batch"]'))?.includes("empty"), "the batch starts empty");
  await page.screenshot({ path: join(shots, "chain-0-ready.png") });

  // A Wait: stage 1 at once
  await page.keyboard.press("Space");
  const mirror = await until(
    page,
    "stage 1 shows at once",
    () => stage(page, "mirror"),
    (line) => line !== null,
    2_000,
  );
  console.log(`stage 1: ${mirror}`);
  ok(/^mirror: (played 1|not mirrored)/.test(mirror), "stage 1 is the mirror's prediction");
  const batch = await text(page, '[data-panel="batch"]');
  ok(batch?.includes("wait"), `the batch holds the Wait (${batch})`);
  const ghost = await page.evaluate(() => document.querySelector("[data-ghosts]")?.dataset.end);
  console.log(`ghost end: ${ghost || "(none: not mirrored)"}`);
  ok(
    mirror.includes("not mirrored") || /^\d+,\d+,\d$/.test(ghost ?? ""),
    "the predicted tile is a ghost",
  );
  await page.screenshot({ path: join(shots, "chain-1-mirror.png") });

  // Stage 2: the simulation answers by itself
  const simulated = await until(
    page,
    "stage 2 answers",
    () => stage(page, "simulated"),
    (line) => line !== null && !line.includes("simulating"),
  );
  console.log(`stage 2: ${simulated}`);
  ok(
    /^simulated: played 1, stop none/.test(simulated),
    "stage 2 is the node's simulation of the Wait",
  );
  ok((await text(page, '[data-panel="differs"]')) === null, "the mirror and the simulation agree");
  await page.screenshot({ path: join(shots, "chain-2-simulated.png") });

  // Stage 3: B sends it
  const generation = () =>
    page.evaluate(() => Number(document.querySelector('[data-chain="ready"]')?.dataset.generation));
  const drawnBefore = await generation();
  await page.keyboard.press("KeyB");
  const sent = await until(
    page,
    "stage 3 shows",
    () => stage(page, "sent"),
    (line) => line !== null,
    120_000,
  );
  console.log(`stage 3: ${sent}`);
  ok(/^sent: played 1, stop none/.test(sent), "stage 3 is the chain's result of the Wait");
  ok(
    sent.replace(/^sent: /, "") === simulated.replace(/^simulated: /, ""),
    "the sent outcome equals the simulated one",
  );
  await until(
    page,
    "play resumes",
    () => text(page, "[data-chain-panel]"),
    (panel) => panel !== null,
    60_000,
  );
  await until(
    page,
    "the phase is ready again",
    () => page.evaluate(() => document.querySelector("[data-chain-panel]")?.dataset.chainPanel),
    (phase) => phase === "ready",
    120_000,
  );
  ok((await text(page, '[data-panel="differs"]')) === null, "no field differs between the stages");
  ok(
    (await text(page, '[data-panel="batch"]'))?.includes("empty"),
    "the batch is empty after the send",
  );
  // The map is mounted again from the chain's state: the state it draws is a new one
  const drawnAfter = await generation();
  ok(
    drawnAfter > drawnBefore,
    `the map was drawn again from the chain's state (state ${drawnBefore} → ${drawnAfter})`,
  );
  await page.waitForSelector("[data-frames]", { timeout: 20_000 });
  // §5.3: the simulation the batch was sent on stays beside the sent result
  const beside = await stage(page, "simulated");
  ok(
    beside !== null && beside.replace(/^simulated: /, "") === simulated.replace(/^simulated: /, ""),
    "stage 2 stays beside stage 3",
  );
  await page.screenshot({ path: join(shots, "chain-3-sent.png") });

  // D-273: nothing the page logged or shows holds the burner's key; the URL is unchanged
  const key = await page.evaluate(() => {
    try {
      const raw = localStorage.getItem("grimworld.account");
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  });
  const secrets = key
    ? Object.values(key).filter((v) => typeof v === "string" && /^0x[0-9a-f]{40,}$/i.test(v))
    : [];
  ok(secrets.length > 0, "the burner's key is in the page's own storage (and only there)");
  const everything = logged.join("\n") + (await page.content()) + page.url();
  ok(
    !secrets.some((s) => everything.includes(s)),
    "no log, no page and no URL holds the burner's key",
  );
  ok(page.url() === url, "the URL did not change");
  ok(errors.length === 0, `no page error${errors.length ? `: ${errors.join(" | ")}` : ""}`);
  console.log(`captures in ${shots}`);
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
