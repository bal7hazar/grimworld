// The Cairo `Serde` of what a segment reads and returns (CLI-02g-A, D-254): each type decoded
// from its felts and encoded back, in the order of the Cairo struct or enum, held equal to it by
// `contracts/logic/vectors/segment2.jsonl` (its codec round-trips, and every call digest, which
// hashes these felts). `Content` (`types::tick`), `Words` (`types::world`), the ground
// (`Array<(u8, Features)>`, `models::index::Features`), `Area` and `Done` (`types::play`),
// `executor::Board`, `actions::Action`, `Illegal` (`types::action`) and the calls a row records
// (`types::play::tests::recorder::Call`).

import { boolFromFelt, boolToFelt, fromFelt, i16, toFelt, u16, u32, u64, u8, u128 } from "../felt";
import type { Features } from "../reveal";
import type {
  CasteSheet,
  Content,
  GoblinWords,
  MemberWords,
  PotionSheet,
  SkillSheet,
  Words,
} from "./words";

/** A reader of `Serde` felts, from the first. */
export class Felts {
  private at = 0;
  constructor(private readonly felts: readonly bigint[]) {}
  felt(): bigint {
    const felt = this.felts[this.at++];
    if (felt === undefined) throw new RangeError(`${this.felts.length} felts, more expected`);
    return felt;
  }
  u8(): number {
    return Number(fromFelt(u8, this.felt()));
  }
  u16(): number {
    return Number(fromFelt(u16, this.felt()));
  }
  u32(): number {
    return Number(fromFelt(u32, this.felt()));
  }
  i16(): number {
    return Number(fromFelt(i16, this.felt()));
  }
  bool(): boolean {
    return boolFromFelt(this.felt());
  }
  /** An `Array` or a `Span`: its length, then its items. */
  span<T>(item: () => T): T[] {
    return Array.from({ length: this.u32() }, item);
  }
  /** A fixed-size array `[T; n]`: its items alone. */
  fixed<T>(n: number, item: () => T): T[] {
    return Array.from({ length: n }, item);
  }
  /** Whether every felt was read. */
  get done(): boolean {
    return this.at === this.felts.length;
  }
  end(): void {
    if (!this.done) throw new RangeError(`${this.felts.length} felts, ${this.at} read`);
  }
}

const n = (value: number | boolean): bigint =>
  typeof value === "boolean" ? boolToFelt(value) : BigInt(value);
const span = <T>(items: readonly T[], write: (item: T) => bigint[]): bigint[] => [
  BigInt(items.length),
  ...items.flatMap(write),
];

// ---- Content ------------------------------------------------------------------------------

function readSkill(r: Felts): SkillSheet {
  return {
    id: r.u16(),
    kind: r.u8(),
    energy: r.u8(),
    profession: r.u8(),
    adrenaline: r.u8(),
    activation: r.u16(),
    recharge: r.u16(),
    regen0: r.i16(),
    regen12: r.i16(),
    range: r.u8(),
    entry1: fromFelt(u128, r.felt()),
    entry2: fromFelt(u128, r.felt()),
    entry3: fromFelt(u128, r.felt()),
  };
}

function readPotion(r: Felts): PotionSheet {
  return {
    id: r.u32(),
    regen: r.i16(),
    entry: fromFelt(u128, r.felt()),
    range: r.u8(),
    strength: r.u8(),
  };
}

function readCaste(r: Felts): CasteSheet {
  return {
    id: r.u16(),
    health: r.u16(),
    health_regen: r.u8(),
    energy: r.u8(),
    energy_regen: r.u8(),
    weapon_ticks: r.u8(),
    skills: r.fixed(4, () => r.u16()),
    armor: r.u8(),
    armor_vs: fromFelt(u64, r.felt()),
    weapon: r.u8(),
    weapon_damage: r.u8(),
    damage_type: r.u8(),
    weapon_range: r.u8(),
    rank: r.u8(),
  };
}

export function readContent(r: Felts): Content {
  return { skills: r.span(() => readSkill(r)), potions: r.span(() => readPotion(r)), castes: r.span(() => readCaste(r)) };
}

export function writeContent(content: Content): bigint[] {
  return [
    ...span(content.skills, (s) => [
      ...[s.id, s.kind, s.energy, s.profession, s.adrenaline, s.activation, s.recharge].map(n),
      toFelt(i16, BigInt(s.regen0)),
      toFelt(i16, BigInt(s.regen12)),
      n(s.range),
      s.entry1,
      s.entry2,
      s.entry3,
    ]),
    ...span(content.potions, (p) => [n(p.id), toFelt(i16, BigInt(p.regen)), p.entry, n(p.range), n(p.strength)]),
    ...span(content.castes, (c) => [
      ...[c.id, c.health, c.health_regen, c.energy, c.energy_regen, c.weapon_ticks].map(n),
      ...c.skills.map(n),
      n(c.armor),
      c.armor_vs,
      ...[c.weapon, c.weapon_damage, c.damage_type, c.weapon_range, c.rank].map(n),
    ]),
  ];
}

