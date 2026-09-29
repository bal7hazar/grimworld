import type { Facing, Tile, ViewActor, ViewArcs } from "../render/view";
import { CHUNK, type Terrain, inBounds, kindAt, sameTile } from "./world";

/**
 * The only file of `client/app` that computes what the chain decides (ORCH-client-visual §6.1).
 * Every function here is a stand-in until `client/sim` has the real rule; CLI-03 deletes this
 * file. Only the sandbox's wiring (`wiring.ts`) imports it, which a test checks. No randomness, no
 * clock.
 */

/**
 * PLACEHOLDER until CLI-02. The neighbour of a tile in a direction: `Direction::next` of the map
 * library (`hexx-cairo`, `direction.cairo`), pointy-top, odd-r, written on global coordinates. Its
 * numbering: 0 East, 1 North-East, 2 North-West, 3 West, 4 South-West, 5 South-East.
 */
export function neighbour(tile: Tile, direction: Facing): Tile {
  const odd = tile.y & 1;
  switch (direction) {
    case 0:
      return { x: tile.x - 1, y: tile.y };
    case 1:
      return { x: tile.x - 1 + odd, y: tile.y + 1 };
    case 2:
      return { x: tile.x + odd, y: tile.y + 1 };
    case 3:
      return { x: tile.x + 1, y: tile.y };
    case 4:
      return { x: tile.x + odd, y: tile.y - 1 };
    case 5:
      return { x: tile.x - 1 + odd, y: tile.y - 1 };
  }
}

const FACINGS: readonly Facing[] = [0, 1, 2, 3, 4, 5];

function turn(facing: Facing, by: number): Facing {
  return ((facing + by) % 6) as Facing;
}

/**
 * PLACEHOLDER until CLI-02. Hex distance between two tiles (the library's `distance`), through
 * cube coordinates of the odd-r layout.
 */
export function distance(a: Tile, b: Tile): number {
  const aq = a.x - (a.y - (a.y & 1)) / 2;
  const bq = b.x - (b.y - (b.y & 1)) / 2;
  const dq = aq - bq;
  const dr = a.y - b.y;
  return (Math.abs(dq) + Math.abs(dr) + Math.abs(dq + dr)) / 2;
}

/** Sight radius (design/18, ADR-0006). */
export const SIGHT_RADIUS = 6;

/**
 * PLACEHOLDER until CLI-02. The tiles in sight: design/18 *What the adventurer sees*, a hexagon of
 * radius 6 around the adventurer, line of sight not required. Row by row, lowest tile first.
 */
export function tilesInSight(terrain: Terrain, centre: Tile): Tile[] {
  const tiles: Tile[] = [];
  for (let y = centre.y - SIGHT_RADIUS; y <= centre.y + SIGHT_RADIUS; y++) {
    for (let x = centre.x - SIGHT_RADIUS - 1; x <= centre.x + SIGHT_RADIUS + 1; x++) {
      const tile = { x, y };
      if (inBounds(terrain, tile) && distance(centre, tile) <= SIGHT_RADIUS) tiles.push(tile);
    }
  }
  return tiles;
}

/**
 * PLACEHOLDER until CLI-02. The four arcs of an actor: design/04 *Facing and arcs (D-41)*: front
 * `d`, front-side `d ± 1`, rear-side `d ± 2`, back `d + 3`. Design/11 tints them "when you can
 * reach them"; here, a tile can be reached when it is floor.
 */
export function arcsOf(terrain: Terrain, actor: ViewActor): ViewArcs {
  const at = (by: number) => neighbour(actor.tile, turn(actor.facing, by));
  const reachable = (tiles: Tile[]) => tiles.filter((t) => kindAt(terrain, t) === "floor");
  return {
    actorId: actor.id,
    front: reachable([at(0)]),
    frontSide: reachable([at(1), at(5)]),
    rearSide: reachable([at(2), at(4)]),
    back: reachable([at(3)]),
  };
}

/**
 * PLACEHOLDER until CLI-02. The facing toward an adjacent tile, for a turn (design/04 *Actions*:
 * turn), or null when the tile is not adjacent.
 */
export function facingToward(from: Tile, to: Tile): Facing | null {
  return FACINGS.find((d) => sameTile(neighbour(from, d), to)) ?? null;
}

/**
 * PLACEHOLDER until CLI-02 (and CLI-03 for paths). One step of an actor toward a target tile:
 * design/04 *Actions*: a move is one tile in one of six directions and sets facing to the direction
 * moved. The step goes to a neighbouring floor tile that no actor holds and that is strictly
 * closer to the target; among several, the lowest tile index (`y`, then `x`: design/04 and the
 * determinism rules, "lowest entity id, then lowest tile index"). Null when there is none.
 */
export function stepToward(
  terrain: Terrain,
  actors: readonly ViewActor[],
  moverId: number,
  target: Tile,
): { tile: Tile; facing: Facing } | null {
  const mover = actors.find((a) => a.id === moverId);
  if (!mover) return null;
  let best: { tile: Tile; facing: Facing } | null = null;
  let bestDistance = distance(mover.tile, target);
  for (const d of FACINGS) {
    const tile = neighbour(mover.tile, d);
    if (kindAt(terrain, tile) !== "floor") continue;
    if (actors.some((a) => sameTile(a.tile, tile))) continue;
    const left = distance(tile, target);
    const lower =
      best !== null && (tile.y < best.tile.y || (tile.y === best.tile.y && tile.x < best.tile.x));
    if (left < bestDistance || (left === bestDistance && lower)) {
      best = { tile, facing: d };
      bestDistance = left;
    }
  }
  return best;
}

/**
 * PLACEHOLDER until CLI-02. The actors the adventurer sees: design/18 *What the adventurer sees*,
 * the adventurer and the goblins within sight (radius 6, line of sight not required).
 */
export function visibleActors(terrain: Terrain, actors: readonly ViewActor[]): ViewActor[] {
  const adventurer = actors.find((a) => a.side === "adventurer");
  if (!adventurer) return [];
  const sight = tilesInSight(terrain, adventurer.tile);
  return actors.filter((a) => a.side === "adventurer" || sight.some((t) => sameTile(t, a.tile)));
}

/**
 * PLACEHOLDER until CLI-02. The reveal: ADR-0006 §2 and §4, "a chunk is revealed when sight
 * touches one of its tiles", so sight never reaches an unrevealed tile. Every chunk that sight
 * from `centre` touches while unrevealed takes the terrain the fixture holds for it (`hidden`),
 * which stands for the generation at reveal.
 */
export function revealInSight(terrain: Terrain, centre: Tile): Terrain {
  const chunks = new Set<string>();
  for (const tile of tilesInSight(terrain, centre)) {
    if (kindAt(terrain, tile) === "unrevealed") {
      chunks.add(`${Math.floor(tile.x / CHUNK)},${Math.floor(tile.y / CHUNK)}`);
    }
  }
  if (chunks.size === 0) return terrain;
  const kinds = terrain.kinds.map((kind, index) => {
    const x = index % terrain.width;
    const y = Math.floor(index / terrain.width);
    const touched = chunks.has(`${Math.floor(x / CHUNK)},${Math.floor(y / CHUNK)}`);
    return touched && kind === "unrevealed" ? (terrain.hidden[index] ?? "wall") : kind;
  });
  return { ...terrain, kinds };
}
