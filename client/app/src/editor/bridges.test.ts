import { readFileSync, writeFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import type { Tile } from "../render/view";
import { type Manifest, convert, recordsFile } from "./export/convert";
import { fromExport, readManifest, toExport } from "./export/document";
import * as R from "./export/records";
import { Refused } from "./export/records";
import { loadMap, saveMap } from "./file";
import {
  CHUNK,
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  WALL,
  cellOf,
  createMap,
  groundOfCell,
  keyOf,
  nextObjectId,
  sideOf,
} from "./model";
import type { MapObject } from "./objects";
import { type PackObject, bridgeCopies, bridgeHexes, placedOn, spanned } from "./pack";
import { SIDE } from "./palette";
import { type Finding, validate } from "./validate";
import { townStructures, walkWorld } from "./walkWorld";

/**
 * CLI-09f: bridges in the editor, one level (D-227, ADR-0008). A bridge is two end hexes on land and
 * a deck of one or more hexes over water, all walkable; nothing stands on its ends or deck (R-37).
 * The passing map is the committed fixture `bridge-zone`: a one-chunk meadow with two ponds, a stone
 * bridge running North over a deck of 3 and a covered bridge running West over a deck of 2. Each
 * failing map is that fixture with one change. `GRIMWORLD_WRITE_FIXTURES=1` writes the fixture and
 * its export again (then `prettier --write` them); the records file is the converter's own output:
 *
 *     python3 tools/map-format/convert.py \
 *         client/app/src/editor/fixtures/bridge-zone.export.json \
 *         --manifest tools/map-format/samples/manifest.json \
 *         --out client/app/src/editor/fixtures/bridge-zone.records.json
 */

const DIR = new URL("./fixtures/", import.meta.url);
const SAMPLES = new URL("../../../../tools/map-format/samples/", import.meta.url);
const MANIFEST = readManifest(readFileSync(new URL("manifest.json", SAMPLES), "utf8")) as Manifest;

const grass = GROUND_KINDS.indexOf("grass");
const water = GROUND_KINDS.indexOf("water");

const STONE_SOUTH = { x: 7, y: 3 };
const COVERED_EAST = { x: 3, y: 11 };

function add(doc: MapDocument, object: MapObject): number {
  const id = nextObjectId(doc);
  doc.objects.set(id, object);
  return id;
}

const bridge = (
  at: Tile,
  type: string,
  deck: number,
  run: "north" | "west" = "north",
): Extract<PackObject, { kind: "bridge" }> => ({
  kind: "bridge",
  at,
  type,
  mirror: false,
  run,
  deck,
});

/** A pond under a bridge: its deck and the hexes around the deck, but its ends, as water walls. */
function pond(doc: MapDocument, object: Extract<PackObject, { kind: "bridge" }>): void {
  const hexes = bridgeHexes(object)!;
  const ends = new Set(hexes.ends.map(keyOf));
  for (const t of hexes.deck) {
    for (const h of [t, ...[0, 1, 2, 3, 4, 5].map((s) => sideOf(t, s))]) {
      if (!ends.has(keyOf(h))) doc.hexes.set(keyOf(h), cellOf(WALL, water));
    }
  }
}

/**
 * The fixture: chunk (0, 0) inside the outline, grass floor, one ring of water outside it so that
 * the outline is closed (E-3); two ponds, each crossed by a bridge; the entry South of the stone bridge.
 */
function bridgeZone(): MapDocument {
  const doc = createMap({ kind: "zone", name: "Bridge pond", location: 2, biome: "meadow" });
  doc.meta = { ...doc.meta, region: 1, levelMin: 1, levelMax: 3 };
  for (let y = -1; y <= CHUNK; y++) {
    for (let x = -1; x <= CHUNK; x++) {
      const inside = x >= 0 && y >= 0 && x < CHUNK && y < CHUNK;
      doc.hexes.set(keyOf({ x, y }), inside ? cellOf(FLOOR, grass) : cellOf(WALL, water, true));
    }
  }
  const stone = bridge(STONE_SOUTH, "stone_bridge", 3);
  const covered = bridge(COVERED_EAST, "covered_bridge", 2, "west");
  pond(doc, stone);
  pond(doc, covered);
  // Two hexes South of the stone bridge: the walk's start sees its deck.
  add(doc, { kind: "entry", at: { x: 7, y: 1 } });
  add(doc, stone);
  add(doc, covered);
  doc.origin = { x: 0, y: 0, how: "fitted" };
  return doc;
}

/**
 * A river across the chunk, row 7 and 8, crossed only by the stone bridge: its far bank is reached
 * by the deck alone.
 */
function riverZone(): MapDocument {
  const doc = createMap({ kind: "zone", name: "Bridge river", location: 2, biome: "meadow" });
  doc.meta = { ...doc.meta, region: 1, levelMin: 1, levelMax: 3 };
  for (let y = -1; y <= CHUNK; y++) {
    for (let x = -1; x <= CHUNK; x++) {
      const inside = x >= 0 && y >= 0 && x < CHUNK && y < CHUNK;
      const river = y === 7 || y === 8;
      doc.hexes.set(
        keyOf({ x, y }),
        !inside ? cellOf(WALL, water, true) : river ? cellOf(WALL, water) : cellOf(FLOOR, grass),
      );
    }
  }
  add(doc, { kind: "entry", at: { x: 1, y: 1 } });
  add(doc, bridge({ x: 7, y: 6 }, "stone_bridge", 2));
  doc.origin = { x: 0, y: 0, how: "fitted" };
  return doc;
}

function fixture(): MapDocument {
  const read = loadMap(readFileSync(new URL("bridge-zone.grimmap.json", DIR), "utf8"));
  if ("problem" in read) throw new Error(read.problem);
  return read.doc;
}

/** The fixture's bridges: the stone one (North, deck 3), the covered one (West, deck 2). */
function bridgesOf(doc: MapDocument) {
  const found = [...doc.objects].filter(([, o]) => o.kind === "bridge") as [
    number,
    Extract<PackObject, { kind: "bridge" }>,
  ][];
  return found.map(([id, o]) => ({ id, object: o, ...bridgeHexes(o)! }));
}

const errors = (doc: MapDocument): Finding[] => validate(doc).filter((f) => f.severity === "error");
const findings = (doc: MapDocument, check: string): Finding[] =>
  validate(doc).filter((f) => f.check === check);

function fails(doc: MapDocument, check: string, code?: string): Finding[] {
  const found = findings(doc, check);
  expect(found.length, `${check} fails`).toBeGreaterThan(0);
  for (const f of found) expect(f.severity).toBe("error");
  if (code)
    expect(
      found.some((f) => f.message.includes(`(${code})`)),
      code,
    ).toBe(true);
  return found;
}

const passes = (doc: MapDocument, check: string) =>
  expect(findings(doc, check), `${check} passes`).toEqual([]);

describe("the committed bridge fixture", () => {
  it("is what the builder draws", () => {
    if (process.env.GRIMWORLD_WRITE_FIXTURES === "1") {
      writeFileSync(new URL("bridge-zone.grimmap.json", DIR), saveMap(bridgeZone(), "fixture"));
      const out = toExport(bridgeZone(), MANIFEST, "fixture");
      if ("problem" in out) throw new Error(out.problem);
      writeFileSync(
        new URL("bridge-zone.export.json", DIR),
        `${JSON.stringify(out.file, null, 2)}\n`,
      );
    }
    expect(fixture()).toEqual(bridgeZone());
  });

  it("holds a multi-hex bridge each way: North over 3 deck hexes, West over 2", () => {
    const [stone, covered] = bridgesOf(fixture());
    expect(stone!.deck).toHaveLength(3);
    expect(covered!.deck).toHaveLength(2);
    expect(covered!.deck.every((t) => t.y === COVERED_EAST.y)).toBe(true);
    // One hex line between two land ends: each hex next to the one before.
    for (const b of [stone!, covered!]) {
      const line = [b.ends[0], ...b.deck, b.ends[1]];
      for (let i = 1; i < line.length; i++) {
        const near = [0, 1, 2, 3, 4, 5].some(
          (s) => keyOf(sideOf(line[i - 1]!, s)) === keyOf(line[i]!),
        );
        expect(near, `hex ${i}`).toBe(true);
      }
    }
  });

  it("validates with no error: every bridge check passes", () => {
    const doc = fixture();
    expect(errors(doc)).toEqual([]);
    for (const check of ["R-37", "E-46", "E-47", "E-25", "R-34", "E-6", "E-7"]) passes(doc, check);
    // With the content manifest, the converter's own checks run on its export too.
    expect(validate(doc, MANIFEST).filter((f) => f.severity === "error")).toEqual([]);
  });
});

describe("R-37 widened (bridge: tile taken): nothing on a bridge's ends or deck", () => {
  const cases: [string, (deck: Tile, end: Tile) => MapObject][] = [
    [
      "a feature on the deck",
      (deck) => ({ kind: "feature", at: deck, feature: "chest", param: 0 }),
    ],
    ["a spawn point on an end", (_, end) => ({ kind: "spawn", at: end, template: 1 })],
    ["a character on the deck", (deck) => ({ kind: "npc", at: deck, type: "pawn", facing: 0 })],
    [
      "a prop on an end",
      (_, end) => ({
        kind: "scenery",
        at: end,
        type: "bones",
        variant: 0,
        facing: 0,
        mirror: false,
      }),
    ],
    ["the entry on an end", (_, end) => ({ kind: "entry", at: end })],
  ];
  it.each(cases)("%s fails", (_, make) => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    const object = make(stone!.deck[1]!, stone!.ends[1]);
    if (object.kind === "entry") doc.objects.delete(1);
    add(doc, object);
    fails(doc, "R-37", "bridge: tile taken");
  });

  it("a building whose footprint takes an end fails", () => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    const end = stone!.ends[1];
    add(doc, { kind: "building", at: end, type: "house1", depth: 0, door: "0,0", footprint: "" });
    fails(doc, "R-37", "bridge: tile taken");
  });

  it("an object beside the bridge passes", () => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    const end = stone!.ends[1];
    add(doc, { kind: "npc", at: sideOf(sideOf(end, 0), 0), type: "pawn", facing: 0 });
    passes(doc, "R-37");
  });
});

