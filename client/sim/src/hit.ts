// One hit (design/19 §5.5 steps 1–4, §5.6; CBT-03a, D-170, D-179): the mirror of `HitTrait`
// (`contracts/logic/src/types/hit.cairo`), held equal to it by `contracts/logic/vectors/hit.jsonl`.
// From the hit's inputs to its outcome, stopped (missed, blocked, evaded) or landed with its
// damage. The fields keep the Cairo names; the reasons of each rule are the Cairo module's
// documentation.

import { exp2 } from "./exp2";
import {
  add,
  arg,
  boolFromFelt,
  boolToFelt,
  fromFelt,
  i16,
  i32,
  i8,
  mul,
  narrow,
  panic,
  u16,
  u32,
  u64,
  u8,
  variantFromFelt,
} from "./felt";
import { Arc } from "./window";

/** `combat::HitClass`, by its `Serde` index. */
export const HitClass = { Weapon: 0, Spell: 1, Item: 2, Trap: 3 } as const;
export type HitClass = (typeof HitClass)[keyof typeof HitClass];

/** `combat::weapon::AXE`. */
export const AXE = 2;
/** A critical strike: +40 %. */
export const CRITICAL_PERCENT = 40n;
/** The axe, from the rear-side and back arcs: +25 %. */
export const AXE_PERCENT = 25n;
/** Weakness on the source: −33 % to its weapon hits. */
export const WEAKNESS_PERCENT = -33n;
/** The sum of the percents is never below −100 (D-140). */
export const MIN_PERCENT = -100n;
/** Penetration is capped at 100 % (FX-9). */
export const PENETRATION_CAP = 100n;
/** The damage of one hit is clamped to [0, 65,535] (D-140). */
export const MAX_DAMAGE = 65535n;
/** `snapshot::STRENGTH_PER_RANK`: a weapon's strength is 5 × rank. */
export const STRENGTH_PER_RANK = 5n;
/** Strength of a spell and a trap: 3 × level. */
export const STRENGTH_PER_LEVEL = 3n;
/** A weapon's damage below its requirement is divided by 3. */
export const REQUIREMENT_DIVISOR = 3n;
/** The largest base of a hit. */
export const MAX_BASE = 33022n;
/** A `BLOCK`'s charges, 1…63; 0 is none held. */
export const MAX_BLOCK = 63n;
/** `exp2::SHIFT`: 16 fractional bits. */
const SHIFT = 65536n;

export const errors = {
  BASE: "hit: base above its bound",
  HEALTH: "hit: health above max",
  BLOCK: "hit: block charges",
} as const;

/** One hit and its source (`Hit`); integers as `bigint` of their Cairo type. */
export type Hit = {
  class: HitClass;
  weapon: bigint;
  melee: boolean;
  arc: Arc;
  in_front: boolean;
  strength: bigint;
  base: bigint;
  percent: bigint;
  percent_above_half: bigint;
  penetration: bigint;
  health: bigint;
  max_health: bigint;
  weakened: boolean;
  blind: boolean;
};

/** The target of a hit (`HitTarget`). */
export type HitTarget = {
  armor: bigint;
  armor_effects: bigint;
  armor_stance: bigint;
  armor_enchanted: bigint;
  in_stance: boolean;
  enchanted: boolean;
  armor_vs: bigint;
  block: bigint;
  evade: boolean;
  knocked_down: boolean;
  asleep: boolean;
  halve: boolean;
  health: bigint;
  max_health: bigint;
};

/** What a hit does (`HitOutcome`): a stopped hit, or a landed one with its damage. */
export type HitOutcome =
  | { kind: "Missed" }
  | { kind: "Blocked" }
  | { kind: "Evaded" }
  | { kind: "Landed"; damage: bigint; critical: boolean; halved: boolean };

const OUTCOMES = ["Missed", "Blocked", "Evaded", "Landed"] as const;

