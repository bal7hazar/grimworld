// What a source adds to the conditions it inflicts (CLI-02g-C): `types/infliction.cairo`'s
// `Infliction` and its `duration`, and `durations.cairo`'s `effective_duration`. A member reads it
// in its kit (`member.ts`, `infliction`); a goblin and a terrain trap hold none (`NONE`).

import { condition } from "../combat";
import { add, div, mul, panic, u32 } from "../felt";

/** `types::infliction::Infliction`: `CONDITION_DURATION`'s condition and percent, `KNOCKDOWN_FLAT`. */
export type Infliction = { condition: number; percent: number; knockdown: number };

/** `Infliction`'s `Default`: a goblin's, a terrain trap's. */
export const NONE: Infliction = { condition: 0, percent: 0, knockdown: 0 };

/** `durations.cairo`'s bounds, and `types::MAX_DURATION`. */
export const MAX_BASE_DURATION = 43688;
const MAX_DURATION_BONUS_PERCENT = 50;
const MAX_DURATION_FLAT = 3;
const MAX_DURATION = 0xffff;
/** `effect::MAX_VALUE_DURATION`: a duration carried as a value is 1…32,767 ticks. */
const MAX_VALUE_DURATION = 32767;

export const errors = {
  BASE: "duration: base above the cap",
  MAX: "duration: above MAX_DURATION",
} as const;

const u32op = (op: typeof add, a: number, b: number): number =>
  Number(op(u32, BigInt(a), BigInt(b)));

/**
 * `effective_duration`: `base × (100 + percent) / 100 + flat`, the percent capped at 50 and the
 * flat ticks at 3; a base above `MAX_BASE_DURATION` and a result above `MAX_DURATION` panic.
 */
export function effective_duration(base: number, bonus_percent: number, flat: number): number {
  if (!(base <= MAX_BASE_DURATION)) panic(errors.BASE);
  const percent = Math.min(bonus_percent, MAX_DURATION_BONUS_PERCENT);
  const ticks = Math.min(flat, MAX_DURATION_FLAT);
  const scaled = u32op(div, u32op(mul, base, u32op(add, 100, percent)), 100);
  const effective = u32op(add, scaled, ticks);
  if (!(effective <= MAX_DURATION)) panic(errors.MAX);
  return effective;
}

/**
 * `InflictionTrait::duration`: `condition` inflicted with the value `v`, clamped to 1…32,767, then
 * `effective_duration` with the percent if the source's `CONDITION_DURATION` names it and the flat
 * ticks if it is Knocked down.
 */
export function duration(source: Infliction, c: number, v: number): number {
  const base = v < 1 ? 1 : v > MAX_VALUE_DURATION ? MAX_VALUE_DURATION : v;
  const percent = c === source.condition ? source.percent : 0;
  const flat = c === condition.KNOCKED_DOWN ? source.knockdown : 0;
  return effective_duration(base, percent, flat);
}