describe("E-46 (export: deck outside the zone)", () => {
  it("a deck hex outside the outline fails", () => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    doc.hexes.set(keyOf(stone!.deck[0]!), cellOf(WALL, water, true));
    fails(doc, "E-46", "export: deck outside the zone");
  });

  it("a deck hex left unpainted fails", () => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    doc.hexes.delete(keyOf(stone!.deck[2]!));
    fails(doc, "E-46", "export: deck outside the zone");
  });

  it("on a town, a deck over painted water passes", () => {
    const doc = fixture();
    doc.meta = { ...doc.meta, kind: "town", biome: null };
    passes(doc, "E-46");
  });
});

describe("E-47 (export: deck blocked), and E-25: the deck over water", () => {
  it("a blocking prop on the deck fails", () => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    add(doc, {
      kind: "scenery",
      at: stone!.deck[1]!,
      type: "water_rock",
      variant: 0,
      facing: 0,
      mirror: false,
    });
    fails(doc, "E-47", "export: deck blocked");
  });

  it("a building's footprint on the deck fails", () => {
    const doc = fixture();
    const [, covered] = bridgesOf(doc);
    const deck = covered!.deck[0]!;
    // The door stays walkable: the footprint's other hexes block.
    add(doc, {
      kind: "building",
      at: deck,
      type: "barracks",
      depth: 1,
      door: "0,0",
      footprint: "",
    });
    fails(doc, "E-47", "export: deck blocked");
  });

  it("a deck hex on land fails", () => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    doc.hexes.set(keyOf(stone!.deck[1]!), cellOf(FLOOR, grass));
    const found = fails(doc, "E-25");
    expect(found[0]!.message).toContain("not over water");
  });
});

