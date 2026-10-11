// The executor's trap path (CLI-02g-D, D-257): the mirror of what `contracts/logic/src/types/
// executor.cairo`'s `ExecutorTrait::trigger` runs, held equal to it by `contracts/logic/vectors/
// trap.jsonl`. A trap's payload on its one entrant: the guards (`guards`), each entry's `Op`
// (`ops`, `hold`), the hit (`trap`, `strike`, `resolve`, through `hit.ts`) never blocked or evaded
// and with no arc, the other entries in entry order (`entries`), the entrant written back (`put`).
// The defence a hit reads (`DefenceTrait`, `holding`) is read through `Levered`'s cache, as the
// class does (`TrapLibrary` runs `Levered` with a fresh `Cache`).
//
// Not here, for `act` (lot E, RV-03b): a carrier's `read`, `modifiers`, `penetration`, `on`,
// `attack`, the actor sets (`actors`) and a source's `offence`; the trap path reaches none of them.
// `strike`'s `Blocked` branch and `resolve`'s weapon arc are ported whole, but only a weapon hit
// reaches them. The fields keep the Cairo names; the reasons of each rule are the Cairo module's.

import * as body from "./body";
import type { Unit } from "./body";
import * as m from "./body/member";
import { type Infliction, effective_duration } from "./body/infliction";
import { skill_kind } from "./combat";
import { type Entry, duration, is_holding, kind, unpack, value } from "./effect";
import { add, mul, panic, u32 } from "./felt";
import { HitClass, MAX_BLOCK, type HitOutcome, level_strength, resolve as hit } from "./hit";
import { field, limbs } from "./packing";
import * as goblinModel from "./segment/goblin";
import type { Goblin } from "./segment/goblin";
import type { Board } from "./segment/serde";
import { ai } from "./segment/tick";
import { ABSENT, ABSENT_LANE, type Held, type Member, type Sheets } from "./segment/words";
import type { World } from "./segment/world";
import { from16, from8 } from "./signed";
import { Arc, FAR, arc, front } from "./window";

export type { Board };

/** `types::FIRST_GOBLIN`: entities below it are members 0–7. */
export const FIRST_GOBLIN = 8;
/** `types::MAX_CLOCK`: the deadline of a charge-only effect (§3.4). */
export const MAX_CLOCK = 0xfffffff;
/** A value's bounds at play (design/19 §6). */
const MAX_VALUE = 32767;
const MAX_ENERGY_VALUE = 255;
const MAX_ARMOR_EFFECT = 255;

export const errors = {
  ADDRESS: "executor: no such actor",
} as const;

const two = (bits: number): bigint => 1n << BigInt(bits);
const small = (value: bigint): number => Number(value);
const OUT = "Index out of bounds";

/** A list's element, or Cairo's panic past its end. */
function at<T>(list: readonly T[], index: number): T {
  const item = list[index];
  if (item === undefined) panic(OUT);
  return item;
}

/** `world::Actor`: member `i` or goblin `i` of the world. */
export type Actor = { kind: "M"; i: number } | { kind: "G"; i: number };

/** `Defence`: what a hit reads of its target that changes only with a held effect (§5.5 step 3). */
export type Defence = {
  armor: number;
  effects: number;
  stance: number;
  enchanted: number;
  in_stance: boolean;
  is_enchanted: boolean;
  block: number;
  block_slot: number;
  evade: boolean;
};

/** `Cache`: the member's defence kept for the tick (L3), and the hits counted. */
export type Cache = { defence: Defence; member: number; at: number; hits: number; hits_at: number };

const noDefence = (): Defence => ({
  armor: 0,
  effects: 0,
  stance: 0,
  enchanted: 0,
  in_stance: false,
  is_enchanted: false,
  block: 0,
  block_slot: 0,
  evade: false,
});

/** A fresh `Cache` (`Default::default()`). */
export const cache = (): Cache => ({ defence: noDefence(), member: 0, at: 0, hits: 0, hits_at: 0 });

/** `Offence`: a carrier's source terms of its hit (§5.4). */
export type Offence = {
  class: HitClass;
  weapon: number;
  melee: boolean;
  strength: number;
  base: number;
  percent: number;
  above: number;
  penetration: number;
  damage_type: number;
  steal: number;
  energy: number;
};

/** `Context`: what a carrier's entries apply with. */
export type Context = {
  rank: number;
  infliction: Infliction;
  enchant: number;
  skill_kind: number;
  carrier: number;
  potion: boolean;
  at: number;
  scope: number;
  t: number;
};

/** `Shot`: one hit's geometry and source terms. */
export type Shot = {
  hit: boolean;
  offence: Offence;
  source_at: number;
  source_facing: number;
  target_at: number;
};

