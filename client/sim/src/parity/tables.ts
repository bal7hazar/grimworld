// The tables the mirror replays, one entry each: the file in `contracts/logic/vectors/`, its floor
// (the cases it holds today: a table that loses cases fails) and the mirror's function per `fn`,
// adapting the felts of a case to the mirror's arguments and its result to Cairo's `Serde`.
// A new table of the game is one entry here.

import * as body from "../body";
import {
  readHeld,
  readInfliction,
  readUnit,
  writeHeld,
  writeInfliction,
  writeUnit,
} from "../body/serde";
import {
  type Entry as EffectEntry,
  class_,
  duration,
  is_holding,
  is_hit_modifier,
  line,
  pack,
  unpack,
  value,
} from "../effect";
import {
  CairoPanic,
  boolFromFelt,
  fromFelt,
  i16,
  i32,
  i8,
  panic,
  toFelt,
  u128,
  u16,
  u32,
  u8,
} from "../felt";
import { PURPOSES, derive, domain } from "../fate";
import { hitFromFelts, outcomeToFelts, resolve } from "../hit";
import {
  LIVE,
  byte_at,
  errors as packingErrors,
  field,
  fits,
  join,
  limbs,
  low_field,
  pack_bitmap,
  pack_counter,
  pack_lanes16,
  pack_lanes32,
  peel,
  split,
  u16_at,
  u32_at,
  unpack_bitmap,
  unpack_counter,
  unpack_lanes16,
  unpack_lanes32,
} from "../packing";
import { admit, revealed } from "../batch";
import { awake, board, flood, flood_distance, move_ticks, next_step, position } from "../movement";
import { arc, distance, facing, front, neighbor, reach, shape, sight } from "../window";
import {
  chunks,
  feed,
  member,
  optionToFelts,
  progressToFelts,
  reveal as revealChunks,
  revealFromFelts,
  revealedToFelts,
  word,
} from "../reveal";
import { base } from "../reveal/board";
import { fast, path, run as runSegment } from "../segment";
import type { Segment } from "../segment";
import type { Classes } from "../segment/classes";
import {
  type Done,
  Felts,
  readAction,
  readArea,
  readBoard,
  readCall,
  readContent,
  readFeatures,
  readGround,
  readWords,
  type Ground,
  type Outcome,
  writeContent,
  writeDone,
  writeGround,
  writeWords,
} from "../segment/serde";
import { type Content, type MemberWords, type Words, sheets as indexed } from "../segment/words";
import { world as loadWorld, words as storeWorld } from "../segment/world";
import type { Entry, Mirror } from "./replay";
import { replayer } from "./replayer";
import { free, triggerClass } from "../trap";
import { actClass } from "../action";
import { ticksClass } from "../tick";
import * as executor from "../executor";
import { load as loadMember } from "../segment/words";
import { load as loadGoblin } from "../segment/goblin";
import { type Vector, contentRow, readTable } from "./table";

/** The felts of a case, exactly `count` of them. */
function args(felts: readonly bigint[], count: number): readonly bigint[] {
  if (felts.length !== count) throw new RangeError(`${felts.length} arguments, expected ${count}`);
  return felts;
}

/** A `u8` argument (a position, a facing, a range, a shape) as the mirror's `number`. */
const small = (felt: bigint): number => Number(fromFelt(u8, felt));
const bool = (value: boolean): bigint[] => [value ? 1n : 0n];

const window: Record<string, Mirror> = {
  sight: (c) => {
    const [open, from, to] = args(c, 3);
    return bool(sight(open!, small(from!), small(to!)));
  },
  reach: (c) => {
    const [open, from, to, range] = args(c, 4);
    return bool(reach(open!, small(from!), small(to!), small(range!)));
  },
  arc: (c) => {
    const [source, target, facing] = args(c, 3);
    const result = arc(small(source!), small(target!), small(facing!));
    return result === undefined ? [1n] : [0n, BigInt(result)];
  },
  facing: (c) => {
    const [from, to, turn] = args(c, 3);
    return [BigInt(facing(small(from!), small(to!), small(turn!)))];
  },
  front: (c) => {
    const [source, target, facing] = args(c, 3);
    return bool(front(small(source!), small(target!), small(facing!)));
  },
  distance: (c) => {
    const [from, to] = args(c, 2);
    return [BigInt(distance(small(from!), small(to!)))];
  },
  shape: (c) => {
    const [open, id, centre] = args(c, 3);
    return [shape(open!, small(id!), small(centre!))];
  },
};