describe("R-34 (bridge: end not floor): the ends walkable land", () => {
  it("an end painted as a wall fails", () => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    doc.hexes.set(keyOf(stone!.ends[0]), cellOf(WALL, grass));
    fails(doc, "R-34", "bridge: end not floor");
  });

  it("an end in the water fails", () => {
    const doc = fixture();
    const [, covered] = bridgesOf(doc);
    doc.hexes.set(keyOf(covered!.ends[1]), cellOf(WALL, water));
    fails(doc, "R-34", "bridge: end not floor");
  });

  it("an end under a blocking prop fails", () => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    add(doc, {
      kind: "scenery",
      at: stone!.ends[0],
      type: "rock",
      variant: 0,
      facing: 0,
      mirror: false,
    });
    fails(doc, "R-34", "bridge: end not floor");
  });
});

describe("the deck is walkable (ADR-0008 rule 1)", () => {
  it("a river crossed by the bridge alone: every hex reachable from the entry (E-7 passes)", () => {
    const doc = riverZone();
    expect(errors(doc)).toEqual([]);
  });

  it("the same river without its bridge: the far bank is sealed (E-7 fails)", () => {
    const doc = riverZone();
    doc.objects.delete(2);
    fails(doc, "E-7");
  });

  it("the preview walk's world: the deck is floor, its ground still water", () => {
    const doc = fixture();
    const frame = { x0: 0, y0: 0, width: 1, height: 1 };
    const world = walkWorld(doc, frame, { start: { x: 7, y: 1 }, fog: false });
    const [stone, covered] = bridgesOf(doc);
    for (const t of [...stone!.deck, ...covered!.deck]) {
      const i = t.y * CHUNK + t.x;
      expect(world.terrain.hidden[i], `(${t.x}, ${t.y})`).toBe("floor");
      expect(world.terrain.ground![i]).toBe("water");
    }
    // The pond around the deck stays a wall.
    const decks = new Set(stone!.deck.map(keyOf));
    const beside = [0, 1, 2, 3, 4, 5]
      .map((side) => sideOf(stone!.deck[1]!, side))
      .find((t) => !decks.has(keyOf(t)))!;
    expect(world.terrain.hidden[beside.y * CHUNK + beside.x]).toBe("wall");
  });

  it("the converter's port, as tools/map-format's (ENG-09), writes the deck walkable: P-1 holds", () => {
    const out = toExport(riverZone(), MANIFEST, "fixture");
    if ("problem" in out) throw new Error(out.problem);
    const verdict = convert(out.file, MANIFEST);
    if (verdict instanceof Refused) throw verdict;
    // The deck's two hexes, painted water walls, are floor in the chunk's record.
    const chunk = verdict.zone!.chunks.get(0)!;
    const [deck] = bridgesOf(riverZone());
    for (const t of deck!.deck) expect(R.has(chunk.walls, t.y * CHUNK + t.x), keyOf(t)).toBe(false);
    expect(validate(riverZone(), MANIFEST).filter((f) => f.severity === "error")).toEqual([]);
  });
});