/** `Op`: one entry other than the hit, ready to apply; kind 0 for one that applies nothing. */
export type Op = { kind: number; param: number; v: number; held: Held; stance: boolean };

/** `Struck`: what a hit reads of its target, read once. */
export type Struck = {
  defence: Defence;
  facing: number;
  armor_vs: number;
  knocked: boolean;
  asleep: boolean;
  halves: boolean;
  health: number;
  max_health: number;
};

// ---- `Levered`, the lever the classes run (SPK-15's L3).

/** `LeveredLevers::entry`: entry `k` of the skill at `at`, decoded once into the sheets. */
export const entry = (sheets: Sheets, position: number, k: number): Entry =>
  at(sheets.entries, Number(mul(u32, 3n, BigInt(position))) + k);

/** `LeveredLevers::potion_entry`. */
const potion_entry = (sheets: Sheets, position: number): Entry =>
  at(sheets.potion_entries, position);

/** `LeveredLevers::defence`: member `index`'s defence at `t`, kept while `at == t + 1`. */
function leveredDefence(c: Cache, member: Member, index: number, t: number, sheets: Sheets) {
  if (c.at === t + 1 && c.member === index) return c.defence;
  const defence = memberDefence(member, t, sheets);
  c.defence = defence;
  c.member = index;
  c.at = t + 1;
  return defence;
}

/** `LeveredLevers::spent`: a block's charge spent by the cached member. */
function spent(c: Cache, index: number): void {
  if (c.member === index && c.at !== 0) c.defence = { ...c.defence, block: c.defence.block - 1 };
}

/** `LeveredLevers::held`: an effect held on the cached member: read it again. */
function heldOn(c: Cache, index: number): void {
  if (c.member === index) c.at = 0;
}

// ---- The member's reads the executor adds to lot C's.

/** `MemberSnapshotTrait::position`: bar slot 0–7's skill position (`ABSENT_LANE` for none). */
export const position = (member: Member, slot: number): number => at(member.bar_at, slot);

/** `MemberSnapshotTrait::rank`: bar slot 0–7's rank (`MemberStats` 128 + 4 slot). */
export function rank(member: Member, slot: number): number {
  if (slot >= 8) panic(OUT);
  return small(field(limbs(member.words.stats)[1], two(4 * slot), 0x10n));
}

/** `MemberSnapshotTrait::level` (`MemberStats` 64–71). */
export const level = (member: Member): number =>
  small(field(limbs(member.words.stats)[0], two(64), 0x100n));

/** `MemberSnapshotTrait::armor`: its unguarded armor, its stance and enchanted sums (F-20). */
export function armor(member: Member): { armor: number; stance: number; enchanted: number } {
  const bar = limbs(member.words.bar)[1];
  const kit = limbs(member.words.kit)[1];
  return {
    armor: from16(field(bar, two(104), two(16))),
    stance: from8(field(kit, two(56), two(8))),
    enchanted: from8(field(kit, two(64), two(8))),
  };
}

// ---- `DefenceTrait`.

/** `DefenceTrait::member`: its armor terms, each held effect's holding entry, its stance. */
export function memberDefence(member: Member, t: number, sheets: Sheets): Defence {
  const { armor: a, stance, enchanted } = armor(member);
  const defence = { ...noDefence(), armor: a, stance, enchanted };
  for (let slot = 0; slot < 4; slot++) {
    const held = m.effect_of(member, slot);
    const position = m.effect_position(member, slot);
    if (held.deadline >= t && position !== ABSENT_LANE) {
      addHeld(defence, held, position, slot, sheets);
    }
  }
  return defence;
}

/** `DefenceTrait::goblin`: its caste's armor and its one held effect. */
export function goblinDefence(goblin: Goblin, t: number, sheets: Sheets): Defence {
  const defence = { ...noDefence(), armor: at(sheets.castes, goblin.caste_at).armor };
  const held = goblinModel.effect_of(goblin);
  if (held.deadline >= t && goblin.effect_at !== ABSENT) {
    addHeld(defence, held, goblin.effect_at, 0, sheets);
  }
  return defence;
}