const hit: Record<string, Mirror> = {
  "": (c) => outcomeToFelts(resolve(...hitFromFelts(c))),
};

const fate: Record<string, Mirror> = {
  purpose: (c) => {
    const [index] = args(c, 1);
    const purpose = PURPOSES[Number(index!)];
    if (purpose === undefined) throw new RangeError(`no purpose ${index}`);
    return [purpose];
  },
  domain: (c) => {
    const [subject, counter, purpose] = args(c, 3);
    return [domain(subject!, counter!, purpose!)];
  },
  derive: (c) => {
    const [word, dom, index] = args(c, 3);
    return [derive(word!, dom!, Number(fromFelt(u32, index!)))];
  },
};

/**
 * A guarded call as the packing table records it: `[0, result…]` accepted, `[1]` refused. Only the
 * guard's own panic is a refusal; any other throw is a divergence.
 */
function guarded(message: string, call: () => readonly bigint[]): bigint[] {
  try {
    return [0n, ...call()];
  } catch (error) {
    if (error instanceof CairoPanic && error.data.join() === message) return [1n];
    throw error;
  }
}

const packing: Record<string, Mirror> = {
  split: (c) => split(args(c, 1)[0]!),
  limbs: (c) => limbs(args(c, 1)[0]!),
  join: (c) => {
    const [low, high] = args(c, 2);
    return guarded(packingErrors.HIGH, () => [join(low!, high!)]);
  },
  peel: (c) => {
    const [rest, size] = args(c, 2);
    return peel(rest!, size!);
  },
  fits: (c) => {
    const [value, size] = args(c, 2);
    return guarded("fits", () => (fits(value!, size!, "fits"), []));
  },
  field: (c) => {
    const [limb, shift, size] = args(c, 3);
    return [field(limb!, shift!, size!)];
  },
  byte_at: (c) => {
    const [limb, shift] = args(c, 2);
    return [byte_at(limb!, shift!)];
  },
  u16_at: (c) => {
    const [limb, shift] = args(c, 2);
    return [u16_at(limb!, shift!)];
  },
  u32_at: (c) => {
    const [limb, shift] = args(c, 2);
    return [u32_at(limb!, shift!)];
  },
  low_field: (c) => {
    const [limb, size] = args(c, 2);
    return [low_field(limb!, size!)];
  },
  pack_lanes32: (c) => [pack_lanes32({ lanes: args(c, 7) })],
  unpack_lanes32: (c) => unpack_lanes32(args(c, 1)[0]!).lanes,
  pack_lanes16: (c) => [pack_lanes16({ lanes: args(c, 15) })],
  unpack_lanes16: (c) => unpack_lanes16(args(c, 1)[0]!).lanes,
  pack_counter: (c) => [pack_counter({ value: args(c, 1)[0]! })],
  unpack_counter: (c) => [unpack_counter(args(c, 1)[0]!).value],
  pack_bitmap: (c) => {
    const [bits] = args(c, 1);
    return guarded(packingErrors.BITMAP, () => [pack_bitmap({ bits: bits! })]);
  },
  unpack_bitmap: (c) => [unpack_bitmap(args(c, 1)[0]!).bits],
};

/** `None` as the movement table writes it. */
const NONE = 255n;
const orNone = (value: number | undefined): bigint => (value === undefined ? NONE : BigInt(value));

const movement: Record<string, Mirror> = {
  origin: (c) => {
    const [x, y] = args(c, 2).map(small);
    const at = board(x!, y!);
    return [BigInt(at.x), BigInt(at.y), BigInt(position(at, x!, y!))];
  },
  move: (c) => {
    const [from, direction] = args(c, 2).map(small);
    return [orNone(neighbor(from!, direction!))];
  },
  ticks: (c) => {
    const [crippled, t0, movement] = args(c, 3);
    const deadline = Number(fromFelt(u32, crippled!));
    return [BigInt(move_ticks(deadline, Number(fromFelt(u32, t0!)), boolFromFelt(movement!)))];
  },
  // The table's flood: from its source, no obstacle, capped at 15 layers; the walker not blocked
  flood: (c) => {
    const [grid, source, walker] = args(c, 3);
    const layers = flood(grid!, small(source!), 0n, 15);
    return [
      orNone(next_step(layers, small(walker!), 0n)),
      orNone(flood_distance(layers, small(walker!))),
    ];
  },
  // The table's goblins: entity `8 + k`, alive, the fourth (k = 3) asleep
  awake: (c) => {
    const distances = c.map((d) => Number(fromFelt(u16, d)));
    const goblins = distances.map((_, k) => ({ entity: 8 + k, alive: true, asleep: k === 3 }));
    return awake(goblins, distances).map((index) => BigInt(8 + index));
  },
};

