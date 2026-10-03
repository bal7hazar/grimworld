import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { fixtureNamed } from "../sandbox/fixtures";
import { initialState } from "../sandbox/wiring";
import { OBSTACLES, hexHash, obstacleOf } from "./obstacles";

/** The `[[still]]` entries of `tools/art/manifest.toml`: name → role. */
function manifestStills(): Map<string, string> {
  const text = readFileSync(
    new URL("../../../../tools/art/manifest.toml", import.meta.url),
    "utf8",
  );
  const stills = new Map<string, string>();
  for (const m of text.matchAll(/\[\[still\]\]\nname = "([^"]+)"\nrole = "([^"]+)"/g)) {
    stills.set(m[1]!, m[2]!);
  }
  return stills;
}

/** Every wall hex of the zone fixture on land, revealed or not: what its obstacles stand on. */
function zoneWalls(): { x: number; y: number }[] {
  const { terrain } = initialState(fixtureNamed("zone")).world;
  const walls: { x: number; y: number }[] = [];
  terrain.hidden.forEach((kind, i) => {
    if (kind === "wall" && terrain.ground?.[i] !== "water")
      walls.push({ x: i % terrain.width, y: Math.floor(i / terrain.width) });
  });
  return walls;
}

describe("the zone's wall obstacles (CLI-03h)", () => {
  it("every obstacle is a prop still of the manifest: rocks, bushes, stumps and trees", () => {
    const stills = manifestStills();
    for (const { sprite } of OBSTACLES)
      expect([sprite, stills.get(sprite)]).toEqual([sprite, "prop"]);
    const kinds = new Set(OBSTACLES.map((o) => o.sprite.replace(/\d+$/, "")));
    expect(kinds).toEqual(new Set(["rock", "bush", "stump", "tree"]));
  });

  it("the same hex always shows the same still: a hash of its coordinates, nothing else", () => {
    for (const tile of zoneWalls()) {
      expect(obstacleOf(tile, OBSTACLES)).toEqual(obstacleOf({ ...tile }, OBSTACLES));
      expect(hexHash(tile)).toBe(hexHash({ x: tile.x, y: tile.y }));
    }
    expect(hexHash({ x: 3, y: 4 })).not.toBe(hexHash({ x: 4, y: 3 }));
  });

  it("over the zone's walls, each still about as often as its weight, both ways mirrored", () => {
    const walls = zoneWalls();
    expect(walls.length).toBeGreaterThan(100);
    const counts = new Map<string, number>();
    let mirrored = 0;
    for (const tile of walls) {
      const choice = obstacleOf(tile, OBSTACLES)!;
      counts.set(choice.sprite, (counts.get(choice.sprite) ?? 0) + 1);
      if (choice.mirror) mirrored += 1;
    }
    const total = OBSTACLES.reduce((sum, o) => sum + o.weight, 0);
    const share = (prefix: string) =>
      [...counts].filter(([s]) => s.startsWith(prefix)).reduce((sum, [, n]) => sum + n, 0) /
      walls.length;
    const weight = (prefix: string) =>
      OBSTACLES.filter((o) => o.sprite.startsWith(prefix)).reduce((sum, o) => sum + o.weight, 0) /
      total;
    for (const kind of ["rock", "bush", "stump", "tree"]) {
      expect(Math.abs(share(kind) - weight(kind))).toBeLessThan(0.12);
    }
    expect(mirrored / walls.length).toBeGreaterThan(0.3);
    expect(mirrored / walls.length).toBeLessThan(0.7);
  });

  it("only among the choices given; none without a choice", () => {
    const rocks = OBSTACLES.filter((o) => o.sprite.startsWith("rock"));
    for (const tile of zoneWalls()) {
      expect(obstacleOf(tile, rocks)!.sprite).toMatch(/^rock\d$/);
      expect(obstacleOf(tile, [])).toBeNull();
    }
  });
});
