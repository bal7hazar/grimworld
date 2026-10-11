// The adventurer's action (CLI-02g-E, D-257): the mirror of `contracts/logic/src/types/
// action.cairo`'s `ActionTrait::act` (its private steps `aim`, `energy`, `glyphs`, `consume`, and
// `QuickCastTrait::count`) and of `ActionLibrary::act` (`contracts/logic/src/systems/action.cairo`),
// held equal to them by `contracts/logic/vectors/act.jsonl`. `actClass` is the class itself,
// computed: `run`'s seam (`segment/classes.ts`) takes it for `Classes.act`.
//
// The class runs `act` with `Delegate` rules: a `TRAP` carrier placed in the ground before any
// sub-world, any other carrier through `ExecutorLibrary`, which the port runs on the whole world
// (`executor.ts`'s `execute`: the sub-world is the call's cost, not its result). On a refusal the
// class returns the words as they came; only a carrier writes the ground, and every refusal comes
// before its arm's carrier (`types::action::tests::test_no_carry_before_a_refusal`).

import * as executor from "./executor";
import {
  type Actor,
  type Board,
  type Cache,
  type Carrier,
  type Executed,
  entry,
  guards,
  rank,
  target,
} from "./executor";
import { kind, line } from "./effect";
import { P, add, panic, u32 } from "./felt";
import { position as boardPosition } from "./movement";
import { field, limbs } from "./packing";
import * as m from "./body/member";
import { LAST_TICK } from "./segment";
import type { ActCall, Classes } from "./segment/classes";
import { type Action, type Ground, Illegal, type Outcome, type Target } from "./segment/serde";
import { can_act, flag, recharge_deadline } from "./segment/tick";
import {
  ABSENT_LANE,
  ENERGY_THIRDS,
  type Member,
  type Sheets,
  delta,
  is_alive,
  place,
  set_facing,
  sheets as indexed,
} from "./segment/words";
import { type World, world as load, words as store } from "./segment/world";
import { place as placeTrap, placer, spot } from "./trap";
import { facing, reach } from "./window";

/** `skill_kind`: the kinds `act` tells apart (design/19 §3.4). */
export const skill_kind = { ATTACK: 1, SPELL: 2, HEX: 3, ENCHANTMENT: 4 } as const;
/** `Profession::Warden`'s id. */
const WARDEN = 2;
/** *Fieldcraft*'s energy a primary rank takes off a Warden skill's cost (design/20 §1.3). */
export const FIELDCRAFT_PER_RANK = 1;

const two = (bits: number): bigint => 1n << BigInt(bits);
const small = (value: bigint): number => Number(value);
const felt = (value: bigint): bigint => ((value % P) + P) % P;
const OUT = "Index out of bounds";

/** A list's element, or Cairo's panic past its end. */
function at<T>(list: readonly T[], index: number): T {
  const item = list[index];
  if (item === undefined) panic(OUT);
  return item;
}

/** A copy of a member, nothing shared with the world's (Cairo's `world.member(m)`). */
const copy = (member: Member): Member => ({
  ...member,
  effect_deadlines: [...member.effect_deadlines],
  effect_regen: [...member.effect_regen],
  bar_at: [...member.bar_at],
  effect_at: [...member.effect_at],
  words: { ...member.words },
});

// ---- The member's reads and writes `act` adds (`models/member.cairo`).

/** `MemberSnapshotTrait::weapon_ticks`: its weapon's tick cost `k` (`MemberStats` 104–111), at least 1. */
export function weapon_ticks(member: Member): number {
  const k = small(field(limbs(member.words.stats)[0], two(104), 0x100n));
  return k === 0 ? 1 : k;
}

/** `MemberSnapshotTrait::primary`: its primary profession and rank (`MemberStats` 72–79, 80–87). */
export function primary(member: Member): [number, number] {
  const low = limbs(member.words.stats)[0];
  return [small(field(low, two(72), 0x100n)), small(field(low, two(80), 0x100n))];
}