describe("drawn with the pack's art, repeated along the deck", () => {
  it.each([
    [1, [0]],
    [2, [0, 1]],
    [3, [0, 2]],
    [4, [0, 2, 3]],
    [5, [0, 2, 4]],
  ])("a deck of %i: the sprite at the line's hexes %j", (deck, at) => {
    const b = bridge(STONE_SOUTH, "stone_bridge", deck);
    const hexes = bridgeHexes(b)!;
    const line = [hexes.ends[0], ...hexes.deck, hexes.ends[1]];
    expect(bridgeCopies(b)).toEqual(at.map((k) => line[k]));
  });

  it("the view: one structure a copy, the first keeping the object's key", () => {
    const doc = fixture();
    const keys = townStructures(doc).map((s) => s.key);
    expect(keys).toEqual(["bridge:2", "bridge:2:1", "bridge:3", "bridge:3:1"]);
    expect(townStructures(doc).every((s) => s.covers.length === 0)).toBe(true);
  });
});

describe("placed across the water", () => {
  const isWater = (doc: MapDocument) => (t: Tile) => {
    const cell = doc.hexes.get(keyOf(t));
    return cell === undefined ? null : groundOfCell(cell) === water;
  };

  it("on land facing a pond: the deck spans the water to the far bank", () => {
    const doc = fixture();
    const placed = placedOn(doc, bridge(STONE_SOUTH, "stone_bridge", 1));
    expect(placed.deck).toBe(3);
    expect(isWater(doc)(STONE_SOUTH)).toBe(false);
  });

  it("on water, or with no water ahead: the deck as the kind gives it", () => {
    const doc = fixture();
    const [stone] = bridgesOf(doc);
    expect(placedOn(doc, bridge(stone!.deck[0]!, "stone_bridge", 1)).deck).toBe(1);
    // Land ahead: nothing to span.
    expect(placedOn(doc, bridge({ x: 7, y: 13 }, "stone_bridge", 1)).deck).toBe(1);
  });
});

