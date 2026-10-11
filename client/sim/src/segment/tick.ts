// What a tick shares between its actors, as named functions each with one source (CLI-02g-B1):
// `TickMathTrait::{degeneration, effect_pips, heal, decay, held}` (`helpers/tick.cairo`),
// `MemberTickTrait::regenerate` and `MemberConditionTrait::can_act` (`models/member.cairo`), and
// `types::tick::flag` with its `KEPT`. `segment.ts`'s fast path calls them; the ticks of the other
// lots are to call the same ones.

import { u16add } from "./words";
import type { Member } from "./words";

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
