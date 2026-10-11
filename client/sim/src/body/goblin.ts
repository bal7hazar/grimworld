// A goblin's side of the `Body` operations (CLI-02g-C, D-257; `contracts/logic/src/models/
// goblin.cairo`): its interrupt (`GoblinTickTrait`), the lifecycle (`GoblinLifecycleTrait`: a dead
// goblin takes nothing, its one slot refreshed by its carrier or replaced, its gains capped at its
// caste's cap) and the conditions (`GoblinConditionTrait`: `apply`, `knock`). Its words' fields are
// `segment/goblin.ts`'. Each writer changes the goblin in place, as Cairo's `ref self`.

import { activation, condition } from "../combat";
import { line } from "../effect";
import { panic } from "../felt";
import { type Infliction, duration } from "./infliction";
import {
  assert_pips,
  crippled,
  effect_of,
  is_alive,
  set_crippled,
  set_effect,
  set_recharge,
  type Goblin,
} from "../segment/goblin";
import {
  assert_condition,
  cured,
  errors as tickErrors,
  held as holds,
  min16,
  recharge_deadline,
  refreshed,
} from "../segment/tick";
import type { Held, Sheets } from "../segment/words";

const OUT = "Index out of bounds";

/** A span's element, or Cairo's panic past its end. */
function at<T>(list: readonly T[], index: number): T {
  const item = list[index];
  if (item === undefined) panic(OUT);
  return item;
}

/** `GoblinConditionTrait::takes_critical`: knocked down at `t0` (`t0 ≤ D`). */
export const takes_critical = (goblin: Goblin, t0: number): boolean => holds(goblin.knocked, t0);

/** `CasteSheetTrait::armor_vs`: its caste's armor against damage type 1–9 (6 bits a type); 0 else. */
export function armor_vs(goblin: Goblin, damage_type: number, sheets: Sheets): number {
  if (damage_type === 0 || damage_type > 9) return 0;
  const vs = at(sheets.castes, goblin.caste_at).armor_vs;
  return Number((vs / (1n << BigInt(6 * (damage_type - 1)))) % 0x40n);
}

/** `GoblinTickTrait::clear`: no activation. */
function clear(goblin: Goblin): void {
  goblin.act_slot = activation.NONE;
  goblin.act_target = 0;
  goblin.act_deadline = 0;
}

/**
 * `GoblinTickTrait::interrupt`: the activation stopped at `t0`, its recharge from `t0`; nothing
 * unless activating (a recovery is not an activation).
 */
export function interrupt(goblin: Goblin, t0: number, sheets: Sheets): void {
  const slot = goblin.act_slot;
  if (slot > activation.LAST_SLOT) return;
  // `Sheets::caste_skill`: the kit's position of the slot's skill, then its sheet
  const r = at(sheets.skills, at(at(sheets.kits, goblin.caste_at).skills, slot)).recharge;
  set_recharge(goblin, slot, recharge_deadline(t0, r));
  clear(goblin);
}

/** `GoblinLifecycleTrait::condition`: the deadline of condition 1–5. */
export function condition_of(goblin: Goblin, c: number): number {
  assert_condition(c);
  if (c === condition.BLEEDING) return goblin.bleeding;
  if (c === condition.POISON) return goblin.poison;
  if (c === condition.BURNING) return goblin.burning;
  if (c === condition.CRIPPLED) return crippled(goblin);
  return goblin.knocked;
}

/** `GoblinLifecycleTrait::set_condition`. */
export function set_condition(goblin: Goblin, c: number, deadline: number): void {
  if (c === condition.BLEEDING) goblin.bleeding = deadline;
  else if (c === condition.POISON) goblin.poison = deadline;
  else if (c === condition.BURNING) goblin.burning = deadline;
  else if (c === condition.CRIPPLED) set_crippled(goblin, deadline);
  else goblin.knocked = deadline;
}

/** `GoblinLifecycleTrait::cure`: `CURE` at `t0` (`D = t0 − 1` if held); a dead goblin, nothing. */
export function cure(goblin: Goblin, c: number, t0: number): void {
  if (!is_alive(goblin)) return;
  set_condition(goblin, c, cured(condition_of(goblin, c), t0));
}

/**
 * `GoblinLifecycleTrait::hold`: a holding effect on its one slot at `t`: the same carrier held keeps
 * the later deadline, the new one on a tie; anything else replaces it. A dead goblin, nothing.
 */
export function hold(
  goblin: Goblin,
  held: Held,
  position: number,
  t: number,
  sheets: Sheets,
): void {
  if (!is_alive(goblin)) return;
  const old = effect_of(goblin);
  if (old.deadline >= t && old.carrier === held.carrier && held.deadline < old.deadline) return;
  const skill = at(sheets.skills, position);
  const pips = line(skill.regen0, skill.regen12, held.rank);
  assert_pips(pips);
  set_effect(goblin, held, pips);
  goblin.effect_at = position;
}

/** `GoblinLifecycleTrait::gain_adrenaline`: quarters, capped at its caste's cap. */
export function gain_adrenaline(goblin: Goblin, quarters: number, sheets: Sheets): void {
  const cap = at(sheets.kits, goblin.caste_at).cap;
  if (goblin.adrenaline < cap) goblin.adrenaline = min16(goblin.adrenaline + quarters, cap);
}

/** `GoblinLifecycleTrait::land_weapon_hit`: 4 quarters. */
export const land_weapon_hit = (goblin: Goblin, sheets: Sheets): void =>
  gain_adrenaline(goblin, 4, sheets);

/** `GoblinLifecycleTrait::take_hit`: 1 quarter, alive and above 0 health. */
export function take_hit(goblin: Goblin, sheets: Sheets): void {
  if (is_alive(goblin) && goblin.health > 0) gain_adrenaline(goblin, 1, sheets);
}

/**
 * `GoblinConditionTrait::apply`: condition 1–4 for the value `v` at `t0`, through the source's
 * `Infliction`, refreshed by `max`; a dead goblin takes nothing. Any other condition panics once
 * its duration is computed.
 */
export function apply(goblin: Goblin, c: number, v: number, source: Infliction, t0: number): void {
  if (!is_alive(goblin)) return;
  const d = duration(source, c, v);
  if (c === condition.BLEEDING) goblin.bleeding = refreshed(goblin.bleeding, t0, d);
  else if (c === condition.POISON) goblin.poison = refreshed(goblin.poison, t0, d);
  else if (c === condition.BURNING) goblin.burning = refreshed(goblin.burning, t0, d);
  else {
    if (c !== condition.CRIPPLED) panic(tickErrors.KNOCK);
    set_crippled(goblin, refreshed(crippled(goblin), t0, d));
  }
}

/**
 * `GoblinConditionTrait::knock`: Knocked down for `v` at `t0`, refreshed by `max`, and the
 * activation interrupted (a recovery kept); a dead goblin takes nothing.
 */
export function knock(
  goblin: Goblin,
  v: number,
  source: Infliction,
  t0: number,
  sheets: Sheets,
): void {
  if (!is_alive(goblin)) return;
  const d = duration(source, condition.KNOCKED_DOWN, v);
  goblin.knocked = refreshed(goblin.knocked, t0, d);
  interrupt(goblin, t0, sheets);
}
