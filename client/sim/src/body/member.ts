// A member's side of the `Body` operations (CLI-02g-C, D-257; `contracts/logic/src/models/
// member.cairo`): the snapshot fields its hits read (`MemberSnapshotTrait`), the words' fields the
// lifecycle writes (`MemberWordsTrait`: Crippled, the `hits` counter, the held effects), its
// recharges and its interrupt (`MemberTrait`, `MemberTickTrait`), the lifecycle (`MemberLifecycleTrait`:
// conditions cured, effects held, adrenaline gained) and the conditions (`MemberConditionTrait`:
// `apply`, `knock`). Each writer changes the member in place, as Cairo's `ref self`; a word is
// changed as Cairo changes it, by a felt delta in the field.

import { condition, damage, skill_kind } from "../combat";
import { line } from "../effect";
import { P, add, i32, mul, panic } from "../felt";
import { field, limbs } from "../packing";
import { type Infliction, duration } from "./infliction";
import {
  ABSENT_LANE,
  ENERGY_THIRDS,
  NO_SLOT,
  beltItem,
  delta,
  effect_lane,
  errors as wordsErrors,
  held as heldOf,
  is_alive,
  u16add,
  type Held,
  type Member,
  type Sheets,
} from "../segment/words";
import {
  assert_condition,
  cured,
  errors as tickErrors,
  flag,
  held as holds,
  min16,
  recharge_deadline,
  refreshed,
} from "../segment/tick";

const two = (bits: number): bigint => 1n << BigInt(bits);
const felt = (value: bigint): bigint => ((value % P) + P) % P;
const small = (value: bigint): number => Number(value);
const OUT = "Index out of bounds";

/** A span's element, or Cairo's panic past its end. */
function at<T>(list: readonly T[], index: number): T {
  const item = list[index];
  if (item === undefined) panic(OUT);
  return item;
}

const kitHigh = (member: Member): bigint => limbs(member.words.kit)[1];

/** `MemberSnapshotTrait::halves`: `HALVE_FIRST_HEAVY_HIT` held (`MemberKit` 202), `HALVED` not set. */
export const halves = (member: Member): boolean =>
  field(kitHigh(member), two(74), 2n) === 1n && (member.flags & flag.HALVED) === 0;

/**
 * `MemberSnapshotTrait::armor_vs`: its `ARMOR_VS` of damage type 1–9 (`MemberStats` 48 + 6 (t − 1)
 * for 1–2, 200 + 6 (t − 3) for 3–9); 0 for type 0 and past the last.
 */
export function armor_vs(member: Member, damage_type: number): number {
  if (damage_type === 0 || damage_type > damage.LAST) return 0;
  const [low, high] = limbs(member.words.stats);
  if (damage_type <= 2) return small(field(low, two(48 + 6 * (damage_type - 1)), 0x40n));
  return small(field(high, two(72 + 6 * (damage_type - 3)), 0x40n));
}

/**
 * `MemberWordsTrait::infliction`: what it adds to the conditions it inflicts (`MemberKit`:
 * `CONDITION_DURATION`'s condition 144–147 and percent 148–153, `KNOCKDOWN_FLAT` 200–201).
 */
export function infliction(member: Member): Infliction {
  const high = kitHigh(member);
  return {
    condition: small(field(high, two(16), 0x10n)),
    percent: small(field(high, two(20), 0x40n)),
    knockdown: small(field(high, two(72), 4n)),
  };
}

/** `MemberSnapshotTrait::enchant_percent`: `ENCHANT_DURATION`'s percent (`MemberKit` 154–159). */
export const enchant_percent = (member: Member): number =>
  small(field(kitHigh(member), two(26), 0x40n));

/** `MemberConditionTrait::takes_critical`: knocked down at `t0` (`t0 ≤ D`). */
export const takes_critical = (member: Member, t0: number): boolean => holds(member.knocked, t0);

// ---- The words' fields.

/** `MemberWordsTrait::crippled`: Crippled's deadline (`MemberTimers` 160–191). */
export const crippled = (member: Member): number =>
  small(field(limbs(member.words.timers)[1], two(32), two(32)));

