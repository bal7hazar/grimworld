import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import type { Tile } from "../render/view";
import { type Fitted, fitChunks, fitted } from "./fit";
import { loadMap } from "./file";
import {
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  WALL,
  cellOf,
  createMap,
  keyOf,
  nextObjectId,
  sideOf,
} from "./model";
import type { MapObject } from "./objects";
import { type Finding, checkFitted, tally, validate } from "./validate";

/**
 * §5's checks (CLI-09b's acceptance): each check that does not wait for ENG-08's spike has a
 * passing map and a failing one; each ○ check runs as a warning. The passing maps are the
 * committed fixtures (the seed's zone, the town and the outpost, which validate with no error);
 * each failing map is one of them with one change.
 */

function fixture(name: string): MapDocument {
  const read = loadMap(
    readFileSync(new URL(`./fixtures/${name}.grimmap.json`, import.meta.url), "utf8"),
  );
  if ("problem" in read) throw new Error(read.problem);
  return read.doc;
}

const zone = () => fixture("seed-zone");
const town = () => fixture("town-a");

const grass = GROUND_KINDS.indexOf("grass");
const water = GROUND_KINDS.indexOf("water");
const earth = GROUND_KINDS.indexOf("earth");

function set(doc: MapDocument, tile: Tile, terrain: 0 | 1, ground = grass, outside = false) {
  doc.hexes.set(keyOf(tile), cellOf(terrain, ground, outside));
}

function add(doc: MapDocument, object: MapObject): number {
  const id = nextObjectId(doc);
  doc.objects.set(id, object);
  return id;
}

function only<K extends MapObject["kind"]>(doc: MapDocument, kind: K) {
  return [...doc.objects].filter(([, o]) => o.kind === kind) as [
    number,
    Extract<MapObject, { kind: K }>,
  ][];
}

const findings = (doc: MapDocument, check: string): Finding[] =>
  validate(doc).filter((f) => f.check === check);

/** The check fails the map (an error), and only as an error of its own source. */
function fails(doc: MapDocument, check: string): Finding[] {
  const found = findings(doc, check);
  expect(found.length, `${check} fails`).toBeGreaterThan(0);
  for (const f of found) {
    expect(f.severity).toBe("error");
    expect(f.source).toBe(check[0]);
  }
  return found;
}

const passes = (doc: MapDocument, check: string) =>
  expect(findings(doc, check), `${check} passes`).toEqual([]);

/** A floor hex inside the seed's zone, away from its objects: (6, 5) of chunk 0. */
const FLOOR_HEX = { x: 6, y: 5 };
/** A rock inside chunk 0 (the rocks' pattern: `(7x + 11y) mod 9 = 0`). */
const ROCK = { x: 0, y: 0 };

describe("the passing maps", () => {
  it.each(["seed-zone", "town-a", "outpost-b"])("%s has no error", (name) => {
    const all = validate(fixture(name));
    expect(tally(all).errors).toBe(0);
  });

  it("the seed's zone has no finding at all: no warning, no hint", () => {
    expect(validate(zone())).toEqual([]);
  });
});

