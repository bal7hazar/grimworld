import {
  type Area,
  type Classes,
  type Content,
  type Features,
  type Ground,
  NotMirrored,
  type Segment,
  runSegment,
  split,
} from "@grimworld/sim";
import type { Predict } from "./reconcile";
import { ChunkKind, type InstanceView, type RegionChunk } from "./view";

/**
 * The mirror wired (CLI-10b, D-257; CLI-10c, VIEW-01 / D-263): client/sim's `runSegment` on the
 * segment `PlayLibrary` would build before its first `SegmentLibrary` call
 * (contracts/ephemeral/src/systems/play.cairo, `play` and `run`): the words (the header's clock,
 * the members' seven words, the goblins), the area (the location's extent, its chunks not void,
 * the revealed set, the walkable tiles of the revealed chunks around the controlled member), the
 * ground (their `Features`), the location's `level_min`, no owed tick and the whole weight.
 *
 * Its inputs are what the chain gives: `InstanceView` (`instance_state`: the words, the goblins a
 * batch loads first, instances.cairo :136-146, and the location's `width`, `height` and
 * `level_min`, :142-145), the region's chunks (`instance_region`: the view's `chunks` are gone,
 * the chunks are the region's), the controlled member (`Instances.placement`, `placement.member`,
 * play.cairo :186-187) and the content (the sheets of the members' skills and potions and of the
 * area goblins' castes and skills, as `PlayLibrary`'s `bundle` reads them), which the caller
 * passes decoded (CLI-10d). Where these do not hold what the segment needs, there is no
 * prediction (`NotMirrored`), never a guess:
 * - a view whose goblins are the `UNLOADABLE` marker: `play` refuses the batch (`Stop::Invalid`
 *   before any action, play.cairo :285-300), the mirror does not predict a refusal;
 * - an empty goblin list where the roster or a pack of the area holds some: the view lists none
 *   while no `PlayLibrary` is set (instances.cairo :598);
 * - several members while the view lists goblins: it lists the goblins of every member's window at once
 *   (play.cairo :338-349, `window`), `play` loads those of the controlled member's alone, and the
 *   view cannot tell a window's goblins from a roster's;
 * - a revealed chunk around the controlled member that the region does not give.
 * The goblins are the view's as they are, derived ones included (at full health, in their pack's
 * state): `PlayLibrary` loads them by the same functions.
 * The three classes behind the seam (`TickLibrary::ticks`, `ActionLibrary::act`,
 * `TrapLibrary::trigger`) have no port in client/sim yet: `unportedClasses` answers each call with
 * `NotMirrored`, so a segment predicts only on the fast path (no goblin in the window, no combat,
 * no trap).
 */

/** What the mirror runs from. */
export interface MirrorState {
  /** The state the batch runs on (the view before it). */
  readonly view: InstanceView;
  /** The member the adventurer controls (`Instances.placement`), the area's centre. */
  readonly member: number;
  /** The instance's chunks, as `instance_region` gives them. */
  readonly region: readonly RegionChunk[];
  readonly content: Content;
}

/** `types::MAX_WEIGHT`. */
const MAX_WEIGHT = 10;
/** Every tile of a chunk (`play::TILES`). */
const TILES = (1n << 225n) - 1n;
const P97 = 1n << 97n;
const P64 = 1n << 64n;
const P32 = 1n << 32n;
const P128 = 1n << 128n;
/** A pack's goblins take entities `8 + 16 chunk + 5 p + i` (M-5, `goblin_entity`). */
const goblinEntity = (chunk: number, k: number) => 8 + 16 * chunk + k;

const bitsOf = (value: bigint, at: number, width: number): number =>
  Number((value >> BigInt(at)) & ((1n << BigInt(width)) - 1n));
const has = (bits: bigint, index: number): boolean => ((bits >> BigInt(index)) & 1n) === 1n;
/** A stored word's value, `LIVE` removed (`packing::split`, the limbs joined). */
const unlive = (word: bigint): bigint => {
  const [low, high] = split(word);
  return low + high * P128;
};

/** `TerrainStorePacking::unpack`'s walls. */
export function unpackWalls(word: bigint): bigint {
  const [low, high] = split(word);
  return low + (high % P97) * P128;
}

/** `FeaturesStorePacking::unpack`. */
export function unpackFeatures(word: bigint): Features {
  const [low, high] = split(word);
  const pack = (bits: bigint) => ({
    tile: bitsOf(bits, 0, 8),
    template: bitsOf(bits, 8, 16),
    level: bitsOf(bits, 24, 8),
    count: bitsOf(bits, 32, 4),
    offsets: bitsOf(bits, 36, 25),
    alert: bitsOf(bits, 61, 3),
  });
  const object = (bits: bigint) => ({
    tile: bitsOf(bits, 0, 8),
    kind: bitsOf(bits, 8, 4),
    state: bitsOf(bits, 12, 4),
    param: bitsOf(bits, 16, 16),
  });
  return {
    packs: [pack(low % P64), pack(low / P64)],
    objects: [object(high % P32), object((high / P32) % P32), object((high / P64) % P32)],
    touched: bitsOf(high, 96, 16),
  };
}