const reveal: Record<string, Mirror> = {
  word: (c) => {
    const [entropy, instance, chunk] = args(c, 3);
    return [word(entropy!, instance!, small(chunk!))];
  },
  feed: (c) => {
    const [entropy, ...fact] = args(c, 4);
    return [feed(entropy!, fact)];
  },
  base: (c) => {
    const [word, biome] = args(c, 2);
    return [base(word!, small(biome!))];
  },
  sight: (c) => {
    const [x, y, width, height] = args(c, 4).map(small);
    return chunks(x!, y!, width!, height!).map(BigInt);
  },
  member: (c) => {
    const [tile, k, odd] = args(c, 3);
    return optionToFelts(member(small(tile!), small(k!), boolFromFelt(odd!)));
  },
  reveal: (c) => {
    const [site, progress, instance, known, asked] = revealFromFelts(c);
    const out = revealChunks(site, progress, instance, known, asked);
    return [...progressToFelts(progress), ...revealedToFelts(out)];
  },
};

/**
 * The batch table's rows. `records` is `admit` as the Cairo test prints it: stopped, the records
 * counted after, the weight left (the weight kept when stopped). `owed` and `reveal` restate what
 * the test builds around `admit` (the owed records added, the `written` count with no next
 * action, `PlayLibrary`'s order of Move then reveal); only `admit` and `revealed` are the contract's.
 */
const batch: Record<string, Mirror> = {
  records: (c) => {
    const [changed, fresh, firsts, cost, ran, weight] = args(c, 6);
    const left = admit(
      Number(changed!),
      Number(fresh!),
      small(firsts!),
      small(cost!),
      boolFromFelt(ran!),
      small(weight!),
    );
    return left === undefined ? [1n, changed!, weight!] : [0n, changed! + fresh!, BigInt(left)];
  },
  owed: (c) => {
    const [changed, owed, owedFirsts, fresh, firsts, cost, weight, next] = args(c, 8);
    if (!boolFromFelt(next!)) return [0n, changed! + owed!, weight!];
    const left = admit(
      Number(changed!),
      Number(owed! + fresh!),
      small(owedFirsts! + firsts!),
      small(cost!),
      true,
      small(weight!),
    );
    return left === undefined
      ? [1n, changed! + owed!, weight!]
      : [0n, changed! + owed! + fresh!, BigInt(left)];
  },
  reveal: (c) => {
    const [weight, ticks, firsts, chunks] = args(c, 4);
    const after = admit(0, small(firsts!), small(firsts!), small(ticks!), true, small(weight!));
    if (after === undefined) panic("Option::unwrap failed.");
    return [BigInt(after), BigInt(revealed(after, Number(chunks!)))];
  },
};

/** The member words of a `segment` row's adventurer: its place, status, health and timers. */
type Standing = {
  x: number;
  y: number;
  facing: number;
  status: number;
  health: number;
  crippled: number;
  knocked: number;
};

const two = (bits: number): bigint => 1n << BigInt(bits);

/**
 * The words of a `segment` row's adventurer as the unit-test fixture's member: max health 480, no
 * regeneration (stored 10, its pips + 10), no energy, adrenaline, activation (`NO_SLOT`),
 * condition but Crippled and the knock-down, effect, skill or belt; flags 0. What the row prints
 * of it (its place and flags) is all a tick on the fast path can change of it.
 */
function standing(a: Standing): MemberWords {
  return {
    state:
      LIVE +
      BigInt(a.x) * two(32) +
      BigInt(a.y) * two(40) +
      BigInt(a.facing) * two(48) +
      BigInt(a.status) * two(56) +
      BigInt(a.health) * two(64),
    timers: LIVE + 255n + BigInt(a.crippled) * two(160) + BigInt(a.knocked) * two(192),
    effects: LIVE,
    recharges: LIVE,
    stats: LIVE + 480n + 10n * two(32),
    bar: LIVE,
    kit: LIVE,
  };
}

