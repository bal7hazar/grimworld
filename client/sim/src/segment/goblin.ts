// A goblin in a world tick (CLI-02g-B1; `contracts/logic/src/models/goblin.cairo`): its stored
// words and its view inside a call (`models::index::GoblinWords`, `Goblin`). Its load, which reads
// the hot fields once and derives what it needs from its caste and level, and which refuses what
// Cairo refuses, **fail closed**: a caste or a caste skill the content does not hold, a
// regeneration above an `i8`, a max health above a `u16` (`GoblinTrait::load`, `GoblinAssert`); its
// store, which writes the hot fields back as deltas (`GoblinTrait`); the fields read and written
// in the words directly (`GoblinWordsTrait`, `GoblinPlaceTrait`). The activation's rules
// (`GoblinTickTrait`) and the lifecycle's (`GoblinLifecycleTrait`) wait for RV-03's oracle (Lot B).
// The offsets are ENG-01's frozen ones, the Cairo module's documentation; a field is read with
// `packing.ts` and a word is changed as Cairo changes it, by a delta in the field.

import { P, arg, div, i8, mul, narrow, panic, u16, u32, u8 } from "../felt";
import { field, limbs, peel } from "../packing";
import {
  ABSENT,
  DEAD,
  MISSING,
  casteAt,
  delta,
  errors as tickErrors,
  line,
  skillAt,
  type GoblinWords,
  type Held,
  type Sheets,
} from "./words";

export type { GoblinWords };

/** `GoblinTrait`'s errors (`models::goblin::errors`); `NO_SKILL` and `NO_CASTE` are `words.ts`'. */
export const errors = {
  REGEN: "goblin: regeneration above i8",
} as const;

/** A caste's health regeneration is stored as its pips + 10 (`REGEN_OFFSET`). */
const REGEN_OFFSET = 10;

const two = (bits: number): bigint => 1n << BigInt(bits);
const felt = (value: bigint): bigint => ((value % P) + P) % P;
const small = (value: bigint): number => Number(value);

/** A goblin inside the call (`models::index::Goblin`): its hot fields, what it derives, its words. */
export type Goblin = {
  entity: number;
  awake: boolean;
  ai: number;
  health: number;
  energy: number;
  adrenaline: number;
  caste: number;
  act_slot: number;
  act_target: number;
  act_deadline: number;
  bleeding: number;
  poison: number;
  burning: number;
  knocked: number;
  effect_deadline: number;
  effect_regen: number;
  max_health: number;
  caste_at: number;
  effect_at: number;
  state: bigint;
  timers: bigint;
};

/** The hot fields of a goblin's words (`GoblinTrait::hot`), in `Goblin`'s order, and its level. */
export type Hot = {
  ai: number;
  health: number;
  energy: number;
  adrenaline: number;
  caste: number;
  act_slot: number;
  act_target: number;
  act_deadline: number;
  bleeding: number;
  poison: number;
  burning: number;
  knocked: number;
  effect_deadline: number;
  level: number;
  /** The effect's skill and its rank. */
  effect: number;
  rank: number;
};

/** `GoblinAssert::assert_pips`: an effect's `REGENERATION` pips fit an `i8`. */
export function assert_pips(pips: number): void {
  if (!(pips >= -128 && pips <= 127)) panic(errors.REGEN);
}

/** `GoblinAssert::assert_kit`: its caste's skills are all in the content. */
export function assert_kit(kit: { skills: readonly number[] }): void {
  if (!kit.skills.every((skill) => skill !== MISSING)) panic(tickErrors.NO_SKILL);
}

/**
 * `GoblinTrait::hot`: the hot fields of a goblin's words, each read from its low bits. The
 * timers' rank is what is left of the high limb once `LIVE` is removed and the fields above are
 * peeled.
 */
export function hot(state: bigint, timers: bigint): Hot {
  const [low] = limbs(state);
  // Bits 0–23 (position, facing) are not read
  let rest = low / two(24);
  const read = (size: bigint): number => {
    const [value, next] = peel(rest, size);
    rest = next;
    return small(value);
  };
  const ai = read(0x100n);
  const health = read(0x10000n);
  const energy = read(0x100n);
  const adrenaline = read(0x100n);
  const caste = read(0x10000n);
  const level = read(0x100n);
  const [tlow, thigh] = limbs(timers);
  rest = tlow;
  const act_slot = read(0x100n);
  const act_target = read(0x10000n);
  const act_deadline = read(two(28));
  const bleeding = read(two(28));
  const poison = read(two(28));
  const effect = read(0x10000n);
  rest = thigh;
  const burning = read(two(28));
  read(two(28));
  const knocked = read(two(28));
  const effect_deadline = read(two(28));
  read(0x40n);
  const rank = small(narrow(u8, rest));
  return {
    ai,
    health,
    energy,
    adrenaline,
    caste,
    act_slot,
    act_target,
    act_deadline,
    bleeding,
    poison,
    burning,
    knocked,
    effect_deadline,
    level,
    effect,
    rank,
  };
}