/** `PlayTrait::around`: the 3 × 3 chunks around the tile `(x, y)`'s, inside the 15 × 15 grid. */
function around(x: number, y: number): number[] {
  const [cx, cy] = [Math.floor(x / 15), Math.floor(y / 15)];
  const out: number[] = [];
  for (let dy = 0; dy < 3; dy++) {
    for (let dx = 0; dx < 3; dx++) {
      if (cx + dx >= 1 && cy + dy >= 1 && cx + dx <= 15 && cy + dy <= 15) {
        out.push((cy + dy - 1) * 15 + cx + dx - 1);
      }
    }
  }
  return out;
}

/** The segment's inputs but its actions; throws `NotMirrored` where the state lacks one. */
export function segmentOf(state: MirrorState): Omit<Segment, "actions"> {
  const { view, region } = state;
  if (view.unloadable) throw new NotMirrored("a goblin cannot load");
  if (view.members.length > 1 && view.goblins.length > 0) {
    throw new NotMirrored("several members: the view's goblins are those of every window");
  }
  const members = view.members.map(({ state, timers, effects, recharges, stats, bar, kit }) => ({
    state,
    timers,
    effects,
    recharges,
    stats,
    bar,
    kit,
  }));
  const first = view.members[state.member];
  if (first === undefined) throw new NotMirrored(`the view holds no member ${state.member}`);
  // `PlayTrait::place`: x at bits 32–39, y at 40–47
  const [x, y] = [bitsOf(first.state, 32, 8), bitsOf(first.state, 40, 8)];
  const revealed = unlive(view.revealed);
  let known = 0n;
  for (const chunk of region) if (chunk.kind !== ChunkKind.Void) known |= 1n << BigInt(chunk.chunk);
  const ground: Ground = [];
  const chunks: [number, bigint][] = [];
  for (const chunk of around(x, y)) {
    if (!has(revealed, chunk)) continue;
    const read = region.find((c) => c.chunk === chunk && c.kind === ChunkKind.Revealed);
    if (read === undefined) throw new NotMirrored(`revealed chunk ${chunk} not in the region`);
    ground.push([chunk, unpackFeatures(read.features)]);
    chunks.push([chunk, TILES - unpackWalls(read.terrain)]);
  }
  const listed = new Set(view.goblins.map((g) => g.entity));
  for (const [chunk, features] of ground) {
    features.packs.forEach((pack, p) => {
      for (let i = 0; i < pack.count; i++) {
        const entity = goblinEntity(chunk, 5 * p + i);
        if (!listed.has(entity)) {
          throw new NotMirrored(
            `goblin ${entity} of chunk ${chunk}'s pack not in the view (no PlayLibrary set)`,
          );
        }
      }
    });
  }
  if (view.header.rosterCount > 0 && view.goblins.length === 0) {
    throw new NotMirrored("the roster's goblins not in the view (no PlayLibrary set)");
  }
  const area: Area = {
    width: view.width,
    height: view.height,
    known,
    revealed,
    chunks,
    changed: [],
    ran: false,
  };
  return {
    words: {
      clock: view.header.clock,
      members,
      // `PlayTrait::sorted`: by entity (the view lists them so; kept as `sorted` does)
      goblins: view.goblins
        .map((g) => ({ entity: g.entity, awake: false, state: g.state, timers: g.timers }))
        .sort((a, b) => a.entity - b.entity),
      killed: [],
      defeated: false,
    },
    content: state.content,
    area,
    level: view.levelMin,
    ground,
    owed: 0,
    weight: MAX_WEIGHT,
  };
}

/** The classes client/sim does not port yet: each call is no prediction. */
export const unportedClasses: Classes = {
  ticks() {
    throw new NotMirrored("TickLibrary::ticks (no port in client/sim yet)");
  },
  act() {
    throw new NotMirrored("ActionLibrary::act (no port in client/sim yet)");
  },
  trigger() {
    throw new NotMirrored("TrapLibrary::trigger (no port in client/sim yet)");
  },
};

/** The preview's `predict`: the segment of `state` with the batch's actions. */
export function mirrorOf(state: MirrorState, classes: Classes = unportedClasses): Predict {
  const window = (x: number, y: number) => around(x, y).join(",");
  const at = (word: bigint) => window(bitsOf(word, 32, 8), bitsOf(word, 40, 8));
  return (actions) => {
    // Built per call: a state the segment cannot be built from is `NotMirrored` there, in `reconcile`
    const segment = segmentOf(state);
    const start = at(state.view.members[state.member]!.state);
    const ran = runSegment({ ...segment, actions: [...actions] }, classes);
    const member = ran.words.members[state.member];
    // The chain's view after the batch lists the window around the member where it ended
    return { ...ran, moved: member !== undefined && at(member.state) !== start };
  };
}
