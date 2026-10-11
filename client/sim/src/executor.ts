// The executor (CLI-02g-D, CLI-02g-E, D-257): the mirror of what `contracts/logic/src/types/
// executor.cairo`'s `ExecutorTrait` runs for a trap's trigger (`trigger`) and for the action
// phase's carrier (`execute`), held equal to it by `contracts/logic/vectors/trap.jsonl` and
// `act.jsonl`. A carrier's entries (`read`), their guards (`guards`), each entry's `Op` (`ops`,
// `hold`), its hit modifiers (`modifiers`), the target sets (`actors`), the source's terms
// (`offence`, `penetration`, `attack`), the hit (`strike`, `resolve`, through `hit.ts`), the other
// entries in entry order (`apply`), each actor written back (`put`). The defence a hit reads
// (`DefenceTrait`, `holding`) is read through `Levered`'s cache, as the classes do (`TrapLibrary`
// and `ExecutorLibrary` run `Levered`); a carrier's awake goblins are gathered into one write of
// the awake set (`pending`, `flush`), a trap's one entrant is written at once (`Naive`'s).
//
// Not here: `Delegate`'s sub-world (the goblins a carrier can reach, `wide`, `subcontent`) is the
// call's cost, not its result: the port runs the carrier on the whole world. `conclude` and
// `legal` (an activation's end) are the ticks' (lot F). The fields keep the Cairo names; the
// reasons of each rule are the Cairo module's.

import * as body from "./body";
import type { Unit } from "./body";
import * as m from "./body/member";
import { type Infliction, effective_duration } from "./body/infliction";
import { skill_kind } from "./combat";
import { type Entry, duration, is_hit_modifier, is_holding, kind, unpack, value } from "./effect";
import { add, arg, mul, panic, u16, u32 } from "./felt";
import {
  HitClass,
  MAX_BLOCK,
  type HitOutcome,
  level_strength,
  resolve as hit,
  weapon_base,
  weapon_strength,
} from "./hit";
import { position as boardPosition } from "./movement";
import { field, limbs } from "./packing";
import * as goblinModel from "./segment/goblin";
import type { Goblin } from "./segment/goblin";
import type { Board } from "./segment/serde";
import { ai } from "./segment/tick";
import {
  ABSENT,
  ABSENT_LANE,
  type Held,
  type Member,
  type Sheets,
  is_alive,
  place as memberPlace,
} from "./segment/words";
import type { World } from "./segment/world";
import { from16, from8 } from "./signed";
import { Arc, FAR, arc, front, inside, range, shape, shapes } from "./window";

export type { Board };

/** `types::FIRST_GOBLIN`: entities below it are members 0–7. */
export const FIRST_GOBLIN = 8;
/** `types::MAX_CLOCK`: the deadline of a charge-only effect (§3.4). */
export const MAX_CLOCK = 0xfffffff;
/** A value's bounds at play (design/19 §6). */
const MAX_VALUE = 32767;
const MAX_ENERGY_VALUE = 255;
const MAX_PERCENT = 100;
const MAX_ARMOR_EFFECT = 255;
/** The bit of an actor's membership mask for the carrier's hit; entries 1–3 are bits 1, 2, 4. */
const HIT_BIT = 8;

/** `types::effect::target`: what an entry addresses. */
export const target = { SELF: 0, FOE: 1, ALLY: 2, TILE: 3 } as const;
/** `types::effect::filter`: the actors of a set. */
export const filter = { FOES: 0, ALLIES: 1 } as const;
/** `types::effect::scope`: the hits a `PENETRATION` effect applies to. */
export const scope = { WEAPON: 0, ATTACK_SKILL: 1, SPELL: 2, ALL: 3 } as const;

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

/** Cairo's `==` on two actors. */
export const same = (a: Actor, b: Actor): boolean => a.kind === b.kind && a.i === b.i;

