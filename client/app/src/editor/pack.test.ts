import { describe, expect, it } from "vitest";
import type { Tile } from "../render/view";
import { loadMap, saveMap } from "./file";
import {
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  WALL,
  cellOf,
  createMap,
  keyOf,
  nextObjectId,
} from "./model";
import { KINDS, type MapObject, TOWN_OBJECTS, ZONE_OBJECTS, kindOf, newObject } from "./objects";
import {
  PACK_KINDS,
  PACK_KIND_OF,
  type PackObject,
  buildingFootprint,
  doorOf,
  doorOffset,
  propSprite,
  recordFor,
} from "./pack";
import { npcSprite, packSprites } from "./packDraw";
import { BRIDGES, BUILDINGS, NPCS, PROPS, bridgeAt, doorChoices, footprintAt } from "./palette";
import { EditorSession } from "./session";
import { type Finding, validate } from "./validate";
import { coversOf, townStructures, walkWorld } from "./walkWorld";

/**
 * CLI-09e part 2: the palette's buildings, characters, props and bridges as objects of the map —
 * their rows and records, placing, moving, deleting, undo, R and H, the checks E-16 (a zone's
 * footprints), E-20 to E-23 with a passing and a failing map each, and the file's round trip.
 */

const zone = () => createMap({ kind: "zone", name: "Pack", location: 2, biome: "meadow" });
const town = () => createMap({ kind: "town", name: "Town", location: 1, biome: "meadow" });

const grass = GROUND_KINDS.indexOf("grass");
const water = GROUND_KINDS.indexOf("water");

/** A floor block painted from (0, 0) to (w - 1, h - 1), straight on the document. */
function block(doc: MapDocument, w = 30, h = 20): MapDocument {
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) doc.hexes.set(keyOf({ x, y }), cellOf(FLOOR, grass, false));
  }
  return doc;
}

const click = (s: EditorSession, tile: Tile) => {
  s.strokeStart(tile, { erase: false, alt: false, shift: false });
  s.strokeEnd();
};

const drag = (s: EditorSession, from: Tile, to: Tile) => {
  s.strokeStart(from, { erase: false, alt: false, shift: false });
  s.strokeMove([to]);
  s.strokeEnd();
};

function add(doc: MapDocument, object: MapObject): number {
  const id = nextObjectId(doc);
  doc.objects.set(id, object);
  return id;
}

const findings = (doc: MapDocument, check: string): Finding[] =>
  validate(doc).filter((f) => f.check === check);

function fails(doc: MapDocument, check: string): Finding[] {
  const found = findings(doc, check);
  expect(found.length, `${check} fails`).toBeGreaterThan(0);
  for (const f of found) expect(f.severity).toBe("error");
  return found;
}

const passes = (doc: MapDocument, check: string) =>
  expect(findings(doc, check), `${check} passes`).toEqual([]);

const building = (at: Tile, type = "house1", door = "0,0", depth = 1): PackObject => ({
  kind: "building",
  at,
  type,
  depth,
  door,
});
const npc = (at: Tile, type = "pawn", facing = 0): PackObject => ({
  kind: "npc",
  at,
  type,
  facing,
});
const prop = (at: Tile, type = "tree", variant = 0, mirror = false, facing = 0): PackObject => ({
  kind: "scenery",
  at,
  type,
  variant,
  facing,
  mirror,
});
const bridge = (at: Tile, type = "stone_bridge", mirror = false): PackObject => ({
  kind: "bridge",
  at,
  type,
  mirror,
});

