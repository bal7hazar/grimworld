import {
  type CasteSheet,
  type Content,
  type PotionSheet,
  type SkillSheet,
  from16,
  limbs,
} from "@grimworld/sim";
import type { InstanceView, MemberView } from "./view";

/**
 * The content a batch's segment reads (CLI-10d, D-257, D-263), assembled from the Registry's
 * records as `PlayLibrary` assembles it before its first `SegmentLibrary` call
 * (contracts/ephemeral/src/systems/play.cairo): `Content { skills, potions, castes }` (:590-594)
 * from its `Book`, filled in two reads.
 *
 * 1. `play`'s first `bundle` (:226-247): after the location, its chunk set and the area's pack
 *    templates, each member's content (`member_content`, :1228-1250: the bar's 8 skills, then for
 *    each slot 0–3 the belt's item and, for a held effect that is not a potion's, its carrier
 *    skill; 0 skipped, each id once), the skills then the potions. A record the registry lacks is
 *    skipped (`exists`, :260-284).
 * 2. `goblins` (:400-536): the castes the goblins need (the derived ones' from their pack's
 *    template, :428-456, then the stored ones', :457-462), the castes' skills the book lacks, in
 *    caste order (:463-486), then the stored goblins' held effects' skills (:487-492), 32 a
 *    `bundle` (:493-514). A missing caste or skill makes the goblin unloadable (`usable`), which
 *    the view reports as `UNLOADABLE`.
 *
 * The client needs neither the location (the view's, VIEW-01) nor the pack templates: the view's
 * goblins carry their caste, the derived ones' set from their template as `goblins` sets it
 * (:515-528). It reads the castes from the goblins' states, and each record by one
 * `Registry.record(kind, id)` (the records are the ones `bundle` concatenates, :175-184).
 *
 * The order: as `play`'s, but for the stored goblins, taken in entity order where `play` takes the
 * roster's order (`roster`, which the view does not give) and then the touched ones by chunk. The
 * order moves only positions in the lists: the segment finds every sheet by its id (`Index`), and
 * the lists hold each id once, so what it computes is the same.
 */

/** `content::CASTE`, `SKILL` and `ITEM` (contracts/logic/src/content.cairo :16, :17, :21). */
export const CASTE = 8;
export const SKILL = 9;
export const ITEM = 11;

/** `Registry.record(kind, id)`: the record's parts, zeros for one never written. */
export type RecordRead = (kind: number, id: number) => Promise<readonly bigint[]>;

const P8 = 1n << 8n;
const P16 = 1n << 16n;
/** `effect::ENTRY_BOUND`: an entry's 97 bits. */
const ENTRY_BOUND = 1n << 97n;
/** `CasteSheet.armor_vs`'s 54 bits (`VS_BOUND`). */
const VS_BOUND = 1n << 54n;
/** `kind::EMPTY`, `kind::REGENERATION`. */
const EMPTY = 0n;
const REGENERATION = 5n;

/** `packing::peel`: the low `size` of `rest`, and what is above it. */
const peel = (rest: bigint, size: bigint): [bigint, bigint] => [rest % size, rest / size];
/** `try_into().unwrap()` into an unsigned type of `width` bits. */
function narrow(value: bigint, width: number): number {
  if (value >= 1n << BigInt(width)) throw new RangeError(`${value} above u${width}`);
  return Number(value);
}

/** `content::exists`: a record is written when its first part is not 0. */
export const exists = (parts: readonly bigint[]): boolean => (parts[0] ?? 0n) !== 0n;