/** A `segment` row's case: the adventurer alone, `Area`, `owed`, `weight`, the actions. */
function segmentFromFelts(c: readonly bigint[]): Segment {
  const read = new Felts(c);
  const clock = read.u32();
  const [x, y, facing, status] = [read.u8(), read.u8(), read.u8(), read.u8()];
  const health = read.u16();
  const [crippled, knocked] = [read.u32(), read.u32()];
  const member = standing({ x, y, facing, status, health, crippled, knocked });
  const words: Words = { clock, members: [member], goblins: [], killed: [], defeated: false };
  const area = readArea(read);
  const [owed, weight] = [read.u8(), read.u8()];
  const actions = read.span(() => readAction(read));
  read.end();
  const content = { skills: [], potions: [], castes: [] };
  return { words, content, area, level: 1, ground: [], owed, weight, actions };
}

/** The classes of a table that never reaches them: a call fails its row. */
const UNREACHED: Classes = {
  ticks: () => panic("segment.jsonl: a TickLibrary call"),
  act: () => panic("segment.jsonl: an ActionLibrary call"),
  trigger: () => panic("segment.jsonl: a TrapLibrary call"),
};

/** The adventurer's clock, place and flags after, then `Done`, as the row prints them. */
function segmentToFelts(words: Words, done: Done): bigint[] {
  const [low, high] = limbs(words.members[0]!.state);
  const [x, y, facing] = [32n, 40n, 48n].map((shift) => (low >> shift) & 0xffn);
  return [BigInt(words.clock), x!, y!, facing!, (high >> 32n) & 0xffn, ...writeDone(done)];
}

/** Every `fn` of the segment table is one call of `run`; the `fn` names the branch it is about. */
const segmentRow: Mirror = (c) => {
  const { words, done } = runSegment(segmentFromFelts(c), UNREACHED);
  return segmentToFelts(words, done);
};

const segment: Record<string, Mirror> = Object.fromEntries(
  ["fold", "reveal", "cost", "ran", "fits", "halt"].map((name) => [name, segmentRow]),
);

/** `segment2.jsonl`'s content: its row 0's `ok`, which every other row loads its words through. */
let content2: Content | undefined;
function content(): Content {
  if (content2 === undefined) {
    const read = new Felts(readTable("segment2.jsonl")[0]!.ok!);
    content2 = readContent(read);
    read.end();
  }
  return content2;
}

/** The calls of `segment2.jsonl` the ports computed, each equal to its recording, by kind. */
export const native = { triggers: 0, acts: 0, ticks: 0 };

const ticksFelts = (out: { words: Words; ground: Ground }): bigint[] => [
  ...writeWords(out.words),
  ...writeGround(out.ground),
];

const callFelts = (out: { words: Words; ground: Ground; triggered: boolean }): bigint[] => [
  ...writeWords(out.words),
  ...writeGround(out.ground),
  ...bool(out.triggered),
];

/** `Result<u8, Illegal>`'s `Serde`. */
const outcomeFelts = (outcome: Outcome): bigint[] =>
  "ticks" in outcome ? [0n, BigInt(outcome.ticks)] : [1n, BigInt(outcome.illegal)];

const actFelts = (out: { words: Words; ground: Ground; outcome: Outcome }): bigint[] => [
  ...writeWords(out.words),
  ...writeGround(out.ground),
  ...outcomeFelts(out.outcome),
];

/** Throws unless two results are felt for felt the same. */
function equal(name: string, got: readonly bigint[], recorded: readonly bigint[]): void {
  if (got.length !== recorded.length || got.some((felt, i) => felt !== recorded[i])) {
    throw new Error(`${name} computed ${got}, recorded ${recorded}`);
  }
}

/**
 * The replayed classes with the three computed by the ports (`trap.ts`'s `triggerClass`,
 * `action.ts`'s `actClass`, `tick.ts`'s `ticksClass`): the replayer still takes the recorded call
 * (its kind, its digest, its place in the span), and the port's result must equal it, felt for
 * felt; the port's is what `run` loads.
 */
