// The packing of records into one felt: the mirror of `contracts/logic/src/packing.cairo` (its
// three rules, its costs and its reasons are the Cairo module's documentation), held equal to it by
// `contracts/logic/vectors/packing.jsonl` (VEC-01). A limb, a field and a lane are `bigint` of
// their Cairo type; a guard that panics in Cairo throws its `CairoPanic` here, never writes.

import { type IntType, P, arg, feltArg, narrow, panic, u16, u32, u64, u128 } from "./felt";

/** Bit 250, set in every stored record: a stored slot is never 0. */
export const LIVE = 2n ** 250n;
/** `LIVE` as seen in the high limb (bit 122 of it). */
export const LIVE_HIGH = 2n ** 122n;
/** 2^128. */
export const TWO_POW_128 = 2n ** 128n;

export const errors = {
  HIGH: "packing: high limb overflow",
  BITMAP: "packing: bitmap above bit 249",
} as const;

const LOW_MASK = TWO_POW_128 - 1n;
const P16 = 2n ** 16n;
const P32 = 2n ** 32n;

/** A felt's two `u128` limbs, `[low, high]`, as `felt252 → u256` gives them. */
function wide(word: bigint): [bigint, bigint] {
  feltArg(word);
  return [word & LOW_MASK, word >> 128n];
}

/** A `NonZero<u128>` divisor: Cairo cannot hold 0 there, so 0 is a bug of the caller. */
function nonZero(size: bigint): bigint {
  if (arg(u128, size) === 0n) throw new RangeError("a NonZero<u128> is not 0");
  return size;
}

/** `shift.try_into().unwrap()` into a `NonZero<u128>`: 0 is the panic of the failed unwrap. */
function toNonZero(value: bigint): bigint {
  if (arg(u128, value) === 0n) panic("Option::unwrap failed.");
  return value;
}

/** The two limbs of any word, `LIVE` removed from the high one if it is set. */
export function split(word: bigint): [bigint, bigint] {
  const [low, high] = wide(word);
  return high < LIVE_HIGH ? [low, high] : [low, high - LIVE_HIGH];
}

/** The two limbs of a stored record (it carries `LIVE`), `LIVE` removed as a field subtraction. */
export function limbs(word: bigint): [bigint, bigint] {
  return wide((((feltArg(word) - LIVE) % P) + P) % P);
}

/** A stored record from its two limbs, `LIVE` set; a high limb from 2^122 up panics. */
export function join(low: bigint, high: bigint): bigint {
  arg(u128, low);
  if (arg(u128, high) >= LIVE_HIGH) panic(errors.HIGH);
  return low + high * TWO_POW_128 + LIVE;
}

/** The low field of `rest`, of width `size`, and what remains: `[value, rest]` (Cairo's `ref`). */
export function peel(rest: bigint, size: bigint): [bigint, bigint] {
  nonZero(size);
  return [arg(u128, rest) % size, rest / size];
}

/** Panics with `message` when `value` is not below its field's `size`. */
export function fits(value: bigint, size: bigint, message: string): void {
  if (!(arg(u128, value) < arg(u128, size))) panic(message);
}

/** The field of `limb` at bit `2^offset = shift`, of width `2^width = size`. */
export function field(limb: bigint, shift: bigint, size: bigint): bigint {
  arg(u128, limb);
  return (limb / toNonZero(shift)) % toNonZero(size);
}

/** The byte of `limb` at `shift`. */
export function byte_at(limb: bigint, shift: bigint): bigint {
  return field(limb, shift, 0x100n);
}

/** The `u16` of `limb` at `shift`. */
export function u16_at(limb: bigint, shift: bigint): bigint {
  return field(limb, shift, P16);
}

/** The `u32` of `limb` at `shift`. */
export function u32_at(limb: bigint, shift: bigint): bigint {
  return field(limb, shift, P32);
}

/** The low field of `limb`, of width `size`. */
export function low_field(limb: bigint, size: bigint): bigint {
  return arg(u128, limb) % nonZero(size);
}

/** Seven `u32` lanes: 0 to 3 in the low limb, 4 to 6 in the high one. */
export type Lanes32 = { lanes: readonly bigint[] };

/** Fifteen `u16` lanes: 0 to 7 in the low limb, 8 to 14 in the high one. */
export type Lanes16 = { lanes: readonly bigint[] };

function lanesOf(value: { lanes: readonly bigint[] }, count: number, type: IntType): bigint[] {
  if (value.lanes.length !== count)
    throw new RangeError(`${value.lanes.length} lanes, not ${count}`);
  return value.lanes.map((lane) => arg(type, lane));
}

export function pack_lanes32(value: Lanes32): bigint {
  const [a, b, c, d, e, f, g] = lanesOf(value, 7, u32) as [
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
  ];
  const low = a + b * P32 + c * P32 ** 2n + d * P32 ** 3n;
  const high = e + f * P32 + g * P32 ** 2n;
  return join(low, high);
}

/** A word without `LIVE` decodes by `split`; the last lane of each limb is its quotient. */
export function unpack_lanes32(word: bigint): Lanes32 {
  const [low, high] = split(word);
  const [a, l1] = peel(low, P32);
  const [b, l2] = peel(l1, P32);
  const [c, d] = peel(l2, P32);
  const [e, h1] = peel(high, P32);
  const [f, g] = peel(h1, P32);
  return { lanes: [a, b, c, d, e, f, g].map((lane) => narrow(u32, lane)) };
}

export function pack_lanes16(value: Lanes16): bigint {
  const lanes = lanesOf(value, 15, u16);
  let low = 0n;
  let high = 0n;
  lanes.forEach((lane, i) => {
    if (i < 8) low += lane * P16 ** BigInt(i);
    else high += lane * P16 ** BigInt(i - 8);
  });
  return join(low, high);
}

/** Eight lanes peeled from the low limb, seven from the high one; what remains above is dropped. */
export function unpack_lanes16(word: bigint): Lanes16 {
  const [low, high] = split(word);
  const lanes: bigint[] = [];
  for (const [limb, count] of [
    [low, 8],
    [high, 7],
  ] as const) {
    let rest = limb;
    for (let i = 0; i < count; i++) {
      const [lane, next] = peel(rest, P16);
      lanes.push(narrow(u16, lane));
      rest = next;
    }
  }
  return { lanes };
}

/** A `u64` counter kept with `LIVE`, so that it is never 0 in storage. */
export type Counter = { value: bigint };

export function pack_counter(value: Counter): bigint {
  return join(arg(u64, value.value), 0n);
}

/** The low limb only, `try_into` a `u64`. */
export function unpack_counter(word: bigint): Counter {
  const [low] = split(word);
  return { value: narrow(u64, low) };
}

/** A bitmap of 250 bits (bits 0 to 249), `LIVE` at bit 250 when stored. */
export type Bitmap = { bits: bigint };

export function pack_bitmap(value: Bitmap): bigint {
  const [, high] = wide(value.bits);
  if (high >= LIVE_HIGH) panic(errors.BITMAP);
  return value.bits + LIVE;
}

export function unpack_bitmap(word: bigint): Bitmap {
  const [low, high] = split(word);
  return { bits: low + high * TWO_POW_128 };
}