/** `SkillSheetTrait::read` (contracts/logic/src/types/tick.cairo :260-305), from 2 parts. */
export function readSkillSheet(id: number, parts: readonly bigint[]): SkillSheet {
  const [header, first] = limbs(parts[0]!);
  const [second, third] = limbs(parts[1]!);
  let regen0 = 0;
  let regen12 = 0;
  for (const entry of [first, second, third]) {
    const [entryKind, above] = peel(entry, P8);
    if (entryKind === EMPTY) break;
    if (entryKind === REGENERATION) {
      // Bits 8–15, then `v0` and `v12`
      const [v0, rest] = peel(above / P8, P16);
      regen0 = from16(v0);
      regen12 = from16(peel(rest, P16)[0]);
      break;
    }
  }
  // The header: profession 0–7, attribute 8–15, kind, energy, adrenaline, activation, recharge,
  // range
  const fields: bigint[] = [];
  let rest = header;
  for (const size of [P8, P8, P8, P8, P8, P16, P16, P8]) {
    let value: bigint;
    [value, rest] = peel(rest, size);
    fields.push(value);
  }
  const [profession, , kind, energy, adrenaline, activation, recharge, range] = fields;
  return {
    id: narrow(BigInt(id), 16),
    kind: narrow(kind!, 8),
    energy: narrow(energy!, 8),
    profession: narrow(profession!, 8),
    adrenaline: narrow(adrenaline!, 8),
    activation: narrow(activation!, 16),
    recharge: narrow(recharge!, 16),
    regen0,
    regen12,
    range: narrow(range!, 8),
    entry1: first,
    entry2: second,
    entry3: third,
  };
}

/** `PotionSheetTrait::read` (tick.cairo :343-361), from 1 part. */
export function readPotionSheet(id: number, parts: readonly bigint[]): PotionSheet {
  const [, high] = limbs(parts[0]!);
  const [entry, above] = peel(high, ENTRY_BOUND);
  const [range, strength] = peel(above, P8);
  const [entryKind, rest] = peel(entry, P8);
  const regen = entryKind === REGENERATION ? from16(peel(rest / P8, P16)[0]) : 0;
  return { id, regen, entry, range: narrow(range, 8), strength: narrow(strength, 8) };
}

/** `CasteSheetTrait::read` (tick.cairo :410-454), from 2 parts. */
export function readCasteSheet(id: number, parts: readonly bigint[]): CasteSheet {
  const [low, high] = limbs(parts[0]!);
  const [skills] = limbs(parts[1]!);
  // Tier and AI profile 0–15, the health multiplier, its regeneration, the armor; the weapon's
  // class, damage, type, ticks and range 48–79; energy and its regeneration, the flee threshold,
  // the rank 104–107. The high limb: the armor by type, 54 bits.
  const P4 = 1n << 4n;
  const fields: bigint[] = [];
  let rest = low / P16;
  for (const size of [P16, P8, P8, P4, P16, P4, P4, P4, P8, P8, P8, P4]) {
    let value: bigint;
    [value, rest] = peel(rest, size);
    fields.push(value);
  }
  const [
    health,
    healthRegen,
    armor,
    weapon,
    damage,
    damageType,
    ticks,
    range,
    energy,
    energyRegen,
  ] = fields;
  const rank = fields[11]!;
  const ids: number[] = [];
  rest = skills;
  for (let k = 0; k < 4; k++) {
    let value: bigint;
    [value, rest] = peel(rest, P16);
    ids.push(Number(value));
  }
  return {
    id: narrow(BigInt(id), 16),
    health: narrow(health!, 16),
    health_regen: narrow(healthRegen!, 8),
    energy: narrow(energy!, 8),
    energy_regen: narrow(energyRegen!, 8),
    weapon_ticks: narrow(ticks!, 8),
    skills: ids,
    armor: narrow(armor!, 8),
    armor_vs: high % VS_BOUND,
    weapon: narrow(weapon!, 8),
    weapon_damage: narrow(damage!, 8),
    damage_type: narrow(damageType!, 8),
    weapon_range: narrow(range!, 8),
    rank: narrow(rank, 8),
  };
}

/** `id` added to `ids` unless it is 0 or already there (`InternalTrait::add`, `PlayTrait::push`). */
function add(ids: number[], id: number): void {
  if (id !== 0 && !ids.includes(id)) ids.push(id);
}

/** A field of a word's low limb (`packing::field`). */
const lowField = (word: bigint, at: number, width: number): number =>
  Number((limbs(word)[0] >> BigInt(at)) & ((1n << BigInt(width)) - 1n));

