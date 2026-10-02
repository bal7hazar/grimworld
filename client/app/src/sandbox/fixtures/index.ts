import type { Tile } from "../../render/view";
import { CHUNK, type SandboxWorld } from "../world";
import { fromAscii } from "./build";
import { SEED_GATES, globalTile } from "./region";
import { zoneWorld } from "./zone";

/**
 * The sandbox's fixtures, chosen by `?fixture=<name>`. Maps are drawn as on screen: first line
 * North, first character West (see `build.ts`).
 */

/** An open meadow (design/18: 80–90 % walkable), a pack of five asleep, some of it out of sight. */
const meadow = fromAscii({
  name: "meadow",
  description: "Open meadow, 2 × 2 chunks; a pack of five asleep north-west, partly out of sight",
  profession: "vanguard",
  adventurerFacing: 2,
  goblins: { facing: 5, mark: "asleep" },
  overrides: { 1: { facing: 0 }, 2: { facing: 4 }, 4: { facing: 3 } },
  map: [
    "##############################",
    "#............................#",
    "#....#.............#.........#",
    "#............................#",
    "#.........#..........#.......#",
    "#..#.........................#",
    "#..............#.............#",
    "#............................#",
    "#......#.........r.s.........#",
    "#...............r..h.....#...#",
    "#............................#",
    "#....#.............r.........#",
    "#............................#",
    "#..........#.................#",
    "#............................#",
    "#...................A........#",
    "#......#.....................#",
    "#............................#",
    "#....................#.......#",
    "#..#.........................#",
    "#............#...............#",
    "#............................#",
    "#.......#...............#....#",
    "#............................#",
    "#..#...........#.............#",
    "#............................#",
    "#......#..............#......#",
    "#............................#",
    "#..........#.................#",
    "##############################",
  ],
});

/**
 * A cave (design/18: 45–55 % walkable, pockets and chokepoints) with a pack of ten on watch, all
 * in sight at the start: with the adventurer, SPK-6's row "a room of 15 × 15 with 10 animated
 * actors".
 */
const cave = fromAscii({
  name: "cave",
  description: "Cave, 2 × 1 chunks, walls and chokepoints; a pack of ten on watch, all in sight",
  profession: "warden",
  adventurerFacing: 3,
  goblins: { facing: 0, mark: null },
  overrides: {
    0: { facing: 5 },
    1: { facing: 4 },
    2: { facing: 1 },
    3: { facing: 0 },
    4: { facing: 2 },
    5: { facing: 3 },
    6: { facing: 0 },
    7: { facing: 5 },
    8: { facing: 1 },
    9: { facing: 2 },
  },
  map: [
    "##############################",
    "###....####.......###....#####",
    "##......##.........#......####",
    "##.......#....r.....#.......##",
    "###..........s.l....##......##",
    "####....##..h..r....##...#..##",
    "###.....###...s..l..#.......##",
    "##.......##..r...A...#......##",
    "##..#.....#....H.....#......##",
    "##.........##.s......##...#.##",
    "###.........##......###.....##",
    "####..........##...#####...###",
    "#####.....####...........#####",
    "######...######....###..######",
    "##############################",
  ],
});

/** Lines of a map drawn by a pattern: border and chunk corners wall (D-134), rocks, actors. */
function patternMap(
  width: number,
  height: number,
  rock: (x: number, y: number) => boolean,
  placed: readonly (readonly [Tile, string])[],
): string[] {
  const lines: string[] = [];
  for (let y = height - 1; y >= 0; y--) {
    let line = "";
    for (let x = width - 1; x >= 0; x--) {
      const glyph = placed.find(([t]) => t.x === x && t.y === y)?.[1];
      const border = x === 0 || y === 0 || x === width - 1 || y === height - 1;
      const corner =
        (x % CHUNK === 0 || x % CHUNK === CHUNK - 1) &&
        (y % CHUNK === 0 || y % CHUNK === CHUNK - 1);
      line += glyph ?? (border || corner || rock(x, y) ? "#" : ".");
    }
    lines.push(line);
  }
  return lines;
}

/**
 * The edge of the unrevealed: 3 × 2 chunks of which three are not revealed, drawn as wall
 * (D-136). The adventurer stands 7 tiles from the edge, just out of sight of it.
 */
const edge = fromAscii({
  name: "edge",
  description: "3 × 2 chunks, three not revealed (wall, D-136); the edge 7 tiles away",
  profession: "cleric",
  adventurerFacing: 1,
  goblins: { facing: 0, mark: "alerted" },
  overrides: { 1: { mark: "engaged", facing: 2 }, 2: { mark: "fleeing", facing: 3 } },
  unrevealed: [
    [2, 0],
    [2, 1],
    [1, 1],
  ],
  path: [
    { x: 24, y: 6 },
    { x: 25, y: 6 },
    { x: 26, y: 6 },
  ],
  map: patternMap(45, 30, (x, y) => (x * 7 + y * 11) % 17 === 0, [
    [{ x: 23, y: 7 }, "A"],
    [{ x: 19, y: 10 }, "s"],
    [{ x: 21, y: 3 }, "r"],
    [{ x: 26, y: 9 }, "h"],
  ]),
});

/** The seed's zone, entered through the town's gate 1 (CLI-03c): the loop's instance. */
const zone = zoneWorld(globalTile(SEED_GATES[0]!.entry_chunk, SEED_GATES[0]!.entry_tile));

export const FIXTURES: Readonly<Record<string, SandboxWorld>> = { meadow, cave, edge, zone };

export const DEFAULT_FIXTURE = "meadow";

export function fixtureNamed(name: string | null): SandboxWorld {
  return FIXTURES[name ?? DEFAULT_FIXTURE] ?? meadow;
}
