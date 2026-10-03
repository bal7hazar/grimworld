import { describe, expect, it } from "vitest";
import type { Tile } from "../../render/view";
import { findPath } from "../placeholders";
import { kindAt } from "../world";
import { FIXTURES } from ".";
import { HUB_PATHS, HUB_VIEWS } from "./hubs";
import { HUB_ADVENTURER_ID, footprint, hubTap, hubWorld, onIsland } from "./hubWorld";

const key = (t: Tile) => `${t.x},${t.y}`;

describe("a hub as a zone's world (CLI-03f, AC-2)", () => {
  for (const view of HUB_VIEWS.values()) {
    const world = hubWorld(view, view.arrival);
    const { terrain } = world;
    const others = world.actors.filter((a) => a.id !== HUB_ADVENTURER_ID);

    it(`${view.name}: whole chunks, all revealed, of kind hub`, () => {
      expect(world.kind).toBe("hub");
      expect(terrain.width % 15).toBe(0);
      expect(terrain.height % 15).toBe(0);
      expect(terrain.kinds).toHaveLength(terrain.width * terrain.height);
      expect(terrain.kinds).not.toContain("unrevealed");
    });

    it(`${view.name}: the arrival hex is floor and free; the adventurer stands there`, () => {
      expect(kindAt(terrain, view.arrival)).toBe("floor");
      expect(others.some((a) => key(a.tile) === key(view.arrival))).toBe(false);
      const adventurer = world.actors.find((a) => a.id === world.adventurerId);
      expect(adventurer?.tile).toEqual(view.arrival);
    });

    it(`${view.name}: every door is floor; every footprint and every prop is wall`, () => {
      for (const place of view.places) {
        expect(kindAt(terrain, place.at), place.id).toBe("floor");
        for (const t of footprint(view, place)) {
          if (key(t) !== key(place.at))
            expect(kindAt(terrain, t), `${place.id} ${key(t)}`).toBe("wall");
        }
      }
      for (const decor of view.decor) {
        for (const t of footprint(view, decor)) expect(kindAt(terrain, t), decor.id).toBe("wall");
      }
      for (const prop of view.props) expect(kindAt(terrain, prop.at), prop.id).toBe("wall");
    });

    it(`${view.name}: no structure stands on a floor hex except at a door`, () => {
      const doors = new Set(view.places.map((p) => key(p.at)));
      for (const s of world.structures ?? []) {
        for (const t of [s.at, ...s.covers]) {
          if (kindAt(terrain, t) === "floor") expect(doors.has(key(t)), s.key).toBe(true);
        }
        for (const t of s.covers) expect(kindAt(terrain, t), `${s.key} ${key(t)}`).toBe("wall");
      }
      expect(world.structures).toHaveLength(
        view.places.length + view.decor.length + view.props.length,
      );
    });

    it(`${view.name}: every door is reachable from the arrival hex, the window lifted`, () => {
      for (const place of view.places) {
        const path = findPath(terrain, world.actors, view.arrival, place.at, false);
        expect(path, place.id).not.toBeNull();
        expect(path!.at(-1)).toEqual(place.at);
      }
    });

    it(`${view.name}: the present figures are actors on their hexes, on floor, facing their side`, () => {
      expect(others).toHaveLength(view.figures.length);
      for (const figure of view.figures) {
        const actor = others.find((a) => a.id === figure.id);
        expect(actor?.tile).toEqual(figure.at);
        expect(actor?.side).toBe("adventurer");
        expect(actor?.mark).toBeNull();
        expect(actor?.facing).toBe(figure.facing === "left" ? 3 : 0);
        expect(kindAt(terrain, figure.at)).toBe("floor");
      }
    });

    it(`${view.name}: a tap is a place on its footprint and door, a figure, a decor, a prop or ground`, () => {
      for (const place of view.places) {
        for (const t of footprint(view, place)) {
          expect(hubTap(view, t)).toEqual({ kind: "place", place });
        }
      }
      for (const figure of view.figures)
        expect(hubTap(view, figure.at)).toEqual({ kind: "figure", figure });
      for (const decor of view.decor) {
        expect(hubTap(view, decor.at)).toEqual({ kind: "decor", id: decor.id });
      }
      for (const prop of view.props)
        expect(hubTap(view, prop.at)).toEqual({ kind: "prop", id: prop.id });
      expect(hubTap(view, view.arrival)).toEqual({ kind: "ground" });
    });
  }
});