/** `MemberWordsTrait::set_crippled`. */
export function set_crippled(member: Member, deadline: number): void {
  const timers = felt(member.words.timers + delta(crippled(member), deadline, two(160)));
  member.words = { ...member.words, timers };
}

/** `MemberWordsTrait::hits`: the `hits` counter (`MemberState` 112–119). */
export const hits = (member: Member): number =>
  small(field(limbs(member.words.state)[0], two(112), 0x100n));

/** `MemberWordsTrait::set_hits`. */
export function set_hits(member: Member, value: number): void {
  const state = felt(member.words.state + delta(hits(member), value, two(112)));
  member.words = { ...member.words, state };
}

/** `MemberWordsTrait::double_every`: `ADRENALINE_EVERY_N`'s N (`MemberKit` 160–167), 0 for none. */
export const double_every = (member: Member): number =>
  small(field(kitHigh(member), two(32), 0x100n));

/** `MemberWordsTrait::belt_item`: the potion item of belt slot 0–3. */
export const belt_item = (member: Member, slot: number): number =>
  beltItem(limbs(member.words.kit)[0], slot);

/** `MemberWordsTrait::effect_of`: the held effect of slot 0–3. */
export const effect_of = (member: Member, slot: number): Held => heldOf(member.words.effects, slot);

/** `MemberWordsTrait::set_effect`: writes `held` in slot 0–3 with its `REGENERATION` pips. */
export function set_effect(member: Member, slot: number, held: Held, pips: number): void {
  const old = effect_of(member, slot);
  const { base } = effect_lane(slot);
  const tag = (potion: boolean): number => (potion ? 1 : 0);
  const effects = felt(
    member.words.effects +
      delta(old.carrier, held.carrier, base) +
      delta(old.charges, held.charges, base * two(16)) +
      delta(tag(old.potion), tag(held.potion), base * two(23)) +
      delta(old.deadline, held.deadline, base * two(24)) +
      delta(old.rank, held.rank, base * two(52)),
  );
  member.words = { ...member.words, effects };
  const lane = Math.min(slot, 3);
  member.effect_deadlines = member.effect_deadlines.with(lane, held.deadline);
  member.effect_regen = member.effect_regen.with(lane, pips);
}

/**
 * `MemberTrait::effect_position`: effect slot `slot`'s carrier's position (`ABSENT_LANE` for an
 * empty slot). `effect_at`'s lanes 4–7 hold nothing (`serde.ts` refuses a member whose do).
 */
export function effect_position(member: Member, slot: number): number {
  if (slot >= 8) panic(OUT);
  return slot < 4 ? member.effect_at[slot]! : 0;
}

// ---- The recharges and the interrupt.

/** `MemberTrait::recharge_at`: bar slot 0–7's recharge lane; a slot above 7 is slot 7. */
function recharge_lane(slot: number): { upper: boolean; shift: bigint; base: bigint } {
  const s = Math.min(slot, 7);
  return { upper: s >= 4, shift: two(28 * (s % 4)), base: two(28 * s + (s >= 4 ? 16 : 0)) };
}

/** `MemberTrait::recharge`: the recharge deadline of bar slot 0–7. */
export function recharge(member: Member, slot: number): number {
  const [low, high] = limbs(member.words.recharges);
  const { upper, shift } = recharge_lane(slot);
  return small(field(upper ? high : low, shift, two(28)));
}

/** `MemberTrait::set_recharge`. */
export function set_recharge(member: Member, slot: number, deadline: number): void {
  const old = recharge(member, slot);
  const recharges = felt(member.words.recharges + delta(old, deadline, recharge_lane(slot).base));
  member.words = { ...member.words, recharges };
}

/** `MemberTrait::position` and `sheet`: bar slot 0–7's skill's sheet, at its position. */
const sheet = (member: Member, slot: number, sheets: Sheets) =>
  at(sheets.skills, at(member.bar_at, slot));

/** `MemberTickTrait::clear`: no activation. */
function clear(member: Member): void {
  member.act_slot = NO_SLOT;
  member.act_target = 0;
  member.act_tile = 0;
  member.act_deadline = 0;
}

/**
 * `MemberTickTrait::conclude` (CLI-02g-F): step 1 at `A`, the activation ends, its recharge counts
 * from `A` (FX-2); its slot and target, for the executor.
 */
