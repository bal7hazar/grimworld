// The effect entry (CLI-02g-C, D-257): the mirror of `contracts/logic/src/types/effect.cairo`'s
// `Entry` and `EntryTrait` (its 97 bits, its line, its kind's class). An entry's layout, in the
// order of design/19 §2.1: kind 0–7 · param 8–15 · `v0` 16–31 · `v12` 32–47 (signed, two's
// complement) · `d0` 48–63 · `d12` 64–79 · charges 80–85 · target 86–87 · shape 88–90 · filter 91
// · guard 92–94 · scope 95–96. The content pipeline's checks (`assert_legal`, `assert_carrier`) are
// not mirrored: they run when content is written, never in play.

import { narrow, panic, u8 } from "./felt";
import { bits16, from16 } from "./signed";

/** `types::effect::Entry`. */
export type Entry = {
  kind: number;
  param: number;
  v0: number;
  v12: number;
  d0: number;
  d12: number;
  charges: number;
  target: number;
  shape: number;
  filter: number;
  guard: number;
  scope: number;
};

/** `types::effect::kind`: the effect kinds, 0 the empty entry. */
export const kind = {
  EMPTY: 0,
  DAMAGE: 1,
  ATTACK_BONUS: 2,
  HEAL: 3,
  LIFE_STEAL: 4,
  REGENERATION: 5,
  CONDITION: 6,
  CURE: 7,
  ENERGY: 8,
  NEXT_SPELL_COST: 9,
  ARMOR: 10,
  PENETRATION: 11,
  HIT_PENETRATION: 12,
  BLOCK: 13,
  EVADE: 14,
  ON_ATTACK_CONDITION: 15,
  MOVEMENT: 16,
  INTERRUPT: 17,
  TRAP: 18,
  LAST_MVP: 18,
} as const;

/** `types::effect::KindClass`, by its `Serde` variant index. */
export const KindClass = { Hit: 0, HitModifier: 1, Holding: 2, Instant: 3, Placement: 4 } as const;
export type KindClass = (typeof KindClass)[keyof typeof KindClass];

/** `MAX_RANK`: the highest rank a value scales to (FX-0b). */
export const MAX_RANK = 15;
/** `durations::MAX_BASE_DURATION`: the widest duration an entry holds. */
export const MAX_BASE_DURATION = 43688;

export const errors = {
  CHARGES: "entry: charges",
  TARGET: "entry: target",
  SHAPE: "entry: shape",
  FILTER: "entry: filter",
  GUARD: "entry: guard",
  SCOPE: "entry: scope",
  DURATION: "entry: duration",
  RANK: "entry: rank",
} as const;

const two = (bits: number): bigint => 1n << BigInt(bits);
const small = (value: bigint): number => Number(value);

/**
 * `EntryAssertTrait::assert_valid`: every field fits its layout (charges 6 bits, target 2, shape
 * 3, filter 1, guard 3, scope 2), the durations at most `MAX_BASE_DURATION`.
 */
export function assert_valid(entry: Entry): void {
  if (!(entry.charges < 0x40)) panic(errors.CHARGES);
  if (!(entry.target < 4)) panic(errors.TARGET);
  if (!(entry.shape < 8)) panic(errors.SHAPE);
  if (!(entry.filter < 2)) panic(errors.FILTER);
  if (!(entry.guard < 8)) panic(errors.GUARD);
  if (!(entry.scope < 4)) panic(errors.SCOPE);
  if (!(entry.d0 <= MAX_BASE_DURATION && entry.d12 <= MAX_BASE_DURATION)) panic(errors.DURATION);
}

/** `EntryTrait::pack`: the entry's 97 bits, after `assert_valid`. */
export function pack(entry: Entry): bigint {
  assert_valid(entry);
  return (
    BigInt(entry.kind) +
    BigInt(entry.param) * two(8) +
    bits16(entry.v0) * two(16) +
    bits16(entry.v12) * two(32) +
    BigInt(entry.d0) * two(48) +
    BigInt(entry.d12) * two(64) +
    BigInt(entry.charges) * two(80) +
    BigInt(entry.target) * two(86) +
    BigInt(entry.shape) * two(88) +
    BigInt(entry.filter) * two(91) +
    BigInt(entry.guard) * two(92) +
    BigInt(entry.scope) * two(95)
  );
}

/** `EntryTrait::unpack`: the entry of 97 bits (a limb: below 2^128). */
export function unpack(bits: bigint): Entry {
  let rest = bits;
  const take = (size: bigint): bigint => {
    const value = rest % size;
    rest /= size;
    return value;
  };
  const kind = small(take(0x100n));
  const param = small(take(0x100n));
  const v0 = from16(take(0x10000n));
  const v12 = from16(take(0x10000n));
  const d0 = small(take(0x10000n));
  const d12 = small(take(0x10000n));
  const charges = small(take(0x40n));
  const target = small(take(4n));
  const shape = small(take(8n));
  const filter = small(take(2n));
  const guard = small(take(8n));
  // What is left is the scope (`div_rem` of the last field keeps the quotient)
  const scope = Number(narrow(u8, rest));
  return { kind, param, v0, v12, d0, d12, charges, target, shape, filter, guard, scope };
}

/**
 * `EntryTrait::line`: `v0 + (v12 − v0) × rank / 12` in `i32`, truncated toward zero (§2.2); a rank
 * above `MAX_RANK` panics. `|v12 − v0| ≤ 65,535` and `rank ≤ 15`: the product fits an `i32`.
 */
export function line(v0: number, v12: number, rank: number): number {
  if (!(rank <= MAX_RANK)) panic(errors.RANK);
  return v0 + Math.trunc(((v12 - v0) * rank) / 12);
}

/** `EntryTrait::value`: the line on its `v0`, `v12`. */
export const value = (entry: Entry, rank: number): number => line(entry.v0, entry.v12, rank);

/** `EntryTrait::duration`: the line on its `d0`, `d12` (signed: `d12` may be below `d0`). */
export function duration(entry: Entry, rank: number): number {
  if (!(rank <= MAX_RANK)) panic(errors.RANK);
  return entry.d0 + Math.trunc(((entry.d12 - entry.d0) * rank) / 12);
}

/** `EntryTrait::class`: the kind's role for the executor; `undefined` for the empty entry and the kinds after the MVP. */
export function class_(entry: Entry): KindClass | undefined {
  const k = entry.kind;
  if (k === kind.DAMAGE) return KindClass.Hit;
  if (k === kind.ATTACK_BONUS || k === kind.HIT_PENETRATION) return KindClass.HitModifier;
  if (
    k === kind.REGENERATION ||
    (k >= kind.NEXT_SPELL_COST && k <= kind.PENETRATION) ||
    (k >= kind.BLOCK && k <= kind.MOVEMENT)
  ) {
    return KindClass.Holding;
  }
  if (k === kind.TRAP) return KindClass.Placement;
  if (k === kind.EMPTY || k > kind.LAST_MVP) return undefined;
  return KindClass.Instant;
}

/** `EntryTrait::is_holding`. */
export const is_holding = (entry: Entry): boolean => class_(entry) === KindClass.Holding;

/** `EntryTrait::is_hit_modifier`. */
export const is_hit_modifier = (entry: Entry): boolean =>
  entry.kind === kind.ATTACK_BONUS || entry.kind === kind.HIT_PENETRATION;