// ---- Words --------------------------------------------------------------------------------

const MEMBER_KEYS = ["state", "timers", "effects", "recharges", "stats", "bar", "kit"] as const;

export function readWords(r: Felts): Words {
  return {
    clock: r.u32(),
    members: r.span(
      () => Object.fromEntries(MEMBER_KEYS.map((key) => [key, r.felt()])) as MemberWords,
    ),
    goblins: r.span((): GoblinWords => ({ entity: r.u16(), awake: r.bool(), state: r.felt(), timers: r.felt() })),
    killed: r.span(() => r.u16()),
    defeated: r.bool(),
  };
}

export function writeWords(words: Words): bigint[] {
  return [
    n(words.clock),
    ...span(words.members, (m) => MEMBER_KEYS.map((key) => m[key])),
    ...span(words.goblins, (g) => [n(g.entity), n(g.awake), g.state, g.timers]),
    ...span(words.killed, (e) => [n(e)]),
    n(words.defeated),
  ];
}

// ---- The ground ---------------------------------------------------------------------------

/** The chunk objects and `touched` bits a call reads and writes, `(chunk, Features)`. */
export type Ground = [number, Features][];

function readFeatures(r: Felts): Features {
  return {
    packs: r.fixed(2, () => ({
      tile: r.u8(),
      template: r.u16(),
      level: r.u8(),
      count: r.u8(),
      offsets: r.u32(),
      alert: r.u8(),
    })),
    objects: r.fixed(3, () => ({ tile: r.u8(), kind: r.u8(), state: r.u8(), param: r.u16() })),
    touched: r.u16(),
  };
}

export function readGround(r: Felts): Ground {
  return r.span((): [number, Features] => [r.u8(), readFeatures(r)]);
}

export function writeGround(ground: Ground): bigint[] {
  return span(ground, ([chunk, f]) => [
    n(chunk),
    ...f.packs.flatMap((p) => [p.tile, p.template, p.level, p.count, p.offsets, p.alert].map(n)),
    ...f.objects.flatMap((o) => [o.tile, o.kind, o.state, o.param].map(n)),
    n(f.touched),
  ]);
}

// ---- Area, Board, Action, Done ------------------------------------------------------------

/** `play::Area`: the chunks a segment's windows may overlap. */
export type Area = {
  width: number;
  height: number;
  /** Bit `15 cy + cx` for each chunk that is not void. */
  known: bigint;
  /** Bit `15 cy + cx` for each chunk revealed. */
  revealed: bigint;
  /** `(chunk, walkable bits)` of the revealed chunks: bit `15 ly + lx`, 1 walkable. */
  chunks: (readonly [number, bigint])[];
  /** The goblins whose records the invocation's earlier segments changed. */
  changed: number[];
  ran: boolean;
};

export function readArea(r: Felts): Area {
  return {
    width: r.u8(),
    height: r.u8(),
    known: r.felt(),
    revealed: r.felt(),
    chunks: r.span(() => [r.u8(), r.felt()] as const),
    changed: r.span(() => r.u16()),
    ran: r.bool(),
  };
}

export function writeArea(area: Area): bigint[] {
  return [
    n(area.width),
    n(area.height),
    area.known,
    area.revealed,
    ...span(area.chunks, ([chunk, bits]) => [n(chunk), bits]),
    ...span(area.changed, (e) => [n(e)]),
    n(area.ran),
  ];
}

/** `executor::Board`: a window's walkable tiles and its origin, each plus `ORIGIN`. */
export type Board = { open: bigint; x: number; y: number };

export function readBoard(r: Felts): Board {
  const open = r.felt();
  // `WindowSerde` refuses a bitmap with a bit at or above 240
  if (open >= 1n << 240n) throw new RangeError(`window ${open} above bit 239`);
  return { open, x: r.u8(), y: r.u8() };
}

export const writeBoard = (board: Board): bigint[] => [board.open, n(board.x), n(board.y)];

/** `Target`: an entity (0) or a tile (1). */
export type Target = { tile: boolean; value: number };

/** `actions::Action`, by its `Serde` variant. */
export type Action =
  | { kind: "move"; direction: number }
  | { kind: "turn"; direction: number }
  | { kind: "wait" }
  | { kind: "attack"; entity: number }
  | { kind: "skill"; slot: number; target: Target }
  | { kind: "item"; slot: number; entity: number }
  | { kind: "interact"; tile: number };

