import { type Ground, NotMirrored, groundObject, segmentBoard } from "@grimworld/sim";
import { readWorld } from "../combat/fromWords";
import type { CombatWorld } from "../combat/targeting";
import { type MirrorState, segmentOf, unpackFeatures, unpackWalls } from "../preview/mirror";
import type { MirrorWords } from "../preview/reconcile";
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

/** The art's castes in the order of the seed's caste ids (`contracts/seed/README.md`: 1 Runt, 2 Slinger,
 * 3 Skirmisher, 4 Shaman, 5 Hobgoblin); a later id wraps over them. */
const CASTES: readonly Caste[] = ["runt", "slinger", "skirmisher", "shaman", "hobgoblin"];
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

/**
 * The combat world of a mirror state (CLI-11d): client/sim's load of the words, the content and the
 * ground on the window's board, as `combat/fromWords.ts` reads it. `after` is a prediction's words
 * and ground (the batch planned so far); without it, the state the chain holds. None where the
 * combat screen has nothing to read: no content given, the controlled member not the adventurer
 * (member 0), or a state the mirror cannot build (`NotMirrored`) or the loaders refuse (logged).
 */
export function combatWorldOf(
  mirror: MirrorState,
  after?: { readonly words: MirrorWords; readonly ground: Ground },
): CombatWorld | undefined {
  const { content, member } = mirror;
  if (content === undefined || member !== 0) return undefined;
  try {
    const segment = segmentOf(mirror);
    const words = after?.words ?? segment.words;
    const first = words.members[0];
    if (first === undefined) return undefined;
    const { x, y } = memberPlace(first.state);
    return readWorld(
      words,
      content,
      after?.ground ?? segment.ground,
      segmentBoard(segment.area, x, y),
    );
  } catch (error) {
    if (error instanceof NotMirrored) return undefined;
    console.warn("grimworld.combat-world", error instanceof Error ? error.message : String(error));
    return undefined;
  }
}

/**
 * Whether the revealed chunk of `tile` holds an object there that is no trap: a gate, a chest, a
 * lever, whatever the chunk's features place (`unpackFeatures`' objects, tile `15 y + x` of the
 * chunk). Interactions are not available (CLI-05 brief §4.4); a tap on such a tile says so.
 */
export function objectAt(region: readonly RegionChunk[], tile: { x: number; y: number }): boolean {
  const chunk = Math.floor(tile.y / CHUNK) * 15 + Math.floor(tile.x / CHUNK);
  const read = region.find((c) => c.chunk === chunk && c.kind === ChunkKind.Revealed);
  if (read === undefined) return false;
  const local = (tile.y % CHUNK) * CHUNK + (tile.x % CHUNK);
  return unpackFeatures(read.features).objects.some(
    (o) =>
      o.tile === local &&
      o.kind !== groundObject.NONE &&
      o.kind !== groundObject.TRAP &&
      o.kind !== groundObject.PLACED_TRAP,
  );
}