export function conclude(member: Member, sheets: Sheets): [number, number] {
  const slot = member.act_slot;
  const address = member.act_target;
  const r = sheet(member, slot, sheets).recharge;
  set_recharge(member, slot, recharge_deadline(member.act_deadline, r));
  clear(member);
  return [slot, address];
}

/** `MemberTickTrait::interrupt`: the activation stopped at `t0`, its recharge from `t0`. */
export function interrupt(member: Member, t0: number, sheets: Sheets): void {
  if (member.act_slot === NO_SLOT) return;
  const r = sheet(member, member.act_slot, sheets).recharge;
  set_recharge(member, member.act_slot, recharge_deadline(t0, r));
  clear(member);
}

// ---- The lifecycle (design/19 §5.7, §5.12).

/** `MemberLifecycleTrait::condition`: the deadline of condition 1–5. */
export function condition_of(member: Member, c: number): number {
  assert_condition(c);
  if (c === condition.BLEEDING) return member.bleeding;
  if (c === condition.POISON) return member.poison;
  if (c === condition.BURNING) return member.burning;
  if (c === condition.CRIPPLED) return crippled(member);
  return member.knocked;
}

/** `MemberLifecycleTrait::set_condition`. */
export function set_condition(member: Member, c: number, deadline: number): void {
  if (c === condition.BLEEDING) member.bleeding = deadline;
  else if (c === condition.POISON) member.poison = deadline;
  else if (c === condition.BURNING) member.burning = deadline;
  else if (c === condition.CRIPPLED) set_crippled(member, deadline);
  else member.knocked = deadline;
}

/** `MemberLifecycleTrait::cure`: `CURE` at `t0` (`D = t0 − 1` if held), no alive check. */
export function cure(member: Member, c: number, t0: number): void {
  set_condition(member, c, cured(condition_of(member, c), t0));
}

/** `MemberAssert::assert_pips`: an effect's pips fit an `i8`. */
export function assert_pips(pips: number): void {
  if (!(pips >= -128 && pips <= 127)) panic(wordsErrors.REGEN);
}

/**
 * `MemberLifecycleTrait::put`: `held` in `slot` with its pips (a potion's sheet, a skill's line at
 * its rank) and its carrier's position `position`.
 */
export function put(
  member: Member,
  slot: number,
  held: Held,
  position: number,
  sheets: Sheets,
): void {
  let pips: number;
  if (held.potion) {
    pips = at(sheets.potions, position).regen;
  } else {
    const skill = at(sheets.skills, position);
    pips = line(skill.regen0, skill.regen12, held.rank);
  }
  assert_pips(pips);
  set_effect(member, slot, held, pips);
  // `effect_at`'s lanes are 16 bits: Cairo's sum would carry a wider position into the next lane
  if (slot >= 4 || position > ABSENT_LANE) throw new RangeError(`not mirrored: lane ${position}`);
  member.effect_at = member.effect_at.with(slot, position);
}

/**
 * `MemberLifecycleTrait::hold`: a holding effect at `t` (§5.7), `stance` if its carrier is one,
 * `position` its carrier's in the content; returns its slot. In order: its carrier held (a skill
 * by id, a potion by its belt slot's item) keeps the later deadline, the new one on a tie; else a
 * stance takes the stance's slot; else the lowest free slot; else the earliest deadline, ties the
 * lowest slot.
 */
