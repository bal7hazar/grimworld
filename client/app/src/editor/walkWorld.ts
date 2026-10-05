import { TILE_WIDTH } from "../input/coords";
import type { GroundKind, Tile, TileKind, ViewActor, ViewStructure } from "../render/view";
import { footprint } from "../sandbox/fixtures/hubWorld";
import { ADVENTURER, BUILDINGS } from "../sandbox/fixtures/hubs";
import type { SandboxWorld } from "../sandbox/world";
import { type FitScore, fitChunks, fitted } from "./fit";
import {
  CHUNK,
  GROUND_KINDS,
  type MapDocument,
  WALL,
  groundOfCell,
  isOutside,
  isZone,
  keyOf,
  terrainOf,
} from "./model";
import type { MapObject } from "./objects";

/**
 * The map as the game builds it (CLI-09b, brief §2.8): a zone as an instance's `SandboxWorld`
 * (`fixtures/zone.ts`'s shape), a town or an outpost as a hub's (`fixtures/hubWorld.ts`'s), in the
 * fitted map's coordinates (D-216), for the preview walk and the town's checks (E-15). The walk
 * itself is the game's: the same `SandboxSession`, intents and finder, reached through the wiring.
 * Presentation, not a rule.
 */

/** A hub's footprints are measured from the hub's origin; any origin gives the same hexes. */
const ROOM = { origin: { x: 0, y: 0 } };

type Building = Extract<MapObject, { kind: "place" } | { kind: "decor" }>;

/** The hexes a building stands on (`footprint`, `hubWorld.ts:44-56`), its door included. */
export function footprintOf(object: Building): Tile[] {
  const [width] = BUILDINGS[object.building];
  return footprint(ROOM, { at: object.at, width, depth: object.depth });
}

/**
 * The wall hexes each town object stands on, as `structures()` makes them (`hubWorld.ts:72-108`):
 * a place's footprint but its door, a decor's whole footprint, a prop's hex. Figures, the arrival
 * and the zone's objects cover nothing.
 */
export function coversOf(object: MapObject): Tile[] {
  switch (object.kind) {
    case "place":
      return footprintOf(object).filter((t) => t.x !== object.at.x || t.y !== object.at.y);
    case "decor":
      return footprintOf(object);
    case "prop":
      return [object.at];
    default:
      return [];
  }
}

/** The hexes the town's buildings and props make walls of, by key. */
export function townCovers(doc: MapDocument): Set<number> {
  const out = new Set<number>();
  for (const object of doc.objects.values()) for (const t of coversOf(object)) out.add(keyOf(t));
  return out;
}

/** The fitted map's frame: its origin on the editor's plane, and its size in chunks. */
export type Frame = Pick<FitScore, "x0" | "y0" | "width" | "height">;

/** The document's fitted frame, or the best fit's when none was chosen; null for an empty map. */
export function frameOf(doc: MapDocument): Frame | null {
  const fit = fitted(doc);
  if (typeof fit !== "string") return fit;
  const best = fitChunks(doc);
  return typeof best === "string" ? null : best;
}

export interface WalkOptions {
  /** Where the adventurer starts, on the editor's plane. */
  readonly start: Tile;
  /** Fog on: a zone's chunks are revealed by sight, as on entering (§2.8). */
  readonly fog: boolean;
}

/** The professions the town's figure spots show: a spot carries no adventurer (§4.3). */
const FIGURES = ["warden", "vanguard", "cleric", "arcanist"] as const;

/** The adventurer's id in the preview's world. */
export const WALKER_ID = 1;

/**
 * The world of the preview walk, in the fitted map's coordinates (`frame`):
 *
 * - a zone: whole chunks of the fitted rectangle; inside the outline its painted terrain and
 *   ground, outside it and unpainted the void (wall, water), as `zoneWorld`; with the fog, every
 *   chunk of the outline but the start's is unrevealed (D-136), as on entering. No goblins: packs
 *   are markers, not actors (§2.8).
 * - a town: its painted terrain and ground, the buildings and props as structures on the walls
 *   they cover (a place's door stays floor), the figures standing on their spots, as `hubWorld`.
 */
