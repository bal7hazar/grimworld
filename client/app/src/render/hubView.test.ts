import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { TILE_WIDTH, pixelToTile, tileToPixel } from "../input/coords";
import { BUILDINGS, HUB_VIEWS } from "../sandbox/fixtures/hubs";
import {
  type HubView,
  feetPoint,
  groundCell,
  groundCells,
  hubPoint,
  standingOrder,
} from "./hubView";
import { DEFAULT_FEET, feetOffset } from "./renderer";
import type { Tile } from "./view";

const key = (t: Tile) => `${t.x},${t.y}`;

/** The `[[still]]` and `[[tileset]]` entries of `tools/art/manifest.toml`: name → role. */
function manifest(): { stills: Map<string, string>; tiles: Set<string> } {
  const text = readFileSync(
    new URL("../../../../tools/art/manifest.toml", import.meta.url),
    "utf8",
  );
  const stills = new Map<string, string>();
  for (const m of text.matchAll(/\[\[still\]\]\nname = "([^"]+)"\nrole = "([^"]+)"/g)) {
    stills.set(m[1]!, m[2]!);
  }
  const tiles = new Set<string>();
  for (const m of text.matchAll(/\[\[tileset\]\]\nname = "([^"]+)"[\s\S]*?cells = \{([^}]*)\}/g)) {
    for (const cell of m[2]!.matchAll(/(\w+) = \[/g)) tiles.add(`${m[1]}_${cell[1]}`);
  }
  return { stills, tiles };
}

describe("the hubs on the instance's hex grid (CLI-03e, AC-2)", () => {
  for (const view of HUB_VIEWS.values()) {
    it(`${view.name}: every piece stands on a hex centre of the room's grid`, () => {
      const all = [
        ...view.places.map((p) => p.at),
        ...view.decor.map((d) => d.at),
        ...view.props.map((p) => p.at),
        ...view.figures.map((f) => f.at),
        ...view.ground.path,
      ];
      for (const tile of all) {
        const p = hubPoint(view, tile);
        const room = tileToPixel(tile);
        expect(p.x - view.origin.x).toBeCloseTo(room.x, 9);
        expect(p.y - view.origin.y).toBeCloseTo(room.y, 9);
        // Back through the room's own conversion: the point is that tile's centre.
        expect(pixelToTile({ x: p.x - view.origin.x, y: p.y - view.origin.y })).toEqual(tile);
      }
      for (const figure of view.figures) {
        const c = hubPoint(view, figure.at);
        expect(feetPoint(view, figure.at)).toEqual({ x: c.x, y: c.y + feetOffset(DEFAULT_FEET) });
      }
    });

    it(`${view.name}: no two buildings share a hex; no prop on a door or the path`, () => {
      const doors = [...view.places, ...view.decor].map((p) => key(p.at));
      expect(new Set(doors).size).toBe(doors.length);
      const path = new Set(view.ground.path.map(key));
      const props = view.props.map((p) => key(p.at));
      expect(new Set(props).size).toBe(props.length);
      for (const prop of view.props) {
        expect(doors, prop.id).not.toContain(key(prop.at));
        expect(path.has(key(prop.at)), prop.id).toBe(false);
      }
      for (const figure of view.figures) expect(doors).not.toContain(key(figure.at));
    });

    it(`${view.name}: at most 750 art pixels wide, whole ground cells, everything inside`, () => {
      expect(view.width).toBeLessThanOrEqual(750);
      expect(view.width % TILE_WIDTH).toBe(0);
      expect(view.height % TILE_WIDTH).toBe(0);
      for (const b of [...view.places, ...view.decor]) {
        const base = hubPoint(view, b.at);
        expect(base.x - b.width / 2, b.id).toBeGreaterThanOrEqual(0);
        expect(base.x + b.width / 2, b.id).toBeLessThanOrEqual(view.width);
        expect(base.y - b.height, b.id).toBeGreaterThanOrEqual(0);
        expect(base.y, b.id).toBeLessThanOrEqual(view.height);
      }
    });

    it(`${view.name}: a place's size is its building's native size`, () => {
      for (const p of [...view.places, ...view.decor]) {
        expect([p.width, p.height], p.id).toEqual(BUILDINGS[p.building as keyof typeof BUILDINGS]);
      }
    });
  }
});