export function hold(
  member: Member,
  held: Held,
  position: number,
  stance: boolean,
  t: number,
  sheets: Sheets,
): number {
  const item = held.potion ? belt_item(member, held.carrier) : 0;
  // 1. The same carrier
  for (let slot = 0; slot < 4; slot++) {
    const old = effect_of(member, slot);
    if (old.deadline >= t && old.potion === held.potion) {
      const same = held.potion
        ? belt_item(member, old.carrier) === item
        : old.carrier === held.carrier;
      if (same) {
        if (held.deadline >= old.deadline) put(member, slot, held, position, sheets);
        return slot;
      }
    }
  }
  // 2. A stance replaces the stance held
  if (stance) {
    for (let slot = 0; slot < 4; slot++) {
      const old = effect_of(member, slot);
      if (old.deadline >= t && !old.potion && old.carrier !== 0) {
        const there = effect_position(member, slot);
        if (there !== ABSENT_LANE && at(sheets.skills, there).kind === skill_kind.STANCE) {
          put(member, slot, held, position, sheets);
          return slot;
        }
      }
    }
  }
  // 3. The lowest free slot; 4. else the earliest deadline, ties the lowest slot
  let earliest = 0;
  let earliest_deadline = 0xffffffff;
  for (let slot = 0; slot < 4; slot++) {
    const deadline = effect_of(member, slot).deadline;
    if (deadline < t) {
      put(member, slot, held, position, sheets);
      return slot;
    }
    if (deadline < earliest_deadline) {
      earliest = slot;
      earliest_deadline = deadline;
    }
  }
  put(member, earliest, held, position, sheets);
  return earliest;
}

/** `MemberLifecycleTrait::gain_adrenaline`: quarters, capped at its cap; one at or above it keeps it. */
export function gain_adrenaline(member: Member, quarters: number): void {
  if (member.adrenaline < member.adrenaline_cap) {
    member.adrenaline = min16(u16add(member.adrenaline, quarters), member.adrenaline_cap);
  }
}

/**
 * `MemberLifecycleTrait::land_weapon_hit`: 4 quarters, 8 on every N-th hit of
 * `ADRENALINE_EVERY_N` (the `hits` counter back to 0 at N; N = 0: it stays 0).
 */
export function land_weapon_hit(member: Member): void {
  const every = double_every(member);
  let quarters = 4;
  if (every > 0) {
    const next = hits(member) + 1;
    if (next > 0xff) panic("u8_add Overflow");
    if (next === every) {
      quarters = 8;
      set_hits(member, 0);
    } else {
      set_hits(member, next);
    }
  }
  gain_adrenaline(member, quarters);
}

/** `MemberLifecycleTrait::take_hit`: 1 quarter above 0 health. */
export function take_hit(member: Member): void {
  if (member.health > 0) gain_adrenaline(member, 1);
}

// ---- The conditions (CBT-04).

/**
 * `MemberConditionTrait::apply`: condition 1–4 for the value `v` at `t0`, through the source's
 * `Infliction`, refreshed by `max`; nothing on a member not alive. Knocked down is `knock`'s: any
 * other condition panics once its duration is computed.
 */
export function apply(member: Member, c: number, v: number, source: Infliction, t0: number): void {
  if (!is_alive(member)) return;
  const d = duration(source, c, v);
  if (c === condition.BLEEDING) member.bleeding = refreshed(member.bleeding, t0, d);
  else if (c === condition.POISON) member.poison = refreshed(member.poison, t0, d);
  else if (c === condition.BURNING) member.burning = refreshed(member.burning, t0, d);
  else {
    if (c !== condition.CRIPPLED) panic(tickErrors.KNOCK);
    set_crippled(member, refreshed(crippled(member), t0, d));
  }
}

/**
 * `MemberConditionTrait::knock`: Knocked down for `v` at `t0` through the source's `Infliction`,
 * refreshed by `max`, and the activation interrupted; nothing on a member not alive.
 */
export function knock(
  member: Member,
  v: number,
  source: Infliction,
  t0: number,
  sheets: Sheets,
): void {
  if (!is_alive(member)) return;
  const d = duration(source, condition.KNOCKED_DOWN, v);
  member.knocked = refreshed(member.knocked, t0, d);
  interrupt(member, t0, sheets);
}

/** `energy + v × ENERGY_THIRDS` in `i32`, as both kinds' `energize` (its overflows panic). */
export const thirds = (energy: number, v: number): number =>
  Number(add(i32, BigInt(energy), mul(i32, BigInt(v), BigInt(ENERGY_THIRDS))));

/** `MemberBody::energize`: `v` energy in thirds, clamped to `[0, max]`. */
export function energize(member: Member, v: number): void {
  member.energy = clamp(thirds(member.energy, v), 0, member.max_energy);
}

/** `ExecutorTrait::clamp`. */
export function clamp(v: number, low: number, high: number): number {
  if (v < low) return low;
  if (v > high) return high;
  return v;
}
