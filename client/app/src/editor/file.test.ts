import { describe, expect, it } from "vitest";
import { FORMAT, FORMAT_VERSION, fileName, loadMap, saveMap, toFile } from "./file";
import { fitted } from "./fit";
import {
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  WALL,
  cellAt,
  createMap,
  isOutside,
  keyOf,
} from "./model";
import { EditorSession } from "./session";

function loaded(text: string): MapDocument {
  const read = loadMap(text);
  if ("problem" in read) throw new Error(read.problem);
  return read.doc;
}

const problem = (text: string) => {
  const read = loadMap(text);
  return "problem" in read ? read.problem : null;
};

const zone = () => createMap({ kind: "zone", name: "Ashen Meadow", location: 2, biome: "meadow" });

describe("CLI-09a2's acceptance: paint away from the origin, fit, nudge, save, reload, identical", () => {
  it("a zone far from (0, 0), below zero, round-trips through its format 2 file", () => {
    const doc = zone();
    const session = new EditorSession(doc);
    // Walls, a floor blob with a brush of 3, a lake of water, earth by Fill.
    session.choose("terrain", WALL);
    session.setBrush(3);
    session.strokeStart({ x: -400, y: -301 }, { erase: false, alt: false });
    for (let x = -399; x < -250; x += 2) session.strokeMove([{ x, y: -301 + (x % 7) }]);
    session.strokeEnd();
    session.choose("terrain", FLOOR);
    session.setBrush(2);
    session.strokeStart({ x: -380, y: -300 }, { erase: false, alt: false });
    for (let x = -379; x < -270; x += 3) session.strokeMove([{ x, y: -300 + (x % 5) }]);
    session.strokeEnd();
    session.choose("ground", GROUND_KINDS.indexOf("water"));
    session.strokeStart({ x: -330, y: -299 }, { erase: false, alt: false });
    session.strokeEnd();
    session.choose("ground", GROUND_KINDS.indexOf("earth"));
    session.armTool("fill");
    session.strokeStart({ x: -370, y: -300 }, { erase: false, alt: false });
    session.strokeEnd();
    // Outlined from the floor, a stroke outside on its edge; fitted, then nudged.
    session.armTool("outline");
    session.outlineFromFloor(null);
    session.setBrush(1);
    session.strokeStart({ x: -378, y: -300 }, { erase: true, alt: false });
    session.strokeEnd();
    session.fitChunks();
    session.nudgeOrigin(0, 1);
    expect(doc.origin?.how).toBe("nudged");
    expect(session.history.steps).toBe(6);
    // Saved, reloaded: the documents are equal, hex by hex and field by field.
    const text = saveMap(doc, "test");
    const back = loaded(text);
    expect(back).toEqual(doc);
    expect([...back.hexes.values()].some(isOutside)).toBe(true);
    expect(fitted(back)).toEqual(fitted(doc));
    // And saving again gives the same text.
    expect(saveMap(back, "test")).toBe(text);
  });

  it("a town round-trips without an outline, its pins on painted hexes", () => {
    const doc = createMap({ kind: "town", name: "Town A", location: 1, biome: "meadow" });
    const s = new EditorSession(doc);
    s.setBrush(2);
    s.strokeStart({ x: 3, y: -2 }, { erase: false, alt: false });
    s.strokeEnd();
    doc.obstacles.set(keyOf({ x: 3, y: -2 }), "rock2");
    const back = loaded(saveMap(doc));
    expect(back).toEqual(doc);
    expect(toFile(doc).rows.every((r) => r.outline === undefined)).toBe(true);
    expect(toFile(doc).obstacles).toEqual([{ x: 3, y: -2, sprite: "rock2" }]);
    expect(toFile(doc).chunks).toBeNull();
  });
});

