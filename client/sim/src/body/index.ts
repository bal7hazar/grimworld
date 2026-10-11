// The `Body` operations (CLI-02g-C, D-257; `contracts/logic/src/types/executor.cairo`'s `Body`
// trait, its `MemberBody` and `GoblinBody` impls, and `UnitBody`, the executor's dispatch, CBT-05a
// route (c)): an actor of either kind, one type, each operation dispatching to the kind's own. The
// writers change the unit's actor in place, as Cairo's `ref self: Unit`; a caller that keeps its
// input passes a copy (`copyUnit`). `defence` and `offence` come with `act` (RV-03b).

import { condition } from "../combat";
import { panic, sub, u32 } from "../felt";
import * as goblinModel from "../segment/goblin";
import type { Goblin } from "../segment/goblin";
import { ai, flag } from "../segment/tick";
import {
  ABSENT,
  ABSENT_LANE,
  is_alive,
  place as memberPlace,
  type Held,
  type Member,
  type Sheets,
} from "../segment/words";
import * as g from "./goblin";
import { type Infliction, NONE } from "./infliction";
import * as m from "./member";

export type { Infliction };

/** `executor::Unit`: a member or a goblin. */
export type Unit = { kind: "M"; member: Member } | { kind: "G"; goblin: Goblin };

/** A deep copy of a unit, for a caller that keeps its input (Cairo's values are copies). */
export function copyUnit(unit: Unit): Unit {
  if (unit.kind === "G") return { kind: "G", goblin: { ...unit.goblin } };
  const member = unit.member;
  return {
    kind: "M",
    member: {
      ...member,
      effect_deadlines: [...member.effect_deadlines],
      effect_regen: [...member.effect_regen],
      bar_at: [...member.bar_at],
      effect_at: [...member.effect_at],
      words: { ...member.words },
    },
  };
}

const pick = <T>(unit: Unit, onMember: (member: Member) => T, onGoblin: (goblin: Goblin) => T): T =>
  unit.kind === "M" ? onMember(unit.member) : onGoblin(unit.goblin);

export const health = (unit: Unit): number =>
  pick(
    unit,
    (x) => x.health,
    (x) => x.health,
  );

export const max_health = (unit: Unit): number =>
  pick(
    unit,
    (x) => x.max_health,
    (x) => x.max_health,
  );

/** Alive: a member inside above 0 health; a goblin neither dead nor looted, above 0 health. */
export const alive = (unit: Unit): boolean =>
  pick(unit, is_alive, (x) => goblinModel.is_alive(x) && x.health > 0);

export const is_member = (unit: Unit): boolean => unit.kind === "M";

/** Its tile and facing. */
export const place = (unit: Unit): { x: number; y: number; facing: number } =>
  pick(unit, memberPlace, goblinModel.place);

/** Knocked down at `t` (a weapon hit on it is critical from any arc). */
export const knocked = (unit: Unit, t: number): boolean =>
  pick(
    unit,
    (x) => m.takes_critical(x, t),
    (x) => g.takes_critical(x, t),
  );

/** A goblin asleep; a member never. */
export const asleep = (unit: Unit): boolean =>
  pick(
    unit,
    () => false,
    (x) => x.ai === ai.ASLEEP,
  );

/** It halves the first heavy hit (a member's kit, not yet spent); a goblin never. */
export const halves = (unit: Unit): boolean => pick(unit, m.halves, () => false);

/** Its armor against damage type `damage_type`. */
export const armor_vs = (unit: Unit, damage_type: number, sheets: Sheets): number =>
  pick(
    unit,
    (x) => m.armor_vs(x, damage_type),
    (x) => g.armor_vs(x, damage_type, sheets),
  );

/** What it adds to the conditions it inflicts; a goblin none. */
export const infliction = (unit: Unit): Infliction => pick(unit, m.infliction, () => NONE);

/** `ENCHANT_DURATION`'s percent; a goblin 0. */
export const enchant_percent = (unit: Unit): number => pick(unit, m.enchant_percent, () => 0);

/** Its effect slots: 4 for a member, 1 for a goblin. */
export const slots = (unit: Unit): number => (unit.kind === "M" ? 4 : 1);

/** Effect slot `slot` and its carrier's position (`ABSENT` for none); a goblin's one slot. */
export function effect(unit: Unit, slot: number): { held: Held; at: number } {
  if (unit.kind === "G") {
    return { held: goblinModel.effect_of(unit.goblin), at: unit.goblin.effect_at };
  }
  const position = m.effect_position(unit.member, slot);
  return {
    held: m.effect_of(unit.member, slot),
    at: position === ABSENT_LANE ? ABSENT : position,
  };
}