/** `DefenceTrait::add`: one held effect's `ARMOR`, `BLOCK`, `EVADE`, and its carrier's kind. */
function addHeld(
  defence: Defence,
  held: Held,
  position: number,
  slot: number,
  sheets: Sheets,
): void {
  const e = holding(sheets, held.potion, position);
  if (e.kind === kind.ARMOR) {
    defence.effects += clamp(value(e, held.rank), 0, MAX_ARMOR_EFFECT);
  } else if (e.kind === kind.BLOCK) {
    if (defence.block === 0 && held.charges > 0) {
      defence.block = held.charges;
      defence.block_slot = slot;
    }
  } else if (e.kind === kind.EVADE) {
    defence.evade = true;
  }
  if (!held.potion) {
    const k = at(sheets.skills, position).kind;
    if (k === skill_kind.STANCE) defence.in_stance = true;
    else if (k === skill_kind.ENCHANTMENT) defence.is_enchanted = true;
  }
}

/** `ExecutorTrait::holding`: the holding entry of a held effect's carrier; the empty entry if none. */
export function holding(sheets: Sheets, potion: boolean, position: number): Entry {
  if (potion) return potion_entry(sheets, position);
  for (let k = 0; k < 3; k++) {
    const e = entry(sheets, position, k);
    if (e.kind === kind.EMPTY) break;
    if (is_holding(e)) return e;
  }
  return unpack(0n);
}

/** `Body::defence`: a member's through the cache, by its index; a goblin's read now. */
function defenceOf(c: Cache, unit: Unit, actor: Actor, t: number, sheets: Sheets): Defence {
  if (unit.kind === "G") return goblinDefence(unit.goblin, t, sheets);
  if (actor.kind !== "M") panic(errors.ADDRESS);
  return leveredDefence(c, unit.member, actor.i, t, sheets);
}

// ---- `ExecutorTrait`.

/** `ExecutorTrait::actor`: member 0–7 the world holds, or the goblin of entity `entity`. */
export function actor(world: World, entity: number): Actor | undefined {
  if (entity < FIRST_GOBLIN) {
    return entity < world.members.length ? { kind: "M", i: entity } : undefined;
  }
  const i = find(world, entity);
  return i === undefined ? undefined : { kind: "G", i };
}

/** `WorldTrait::find`: the goblin of entity `entity`, by a binary search of the world's goblins. */
export function find(world: World, entity: number): number | undefined {
  let low = 0;
  let high = world.goblins.length;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    const found = world.goblins[middle]!.entity;
    if (found === entity) return middle;
    if (found < entity) low = middle + 1;
    else high = middle;
  }
  return undefined;
}

/** The unit of `actor` in the world, a copy (Cairo's `world.member(i)`, `world.goblin(i)`). */
export function unitOf(world: World, actor: Actor): Unit {
  if (actor.kind === "M") return body.copyUnit({ kind: "M", member: at(world.members, actor.i) });
  return { kind: "G", goblin: { ...at(world.goblins, actor.i) } };
}

/**
 * `ExecutorTrait::put` with `Naive`'s lever (a trap's one entrant is no carrier's rebuild): a
 * member written back; a goblin at 0 health still alive killed (`ai::DEAD`, in `killed`), written.
 */
export function put(world: World, actor: Actor, unit: Unit): void {
  if (unit.kind === "M") {
    if (actor.kind === "M") {
      at(world.members, actor.i);
      world.members[actor.i] = unit.member;
    }
    return;
  }
  if (actor.kind !== "G") panic(errors.ADDRESS);
  const goblin = unit.goblin;
  if (goblinModel.is_alive(goblin) && goblin.health === 0) {
    goblin.ai = ai.DEAD;
    world.killed.push(goblin.entity);
  }
  at(world.goblins, actor.i);
  world.goblins[actor.i] = goblin;
}

/** `ExecutorTrait::bit`: entry `k`'s bit. */
const bit = (k: number): number => at([1, 2, 4, 8], k);

/**
 * `ExecutorTrait::trigger`: the payload at `payload` (its entries up to the first empty) on the
 * entrant alone, class `TRAP`, at strength `3 × level`, with the guards `held` and the source's
 * `infliction`: the hit, then the other entries if the entrant is alive; the entrant written back.
 */
export function trigger(
  c: Cache,
  world: World,
  sheets: Sheets,
  payload: number,
  rank: number,
  level: number,
  held: number,
  infliction: Infliction,
  entrant: Actor,
  t: number,
): void {
  const sheet = at(sheets.skills, payload);
  const entries: Entry[] = [];
  for (let k = 0; k < 3; k++) {
    const e = entry(sheets, payload, k);
    if (e.kind === kind.EMPTY) break;
    entries.push(e);
  }
  const context: Context = {
    rank,
    infliction,
    enchant: 0,
    skill_kind: sheet.kind,
    carrier: sheet.id,
    potion: false,
    at: payload,
    scope: 3,
    t,
  };
  // Every entry's set is the entrant; the hit is the `DAMAGE` entry's
  let bits = 0;
  let damage: Entry | undefined;
  entries.forEach((e, k) => {
    if (e.kind === kind.DAMAGE) {
      if ((held & bit(k)) !== 0) damage = e;
    } else {
      bits += bit(k);
    }
  });
  const list = ops(entries, context);
  const strength = Number(level_strength(BigInt(level)));
  const unit = unitOf(world, entrant);
  if (trap(c, unit, entrant, damage, strength, context, sheets)) {
    apply(c, unit, entrant, list, bits, held, context, sheets);
  }
  put(world, entrant, unit);
}

