import { readFileSync, writeFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import type { Intent } from "../input/intent";
import type { Tile } from "../render/view";
import { hubWorld, onIsland } from "../sandbox/fixtures/hubWorld";
import { HUB_VIEWS } from "../sandbox/fixtures/hubs";
import { GATES, OUTPOST, TOWN, ZONE, globalTile, locationOf } from "../sandbox/fixtures/region";
import { insideOutline, zoneWorld } from "../sandbox/fixtures/zone";
import { applyIntent, initialState, walkStep } from "../sandbox/wiring";
import type { SandboxWorld } from "../sandbox/world";
import { fitChunks, fitted } from "./fit";
import { loadMap, saveMap } from "./file";
import {
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  WALL,
  cellOf,
  createMap,
  keyOf,
  terrainOf,
} from "./model";
import type { MapObject } from "./objects";
import { validate } from "./validate";
import { frameOf, walkWorld } from "./walkWorld";

/**
 * The seed's zone (`fixtures/zone.ts`) and the hubs (`fixtures/hubs.ts`) redrawn in the editor
 * (CLI-09b's acceptance), committed as files of the editor's format 2 under `fixtures/`. The
 * documents are built here from the game's fixtures; the committed files must be what they save
 * to. `GRIMWORLD_WRITE_FIXTURES=1` writes them again.
 */

const DIR = new URL("./fixtures/", import.meta.url);
const EDITOR = "fixture";

const ground = (g: string) => GROUND_KINDS.indexOf(g as (typeof GROUND_KINDS)[number]);

/** The client's fixture gate 102 anchors at (40, 7), one hex inside the outline: E-5 refuses it. */
const GATE_102_GAME = { x: 40, y: 7 };
/** The redrawn zone moves it one hex East, onto the outline's border (x grows West). */
const GATE_102_EDITOR = { x: 41, y: 7 };

function put(doc: MapDocument, object: MapObject): void {
  doc.objects.set(doc.objects.size + 1, object);
}

/**
 * The seed's zone: location 2, a meadow of 3 × 2 chunks cut by its outline; its terrain and ground
 * as `zoneWorld` makes them (the rocks' pattern), the outside painted as the void's water, with one
 * ring of it around the rectangle so that the outline is closed (E-3). Given candidate quota places
 * (an exit and a collector, two each) and two spawn points (the runts' pack, and one in chunk 16),
 * as the task asks; a chest.
 */
function seedZone(): MapDocument {
  const record = locationOf(ZONE)!;
  const entry = globalTile(record.entry_chunk, record.entry_tile);
  const world = zoneWorld(entry);
  const { width, height } = world.terrain;
  const doc = createMap({ kind: "zone", name: "Seed meadow", location: ZONE, biome: "meadow" });
  doc.meta = {
    ...doc.meta,
    levelMin: record.level_min,
    levelMax: record.level_max,
    spawnTable: 1,
    quotas: [
      { kind: "exit", param: 0, count: 1 },
      { kind: "collector", param: 0, count: 1 },
    ],
  };
  for (let y = -1; y <= height; y++) {
    for (let x = -1; x <= width; x++) {
      const inRect = x >= 0 && y >= 0 && x < width && y < height;
      const i = y * width + x;
      const inside = inRect && insideOutline(ZONE, { x, y });
      const kind = inRect ? world.terrain.hidden[i] : "wall";
      const g = inRect ? world.terrain.ground![i]! : "water";
      doc.hexes.set(keyOf({ x, y }), cellOf(kind === "floor" ? FLOOR : WALL, ground(g), !inside));
    }
  }
  put(doc, { kind: "entry", at: entry });
  for (const gate of GATES.filter((g) => g.source === ZONE)) {
    const anchor = globalTile(gate.anchor_chunk, gate.anchor_tile);
    const moved = anchor.x === GATE_102_GAME.x && anchor.y === GATE_102_GAME.y;
    put(doc, {
      kind: "gate",
      at: moved ? GATE_102_EDITOR : anchor,
      to: gate.destination,
      gate: "hub",
      rank: gate.rank,
      quest: gate.quest,
      entryChunk: gate.entry_chunk,
      entryTile: gate.entry_tile,
    });
  }
  put(doc, { kind: "candidate", at: { x: 38, y: 12 }, quota: 0 });
  put(doc, { kind: "candidate", at: { x: 22, y: 26 }, quota: 0 });
  put(doc, { kind: "candidate", at: { x: 10, y: 20 }, quota: 1 });
  put(doc, { kind: "candidate", at: { x: 26, y: 4 }, quota: 1 });
  put(doc, { kind: "spawn", at: { x: 21, y: 10 }, template: 1 });
  put(doc, { kind: "spawn", at: { x: 18, y: 22 }, template: 1 });
  put(doc, { kind: "feature", at: { x: 33, y: 2 }, feature: "chest" });
  doc.origin = { x: 0, y: 0, how: "fitted" };
  return doc;
}

/**
 * A hub of `fixtures/hubs.ts`: its island (`onIsland`) painted floor over the world's whole
 * chunks, the water off it painted wall, the ground as `hubWorld` makes it (the path's earth);
 * its places, decor, props, figures and arrival as objects. The footprints are the editor's to
 * compute: the hexes under them are painted as the island.
 */
function hubMap(id: typeof TOWN | typeof OUTPOST): MapDocument {
  const view = HUB_VIEWS.get(id)!;
  const world = hubWorld(view, view.arrival);
  const { width, height } = world.terrain;
  const doc = createMap({
    kind: id === TOWN ? "town" : "outpost",
    name: view.name,
    location: id,
    biome: "meadow",
  });
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const island = onIsland(view, { x, y });
      const g = world.terrain.ground![y * width + x]!;
      doc.hexes.set(keyOf({ x, y }), cellOf(island ? FLOOR : WALL, ground(g)));
    }
  }
  for (const p of view.places) {
    put(doc, {
      kind: "place",
      at: p.at,
      target: p.target.kind === "gate" ? "gate" : p.target.service,
      building: p.building as never,
      depth: p.depth ?? 1,
      mirror: false,
    });
  }
  for (const d of view.decor) {
    put(doc, { kind: "decor", at: d.at, building: d.building as never, depth: d.depth ?? 1, mirror: false });
  }
  for (const p of view.props) {
    put(doc, { kind: "prop", at: p.at, sprite: p.sprite, mirror: p.mirror ?? false });
  }
  for (const f of view.figures) put(doc, { kind: "figure", at: f.at, facing: f.facing });
  put(doc, { kind: "arrival", at: view.arrival });
  doc.origin = { x: 0, y: 0, how: "fitted" };
  return doc;
}