function computed(replayed: ReturnType<typeof replayer>): ReturnType<typeof replayer> {
  return {
    ...replayed,
    ticks(call) {
      const recorded = ticksFelts(replayed.ticks(call));
      const out = ticksClass(call);
      equal("ticks", ticksFelts(out), recorded);
      native.ticks += 1;
      return out;
    },
    trigger(call) {
      const recorded = callFelts(replayed.trigger(call));
      const out = triggerClass(call);
      equal("trigger", callFelts(out), recorded);
      native.triggers += 1;
      return out;
    },
    act(call) {
      const recorded = actFelts(replayed.act(call));
      const out = actClass(call);
      equal("act", actFelts(out), recorded);
      native.acts += 1;
      return out;
    },
  };
}

/**
 * A `segment2` row: `run` on the case's words, area, level, ground, `owed`, `weight` and actions,
 * the classes replayed from the calls the row recorded (test scaffolding) and computed by the ports
 * (`computed`); the words, the ground and `Done` after it.
 */
const segment2Row: Mirror = (c) => {
  const read = new Felts(c);
  const words = readWords(read);
  const area = readArea(read);
  const level = read.u8();
  const ground = readGround(read);
  const [owed, weight] = [read.u8(), read.u8()];
  const actions = read.span(() => readAction(read));
  const calls = read.span(() => readCall(read));
  read.end();
  const classes = computed(replayer(calls));
  const out = runSegment(
    { words, content: content(), area, level, ground, owed, weight, actions },
    classes,
  );
  classes.end();
  return [...writeWords(out.words), ...writeGround(out.ground), ...writeDone(out.done)];
};

const segment2: Record<string, Mirror> = {
  // The table's content, decoded and encoded again: what every other row reads
  content: (c) => {
    args(c, 0);
    return writeContent(content());
  },
  ...Object.fromEntries(
    [
      ...["combat", "ticks", "fits", "defeated", "trap", "occupied", "companions"],
      ...["regeneration", "movement", "turn", "follow"],
    ].map((name) => [name, segment2Row]),
  ),
};

/** `body.jsonl`'s content: its row 0's `ok`, which every actor of the table is loaded through. */
let bodyContent: Content | undefined;
function contentOfBody(): Content {
  if (bodyContent === undefined) {
    const read = new Felts(readTable("body.jsonl")[0]!.ok!);
    bodyContent = readContent(read);
    read.end();
  }
  return bodyContent;
}
let bodySheets: ReturnType<typeof indexed> | undefined;
const sheetsOfBody = () => (bodySheets ??= indexed(contentOfBody()));

/** An `Entry`'s `Serde`, its 12 fields. */
function readEntry(r: Felts): EffectEntry {
  return {
    kind: r.u8(),
    param: r.u8(),
    v0: r.i16(),
    v12: r.i16(),
    d0: r.u16(),
    d12: r.u16(),
    charges: r.u8(),
    target: r.u8(),
    shape: r.u8(),
    filter: r.u8(),
    guard: r.u8(),
    scope: r.u8(),
  };
}

const writeEntry = (e: EffectEntry): bigint[] => [
  ...[e.kind, e.param].map(BigInt),
  toFelt(i16, BigInt(e.v0)),
  toFelt(i16, BigInt(e.v12)),
  ...[e.d0, e.d12, e.charges, e.target, e.shape, e.filter, e.guard, e.scope].map(BigInt),
];

/** A `body` row: the actor, then the operation's arguments read by `args`, all read. */
function onUnit<T>(c: readonly bigint[], args: (r: Felts) => T): [body.Unit, T] {
  const read = new Felts(c);
  const unit = readUnit(read);
  const rest = args(read);
  read.end();
  return [unit, rest];
}

/** A read of the actor: its value's felts. */
const reading =
  (get: (unit: body.Unit) => number | boolean): Mirror =>
  (c) => {
    const [unit] = onUnit(c, () => undefined);
    return [BigInt(get(unit))];
  };

/** A write on the actor: its arguments read by `args`, the actor after. */
const writing =
  <T>(args: (r: Felts) => T, op: (unit: body.Unit, rest: T) => void): Mirror =>
  (c) => {
    const [unit, rest] = onUnit(c, args);
    op(unit, rest);
    return writeUnit(unit);
  };

const i32of = (r: Felts): number => Number(fromFelt(i32, r.felt()));

/** An entry row: its `case` read by `args`, all read. */
function onEntry<T>(c: readonly bigint[], args: (r: Felts) => T): T {
  const read = new Felts(c);
  const rest = args(read);
  read.end();
  return rest;
}

