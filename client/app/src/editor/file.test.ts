import { describe, expect, it } from "vitest";
import { FORMAT, FORMAT_VERSION, fileName, loadMap, saveMap, toFile } from "./file";
import { FLOOR, GROUND_KINDS, type MapDocument, createMap } from "./model";
import { EditorSession } from "./session";

function loaded(text: string): MapDocument {
  const read = loadMap(text);
  if ("problem" in read) throw new Error(read.problem);
  return read.doc;
}

describe("CLI-09a's acceptance: create, paint, outline, save, reload, identical", () => {
  it("a 15 × 15-chunk zone round-trips through its file", () => {
    const doc = createMap({
      kind: "zone",
      name: "Ashen Meadow",
      location: 2,
      width: 15,
      height: 15,
      biome: "meadow",
      start: "wall",
    });
    const session = new EditorSession(doc);
    // Painted: a floor blob with a brush of 3, a lake of water, earth paths.
    session.choose("terrain", FLOOR);
    session.setBrush(3);
    session.strokeStart({ x: 40, y: 40 }, { erase: false, alt: false });
    for (let x = 41; x < 180; x += 2) session.strokeMove([{ x, y: 40 + (x % 7) }]);
    session.strokeEnd();
    session.choose("ground", GROUND_KINDS.indexOf("water"));
    session.setBrush(2);
    session.strokeStart({ x: 100, y: 120 }, { erase: false, alt: false });
    session.strokeEnd();
    session.choose("ground", GROUND_KINDS.indexOf("earth"));
    session.armTool("fill");
    session.strokeStart({ x: 60, y: 41 }, { erase: false, alt: false });
    session.strokeEnd();
    // Outlined: from the floor, then a stroke outside on its edge.
    session.armTool("outline");
    session.outlineFromFloor(null);
    session.setBrush(1);
    session.strokeStart({ x: 45, y: 40 }, { erase: true, alt: false });
    session.strokeEnd();
    expect(session.history.steps).toBe(5);
    // Saved, reloaded: the documents are equal, layer by layer and field by field.
    const text = saveMap(doc, "test");
    const back = loaded(text);
    expect(back).toEqual(doc);
    expect(back.outline).not.toBeNull();
    expect(back.outline!.some((v) => v === 0) && back.outline!.some((v) => v === 1)).toBe(true);
    // And saving again gives the same text.
    expect(saveMap(back, "test")).toBe(text);
  });

  it("a town round-trips without an outline", () => {
    const doc = createMap({
      kind: "town",
      name: "Town A",
      location: 1,
      width: 1,
      height: 1,
      biome: "meadow",
      start: "floor",
    });
    doc.obstacles.set(17, "rock2");
    const back = loaded(saveMap(doc));
    expect(back).toEqual(doc);
    expect(toFile(doc).layers.outline).toBeNull();
    expect(toFile(doc).obstacles).toEqual([{ x: 2, y: 1, sprite: "rock2" }]);
  });
});

describe("the file", () => {
  const zone = () =>
    createMap({
      kind: "zone",
      name: "Small",
      location: 3,
      width: 1,
      height: 1,
      biome: "cave",
      start: "floor",
    });

  it("carries the format, its version, the editor's version and one row per y", () => {
    const file = toFile(zone(), "abc123");
    expect(file.format).toBe(FORMAT);
    expect(file.version).toBe(FORMAT_VERSION);
    expect(file.editor).toBe("abc123");
    expect(file.layers.terrain).toHaveLength(15);
    expect(file.layers.terrain[0]).toBe(".".repeat(15));
    expect(file.layers.ground[0]).toBe("g".repeat(15));
    expect(file.layers.outline?.[0]).toBe("1".repeat(15));
  });

  it("refuses a newer version, another format, broken JSON and bad layers, with the reason", () => {
    const good = JSON.parse(saveMap(zone())) as Record<string, unknown>;
    const text = (patch: Record<string, unknown>) => JSON.stringify({ ...good, ...patch });
    const problem = (t: string) => {
      const read = loadMap(t);
      return "problem" in read ? read.problem : null;
    };
    expect(problem(text({}))).toBeNull();
    expect(problem(text({ version: FORMAT_VERSION + 1 }))).toMatch(/newer than this editor/);
    expect(problem(text({ format: "other" }))).toMatch(/not a Grim World map/);
    expect(problem("{")).toMatch(/not JSON/);
    const layers = good.layers as Record<string, string[]>;
    expect(
      problem(text({ layers: { ...layers, terrain: layers.terrain!.slice(1) } })),
    ).toMatch(/15 rows/);
    expect(
      problem(text({ layers: { ...layers, ground: ["x".repeat(15), ...layers.ground!.slice(1)] } })),
    ).toMatch(/unknown character/);
    expect(problem(text({ map: { ...(good.map as object), width: 16 } }))).toMatch(/size/);
    expect(problem(text({ map: { ...(good.map as object), biome: null } }))).toMatch(/biome/);
    expect(problem(text({ obstacles: [{ x: 99, y: 0, sprite: "rock1" }] }))).toMatch(/obstacle/);
  });

  it("is named after the map", () => {
    expect(fileName({ name: "Ashen Meadow" })).toBe("ashen-meadow.grimmap.json");
    expect(fileName({ name: "  ?? " })).toBe("map.grimmap.json");
  });
});