/** `ExecutorTrait::trap`: the payload's hit, if any, on the target; whether it is alive after. */
export function trap(
  c: Cache,
  target: Unit,
  actor: Actor,
  damage: Entry | undefined,
  strength: number,
  context: Context,
  sheets: Sheets,
): boolean {
  if (damage !== undefined) {
    const offence = spell(HitClass.Trap, strength, damage, 0, 0, 0, context);
    const shot: Shot = { hit: true, offence, source_at: FAR, source_facing: 0, target_at: FAR };
    strike(c, target, actor, shot, 0, 0, context.t, sheets);
  }
  return body.alive(target);
}

/**
 * `ExecutorTrait::strike`: the target read once into a view, the hit resolved on it, its outcome
 * written back (a block's charge spent; a landed hit's wound, halving and `struck`); whether it
 * landed.
 */
export function strike(
  c: Cache,
  target: Unit,
  actor: Actor,
  shot: Shot,
  health: number,
  max_health: number,
  t: number,
  sheets: Sheets,
): boolean {
  const defence = defenceOf(c, target, actor, t, sheets);
  const view: Struck = {
    defence,
    facing: body.place(target).facing,
    armor_vs: body.armor_vs(target, shot.offence.damage_type, sheets),
    knocked: body.knocked(target, t),
    asleep: body.asleep(target),
    halves: body.halves(target),
    health: body.health(target),
    max_health: body.max_health(target),
  };
  const outcome = resolve(c, shot, view, health, max_health, t);
  if (outcome.kind === "Blocked") {
    body.spend(target, defence.block_slot, t);
    if (actor.kind === "M") spent(c, actor.i);
    return false;
  }
  if (outcome.kind === "Landed") {
    body.wound(target, Number(outcome.damage));
    if (outcome.halved) body.halved(target);
    body.struck(target, sheets);
    return true;
  }
  return false;
}

/** `ExecutorTrait::resolve`: the hit on a target's view (CBT-03a's `resolve`); the hit counted. */
export function resolve(
  c: Cache,
  shot: Shot,
  view: Struck,
  health: number,
  max_health: number,
  t: number,
): HitOutcome {
  const offence = shot.offence;
  const defence = view.defence;
  const weapon = offence.class === HitClass.Weapon;
  let side: Arc = Arc.Front;
  let in_front = false;
  if (weapon) {
    side = arc(shot.source_at, shot.target_at, view.facing) ?? Arc.Front;
    in_front = front(shot.source_at, shot.target_at, shot.source_facing);
  }
  const block = BigInt(defence.block) > MAX_BLOCK ? MAX_BLOCK : BigInt(defence.block);
  if (c.hits_at !== t + 1) {
    c.hits = 0;
    c.hits_at = t + 1;
  }
  c.hits += 1;
  return hit(
    {
      class: offence.class,
      weapon: BigInt(offence.weapon),
      melee: offence.melee,
      arc: side,
      in_front,
      strength: BigInt(offence.strength),
      base: BigInt(offence.base),
      percent: BigInt(offence.percent),
      percent_above_half: BigInt(offence.above),
      penetration: BigInt(offence.penetration),
      health: BigInt(health),
      max_health: BigInt(max_health),
      weakened: false,
      blind: false,
    },
    {
      armor: BigInt(defence.armor),
      armor_effects: BigInt(defence.effects),
      armor_stance: BigInt(defence.stance),
      armor_enchanted: BigInt(defence.enchanted),
      in_stance: defence.in_stance,
      enchanted: defence.is_enchanted,
      armor_vs: BigInt(view.armor_vs),
      block,
      evade: defence.evade,
      knocked_down: view.knocked,
      asleep: view.asleep,
      halve: weapon && view.halves,
      health: BigInt(view.health),
      max_health: BigInt(view.max_health),
    },
  );
}

/**
 * `ExecutorTrait::entries`: the entries other than the hit on `target`, in entry order, those
 * whose set holds it (`bits`) and whose guard held (`held`), while it is alive.
 */