const bodyFns: Record<string, Mirror> = {
  // The table's content, decoded and encoded again: what every actor is loaded through
  content: (c) => {
    args(c, 0);
    return writeContent(contentOfBody());
  },
  health: reading(body.health),
  max_health: reading(body.max_health),
  is_member: reading(body.is_member),
  alive: reading(body.alive),
  asleep: reading(body.asleep),
  halves: reading(body.halves),
  enchant_percent: reading(body.enchant_percent),
  slots: reading(body.slots),
  place: (c) => {
    const [unit] = onUnit(c, () => undefined);
    const { x, y, facing } = body.place(unit);
    return [x, y, facing].map(BigInt);
  },
  knocked: (c) => {
    const [unit, t] = onUnit(c, (r) => r.u32());
    return [BigInt(body.knocked(unit, t))];
  },
  armor_vs: (c) => {
    const [unit, type] = onUnit(c, (r) => r.u8());
    return [BigInt(body.armor_vs(unit, type, sheetsOfBody()))];
  },
  infliction: (c) => {
    const [unit] = onUnit(c, () => undefined);
    return writeInfliction(body.infliction(unit));
  },
  effect: (c) => {
    const [unit, slot] = onUnit(c, (r) => r.u8());
    const { held, at } = body.effect(unit, slot);
    return [...writeHeld(held), BigInt(at)];
  },
  wound: writing(
    (r) => r.u16(),
    (unit, damage) => body.wound(unit, damage),
  ),
  heal: writing(
    (r) => r.u16(),
    (unit, v) => body.heal(unit, v),
  ),
  energize: writing(i32of, (unit, v) => body.energize(unit, v, sheetsOfBody())),
  struck: writing(
    () => undefined,
    (unit) => body.struck(unit, sheetsOfBody()),
  ),
  landed: writing(
    () => undefined,
    (unit) => body.landed(unit, sheetsOfBody()),
  ),
  halved: writing(
    () => undefined,
    (unit) => body.halved(unit),
  ),
  inflict: writing(
    (r) => ({ c: r.u8(), v: i32of(r), source: readInfliction(r), t: r.u32() }),
    (unit, { c, v, source, t }) => body.inflict(unit, c, v, source, t, sheetsOfBody()),
  ),
  cure: writing(
    (r) => ({ c: r.u8(), t: r.u32() }),
    (unit, { c, t }) => body.cure(unit, c, t),
  ),
  hold: writing(
    (r) => ({ held: readHeld(r), at: r.u32(), stance: r.bool(), t: r.u32() }),
    (unit, { held, at, stance, t }) => body.hold(unit, held, at, stance, t, sheetsOfBody()),
  ),
  spend: writing(
    (r) => ({ slot: r.u8(), t: r.u32() }),
    (unit, { slot, t }) => body.spend(unit, slot, t),
  ),
  line: (c) => {
    const [v0, v12, rank] = onEntry(c, (r) => [r.i16(), r.i16(), r.u8()]);
    return [toFelt(i32, BigInt(line(v0!, v12!, rank!)))];
  },
  value: (c) => {
    const [entry, rank] = onEntry(c, (r) => [readEntry(r), r.u8()] as const);
    return [toFelt(i32, BigInt(value(entry, rank)))];
  },
  duration: (c) => {
    const [entry, rank] = onEntry(c, (r) => [readEntry(r), r.u8()] as const);
    return [toFelt(i32, BigInt(duration(entry, rank)))];
  },
  class: (c) => {
    const entry = { ...unpack(0n), kind: onEntry(c, (r) => r.u8()) };
    const found = class_(entry);
    return [
      ...(found === undefined ? [1n] : [0n, BigInt(found)]),
      ...bool(is_holding(entry)),
      ...bool(is_hit_modifier(entry)),
    ];
  },
  pack: (c) => [pack(onEntry(c, readEntry))],
  unpack: (c) => writeEntry(unpack(onEntry(c, (r) => fromFelt(u128, r.felt())))),
};

/** The tables whose rows read their latest `content` row (`contentRow`), each read once. */
const rowsOf = new Map<string, Vector[]>();
/** Each `content` row's content, decoded once, by its table and id. */
const contents = new Map<string, Content>();