export function walkWorld(doc: MapDocument, frame: Frame, options: WalkOptions): SandboxWorld {
  const zone = isZone(doc);
  const width = frame.width * CHUNK;
  const height = frame.height * CHUNK;
  const covered = zone ? new Set<number>() : townCovers(doc);
  const at = (t: Tile): Tile => ({ x: t.x - frame.x0, y: t.y - frame.y0 });
  const start = at(options.start);
  const inside = (x: number, y: number): boolean => {
    const cell = doc.hexes.get(keyOf({ x: x + frame.x0, y: y + frame.y0 }));
    return cell !== undefined && !(zone && isOutside(cell));
  };
  const hidden: TileKind[] = [];
  const ground: GroundKind[] = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const key = keyOf({ x: x + frame.x0, y: y + frame.y0 });
      const cell = doc.hexes.get(key);
      if (cell === undefined || (zone && isOutside(cell))) {
        hidden.push("wall");
        ground.push("water");
        continue;
      }
      hidden.push(terrainOf(cell) === WALL || covered.has(key) ? "wall" : "floor");
      ground.push(GROUND_KINDS[groundOfCell(cell)]!);
    }
  }
  const sx = Math.floor(start.x / CHUNK);
  const sy = Math.floor(start.y / CHUNK);
  const kinds =
    zone && options.fog
      ? hidden.map((kind, i): TileKind => {
          const x = i % width;
          const y = Math.floor(i / width);
          const startChunk = Math.floor(x / CHUNK) === sx && Math.floor(y / CHUNK) === sy;
          return startChunk || !inside(x, y) ? kind : "unrevealed";
        })
      : hidden;
  const actors: ViewActor[] = [
    {
      id: WALKER_ID,
      side: "adventurer",
      profession: ADVENTURER.profession,
      tile: start,
      facing: 0,
      mark: null,
    },
  ];
  const structures: ViewStructure[] = [];
  if (!zone) {
    let n = 0;
    for (const [id, object] of [...doc.objects].sort(([a], [b]) => a - b)) {
      if (object.kind === "figure") {
        actors.push({
          id: 100 + id,
          side: "adventurer",
          profession: FIGURES[n++ % FIGURES.length]!,
          tile: at(object.at),
          // West (3) for "left", East (0) for "right", as `hubWorld` turns a figure.
          facing: object.facing === "left" ? 3 : 0,
          mark: null,
        });
        continue;
      }
      if (object.kind !== "place" && object.kind !== "decor" && object.kind !== "prop") continue;
      const size =
        object.kind === "prop" ? [TILE_WIDTH, TILE_WIDTH] : BUILDINGS[object.building];
      structures.push({
        key: `${object.kind}:${id}`,
        kind: object.kind === "prop" ? "prop" : "building",
        sprite: object.kind === "prop" ? object.sprite : object.building,
        at: at(object.at),
        width: size[0]!,
        height: size[1]!,
        ...(object.mirror ? { mirror: true } : {}),
        ...(object.kind === "prop"
          ? {}
          : { shape: object.kind === "decor" ? "decor" : object.target === "gate" ? "gate" : "house" }),
        covers: coversOf(object).map(at),
      });
    }
  }
  return {
    name: doc.meta.name,
    description: `${doc.meta.name}: the map editor's preview walk`,
    terrain: { width, height, kinds, hidden, ground },
    void: "water",
    actors,
    adventurerId: WALKER_ID,
    path: [],
    ...(zone ? {} : { kind: "hub" as const, structures }),
  };
}

/** Where a hex of the editor's plane is in the preview's world, and back. */
export function toFrame(frame: Frame, tile: Tile): Tile {
  return { x: tile.x - frame.x0, y: tile.y - frame.y0 };
}

export function fromFrame(frame: Frame, tile: Tile): Tile {
  return { x: tile.x + frame.x0, y: tile.y + frame.y0 };
}
