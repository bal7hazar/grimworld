import type { GroundKind, Tile, TileKind, ViewActor, ViewStructure } from "../render/view";
import { ADVENTURER } from "../sandbox/fixtures/hubs";
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
import { type MapObject, kindOf } from "./objects";
import { bridgeHexes } from "./pack";

/**
 * The map as the game builds it (CLI-09b, brief §2.8): a zone as an instance's `SandboxWorld`
 * (`fixtures/zone.ts`'s shape), a town or an outpost as a hub's (`fixtures/hubWorld.ts`'s), in the
 * fitted map's coordinates (D-216), for the preview walk and the town's checks (E-15). The walk
 * itself is the game's: the same `SandboxSession`, intents and finder, reached through the wiring.
 * Presentation, not a rule.
 */

/** The hexes a building stands on (`footprint`, `hubWorld.ts:44-56`), its door included. */
export function footprintOf(object: MapObject): Tile[] {
  return kindOf(object).footprint?.(object) ?? [];
}

/**
 * The wall hexes an object stands on in the walk's world, from its kind's row (`structures()`,
 * `hubWorld.ts:72-108`): a place's footprint but its door, a decor's whole footprint, a prop's hex.
 */
export function coversOf(object: MapObject): Tile[] {
  return kindOf(object).covers?.(object) ?? [];
}

/**
 * The hexes of the map's bridges' decks, by key (D-227, ADR-0008 rule 1): walkable ground over
 * water, as the converter writes them. A bridge whose record cannot be written has none.
 */
export function deckKeys(doc: MapDocument): Set<number> {
  const out = new Set<number>();
  for (const object of doc.objects.values()) {
    if (object.kind !== "bridge") continue;
    for (const t of bridgeHexes(object)?.deck ?? []) out.add(keyOf(t));
  }
  return out;
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
 * - on both, the pack's objects (CLI-09e part 3) stand as structures, characters in their idle
 *   loop; a building's footprint but its door and a blocking prop's hex are walls, as the
 *   validation counts them and as the converter will make them (ENG-08). A bridge's deck is
 *   floor, its ground still water under the sprite (D-227, ADR-0008 rule 1); one outside the
 *   outline or blocked stays as painted (E-24, E-25 refuse it).
 */
export function walkWorld(doc: MapDocument, frame: Frame, options: WalkOptions): SandboxWorld {
  const zone = isZone(doc);
  const width = frame.width * CHUNK;
  const height = frame.height * CHUNK;
  const covered = townCovers(doc);
  const decks = deckKeys(doc);
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
      const floor = decks.has(key) || terrainOf(cell) !== WALL;
      hidden.push(!floor || covered.has(key) ? "wall" : "floor");
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
  if (!zone) {
    let n = 0;
    for (const [id, object] of [...doc.objects].sort(([a], [b]) => a - b)) {
      if (object.kind !== "figure") continue;
      actors.push({
        id: 100 + id,
        side: "adventurer",
        profession: FIGURES[n++ % FIGURES.length]!,
        tile: at(object.at),
        // West (3) for "left", East (0) for "right", as `hubWorld` turns a figure.
        facing: object.facing === "left" ? 3 : 0,
        mark: null,
      });
    }
  }
  const structures = townStructures(doc, at);
  return {
    name: doc.meta.name,
    description: `${doc.meta.name}: the map editor's preview walk`,
    terrain: { width, height, kinds, hidden, ground },
    void: "water",
    actors,
    adventurerId: WALKER_ID,
    path: [],
    structures,
    ...(zone ? {} : { kind: "hub" as const }),
  };
}

/**
 * A town's buildings and props as the game's structures (`structures()`, `hubWorld.ts:72-108`),
 * each on the hexes it covers; `at` places a hex of the editor's plane.
 */
export function townStructures(
  doc: MapDocument,
  at: (tile: Tile) => Tile = (t) => t,
): ViewStructure[] {
  const out: ViewStructure[] = [];
  for (const [id, object] of [...doc.objects].sort(([a], [b]) => a - b)) {
    const kind = kindOf(object);
    const look = kind.look?.(object);
    if (!look) continue;
    // A repeated sprite (a long bridge) is one structure a copy; the first keeps the object's key.
    (kind.drawnAt?.(object) ?? [object.at]).forEach((tile, i) => {
      out.push({
        key: i === 0 ? `${object.kind}:${id}` : `${object.kind}:${id}:${i}`,
        ...look,
        at: at(tile),
        ...((look.mirror ?? ("mirror" in object && object.mirror)) ? { mirror: true } : {}),
        covers: i === 0 ? coversOf(object).map(at) : [],
      });
    });
  }
  return out;
}

/** Where a hex of the editor's plane is in the preview's world, and back. */
export function toFrame(frame: Frame, tile: Tile): Tile {
  return { x: tile.x - frame.x0, y: tile.y - frame.y0 };
}

export function fromFrame(frame: Frame, tile: Tile): Tile {
  return { x: tile.x + frame.x0, y: tile.y + frame.y0 };
}
