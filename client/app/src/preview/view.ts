/**
 * `InstanceView`, decoded from the felts `instance_state` returns: the Cairo `Serde` of the struct
 * (`contracts/ephemeral/src/systems/instances.cairo` :93-135), fields in their order, a `Span` as
 * its length then its items, an enum of unit variants as its index. Words stay in their stored
 * layout (`LIVE` set), as the view returns them; only the header is unpacked, for the fields the
 * preview shows. The client had no decoder of the view before this one.
 */

/** A reader of `Serde` felts, from the first. */
export class Felts {
  private at = 0;
  constructor(private readonly felts: readonly bigint[]) {}
  felt(): bigint {
    const felt = this.felts[this.at++];
    if (felt === undefined) throw new RangeError(`${this.felts.length} felts, more expected`);
    return felt;
  }
  /** An unsigned integer of `width` bits, refused beyond it as `Serde` refuses it. */
  uint(width: number): number {
    const felt = this.felt();
    if (felt >= 1n << BigInt(width)) throw new RangeError(`${felt} above u${width}`);
    return Number(felt);
  }
  u64(): bigint {
    const felt = this.felt();
    if (felt >= 1n << 64n) throw new RangeError(`${felt} above u64`);
    return felt;
  }
  bool(): boolean {
    const felt = this.felt();
    if (felt > 1n) throw new RangeError(`bool ${felt}`);
    return felt === 1n;
  }
  /** A unit-variant enum's index, below `variants`. */
  variant(variants: number): number {
    const index = this.felt();
    if (index >= BigInt(variants)) throw new RangeError(`variant ${index} of ${variants}`);
    return Number(index);
  }
  span<T>(item: () => T): T[] {
    return Array.from({ length: this.uint(32) }, item);
  }
  end(): void {
    if (this.at !== this.felts.length) {
      throw new RangeError(`${this.felts.length} felts, ${this.at} read`);
    }
  }
}

/** `GoblinView`: a goblin as stored, or derived from its chunk (`derived`). */
export type GoblinView = { entity: number; derived: boolean; state: bigint; timers: bigint };

/** `types::ChunkKind`. */
export const ChunkKind = { Void: 0, Unrevealed: 1, Revealed: 2 } as const;
export type ChunkKind = (typeof ChunkKind)[keyof typeof ChunkKind];

/** `RegionChunk`. */
export type RegionChunk = {
  chunk: number;
  kind: ChunkKind;
  terrain: bigint;
  features: bigint;
  goblins: GoblinView[];
};

/** `models::instance::Header`, unpacked (bits as its `StorePacking` lays them). */
export type Header = {
  generation: number;
  sequence: number;
  clock: number;
  location: number;
  status: number;
  members: number;
  tasks: number;
  revealedCount: number;
  rosterCount: number;
  flags: number;
  entryChunk: number;
  entryTile: number;
  gate: number;
};

/** The member words the view returns, eight a member in `Member`'s order (controller last). */
export const MEMBER_WORDS = 8;
export type MemberView = {
  state: bigint;
  timers: bigint;
  effects: bigint;
  recharges: bigint;
  stats: bigint;
  bar: bigint;
  kit: bigint;
  controller: bigint;
};

export type InstanceView = {
  instanceId: bigint;
  /** The stored word, and its fields. */
  headerWord: bigint;
  header: Header;
  entropy: bigint;
  revealed: bigint;
  quotas: bigint;
  tasks: bigint[];
  members: MemberView[];
  roster: bigint[];
  goblins: GoblinView[];
  chunks: RegionChunk[];
};

const LIVE_HIGH = 1n << 122n;
const field = (limb: bigint, at: number, width: number): number =>
  Number((limb >> BigInt(at)) & ((1n << BigInt(width)) - 1n));

/** `HeaderStorePacking::unpack`, `LIVE` removed from the high limb when set. */
export function unpackHeader(word: bigint): Header {
  const low = word & ((1n << 128n) - 1n);
  let high = word >> 128n;
  if (high >= LIVE_HIGH) high -= LIVE_HIGH;
  return {
    generation: field(low, 0, 32),
    sequence: field(low, 32, 32),
    clock: field(low, 64, 32),
    location: field(low, 96, 16),
    status: field(low, 112, 8),
    members: field(low, 120, 8),
    tasks: field(high, 0, 8),
    revealedCount: field(high, 8, 8),
    rosterCount: field(high, 16, 8),
    flags: field(high, 24, 8),
    entryChunk: field(high, 32, 8),
    entryTile: field(high, 40, 8),
    gate: field(high, 48, 16),
  };
}

function readGoblin(r: Felts): GoblinView {
  return { entity: r.uint(16), derived: r.bool(), state: r.felt(), timers: r.felt() };
}

function readChunk(r: Felts): RegionChunk {
  return {
    chunk: r.uint(8),
    kind: r.variant(3) as ChunkKind,
    terrain: r.felt(),
    features: r.felt(),
    goblins: r.span(() => readGoblin(r)),
  };
}

function members(words: bigint[]): MemberView[] {
  if (words.length % MEMBER_WORDS !== 0) {
    throw new RangeError(`${words.length} member words, not a multiple of ${MEMBER_WORDS}`);
  }
  return Array.from({ length: words.length / MEMBER_WORDS }, (_, i) => {
    const [state, timers, effects, recharges, stats, bar, kit, controller] = words.slice(
      i * MEMBER_WORDS,
      (i + 1) * MEMBER_WORDS,
    ) as [bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint];
    return { state, timers, effects, recharges, stats, bar, kit, controller };
  });
}

/** The view from every felt of `instance_state`'s result; a felt left over or missing throws. */
export function decodeInstanceView(felts: readonly bigint[]): InstanceView {
  const r = new Felts(felts);
  const instanceId = r.u64();
  const headerWord = r.felt();
  const view: InstanceView = {
    instanceId,
    headerWord,
    header: unpackHeader(headerWord),
    entropy: r.felt(),
    revealed: r.felt(),
    quotas: r.felt(),
    tasks: r.span(() => r.felt()),
    members: members(r.span(() => r.felt())),
    roster: r.span(() => r.felt()),
    goblins: r.span(() => readGoblin(r)),
    chunks: r.span(() => readChunk(r)),
  };
  r.end();
  return view;
}

/** The view's `Serde` felts: the inverse of `decodeInstanceView`, for tests and fixtures. */
export function encodeInstanceView(view: InstanceView): bigint[] {
  const goblin = (g: GoblinView) => [BigInt(g.entity), g.derived ? 1n : 0n, g.state, g.timers];
  const span = <T>(items: readonly T[], write: (item: T) => bigint[]) => [
    BigInt(items.length),
    ...items.flatMap(write),
  ];
  return [
    view.instanceId,
    view.headerWord,
    view.entropy,
    view.revealed,
    view.quotas,
    ...span(view.tasks, (t) => [t]),
    ...span(
      view.members.flatMap((m) => [
        m.state,
        m.timers,
        m.effects,
        m.recharges,
        m.stats,
        m.bar,
        m.kit,
        m.controller,
      ]),
      (w) => [w],
    ),
    ...span(view.roster, (w) => [w]),
    ...span(view.goblins, goblin),
    ...span(view.chunks, (c) => [
      BigInt(c.chunk),
      BigInt(c.kind),
      c.terrain,
      c.features,
      ...span(c.goblins, goblin),
    ]),
  ];
}