/** `MemberSnapshotTrait::quick_casts`: its two pairs `(attribute, N)` (`MemberBar` 208–219, 220–231). */
export function quick_casts(member: Member): [[number, number], [number, number]] {
  const high = limbs(member.words.bar)[1];
  const pair = (bits: bigint): [number, number] => [small(bits % 0x10n), small(bits / 0x10n)];
  return [pair(field(high, two(80), 0x1000n)), pair(field(high, two(92), 0x1000n))];
}

/** `MemberSnapshotTrait::quick_cast_matches`: the pairs bar slot 0–7 counts for (`MemberStats` 168 + 2 slot, 242 + 2 (slot − 4)). */
export function quick_cast_matches(member: Member, slot: number): number {
  if (slot >= 8) panic(OUT);
  const shift = slot < 4 ? 40 + 2 * slot : 114 + 2 * (slot - 4);
  return small(field(limbs(member.words.stats)[1], two(shift), 4n));
}

/** `MemberSnapshotTrait::weapon_required`: bar slot 0–7's attack skill names another weapon (`MemberStats` 40 + slot). */
export function weapon_required(member: Member, slot: number): boolean {
  if (slot >= 8) panic(OUT);
  return field(limbs(member.words.stats)[0], two(40 + slot), 2n) !== 0n;
}

/** `MemberWordsTrait::casts`: quick-cast counter `k` (0: `MemberState` 120–127; 1: 168–175). */
export function casts(member: Member, k: number): number {
  const [low, high] = limbs(member.words.state);
  return small(k === 0 ? field(low, two(120), 0x100n) : field(high, two(40), 0x100n));
}

export function set_casts(member: Member, k: number, value: number): void {
  const shift = k === 0 ? two(120) : two(168);
  const state = felt(member.words.state + delta(casts(member, k), value, shift));
  member.words = { ...member.words, state };
}

/** `MemberWordsTrait::belt_count`: the count left in belt slot 0–3 (`MemberState` 128 + 8 slot). */
export function belt_count(member: Member, slot: number): number {
  if (slot >= 4) panic(OUT);
  return small(field(limbs(member.words.state)[1], two(8 * slot), 0x100n));
}

export function set_belt_count(member: Member, slot: number, count: number): void {
  const old = belt_count(member, slot);
  const state = felt(member.words.state + delta(old, count, two(128 + 8 * slot)));
  member.words = { ...member.words, state };
}

/** `MemberTickTrait::start`: an activation of `n` ticks started at clock `c`: `A = c + n`, `n` at least 1. */
export function start(member: Member, slot: number, address: number, n: number, c: number): void {
  member.act_slot = slot;
  member.act_target = address;
  member.act_tile = 0;
  member.act_deadline = Number(add(u32, BigInt(c), BigInt(n === 0 ? 1 : n)));
}

/** `MemberTickTrait::use_instant`: bar slot `slot`'s recharge from `t₀ = c + 1`. */
export function use_instant(member: Member, slot: number, c: number, sheets: Sheets): void {
  const r = at(sheets.skills, at(member.bar_at, slot)).recharge;
  m.set_recharge(member, slot, recharge_deadline(c + 1, r));
}

// ---- `QuickCastTrait`.

/** `QuickCastTrait::step`: one pair's counter. */
function step(count: number, n: number, matches: boolean): [number, number] {
  if (n === 0 || !matches) return [count, 0];
  return count + 1 >= n ? [0, 1] : [count + 1, 0];
}

/**
 * `QuickCastTrait::count`: a spell of activation ≥ 1 starts: each pair whose bit is set in
 * `matches` moves its counter; one at `N` gives a bonus of 1 and resets.
 */
export function count(
  counters: [number, number],
  pairs: [[number, number], [number, number]],
  matches: number,
): [[number, number], number] {
  const [c0, b0] = step(counters[0], pairs[0][1], (matches & 1) !== 0);
  const [c1, b1] = step(counters[1], pairs[1][1], (matches & 2) !== 0);
  return [[c0, c1], b0 + b1];
}