describe("the pack's rows (CLI-09e part 2)", () => {
  it("each pack kind has a row, on zones and towns alike, and each palette category places one", () => {
    for (const kind of PACK_KINDS) {
      expect(KINDS[kind].map).toBe("both");
      expect(ZONE_OBJECTS).toContain(kind);
      expect(TOWN_OBJECTS).toContain(kind);
      expect(KINDS[kind].record).toBeDefined();
    }
    expect(Object.values(PACK_KIND_OF).sort()).toEqual([...PACK_KINDS].sort());
  });

  it("a choice's kind id is kept; a missing one is the category's first", () => {
    expect(newObject({ kind: "building", type: "castle" }, { x: 1, y: 2 })).toEqual(
      building({ x: 1, y: 2 }, "castle"),
    );
    expect(newObject({ kind: "npc" }, { x: 0, y: 0 })).toMatchObject({ type: NPCS[0]!.id });
    expect(newObject({ kind: "scenery" }, { x: 0, y: 0 })).toMatchObject({ type: PROPS[0]!.id });
    expect(newObject({ kind: "bridge" }, { x: 0, y: 0 })).toMatchObject({ type: BRIDGES[0]!.id });
  });

  it("a building's record: kind, footprint, anchor, door on the border; unwalkable but its door", () => {
    const castle = BUILDINGS.find((k) => k.id === "castle")!;
    const at = { x: 10, y: 4 };
    const o = building(at, "castle");
    const record = recordFor(o);
    expect(record).toEqual({
      category: "building",
      record: { kind: "castle", footprint: footprintAt(castle, at, 1), anchor: at, door: at },
    });
    expect(coversOf(o)).toEqual(footprintAt(castle, at, 1).filter((t) => t.x !== 10 || t.y !== 4));
    const side = doorChoices(footprintAt(castle, at, 1))[1]!;
    const moved = { ...o, door: doorOffset(at, side) } as PackObject;
    expect(doorOf(moved as Extract<PackObject, { kind: "building" }>)).toEqual(side);
    expect(recordFor(moved)).toMatchObject({ record: { door: side } });
    expect(coversOf(moved)).toContainEqual(at);
    expect(coversOf(moved)).not.toContainEqual(side);
  });

  it("a character's record: its template, hex and facing; it covers nothing", () => {
    const o = npc({ x: 3, y: 3 }, "lancer", 4);
    expect(recordFor(o)).toEqual({
      category: "npc",
      record: { template: "lancer", hex: { x: 3, y: 3 }, facing: 4 },
    });
    expect(coversOf(o)).toEqual([]);
    // Drawn at its idle frame 0, mirrored on the West facings.
    expect(npcSprite("lancer", o.at, 4)).toEqual({
      sprite: "npc_lancer",
      animation: "idle",
      at: o.at,
      mirror: true,
    });
    expect(npcSprite("lancer", o.at, 0)!.mirror).toBe(false);
  });

  it("a prop's record: variant and flip for a flip prop, facing for the cannon; a blocking one covers its hex", () => {
    const tree = prop({ x: 2, y: 2 }, "tree", 2, true);
    expect(recordFor(tree)).toEqual({
      category: "prop",
      record: { kind: "tree", hex: { x: 2, y: 2 }, variant: 2, flip: true },
    });
    expect(coversOf(tree)).toEqual([{ x: 2, y: 2 }]);
    expect(propSprite(tree as Extract<PackObject, { kind: "scenery" }>)).toEqual({
      sprite: "tree3",
      mirror: true,
    });
    const bush = prop({ x: 2, y: 2 }, "bush");
    expect(coversOf(bush)).toEqual([]);
    const gold = prop({ x: 1, y: 1 }, "gold");
    // One sprite: no variant written; no flip when false.
    expect(recordFor(gold)).toEqual({
      category: "prop",
      record: { kind: "gold", hex: { x: 1, y: 1 } },
    });
    const cannon = prop({ x: 4, y: 4 }, "cannon", 0, false, 3);
    expect(recordFor(cannon)).toEqual({
      category: "prop",
      record: { kind: "cannon", hex: { x: 4, y: 4 }, facing: 3 },
    });
    // West: the East sprite mirrored, by the look itself.
    expect(kindOf(cannon).look!(cannon)).toMatchObject({ sprite: "cannon_right", mirror: true });
  });

  it("a bridge's record: its deck and its two ends from the southern end; it covers nothing", () => {
    const kind = BRIDGES[0]!;
    const o = bridge({ x: 5, y: 5 }, kind.id, true);
    const { deck, ends } = bridgeAt(kind, { x: 5, y: 5 }, true);
    expect(recordFor(o)).toEqual({ category: "bridge", record: { kind: kind.id, deck, ends } });
    expect(coversOf(o)).toEqual([]);
  });

  it("the renderer draws a town's pack buildings, props and bridges; the overlay its characters", () => {
    const doc = block(town());
    add(doc, building({ x: 10, y: 4 }, "tower"));
    add(doc, prop({ x: 2, y: 2 }, "rock", 1, true));
    add(doc, bridge({ x: 20, y: 2 }));
    add(doc, npc({ x: 3, y: 8 }, "pawn", 2));
    const structures = townStructures(doc);
    expect(structures.map((s) => [s.kind, s.sprite, s.mirror ?? false])).toEqual([
      ["building", "tower", false],
      ["prop", "rock2", true],
      ["building", "stone_bridge", false],
    ]);
    expect(packSprites(doc, false)).toEqual([
      { sprite: "npc_pawn", animation: "idle", at: { x: 3, y: 8 }, mirror: true },
    ]);
    // A zone's view sends no structure: the overlay draws them all.
    expect(packSprites(doc, true).map((s) => s.sprite)).toEqual([
      "tower",
      "rock2",
      "stone_bridge",
      "npc_pawn",
    ]);
  });

  it("the walk's world of a town makes walls of a building's footprint but its door", () => {
    const doc = block(town());
    add(doc, building({ x: 10, y: 4 }, "tower"));
    const world = walkWorld(
      doc,
      { x0: 0, y0: 0, width: 2, height: 2 },
      { start: { x: 1, y: 1 }, fog: false },
    );
    const at = (t: Tile) => world.terrain.hidden[t.y * world.terrain.width + t.x];
    expect(at({ x: 10, y: 4 })).toBe("floor");
    for (const t of buildingFootprint(building({ x: 10, y: 4 }, "tower") as never)) {
      if (t.x !== 10 || t.y !== 4) expect(at(t)).toBe("wall");
    }
  });
});

