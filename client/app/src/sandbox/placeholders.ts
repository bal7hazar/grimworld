import type { Facing, Tile, ViewActor, ViewArcs, ViewGoblin } from "../render/view";
import { GATE_KIND, type GateRecord, globalTile } from "./fixtures/region";
import { CHUNK, type Terrain, inBounds, kindAt, sameTile } from "./world";

/**
 * The only file of `client/app` that computes what the chain decides (ORCH-client-visual §6.1).
 * Every function here is a stand-in until `client/sim` has the real rule; CLI-03 deletes this
 * file. Only the sandbox's wiring (`wiring.ts`) and the loop's machine (`loop/machine.ts`, for
 * gates and hubs) import it, which a test checks. No randomness, no clock.
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

/** The simulation window (D-120): 15 columns × 16 rows around the adventurer. */
export const WINDOW = { columns: 15, rows: 16 } as const;

/**
 * PLACEHOLDER until CLI-02. Whether a tile lies in the window around `centre` (D-120): the
 * columns centred exactly (7 on each side), the 16 rows starting on the even row among
 * `centre.y - 8` and `centre.y - 7` (the sixteenth row absorbs the parity of the origin).
 */
export function inWindow(centre: Tile, tile: Tile): boolean {
  const half = (WINDOW.columns - 1) / 2;
  const top = centre.y - 8 + (centre.y & 1);
  return Math.abs(tile.x - centre.x) <= half && tile.y >= top && tile.y < top + WINDOW.rows;
}

/**
 * PLACEHOLDER until CLI-02. Whether a tile lies inside the window's outer ring: the window less its
 * first and last columns and rows. The ring is wall for the chain's tick (D-120; SPK-7 §4: the
 * flood never enters it, goblins there are frozen), so a path neither ends nor passes there.
 */
export function insideRing(centre: Tile, tile: Tile): boolean {
  const half = (WINDOW.columns - 1) / 2 - 1;
  const top = centre.y - 8 + (centre.y & 1);
  return Math.abs(tile.x - centre.x) <= half && tile.y > top && tile.y < top + WINDOW.rows - 1;
}

/** Ticks a step of a path costs: one (a placeholder, until the rules' move cost reaches here). */
export const TICKS_PER_STEP = 1;

/**
 * PLACEHOLDER until CLI-02 (design/02 *The planned queue*, the map library's finder, the flood of
 * the tick). The shortest path of the mover from `from` to `to`, first step first, `from`
 * excluded: over floor tiles no actor holds (walls and unrevealed tiles are not floor), inside
 * the window around `from` and off its outer ring (D-120, `insideRing`). Null when there is none,
 * or when `to` is `from`. A breadth-first flood from `to`, bounded by the window's 240 tiles.
 *
 * The tie rule is **a reading** of "lowest tile index" (design/04, the determinism rules): among
 * shortest paths, each step takes the neighbour of lowest index (`y`, then `x`). The map library's
 * finder may break ties otherwise; CLI-02 replaces this function by it, and its paths are the rule.
 */