describe("saved and loaded, and the export", () => {
  it("a file keeps the deck's length", () => {
    const doc = fixture();
    const read = loadMap(saveMap(doc));
    if ("problem" in read) throw new Error(read.problem);
    expect(bridgesOf(read.doc).map((b) => b.object.deck)).toEqual([3, 2]);
  });

  it("an older file, a bridge without its deck's length, opens with CLI-09e's one-hex deck", () => {
    const file = JSON.parse(saveMap(fixture()));
    for (const o of file.objects) if (o.kind === "bridge") delete o.deck;
    const read = loadMap(JSON.stringify(file));
    if ("problem" in read) throw new Error(read.problem);
    const [stone] = bridgesOf(read.doc);
    expect(stone!.object.deck).toBe(1);
    expect(stone!.deck).toHaveLength(1);
  });

  it("exports to the committed export, which opens to the same map", () => {
    const out = toExport(fixture(), MANIFEST, "fixture");
    if ("problem" in out) throw new Error(out.problem);
    const committed = JSON.parse(readFileSync(new URL("bridge-zone.export.json", DIR), "utf8"));
    expect(out.file).toEqual(committed);
    expect(out.file.bridges).toEqual([
      expect.objectContaining({ kind: "stone_bridge" }),
      expect.objectContaining({ kind: "covered_bridge" }),
    ]);
    expect(out.file.bridges![0]!.deck).toHaveLength(3);
    const back = fromExport(committed, MANIFEST);
    if ("problem" in back) throw new Error(back.problem);
    expect(bridgesOf(back.doc).map((b) => b.object)).toEqual(
      bridgesOf(fixture()).map((b) => b.object),
    );
  });

  it("the converter's port writes the records convert.py wrote, felt for felt", () => {
    const committed = JSON.parse(readFileSync(new URL("bridge-zone.export.json", DIR), "utf8"));
    const out = convert(committed, MANIFEST);
    if (out instanceof Refused) throw out;
    const python = JSON.parse(readFileSync(new URL("bridge-zone.records.json", DIR), "utf8"));
    expect(JSON.parse(recordsFile(out.writes, "bridge-zone.export.json"))).toEqual(python);
    expect(python.writes.filter((w: { kind: string }) => w.kind === "BRIDGE")).toHaveLength(2);
  });
});

/**
 * A deck along one line (CLI-09h, the review of CLI-09f): the line from the southern end to the
 * northern end is a chain of neighbours in the six hex directions, whatever the row's parity, the
 * sign of the coordinates and the run's mirror; the sprite's copies and the span follow it.
 */