describe("placing the pack (CLI-09e part 2)", () => {
  it.each([
    ["zone", zone],
    ["town", town],
  ] as const)("on a %s: place, move, delete, each one step of the history", (_, make) => {
    const s = new EditorSession(block(make()));
    s.choosePlace({ kind: "building", type: "barracks" });
    click(s, { x: 10, y: 4 });
    s.choosePlace({ kind: "npc", type: "monk" });
    click(s, { x: 4, y: 8 });
    s.choosePlace({ kind: "scenery", type: "bush" });
    click(s, { x: 2, y: 2 });
    s.choosePlace({ kind: "bridge", type: "covered_bridge" });
    click(s, { x: 20, y: 2 });
    const kinds = () => [...s.doc.objects].sort(([a], [b]) => a - b).map(([, o]) => o.kind);
    expect(kinds()).toEqual(["building", "npc", "scenery", "bridge"]);
    // The last placed is selected; move it.
    s.armTool("select");
    drag(s, { x: 20, y: 2 }, { x: 22, y: 6 });
    const moved = [...s.doc.objects.values()].at(-1)!;
    expect(moved).toEqual(bridge({ x: 22, y: 6 }, "covered_bridge"));
    s.undo();
    expect([...s.doc.objects.values()].at(-1)!.at).toEqual({ x: 20, y: 2 });
    // Delete the character, then undo it back.
    click(s, { x: 4, y: 8 });
    s.deleteSelection();
    expect(kinds()).toEqual(["building", "scenery", "bridge"]);
    s.undo();
    expect(kinds()).toEqual(["building", "npc", "scenery", "bridge"]);
    for (let i = 0; i < 4; i++) s.undo();
    expect(kinds()).toEqual([]);
    s.redo();
    expect(kinds()).toEqual(["building"]);
  });

  it("a placement whose record cannot be written is refused, and says why", () => {
    const s = new EditorSession(zone());
    s.choosePlace({ kind: "bridge" });
    click(s, { x: 0, y: 32767 });
    expect(s.doc.objects.size).toBe(0);
    expect(s.said).toContain("past the plane's bound");
  });

  it("R turns: a character and the cannon a facing, a prop its variant, a building its door", () => {
    const s = new EditorSession(block(zone()));
    s.choosePlace({ kind: "npc", type: "pawn" });
    click(s, { x: 4, y: 4 });
    s.turn();
    s.turn();
    expect([...s.doc.objects.values()][0]).toMatchObject({ facing: 2 });
    for (let i = 0; i < 4; i++) s.turn();
    expect([...s.doc.objects.values()][0]).toMatchObject({ facing: 0 });
    s.undo();
    expect([...s.doc.objects.values()][0]).toMatchObject({ facing: 5 });

    s.choosePlace({ kind: "scenery", type: "cannon" });
    click(s, { x: 6, y: 6 });
    s.turn();
    expect([...s.doc.objects.values()][1]).toMatchObject({ facing: 1, variant: 0 });

    s.choosePlace({ kind: "scenery", type: "rock" });
    click(s, { x: 8, y: 8 });
    for (let i = 0; i < 5; i++) s.turn();
    // Four rocks: the fifth turn is the second again.
    expect([...s.doc.objects.values()][2]).toMatchObject({ variant: 1 });
    s.mirror();
    expect([...s.doc.objects.values()][2]).toMatchObject({ mirror: true });

    s.choosePlace({ kind: "building", type: "castle" });
    click(s, { x: 14, y: 4 });
    const castle = () =>
      [...s.doc.objects.values()][3] as Extract<PackObject, { kind: "building" }>;
    const choices = doorChoices(buildingFootprint(castle()));
    // The anchor is the first door, on the border; R takes the next hex of the border.
    const i = choices.findIndex((t) => t.x === 14 && t.y === 4);
    expect(i).toBeGreaterThanOrEqual(0);
    s.turn();
    expect(doorOf(castle())).toEqual(choices[(i + 1) % choices.length]);

    s.choosePlace({ kind: "scenery", type: "gold" });
    click(s, { x: 2, y: 12 });
    s.turn();
    expect(s.said).toContain("Turn: select");
  });
});