/** `damage` taken, floored at 0 (no alive check). */
export function wound(unit: Unit, damage: number): void {
  const actor = unit.kind === "M" ? unit.member : unit.goblin;
  actor.health = damage >= actor.health ? 0 : actor.health - damage;
}

/** `v` health, up to its max; nothing on an actor not alive (a goblin: alive and above 0). */
export function heal(unit: Unit, v: number): void {
  if (unit.kind === "M") {
    if (!is_alive(unit.member)) return;
  } else if (!goblinModel.is_alive(unit.goblin) || unit.goblin.health === 0) {
    return;
  }
  const actor = unit.kind === "M" ? unit.member : unit.goblin;
  const next = actor.health + v;
  actor.health = next > actor.max_health ? actor.max_health : next;
}

/** `v` energy, in thirds, clamped to `[0, max]`. */
export function energize(unit: Unit, v: number, sheets: Sheets): void {
  if (unit.kind === "M") {
    m.energize(unit.member, v);
    return;
  }
  const goblin = unit.goblin;
  const max = goblinModel.max_energy(goblin, sheets);
  goblin.energy = m.clamp(m.thirds(goblin.energy, v), 0, max);
}

/** Hit: a member's `HIT` flag and 1 quarter; a goblin's quarter, and asleep or on watch it engages. */
export function struck(unit: Unit, sheets: Sheets): void {
  if (unit.kind === "M") {
    unit.member.flags |= flag.HIT;
    m.take_hit(unit.member);
    return;
  }
  const goblin = unit.goblin;
  g.take_hit(goblin, sheets);
  // §5.5 step 9: a goblin hit while asleep or on watch notices (D-179)
  if (goblin.health > 0 && (goblin.ai === ai.ASLEEP || goblin.ai === ai.WATCH)) {
    goblin.ai = ai.ENGAGED;
  }
}

/** A weapon hit landed: its adrenaline. */
export function landed(unit: Unit, sheets: Sheets): void {
  if (unit.kind === "M") m.land_weapon_hit(unit.member);
  else g.land_weapon_hit(unit.goblin, sheets);
}

/** A heavy hit halved: a member's `HALVED` flag; a goblin nothing. */
export function halved(unit: Unit): void {
  if (unit.kind === "M") unit.member.flags |= flag.HALVED;
}

/** Condition 1–5 for the value `v` at `t` through the source's `Infliction`: Knocked down knocks. */
export function inflict(
  unit: Unit,
  c: number,
  v: number,
  source: Infliction,
  t: number,
  sheets: Sheets,
): void {
  if (unit.kind === "M") {
    if (c === condition.KNOCKED_DOWN) m.knock(unit.member, v, source, t, sheets);
    else m.apply(unit.member, c, v, source, t);
  } else if (c === condition.KNOCKED_DOWN) {
    g.knock(unit.goblin, v, source, t, sheets);
  } else {
    g.apply(unit.goblin, c, v, source, t);
  }
}

/** `CURE` of condition `c` at `t`: never on a member at 0 or down, nor on a dead goblin. */
export function cure(unit: Unit, c: number, t: number): void {
  if (unit.kind === "M") {
    if (is_alive(unit.member)) m.cure(unit.member, c, t);
  } else {
    g.cure(unit.goblin, c, t);
  }
}

/** A holding effect through §5.7, its carrier at `position`; a goblin never holds a potion's. */
export function hold(
  unit: Unit,
  held: Held,
  position: number,
  stance: boolean,
  t: number,
  sheets: Sheets,
): void {
  if (unit.kind === "M") {
    if (is_alive(unit.member)) m.hold(unit.member, held, position, stance, t, sheets);
  } else if (!held.potion) {
    g.hold(unit.goblin, held, position, t, sheets);
  }
}

/** One charge of slot `slot` spent at `t`; at 0 the effect ends (`D = t − 1`). */
export function spend(unit: Unit, slot: number, t: number): void {
  const held =
    unit.kind === "M" ? m.effect_of(unit.member, slot) : goblinModel.effect_of(unit.goblin);
  if (held.charges === 0) return;
  const next = { ...held, charges: held.charges - 1 };
  if (next.charges === 0) next.deadline = Number(sub(u32, BigInt(t), 1n));
  if (unit.kind === "M") {
    const pips = unit.member.effect_regen[slot];
    if (pips === undefined) panic("Index out of bounds");
    m.set_effect(unit.member, slot, next, pips);
  } else {
    goblinModel.set_effect(unit.goblin, next, unit.goblin.effect_regen);
  }
}