// ---- `ActionTrait`.

/** The rules `act` runs with (`Delegate`'s `Carry`): the tick's board, its cache, the ground. */
export type Rules = { board: Board; cache: Cache; ground: Ground };

/**
 * `DelegateCarry::carry`: a `TRAP` carrier placed if its guard holds and the tile can take one,
 * nothing else run; any other through the executor's class (here, on the whole world).
 */
export function carry(
  rules: Rules,
  world: World,
  sheets: Sheets,
  source: Actor,
  slot: number,
  carrier: Carrier,
  address: number,
  t: number,
): Executed {
  if (carrier.kind === "Skill") {
    const first = entry(sheets, carrier.at, 0);
    if (first.kind === kind.TRAP) {
      const unit = executor.unitOf(world, source);
      if ((guards(unit, [first]) & 1) === 0) return "Skipped";
      const by = placer(world, source, slot);
      const ground = placeTrap(
        rules.ground,
        world,
        rules.board,
        executor.tile(rules.board, address),
        by,
      );
      if (ground === undefined) return "Illegal";
      rules.ground = ground;
      return "Place";
    }
  }
  return executor.execute(rules.cache, world, sheets, rules.board, source, carrier, address, t);
}

/** `Aim`: the carrier's address and the window's position of its target. */
type Aim = { address: number; to: number };

/**
 * `ActionTrait::aim`: the carrier's address and its target's position, if the carrier addresses
 * `address` (a `FOE` a living goblin, an `ALLY` a living member, a `TILE` a tile, `SELF` the
 * source) and it is in reach; else why not.
 */
export function aim(
  world: World,
  sheets: Sheets,
  board: Board,
  source: Actor,
  from: number,
  carrier: Carrier,
  address: Target,
): Aim | Illegal {
  const [addressing, range] = executor.addressing(world, sheets, source, carrier);
  if (addressing === target.SELF) {
    return { address: source.kind === "M" ? source.i : 0, to: from };
  }
  let to: number;
  if (address.tile) {
    if (addressing !== target.TILE) return Illegal.Target;
    to = executor.tile(board, address.value);
  } else {
    if (addressing === target.TILE) return Illegal.Target;
    const actor = executor.actor(world, address.value);
    if (actor === undefined) return Illegal.Target;
    if ((actor.kind === "M") !== (addressing === target.ALLY)) return Illegal.Target;
    const [alive, position] = executor.locate(world, board, actor);
    if (!alive) return Illegal.Target;
    to = position;
  }
  if (!reach(board.open, from, to, range)) return Illegal.Reach;
  return { address: address.value, to };
}

/** `ActionTrait::is_spell`: skill kinds 2, 3, 4 (FX-25: not kind 11). */
export const is_spell = (k: number): boolean =>
  k === skill_kind.SPELL || k === skill_kind.HEX || k === skill_kind.ENCHANTMENT;

/**
 * `ActionTrait::energy`: the energy, in thirds, a skill costs: less *Fieldcraft* on a Warden's
 * Warden skill and the glyphs' `glyph`, floored at 0.
 */
export function energy(member: Member, cost: number, profession: number, glyph: number): number {
  const [first, r] = primary(member);
  const fieldcraft = first === WARDEN && profession === WARDEN ? r * FIELDCRAFT_PER_RANK : 0;
  const off = fieldcraft + glyph;
  return off >= cost ? 0 : (cost - off) * ENERGY_THIRDS;
}

/**
 * `ActionTrait::glyphs`: the `NEXT_SPELL_COST` the member's held glyphs take off a spell at clock
 * `c`, each at its rank, and the mask of their slots.
 */