/** The content row `id` of `file` reads: the `ok` of its last `content` row at or before it. */
function contentAt(file: string, id: number): Content {
  let rows = rowsOf.get(file);
  if (rows === undefined) rowsOf.set(file, (rows = readTable(file)));
  const at = contentRow(rows, id);
  const key = `${file} ${at}`;
  let found = contents.get(key);
  if (found === undefined) {
    const read = new Felts(rows[at]!.ok!);
    found = readContent(read);
    read.end();
    contents.set(key, found);
  }
  return found;
}

/** `trap.jsonl`'s content for row `id`: its latest `content` row's, which its words are loaded through. */
const contentOfTrap = (id: number): Content => contentAt("trap.jsonl", id);

const trap: Record<string, Mirror> = {
  // The row's content, decoded and encoded again: what every later `trigger` row reads
  content: (c, id) => {
    args(c, 0);
    return writeContent(contentOfTrap(id));
  },
  // `TrapLibrary::trigger` on the case's words, board, ground, entrant, position and level
  trigger: (c, id) => {
    const read = new Felts(c);
    const words = readWords(read);
    const board = readBoard(read);
    const ground = readGround(read);
    const [entrant, position, level] = [read.u16(), read.u8(), read.u8()];
    read.end();
    const out = triggerClass({
      words,
      content: contentOfTrap(id),
      board,
      ground,
      entrant,
      position,
      level,
    });
    return [...writeWords(out.words), ...writeGround(out.ground), ...bool(out.triggered)];
  },
  free: (c) => {
    const read = new Felts(c);
    const features = readFeatures(read);
    const tile = read.u8();
    read.end();
    const found = free(features, tile);
    return found === undefined ? [1n] : [0n, BigInt(found)];
  },
};

/** `act.jsonl`'s content for row `id`: its latest `content` row's, which its actors are loaded through. */
const contentOfAct = (id: number): Content => contentAt("act.jsonl", id);
const actSheets = new Map<Content, ReturnType<typeof indexed>>();
function sheetsOfAct(id: number): ReturnType<typeof indexed> {
  const content = contentOfAct(id);
  let found = actSheets.get(content);
  if (found === undefined) actSheets.set(content, (found = indexed(content)));
  return found;
}

/** An actor as an `act.jsonl` row records it: `0` and its `MemberWords`, or `1` and its `GoblinWords`, loaded. */
function readActor(r: Felts, sheets: ReturnType<typeof indexed>): body.Unit {
  const tag = r.u8();
  if (tag === 0) {
    const [state, timers, effects, recharges, stats, bar, kit] = r.fixed(7, () => r.felt());
    const words = { state, timers, effects, recharges, stats, bar, kit } as MemberWords;
    return { kind: "M", member: loadMember(words, sheets) };
  }
  if (tag === 1) {
    const words = { entity: r.u16(), awake: r.bool(), state: r.felt(), timers: r.felt() };
    return { kind: "G", goblin: loadGoblin(words, sheets) };
  }
  throw new RangeError(`actor tag ${tag}`);
}

/** The actor of a `defence` or `offence` row: a member as member 0, a goblin as goblin 0. */
const actorOfUnit = (unit: body.Unit): executor.Actor =>
  unit.kind === "M" ? { kind: "M", i: 0 } : { kind: "G", i: 0 };

const signed8 = (v: number): bigint => toFelt(i8, BigInt(v));
const signed16 = (v: number): bigint => toFelt(i16, BigInt(v));

