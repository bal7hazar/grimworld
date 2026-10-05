import { describe, expect, it } from "vitest";
import { type FitScore, type Fitted, fitChunks, fitted } from "./fit";
import { loadMap } from "./file";
import { COORD_MAX, FLOOR, type MapDocument, WALL, apply, createMap, erase, paint } from "./model";
import { outlineSegments, seamSegments, visibleRange } from "./overlay";
import { DEFAULT_LAYERS, VIEW_MAX, VOID_PAD, editorView, holds, viewWindow } from "./view";

describe("overlays (§2.3)", () => {
  const zone = () => createMap({ kind: "zone", name: "O", location: 2, biome: "meadow" });
  const fill = (doc: MapDocument, x: number, y: number, w: number, h: number) => {
    const tiles = [];
    for (let dy = 0; dy < h; dy++)
      for (let dx = 0; dx < w; dx++) tiles.push({ x: x + dx, y: y + dy });
    apply(doc, paint(doc, tiles, { layer: "terrain", value: FLOOR }));
  };

  it("the fitted grid: one edge per pair of hexes in two chunks of the set, one label a chunk", () => {
    const doc = zone();
    fill(doc, -200, 40, 30, 15);
    doc.origin = { ...(fitChunks(doc) as FitScore).origin, how: "fitted" };
    const fit = fitted(doc) as Fitted;
    expect(fit.chunkSet).toEqual([0, 1]);
    const one = seamSegments({ ...fit, chunkSet: [0] });
    const two = seamSegments(fit);
    expect(two.labels.map((l) => l.text)).toEqual(["0", "1"]);
    // Two chunks side by side share one seam of 15 rows: odd-r rows touch by 1 or 2 edges.
    expect(two.segments.length / 4).toBe(2 * (one.segments.length / 4) - (15 + 14));
  });

  it("the outline's border: around the painted inside, around a hole when one hex is out", () => {
    const doc = zone();
    fill(doc, 1000, -1000, 15, 15);
    const all = outlineSegments(doc).length / 4;
    expect(all).toBeGreaterThan(4 * 15);
    apply(doc, erase(doc, [{ x: 1007, y: -993 }], true));
    expect(outlineSegments(doc).length / 4).toBe(all + 6);
    // Unpainting the hex instead: the same border.
    apply(doc, erase(doc, [{ x: 1007, y: -993 }]));
    expect(outlineSegments(doc).length / 4).toBe(all + 6);
    expect(
      outlineSegments(createMap({ kind: "town", name: "T", location: 1, biome: "meadow" })).length,
    ).toBe(0);
  });

  it("the visible range covers the viewport's hexes, unbounded", () => {
    const camera = { centre: { x: 3000 * 64, y: 500 * 55.4 }, scale: 1 };
    const range = visibleRange(camera, { width: 320, height: 240 });
    expect(range.x0).toBeLessThanOrEqual(-3002);
    expect(range.x1).toBeGreaterThanOrEqual(-2998);
    expect(range.y0).toBeLessThan(-500);
  });
});

