// What a segment runs over (CLI-02g-A, D-254): the words that cross a library call
// (`types::world::Words`), the call's content (`types::tick::Content`) and its in-call view
// (`Sheets`, `Index`, `Kit`: `ContentTrait::index`), and each actor's load and store
// (`models::member`'s `MemberTrait::load`, `store`; `models::goblin`'s place and AI state). The
// offsets are ENG-01's frozen ones, the Cairo modules' documentation; a field is read and written
// with `packing.ts`, and a word is changed as Cairo changes it, by a delta in the field.
//
// A goblin is kept as its words: `run` only reads a goblin (its place, its AI state, its words for
// the records of `fits`), and the classes write it, so a goblin's load is its words read where
// they are needed. Not mirrored, as no row reaches them: `GoblinTrait::load`'s refusal of a caste
// or a caste skill the content does not hold, and `WorldAssert::assert_awake` (at most 8 awake).

import { P, add, fromFelt, i16, narrow, panic, u16, u32, u8 } from "../felt";
import { field, limbs, peel } from "../packing";

/** A member's stored words (`models::index::MemberWords`). */
export type MemberWords = {
  state: bigint;
  timers: bigint;
  effects: bigint;
  recharges: bigint;
  stats: bigint;
  bar: bigint;
  kit: bigint;
};

/** A goblin's stored words, its entity id and whether it is in the awake set (`GoblinWords`). */
export type GoblinWords = { entity: number; awake: boolean; state: bigint; timers: bigint };

/** What crosses a library call (`types::world::Words`). */
export type Words = {
  clock: number;
  members: MemberWords[];
  goblins: GoblinWords[];
  killed: number[];
  defeated: boolean;
};

/** `types::tick::SkillSheet`. */
export type SkillSheet = {
  id: number;
  kind: number;
  energy: number;
  profession: number;
  adrenaline: number;
  activation: number;
  recharge: number;
  regen0: number;
  regen12: number;
  range: number;
  entry1: bigint;
  entry2: bigint;
  entry3: bigint;
};

/** `types::tick::PotionSheet`. */
export type PotionSheet = { id: number; regen: number; entry: bigint; range: number; strength: number };

/** `types::tick::CasteSheet`. */
export type CasteSheet = {
  id: number;
  health: number;
  health_regen: number;
  energy: number;
  energy_regen: number;
  weapon_ticks: number;
  skills: number[];
  armor: number;
  armor_vs: bigint;
  weapon: number;
  weapon_damage: number;
  damage_type: number;
  weapon_range: number;
  rank: number;
};

/** The content of a batch (`types::tick::Content`). */
export type Content = { skills: SkillSheet[]; potions: PotionSheet[]; castes: CasteSheet[] };

/** `types::effect::Entry`, unpacked from its 97 bits. */
export type Entry = {
  kind: number;
  param: number;
  v0: number;
  v12: number;
  d0: number;
  d12: number;
  charges: number;
  target: number;
  shape: number;
  filter: number;
  guard: number;
  scope: number;
};

/** A caste's kit (`types::tick::Kit`). */
export type Kit = { skills: number[]; cap: number; weapon_ticks: number };

/** The content as the ticks read it (`types::tick::Sheets`), its index beside it (`Index`). */
export type Sheets = Content & {
  kits: Kit[];
  /** Skill `p`'s three entries at `3 p`, `3 p + 1`, `3 p + 2`. */
  entries: Entry[];
  potion_entries: Entry[];
  /** `Index`: a record's position by its id, the first of two records of one id. */
  index: { skills: Map<number, number>; castes: Map<number, number>; potions: Map<number, number> };
};

/** `types::effect::kind`, the kinds the segment reads. */
export const kind = { EMPTY: 0, REGENERATION: 5, MOVEMENT: 16 } as const;

/** A position in a list of `Sheets` that holds nothing (`ABSENT`), and in a 16-bit lane. */
export const ABSENT = 0xffffffff;
export const ABSENT_LANE = 0xffff;
/** A caste skill the content does not hold (`MISSING`). */
export const MISSING = 0xfffffffe;
/** No member activation (`NO_SLOT`). */
export const NO_SLOT = 255;
/** Stored health regeneration is its pips + 10 (`REGEN_OFFSET`). */
const REGEN_OFFSET = 10;
/** Energy is in thirds (`ENERGY_THIRDS`). */
const ENERGY_THIRDS = 3;
const MAX_GOBLIN_ADRENALINE = 252;
const MAX_SKILLS = 0xffff;

export const errors = {
  NO_SKILL: "tick: skill not in content",
  NO_POTION: "tick: potion not in content",
  SKILLS: "tick: more skills than ids",
  REGEN: "member: regeneration above i8",
} as const;