/** `Carrier`: a weapon attack, a skill at its position and rank, a potion at its position and belt slot. */
export type Carrier =
  | { kind: "Weapon" }
  | { kind: "Skill"; at: number; rank: number }
  | { kind: "Potion"; at: number; slot: number };

/** `Executed`: what an execution did. */
export type Executed = "Ran" | "Place" | "Skipped" | "Illegal";

/** `world::Pending`: the awake goblins a carrier wrote, by index, for one write of the awake set. */
export type Pending = [number, Goblin][];

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
export const potion_entry = (sheets: Sheets, position: number): Entry =>
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

/**
 * `MemberSnapshotTrait::weapon`: its class (`MemberStats` 88–95), damage (96–103), range
 * (112–119), strength (120–127), damage type (160–167), requirement met (176–183).
 */
export function weapon(member: Member): {
  weapon: number;
  damage: number;
  range: number;
  strength: number;
  damage_type: number;
  met: boolean;
} {
  const [low, high] = limbs(member.words.stats);
  return {
    weapon: small(field(low, two(88), 0x100n)),
    damage: small(field(low, two(96), 0x100n)),
    range: small(field(low, two(112), 0x100n)),
    strength: small(low / two(120)),
    damage_type: small(field(high, two(32), 0x100n)),
    met: field(high, two(48), 0x100n) !== 0n,
  };
}

/** `MemberSnapshotTrait::on_hit`: `LIFE_STEAL_ON_HIT` and `ENERGY_ON_HIT` (`MemberKit` 128–143). */
export function on_hit(member: Member): { steal: number; energy: number } {
  const high = limbs(member.words.kit)[1];
  return { steal: small(high % 0x100n), energy: small(field(high, two(8), 0x100n)) };
}

/**
 * `MemberSnapshotTrait::passives`: its `DAMAGE_PERCENT` sums of class `s` (0 plain weapon, 1
 * attack skill, 2 spell), unguarded and `ABOVE_HALF`, and its `PENETRATION` sum of the class
 * (`MemberBar` 136 + 8 (3 g + s), 184 + 8 s).
 */
