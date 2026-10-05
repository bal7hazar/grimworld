import { describe, expect, it } from "vitest";
import { Drafts, type DraftStorage } from "./drafts";
import { FLOOR, GROUND_KINDS, WALL, createMap, indexOf } from "./model";
import { EditorSession } from "./session";

const zone = () =>
  createMap({
    kind: "zone",
    name: "Tools",
    location: 2,
    width: 2,
    height: 2,
    biome: "forest",
    start: "wall",
  });

describe("the tools on strokes (§3)", () => {
  it("paint with a brush, right drag erases, each stroke one step", () => {
    const doc = zone();
    const s = new EditorSession(doc);
    s.choose("terrain", FLOOR);
    s.setBrush(1);
    s.strokeStart({ x: 10, y: 10 }, { erase: false, alt: false });
    s.strokeMove([
      { x: 11, y: 10 },
      { x: 12, y: 10 },
    ]);
    s.strokeEnd();
    expect(doc.terrain.reduce((n, v) => n + (v === FLOOR ? 1 : 0), 0)).toBe(13);
    s.setBrush(0);
    s.strokeStart({ x: 11, y: 10 }, { erase: true, alt: false });
    s.strokeEnd();
    expect(doc.terrain[indexOf(doc, { x: 11, y: 10 })]).toBe(WALL);
    expect(s.history.steps).toBe(2);
    s.undo();
    expect(doc.terrain[indexOf(doc, { x: 11, y: 10 })]).toBe(FLOOR);
    s.undo();
    expect(doc.terrain.every((v) => v === WALL)).toBe(true);
    expect(s.revision).toBeGreaterThan(0);
  });

  it("Alt+click picks and Pick returns to the tool before it", () => {
    const doc = zone();
    const s = new EditorSession(doc);
    const earth = GROUND_KINDS.indexOf("earth");
    s.choose("ground", earth);
    s.strokeStart({ x: 3, y: 3 }, { erase: false, alt: false });
    s.strokeEnd();
    s.choose("ground", 0);
    s.armTool("erase");
    s.armTool("pick");
    s.strokeStart({ x: 3, y: 3 }, { erase: false, alt: false });
    expect(s.ground).toBe(earth);
    expect(s.tool).toBe("erase");
    s.choose("ground", 0);
    s.strokeStart({ x: 3, y: 3 }, { erase: false, alt: true });
    expect(s.ground).toBe(earth);
    expect(s.tool).toBe("paint");
    // The picks changed nothing.
    expect(s.history.steps).toBe(1);
  });

  it("the outline tool marks inside and outside; Fill armed from it fills the outline", () => {
    const doc = zone();
    const s = new EditorSession(doc);
    s.armTool("outline");
    s.setBrush(2);
    s.strokeStart({ x: 15, y: 15 }, { erase: true, alt: false });
    s.strokeEnd();
    expect(doc.outline?.reduce((n, v) => n + v, 0)).toBe(900 - 19);
    s.armTool("fill");
    expect(s.fillOutline).toBe(true);
    // Fill inside the 19 outside hexes: they come back in; the terrain is untouched.
    s.strokeStart({ x: 15, y: 15 }, { erase: false, alt: false });
    expect(doc.outline?.every((v) => v === 1)).toBe(true);
    expect(doc.terrain.every((v) => v === WALL)).toBe(true);
    // A swatch arms Paint and Fill fills terrain again.
    s.choose("terrain", FLOOR);
    s.armTool("fill");
    expect(s.fillOutline).toBe(false);
    s.strokeStart({ x: 0, y: 0 }, { erase: false, alt: false });
    expect(doc.terrain.every((v) => v === FLOOR)).toBe(true);
  });

  it("a town refuses the outline tool and says why", () => {
    const town = createMap({
      kind: "town",
      name: "Town",
      location: 1,
      width: 1,
      height: 1,
      biome: "meadow",
      start: "floor",
    });
    const s = new EditorSession(town);
    s.armTool("outline");
    expect(s.tool).toBe("paint");
    expect(s.said).toMatch(/no outline/);
  });

  it("the brush is radius 0 to 3; K walks the layers", () => {
    const s = new EditorSession(zone());
    s.setBrush(9);
    expect(s.brush).toBe(3);
    s.setBrush(-1);
    expect(s.brush).toBe(0);
    s.toggleLayer("grid");
    expect(s.layers.grid).toBe(false);
    for (let k = 0; k < 6; k++) s.focusNextLayer();
    expect(s.layerFocus).toBe(0);
  });
});

describe("drafts (O-5)", () => {
  const memory = (): DraftStorage & { map: Map<string, string> } => {
    const map = new Map<string, string>();
    return {
      map,
      getItem: (k) => map.get(k) ?? null,
      setItem: (k, v) => void map.set(k, v),
      removeItem: (k) => void map.delete(k),
    };
  };

  it("keeps the open map, lists it last edited first, and forgets it", () => {
    const store = new Drafts(memory());
    const a = zone();
    store.put("a", a, new Date("2026-10-05T10:00:00Z"));
    store.put(
      "b",
      createMap({ ...a.meta, name: "Other", biome: "cave" }),
      new Date("2026-10-05T11:00:00Z"),
    );
    expect(store.list().map((e) => e.id)).toEqual(["b", "a"]);
    expect(store.get("a")).toEqual(a);
    store.forget("b");
    expect(store.list().map((e) => e.id)).toEqual(["a"]);
    expect(store.get("b")).toMatch(/gone/);
  });

  it("works without a storage, and with one that throws", () => {
    const none = new Drafts(null);
    expect(none.put("a", zone())).toBe(false);
    expect(none.list()).toEqual([]);
    const throwing = new Drafts({
      getItem: () => {
        throw new Error("blocked");
      },
      setItem: () => {
        throw new Error("full");
      },
      removeItem: () => {
        throw new Error("blocked");
      },
    });
    expect(throwing.put("a", zone())).toBe(false);
    expect(throwing.list()).toEqual([]);
    expect(throwing.get("a")).toMatch(/cannot be read/);
    expect(() => throwing.forget("a")).not.toThrow();
  });
});