/** `HitAssert::assert_valid`: a breach is a bug, not a play (D-140). */
function assertValid(hit: Hit, target: HitTarget): void {
  if (hit.base > MAX_BASE) panic(errors.BASE);
  if (hit.health > hit.max_health) panic(errors.HEALTH);
  if (target.health > target.max_health) panic(errors.HEALTH);
  if (target.block > MAX_BLOCK) panic(errors.BLOCK);
}

/** The class reads the source's `DAMAGE_PERCENT` and the penetrations (weapon and spell). */
function readsPassives(hit: Hit): boolean {
  return hit.class === HitClass.Weapon || hit.class === HitClass.Spell;
}

/** Step 2 of a weapon hit (§5.6), in §5.5's order: a miss, a block, an evasion. */
function stop(hit: Hit, target: HitTarget): HitOutcome | undefined {
  if (hit.blind && !hit.in_front) return { kind: "Missed" };
  const open = !target.knocked_down;
  const front = hit.arc === Arc.Front || hit.arc === Arc.FrontSide;
  // A sleeping target can neither block (design/04) nor evade (D-179 #5, CBT-05a) its first hit.
  if (target.block > 0n && front && open && !target.asleep) return { kind: "Blocked" };
  if (target.evade && hit.melee && open && !target.asleep) return { kind: "Evaded" };
  return undefined;
}

/** Critical from the back, or on a knocked-down or sleeping target from any arc. */
function isCritical(hit: Hit, target: HitTarget): boolean {
  return hit.arc === Arc.Back || target.knocked_down || target.asleep;
}

/** Step 3: the final armor, never below 0, then the penetration (capped at 100) taken off. */
function armor(hit: Hit, target: HitTarget): bigint {
  let a = target.armor + target.armor_effects + target.armor_vs;
  if (target.in_stance) a += target.armor_stance;
  if (target.enchanted) a += target.armor_enchanted;
  if (a <= 0n) return 0n;
  a = narrow(u32, a);
  let p = 0n;
  if (readsPassives(hit)) p = hit.penetration > PENETRATION_CAP ? PENETRATION_CAP : hit.penetration;
  return a - (a * p) / 100n;
}

/** The percents that apply (§5.4), each a term of one sum (D-140 #3). */
function percents(hit: Hit, target: HitTarget, critical: boolean): bigint[] {
  const terms: bigint[] = [];
  if (readsPassives(hit)) {
    terms.push(hit.percent);
    if (hit.health * 2n > hit.max_health) terms.push(hit.percent_above_half);
  }
  if (hit.class === HitClass.Weapon) {
    if (critical) terms.push(CRITICAL_PERCENT);
    if (hit.weapon === BigInt(AXE) && (hit.arc === Arc.RearSide || hit.arc === Arc.Back)) {
      terms.push(AXE_PERCENT);
    }
    if (hit.weakened) terms.push(WEAKNESS_PERCENT);
  }
  return terms;
}

/**
 * Step 4 before FX-19: `x = strength − armor` clamped by the table, `⌊base × table(x) / 2^16⌋`,
 * then `⌊· × (100 + percent) / 100⌋` with `percent` the sum of the terms floored at −100,
 * clamped to [0, 65,535].
 */
function damage(hit: Hit, armor: bigint, terms: readonly bigint[]): bigint {
  const x = narrow(i32, hit.strength - narrow(i32, armor));
  const scaled = (hit.base * exp2(Number(x))) / SHIFT;
  const sum = terms.reduce((total, term) => total + term, 0n);
  const percent = sum < MIN_PERCENT ? MIN_PERCENT : sum;
  const multiplier = narrow(u64, 100n + percent);
  const damage = (scaled * multiplier) / 100n;
  return damage > MAX_DAMAGE ? MAX_DAMAGE : damage;
}

/**
 * FX-19: a target holding the halving unspent, brought by a weapon hit from at least 50 % to
 * below 50 %, takes half the damage, truncated.
 */
function halve(target: HitTarget, damage: bigint): [bigint, boolean] {
  if (!target.halve) return [damage, false];
  const after = damage > target.health ? 0n : target.health - damage;
  if (target.health * 2n >= target.max_health && after * 2n < target.max_health) {
    return [damage / 2n, true];
  }
  return [damage, false];
}

