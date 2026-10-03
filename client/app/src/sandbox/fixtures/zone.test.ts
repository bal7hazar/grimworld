import { describe, expect, it } from "vitest";
import { initialState } from "../wiring";
import { kindAt } from "../world";
import { globalTile } from "./region";
import { insideOutline, zoneWorld } from "./zone";

describe("the seed's zone as a fixture (CLI-03c)", () => {
  const entry = globalTile(0, 105);
  const world = zoneWorld(entry);

  it("is 3 × 2 chunks, the adventurer on the entry tile, floor", () => {
    expect(world.terrain.width).toBe(45);
    expect(world.terrain.height).toBe(30);
    expect(world.actors[0]).toMatchObject({ id: 1, side: "adventurer", tile: entry });
    expect(world.terrain.hidden[entry.y * 45 + entry.x]).toBe("floor");
  });

  it("follows the outline: chunk (2, 1) void, chunk (2, 0) columns 0–11, chunk (1, 1) cut", () => {
    expect(insideOutline(2, { x: 35, y: 20 })).toBe(false);
    expect(insideOutline(2, { x: 41, y: 3 })).toBe(true);
    expect(insideOutline(2, { x: 42, y: 3 })).toBe(false);
    expect(insideOutline(2, { x: 29, y: 24 })).toBe(true);
    expect(insideOutline(2, { x: 24, y: 25 })).toBe(true);
    expect(insideOutline(2, { x: 25, y: 25 })).toBe(false);
    expect(kindAt(world.terrain, { x: 35, y: 20 })).toBe("wall");
  });

  it("opens on the entry chunk: the others are not revealed, void stays wall (D-134, D-136)", () => {
    const state = initialState(world);
    const { terrain } = state.world;
    expect(kindAt(terrain, entry)).toBe("floor");
    expect(kindAt(terrain, { x: 20, y: 7 })).toBe("unrevealed");
    expect(kindAt(terrain, { x: 35, y: 20 })).toBe("wall");
    const revealed = terrain.kinds.filter((k) => k !== "unrevealed").length;
    // The entry chunk (225 tiles) and the void tiles of chunk (2, 0), (1, 1) and (2, 1).
    expect(revealed).toBe(225 + 3 * 15 + 5 * 5 + 15 * 15);
  });

  it("opens the outpost's way in on its own chunk, the far end", () => {
    const far = zoneWorld(globalTile(2, 115));
    const state = initialState(far);
    expect(kindAt(state.world.terrain, { x: 40, y: 7 })).toBe("floor");
    expect(kindAt(state.world.terrain, { x: 3, y: 7 })).toBe("unrevealed");
  });
});

describe("the zone's ground (CLI-03g1, AC-2)", () => {
  const world = zoneWorld(globalTile(0, 105));
  const { terrain } = world;

  it("grass inside the outline, water and wall outside it; the void is water", () => {
    const ground = terrain.ground!;
    expect(ground).toHaveLength(terrain.width * terrain.height);
    const counts = { grass: 0, water: 0, earth: 0 };
    for (let y = 0; y < terrain.height; y++) {
      for (let x = 0; x < terrain.width; x++) {
        const i = y * terrain.width + x;
        const inside = insideOutline(2, { x, y });
        expect(ground[i], `${x},${y}`).toBe(inside ? "grass" : "water");
        if (!inside) {
          expect(terrain.kinds[i]).toBe("wall");
          expect(terrain.hidden[i]).toBe("wall");
        }
        counts[ground[i]!] += 1;
      }
    }
    expect(counts.water).toBeGreaterThan(0);
    expect(counts.earth).toBe(0);
    expect(world.void).toBe("water");
  });
});