/** A goblin's max health at `level` (`CasteSheet::max_health`): `(80 + 20 level) × health / 100`. */
function max_health_of(multiplier: number, level: number): number {
  const base = 80 + 20 * level;
  return small(narrow(u16, div(u32, mul(u32, BigInt(base), BigInt(multiplier)), 100n)));
}

/**
 * `GoblinTrait::load`: a goblin from its words, with what it derives once from its caste and level:
 * its max health, and its effect's `REGENERATION` pips; its caste's position. Refused, as Cairo
 * refuses: a caste not in the content (`NO_CASTE`), a caste skill or the effect's skill not in it
 * (`NO_SKILL`), pips above an `i8` (`REGEN`), a max health above a `u16`.
 */
export function load(words: GoblinWords, sheets: Sheets): Goblin {
  const fields = hot(words.state, words.timers);
  const caste_at = casteAt(sheets, fields.caste);
  const sheet = sheets.castes[caste_at]!;
  assert_kit(sheets.kits[caste_at]!);
  let effect_at = ABSENT;
  let effect_regen = 0;
  if (fields.effect !== 0) {
    effect_at = skillAt(sheets, fields.effect);
    const skill = sheets.skills[effect_at]!;
    effect_regen = line(skill.regen0, skill.regen12, fields.rank);
  }
  assert_pips(effect_regen);
  return {
    entity: words.entity,
    awake: words.awake,
    ai: fields.ai,
    health: fields.health,
    energy: fields.energy,
    adrenaline: fields.adrenaline,
    caste: fields.caste,
    act_slot: fields.act_slot,
    act_target: fields.act_target,
    act_deadline: fields.act_deadline,
    bleeding: fields.bleeding,
    poison: fields.poison,
    burning: fields.burning,
    knocked: fields.knocked,
    effect_deadline: fields.effect_deadline,
    effect_regen: small(narrow(i8, BigInt(effect_regen))),
    max_health: max_health_of(sheet.health, fields.level),
    caste_at,
    effect_at,
    state: words.state,
    timers: words.timers,
  };
}

/**
 * `GoblinTrait::store`: its words, the hot fields written back. Each of the four regions the hot
 * fields lie in is rewritten whole, by the difference between its new value and the one the words
 * hold (the other bits kept).
 */
export function store(goblin: Goblin): GoblinWords {
  const [low] = limbs(goblin.state);
  const old = (low / two(24)) % two(40);
  const next =
    BigInt(goblin.ai) +
    BigInt(goblin.health) * two(8) +
    BigInt(goblin.energy) * two(24) +
    BigInt(goblin.adrenaline) * two(32);
  const state = felt(goblin.state + (next - old) * two(24));
  const [tlow, thigh] = limbs(goblin.timers);
  const old_low = tlow % two(108);
  const new_low =
    BigInt(goblin.act_slot) +
    BigInt(goblin.act_target) * two(8) +
    BigInt(goblin.act_deadline) * two(24) +
    BigInt(goblin.bleeding) * two(52) +
    BigInt(goblin.poison) * two(80);
  const old_burning = thigh % two(28);
  const old_tail = (thigh / two(56)) % two(56);
  const new_tail = BigInt(goblin.knocked) + BigInt(goblin.effect_deadline) * two(28);
  const timers = felt(
    goblin.timers +
      (new_low - old_low) +
      (BigInt(goblin.burning) - old_burning) * two(128) +
      (new_tail - old_tail) * two(184),
  );
  return { entity: goblin.entity, awake: goblin.awake, state, timers };
}

/** `GoblinTrait::health_regen`: its caste's health regeneration, signed pips (`health_regen` − 10). */
export function health_regen(goblin: Goblin, sheets: Sheets): number {
  const regen = sheets.castes[goblin.caste_at]!.health_regen;
  return small(narrow(i8, BigInt(regen - REGEN_OFFSET)));
}

/** `GoblinTrait::max_energy`: its caste's max energy, in thirds (a `u8` product). */
export function max_energy(goblin: Goblin, sheets: Sheets): number {
  return small(mul(u8, BigInt(sheets.castes[goblin.caste_at]!.energy), 3n));
}