export function readAction(r: Felts): Action {
  const variant = r.felt();
  switch (variant) {
    case 0n:
      return { kind: "move", direction: r.u8() };
    case 1n:
      return { kind: "turn", direction: r.u8() };
    case 2n:
      return { kind: "wait" };
    case 3n:
      return { kind: "attack", entity: r.u16() };
    case 4n: {
      const slot = r.u8();
      const tag = r.felt();
      if (tag !== 0n && tag !== 1n) throw new RangeError(`target variant ${tag}`);
      return { kind: "skill", slot, target: { tile: tag === 1n, value: r.u16() } };
    }
    case 5n:
      return { kind: "item", slot: r.u8(), entity: r.u16() };
    case 6n:
      return { kind: "interact", tile: r.u16() };
    default:
      throw new RangeError(`action variant ${variant}`);
  }
}

export function writeAction(action: Action): bigint[] {
  switch (action.kind) {
    case "move":
      return [0n, n(action.direction)];
    case "turn":
      return [1n, n(action.direction)];
    case "wait":
      return [2n];
    case "attack":
      return [3n, n(action.entity)];
    case "skill":
      return [4n, n(action.slot), n(action.target.tile), n(action.target.value)];
    case "item":
      return [5n, n(action.slot), n(action.entity)];
    case "interact":
      return [6n, n(action.tile)];
  }
}

/** `Illegal`, by its `Serde` index. */
export const Illegal = {
  Clock: 0,
  Absent: 1,
  Knocked: 2,
  Turned: 3,
  Instant: 4,
  Empty: 5,
  Belt: 6,
  Recharging: 7,
  Energy: 8,
  Adrenaline: 9,
  Target: 10,
  Reach: 11,
  Trap: 12,
  Kind: 13,
  Blocked: 14,
} as const;
export type Illegal = (typeof Illegal)[keyof typeof Illegal];

function readIllegal(r: Felts): Illegal {
  const index = r.u8();
  if (index > Illegal.Blocked) throw new RangeError(`illegal variant ${index}`);
  return index as Illegal;
}

/** `play::Done`: how a segment ended. */
export type Done = {
  played: number;
  weight: number;
  owed: number;
  reveal: boolean;
  illegal: Illegal | undefined;
  heavy: boolean;
  changed: number[];
  undo: boolean;
};

export function readDone(r: Felts): Done {
  const [played, weight, owed] = [r.u8(), r.u8(), r.u8()];
  const reveal = r.bool();
  const some = r.felt();
  if (some !== 0n && some !== 1n) throw new RangeError(`option variant ${some}`);
  const illegal = some === 0n ? readIllegal(r) : undefined;
  return { played, weight, owed, reveal, illegal, heavy: r.bool(), changed: r.span(() => r.u16()), undo: r.bool() };
}

export function writeDone(done: Done): bigint[] {
  return [
    ...[done.played, done.weight, done.owed, done.reveal].map(n),
    ...(done.illegal === undefined ? [1n] : [0n, n(done.illegal)]),
    n(done.heavy),
    ...span(done.changed, (e) => [n(e)]),
    n(done.undo),
  ];
}

// ---- The calls a row records ------------------------------------------------------------

/** What `ActionLibrary::act` returns of the action: its ticks, or why it is illegal. */
export type Outcome = { ticks: number } | { illegal: Illegal };

/** One class call of a segment, as `recorder::Call` logs it: its inputs' digest, its outputs. */
export type Call =
  | { kind: "ticks"; digest: bigint; words: Words; ground: Ground }
  | { kind: "act"; digest: bigint; words: Words; ground: Ground; outcome: Outcome }
  | { kind: "trigger"; digest: bigint; words: Words; ground: Ground; triggered: boolean };

export function readCall(r: Felts): Call {
  const variant = r.felt();
  const digest = r.felt();
  const [words, ground] = [readWords(r), readGround(r)];
  if (variant === 0n) return { kind: "ticks", digest, words, ground };
  if (variant === 1n) {
    const tag = r.felt();
    if (tag !== 0n && tag !== 1n) throw new RangeError(`result variant ${tag}`);
    const outcome: Outcome = tag === 0n ? { ticks: r.u8() } : { illegal: readIllegal(r) };
    return { kind: "act", digest, words, ground, outcome };
  }
  if (variant === 2n) return { kind: "trigger", digest, words, ground, triggered: r.bool() };
  throw new RangeError(`call variant ${variant}`);
}

export function writeCall(call: Call): bigint[] {
  const head = [call.digest, ...writeWords(call.words), ...writeGround(call.ground)];
  switch (call.kind) {
    case "ticks":
      return [0n, ...head];
    case "act":
      return [1n, ...head, ...("ticks" in call.outcome ? [0n, n(call.outcome.ticks)] : [1n, n(call.outcome.illegal)])];
    case "trigger":
      return [2n, ...head, n(call.triggered)];
  }
}
