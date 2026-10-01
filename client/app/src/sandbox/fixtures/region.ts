import type { Tile } from "../../render/view";
import { CHUNK } from "../world";

/**
 * The region the loop walks (CLI-03c): records copied from ENG-03's seed,
 * `contracts/seed/test-region.json`, with the field names of its `<kind>_fields`. A test reads the
 * seed and fails if a copied field differs (`region.test.ts`). The outpost and its two gates are
 * not in the seed: they are fixtures of `client/app` (design/01's Outpost B), with ids no seed
 * record uses.
 */

/** `LOCATION`'s `kind` (ENG-01 §3.5): 1 town, 2 outpost, 3 zone, 4 dungeon. */
export const LOCATION_KIND = { town: 1, outpost: 2, zone: 3, dungeon: 4 } as const;

/** `LOCATION`'s `biome` (ENG-01 §3.5, design/18). */
export const BIOME_NAMES: Readonly<Record<number, string>> = {
  1: "meadow",
  2: "forest",
  3: "cave",
  4: "ruin",
};

/** `GATE`'s `kind`: 1 hub, 2 link, 3 floor. */
export const GATE_KIND = { hub: 1, link: 2, floor: 3 } as const;

export interface LocationRecord {
  readonly id: number;
  readonly kind: number;
  readonly region: number;
  readonly biome: number;
  readonly level_min: number;
  readonly level_max: number;
  /** In chunks; 0 for a hub (no map). */
  readonly width: number;
  readonly height: number;
  readonly entry_chunk: number;
  readonly entry_tile: number;
}

export interface GateRecord {
  readonly id: number;
  readonly source: number;
  readonly destination: number;
  readonly anchor_chunk: number;
  readonly anchor_tile: number;
  readonly entry_chunk: number;
  readonly entry_tile: number;
  readonly kind: number;
  readonly rank: number;
  readonly quest: number;
}

/** An `OUTLINE` record: `chunk` 255 is the zone's chunk set, any other a chunk's tile mask. */
export interface OutlineRecord {
  readonly location: number;
  readonly chunk: number;
  /** `row_0` … `row_14`: bit `c` of row `r` is the chunk or tile `(c, r)`. */
  readonly rows: readonly number[];
}

/** From the seed: region 1 and its town, location 1. */
export const SEED_REGION = { id: 1, town: 1, first_location: 1, name: "Test Region" } as const;

export const TOWN = 1;
export const ZONE = 2;

/** From the seed: the town (a hub, no map) and the meadow zone. */
export const SEED_LOCATIONS: readonly LocationRecord[] = [
  {
    id: TOWN,
    kind: 1,
    region: 1,
    biome: 0,
    level_min: 0,
    level_max: 0,
    width: 0,
    height: 0,
    entry_chunk: 0,
    entry_tile: 0,
  },
  {
    id: ZONE,
    kind: 3,
    region: 1,
    biome: 1,
    level_min: 1,
    level_max: 3,
    width: 3,
    height: 2,
    entry_chunk: 0,
    entry_tile: 105,
  },
];

/** From the seed: gate 1, town → zone, and gate 2, zone → town anchored on the zone's entry. */
export const SEED_GATES: readonly GateRecord[] = [
  {
    id: 1,
    source: 1,
    destination: 2,
    anchor_chunk: 0,
    anchor_tile: 0,
    entry_chunk: 0,
    entry_tile: 105,
    kind: 1,
    rank: 0,
    quest: 0,
  },
  {
    id: 2,
    source: 2,
    destination: 1,
    anchor_chunk: 0,
    anchor_tile: 105,
    entry_chunk: 0,
    entry_tile: 0,
    kind: 1,
    rank: 0,
    quest: 0,
  },
];

/** From the seed: the zone's chunk set and the tile masks of its two border chunks. */
export const SEED_OUTLINES: readonly OutlineRecord[] = [
  { location: ZONE, chunk: 255, rows: [7, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { location: ZONE, chunk: 2, rows: Array<number>(15).fill(4095) },
  {
    location: ZONE,
    chunk: 16,
    rows: [...Array<number>(10).fill(32767), ...Array<number>(5).fill(1023)],
  },
];

/** A fixture of `client/app`, not in the seed: design/01's Outpost B. */
export const OUTPOST = 101;

export const FIXTURE_LOCATIONS: readonly LocationRecord[] = [
  {
    id: OUTPOST,
    kind: LOCATION_KIND.outpost,
    region: 1,
    biome: 0,
    level_min: 0,
    level_max: 0,
    width: 0,
    height: 0,
    entry_chunk: 0,
    entry_tile: 0,
  },
];

/**
 * Fixtures: the outpost's gate into the zone, entering at its far end (chunk 2, tile 115: chunk
 * (2, 0), row 7, column 10), and the hub gate back, anchored there.
 */
export const FIXTURE_GATES: readonly GateRecord[] = [
  {
    id: 101,
    source: OUTPOST,
    destination: ZONE,
    anchor_chunk: 0,
    anchor_tile: 0,
    entry_chunk: 2,
    entry_tile: 115,
    kind: GATE_KIND.hub,
    rank: 0,
    quest: 0,
  },
  {
    id: 102,
    source: ZONE,
    destination: OUTPOST,
    anchor_chunk: 2,
    anchor_tile: 115,
    entry_chunk: 0,
    entry_tile: 0,
    kind: GATE_KIND.hub,
    rank: 0,
    quest: 0,
  },
];

export const LOCATIONS: readonly LocationRecord[] = [...SEED_LOCATIONS, ...FIXTURE_LOCATIONS];
export const GATES: readonly GateRecord[] = [...SEED_GATES, ...FIXTURE_GATES];

export function locationOf(id: number): LocationRecord | undefined {
  return LOCATIONS.find((l) => l.id === id);
}

export function gateOf(id: number): GateRecord | undefined {
  return GATES.find((g) => g.id === id);
}

/**
 * A chunk index and a tile index (ENG-01 §3.2: `15 row + column` each) as a global tile of the
 * location: how the registry's records are read, not a rule of the game.
 */
export function globalTile(chunk: number, tile: number): Tile {
  return {
    x: (chunk % CHUNK) * CHUNK + (tile % CHUNK),
    y: Math.floor(chunk / CHUNK) * CHUNK + Math.floor(tile / CHUNK),
  };
}
