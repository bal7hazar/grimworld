import { describe, expect, it } from "vitest";
import { createMap, erase, apply } from "./model";
import { outlineSegments, seamSegments, visibleRange } from "./overlay";
import { DEFAULT_LAYERS, editorView } from "./view";

describe("overlays (§2.3)", () => {
  it("chunk seams: one edge per pair of hexes in two chunks", () => {
    // 2 × 1 chunks: one seam of 15 rows; odd-r rows touch the next chunk by 1 or 2 edges.
    const seams = seamSegments(30, 15);
    expect(seams.length / 4).toBe(15 + 14);
    expect(seamSegments(15, 15).length).toBe(0);
  });

  it("the outline's border: around the map when every hex is inside, around a hole when one is out", () => {
    const doc = createMap({
      kind: "zone",
      name: "O",
      location: 2,
      width: 1,
      height: 1,
      biome: "meadow",
      start: "wall",
    });
    const all = outlineSegments(15, 15, doc.outline!).length / 4;
    // The map's edge: 15 hexes a row on top and bottom (2 edges each, the corners 3), rows' ends.
    expect(all).toBeGreaterThan(4 * 15);
    apply(doc, erase(doc, [{ x: 7, y: 7 }], true));
    expect(outlineSegments(15, 15, doc.outline!).length / 4).toBe(all + 6);
  });

  it("the visible range covers the viewport's hexes and stays in the map", () => {
    const camera = { centre: { x: -7 * 64, y: -7 * 55.4 }, scale: 1 };
    const range = visibleRange(camera, { width: 320, height: 240 }, 15, 15);
    expect(range.x0).toBeGreaterThanOrEqual(0);
    expect(range.x1).toBeLessThanOrEqual(14);
    expect(range.x0).toBeLessThanOrEqual(5);
    expect(range.x1).toBeGreaterThanOrEqual(9);
  });
});

describe("the game's view of a map", () => {
  it("every hex revealed and in sight, water void, no actor; layers off draw grass and flat walls", () => {
    const doc = createMap({
      kind: "zone",
      name: "V",
      location: 2,
      width: 1,
      height: 1,
      biome: "meadow",
      start: "wall",
    });
    const view = editorView(doc, DEFAULT_LAYERS);
    expect(view.tiles).toHaveLength(225);
    expect(view.sight).toHaveLength(225);
    expect(view.actors).toEqual([]);
    expect(view.void).toBe("water");
    expect(view.tiles.every((t) => t.kind === "wall" && t.ground === "grass")).toBe(true);
    const flat = editorView(doc, { ...DEFAULT_LAYERS, ground: false, obstacles: false });
    expect(flat.tiles.every((t) => t.kind === "unrevealed" && t.ground === undefined)).toBe(true);
  });
});

describe("the page (O-1)", () => {
  const sources = import.meta.glob<string>("../**/*.{ts,tsx}", {
    query: "?raw",
    import: "default",
    eager: true,
  });

  it("no module of the game imports the editor; the editor imports no stand-in rule", () => {
    const game = Object.entries(sources).filter(
      ([path]) => !path.startsWith("./") && !/\.test\.tsx?$/.test(path),
    );
    expect(game.length).toBeGreaterThan(20);
    for (const [path, text] of game) {
      expect(text, path).not.toMatch(/from\s+["'][^"']*\/editor\//);
    }
    for (const [path, text] of Object.entries(sources).filter(([p]) => p.startsWith("./"))) {
      expect(text, path).not.toMatch(/from\s+["'][^"']*placeholders["']/);
    }
  });
});