export function glyphs(member: Member, sheets: Sheets, c: number): [number, number] {
  let off = 0;
  let mask = 0;
  for (let slot = 0, b = 1; slot < 4; slot++, b *= 2) {
    const position = m.effect_position(member, slot);
    const held = m.effect_of(member, slot);
    if (position !== ABSENT_LANE && !held.potion && c < held.deadline) {
      for (let k = 0; k < 3; k++) {
        const e = entry(sheets, position, k);
        if (e.kind === kind.NEXT_SPELL_COST) {
          const v = line(e.v0, e.v12, held.rank);
          if (v > 0) off += v;
          mask |= b;
        }
      }
    }
  }
  return [off, mask];
}

/** `ActionTrait::consume`: the glyphs of `mask` end now (`D = c`). */
export function consume(member: Member, mask: number, c: number): void {
  for (let rest = mask, slot = 0; rest !== 0; rest = Math.floor(rest / 2), slot++) {
    if (rest % 2 === 1) {
      const held = { ...m.effect_of(member, slot), deadline: c };
      m.set_effect(member, slot, held, at(member.effect_regen, slot));
    }
  }
}

/**
 * `ActionTrait::act`: §5.3 steps 1–4 for member `i`'s `action` at the clock `c = world.clock`: its
 * tick cost, or why it is illegal (then nothing is written).
 */
export function act(
  world: World,
  sheets: Sheets,
  rules: Rules,
  i: number,
  action: Action,
): Outcome {
  const refused = (illegal: Illegal): Outcome => ({ illegal });
  const c = world.clock;
  if (c > LAST_TICK) return refused(Illegal.Clock);
  const member = copy(at(world.members, i));
  if (!is_alive(member)) return refused(Illegal.Absent);
  const t0 = c + 1;
  if (!can_act(member, t0) && action.kind !== "wait") return refused(Illegal.Knocked);
  const board = rules.board;
  const { x, y, facing: facing0 } = place(member);
  const from = boardPosition(board, x, y);
  const source: Actor = { kind: "M", i };
  switch (action.kind) {
    case "wait":
      return { ticks: 1 };
    case "turn": {
      if ((member.flags & flag.TURNED) !== 0) return refused(Illegal.Turned);
      member.flags |= flag.TURNED;
      set_facing(member, action.direction);
      world.members[i] = member;
      return { ticks: 0 };
    }
    case "attack": {
      const weapon: Carrier = { kind: "Weapon" };
      const aimed = aim(world, sheets, board, source, from, weapon, {
        tile: false,
        value: action.entity,
      });
      if (typeof aimed === "number") return refused(aimed);
      set_facing(member, facing(from, aimed.to, facing0));
      world.members[i] = member;
      carry(rules, world, sheets, source, 0, weapon, action.entity, t0);
      return { ticks: weapon_ticks(member) };
    }
    case "skill":
      return skill(world, sheets, rules, member, source, from, facing0, action.slot, action.target);
    case "item":
      return item(world, sheets, rules, member, source, from, facing0, action.slot, action.entity);
    case "move":
    case "interact":
      return refused(Illegal.Kind);
  }
}