export function apply(
  c: Cache,
  target: Unit,
  actor: Actor,
  list: readonly Op[],
  bits: number,
  held: number,
  context: Context,
  sheets: Sheets,
): void {
  const t = context.t;
  let b = 1;
  for (const op of list) {
    if ((bits & held & b) !== 0 && op.kind !== kind.EMPTY) {
      if (!body.alive(target)) break;
      if (op.kind === kind.HEAL) {
        body.heal(target, op.v);
      } else if (op.kind === kind.CONDITION) {
        body.inflict(target, op.param, op.v, context.infliction, t, sheets);
      } else if (op.kind === kind.CURE) {
        body.cure(target, op.param, t);
      } else if (op.kind === kind.ENERGY) {
        body.energize(target, op.v, sheets);
      } else {
        body.hold(target, op.held, context.at, op.stance, t, sheets);
        if (actor.kind === "M") heldOn(c, actor.i);
      }
    }
    b *= 2;
  }
}

const NO_HELD: Held = { carrier: 0, charges: 0, potion: false, deadline: 0, rank: 0 };
const nothing = (): Op => ({ kind: kind.EMPTY, param: 0, v: 0, held: NO_HELD, stance: false });

/** `ExecutorTrait::ops`: each entry's `Op`, its value clamped to its kind's bounds. */
export function ops(entries: readonly Entry[], context: Context): Op[] {
  const r = context.rank;
  return entries.map((e): Op => {
    if (e.kind === kind.HEAL) {
      return { ...nothing(), kind: e.kind, v: clamp(value(e, r), 0, MAX_VALUE) };
    }
    if (e.kind === kind.CONDITION) {
      return { ...nothing(), kind: e.kind, param: e.param, v: value(e, r) };
    }
    if (e.kind === kind.CURE) return { ...nothing(), kind: e.kind, param: e.param };
    if (e.kind === kind.ENERGY) {
      return {
        ...nothing(),
        kind: e.kind,
        v: clamp(value(e, r), -MAX_ENERGY_VALUE, MAX_ENERGY_VALUE),
      };
    }
    if (is_holding(e)) {
      const held = hold(e, context);
      if (held === undefined) return nothing();
      return {
        ...nothing(),
        kind: e.kind,
        held,
        stance: context.skill_kind === skill_kind.STANCE,
      };
    }
    return nothing();
  });
}

/**
 * `ExecutorTrait::hold`: a holding entry's `Held`, its deadline `t + d − 1` (an enchantment's `d`
 * through `ENCHANT_DURATION`), or `MAX_CLOCK` for a charge-only effect; none for one that does not
 * stay.
 */
export function hold(e: Entry, context: Context): Held | undefined {
  const t = context.t;
  let d = duration(e, context.rank);
  if (context.skill_kind === skill_kind.ENCHANTMENT && d > 0) {
    d = effective_duration(d, context.enchant, 0);
  }
  const block = e.kind === kind.BLOCK;
  const charges = block ? clamp(value(e, context.rank), 1, Number(MAX_BLOCK)) : e.charges;
  let deadline: number;
  if (d > 0) deadline = Number(add(u32, BigInt(t), BigInt(d))) - 1;
  else if (charges > 0 && !block) deadline = MAX_CLOCK;
  else return undefined;
  return {
    carrier: context.carrier,
    potion: context.potion,
    charges,
    deadline,
    rank: context.rank,
  };
}

/**
 * `ExecutorTrait::guards`: bit `k` set if entry `k`'s guard holds for the source now: `ALWAYS`, or
 * `BELOW_HALF` under half its max health.
 */
export function guards(source: Unit, entries: readonly Entry[]): number {
  const health = body.health(source);
  const max = body.max_health(source);
  let held = 0;
  let b = 1;
  for (const e of entries) {
    if (e.guard === guard.ALWAYS || (e.guard === guard.BELOW_HALF && health * 2 < max)) held += b;
    b *= 2;
  }
  return held;
}

/** `types::effect::guard`: the guards the MVP's entries carry. */
export const guard = { ALWAYS: 0, BELOW_HALF: 2 } as const;

/** `ExecutorTrait::spell`: the source terms of a hit that is not a weapon's. */
export function spell(
  cls: HitClass,
  strength: number,
  e: Entry,
  percent: number,
  above: number,
  penetration: number,
  context: Context,
): Offence {
  return {
    class: cls,
    weapon: 0,
    melee: false,
    strength,
    base: clamp(value(e, context.rank), 0, MAX_VALUE),
    percent,
    above,
    penetration,
    damage_type: e.param,
    steal: 0,
    energy: 0,
  };
}

/** `ExecutorTrait::clamp`. */
export const clamp = (v: number, low: number, high: number): number =>
  v < low ? low : v > high ? high : v;