describe("the file, format 2", () => {
  it("carries the format, its version, the editor's version, row spans with gaps, the origin", () => {
    const doc = zone();
    const s = new EditorSession(doc);
    s.strokeStart({ x: 10, y: 5 }, { erase: false, alt: false });
    s.strokeEnd();
    s.choose("terrain", WALL);
    s.strokeStart({ x: 13, y: 5 }, { erase: false, alt: false });
    s.strokeEnd();
    s.fitChunks();
    const file = toFile(doc, "abc123");
    expect(file.format).toBe(FORMAT);
    expect(file.version).toBe(FORMAT_VERSION);
    expect(FORMAT_VERSION).toBe(2);
    expect(file.editor).toBe("abc123");
    expect(file.rows).toEqual([{ y: 5, x: 10, terrain: ".  #", ground: "g  g", outline: "1  1" }]);
    expect(file.chunks).toEqual({ x: 0, y: 0, how: "fitted" });
  });

  it("refuses a newer version, another format, broken JSON, bad spans and origins, with the reason", () => {
    const doc = zone();
    const s = new EditorSession(doc);
    s.setBrush(1);
    s.strokeStart({ x: 0, y: 0 }, { erase: false, alt: false });
    s.strokeEnd();
    const good = JSON.parse(saveMap(doc)) as Record<string, unknown>;
    const text = (patch: Record<string, unknown>) => JSON.stringify({ ...good, ...patch });
    const row = (good.rows as Record<string, unknown>[])[0]!;
    expect(problem(text({}))).toBeNull();
    expect(problem(text({ version: FORMAT_VERSION + 1 }))).toMatch(/newer than this editor/);
    expect(problem(text({ format: "other" }))).toMatch(/not a Grim World map/);
    expect(problem("{")).toMatch(/not JSON/);
    expect(problem(text({ rows: [{ ...row, ground: "x".repeat(9) }] }))).toMatch(/one length/);
    expect(
      problem(text({ rows: [{ ...row, terrain: "?.", ground: "gg", outline: "11" }] })),
    ).toMatch(/unknown character/);
    expect(
      problem(text({ rows: [{ ...row, terrain: " .", ground: "gg", outline: "11" }] })),
    ).toMatch(/gap in one layer only/);
    expect(problem(text({ rows: [row, row] }))).toMatch(/comes twice/);
    expect(problem(text({ rows: [{ ...row, outline: undefined }] }))).toMatch(/no outline/);
    expect(problem(text({ chunks: { x: 0, y: 1, how: "fitted" } }))).toMatch(/y even/);
    expect(problem(text({ chunks: { x: 15, y: 0, how: "fitted" } }))).toMatch(/chunk origin/);
    expect(problem(text({ obstacles: [{ x: 99, y: 0, sprite: "rock1" }] }))).toMatch(/obstacle/);
    expect(problem(text({ map: { ...(good.map as object), biome: null } }))).toMatch(/biome/);
  });

  it("is named after the map", () => {
    expect(fileName({ name: "Ashen Meadow" })).toBe("ashen-meadow.grimmap.json");
    expect(fileName({ name: "  ?? " })).toBe("map.grimmap.json");
  });
});

describe("format 1 (CLI-09a), converted on load", () => {
  /** A CLI-09a file of 1 × 1 chunk: walls, a floor row at y = 3, two hexes outside on it. */
  function format1(patch: Record<string, unknown> = {}): string {
    const terrain = Array.from({ length: 15 }, (_, y) => (y === 3 ? "." : "#").repeat(15));
    const ground = Array.from({ length: 15 }, (_, y) => (y === 3 ? "e" : "g").repeat(15));
    const outline = Array.from({ length: 15 }, (_, y) =>
      y === 3 ? "00" + "1".repeat(13) : "1".repeat(15),
    );
    return JSON.stringify({
      format: "grimworld-map",
      version: 1,
      editor: "cli-09a",
      map: {
        kind: "zone",
        name: "Old",
        location: 2,
        width: 1,
        height: 1,
        biome: "cave",
        start: "wall",
        levelMin: 1,
        levelMax: 1,
        rank: 0,
        spawnTable: 0,
      },
      layers: { terrain, ground, outline },
      obstacles: [{ x: 4, y: 5, sprite: "rock2" }],
      ...patch,
    });
  }

  it("every hex painted as it was, the outline kept, the grid at (0, 0), with a note", () => {
    const read = loadMap(format1());
    if ("problem" in read) throw new Error(read.problem);
    const { doc, notes } = read;
    expect(doc.hexes.size).toBe(225);
    expect(cellAt(doc, { x: 5, y: 3 })).not.toBeNull();
    expect(cellAt(doc, { x: 15, y: 0 })).toBeNull();
    const at = (x: number, y: number) => {
      const c = cellAt(doc, { x, y })!;
      return { wall: (c & 1) === WALL, outside: isOutside(c) };
    };
    expect(at(5, 3)).toEqual({ wall: false, outside: false });
    expect(at(0, 3)).toEqual({ wall: false, outside: true });
    expect(at(5, 4)).toEqual({ wall: true, outside: false });
    expect(doc.origin).toEqual({ x: 0, y: 0, how: "nudged" });
    expect(doc.obstacles.get(keyOf({ x: 4, y: 5 }))).toBe("rock2");
    expect(doc.meta).toEqual({
      kind: "zone",
      name: "Old",
      location: 2,
      region: 0,
      biome: "cave",
      levelMin: 1,
      levelMax: 1,
      rank: 0,
      spawnTable: 0,
      quotas: [],
    });
    expect(notes[0]).toMatch(/Converted from format 1/);
    // The fitted records read as CLI-09a's did: one chunk, partly inside (two hexes out).
    const fit = fitted(doc);
    expect(typeof fit !== "string" && [fit.chunkSet, fit.masks.get(0)?.length]).toEqual([[0], 223]);
    // Saved again: format 2, and that round-trips.
    const again = saveMap(doc);
    expect(JSON.parse(again).version).toBe(2);
    expect(loaded(again)).toEqual(doc);
  });

  it("a broken format 1 file is refused with its reason", () => {
    const old = JSON.parse(format1()) as Record<string, Record<string, unknown>>;
    expect(problem(format1({ map: { ...old.map, width: 16 } }))).toMatch(/size/);
    expect(problem(format1({ map: { ...old.map, start: "lava" } }))).toMatch(/start fill/);
    expect(
      problem(
        format1({ layers: { ...old.layers, terrain: (old.layers!.terrain as string[]).slice(1) } }),
      ),
    ).toMatch(/15 rows/);
    expect(problem(format1({ obstacles: [{ x: 99, y: 0, sprite: "rock1" }] }))).toMatch(/obstacle/);
  });
});