const two = (bits: number): bigint => 1n << BigInt(bits);
const felt = (value: bigint): bigint => ((value % P) + P) % P;
const small = (value: bigint): number => Number(value);

/** `TickMathTrait::delta`: `(new − old) × shift`, the felt that rewrites a field in place. */
export const delta = (old: number, next: number, shift: bigint): bigint =>
  felt(BigInt(next - old) * shift);

/** `SignedTrait::from16`: a 16-bit field as an `i16`. */
const from16 = (bits: bigint): number => Number(bits >= 0x8000n ? bits - 0x10000n : bits);

/** `EntryTrait::unpack`: the entry of 97 bits. */
export function unpack(bits: bigint): Entry {
  let rest = bits;
  const take = (size: bigint): bigint => {
    const value = rest % size;
    rest /= size;
    return value;
  };
  const kind = small(take(0x100n));
  const param = small(take(0x100n));
  const v0 = from16(take(0x10000n));
  const v12 = from16(take(0x10000n));
  const d0 = small(take(0x10000n));
  const d12 = small(take(0x10000n));
  const charges = small(take(0x40n));
  const target = small(take(4n));
  const shape = small(take(8n));
  const filter = small(take(2n));
  const guard = small(take(8n));
  // What is left is the scope (`div_rem` of the last field keeps the quotient)
  const scope = Number(narrow(u8, rest));
  return { kind, param, v0, v12, d0, d12, charges, target, shape, filter, guard, scope };
}

/** `EntryTrait::line`: the value at `rank` on the line from rank 0 to rank 12 (Cairo's `i32` `/`). */
export function line(v0: number, v12: number, rank: number): number {
  return v0 + Math.trunc(((v12 - v0) * rank) / 12);
}

const NONE: Entry = unpack(0n);

/** `ContentTrait::index`: the sheets, each caste's kit, the entries decoded, the index. */
export function sheets(content: Content): Sheets {
  if (content.skills.length > MAX_SKILLS) panic(errors.SKILLS);
  const first = <T>(list: readonly T[], id: (item: T) => number): Map<number, number> => {
    const positions = new Map<number, number>();
    list.forEach((item, at) => {
      if (!positions.has(id(item))) positions.set(id(item), at);
    });
    return positions;
  };
  const index = {
    skills: first(content.skills, (s) => s.id),
    castes: first(content.castes, (c) => c.id),
    potions: first(content.potions, (p) => p.id),
  };
  const kits = content.castes.map((caste): Kit => {
    let cap = 0;
    const skills = caste.skills.map((id) => {
      if (id === 0) return ABSENT;
      const at = index.skills.get(id);
      if (at === undefined) return MISSING;
      cap = Math.max(cap, content.skills[at]!.adrenaline * 4);
      return at;
    });
    return { skills, cap: Math.min(cap, MAX_GOBLIN_ADRENALINE), weapon_ticks: caste.weapon_ticks };
  });
  // An entry after an empty one is empty, never decoded (`ContentTrait::entries`)
  const entries = content.skills.flatMap(({ entry1, entry2, entry3 }) => {
    if (entry1 === 0n) return [NONE, NONE, NONE];
    if (entry2 === 0n) return [unpack(entry1), NONE, NONE];
    return [unpack(entry1), unpack(entry2), entry3 === 0n ? NONE : unpack(entry3)];
  });
  const potion_entries = content.potions.map((p) => unpack(p.entry));
  return { ...content, kits, entries, potion_entries, index };
}

function skillAt(sheets: Sheets, id: number): number {
  const at = sheets.index.skills.get(id);
  if (at === undefined) panic(errors.NO_SKILL);
  return at;
}

function potionAt(sheets: Sheets, id: number): number {
  const at = sheets.index.potions.get(id);
  if (at === undefined) panic(errors.NO_POTION);
  return at;
}

/** A member inside the call (`models::index::Member`): its hot fields, what it derives, its words. */
export type Member = {
  status: number;
  health: number;
  energy: number;
  adrenaline: number;
  flags: number;
  act_slot: number;
  act_target: number;
  act_tile: number;
  act_deadline: number;
  bleeding: number;
  poison: number;
  burning: number;
  knocked: number;
  effect_deadlines: number[];
  effect_regen: number[];
  max_health: number;
  max_energy: number;
  health_regen: number;
  energy_regen: number;
  adrenaline_cap: number;
  /** The bar's skills' positions in the content, `ABSENT_LANE` for an empty slot. */
  bar_at: number[];
  /** Each held effect's carrier's position, a skill's or a potion's, `ABSENT_LANE` for none. */
  effect_at: number[];
  words: MemberWords;
};

