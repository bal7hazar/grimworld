import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { tileToPixel } from "../../input/coords";
import { BUILDINGS as HUB_BUILDINGS } from "../../sandbox/fixtures/hubs";
import { DEFAULT_DEPTH, footprint } from "../../sandbox/fixtures/hubWorld";
import { sideOf } from "../model";
import {
  BRIDGES,
  BUILDINGS,
  BUILDING_DEPTH,
  KINDS,
  type Kind,
  NPCS,
  PROPS,
  SIDE,
  kindOf,
  kindTableProblems,
  spritesOf,
} from "./kinds";
import { footprintAt } from "./records";

/** Every sprite name `tools/art/manifest.toml` builds into the map's pages, with its role. */
function manifestSprites(): Map<string, string> {
  const text = readFileSync(
    new URL("../../../../../tools/art/manifest.toml", import.meta.url),
    "utf8",
  );
  const names = new Map<string, string>();
  for (const m of text.matchAll(/\[\[(sprite|still)\]\]\nname = "([^"]+)"\nrole = "([^"]+)"/g)) {
    names.set(m[2]!, m[3]!);
  }
  return names;
}

describe("the kind table (CLI-09e)", () => {
  it("is sound, and every sprite it draws is in the manifest", () => {
    const sprites = manifestSprites();
    expect(sprites.size).toBeGreaterThan(100);
    expect(kindTableProblems(KINDS, new Set(sprites.keys()))).toEqual([]);
  });

  it("draws each category from its own role of the atlas", () => {
    const sprites = manifestSprites();
    const roles = (kinds: readonly Kind[]) =>
      new Set(kinds.flatMap((kind) => spritesOf(kind).map((s) => sprites.get(s))));
    expect(roles(PROPS)).toEqual(new Set(["prop"]));
    expect(roles(BUILDINGS)).toEqual(new Set(["building"]));
    expect(roles(BRIDGES)).toEqual(new Set(["building"]));
    expect(roles(NPCS)).toEqual(new Set(["npc", "caste", "profession"]));
  });

  it("offers every building and prop still of the manifest but the hubs' sheep", () => {
    const sprites = manifestSprites();
    const drawn = new Set(KINDS.flatMap(spritesOf));
    const left = [...sprites]
      .filter(([name, role]) => (role === "building" || role === "prop") && !drawn.has(name))
      .map(([name]) => name);
    // The sheep is an NPC, idle (`npc_sheep`); the hubs keep their still.
    expect(left).toEqual(["sheep"]);
    const npcs = [...sprites].filter(([, role]) => role === "npc").map(([name]) => name);
    expect(npcs.filter((name) => !drawn.has(name))).toEqual([]);
  });

  it("counts: 14 props, 47 buildings, 23 NPCs, 2 bridges", () => {
    expect([PROPS.length, BUILDINGS.length, NPCS.length, BRIDGES.length]).toEqual([14, 47, 23, 2]);
    expect(KINDS.length).toBe(86);
  });

  it("finds a kind by id, and only a kind", () => {
    expect(kindOf("castle")?.category).toBe("building");
    expect(kindOf("pawn")?.category).toBe("npc");
    expect(kindOf("stone_bridge")?.category).toBe("bridge");
    expect(kindOf("rock")?.category).toBe("prop");
    expect(kindOf("nothing")).toBeNull();
  });

  it("proposes blocking for trees, rocks, gold stones, water rocks, skull spikes and the cannon", () => {
    expect(PROPS.filter((p) => p.blocks).map((p) => p.id)).toEqual([
      "tree",
      "rock",
      "gold_stone",
      "water_rock",
      "skull_spike",
      "cannon",
    ]);
  });

  it("turns the cannon by facing, its West facings the mirrored East ones", () => {
    const cannon = kindOf("cannon");
    expect(cannon?.category === "prop" && cannon.turn).toBe("facing");
    if (cannon?.category !== "prop") return;
    // East / West, North-East / North-West, South-East / South-West draw the same sprite.
    expect(cannon.art[0]).toBe(cannon.art[3]);
    expect(cannon.art[1]).toBe(cannon.art[2]);
    expect(cannon.art[5]).toBe(cannon.art[4]);
    expect(PROPS.filter((p) => p.turn === "facing").map((p) => p.id)).toEqual(["cannon"]);
  });

  it("refuses a table that does not hold together", () => {
    const bad: Kind[] = [
      { id: "Rock", label: "x", category: "prop", art: [], turn: "flip", blocks: true },
      { id: "gun", label: "x", category: "prop", art: ["a"], turn: "facing", blocks: true },
      {
        id: "hall",
        label: "x",
        category: "building",
        sprite: "hall",
        width: 0,
        depth: 9,
      },
      { id: "hall", label: "x", category: "bridge", sprite: "b", deck: 0 },
    ];
    expect(kindTableProblems(bad, new Set(["a"]))).toEqual([
      "Rock: not a kind id",
      "Rock: no art",
      "gun: a facing prop needs six sprites",
      "hall: a width of 0",
      "hall: a depth of 9",
      "hall: no sprite hall in the atlas",
      "hall: the id is used twice",
      "hall: a deck of 0",
      "hall: no sprite b in the atlas",
    ]);
  });
});