/** `GoblinTrait::energy_regen`: its caste's energy regeneration, thirds a tick. */
export const energy_regen = (goblin: Goblin, sheets: Sheets): number =>
  sheets.castes[goblin.caste_at]!.energy_regen;

/** `GoblinTrait::adrenaline_cap`: its caste's adrenaline cap, in quarters (its kit's). */
export const adrenaline_cap = (goblin: Goblin, sheets: Sheets): number =>
  sheets.kits[goblin.caste_at]!.cap;

/** `GoblinTrait::is_alive`: neither dead nor looted. */
export const is_alive = (goblin: { ai: number }): boolean => goblin.ai < DEAD;

/** The shift of caste skill `slot`'s recharge deadline in the state word, slot 0–3. */
function recharge_shift(slot: number): bigint {
  const shift = [two(128), two(156), two(184), two(212)][slot];
  if (shift === undefined) panic("Index out of bounds");
  return shift;
}

/** `GoblinTrait::recharge`: the recharge deadline of caste skill 0–3 (`GoblinState` 128–239). */
export function recharge(goblin: Goblin, slot: number): number {
  const [, high] = limbs(goblin.state);
  const shift = [1n, two(28), two(56), two(84)][slot];
  if (shift === undefined) panic("Index out of bounds");
  return small(field(high, shift, two(28)));
}

/** `GoblinTrait::set_recharge`. */
export function set_recharge(goblin: Goblin, slot: number, deadline: number): void {
  const shift = recharge_shift(slot);
  goblin.state = felt(goblin.state + delta(recharge(goblin, slot), deadline, shift));
}

/** `GoblinWordsTrait::crippled`: Crippled's deadline (`GoblinTimers` bits 156–183). */
export function crippled(goblin: Goblin): number {
  const [, high] = limbs(goblin.timers);
  return small(field(high, two(28), two(28)));
}

/** `GoblinWordsTrait::set_crippled`. */
export function set_crippled(goblin: Goblin, deadline: number): void {
  goblin.timers = felt(goblin.timers + delta(crippled(goblin), deadline, two(156)));
}

/** `GoblinWordsTrait::effect_of`: its one held effect (a skill; a goblin holds no potion). */
export function effect_of(goblin: Goblin): Held {
  const [low, high] = limbs(goblin.timers);
  const tail = high / two(112);
  // Bits 240–245 the charges, 246–249 the rank: nothing lies above it once `LIVE` is off
  const charges = small(tail % 0x40n);
  const rank = small(narrow(u8, tail / 0x40n));
  return {
    carrier: small(field(low, two(108), two(16))),
    potion: false,
    charges,
    deadline: goblin.effect_deadline,
    rank,
  };
}

/** `GoblinWordsTrait::set_effect`: writes its one effect, with its `REGENERATION` pips. */
export function set_effect(goblin: Goblin, held: Held, pips: number): void {
  const old = effect_of(goblin);
  goblin.timers = felt(
    goblin.timers +
      delta(old.carrier, held.carrier, two(108)) +
      delta(old.charges, held.charges, two(240)) +
      delta(old.rank, held.rank, two(246)),
  );
  goblin.effect_deadline = held.deadline;
  goblin.effect_regen = small(arg(i8, BigInt(pips)));
}

/** `GoblinPlaceTrait::at`: the tile and facing a `GoblinState` word holds (bits 0–23). */
export function at(state: bigint): { x: number; y: number; facing: number } {
  const [low] = limbs(state);
  return {
    x: small(low % 0x100n),
    y: small((low / 0x100n) % 0x100n),
    facing: small((low / 0x10000n) % 0x100n),
  };
}

/** `GoblinPlaceTrait::place`: its tile and facing. */
export const place = (goblin: Goblin): { x: number; y: number; facing: number } => at(goblin.state);

/** `GoblinPlaceTrait::set_place`: moves it to the tile `(x, y)`, facing `facing` (bits 0–23). */
export function set_place(goblin: Goblin, x: number, y: number, facing: number): void {
  const was = at(goblin.state);
  const old = was.x + was.y * 0x100 + was.facing * 0x10000;
  goblin.state = felt(goblin.state + delta(old, x + y * 0x100 + facing * 0x10000, 1n));
}

/** `GoblinPlaceTrait::level`: its level (`GoblinState` 80–87). */
export function level(goblin: Goblin): number {
  const [low] = limbs(goblin.state);
  return small(field(low, two(80), 0x100n));
}