describe("R checks: ENG-08's content checks for map records", () => {
  it("R-1: width and height in chunks are 1 to 15", () => {
    passes(zone(), "R-1");
    const doc = createMap({ kind: "zone", name: "Long", location: 3, biome: "meadow" });
    for (let x = 0; x < 16 * 15; x++) set(doc, { x, y: 0 }, FLOOR);
    const best = fitChunks(doc);
    if (typeof best === "string") throw new Error(best);
    doc.origin = { ...best.origin, how: "fitted" };
    expect(fails(doc, "R-1")[0]!.message).toContain("16 × 1 chunks");
  });

  it("R-2: the entry's chunk and tile are within the fitted map", () => {
    passes(zone(), "R-2");
    const doc = zone();
    const [[id, entry]] = only(doc, "entry");
    // One hex West of the fitted map, on the ring of void painted around it.
    doc.objects.set(id, { ...entry, at: { x: -1, y: 7 } });
    fails(doc, "R-2");
  });

  it("R-3: a gate's anchor and its entry in the destination are below 225", () => {
    passes(zone(), "R-3");
    const doc = zone();
    const [[id, gate]] = only(doc, "gate");
    doc.objects.set(id, { ...gate, entryTile: 225 });
    fails(doc, "R-3");
    const far = zone();
    const [[gid, g]] = only(far, "gate");
    far.objects.set(gid, { ...g, at: { x: -1, y: 8 } });
    expect(fails(far, "R-3").some((f) => f.message.includes("outside the fitted map"))).toBe(true);
  });

  /** The fitted records hold by construction: they fail only forged. */
  function forged(change: (fit: Fitted) => Fitted): Finding[] {
    const doc = zone();
    const fit = fitted(doc) as Fitted;
    expect(checkFitted(doc, fit)).toEqual([]);
    return checkFitted(doc, change(fit));
  }

  it("R-5: an OUTLINE id's chunk is below 225 (holds by construction)", () => {
    const out = forged((fit) => ({ ...fit, chunkSet: [...fit.chunkSet, 230] }));
    expect(out.map((f) => f.check)).toContain("R-5");
  });

  it("R-7: an outline's mask has no bit above 224 (holds by construction)", () => {
    const out = forged((fit) => {
      const masks = new Map(fit.masks);
      masks.set(2, [...masks.get(2)!, 225]);
      return { ...fit, masks };
    });
    expect(out.map((f) => f.check)).toContain("R-7");
  });

  it("R-10: at most 6 quotas", () => {
    passes(zone(), "R-10");
    const doc = zone();
    doc.meta = {
      ...doc.meta,
      quotas: [...doc.meta.quotas, ...Array(5).fill({ kind: "vein", param: 0, count: 0 })],
    };
    fails(doc, "R-10");
  });

  it("R-11: the chunk set lies within the rectangle (holds by construction)", () => {
    const out = forged((fit) => ({ ...fit, width: 2 }));
    expect(out.map((f) => f.check)).toContain("R-11");
  });

  it("R-13: a quota's count is at most its candidate places", () => {
    passes(zone(), "R-13");
    const doc = zone();
    // The exit's quota counts 3 with its 2 candidates.
    doc.meta = { ...doc.meta, quotas: [{ ...doc.meta.quotas[0]!, count: 3 }, doc.meta.quotas[1]!] };
    const [found] = fails(doc, "R-13");
    expect(found!.message).toContain("counts 3, with 2 candidate places");
    expect(found!.objects).toHaveLength(2);
    // A candidate for a quota the list does not hold.
    const stray = zone();
    add(stray, { kind: "candidate", at: FLOOR_HEX, quota: 4 });
    fails(stray, "R-13");
  });

  it("R-14: spawn points, features and candidates stand on walkable hexes", () => {
    passes(zone(), "R-14");
    // A spawn point on a wall (the task's case).
    const doc = zone();
    const id = add(doc, { kind: "spawn", at: ROCK, template: 2 });
    expect(fails(doc, "R-14")[0]!.objects).toEqual([id]);
    for (const object of [
      { kind: "feature", at: ROCK, feature: "lever" },
      { kind: "candidate", at: ROCK, quota: 0 },
    ] as MapObject[]) {
      const other = zone();
      add(other, object);
      fails(other, "R-14");
    }
  });

  it("R-15: per chunk, at most 2 spawn points and 3 features", () => {
    passes(zone(), "R-15");
    // A third spawn point in one chunk (the task's case): chunk 16 holds one, two more.
    const doc = zone();
    add(doc, { kind: "spawn", at: { x: 20, y: 22 }, template: 1 });
    passes(doc, "R-15");
    add(doc, { kind: "spawn", at: { x: 22, y: 20 }, template: 1 });
    expect(fails(doc, "R-15")[0]!.message).toBe("Chunk 16 holds 3 spawn points: at most 2.");
    const features = zone();
    for (const x of [3, 4, 5, 6]) add(features, { kind: "feature", at: { x, y: 4 }, feature: "node" });
    expect(fails(features, "R-15")[0]!.message).toBe("Chunk 0 holds 4 features: at most 3.");
  });

  it("R-16: corner tiles of an authored chunk may be floor: no check (○, ENG-08's spike)", () => {
    const doc = zone();
    // Chunk 0's four corners as floor.
    for (const t of [ROCK, { x: 14, y: 0 }, { x: 0, y: 14 }, { x: 14, y: 14 }]) set(doc, t, FLOOR);
    expect(validate(doc).filter((f) => f.check.startsWith("R-16"))).toEqual([]);
    expect(tally(validate(doc)).errors).toBe(0);
  });

  it("R-18: every gate anchor is on a walkable hex", () => {
    passes(zone(), "R-18");
    const doc = zone();
    const [[id, gate]] = only(doc, "gate");
    // The rock at (0, 0), on the outline's border (x 0 is its West edge).
    doc.objects.set(id, { ...gate, at: ROCK });
    fails(doc, "R-18");
  });

  it("R-20: each border chunk's mask agrees with the map (holds by construction)", () => {
    const out = forged((fit) => {
      const masks = new Map(fit.masks);
      masks.set(16, masks.get(16)!.slice(1));
      return { ...fit, masks };
    });
    expect(out.map((f) => f.check)).toEqual(["R-20"]);
  });
});

