import type { Tile, TileKind, ViewActor } from "../../render/view";
import { CHUNK, type SandboxWorld } from "../world";
import { GATES, type LocationRecord, SEED_OUTLINES, ZONE, globalTile, locationOf } from "./region";

/**
 * The seed's zone (location 2, a meadow of 3 × 2 chunks) as a sandbox fixture (CLI-03c), built
 * like the others: its size and outline from the seed's records, a meadow's scattered rocks
 * (design/18: 80–90 % walkable), a pack of three runts asleep (design/01: zone 0, runts only), and
 * the adventurer on the entry tile of the gate it came through. Every chunk but the entry's is not
 * revealed (D-136); the sandbox reveals it when sight touches it, as for the other fixtures.
 */

/** Whether bit `c` of row `r` of an outline record is set. */
function bit(rows: readonly number[], c: number, r: number): boolean {
  return (((rows[r] ?? 0) >> c) & 1) === 1;
}

/**
 * Whether a tile is inside the zone's outline (ADR-0006 *Outlines*): its chunk in the chunk set
 * and, for a border chunk with a tile mask, the tile in the mask. Outside is void: wall (D-134).
 * Reading the registry's records, not a rule.
 */
export function insideOutline(location: number, tile: Tile): boolean {
  const cx = Math.floor(tile.x / CHUNK);
  const cy = Math.floor(tile.y / CHUNK);
  const set = SEED_OUTLINES.find((o) => o.location === location && o.chunk === 255);
  if (!set || !bit(set.rows, cx, cy)) return false;
  const mask = SEED_OUTLINES.find((o) => o.location === location && o.chunk === CHUNK * cy + cx);
  return !mask || bit(mask.rows, tile.x % CHUNK, tile.y % CHUNK);
}

/** A rock, by a fixed pattern (no randomness): about one tile in nine. */
const rock = (x: number, y: number) => (x * 7 + y * 11) % 9 === 0;

/** The runts' tiles: chunk (1, 0), out of sight of either entry. */
const RUNTS: readonly Tile[] = [
  { x: 20, y: 9 },
  { x: 22, y: 9 },
  { x: 21, y: 11 },
];

/** The zone, the adventurer standing on `entry` (a tile of the location, global coordinates). */
export function zoneWorld(entry: Tile, record: LocationRecord | undefined = locationOf(ZONE)): SandboxWorld {
  if (!record) throw new Error("the zone is not in the fixed data");
  const width = record.width * CHUNK;
  const height = record.height * CHUNK;
  const keep = [
    entry,
    ...RUNTS,
    ...GATES.filter((g) => g.source === record.id && g.anchor_chunk + g.anchor_tile > 0).map((g) =>
      globalTile(g.anchor_chunk, g.anchor_tile),
    ),
  ];
  const kept = (x: number, y: number) => keep.some((t) => t.x === x && t.y === y);
  const hidden: TileKind[] = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const inside = insideOutline(record.id, { x, y });
      hidden.push(inside && (kept(x, y) || !rock(x, y)) ? "floor" : "wall");
    }
  }
  // Only the entry's chunk is revealed; void chunks stay wall, never unrevealed (D-134, D-136).
  const ex = Math.floor(entry.x / CHUNK);
  const ey = Math.floor(entry.y / CHUNK);
  const kinds = hidden.map((kind, i): TileKind => {
    const x = i % width;
    const y = Math.floor(i / width);
    const entryChunk = Math.floor(x / CHUNK) === ex && Math.floor(y / CHUNK) === ey;
    return entryChunk || !insideOutline(record.id, { x, y }) ? kind : "unrevealed";
  });
  const actors: ViewActor[] = [
    { id: 1, side: "adventurer", profession: "vanguard", tile: entry, facing: 3, mark: null },
    ...RUNTS.map(
      (tile, i): ViewActor => ({
        id: 2 + i,
        side: "goblin",
        caste: "runt",
        tile,
        facing: 0,
        mark: "asleep",
      }),
    ),
  ];
  return {
    name: "zone",
    description: `The seed's zone: meadow, levels ${record.level_min}–${record.level_max}, ${record.width} × ${record.height} chunks; entered at (${entry.x}, ${entry.y})`,
    terrain: { width, height, kinds, hidden },
    actors,
    adventurerId: 1,
    path: [],
  };
}
