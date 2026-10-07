// The tables the mirror replays, one entry each: the file in `contracts/logic/vectors/`, its floor
// (the cases it holds today: a table that loses cases fails) and the mirror's function per `fn`,
// adapting the felts of a case to the mirror's arguments and its result to Cairo's `Serde`.
// A new table of the game is one entry here.

import { CairoPanic, fromFelt, u32, u8 } from "../felt";
import { PURPOSES, derive, domain } from "../fate";
import { hitFromFelts, outcomeToFelts, resolve } from "../hit";
import {
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
import { arc, distance, facing, front, reach, shape, sight } from "../window";
import type { Entry, Mirror } from "./replay";

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

export const TABLES: readonly Entry[] = [
  { file: "window.jsonl", floor: 2065, fns: window },
  { file: "hit.jsonl", floor: 200, fns: hit },
  { file: "fate.jsonl", floor: 227, fns: fate },
  { file: "packing.jsonl", floor: 520, fns: packing },
];