/**
 * `PlayTrait::member_content` over every member (play.cairo :236-239, :1228-1250): the skills and
 * potions their load needs, in `play`'s order.
 */
export function memberContent(members: readonly MemberView[]): {
  skills: number[];
  potions: number[];
} {
  const skills: number[] = [];
  const potions: number[] = [];
  for (const { bar, kit, effects } of members) {
    // `MemberTrait::bar_skill`: slot `s` at bit 16 s of the low limb
    for (let slot = 0; slot < 8; slot++) add(skills, lowField(bar, 16 * slot, 16));
    const [elow, ehigh] = limbs(effects);
    for (let slot = 0; slot < 4; slot++) {
      // `MemberWordsTrait::kit_item`: 32 bits each
      add(potions, lowField(kit, 32 * slot, 32));
      // `MemberWordsTrait::held`: slots 0–1 in the low limb, 2–3 in the high, 56 bits apart
      const held = ((slot < 2 ? elow : ehigh) >> BigInt(56 * (slot % 2))) & ((1n << 56n) - 1n);
      const carrier = Number(held % P16);
      const potion = (held >> 23n) % 2n === 1n;
      if (!potion) add(skills, carrier);
    }
  }
  return { skills, potions };
}

/** A goblin's caste (`PlayTrait::caste_of`, bits 64–79 of its state). */
const casteOf = (state: bigint): number => Number((state >> 64n) & 0xffffn);
/** A goblin's held effect's skill (`PlayTrait::effect_of`, bits 108–123 of its timers). */
const effectOf = (timers: bigint): number => Number((timers >> 108n) & 0xffffn);

/** The content, and the number of `Registry.record` calls it took. */
export type Assembled = { content: Content; calls: number };

/**
 * The batch's content from the view and the Registry's records, in two rounds: the members' skills
 * and potions with the goblins' castes, then the skills of those castes and of the stored goblins'
 * held effects that the first round did not read. The calls of a round run at once.
 */
export async function assembleContent(view: InstanceView, record: RecordRead): Promise<Assembled> {
  let calls = 0;
  const read = (kind: number, id: number) => {
    calls++;
    return record(kind, id);
  };
  const { skills, potions } = memberContent(view.members);
  // The derived goblins first, then the stored ones (`goblins`, :436-460)
  const castes: number[] = [];
  for (const goblin of view.goblins) if (goblin.derived) add(castes, casteOf(goblin.state));
  for (const goblin of view.goblins) if (!goblin.derived) add(castes, casteOf(goblin.state));
  const [skillParts, potionParts, casteParts] = await Promise.all([
    Promise.all(skills.map((id) => read(SKILL, id))),
    Promise.all(potions.map((id) => read(ITEM, id))),
    Promise.all(castes.map((id) => read(CASTE, id))),
  ]);
  const content: Content = { skills: [], potions: [], castes: [] };
  skills.forEach((id, k) => {
    if (exists(skillParts[k]!)) content.skills.push(readSkillSheet(id, skillParts[k]!));
  });
  potions.forEach((id, k) => {
    if (exists(potionParts[k]!)) content.potions.push(readPotionSheet(id, potionParts[k]!));
  });
  const held = (id: number) => content.skills.some((sheet) => sheet.id === id);
  const more: number[] = [];
  castes.forEach((id, k) => {
    if (!exists(casteParts[k]!)) return;
    const sheet = readCasteSheet(id, casteParts[k]!);
    for (const skill of sheet.skills) if (!held(skill)) add(more, skill);
    content.castes.push(sheet);
  });
  for (const goblin of view.goblins) {
    if (goblin.derived) continue;
    const effect = effectOf(goblin.timers);
    if (!held(effect)) add(more, effect);
  }
  const moreParts = await Promise.all(more.map((id) => read(SKILL, id)));
  more.forEach((id, k) => {
    if (exists(moreParts[k]!)) content.skills.push(readSkillSheet(id, moreParts[k]!));
  });
  return { content, calls };
}