describe("the hubs' art names the atlas (CLI-03e, AC-3)", () => {
  const { stills, tiles } = manifest();
  for (const view of HUB_VIEWS.values()) {
    it(`${view.name}: every building a [[still]] building, every prop a prop, the ground tiles`, () => {
      for (const b of [...view.places, ...view.decor]) {
        expect(stills.get(b.building), b.building).toBe("building");
      }
      for (const p of view.props) expect(stills.get(p.sprite), p.sprite).toBe("prop");
      for (const cell of ["nw", "n", "ne", "w", "c", "e", "sw", "s", "se"]) {
        expect(tiles.has(`${view.ground.tileset}_${cell}`), cell).toBe(true);
      }
      expect(tiles.has(view.ground.water)).toBe(true);
    });
  }
  it("every building of the fixtures' table is in the manifest", () => {
    for (const name of Object.keys(BUILDINGS)) expect(stills.get(name), name).toBe("building");
  });
});

describe("the standing layer (CLI-03e, AC-5)", () => {
  const house = { width: 100, height: 120 };
  const view: HubView = {
    name: "test",
    gold: 0,
    width: 640,
    height: 640,
    origin: { x: 320, y: 320 },
    ground: { tileset: "grass", water: "water_c", path: [] },
    places: [
      {
        id: "house",
        label: "House",
        target: { kind: "service", service: "smith" },
        building: "house1",
        at: { x: 0, y: 0 },
        ...house,
      },
    ],
    decor: [{ id: "barn", building: "barn", at: { x: 2, y: 0 }, ...house }],
    props: [{ id: "tree", sprite: "tree1", at: { x: 1, y: 2 } }],
    figures: [
      { id: 2, name: "front", profession: "cleric", level: 1, at: { x: 0, y: -1 }, facing: "left" },
      {
        id: 1,
        name: "behind",
        profession: "warden",
        level: 1,
        at: { x: 0, y: 1 },
        facing: "right",
      },
    ],
    services: [],
  };

  it("is sorted by the y of each base: behind a house first, in front of it last", () => {
    expect(standingOrder(view).map((s) => s.key)).toEqual([
      "prop:tree",
      "figure:1",
      "decor:barn",
      "place:house",
      "figure:2",
    ]);
  });

  it("breaks a tie by a stable key, whatever the order of the view's lists", () => {
    const keys = standingOrder(view).map((s) => s.key);
    const reversed: HubView = {
      ...view,
      places: [...view.places].reverse(),
      decor: [...view.decor].reverse(),
      figures: [...view.figures].reverse(),
    };
    expect(standingOrder(reversed).map((s) => s.key)).toEqual(keys);
    // The barn and the house stand on one row: the key decides.
    const [a, b] = standingOrder(view).filter((s) => s.kind !== "figure" && s.kind !== "prop");
    expect(a!.base.y).toBe(b!.base.y);
  });
});

describe("the ground's cells (CLI-03e, AC-4)", () => {
  it("covers the illustration; the border takes the tileset's edges and corners", () => {
    expect(groundCells({ width: 704, height: 960 })).toEqual({ columns: 11, rows: 15 });
    const names = [0, 1, 2].map((row) => [0, 1, 2].map((c) => groundCell(c, row, 3, 3)));
    expect(names).toEqual([
      ["nw", "n", "ne"],
      ["w", "c", "e"],
      ["sw", "s", "se"],
    ]);
    expect(groundCell(4, 5, 11, 15)).toBe("c");
  });
});