describe("the footprints", () => {
  const anchors = [
    { x: 0, y: 0 },
    { x: 3, y: 1 },
    { x: -4, y: -3 },
  ];

  it("sides are numbered as the screen shows them", () => {
    for (const anchor of anchors) {
      const c = tileToPixel(anchor);
      const at = (side: number) => tileToPixel(sideOf(anchor, side));
      expect(at(SIDE.east).x).toBeGreaterThan(c.x);
      expect(at(SIDE.west).x).toBeLessThan(c.x);
      expect(at(SIDE.northEast).y).toBeLessThan(c.y);
      expect(at(SIDE.northEast).x).toBeGreaterThan(c.x);
      expect(at(SIDE.northWest).x).toBeLessThan(c.x);
      expect(at(SIDE.southEast).y).toBeGreaterThan(c.y);
      expect(at(SIDE.southEast).x).toBeGreaterThan(c.x);
      expect(at(SIDE.southWest).x).toBeLessThan(c.x);
    }
  });

  it("are the hubs' footprints, for every building, depth and row parity (CLI-09 O-6)", () => {
    expect(BUILDING_DEPTH).toBe(DEFAULT_DEPTH);
    for (const kind of BUILDINGS) {
      for (const at of anchors) {
        for (const depth of [0, 1, 2]) {
          const hub = footprint({ origin: { x: 7, y: 11 } }, { at, width: kind.width, depth });
          expect(footprintAt(kind, at, depth), kind.id).toEqual(hub);
        }
      }
    }
  });

  it("take the hubs' widths for the buildings the hubs draw", () => {
    for (const [id, [width]] of Object.entries(HUB_BUILDINGS)) {
      const kind = BUILDINGS.find((k) => k.id === id);
      expect(kind?.width, id).toBe(width);
    }
  });

  it("cover three hexes for the small ones, five at 128 px, nine for the castle", () => {
    const size = (id: string) =>
      footprintAt(
        BUILDINGS.find((k) => k.id === id)!,
        anchors[0]!,
      ).length;
    expect([size("watchtower"), size("hut"), size("cottage"), size("inn"), size("castle")]).toEqual(
      [3, 3, 3, 5, 9],
    );
  });

  it("measure the animated huts at their visible width, not at a cell's (the Goblin Hut's cut)", () => {
    // The pack's opaque columns of frame 0: the hut 140 px (x 26 to 166 of its 192 px cell), the
    // Fish Hut 147, the cave 154. The old 256 px cut gave the Goblin Hut 230 px, a neighbour's 64 px
    // included, and a footprint a hex too wide on the row behind.
    const widths = (ids: string[]) => ids.map((id) => BUILDINGS.find((k) => k.id === id)?.width);
    expect(widths(["goblin_hut", "fish_hut", "cave"])).toEqual([140, 147, 154]);
    const hut = BUILDINGS.find((k) => k.id === "goblin_hut")!;
    expect(footprintAt(hut, anchors[0]!)).toHaveLength(5);
    expect(footprintAt({ ...hut, width: 230 }, anchors[0]!)).toHaveLength(7);
  });
});
