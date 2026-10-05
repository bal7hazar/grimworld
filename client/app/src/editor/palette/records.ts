import type { Facing, Tile } from "../../render/view";
import { inPlane, keyOf, sideOf } from "../model";
import {
  type BridgeKind,
  type BuildingKind,
  FOOTPRINTS,
  type Kind,
  type NpcKind,
  type PropKind,
  SIDE,
  type Walk,
  kindOf,
} from "./kinds";

/**
 * What the author places, and the record the editor will write for it: the shapes track game gave
 * for ENG-08's export (under D-215; ENG-08 not yet merged). An NPC, a building's sprite, anchor and
 * door are client-only; a building's footprint and a blocking prop's hex become unwalkable through
 * ENG-08's converter, not here. A bridge (D-217) is its deck hexes and its two end hexes; the
 * walking rules come with ENG-08b.
 */

export interface NpcPlacement {
  readonly category: "npc";
  readonly kind: string;
  readonly hex: Tile;
  readonly facing: Facing;
}

export interface BuildingPlacement {
  readonly category: "building";
  readonly kind: string;
  readonly anchor: Tile;
  /** A hex of the footprint's border; the kind's door when absent. */
  readonly door?: Tile;
}

export interface PropPlacement {
  readonly category: "prop";
  readonly kind: string;
  readonly hex: Tile;
  /** Which of the kind's sprites, for a prop with several (0 when absent). */
  readonly variant?: number;
  /** A prop that turns by facing: 0 to 5 (0 when absent). */
  readonly facing?: Facing;
  /** A prop that turns by flip: mirrored. */
  readonly flip?: boolean;
}

export interface BridgePlacement {
  readonly category: "bridge";
  readonly kind: string;
  /** The southern end hex. */
  readonly south: Tile;
  /** The deck leans North-West first instead of North-East. */
  readonly mirrored?: boolean;
}

export type Placement = NpcPlacement | BuildingPlacement | PropPlacement | BridgePlacement;

/** ENG-08's NPC: the unit template id (the kind's id), its hex, its facing. */
export interface NpcRecord {
  readonly template: string;
  readonly hex: Tile;
  readonly facing: Facing;
}

/** ENG-08's building: its kind, its footprint, its anchor, its door on the footprint's border. */
export interface BuildingRecord {
  readonly kind: string;
  readonly footprint: readonly Tile[];
  readonly anchor: Tile;
  readonly door: Tile;
}

/** ENG-08's prop: its kind, its hex, an optional variant, a facing or a flip. */
export interface PropRecord {
  readonly kind: string;
  readonly hex: Tile;
  readonly variant?: number;
  readonly facing?: Facing;
  readonly flip?: boolean;
}

/** D-217's bridge: its kind, its deck hexes (South to North) and its two end hexes. */
export interface BridgeRecord {
  readonly kind: string;
  readonly deck: readonly Tile[];
  readonly ends: readonly [Tile, Tile];
}

export type PlacedRecord =
  | { readonly category: "npc"; readonly record: NpcRecord }
  | { readonly category: "building"; readonly record: BuildingRecord }
  | { readonly category: "prop"; readonly record: PropRecord }
  | { readonly category: "bridge"; readonly record: BridgeRecord };

export type RecordResult = PlacedRecord | { readonly problem: string };

const isFacing = (value: unknown): value is Facing =>
  Number.isInteger(value) && (value as number) >= 0 && (value as number) <= 5;

const same = (a: Tile, b: Tile) => a.x === b.x && a.y === b.y;

/** The hex a walk from `start` ends on. */
export function walkFrom(start: Tile, walk: Walk): Tile {
  let tile = start;
  for (const side of walk) tile = sideOf(tile, side);
  return tile;
}

/** A building's footprint hexes, its anchor first. */
export function footprintAt(kind: BuildingKind, anchor: Tile): Tile[] {
  return (FOOTPRINTS[kind.footprint] as readonly Walk[]).map((walk) => walkFrom(anchor, walk));
}

/** The order a door's outward side is chosen in: the viewer's sides first. */
const DOOR_SIDES = [
  SIDE.southEast,
  SIDE.southWest,
  SIDE.east,
  SIDE.west,
  SIDE.northEast,
  SIDE.northWest,
];

/**
 * The side a door opens on: the first of `DOOR_SIDES` whose hex across lies outside the footprint,
 * or null when the hex is not on the footprint's border (or not in it).
 */
export function doorSide(footprint: readonly Tile[], door: Tile): number | null {
  const inside = new Set(footprint.map(keyOf));
  if (!inside.has(keyOf(door))) return null;
  return DOOR_SIDES.find((side) => !inside.has(keyOf(sideOf(door, side)))) ?? null;
}

/** The hexes of a footprint where a door may go: those on its border, in footprint order. */
export function doorChoices(footprint: readonly Tile[]): Tile[] {
  return footprint.filter((tile) => doorSide(footprint, tile) !== null);
}

