// What a tick shares between its actors, as named functions each with one source (CLI-02g-B1,
// CLI-02g-C): `TickMathTrait::{degeneration, effect_pips, heal, decay, held, refreshed, cured,
// recharge_deadline, min16}` and `TickAssert` (`helpers/tick.cairo`), `MemberTickTrait::regenerate`
// and `MemberConditionTrait::can_act` (`models/member.cairo`), and `types::tick`'s `flag` with its
// `KEPT`, `ai` and `status`. `segment.ts`'s fast path and `body/` call them; the ticks of the other
// lots are to call the same ones.

import { condition } from "../combat";
import { panic, sub, u32 } from "../felt";
import { u16add, u32add } from "./words";
import type { Member } from "./words";

/** `helpers::tick::errors`. */
export const errors = {
  CONDITION: "tick: condition not stored",
  DURATION: "tick: duration below 1",
  KNOCK: "tick: knock-down is knock",
} as const;

/** `types::tick::ai`: a goblin's AI state. */
export const ai = {
  ASLEEP: 0,
  WATCH: 1,
  ALERTED: 2,
  ENGAGED: 3,
  FLEEING: 4,
  RETURNING: 5,
  DEAD: 6,
  LOOTED: 7,
} as const;

/** `types::tick::status`: a member's place in the instance. */
export const status = { INSIDE: 0 } as const;

const u32sub = (a: number, b: number): number => Number(sub(u32, BigInt(a), BigInt(b)));

/** `TickAssert::assert_condition`: one of the MVP's five, 1–5. */
export function assert_condition(c: number): void {
  if (!(c >= condition.BLEEDING && c <= condition.LAST_MVP)) panic(errors.CONDITION);
}

/** `TickAssert::assert_duration`: at least 1 tick. */
export function assert_duration(d: number): void {
  if (!(d >= 1)) panic(errors.DURATION);
}

/** `TickMathTrait::refreshed`: inflicted at `t0` for `d ≥ 1` ticks, `max(old, t0 + d − 1)` (FX-6). */
export function refreshed(old: number, t0: number, d: number): number {
  assert_duration(d);
  const deadline = u32sub(u32add(t0, d), 1);
  return deadline > old ? deadline : old;
}

/** `TickMathTrait::cured`: held at `t0` (`old ≥ t0`), it ends at `t0 − 1`; else kept. */
export const cured = (old: number, t0: number): number => (old >= t0 ? u32sub(t0, 1) : old);

/** `TickMathTrait::recharge_deadline`: `t0 + r − 1`. */
export const recharge_deadline = (t0: number, r: number): number => u32sub(u32add(t0, r), 1);

/** `TickMathTrait::min16`. */
export const min16 = (a: number, b: number): number => (a < b ? a : b);

/** `MemberState.flags`: what happened "since the last tick" and "hit this tick" (`types::tick::flag`). */
export const flag = { TURNED: 1, INSTANT: 2, HIT: 8, HALVED: 16 } as const;
/** The flags a tick's step 0 keeps (`flag::KEPT`). */
export const KEPT = 0xff - flag.TURNED - flag.INSTANT - flag.HIT;

/** `types::tick::MAX_PIPS`, `HEALTH_PER_PIP` and `ADRENALINE_DECAY`. */
const MAX_PIPS = 10;
const HEALTH_PER_PIP = 2;
const ADRENALINE_DECAY = 1;

/** `TickMathTrait::held`: a condition of deadline `deadline` held at `t0` (`t0 ≤ D`). */
export const held = (deadline: number, t0: number): boolean => t0 <= deadline;

/** `TickMathTrait::degeneration`: the pips of the conditions active at `t`: −3, −4, −7. */
export function degeneration(bleeding: number, poison: number, burning: number, t: number): number {
  let pips = 0;
  if (t <= bleeding) pips -= 3;
  if (t <= poison) pips -= 4;
  if (t <= burning) pips -= 7;
  return pips;
}

/** `TickMathTrait::effect_pips`: a held effect's pips while it lasts (`t ≤ deadline`). */
export const effect_pips = (pips: number, deadline: number, t: number): number =>
  pips !== 0 && t <= deadline ? pips : 0;

/** `TickMathTrait::heal`: `health + 2 × clamp(pips, −10, 10)`, clamped to `[0, max]`. */
export function heal(health: number, pips: number, max: number): number {
  const change = HEALTH_PER_PIP * Math.min(MAX_PIPS, Math.max(-MAX_PIPS, pips));
  if (change < 0) return -change >= health ? 0 : health - -change;
  return Math.min(health + change, max);
}

/** `TickMathTrait::decay`: adrenaline less `ADRENALINE_DECAY`, floored at 0. */
export const decay = (adrenaline: number): number =>
  adrenaline < ADRENALINE_DECAY ? 0 : adrenaline - ADRENALINE_DECAY;

/**
 * `MemberTickTrait::regenerate`: step 3 at tick `t` for a member inside and alive: health by its
 * pips (its own, the degenerating conditions', its `REGENERATION` effects' while they last), energy
 * by its regeneration up to its max, adrenaline decayed out of combat.
 */
export function regenerate(member: Member, t: number, engaged: boolean): void {
  let pips = member.health_regen + degeneration(member.bleeding, member.poison, member.burning, t);
  member.effect_regen.forEach((regen, slot) => {
    pips += effect_pips(regen, member.effect_deadlines[slot]!, t);
  });
  member.health = heal(member.health, pips, member.max_health);
  member.energy = Math.min(u16add(member.energy, member.energy_regen), member.max_energy);
  if (!engaged) member.adrenaline = decay(member.adrenaline);
}

/** `MemberConditionTrait::can_act`: not knocked down at `t0`. */
export const can_act = (member: Member, t0: number): boolean => !held(member.knocked, t0);