describe("E checks: the editor's own", () => {
  it("E-1: the map is fitted, whole chunks, a town at most 4 × 4", () => {
    passes(zone(), "E-1");
    passes(town(), "E-1");
    const unfitted = zone();
    unfitted.origin = null;
    fails(unfitted, "E-1");
    const empty = createMap({ kind: "town", name: "None", location: 5, biome: "meadow" });
    fails(empty, "E-1");
    const wide = town();
    for (let x = 15; x < 5 * 15; x++) set(wide, { x, y: 0 }, WALL, water);
    expect(fails(wide, "E-1")[0]!.message).toContain("at most 4 × 4");
  });

  it("E-2: the outline is one connected region", () => {
    passes(zone(), "E-2");
    const doc = zone();
    set(doc, { x: 80, y: 80 }, FLOOR);
    fails(doc, "E-2");
    const none = zone();
    for (const [key, cell] of none.hexes) none.hexes.set(key, cell | 8);
    fails(none, "E-2");
  });

  it("E-3: the outline is closed: no inside floor hex touches the unpainted void", () => {
    passes(zone(), "E-3");
    const doc = zone();
    // The ring's hex West of (0, 3): the inside's floor there touches the void.
    doc.hexes.delete(keyOf({ x: -1, y: 3 }));
    expect(fails(doc, "E-3")[0]!.hexes).toContainEqual({ x: 0, y: 3 });
  });

  it("E-4: exactly one entry, on floor inside the outline", () => {
    passes(zone(), "E-4");
    const none = zone();
    none.objects.delete(only(none, "entry")[0]![0]);
    fails(none, "E-4");
    const two = zone();
    add(two, { kind: "entry", at: FLOOR_HEX });
    fails(two, "E-4");
    const wall = zone();
    const [[id, entry]] = only(wall, "entry");
    wall.objects.set(id, { ...entry, at: ROCK });
    fails(wall, "E-4");
  });

  it("E-5: every gate anchor is on the outline's border", () => {
    passes(zone(), "E-5");
    const doc = zone();
    const [, [id, gate]] = only(doc, "gate");
    // The client's own anchor of gate 102, one hex inside.
    doc.objects.set(id, { ...gate, at: { x: 40, y: 7 } });
    expect(fails(doc, "E-5")[0]!.message).toContain("G2");
  });

  /** A floor hex walled in by its six neighbours. */
  function pocket(doc: MapDocument, centre: Tile): void {
    for (let side = 0; side < 6; side++) set(doc, sideOf(centre, side), WALL);
  }

  it("E-6: every gate anchor and candidate is reachable from the entry", () => {
    passes(zone(), "E-6");
    const doc = zone();
    pocket(doc, { x: 38, y: 12 });
    const [found] = fails(doc, "E-6");
    expect(found!.hexes).toEqual([{ x: 38, y: 12 }]);
  });

  it("E-7: every walkable hex inside the outline is reachable (no sealed pocket)", () => {
    passes(zone(), "E-7");
    const doc = zone();
    pocket(doc, FLOOR_HEX);
    expect(fails(doc, "E-7")[0]!.hexes).toEqual([FLOOR_HEX]);
  });

  it("E-10: features, spawn points and candidates are inside the outline", () => {
    passes(zone(), "E-10");
    const doc = zone();
    // A floor hex of the outside, painted: walkable, but outside.
    set(doc, { x: 44, y: 3 }, FLOOR, grass, true);
    add(doc, { kind: "feature", at: { x: 44, y: 3 }, feature: "chest" });
    fails(doc, "E-10");
    passes(doc, "R-14");
  });

  it("E-12: ground agrees with terrain, as a warning", () => {
    passes(zone(), "E-12");
    const doc = zone();
    set(doc, FLOOR_HEX, FLOOR, water);
    set(doc, { x: 7, y: 6 }, WALL, earth);
    const found = findings(doc, "E-12");
    expect(found.map((f) => f.severity)).toEqual(["warning", "warning"]);
  });

  it("E-13: the walkable share against the biome's range, as a hint", () => {
    passes(zone(), "E-13");
    const doc = zone();
    doc.meta = { ...doc.meta, biome: "ruin" };
    const [found] = findings(doc, "E-13");
    expect(found!.severity).toBe("hint");
    expect(found!.message).toMatch(/^Walkable share \d+ % \(ruin 40–50 %\)\.$/);
  });

  it("E-14: one place per service of the hub's list, and one gate", () => {
    passes(town(), "E-14");
    passes(fixture("outpost-b"), "E-14");
    const doc = town();
    const [[id]] = only(doc, "place").filter(([, p]) => p.target === "market");
    doc.objects.delete(id);
    expect(fails(doc, "E-14")[0]!.message).toBe("No place for the market.");
    const twice = town();
    add(twice, { kind: "place", at: { x: 7, y: 9 }, target: "gate", building: "hut", depth: 0, mirror: false });
    expect(fails(twice, "E-14")[0]!.message).toBe("2 places for the gate: one only.");
    // A service the outpost does not hold: a warning.
    const outpost = fixture("outpost-b");
    add(outpost, { kind: "place", at: { x: 4, y: 5 }, target: "smith", building: "hut", depth: 0, mirror: false });
    expect(findings(outpost, "E-14").map((f) => f.severity)).toEqual(["warning"]);
  });

  it("E-15: doors and the arrival are floor; every door is reachable from the arrival", () => {
    passes(town(), "E-15");
    const doc = town();
    const [[id, arrival]] = only(doc, "arrival");
    doc.objects.set(id, { ...arrival, at: { x: 12, y: 3 } });
    expect(fails(doc, "E-15")[0]!.message).toContain("The arrival (12, 3) is not floor");
    const shut = town();
    const [, guild] = only(shut, "place").find(([, p]) => p.target === "guild")!;
    pocket(shut, guild.at);
    expect(fails(shut, "E-15").some((f) => f.message.includes("not reachable"))).toBe(true);
    const none = town();
    none.objects.delete(only(none, "arrival")[0]![0]);
    fails(none, "E-15");
  });

  it("E-16: footprints on land, painted, and apart", () => {
    passes(town(), "E-16");
    const doc = town();
    const [[id, decor]] = only(doc, "decor");
    // The windmill moved onto the castle.
    doc.objects.set(id, { ...decor, at: { x: 5, y: 12 } });
    expect(fails(doc, "E-16")[0]!.message).toContain("overlaps");
    const wet = town();
    add(wet, { kind: "decor", at: { x: 12, y: 3 }, building: "hut", depth: 1, mirror: false });
    expect(fails(wet, "E-16")[0]!.message).toContain("off the land");
  });

  it("E-19: a spawn point carries a template id", () => {
    passes(zone(), "E-19");
    const doc = zone();
    add(doc, { kind: "spawn", at: FLOOR_HEX, template: 0 });
    fails(doc, "E-19");
  });
});