const FILES: readonly [string, () => MapDocument][] = [
  ["seed-zone.grimmap.json", seedZone],
  ["town-a.grimmap.json", () => hubMap(TOWN)],
  ["outpost-b.grimmap.json", () => hubMap(OUTPOST)],
];

/** A committed fixture, read back. */
function fixture(name: string): MapDocument {
  const read = loadMap(readFileSync(new URL(name, DIR), "utf8"));
  if ("problem" in read) throw new Error(read.problem);
  return read.doc;
}

/**
 * Plays each tap, again after a stop (a chunk revealed stops a walk), until the walk ends there or
 * goes nowhere: the adventurer's tile after each.
 */
function walk(world: SandboxWorld, taps: readonly Tile[]): Tile[] {
  let state = initialState(world);
  const out: Tile[] = [];
  const here = () => state.world.actors.find((a) => a.id === world.adventurerId)!.tile;
  for (const tile of taps) {
    for (let tries = 0; tries < 4 && (here().x !== tile.x || here().y !== tile.y); tries++) {
      const intent: Intent = { kind: "tile", tile };
      state = applyIntent(state, intent);
      for (let n = 0; n < 500 && state.walking; n++) state = walkStep(state);
    }
    out.push(here());
  }
  return out;
}

describe("the committed fixtures (CLI-09b)", () => {
  it.each(FILES)("%s is what the game's fixture redraws to", (name, build) => {
    const text = saveMap(build(), EDITOR);
    if (process.env.GRIMWORLD_WRITE_FIXTURES === "1") writeFileSync(new URL(name, DIR), text);
    expect(readFileSync(new URL(name, DIR), "utf8")).toBe(text);
    // And it reads back to the same document.
    expect(fixture(name)).toEqual(build());
  });

  it("the seed's zone fits as the seed: origin (0, 0), 3 × 2 chunks, the seed's chunk set", () => {
    const doc = fixture("seed-zone.grimmap.json");
    const best = fitChunks(doc);
    expect(best).toMatchObject({ origin: { x: 0, y: 0 }, width: 3, height: 2, chunks: 5 });
    const fit = fitted(doc);
    if (typeof fit === "string") throw new Error(fit);
    expect(fit.chunkSet).toEqual([0, 1, 2, 15, 16]);
    expect([...fit.masks.keys()]).toEqual([2, 16]);
  });

  it.each(FILES)("%s validates with no error", (name) => {
    const findings = validate(fixture(name));
    expect(findings.filter((f) => f.severity === "error")).toEqual([]);
  });

  it("the game's own anchor of gate 102 is refused by E-5 alone", () => {
    const doc = fixture("seed-zone.grimmap.json");
    for (const [id, o] of doc.objects) {
      if (o.kind === "gate" && o.at.x === GATE_102_EDITOR.x) doc.objects.set(id, { ...o, at: GATE_102_GAME });
    }
    const errors = validate(doc).filter((f) => f.severity === "error");
    expect(errors.map((f) => f.check)).toEqual(["E-5"]);
  });

  it("the zone's preview world is the game's instance: the same terrain, revealed the same", () => {
    const doc = fixture("seed-zone.grimmap.json");
    const frame = frameOf(doc)!;
    const entry = globalTile(0, 105);
    const game = zoneWorld(entry);
    for (const fog of [true, false]) {
      const preview = walkWorld(doc, frame, { start: entry, fog });
      expect(preview.terrain.hidden).toEqual(game.terrain.hidden);
      expect(preview.terrain.ground).toEqual(game.terrain.ground);
      expect(preview.terrain.kinds).toEqual(fog ? game.terrain.kinds : game.terrain.hidden);
      expect(preview.kind).toBeUndefined();
    }
  });

  it("the zone walks in the preview as in the game", () => {
    const doc = fixture("seed-zone.grimmap.json");
    const entry = globalTile(0, 105);
    const preview = walkWorld(doc, frameOf(doc)!, { start: entry, fog: true });
    // The game's world without its runts: the preview has no goblins (§2.8).
    const game = zoneWorld(entry);
    const alone = { ...game, actors: game.actors.filter((a) => a.side === "adventurer") };
    // Each tap within sight of the last: a tap on a hex never seen does nothing (CLI-03n).
    const taps = [
      { x: 5, y: 9 },
      { x: 10, y: 8 },
      { x: 14, y: 9 },
      { x: 18, y: 12 },
    ];
    const there = walk(preview, taps);
    expect(there).toEqual(walk(alone, taps));
    expect(there).toEqual(taps);
  });

  it.each([TOWN, OUTPOST] as const)("hub %i's preview world is hubWorld's", (id) => {
    const view = HUB_VIEWS.get(id)!;
    const doc = fixture(id === TOWN ? "town-a.grimmap.json" : "outpost-b.grimmap.json");
    const game = hubWorld(view, view.arrival);
    const preview = walkWorld(doc, frameOf(doc)!, { start: view.arrival, fog: false });
    expect(preview.terrain.kinds).toEqual(game.terrain.kinds);
    expect(preview.terrain.ground).toEqual(game.terrain.ground);
    expect(preview.kind).toBe(game.kind);
    const shape = (w: SandboxWorld) =>
      (w.structures ?? []).map(({ key: _key, ...s }) => s);
    expect(shape(preview)).toEqual(shape(game));
    // The figures stand where the hub's stand, facing the same way.
    const figures = (w: SandboxWorld) =>
      w.actors.filter((a) => a.id !== w.adventurerId).map((a) => [a.tile, a.facing]);
    expect(figures(preview)).toEqual(figures(game));
  });

  it("the town walks in the preview as in the game", () => {
    const view = HUB_VIEWS.get(TOWN)!;
    const doc = fixture("town-a.grimmap.json");
    const preview = walkWorld(doc, frameOf(doc)!, { start: view.arrival, fog: false });
    const doors = view.places.map((p) => p.at);
    const there = walk(preview, doors);
    expect(there).toEqual(walk(hubWorld(view, view.arrival), doors));
    expect(there).toEqual(doors);
    // A painted door is floor in the document; its building's other hexes are walls only there.
    expect(terrainOf(doc.hexes.get(keyOf(doors[0]!))!)).toBe(FLOOR);
  });
});