/** §5.5 steps 1–4 and §5.6: the outcome of the hit on the target (`HitTrait::resolve`). */
export function resolve(hit: Hit, target: HitTarget): HitOutcome {
  assertValid(hit, target);
  const weaponHit = hit.class === HitClass.Weapon;
  if (weaponHit) {
    const stopped = stop(hit, target);
    if (stopped !== undefined) return stopped;
  }
  const critical = weaponHit && isCritical(hit, target);
  let amount = damage(hit, armor(hit, target), percents(hit, target, critical));
  let halved = false;
  if (weaponHit) [amount, halved] = halve(target, amount);
  return { kind: "Landed", damage: narrow(u16, amount), critical, halved };
}

/** A weapon hit's strength: `5 × rank` (`rank: u8`), capped by `cap: u8`; a `u16`. */
export function weapon_strength(rank: bigint, cap: bigint): bigint {
  const strength = mul(u16, STRENGTH_PER_RANK, arg(u8, rank));
  return strength > arg(u8, cap) ? cap : strength;
}

/** A spell's or a trap's strength: `3 × level` (`level: u8`); a `u16`. */
export function level_strength(level: bigint): bigint {
  return mul(u16, STRENGTH_PER_LEVEL, arg(u8, level));
}

/**
 * A weapon hit's base (`damage: u8`, `bonus: u16`): the weapon's damage, divided by 3 below its
 * requirement, plus a bonus; a `u32`, at most `MAX_BASE` for the largest arguments.
 */
export function weapon_base(damage: bigint, requirement_met: boolean, bonus: bigint): bigint {
  const own = arg(u8, damage);
  return add(u32, requirement_met ? own : own / REQUIREMENT_DIVISOR, arg(u16, bonus));
}

/** The `Serde` of `(Hit, HitTarget)`: 28 felts, in the order of `hit.cairo`'s documentation. */
export function hitFromFelts(felts: readonly bigint[]): [Hit, HitTarget] {
  if (felts.length !== 28) throw new RangeError(`a hit is 28 felts, got ${felts.length}`);
  const f = (i: number): bigint => felts[i]!;
  const hit: Hit = {
    class: variantFromFelt(f(0), 4) as HitClass,
    weapon: fromFelt(u8, f(1)),
    melee: boolFromFelt(f(2)),
    arc: variantFromFelt(f(3), 4) as Arc,
    in_front: boolFromFelt(f(4)),
    strength: fromFelt(u16, f(5)),
    base: fromFelt(u32, f(6)),
    percent: fromFelt(i16, f(7)),
    percent_above_half: fromFelt(i16, f(8)),
    penetration: fromFelt(u16, f(9)),
    health: fromFelt(u16, f(10)),
    max_health: fromFelt(u16, f(11)),
    weakened: boolFromFelt(f(12)),
    blind: boolFromFelt(f(13)),
  };
  const target: HitTarget = {
    armor: fromFelt(i16, f(14)),
    armor_effects: fromFelt(u16, f(15)),
    armor_stance: fromFelt(i8, f(16)),
    armor_enchanted: fromFelt(i8, f(17)),
    in_stance: boolFromFelt(f(18)),
    enchanted: boolFromFelt(f(19)),
    armor_vs: fromFelt(u8, f(20)),
    block: fromFelt(u8, f(21)),
    evade: boolFromFelt(f(22)),
    knocked_down: boolFromFelt(f(23)),
    asleep: boolFromFelt(f(24)),
    halve: boolFromFelt(f(25)),
    health: fromFelt(u16, f(26)),
    max_health: fromFelt(u16, f(27)),
  };
  return [hit, target];
}

/** The `Serde` of `HitOutcome`: the variant, then `damage`, `critical`, `halved` when landed. */
export function outcomeToFelts(outcome: HitOutcome): bigint[] {
  const variant = BigInt(OUTCOMES.indexOf(outcome.kind));
  if (outcome.kind !== "Landed") return [variant];
  return [variant, outcome.damage, boolToFelt(outcome.critical), boolToFelt(outcome.halved)];
}