/** `MemberTrait::hot`: the hot fields of a member's words, in `Member`'s order. */
function hot(words: MemberWords) {
  const [low, high] = limbs(words.state);
  let rest = low / two(56);
  const read = (size: bigint): number => {
    const [value, next] = peel(rest, size);
    rest = next;
    return small(value);
  };
  const status = read(0x100n);
  const health = read(0x10000n);
  const energy = read(0x10000n);
  const adrenaline = read(0x10000n);
  const flags = small((high / two(32)) % 0x100n);
  const [tlow, thigh] = limbs(words.timers);
  rest = tlow;
  const act_slot = read(0x100n);
  const act_target = read(0x10000n);
  const act_tile = read(0x100n);
  const act_deadline = read(two(32));
  const bleeding = read(two(32));
  const poison = small(rest);
  rest = thigh;
  const burning = read(two(32));
  read(two(32));
  const knocked = read(two(32));
  return {
    status,
    health,
    energy,
    adrenaline,
    flags,
    act_slot,
    act_target,
    act_tile,
    act_deadline,
    bleeding,
    poison,
    burning,
    knocked,
  };
}

/** The belt slot's potion id of a `MemberKit` low limb, slot 0–3 (Cairo's span index). */
function beltItem(belt: bigint, slot: number): number {
  const shift = [1n, two(32), two(64), two(96)][slot];
  if (shift === undefined) panic("Index out of bounds");
  return small(field(belt, shift, two(32)));
}

/**
 * `MemberTrait::load`: the member of `words`, with its maxima and regeneration, each held effect's
 * deadline and `REGENERATION` pips (a skill's at its rank, a potion's through the belt), its bar's
 * positions and its adrenaline cap.
 */
export function load(words: MemberWords, sheets: Sheets): Member {
  const [stats] = limbs(words.stats);
  const max_health = small(field(stats, 1n, two(16)));
  const max_energy = small(field(stats, two(16), two(8)));
  const energy_regen = small(field(stats, two(24), two(8)));
  const health_regen = small(field(stats, two(32), two(8))) - REGEN_OFFSET;
  const [elow, ehigh] = limbs(words.effects);
  const effects = [elow % two(56), (elow / two(56)) % two(56), ehigh % two(56)];
  effects.push((ehigh / two(56)) % two(56));
  const [belt] = limbs(words.kit);
  const effect_deadlines: number[] = [];
  const effect_regen: number[] = [];
  const effect_at: number[] = [];
  for (const effect of effects) {
    const carrier = small(effect % two(16));
    const potion = small((effect / two(23)) % 2n);
    effect_deadlines.push(small((effect / two(24)) % two(28)));
    const rank = small(effect / two(52));
    // The potion tag first: with it the carrier is a belt slot 0–3; without, skill 0 is none
    let pips: number;
    if (potion === 1) {
      const at = potionAt(sheets, beltItem(belt, carrier));
      effect_at.push(at);
      pips = sheets.potions[at]!.regen;
    } else if (carrier === 0) {
      effect_at.push(ABSENT_LANE);
      pips = 0;
    } else {
      const at = skillAt(sheets, carrier);
      effect_at.push(at);
      const sheet = sheets.skills[at]!;
      pips = line(sheet.regen0, sheet.regen12, rank);
    }
    if (pips < -128 || pips > 127) panic(errors.REGEN);
    effect_regen.push(pips);
  }
  const [bar] = limbs(words.bar);
  let adrenaline_cap = 0;
  const bar_at = Array.from({ length: 8 }, (_, slot) => {
    const skill = small(field(bar, two(16 * slot), two(16)));
    if (skill === 0) return ABSENT_LANE;
    const at = skillAt(sheets, skill);
    adrenaline_cap = Math.max(adrenaline_cap, sheets.skills[at]!.adrenaline * 4);
    return at;
  });
  return {
    ...hot(words),
    effect_deadlines,
    effect_regen,
    max_health,
    max_energy: max_energy * ENERGY_THIRDS,
    health_regen,
    energy_regen,
    adrenaline_cap,
    bar_at,
    effect_at,
    words,
  };
}

/** `MemberTrait::store`: its words, the hot fields written back as deltas. */
export function store(member: Member): MemberWords {
  const { words } = member;
  const was = hot(words);
  const region = (m: { status: number; health: number; energy: number; adrenaline: number }) =>
    BigInt(m.status) + BigInt(m.health) * two(8) + BigInt(m.energy) * two(24) + BigInt(m.adrenaline) * two(40);
  const state = felt(
    words.state +
      (region(member) - region(was)) * two(56) +
      BigInt(member.flags - was.flags) * two(160),
  );
  const low = (m: typeof was) =>
    BigInt(m.act_slot) +
    BigInt(m.act_target) * two(8) +
    BigInt(m.act_tile) * two(24) +
    BigInt(m.act_deadline) * two(32) +
    BigInt(m.bleeding) * two(64) +
    BigInt(m.poison) * two(96);
  const timers = felt(
    words.timers +
      (low(member) - low(was)) +
      BigInt(member.burning - was.burning) * two(128) +
      BigInt(member.knocked - was.knocked) * two(192),
  );
  return { ...words, state, timers };
}