describe("the pack's checks (CLI-09e part 2)", () => {
  it("E-16 on a zone: a building's footprint on land and apart from the others", () => {
    const doc = block(zone());
    add(doc, building({ x: 5, y: 4 }, "house1"));
    add(doc, building({ x: 15, y: 4 }, "house2"));
    passes(doc, "E-16");
    const near = block(zone());
    add(near, building({ x: 5, y: 4 }, "castle"));
    add(near, building({ x: 6, y: 4 }, "house2"));
    expect(fails(near, "E-16")[0]!.message).toContain("overlaps");
    const wet = block(zone());
    for (let x = 0; x < 30; x++) wet.hexes.set(keyOf({ x, y: 5 }), cellOf(WALL, water, false));
    add(wet, building({ x: 5, y: 4 }, "house1"));
    expect(fails(wet, "E-16")[0]!.message).toContain("off the land");
  });

  it("E-20: a building's door on its footprint's border and walkable", () => {
    const doc = block(town());
    add(doc, building({ x: 10, y: 4 }));
    passes(doc, "E-20");
    // Fail: a wall under the door. Fix: the door on another border hex.
    const walled = block(town());
    const id = add(walled, building({ x: 10, y: 4 }));
    walled.hexes.set(keyOf({ x: 10, y: 4 }), cellOf(WALL, grass, false));
    expect(fails(walled, "E-20")[0]!.message).toContain("is not walkable");
    const o = walled.objects.get(id) as Extract<PackObject, { kind: "building" }>;
    const other = doorChoices(buildingFootprint(o)).find((t) => t.x !== 10 || t.y !== 4)!;
    walled.objects.set(id, { ...o, door: doorOffset(o.at, other) });
    passes(walled, "E-20");
    // A blocking prop on the door shuts it.
    const shut = block(town());
    add(shut, building({ x: 10, y: 4 }));
    add(shut, prop({ x: 10, y: 4 }, "rock"));
    fails(shut, "E-20");
    // A door inside the footprint (a castle three rows deep): off its border.
    const deep = block(town());
    const castle = building({ x: 10, y: 4 }, "castle", "0,0", 2) as Extract<
      PackObject,
      { kind: "building" }
    >;
    const feet = buildingFootprint(castle);
    const border = doorChoices(feet);
    const inner = feet.find((t) => !border.some((b) => b.x === t.x && b.y === t.y))!;
    add(deep, { ...castle, door: doorOffset(castle.at, inner) });
    expect(fails(deep, "E-20")[0]!.message).toContain("not on its footprint's border");
  });

  it("E-21: a character on a walkable hex", () => {
    const doc = block(zone());
    add(doc, npc({ x: 4, y: 4 }));
    add(doc, prop({ x: 4, y: 6 }, "bush"));
    add(doc, npc({ x: 4, y: 6 }, "sheep"));
    passes(doc, "E-21");
    const wall = block(zone());
    wall.hexes.set(keyOf({ x: 4, y: 4 }), cellOf(WALL, grass, false));
    add(wall, npc({ x: 4, y: 4 }));
    fails(wall, "E-21");
    const onRock = block(zone());
    add(onRock, prop({ x: 4, y: 4 }, "rock"));
    add(onRock, npc({ x: 4, y: 4 }));
    fails(onRock, "E-21");
    const inside = block(zone());
    add(inside, building({ x: 10, y: 4 }, "castle"));
    add(inside, npc({ x: 10, y: 5 }));
    fails(inside, "E-21");
    const off = zone();
    add(off, npc({ x: 4, y: 4 }));
    fails(off, "E-21");
  });

  it("E-22: a prop on a painted hex", () => {
    const doc = block(zone());
    add(doc, prop({ x: 4, y: 4 }));
    passes(doc, "E-22");
    const off = block(zone());
    add(off, prop({ x: 40, y: 4 }));
    fails(off, "E-22");
  });

  it("E-23: a record that cannot be written (an unknown kind, a variant, a depth out of range)", () => {
    const doc = block(zone());
    add(doc, prop({ x: 4, y: 4 }, "tree", 3));
    add(doc, building({ x: 10, y: 4 }, "tower", "0,0", 8));
    passes(doc, "E-23");
    const bad = block(zone());
    add(bad, prop({ x: 4, y: 4 }, "tree", 4));
    add(bad, npc({ x: 6, y: 6 }, "dragon"));
    add(bad, building({ x: 10, y: 4 }, "tower", "0,0", 9));
    expect(fails(bad, "E-23").map((f) => f.message)).toEqual([
      "Pack prop tree (4, 4): tree has no variant 4.",
      "Character dragon (6, 6): no kind dragon.",
      "Building tower (10, 4): depth 9 is not 0 to 8.",
    ]);
  });
});