/** `act`'s Skill arm: legality in its order, the costs at once, facing, now or an activation. */
function skill(
  world: World,
  sheets: Sheets,
  rules: Rules,
  member: Member,
  source: Actor & { kind: "M" },
  from: number,
  facing0: number,
  slot: number,
  address: Target,
): Outcome {
  const refused = (illegal: Illegal): Outcome => ({ illegal });
  const c = world.clock;
  const position = executor.position(member, slot);
  if (position === ABSENT_LANE) return refused(Illegal.Empty);
  const sheet = at(sheets.skills, position);
  const attack = sheet.kind === skill_kind.ATTACK;
  if (attack && weapon_required(member, slot)) return refused(Illegal.Kind);
  const instant = sheet.activation === 0 && !attack;
  if (instant && (member.flags & flag.INSTANT) !== 0) return refused(Illegal.Instant);
  if (c < m.recharge(member, slot)) return refused(Illegal.Recharging);
  const adrenaline = sheet.adrenaline * 4;
  if (member.adrenaline < adrenaline) return refused(Illegal.Adrenaline);
  const spell = is_spell(sheet.kind);
  const [glyph, mask] = spell ? glyphs(member, sheets, c) : [0, 0];
  const cost = energy(member, sheet.energy, sheet.profession, glyph);
  if (member.energy < cost) return refused(Illegal.Energy);
  const carrier: Carrier = { kind: "Skill", at: position, rank: rank(member, slot) };
  const aimed = aim(world, sheets, rules.board, source, from, carrier, address);
  if (typeof aimed === "number") return refused(aimed);
  if (
    entry(sheets, position, 0).kind === kind.TRAP &&
    spot(world, rules.board, rules.ground, aimed.to) === undefined
  ) {
    return refused(Illegal.Trap);
  }
  // 2. Costs, at once
  member.energy -= cost;
  member.adrenaline -= adrenaline;
  consume(member, mask, c);
  let n = sheet.activation;
  if (spell && n >= 1) {
    const [[c0, c1], quick] = count(
      [casts(member, 0), casts(member, 1)],
      quick_casts(member),
      quick_cast_matches(member, slot),
    );
    set_casts(member, 0, c0);
    set_casts(member, 1, c1);
    n = quick >= n ? 1 : n - quick;
  }
  // 3. Facing
  set_facing(member, facing(from, aimed.to, facing0));
  // 4. Now, or an activation
  if (n === 0) {
    use_instant(member, slot, c, sheets);
    if (instant) member.flags |= flag.INSTANT;
    world.members[source.i] = member;
    carry(rules, world, sheets, source, slot, carrier, aimed.address, c + 1);
    return { ticks: attack ? weapon_ticks(member) : 0 };
  }
  start(member, slot, aimed.address, n, c);
  if (address.tile) member.act_tile = 1;
  world.members[source.i] = member;
  // `n.try_into().unwrap()`: a `u8`
  if (n > 0xff) panic("Option::unwrap failed.");
  const k = weapon_ticks(member);
  return { ticks: attack && k > n ? k : n };
}

/** `act`'s Item arm: the potion in the content, its count, its address by its entry. */
function item(
  world: World,
  sheets: Sheets,
  rules: Rules,
  member: Member,
  source: Actor & { kind: "M" },
  from: number,
  facing0: number,
  slot: number,
  value: number,
): Outcome {
  const refused = (illegal: Illegal): Outcome => ({ illegal });
  const id = m.belt_item(member, slot);
  const position = sheets.potions.findIndex((sheet) => id !== 0 && sheet.id === id);
  if (position < 0) return refused(Illegal.Empty);
  const left = belt_count(member, slot);
  if (left === 0) return refused(Illegal.Belt);
  const carrier: Carrier = { kind: "Potion", at: position, slot };
  // The item's target is an entity or a tile by its entry (ENG-01 *play*)
  const tile = executor.potion_entry(sheets, position).target === target.TILE;
  const aimed = aim(world, sheets, rules.board, source, from, carrier, { tile, value });
  if (typeof aimed === "number") return refused(aimed);
  set_belt_count(member, slot, left - 1);
  set_facing(member, facing(from, aimed.to, facing0));
  world.members[source.i] = member;
  carry(rules, world, sheets, source, slot, carrier, aimed.address, world.clock + 1);
  return { ticks: 1 };
}

/**
 * `ActionLibrary::act`, the class: the words loaded through the content, `act` for member 0 with
 * `Delegate`'s rules and a fresh `Cache`; the words stored back, or the words as they came on a
 * refusal, the ground the rules hold. Its inputs are not changed.
 */
export const actClass: Classes["act"] = (call: ActCall) => {
  const sheets = indexed(call.content);
  const world = load(call.words, sheets);
  const rules: Rules = { board: call.board, cache: executor.cache(), ground: call.ground };
  const outcome = act(world, sheets, rules, 0, call.action);
  const words = "illegal" in outcome ? call.words : store(world);
  return { words, ground: rules.ground, outcome };
};