export function passives(
  member: Member,
  s: number,
): { percent: number; above: number; sum: number } {
  const high = limbs(member.words.bar)[1];
  const shift = at([two(8), two(16), two(24)], s);
  return {
    percent: from8(field(high, shift, 0x100n)),
    above: from8(field(high, shift * two(24), 0x100n)),
    sum: small(field(high, shift * two(48), 0x100n)),
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

/** `ExecutorTrait::actor`, under a name a parameter of `actors` does not hide. */
const actorOf = (world: World, entity: number): Actor | undefined => actor(world, entity);

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
 * `ExecutorTrait::put`: a member written back; a goblin at 0 health still alive killed
 * (`ai::DEAD`, in `killed`), then, with `Levered`'s lever (`pending`), gathered for its carrier's
 * one write of the awake set if it is awake and in it, else written at once (`Naive`'s, and a
 * trap's one entrant).
 */
export function put(world: World, actor: Actor, unit: Unit, pending?: Pending): void {
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
  // `world.position(i)`: in the awake set, as the world holds it now
  if (pending !== undefined && goblin.awake && at(world.goblins, actor.i).awake) {
    pending.push([actor.i, goblin]);
    return;
  }
  at(world.goblins, actor.i);
  world.goblins[actor.i] = goblin;
}

/** `WorldTrait::flush` of `ExecutorTrait::sorted`: the pending writes, by ascending index. */
export function flush(world: World, pending: Pending): void {
  for (const [i, goblin] of [...pending].sort(([a], [b]) => a - b)) world.goblins[i] = goblin;
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

// ---- The action phase's carrier (CLI-02g-E): `execute` and what it runs.

/** `BoardTrait::tile`: the window's position of a location's tile `x + 256 y`. */
export const tile = (board: Board, t: number): number =>
  boardPosition(board, t % 256, Math.floor(t / 256));

/**
 * `ExecutorTrait::locate`: whether the actor is alive (a member inside above 0, a goblin not dead
 * and above 0) and its position in the window.
 */
export function locate(world: World, board: Board, actor: Actor): [boolean, number] {
  if (actor.kind === "M") {
    const member = at(world.members, actor.i);
    const { x, y } = memberPlace(member);
    return [is_alive(member), boardPosition(board, x, y)];
  }
  const goblin = at(world.goblins, actor.i);
  const { x, y } = goblinModel.place(goblin);
  return [goblinModel.is_alive(goblin) && goblin.health > 0, boardPosition(board, x, y)];
}

/** `ExecutorTrait::weapon_range`: the range of the source's weapon. */
export function weapon_range(world: World, sheets: Sheets, source: Actor): number {
  if (source.kind === "M") return weapon(at(world.members, source.i)).range;
  return at(sheets.castes, at(world.goblins, source.i).caste_at).weapon_range;
}

/**
 * `ExecutorTrait::addressing`: what `carrier` addresses (its first entry's target, an attack's
 * foe) and the reach its target must be in (the skill's range, an attack's: the weapon's).
 */
export function addressing(
  world: World,
  sheets: Sheets,
  source: Actor,
  carrier: Carrier,
): [number, number] {
  if (carrier.kind === "Weapon") return [target.FOE, weapon_range(world, sheets, source)];
  if (carrier.kind === "Skill") {
    const sheet = at(sheets.skills, carrier.at);
    if (sheet.kind === skill_kind.ATTACK) return [target.FOE, weapon_range(world, sheets, source)];
    return [entry(sheets, carrier.at, 0).target, sheet.range];
  }
  return [potion_entry(sheets, carrier.at).target, at(sheets.potions, carrier.at).range];
}

/** `WindowTrait::near`: a shape of radius 1 at most on `centre`, its walkable tiles; else none. */
export function near(open: bigint, s: number, centre: number): bigint {
  if (!inside(centre)) return 0n;
  if (s === shapes.SINGLE || s === shapes.RING_1 || s === shapes.DISC_1) {
    return shape(open, s, centre);
  }
  return 0n;
}

/**
 * `ExecutorTrait::read`: the carrier's entries up to the first empty, what they apply with, and
 * whether it has an implicit weapon hit (a weapon attack, an attack skill).
 */
export function read(
  sheets: Sheets,
  source: Unit,
  carrier: Carrier,
  t: number,
): { entries: Entry[]; context: Context; weapon: boolean } {
  const infliction = body.infliction(source);
  const enchant = body.enchant_percent(source);
  const base = { infliction, enchant, t };
  if (carrier.kind === "Weapon") {
    const context = {
      ...base,
      rank: 0,
      skill_kind: 0,
      carrier: 0,
      potion: false,
      at: ABSENT,
      scope: 0,
    };
    return { entries: [], context, weapon: true };
  }
  if (carrier.kind === "Skill") {
    const sheet = at(sheets.skills, carrier.at);
    const entries: Entry[] = [];
    for (let k = 0; k < 3; k++) {
      const e = entry(sheets, carrier.at, k);
      if (e.kind === kind.EMPTY) break;
      entries.push(e);
    }
    const attack = sheet.kind === skill_kind.ATTACK;
    const context = {
      ...base,
      rank: carrier.rank,
      skill_kind: sheet.kind,
      carrier: sheet.id,
      potion: false,
      at: carrier.at,
      scope: attack ? 1 : 2,
    };
    return { entries, context, weapon: attack };
  }
  const e = potion_entry(sheets, carrier.at);
  const context = {
    ...base,
    rank: 0,
    skill_kind: 0,
    carrier: carrier.slot,
    potion: true,
    at: carrier.at,
    scope: 3,
  };
  return { entries: e.kind === kind.EMPTY ? [] : [e], context, weapon: false };
}

/**
 * `ExecutorTrait::modifiers`: the hit modifiers whose guard held, `ATTACK_BONUS` (0…32,767, the
 * last one's) and `HIT_PENETRATION` (each 0…100, summed).
 */
export function modifiers(
  entries: readonly Entry[],
  held: number,
  rank: number,
): { bonus: number; penetration: number } {
  let bonus = 0;
  let penetration = 0;
  let b = 1;
  for (const e of entries) {
    if ((held & b) !== 0) {
      if (e.kind === kind.ATTACK_BONUS) bonus = clamp(value(e, rank), 0, MAX_VALUE);
      else if (e.kind === kind.HIT_PENETRATION) {
        penetration = Number(
          add(u16, BigInt(penetration), BigInt(clamp(value(e, rank), 0, MAX_PERCENT))),
        );
      }
    }
    b *= 2;
  }
  return { bonus, penetration };
}

/**
 * `ExecutorTrait::penetration`: the source's `PENETRATION` effects held at `t` that apply to the
 * hit's class `cls` (0 a plain weapon hit, 1 an attack skill's, 2 a spell, 3 none), each 0…100.
 */
export function penetration(source: Unit, cls: number, t: number, sheets: Sheets): number {
  if (cls === 3) return 0;
  let sum = 0;
  for (let slot = 0; slot < body.slots(source); slot++) {
    const { held, at: position } = body.effect(source, slot);
    if (held.deadline >= t && position !== ABSENT) {
      const e = holding(sheets, held.potion, position);
      if (e.kind === kind.PENETRATION) {
        const s = e.scope;
        const applies =
          s === scope.ALL ||
          (cls === 2 && s === scope.SPELL) ||
          (cls < 2 && s === scope.WEAPON) ||
          (cls === 1 && s === scope.ATTACK_SKILL);
        if (applies) {
          sum = Number(add(u16, BigInt(sum), BigInt(clamp(value(e, held.rank), 0, MAX_PERCENT))));
        }
      }
    }
  }
  return sum;
}

/**
 * `Body::offence`: a carrier's source terms of its hit. A member's: its passives of the context's
 * scope, its held penetration and the carrier's; a weapon hit its weapon's, any other `spell`'s
 * at `3 × level` (a bomb at the potion's strength). A goblin's: its caste's weapon at `5 × rank`,
 * no passives.
 */
export function offence(
  source: Unit,
  cls: HitClass,
  e: Entry,
  bonus: number,
  carried: number,
  context: Context,
  sheets: Sheets,
): Offence {
  const u16add = (a: number, b: number): number => Number(add(u16, BigInt(a), BigInt(b)));
  const held = penetration(source, context.scope, context.t, sheets);
  // `bonus.try_into().unwrap()`: a `u16`
  const extra = (): bigint => arg(u16, BigInt(bonus));
  if (source.kind === "G") {
    const goblin = source.goblin;
    const caste = at(sheets.castes, goblin.caste_at);
    const pen = u16add(held, carried);
    if (cls === HitClass.Weapon) {
      return {
        class: cls,
        weapon: caste.weapon,
        melee: caste.weapon_range === range.TOUCH,
        strength: Number(weapon_strength(BigInt(caste.rank), 255n)),
        base: Number(weapon_base(BigInt(caste.weapon_damage), true, extra())),
        percent: 0,
        above: 0,
        penetration: pen,
        damage_type: caste.damage_type,
        steal: 0,
        energy: 0,
      };
    }
    const strength = Number(level_strength(BigInt(goblinModel.level(goblin))));
    return spell(cls, strength, e, 0, 0, pen, context);
  }
  const member = source.member;
  const s = context.scope;
  const { percent, above, sum } = s < 3 ? passives(member, s) : { percent: 0, above: 0, sum: 0 };
  const pen = u16add(u16add(sum, held), carried);
  if (cls === HitClass.Weapon) {
    const w = weapon(member);
    const { steal, energy } = on_hit(member);
    return {
      class: cls,
      weapon: w.weapon,
      melee: w.range === range.TOUCH,
      strength: w.strength,
      base: Number(weapon_base(BigInt(w.damage), w.met, extra())),
      percent,
      above,
      penetration: pen,
      damage_type: w.damage_type,
      steal,
      energy,
    };
  }
  const strength =
    cls === HitClass.Item
      ? at(sheets.potions, context.at).strength
      : Number(level_strength(BigInt(level(member))));
  return spell(cls, strength, e, percent, above, pen, context);
}

/** `Body::defence` through `UnitBody`, the `Levered` lever's: a member's by its index, cached. */
export const defence = defenceOf;

/** `OnAttack`: the source's `ON_ATTACK_CONDITION`s held, the slots holding charges, its infliction. */
export type OnAttack = { conditions: [number, number][]; charged: number; infliction: Infliction };

/** `ExecutorTrait::attack`: the source's `ON_ATTACK_CONDITION`s held at `t`, gathered once a carrier. */
export function attack(source: Unit, t: number, sheets: Sheets): OnAttack {
  const conditions: [number, number][] = [];
  let charged = 0;
  for (let slot = 0; slot < body.slots(source); slot++) {
    const { held, at: position } = body.effect(source, slot);
    if (held.deadline >= t && position !== ABSENT) {
      const e = holding(sheets, held.potion, position);
      if (e.kind === kind.ON_ATTACK_CONDITION) {
        conditions.push([e.param, value(e, held.rank)]);
        if (held.charges > 0) charged += bit(slot);
      }
    }
  }
  return { conditions, charged, infliction: body.infliction(source) };
}

/** `Gain`: what the source gains from one actor's turn. */
export type Gain = { landed: boolean; stolen: number };

/**
 * `ExecutorTrait::on`: one actor other than the source: the hit first, if its set holds it and its
 * guard held; stopped, nothing else; landed by a weapon, the source's `ON_ATTACK_CONDITION`s and
 * its life steal; then the other entries. Returns what the source gains.
 */
export function on(
  c: Cache,
  unit: Unit,
  actor: Actor,
  shot: Shot,
  onAttack: OnAttack,
  health: number,
  max_health: number,
  list: readonly Op[],
  bits: number,
  held: number,
  context: Context,
  sheets: Sheets,
): Gain {
  const gain: Gain = { landed: false, stolen: 0 };
  if (shot.hit) {
    const t = context.t;
    if (!strike(c, unit, actor, shot, health, max_health, t, sheets)) return gain;
    if (shot.offence.class === HitClass.Weapon) {
      gain.landed = true;
      for (const [condition, v] of onAttack.conditions) {
        if (body.alive(unit)) body.inflict(unit, condition, v, onAttack.infliction, t, sheets);
      }
      const steal = shot.offence.steal;
      if (steal > 0 && body.alive(unit)) {
        const stolen = Math.min(steal, body.health(unit));
        body.wound(unit, stolen);
        gain.stolen += stolen;
      }
    }
  }
  apply(c, unit, actor, list, bits, held, context, sheets);
  return gain;
}

/** One actor of a carrier's sets: its position, itself, the bits of the sets that hold it. */
export type Listed = [number, Actor, number];

/**
 * `ExecutorTrait::actors`: every set taken now (its entry's shape on its centre, clipped to the
 * window, the actors its filter takes, alive; the source never in its own hit's set), and the
 * actors of their union, ascending position. A carrier whose entries are all `SINGLE` and none
 * `TILE` reads its source and the addressed entity alone; any other scans the world.
 */
export function actors(
  world: World,
  board: Board,
  source: Unit,
  actor: Actor,
  source_at: number,
  entries: readonly Entry[],
  damage: number | undefined,
  address: number,
): Listed[] {
  let addressed: Actor | undefined;
  let addressed_at = FAR;
  let addressed_alive = false;
  let wide = false;
  let targets_entity = damage === 3;
  for (const e of entries) {
    if (e.target === target.FOE || e.target === target.ALLY) targets_entity = true;
    if (e.shape !== shapes.SINGLE || e.target === target.TILE) wide = true;
  }
  if (targets_entity) {
    const a = actorOf(world, address);
    if (a !== undefined) {
      [addressed_alive, addressed_at] = locate(world, board, a);
      addressed = a;
    }
  }
  const tile_at = tile(board, address);
  const sets: [bigint, number, number][] = [];
  let union = 0n;
  entries.forEach((e, k) => {
    if (e.kind !== kind.TRAP && !is_hit_modifier(e)) {
      const centre =
        e.target === target.SELF ? source_at : e.target === target.TILE ? tile_at : addressed_at;
      const mask = near(board.open, e.shape, centre);
      sets.push([mask, e.filter, e.kind === kind.DAMAGE ? HIT_BIT : bit(k)]);
      union |= mask;
    }
  });
  if (damage === 3) {
    const mask = near(board.open, shapes.SINGLE, addressed_at);
    sets.push([mask, filter.FOES, HIT_BIT]);
    union |= mask;
  }
  const member_source = body.is_member(source);
  const candidates: [number, Actor, boolean][] = [];
  if (wide) {
    world.members.forEach((member, i) => {
      if (is_alive(member)) {
        const { x, y } = memberPlace(member);
        candidates.push([boardPosition(board, x, y), { kind: "M", i }, true]);
      }
    });
    world.goblins.forEach((goblin, i) => {
      if (goblinModel.is_alive(goblin)) {
        const { x, y } = goblinModel.place(goblin);
        candidates.push([boardPosition(board, x, y), { kind: "G", i }, false]);
      }
    });
  } else {
    if (body.alive(source)) candidates.push([source_at, actor, member_source]);
    if (addressed !== undefined && !same(addressed, actor) && addressed_alive) {
      candidates.push([addressed_at, addressed, addressed.kind === "M"]);
    }
  }
  const has = (mask: bigint, p: number): boolean => ((mask >> BigInt(p)) & 1n) === 1n;
  const found: Listed[] = [];
  for (const [p, candidate, is_member] of candidates) {
    if (p >= FAR || !has(union, p)) continue;
    const foe = is_member !== member_source;
    let bits = 0;
    for (const [mask, set_filter, b] of sets) {
      const takes = set_filter === filter.FOES ? foe : !foe;
      const own_hit = b === HIT_BIT && same(candidate, actor);
      if (takes && !own_hit && has(mask, p)) bits |= b;
    }
    if (bits !== 0) found.push([p, candidate, bits]);
  }
  return ascending(found);
}

/** `ExecutorTrait::ascending`: `list` in ascending position, a selection as Cairo's. */
export function ascending(list: readonly Listed[]): Listed[] {
  const sorted: Listed[] = [];
  let last = 0;
  let first = true;
  for (let n = 0; n < list.length; n++) {
    let least = 0x100;
    let pick = 0;
    list.forEach(([p], i) => {
      if ((first || p > last) && p < least) {
        least = p;
        pick = i;
      }
    });
    sorted.push(at(list, pick));
    last = least;
    first = false;
  }
  return sorted;
}

/**
 * `ExecutorTrait::run`: §5.14 for the source, held apart from the world until the carrier ends:
 * the guards once, a `TRAP` carrier placed (or skipped), the hit modifiers, the target sets, the
 * source's terms, each actor in order, the source's side of a landed weapon hit. The awake goblins
 * it changed are gathered into `pending`.
 */
export function run(
  c: Cache,
  world: World,
  sheets: Sheets,
  board: Board,
  source: Unit,
  actor: Actor,
  carrier: Carrier,
  address: number,
  t: number,
  pending: Pending,
): Executed {
  const { entries, context, weapon: weapon_hit } = read(sheets, source, carrier, t);
  const held = guards(source, entries);
  const list = ops(entries, context);
  if (entries.length > 0 && entries[0]!.kind === kind.TRAP) {
    return (held & 1) === 1 ? "Place" : "Skipped";
  }
  const { bonus, penetration: carried } = modifiers(entries, held, context.rank);
  let damage: number | undefined = weapon_hit ? 3 : undefined;
  entries.forEach((e, k) => {
    if (e.kind === kind.DAMAGE) damage = k;
  });
  let hit_held = false;
  let cls: HitClass = HitClass.Spell;
  let hit_entry = unpack(0n);
  if (damage === 3) {
    hit_held = true;
    cls = HitClass.Weapon;
  } else if (damage !== undefined) {
    cls = context.scope === 2 ? HitClass.Spell : HitClass.Item;
    hit_held = (held & bit(damage)) !== 0;
    hit_entry = at(entries, damage);
  }
  const { x, y, facing: source_facing } = body.place(source);
  const source_at = boardPosition(board, x, y);
  const list_of = actors(world, board, source, actor, source_at, entries, damage, address);
  const terms =
    damage !== undefined
      ? offence(source, cls, hit_entry, bonus, carried, context, sheets)
      : spell(cls, 0, hit_entry, 0, 0, 0, context);
  const onAttack: OnAttack =
    cls === HitClass.Weapon
      ? attack(source, t, sheets)
      : { conditions: [], charged: 0, infliction: context.infliction };
  const health = body.health(source);
  const max_health = body.max_health(source);
  let gain: Gain = { landed: false, stolen: 0 };
  for (const [p, target_actor, bits] of list_of) {
    if (same(target_actor, actor)) {
      apply(c, source, actor, list, bits, held, context, sheets);
      continue;
    }
    const shot: Shot = {
      hit: (bits & HIT_BIT) !== 0 && hit_held,
      offence: terms,
      source_at,
      source_facing,
      target_at: p,
    };
    const unit = unitOf(world, target_actor);
    const got = on(
      c,
      unit,
      target_actor,
      shot,
      onAttack,
      health,
      max_health,
      list,
      bits,
      held,
      context,
      sheets,
    );
    gain = {
      landed: gain.landed || got.landed,
      stolen: Number(add(u16, BigInt(gain.stolen), BigInt(got.stolen))),
    };
    put(world, target_actor, unit, pending);
  }
  if (gain.landed) {
    let charged = onAttack.charged;
    for (let slot = 0; charged !== 0; slot++) {
      if (charged % 2 === 1) body.spend(source, slot, t);
      charged = Math.floor(charged / 2);
    }
    body.landed(source, sheets);
    if (terms.energy > 0) body.energize(source, terms.energy, sheets);
  }
  body.heal(source, gain.stolen);
  return "Ran";
}

/**
 * `ExecutorTrait::execute`: runs `carrier` of `source` on `address` (an entity, or a location's
 * tile `x + 256 y` for a `TILE` carrier) at `t`, then writes the source back with the awake
 * goblins it changed (a goblin source joins their one write if it is awake).
 */
export function execute(
  c: Cache,
  world: World,
  sheets: Sheets,
  board: Board,
  source: Actor,
  carrier: Carrier,
  address: number,
  t: number,
): Executed {
  const unit = unitOf(world, source);
  const pending: Pending = [];
  const executed = run(c, world, sheets, board, unit, source, carrier, address, t, pending);
  if (unit.kind === "M") {
    flush(world, pending);
    if (source.kind === "M") world.members[source.i] = unit.member;
    return executed;
  }
  if (source.kind !== "G") panic(errors.ADDRESS);
  if (unit.goblin.awake && at(world.goblins, source.i).awake) pending.push([source.i, unit.goblin]);
  else world.goblins[source.i] = unit.goblin;
  flush(world, pending);
  return executed;
}