const act: Record<string, Mirror> = {
  // The row's content, decoded and encoded again: what every later actor is loaded through
  content: (c, id) => {
    args(c, 0);
    return writeContent(contentOfAct(id));
  },
  // `ActionLibrary::act` on the case's words, board, ground and action
  act: (c, id) => {
    const read = new Felts(c);
    const words = readWords(read);
    const board = readBoard(read);
    const ground = readGround(read);
    const action = readAction(read);
    read.end();
    const out = actClass({ words, content: contentOfAct(id), board, ground, action });
    return actFelts(out);
  },
  // `Body::defence` through `UnitBody`, `Levered` with a fresh `Cache`
  defence: (c, id) => {
    const read = new Felts(c);
    const sheets = sheetsOfAct(id);
    const unit = readActor(read, sheets);
    const t = read.u32();
    read.end();
    const d = executor.defence(executor.cache(), unit, actorOfUnit(unit), t, sheets);
    return [
      signed16(d.armor),
      BigInt(d.effects),
      signed8(d.stance),
      signed8(d.enchanted),
      ...bool(d.in_stance),
      ...bool(d.is_enchanted),
      BigInt(d.block),
      BigInt(d.block_slot),
      ...bool(d.evade),
    ];
  },
  // `Body::offence` through `UnitBody`
  offence: (c, id) => {
    const read = new Felts(c);
    const sheets = sheetsOfAct(id);
    const unit = readActor(read, sheets);
    const cls = read.u8();
    if (cls > 3) throw new RangeError(`hit class ${cls}`);
    const entry = readEntry(read);
    const bonus = read.u32();
    const penetration = read.u16();
    const context: executor.Context = {
      rank: read.u8(),
      infliction: readInfliction(read),
      enchant: read.u8(),
      skill_kind: read.u8(),
      carrier: read.u16(),
      potion: read.bool(),
      at: read.u32(),
      scope: read.u8(),
      t: read.u32(),
    };
    read.end();
    const o = executor.offence(
      unit,
      cls as executor.Offence["class"],
      entry,
      bonus,
      penetration,
      context,
      sheets,
    );
    return [
      BigInt(o.class),
      BigInt(o.weapon),
      ...bool(o.melee),
      BigInt(o.strength),
      BigInt(o.base),
      signed16(o.percent),
      signed16(o.above),
      BigInt(o.penetration),
      BigInt(o.damage_type),
      BigInt(o.steal),
      BigInt(o.energy),
    ];
  },
};

/** `tick.jsonl`'s content for row `id`: its latest `content` row's, which its words are loaded through. */
const contentOfTick = (id: number): Content => contentAt("tick.jsonl", id);

/** `tick.jsonl`'s level, the location band's lower one (`vectors::LEVEL`). */
const TICK_LEVEL = 20;

/** The `skip` rows' ground: chunk 0, empty (`FeaturesTrait::empty`). */
const emptyGround = (): Ground => [
  [
    0,
    {
      packs: [0, 1].map(() => ({ tile: 0, template: 0, level: 0, count: 0, offsets: 0, alert: 0 })),
      objects: [0, 1, 2].map(() => ({ tile: 0, kind: 0, state: 0, param: 0 })),
      touched: 0,
    },
  ],
];

const tick: Record<string, Mirror> = {
  // The row's content, decoded and encoded again: what every later row reads
  content: (c, id) => {
    args(c, 0);
    return writeContent(contentOfTick(id));
  },
  // `TickLibrary::ticks` on the case's words, board, level, ground and `n`
  ticks: (c, id) => {
    const read = new Felts(c);
    const words = readWords(read);
    const board = readBoard(read);
    const level = read.u8();
    const ground = readGround(read);
    const n = read.u8();
    read.end();
    return ticksFelts(ticksClass({ words, content: contentOfTick(id), board, level, ground, n }));
  },
  // `SegmentTrait::ticks`' path for `n` ticks, then the words after it (the empty ground)
  skip: (c, id) => {
    const read = new Felts(c);
    const words = readWords(read);
    const board = readBoard(read);
    const n = read.u8();
    read.end();
    const content = contentOfTick(id);
    const world = loadWorld(words, indexed(content));
    const way = path(world, board, n);
    let after = words;
    if (way === 1) {
      fast(world, n);
      after = storeWorld(world);
    } else if (way === 0) {
      const ground = emptyGround();
      after = ticksClass({ words, content, board, level: TICK_LEVEL, ground, n }).words;
    }
    return [BigInt(way), ...writeWords(after)];
  },
};

export const TABLES: readonly Entry[] = [
  { file: "window.jsonl", floor: 2065, fns: window },
  { file: "hit.jsonl", floor: 200, fns: hit },
  { file: "body.jsonl", floor: 334, fns: bodyFns },
  { file: "trap.jsonl", floor: 87, fns: trap },
  { file: "act.jsonl", floor: 244, fns: act },
  { file: "fate.jsonl", floor: 227, fns: fate },
  { file: "packing.jsonl", floor: 520, fns: packing },
  { file: "movement.jsonl", floor: 81, fns: movement },
  { file: "reveal.jsonl", floor: 197, fns: reveal },
  { file: "batch.jsonl", floor: 28, fns: batch },
  { file: "segment.jsonl", floor: 47, fns: segment },
  { file: "segment2.jsonl", floor: 44, fns: segment2 },
  { file: "tick.jsonl", floor: 171, fns: tick },
];