describe("a deck along one line", () => {
  // Even and odd rows, positive and negative coordinates (odd-r: the steps differ by row).
  const STARTS: readonly Tile[] = [
    { x: 6, y: 4 },
    { x: 6, y: 5 },
    { x: -6, y: -4 },
    { x: -7, y: -5 },
    { x: 0, y: -1 },
    { x: -1, y: 0 },
  ];
  const SIDES = [0, 1, 2, 3, 4, 5];
  const opposite = (side: number) => (side + 3) % 6;

  /** The side from `a` to `b`, or null when they are not neighbours. */
  const sideBetween = (a: Tile, b: Tile): number | null => {
    const side = SIDES.find((s) => {
      const t = sideOf(a, s);
      return t.x === b.x && t.y === b.y;
    });
    return side ?? null;
  };

  it.each(STARTS)(
    "in all six directions from (%j): a line of hexes steps back along the opposite",
    (...args) => {
      const start = args[0] as Tile;
      for (const side of SIDES) {
        let tile = start;
        const walked: Tile[] = [tile];
        for (let i = 0; i < 5; i++) {
          tile = sideOf(tile, side);
          walked.push(tile);
        }
        // Six distinct directions: six distinct first steps.
        expect(sideBetween(walked[0]!, walked[1]!)).toBe(side);
        // Back along the opposite side to the start.
        for (let i = walked.length - 1; i > 0; i--) {
          expect(sideBetween(walked[i]!, walked[i - 1]!)).toBe(opposite(side));
        }
      }
      expect(new Set(SIDES.map((s) => keyOf(sideOf(start, s)))).size).toBe(6);
    },
  );

  const RUNS = [
    { run: "north", mirror: false, sides: [SIDE.northEast, SIDE.northWest] },
    { run: "north", mirror: true, sides: [SIDE.northWest, SIDE.northEast] },
    { run: "west", mirror: false, sides: [SIDE.west, SIDE.west] },
    { run: "west", mirror: true, sides: [SIDE.east, SIDE.east] },
  ] as const;

  for (const { run, mirror, sides } of RUNS) {
    const name = `${run}${mirror ? ", mirrored" : ""}`;

    it(`a bridge running ${name}: one chain of neighbours from the end, every deck length, every start`, () => {
      for (const start of STARTS) {
        for (let deck = 1; deck <= 5; deck++) {
          const b = { ...bridge(start, "stone_bridge", deck, run), mirror };
          const hexes = bridgeHexes(b)!;
          const line = [hexes.ends[0], ...hexes.deck, hexes.ends[1]];
          expect(line).toHaveLength(deck + 2);
          expect(hexes.ends[0]).toEqual(start);
          expect(new Set(line.map(keyOf)).size).toBe(line.length);
          line.slice(1).forEach((t, i) => {
            // The run's own side, alternating for the zig-zag that keeps the ends in one column.
            expect(
              sideBetween(line[i]!, t),
              `${name} from (${start.x}, ${start.y}), step ${i}`,
            ).toBe(sides[i % 2]);
          });
        }
      }
    });

    it(`a bridge running ${name}: the sprite's copies stand on the line, two hexes apart, the last on the end's neighbour`, () => {
      for (const start of STARTS) {
        for (let deck = 1; deck <= 5; deck++) {
          const b = { ...bridge(start, "stone_bridge", deck, run), mirror };
          const hexes = bridgeHexes(b)!;
          const line = [hexes.ends[0], ...hexes.deck, hexes.ends[1]];
          const copies = bridgeCopies(b);
          const at = copies.map((c) => line.findIndex((t) => keyOf(t) === keyOf(c)));
          expect(at.every((k) => k >= 0)).toBe(true);
          expect(at[0]).toBe(0);
          expect(at[at.length - 1]).toBe(line.length - 3);
          // Each copy past the one before, by one or two hexes (review t-0154).
          at.slice(1).forEach((k, i) => {
            expect(k - at[i]!).toBeGreaterThan(0);
            expect(k - at[i]!).toBeLessThanOrEqual(2);
          });
        }
      }
    });

    it(`a bridge running ${name}: placed on land, it spans the water ahead to the far bank`, () => {
      for (const start of STARTS) {
        const reference = { ...bridge(start, "stone_bridge", 3, run), mirror };
        const hexes = bridgeHexes(reference)!;
        const wet = new Set(hexes.deck.map(keyOf));
        const isWater = (t: Tile): boolean => wet.has(keyOf(t));
        const spannedOver = spanned({ ...reference, deck: 1 }, isWater);
        expect(spannedOver.deck).toBe(3);
        // No far bank: land never comes back within reach, so nothing is spanned.
        const endless = spanned({ ...reference, deck: 1 }, (t) => keyOf(t) !== keyOf(start));
        expect(endless.deck).toBe(1);
      }
    });
  }
});