/** `MemberSnapshotTrait::place`: its tile and facing (`MemberState` 32–55). */
export function place(member: Member): { x: number; y: number; facing: number } {
  const [low] = limbs(member.words.state);
  return {
    x: small(field(low, two(32), 0x100n)),
    y: small(field(low, two(40), 0x100n)),
    facing: small(field(low, two(48), 0x100n)),
  };
}

/** `MemberWordsTrait::set_place`: moves it to `(x, y)` facing `facing`. */
export function set_place(member: Member, x: number, y: number, facing: number): void {
  const was = place(member);
  const old = was.x + was.y * 0x100 + was.facing * 0x10000;
  member.words = { ...member.words, state: felt(member.words.state + delta(old, x + y * 0x100 + facing * 0x10000, two(32))) };
}

/** `MemberWordsTrait::set_facing`. */
export function set_facing(member: Member, facing: number): void {
  member.words = {
    ...member.words,
    state: felt(member.words.state + delta(place(member).facing, facing, two(48))),
  };
}

/** `MemberWordsTrait::crippled`: Crippled's deadline (`MemberTimers` 160–191). */
export function crippled(member: Member): number {
  const [, high] = limbs(member.words.timers);
  return small(field(high, two(32), two(32)));
}

/** A held effect as its word stores it (`types::tick::Held`), slot 0–3 (`MemberWordsTrait::held`). */
export function held(effects: bigint, slot: number) {
  const [low, high] = limbs(effects);
  const limb = slot < 2 ? low : high;
  const shift = slot % 2 === 0 ? 1n : two(56);
  return {
    carrier: small(field(limb, shift, two(16))),
    charges: small(field(limb, shift * two(16), 0x40n)),
    potion: field(limb, shift * two(23), 2n) === 1n,
    deadline: small(field(limb, shift * two(24), two(28))),
    rank: small(field(limb, shift * two(52), 0x10n)),
  };
}

/** `MemberTrait::is_alive`: inside, above 0 health. */
export const is_alive = (member: Member): boolean => member.status === 0 && member.health > 0;

/** `MemberTrait::downs`: 1 when inside at 0 health. */
export const downs = (member: Member): number => (member.status === 0 && member.health === 0 ? 1 : 0);

/** `GoblinPlaceTrait::at`: a goblin's tile and facing (`GoblinState` 0–23). */
export function goblinPlace(state: bigint): { x: number; y: number; facing: number } {
  const [low] = limbs(state);
  return {
    x: small(low % 0x100n),
    y: small((low / 0x100n) % 0x100n),
    facing: small((low / 0x10000n) % 0x100n),
  };
}

/** A goblin's AI state (`GoblinState` 24–31). */
export function goblinAi(state: bigint): number {
  const [low] = limbs(state);
  return small((low / two(24)) % 0x100n);
}

/** `ai::DEAD`, and `GoblinTrait::is_alive`: below it. */
export const DEAD = 6;
export const ENGAGED = 3;

/** The world a segment runs over (`types::world::World`), its goblins as their words. */
export type World = {
  clock: number;
  members: Member[];
  goblins: GoblinWords[];
  killed: number[];
  defeated: boolean;
};

/** `WordsTrait::load` (and `SegmentTrait::reload`): the world of `words`, each member loaded. */
export function world(words: Words, sheets: Sheets): World {
  return {
    clock: words.clock,
    members: words.members.map((member) => load(member, sheets)),
    goblins: words.goblins.map((goblin) => ({ ...goblin })),
    killed: [...words.killed],
    defeated: words.defeated,
  };
}

/** `WorldStoreTrait::store`: the words of the world. */
export function words(world: World): Words {
  return {
    clock: world.clock,
    members: world.members.map(store),
    goblins: world.goblins.map((goblin) => ({ ...goblin })),
    killed: [...world.killed],
    defeated: world.defeated,
  };
}

/** `u32` and `u16` adds that panic on overflow, as Cairo's. */
export const u32add = (a: number, b: number): number => Number(add(u32, BigInt(a), BigInt(b)));
export const u16add = (a: number, b: number): number => Number(add(u16, BigInt(a), BigInt(b)));

/** An `i16` of a `Serde` felt (a sheet's regeneration). */
export const i16FromFelt = (value: bigint): number => Number(fromFelt(i16, value));