export function findPath(
  terrain: Terrain,
  actors: readonly ViewActor[],
  from: Tile,
  to: Tile,
): Tile[] | null {
  const free = (tile: Tile) =>
    insideRing(from, tile) &&
    kindAt(terrain, tile) === "floor" &&
    !actors.some((a) => sameTile(a.tile, tile));
  if (sameTile(from, to) || !free(to)) return null;
  const key = (tile: Tile) => `${tile.x},${tile.y}`;
  const left = new Map<string, number>([[key(to), 0]]);
  let layer: Tile[] = [to];
  let reached = false;
  while (layer.length > 0 && !reached) {
    const next: Tile[] = [];
    for (const tile of layer) {
      const depth = left.get(key(tile)) ?? 0;
      for (const d of FACINGS) {
        const around = neighbour(tile, d);
        if (sameTile(around, from)) reached = true;
        if (left.has(key(around)) || !free(around)) continue;
        left.set(key(around), depth + 1);
        next.push(around);
      }
    }
    layer = next;
  }
  if (!reached) return null;
  const path: Tile[] = [];
  let at = from;
  while (!sameTile(at, to)) {
    let best: Tile | null = null;
    let bestLeft = Infinity;
    for (const d of FACINGS) {
      const around = neighbour(at, d);
      const n = left.get(key(around));
      if (n === undefined) continue;
      const lower =
        best !== null && (around.y < best.y || (around.y === best.y && around.x < best.x));
      if (n < bestLeft || (n === bestLeft && lower)) {
        best = around;
        bestLeft = n;
      }
    }
    if (!best) return null;
    path.push(best);
    at = best;
  }
  return path;
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

// --- hubs and the transitions (CLI-03c) ---------------------------------------------------------

/**
 * PLACEHOLDER until CLI-02 (and CLI-03 for gates). The hub gate the adventurer can leave by: D-148,
 * a gate is used by standing on its anchor tile; a hub gate (kind 1) of `location` whose anchor is
 * `tile`, or null. Requirements (rank, quest) are not checked: the fixed data has none.
 */
export function hubGateAt(
  gates: readonly GateRecord[],
  location: number,
  tile: Tile,
): GateRecord | null {
  return (
    gates.find(
      (g) =>
        g.source === location &&
        g.kind === GATE_KIND.hub &&
        sameTile(globalTile(g.anchor_chunk, g.anchor_tile), tile),
    ) ?? null
  );
}

/**
 * PLACEHOLDER until CLI-02 (and CLI-03 for gates). Where entering a gate puts the adventurer
 * (design/02 *Entering*): the gate's destination, on its entry tile. The gate's requirements are
 * met on fixed data; the entry draw is the chain's and decides nothing the sandbox draws.
 */
export function entryThrough(gate: GateRecord): { location: number; tile: Tile } {
  return { location: gate.destination, tile: globalTile(gate.entry_chunk, gate.entry_tile) };
}

/** How an expedition ended (design/02 *Ending an expedition*). */
export type ExpeditionEnd =
  | { readonly how: "gate"; readonly gate: GateRecord }
  | { readonly how: "travel back" }
  | { readonly how: "defeat" };

/**
 * PLACEHOLDER until CLI-02 (and CLI-03, CLI-08 for map travel). The hub an expedition ends in,
 * design/02's table: returned through a hub gate, that gate's hub; travelled back, or defeated,
 * the last hub visited. Travelling back to another unlocked hub is the world map's (CLI-08).
 */
export function hubAfter(end: ExpeditionEnd, lastHub: number): number {
  return end.how === "gate" ? end.gate.destination : lastHub;
}

/** A location's state before or after a step: what the stop conditions read. */
export interface StepState {
  readonly terrain: Terrain;
  readonly actors: readonly ViewActor[];
}

/** The stop conditions a step met; nothing met is `{ entered: [], revealed: false }`. */
export interface StepStops {
  /** Goblins in sight after the step and not before, lowest entity id first. */
  readonly entered: readonly ViewGoblin[];
  /** A chunk was revealed by the step: a tile unrevealed before is not after. */
  readonly revealed: boolean;
}

/**
 * PLACEHOLDER until CLI-02. The stop conditions of a planned queue that the sandbox can evaluate
 * after a step (design/02 *The planned queue and its stop conditions*): a goblin enters sight (the
 * goblins of `visibleActors` after the step that were not before), a chunk is revealed. The others
 * (damage, a condition, a goblin alerted or activating a skill, a Fate action) have no placeholder;
 * the next step being invalid is `stepToward`'s answer.
 */
export function stopsAfterStep(before: StepState, after: StepState): StepStops {
  const seen = new Set(visibleActors(before.terrain, before.actors).map((a) => a.id));
  const entered = visibleActors(after.terrain, after.actors)
    .filter((a): a is ViewGoblin => a.side === "goblin" && !seen.has(a.id))
    .sort((a, b) => a.id - b.id);
  const revealed = before.terrain.kinds.some(
    (kind, i) => kind === "unrevealed" && after.terrain.kinds[i] !== "unrevealed",
  );
  return { entered, revealed };
}
