import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { TILE_WIDTH, pixelToTile, tileToPixel } from "../input/coords";
import { BUILDINGS, HUB_VIEWS } from "../sandbox/fixtures/hubs";
import { hubPoint } from "./hubView";
import type { Tile } from "./view";

const key = (t: Tile) => `${t.x},${t.y}`;

/** The `[[still]]` entries of `tools/art/manifest.toml`: name → role. */
function manifest(): { stills: Map<string, string> } {
  const text = readFileSync(
    new URL("../../../../tools/art/manifest.toml", import.meta.url),
    "utf8",
  );
  const stills = new Map<string, string>();
  for (const m of text.matchAll(/\[\[still\]\]\nname = "([^"]+)"\nrole = "([^"]+)"/g)) {
    stills.set(m[1]!, m[2]!);
  }
  return { stills };
}

describe("the hubs on the instance's hex grid (CLI-03e, AC-2)", () => {
  for (const view of HUB_VIEWS.values()) {
    it(`${view.name}: every piece stands on a hex centre of the room's grid`, () => {
      const all = [
        ...view.places.map((p) => p.at),
        ...view.decor.map((d) => d.at),
        ...view.props.map((p) => p.at),
        ...view.figures.map((f) => f.at),
      ];
      for (const tile of all) {
        const p = hubPoint(view, tile);
        const room = tileToPixel(tile);
        expect(p.x - view.origin.x).toBeCloseTo(room.x, 9);
        expect(p.y - view.origin.y).toBeCloseTo(room.y, 9);
        // Back through the room's own conversion: the point is that tile's centre.
        expect(pixelToTile({ x: p.x - view.origin.x, y: p.y - view.origin.y })).toEqual(tile);
      }
    });

    it(`${view.name}: no two buildings share a hex; no prop on a door`, () => {
      const doors = [...view.places, ...view.decor].map((p) => key(p.at));
      expect(new Set(doors).size).toBe(doors.length);
      const props = view.props.map((p) => key(p.at));
      expect(new Set(props).size).toBe(props.length);
      for (const prop of view.props) {
        expect(doors, prop.id).not.toContain(key(prop.at));
      }
      for (const figure of view.figures) expect(doors).not.toContain(key(figure.at));
    });

    it(`${view.name}: at most 750 art pixels wide, whole cells, every building inside`, () => {
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
  const { stills } = manifest();
  for (const view of HUB_VIEWS.values()) {
    it(`${view.name}: every building a [[still]] building, every prop a prop`, () => {
      for (const b of [...view.places, ...view.decor]) {
        expect(stills.get(b.building), b.building).toBe("building");
      }
      for (const p of view.props) expect(stills.get(p.sprite), p.sprite).toBe("prop");
    });
  }
  it("every building of the fixtures' table is in the manifest", () => {
    for (const name of Object.keys(BUILDINGS)) expect(stills.get(name), name).toBe("building");
  });
});
