import type { Tile, ViewActor, ViewState, ViewTile } from "./view";

/**
 * Exploration by sight (CLI-03n, D-213): presentation only, never read by a rule. The chain
 * reveals a whole chunk when sight touches it (ADR-0006); the map shows only what the adventurer
 * has had in sight since the instance opened:
 *
 * | A tile | Drawn as |
 * | --- | --- |
 * | never in sight (`unseen`), its chunk revealed or not | hidden, as an unrevealed tile |
 * | in sight once, not now (`explored`) | grayscale; goblins on it drawn, in colour |
 * | in sight now (`inSight`) | in colour |
 *
 * The explored set lives with the instance's state on the client, outside the renderer's frames:
 * it grows only when sight changes (a step), and a new instance starts it again. It is not kept:
 * a reload starts it from the sight of that moment (accepted for now, CLI-03n).
 */

/** A tile's key in an explored set. */
export const tileKey = (tile: Tile): string => `${tile.x},${tile.y}`;

/** The tiles in sight at least once since the instance opened, by `tileKey`. */
export type Explored = ReadonlySet<string>;

export const NOTHING_EXPLORED: Explored = new Set();

/** The explored set grown by the tiles in sight; the same set when sight brought nothing new. */
export function explore(explored: Explored, sight: readonly Tile[]): Explored {
  let grown: Set<string> | null = null;
  for (const tile of sight) {
    const key = tileKey(tile);
    if (explored.has(key)) continue;
    grown ??= new Set(explored);
    grown.add(key);
  }
  return grown ?? explored;
}

export type TileSight = "unseen" | "explored" | "inSight";

/** What a tile is to the adventurer's eye: `inSight` holds the tiles in sight now, by key. */
export function tileSight(tile: Tile, explored: Explored, inSight: ReadonlySet<string>): TileSight {
  const key = tileKey(tile);
  if (inSight.has(key)) return "inSight";
  return explored.has(key) ? "explored" : "unseen";
}

/** The tiles to draw: a tile never in sight is sent as unrevealed, whatever the chain holds. */
export function fogTiles(tiles: readonly ViewTile[], explored: Explored): ViewTile[] {
  return tiles.map((tile) =>
    tile.kind === "unrevealed" || explored.has(tileKey(tile))
      ? tile
      : { x: tile.x, y: tile.y, kind: "unrevealed" },
  );
}

/**
 * The actors to draw: the adventurer, and every goblin standing on an explored tile (in sight
 * now or before), as the client holds it. Drawn only: which goblin can be tapped or targeted is
 * not decided here (the wiring keeps it to the goblins in sight).
 */
export function drawnActors(
  actors: readonly ViewActor[],
  adventurerId: number,
  explored: Explored,
): ViewActor[] {
  return actors.filter((a) => a.id === adventurerId || explored.has(tileKey(a.tile)));
}

/** How many tiles a view draws in each state, and the goblins it draws beyond sight. */
export interface FogCounts {
  /** Tiles drawn hidden (unrevealed, or never in sight). */
  readonly hidden: number;
  /** Tiles drawn in grayscale: explored, out of sight. */
  readonly explored: number;
  readonly inSight: number;
  /** Goblins drawn on a tile out of sight. */
  readonly goblinsBeyond: number;
}

export function fogCounts(view: ViewState): FogCounts {
  const inSight = new Set(view.sight.map(tileKey));
  let hidden = 0;
  let explored = 0;
  let seen = 0;
  for (const tile of view.tiles) {
    if (tile.kind === "unrevealed") hidden += 1;
    else if (inSight.has(tileKey(tile))) seen += 1;
    else explored += 1;
  }
  let goblinsBeyond = 0;
  for (const actor of view.actors) {
    if (actor.side === "goblin" && !inSight.has(tileKey(actor.tile))) goblinsBeyond += 1;
  }
  return { hidden, explored, inSight: seen, goblinsBeyond };
}