/** A bridge's hexes from its southern end: `deck` deck hexes, then the northern end. */
export function bridgeAt(
  kind: BridgeKind,
  south: Tile,
  mirrored = false,
): { deck: Tile[]; ends: [Tile, Tile] } {
  // North-South on pointy-top rows: North-East then North-West (or the reverse), so the ends stay
  // in one column on screen.
  const lean = mirrored ? [SIDE.northWest, SIDE.northEast] : [SIDE.northEast, SIDE.northWest];
  const deck: Tile[] = [];
  let tile = south;
  for (let i = 0; i < kind.deck; i++) {
    tile = sideOf(tile, lean[i % 2]!);
    deck.push(tile);
  }
  const north = sideOf(tile, lean[kind.deck % 2]!);
  return { deck, ends: [south, north] };
}

/** Every hex a placement covers (a building's footprint, a bridge's deck and ends). */
export function hexesOf(placed: PlacedRecord): Tile[] {
  switch (placed.category) {
    case "npc":
    case "prop":
      return [placed.record.hex];
    case "building":
      return [...placed.record.footprint];
    case "bridge":
      return [placed.record.ends[0], ...placed.record.deck, placed.record.ends[1]];
  }
}

function kindFor<C extends Kind["category"]>(
  id: string,
  category: C,
): Extract<Kind, { category: C }> | string {
  const kind = kindOf(id);
  if (!kind) return `no kind ${id}`;
  if (kind.category !== category) return `${id} is a ${kind.category}, not a ${category}`;
  return kind as Extract<Kind, { category: C }>;
}

function npcRecord(p: NpcPlacement, kind: NpcKind): RecordResult {
  if (!isFacing(p.facing)) return { problem: `facing ${String(p.facing)} is not 0 to 5` };
  return {
    category: "npc",
    record: { template: kind.id, hex: { x: p.hex.x, y: p.hex.y }, facing: p.facing },
  };
}

function buildingRecord(p: BuildingPlacement, kind: BuildingKind): RecordResult {
  const footprint = footprintAt(kind, p.anchor);
  const door = p.door ?? walkFrom(p.anchor, kind.door);
  if (doorSide(footprint, door) === null) {
    return { problem: `the door (${door.x}, ${door.y}) is not on the footprint's border` };
  }
  return {
    category: "building",
    record: {
      kind: kind.id,
      footprint,
      anchor: { x: p.anchor.x, y: p.anchor.y },
      door: { x: door.x, y: door.y },
    },
  };
}

function propRecord(p: PropPlacement, kind: PropKind): RecordResult {
  const record: { -readonly [K in keyof PropRecord]: PropRecord[K] } = {
    kind: kind.id,
    hex: { x: p.hex.x, y: p.hex.y },
  };
  if (kind.turn === "facing") {
    if (p.flip) return { problem: `${kind.id} turns by facing, not by flip` };
    if (p.variant !== undefined) return { problem: `${kind.id} has no variant` };
    const facing = p.facing ?? 0;
    if (!isFacing(facing)) return { problem: `facing ${String(facing)} is not 0 to 5` };
    record.facing = facing;
  } else {
    if (p.facing !== undefined) return { problem: `${kind.id} turns by flip, not by facing` };
    const variant = p.variant ?? 0;
    if (!(Number.isInteger(variant) && variant >= 0 && variant < kind.art.length)) {
      return { problem: `${kind.id} has no variant ${String(variant)}` };
    }
    // Written only when it says something: a variant of a prop with several, a flip that mirrors.
    if (kind.art.length > 1) record.variant = variant;
    if (p.flip) record.flip = true;
  }
  return { category: "prop", record };
}

function bridgeRecord(p: BridgePlacement, kind: BridgeKind): RecordResult {
  const { deck, ends } = bridgeAt(kind, p.south, p.mirrored);
  return { category: "bridge", record: { kind: kind.id, deck, ends } };
}

/**
 * The record a placement writes, or what is wrong with it: an unknown kind, a kind of another
 * category, a facing or a variant out of range, a door off the border, a hex past the plane's
 * bound.
 */
export function recordOf(placement: Placement): RecordResult {
  let result: RecordResult;
  switch (placement.category) {
    case "npc": {
      const kind = kindFor(placement.kind, "npc");
      result = typeof kind === "string" ? { problem: kind } : npcRecord(placement, kind);
      break;
    }
    case "building": {
      const kind = kindFor(placement.kind, "building");
      result = typeof kind === "string" ? { problem: kind } : buildingRecord(placement, kind);
      break;
    }
    case "prop": {
      const kind = kindFor(placement.kind, "prop");
      result = typeof kind === "string" ? { problem: kind } : propRecord(placement, kind);
      break;
    }
    case "bridge": {
      const kind = kindFor(placement.kind, "bridge");
      result = typeof kind === "string" ? { problem: kind } : bridgeRecord(placement, kind);
      break;
    }
  }
  if ("problem" in result) return result;
  const outside = hexesOf(result).find((tile) => !inPlane(tile));
  if (outside) return { problem: `(${outside.x}, ${outside.y}) is past the plane's bound` };
  return result;
}

/** Whether two placed records share a hex (the editor refuses the second; part 2). */
export function overlaps(a: PlacedRecord, b: PlacedRecord): boolean {
  const hexes = hexesOf(a);
  return hexesOf(b).some((tile) => hexes.some((other) => same(tile, other)));
}