describe("the game's view of a map, near the view only (D-216)", () => {
  it("painted hexes revealed and in sight, water void, no actor; layers off draw grass and flat walls", () => {
    const doc = createMap({ kind: "zone", name: "V", location: 2, biome: "meadow" });
    const tiles = [];
    for (let y = 0; y < 15; y++)
      for (let x = 0; x < 15; x++) tiles.push({ x: x - 500, y: y + 300 });
    apply(doc, paint(doc, tiles, { layer: "terrain", value: WALL }));
    const everywhere = { x0: -10_000, y0: -10_000, x1: 10_000, y1: 10_000 };
    const view = editorView(doc, DEFAULT_LAYERS, everywhere);
    // The painted 15 × 15 and VOID_PAD hexes of water around them.
    const side = 15 + 2 * VOID_PAD;
    expect(view.tiles).toHaveLength(side * side);
    expect(view.sight).toHaveLength(side * side);
    expect(view.actors).toEqual([]);
    expect(view.void).toBe("water");
    const painted = view.tiles.filter((t) => t.ground !== "water");
    expect(painted).toHaveLength(225);
    expect(painted.every((t) => t.kind === "wall" && t.ground === "grass")).toBe(true);
    expect(view.tiles.filter((t) => t.ground === "water").every((t) => t.kind === "wall")).toBe(
      true,
    );
    const flat = editorView(
      doc,
      { ...DEFAULT_LAYERS, ground: false, obstacles: false },
      everywhere,
    );
    expect(
      flat.tiles.filter((t) => t.kind === "unrevealed" && t.ground === undefined),
    ).toHaveLength(225);
  });

  it("only the window's part is sent; the window grows the view by half, snapped to 15", () => {
    const doc = createMap({ kind: "zone", name: "V", location: 2, biome: "meadow" });
    const tiles = [];
    for (let y = 0; y < 225; y++) for (let x = 0; x < 225; x++) tiles.push({ x, y });
    apply(doc, paint(doc, tiles, { layer: "terrain", value: FLOOR }));
    const visible = { x0: 100, y0: 100, x1: 129, y1: 119 };
    const window = viewWindow(visible);
    expect(window).toEqual({ x0: 75, y0: 75, x1: 149, y1: 134 });
    expect(holds(window, visible)).toBe(true);
    expect(holds(window, { ...visible, x1: 150 })).toBe(false);
    expect(editorView(doc, DEFAULT_LAYERS, window).tiles).toHaveLength(75 * 60);
    // Far from the painting: nothing sent.
    expect(
      editorView(doc, DEFAULT_LAYERS, viewWindow({ x0: 5000, y0: 0, x1: 5030, y1: 20 })).tiles,
    ).toEqual([]);
  });
});

describe("two hexes at the plane's far corners (review of #362, minor 1)", () => {
  const text = JSON.stringify({
    format: "grimworld-map",
    version: 2,
    editor: "test",
    map: {
      kind: "zone",
      name: "Far",
      location: 2,
      biome: "meadow",
      levelMin: 1,
      levelMax: 1,
      rank: 0,
      spawnTable: 0,
    },
    rows: [
      { y: -COORD_MAX, x: -COORD_MAX, terrain: ".", ground: "g", outline: "1" },
      { y: COORD_MAX, x: COORD_MAX, terrain: "#", ground: "g", outline: "1" },
    ],
    chunks: null,
    obstacles: [],
  });

  it("the view sends at most VIEW_MAX tiles, whatever the window", () => {
    const read = loadMap(text);
    if ("problem" in read) throw new Error(read.problem);
    const everything = { x0: -COORD_MAX, y0: -COORD_MAX, x1: COORD_MAX, y1: COORD_MAX };
    const view = editorView(read.doc, DEFAULT_LAYERS, everything);
    expect(view.tiles.length).toBeLessThanOrEqual(VIEW_MAX);
    expect(view.tiles).toHaveLength(2);
    // Two islands 2,000 hexes apart, zoomed out over both: still under the cap.
    const doc = createMap({ kind: "zone", name: "Isles", location: 2, biome: "meadow" });
    const isle = (x: number, y: number) => {
      const tiles = [];
      for (let dy = 0; dy < 30; dy++)
        for (let dx = 0; dx < 30; dx++) tiles.push({ x: x + dx, y: y + dy });
      return tiles;
    };
    apply(
      doc,
      paint(doc, [...isle(0, 0), ...isle(2000, 2000)], { layer: "terrain", value: FLOOR }),
    );
    const wide = editorView(
      doc,
      DEFAULT_LAYERS,
      viewWindow({ x0: -500, y0: -500, x1: 2500, y1: 2500 }),
    );
    expect(wide.tiles).toHaveLength(2 * 900);
  });

  it("such a file opens, renders, outlines and refuses its fit, all well under a second", () => {
    const start = performance.now();
    const read = loadMap(text);
    if ("problem" in read) throw new Error(read.problem);
    const box = {
      x0: -COORD_MAX - 10,
      y0: -COORD_MAX - 10,
      x1: COORD_MAX + 10,
      y1: COORD_MAX + 10,
    };
    editorView(read.doc, DEFAULT_LAYERS, viewWindow(box));
    outlineSegments(read.doc);
    expect(fitChunks(read.doc)).toBe("wide");
    expect(performance.now() - start).toBeLessThan(1000);
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
