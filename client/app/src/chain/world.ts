import { unpackWalls } from "../preview/mirror";
import { ChunkKind, type GoblinView, type InstanceView, type RegionChunk } from "../preview/view";
import type { Caste, Facing, GroundKind, Mark, TileKind, ViewActor } from "../render/view";
import { CHUNK, type SandboxWorld } from "../sandbox/world";

/**
 * The world the chain mode draws (CLI-11 §6.2): a `SandboxWorld` built from the view an instance
 * returns and its region, so that the renderer, the camera, sight and the explored tiles are the
 * sandbox's own. Presentation only: nothing here decides a rule.
 *
 * - The terrain: a revealed chunk's tiles from its walls (`unpackWalls`, bit `y * 15 + x` of the
 *   chunk), an unrevealed chunk as wall (it is drawn apart until the chain reveals it), a void
 *   chunk as wall over water. The rectangle is the location's, `width × height` chunks of 15 tiles;
 *   a chunk's index is `15 * row + column`, as the sandbox's own fixtures count them.
 * - The members, from their state words: the tile and facing at bits 32–55 (`MemberState`).
 * - The goblins, from theirs: tile and facing at bits 0–23, the AI state at 24–31, the caste at
 *   64–79 (`GoblinState`); the dead are not drawn. This reads the words as client/sim's `at` and
 *   `hot` do and does not call `loadGoblin`, which needs the batch's content and refuses a goblin
 *   the content lacks: a world must draw whatever the chain holds (gap noted in README).
 */

/** What the world is built from: the state after a batch, or at the start. */
export interface ChainView {
  readonly view: InstanceView;
  readonly region: readonly RegionChunk[];
  /** The member the adventurer controls (`Instances.placement`). */
  readonly member: number;
}

const bitsOf = (word: bigint, at: number, width: number): number =>
  Number((word >> BigInt(at)) & ((1n << BigInt(width)) - 1n));

/** `MemberState`'s tile and facing (bits 32–55). */
export function memberPlace(state: bigint): { x: number; y: number; facing: Facing } {
  return {
    x: bitsOf(state, 32, 8),
    y: bitsOf(state, 40, 8),
    facing: facingOf(bitsOf(state, 48, 8)),
  };
}

/** `GoblinState`'s tile and facing (bits 0–23). */
export function goblinPlace(state: bigint): { x: number; y: number; facing: Facing } {
  return { x: bitsOf(state, 0, 8), y: bitsOf(state, 8, 8), facing: facingOf(bitsOf(state, 16, 8)) };
}

const facingOf = (value: number): Facing => (value < 6 ? (value as Facing) : 0);

/** `ai::ASLEEP` to `ai::DEAD`, the order of client/sim's `ai`. */
const AI_MARK: readonly (Mark | null)[] = [
  "asleep", // ASLEEP
  null, // WATCH
  "alerted", // ALERTED
  "engaged", // ENGAGED
  "fleeing", // FLEEING
  null, // RETURNING
];
/** `ai::DEAD`: a goblin at or above it is gone from the map. */
const DEAD = 6;

/** The art's castes, by order; the seed's caste ids (1 …) wrap over them. */
const CASTES: readonly Caste[] = ["runt", "skirmisher", "slinger", "shaman", "hobgoblin"];
const casteName = (id: number): Caste => CASTES[(Math.max(id, 1) - 1) % CASTES.length] ?? "runt";

/** A goblin as the map draws it, or null for a dead one. */
export function goblinActor(goblin: GoblinView): ViewActor | null {
  const ai = bitsOf(goblin.state, 24, 8);
  if (ai >= DEAD) return null;
  const { x, y, facing } = goblinPlace(goblin.state);
  return {
    id: goblin.entity,
    side: "goblin",
    caste: casteName(bitsOf(goblin.state, 64, 16)),
    tile: { x, y },
    facing,
    mark: AI_MARK[ai] ?? null,
  };
}

/** The world of a view and its region. */
export function chainWorld({ view, region, member }: ChainView): SandboxWorld {
  const width = view.width * CHUNK;
  const height = view.height * CHUNK;
  if (width === 0 || height === 0) throw new RangeError("the view names no location");
  const kinds: TileKind[] = new Array<TileKind>(width * height).fill("wall");
  const hidden: TileKind[] = new Array<TileKind>(width * height).fill("wall");
  const ground: GroundKind[] = new Array<GroundKind>(width * height).fill("water");
  for (const read of region) {
    const column = read.chunk % 15;
    const row = Math.floor(read.chunk / 15);
    if (column >= view.width || row >= view.height) continue;
    const walls = read.kind === ChunkKind.Revealed ? unpackWalls(read.terrain) : 0n;
    for (let ly = 0; ly < CHUNK; ly++) {
      for (let lx = 0; lx < CHUNK; lx++) {
        const at = (row * CHUNK + ly) * width + column * CHUNK + lx;
        if (read.kind === ChunkKind.Void) continue;
        ground[at] = "grass";
        if (read.kind === ChunkKind.Unrevealed) {
          kinds[at] = "unrevealed";
          continue;
        }
        const wall = ((walls >> BigInt(ly * CHUNK + lx)) & 1n) === 1n;
        kinds[at] = wall ? "wall" : "floor";
        hidden[at] = kinds[at] ?? "wall";
      }
    }
  }
  const actors: ViewActor[] = [];
  view.members.forEach((m, index) => {
    const { x, y, facing } = memberPlace(m.state);
    actors.push({
      id: index,
      side: "adventurer",
      profession: "vanguard",
      tile: { x, y },
      facing,
      mark: null,
    });
  });
  for (const goblin of view.goblins) {
    const actor = goblinActor(goblin);
    if (actor !== null) actors.push(actor);
  }
  return {
    name: "chain",
    description: `Instance ${view.instanceId}: ${view.width} × ${view.height} chunks, clock ${view.header.clock}`,
    terrain: { width, height, kinds, hidden, ground },
    void: "water",
    actors,
    adventurerId: member,
    path: [],
  };
}