describe("the finder in a hub (CLI-03f, AC-4)", () => {
  const town = HUB_VIEWS.get(1)!;
  const world = hubWorld(town, town.arrival);
  const guild = town.places.find((p) => p.id === "guild")!;

  it("bounded (a zone's), the Guild's door on row 12 is beyond the window's ring", () => {
    expect(guild.at.y).toBe(12);
    expect(findPath(world.terrain, world.actors, town.arrival, guild.at)).toBeNull();
  });

  it("unbounded, a pinned path from the arrival hex to the Guild's door", () => {
    const path = findPath(world.terrain, world.actors, town.arrival, guild.at, false);
    expect(path?.map(key)).toEqual(PINNED_GUILD);
  });
});

/** The town's arrival hex (2, 0) to the Guild's door (5, 12): 14 steps, the placeholder's tie rule. */
const PINNED_GUILD: readonly string[] = [
  "3,0",
  "4,0",
  "4,1",
  "5,2",
  "4,3",
  "4,4",
  "3,5",
  "4,6",
  "4,7",
  "4,8",
  "3,9",
  "4,10",
  "4,11",
  "5,12",
];

describe("a hub's ground (CLI-03g1, AC-2)", () => {
  for (const view of HUB_VIEWS.values()) {
    const world = hubWorld(view, view.arrival);
    const { terrain } = world;
    const ground = terrain.ground!;
    const at = (t: Tile) => ground[t.y * terrain.width + t.x];

    it(`${view.name}: the island grass or earth, every other hex water and wall; the void water`, () => {
      expect(ground).toHaveLength(terrain.width * terrain.height);
      for (let y = 0; y < terrain.height; y++) {
        for (let x = 0; x < terrain.width; x++) {
          const g = at({ x, y });
          if (onIsland(view, { x, y })) expect(g === "grass" || g === "earth").toBe(true);
          else {
            expect(g).toBe("water");
            expect(kindAt(terrain, { x, y })).toBe("wall");
          }
        }
      }
      expect(world.void).toBe("water");
    });

    it(`${view.name}: every path hex earth and floor; the arrival and every door land`, () => {
      const path = HUB_PATHS.get(view)!;
      expect(path.length).toBeGreaterThan(0);
      for (const tile of path) {
        expect(at(tile), key(tile)).toBe("earth");
        expect(kindAt(terrain, tile), key(tile)).toBe("floor");
      }
      // Earth is the path's only: nothing else is drawn as trodden ground.
      const onPath = new Set(path.map(key));
      expect(ground.filter((g) => g === "earth")).toHaveLength(onPath.size);
      for (const tile of [view.arrival, ...view.places.map((p) => p.at)]) {
        expect(at(tile), key(tile)).not.toBe("water");
      }
    });
  }

  it("no water hex is floor, in any fixture", () => {
    const worlds = [
      ...Object.values(FIXTURES),
      ...[...HUB_VIEWS.values()].map((view) => hubWorld(view, view.arrival)),
    ];
    for (const { name, terrain } of worlds) {
      terrain.ground?.forEach((g, i) => {
        if (g === "water") expect(terrain.kinds[i], name).not.toBe("floor");
        if (g === "water") expect(terrain.hidden[i], name).not.toBe("floor");
        if (g === "earth") expect(terrain.kinds[i], name).toBe("floor");
      });
    }
  });
});