describe("○ checks: warnings until ENG-08's spike", () => {
  const warns = (doc: MapDocument, check: string) => {
    const found = findings(doc, check).filter((f) => f.source === "○");
    expect(found.length, check).toBeGreaterThan(0);
    for (const f of found) expect(f.severity).toBe("warning");
  };

  it("R-12 ○: a quota's count past the zone's members", () => {
    const doc = zone();
    doc.meta = { ...doc.meta, quotas: [{ kind: "exit", param: 0, count: 5000 }] };
    warns(doc, "R-12");
  });

  it("R-15 ○: a candidate counted against a chunk's three objects", () => {
    const doc = zone();
    for (const x of [3, 4]) add(doc, { kind: "feature", at: { x, y: 4 }, feature: "node" });
    for (const x of [5, 6]) add(doc, { kind: "candidate", at: { x, y: 4 }, quota: 0 });
    warns(doc, "R-15");
    expect(findings(doc, "R-15").every((f) => f.source === "○")).toBe(true);
  });

  it("E-17 ○: two neighbouring chunks whose seam has no walkable crossing", () => {
    passes(zone(), "E-17");
    const doc = zone();
    // Walls on both sides of the seam between chunks 15 and 16 (x 14 and 15, y 15 to 29).
    for (let y = 15; y < 30; y++) for (const x of [14, 15]) set(doc, { x, y }, WALL);
    warns(doc, "E-17");
    expect(findings(doc, "E-17")[0]!.message).toContain("Chunks 15 and 16");
  });
});
