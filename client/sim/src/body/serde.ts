// An actor as felts (CLI-02g-C): `Unit`'s layout as `vectors/body.jsonl` records it, `0` then a
// `Member`'s 35 fields or `1` then a `Goblin`'s 21, each in its struct's declaration order
// (`models/index.cairo`), an array's elements with no length, `MemberWords` its `Serde`: what
// `#[derive(Serde)]` would write. `Held` and `Infliction` are their `Serde`. A member's `bar_at`
// and `effect_at` are one `u128` each, 16 bits a lane; `effect_at`'s lanes 4–7 are refused unless
// 0 (no load writes them, and the mirror keeps 4 lanes).

import { fromFelt, i8, toFelt, u128 } from "../felt";
import type { Felts } from "../segment/serde";
import type { Goblin } from "../segment/goblin";
import type { Held, Member, MemberWords } from "../segment/words";
import type { Infliction } from "./infliction";
import type { Unit } from "./index";

const LANE = 0x10000n;

function lanes(packed: bigint, count: number): number[] {
  const out = Array.from({ length: count }, (_, k) => Number((packed / LANE ** BigInt(k)) % LANE));
  if (packed >= LANE ** BigInt(count)) throw new RangeError(`lanes above ${count}: ${packed}`);
  return out;
}

const packLanes = (values: readonly number[]): bigint =>
  values.reduce((sum, value, k) => sum + BigInt(value) * LANE ** BigInt(k), 0n);

const i8of = (r: Felts): number => Number(fromFelt(i8, r.felt()));
const n = (value: number): bigint => BigInt(value);
const signed = (value: number): bigint => toFelt(i8, BigInt(value));

function readMember(r: Felts): Member {
  const status = r.u8();
  const health = r.u16();
  const energy = r.u16();
  const adrenaline = r.u16();
  const flags = r.u8();
  const act_slot = r.u8();
  const act_target = r.u16();
  const act_tile = r.u8();
  const [act_deadline, bleeding, poison, burning, knocked] = r.fixed(5, () => r.u32());
  const effect_deadlines = r.fixed(4, () => r.u32());
  const effect_regen = r.fixed(4, () => i8of(r));
  const max_health = r.u16();
  const max_energy = r.u16();
  const health_regen = i8of(r);
  const energy_regen = r.u8();
  const adrenaline_cap = r.u16();
  const bar_at = lanes(fromFelt(u128, r.felt()), 8);
  const effect_at = lanes(fromFelt(u128, r.felt()), 4);
  const words: MemberWords = {
    state: r.felt(),
    timers: r.felt(),
    effects: r.felt(),
    recharges: r.felt(),
    stats: r.felt(),
    bar: r.felt(),
    kit: r.felt(),
  };
  return {
    status,
    health,
    energy,
    adrenaline,
    flags,
    act_slot,
    act_target,
    act_tile,
    act_deadline: act_deadline!,
    bleeding: bleeding!,
    poison: poison!,
    burning: burning!,
    knocked: knocked!,
    effect_deadlines,
    effect_regen,
    max_health,
    max_energy,
    health_regen,
    energy_regen,
    adrenaline_cap,
    bar_at,
    effect_at,
    words,
  };
}

function writeMember(x: Member): bigint[] {
  const w = x.words;
  return [
    ...[x.status, x.health, x.energy, x.adrenaline, x.flags].map(n),
    ...[x.act_slot, x.act_target, x.act_tile, x.act_deadline].map(n),
    ...[x.bleeding, x.poison, x.burning, x.knocked, ...x.effect_deadlines].map(n),
    ...x.effect_regen.map(signed),
    n(x.max_health),
    n(x.max_energy),
    signed(x.health_regen),
    n(x.energy_regen),
    n(x.adrenaline_cap),
    packLanes(x.bar_at),
    packLanes(x.effect_at),
    w.state,
    w.timers,
    w.effects,
    w.recharges,
    w.stats,
    w.bar,
    w.kit,
  ];
}

function readGoblin(r: Felts): Goblin {
  const entity = r.u16();
  const awake = r.bool();
  const ai = r.u8();
  const health = r.u16();
  const energy = r.u8();
  const adrenaline = r.u8();
  const caste = r.u16();
  const act_slot = r.u8();
  const act_target = r.u16();
  const [act_deadline, bleeding, poison, burning, knocked, effect_deadline] = r.fixed(6, () =>
    r.u32(),
  );
  const effect_regen = i8of(r);
  const max_health = r.u16();
  const caste_at = r.u32();
  const effect_at = r.u32();
  const state = r.felt();
  const timers = r.felt();
  return {
    entity,
    awake,
    ai,
    health,
    energy,
    adrenaline,
    caste,
    act_slot,
    act_target,
    act_deadline: act_deadline!,
    bleeding: bleeding!,
    poison: poison!,
    burning: burning!,
    knocked: knocked!,
    effect_deadline: effect_deadline!,
    effect_regen,
    max_health,
    caste_at,
    effect_at,
    state,
    timers,
  };
}

function writeGoblin(x: Goblin): bigint[] {
  return [
    n(x.entity),
    x.awake ? 1n : 0n,
    ...[x.ai, x.health, x.energy, x.adrenaline, x.caste, x.act_slot, x.act_target].map(n),
    ...[x.act_deadline, x.bleeding, x.poison, x.burning, x.knocked, x.effect_deadline].map(n),
    signed(x.effect_regen),
    n(x.max_health),
    n(x.caste_at),
    n(x.effect_at),
    x.state,
    x.timers,
  ];
}

/** A `Unit`: `0` and a member, or `1` and a goblin. */
export function readUnit(r: Felts): Unit {
  const tag = r.u8();
  if (tag === 0) return { kind: "M", member: readMember(r) };
  if (tag === 1) return { kind: "G", goblin: readGoblin(r) };
  throw new RangeError(`unit tag ${tag}`);
}

export const writeUnit = (unit: Unit): bigint[] =>
  unit.kind === "M" ? [0n, ...writeMember(unit.member)] : [1n, ...writeGoblin(unit.goblin)];

/** `types::tick::Held`'s `Serde`: carrier, potion, charges, deadline, rank. */
export function readHeld(r: Felts): Held {
  const carrier = r.u16();
  const potion = r.bool();
  const charges = r.u8();
  const deadline = r.u32();
  const rank = r.u8();
  return { carrier, potion, charges, deadline, rank };
}

export const writeHeld = (h: Held): bigint[] => [
  n(h.carrier),
  h.potion ? 1n : 0n,
  n(h.charges),
  n(h.deadline),
  n(h.rank),
];

/** `Infliction`'s `Serde`: condition, percent, knockdown. */
export const readInfliction = (r: Felts): Infliction => ({
  condition: r.u8(),
  percent: r.u8(),
  knockdown: r.u8(),
});

export const writeInfliction = (x: Infliction): bigint[] => [
  n(x.condition),
  n(x.percent),
  n(x.knockdown),
];