describe("the pack in the file (CLI-09e part 2)", () => {
  it.each([
    ["zone", zone],
    ["town", town],
  ] as const)("a %s's pack objects survive save → load, in placing order", (_, make) => {
    const doc = block(make());
    add(doc, building({ x: 10, y: 4 }, "castle", "1,0", 2));
    add(doc, npc({ x: 4, y: 8 }, "troll", 5));
    add(doc, prop({ x: 2, y: 2 }, "cannon", 0, false, 3));
    add(doc, prop({ x: 3, y: 2 }, "bones", 2, true));
    add(doc, bridge({ x: 20, y: 2 }, "covered_bridge", true));
    const text = saveMap(doc);
    const read = loadMap(text);
    if ("problem" in read) throw new Error(read.problem);
    expect([...read.doc.objects.values()]).toEqual([...doc.objects.values()]);
    expect(saveMap(read.doc)).toBe(text);
    // The file's object: its kind, its hex, then its fields.
    expect(JSON.parse(text).objects[0]).toEqual({
      kind: "building",
      x: 10,
      y: 4,
      type: "castle",
      depth: 2,
      door: "1,0",
    });
  });

  it("a file without pack objects still opens; a pack object with a field missing is refused", () => {
    const doc = block(zone());
    const plain = loadMap(saveMap(doc));
    expect("problem" in plain).toBe(false);
    const file = JSON.parse(saveMap(doc));
    file.objects = [{ kind: "npc", x: 1, y: 1, type: "pawn" }];
    const read = loadMap(JSON.stringify(file));
    expect("problem" in read && read.problem).toContain('an object "npc" at (1, 1) is not read');
  });
});
