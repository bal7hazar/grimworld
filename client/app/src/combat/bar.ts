/**
 * A bar slot's state and a belt slot's (CLI-05 brief §2.2, §3), from a member client/sim loaded.
 * The state is the refusal the action class would give, in `act`'s order (`client/sim/src/action.ts`,
 * `act` and its Skill arm): `Knocked` first, then `Empty`, `Kind`, `Recharging`, `Adrenaline`,
 * `Energy`. Every figure is read by client/sim's function: the cost by `energy` (Fieldcraft, and a
 * spell's glyphs by `glyphs`), the recharge by `memberRecharge`, the weapon by `weapon_required`,
 * the belt by `beltItem` and `belt_count`.
 *
 * Two states are the screen's own, not `act`'s:
 * - "activating" and the other slots' "not now" while the adventurer activates: `act` does not
 *   refuse a skill then, but in the chain mode the adventurer is never at rest while activating
 *   (§9), so the state is seen in the sandbox only;
 * - "unavailable": a carrier client/sim refuses to mirror (`mixed`, `NotMirrored`), which R-44
 *   keeps out of the content (§4.4).
 */

import {
  ABSENT_LANE,
  NO_SLOT,
  type Carrier,
  type Member,
  type Sheets,
  barRank,
  beltItem,
  belt_count,
  energy,
  glyphs,
  held,
  is_spell,
  kind,
  memberRecharge,
  mixed,
  shapes,
  skillKind,
  target,
  weapon_required,
} from "@grimworld/sim";
import type {
  Addressing,
  BarSlot,
  BeltSlot,
  BeltState,
  PotionLook,
  SkillLook,
  SkillSheetView,
  SlotState,
} from "./state";

/** Energy and adrenaline as the words hold them: thirds and quarters (`ENERGY_THIRDS`, a strike's 4). */
export const THIRDS = 3;
export const QUARTERS = 4;

/** `executor.ts`'s `target`, in words. */
export function addressingName(t: number): Addressing {
  if (t === target.SELF) return "self";
  if (t === target.FOE) return "foe";
  if (t === target.ALLY) return "ally";
  return "tile";
}

/** Whether the member is knocked down at the next tick: `act` refuses with `Knocked` (`can_act`). */
export const knockedAt = (member: Member, clock: number): boolean => held(member.knocked, clock + 1);

/** Whether the member activates now: a slot set and its deadline still ahead. */
export const activating = (member: Member, clock: number): boolean =>
  member.act_slot !== NO_SLOT && member.act_deadline > clock;

/** Skill `at`'s entry `k` (`ContentTrait::entries`' decoding, held in the sheets). */
const entryOf = (sheets: Sheets, at: number, k: number) => sheets.entries[3 * at + k]!;

/** A skill's look for its monogram (§8): attack, trap, stance, spell, shout (a ring on itself), other. */
export function skillLook(sheets: Sheets, at: number): SkillLook {
  const sheet = sheets.skills[at]!;
  const first = entryOf(sheets, at, 0);
  if (sheet.kind === skillKind.ATTACK) return "attack";
  if (first.kind === kind.TRAP) return "trap";
  // `combat.cairo`'s `skill_kind::STANCE`
  if (sheet.kind === 5) return "stance";
  if (is_spell(sheet.kind)) return "spell";
  if (first.target === target.SELF && first.shape === shapes.RING_1) return "shout";
  return "other";
}

/** The skill of bar slot `slot`'s carrier, at its rank. */
export const barCarrier = (member: Member, slot: number): Carrier & { kind: "Skill" } => ({
  kind: "Skill",
  at: member.bar_at[slot]!,
  rank: barRank(member, slot),
});

/** The energy, in thirds, bar slot `slot`'s skill costs at clock `clock` (`act`'s own reading). */
export function costOf(member: Member, sheets: Sheets, clock: number, slot: number): number {
  const sheet = sheets.skills[member.bar_at[slot]!]!;
  const [glyph] = is_spell(sheet.kind) ? glyphs(member, sheets, clock) : [0, 0];
  return energy(member, sheet.energy, sheet.profession, glyph);
}

/** The state of bar slot `slot` at `clock`, and the ticks it counts down (§2.2). */
export function slotState(
  member: Member,
  sheets: Sheets,
  clock: number,
  slot: number,
): { state: SlotState; ticks: number | null } {
  if (knockedAt(member, clock)) return { state: "not-now", ticks: null };
  if (activating(member, clock)) {
    if (member.act_slot === slot) {
      return { state: "activating", ticks: member.act_deadline - clock };
    }
    return { state: "not-now", ticks: null };
  }
  const at = member.bar_at[slot]!;
  if (at === ABSENT_LANE) return { state: "empty", ticks: null };
  if (mixed(sheets, barCarrier(member, slot))) return { state: "unavailable", ticks: null };
  const sheet = sheets.skills[at]!;
  if (sheet.kind === skillKind.ATTACK && weapon_required(member, slot)) {
    return { state: "wrong-weapon", ticks: null };
  }
  const recharge = memberRecharge(member, slot);
  if (clock < recharge) return { state: "recharging", ticks: recharge - clock };
  if (member.adrenaline < sheet.adrenaline * QUARTERS) {
    return { state: "short-adrenaline", ticks: null };
  }
  if (member.energy < costOf(member, sheets, clock, slot)) {
    return { state: "short-energy", ticks: null };
  }
  return { state: "ready", ticks: null };
}

/** The sheet of bar slot `slot`'s skill as the screen shows it; null for an empty slot. */
export function skillView(
  member: Member,
  sheets: Sheets,
  clock: number,
  slot: number,
): SkillSheetView | null {
  const at = member.bar_at[slot]!;
  if (at === ABSENT_LANE) return null;
  const sheet = sheets.skills[at]!;
  const attack = sheet.kind === skillKind.ATTACK;
  return {
    id: sheet.id,
    look: skillLook(sheets, at),
    energy: costOf(member, sheets, clock, slot) / THIRDS,
    strikes: sheet.adrenaline,
    activation: sheet.activation,
    recharge: sheet.recharge,
    range: sheet.range,
    // An attack skill addresses a foe at the weapon's range (`addressing`)
    addressing: attack ? "foe" : addressingName(entryOf(sheets, at, 0).target),
  };
}

/** The eight slots of the bar (§2). */
export function barOf(member: Member, sheets: Sheets, clock: number): BarSlot[] {
  return Array.from({ length: 8 }, (_, slot) => ({
    slot,
    skill: skillView(member, sheets, clock, slot),
    ...slotState(member, sheets, clock, slot),
  }));
}

/** The content's position of belt slot `slot`'s potion, as `act`'s Item arm finds it; -1 for none. */
export function potionAt(member: Member, sheets: Sheets, slot: number): number {
  const id = beltItem(member, slot);
  return sheets.potions.findIndex((sheet) => id !== 0 && sheet.id === id);
}

/** A potion's look (§8): its entry heals, regenerates, or something else. */
export function potionLook(sheets: Sheets, at: number): PotionLook {
  const entry = sheets.potion_entries[at]!;
  if (entry.kind === kind.HEAL) return "heal";
  if (entry.kind === kind.REGENERATION) return "regeneration";
  return "other";
}

/** Belt slot `slot` (§3), in `act`'s order: `Knocked`, `Empty`, `Belt`; activating is "not now". */
export function beltSlot(member: Member, sheets: Sheets, clock: number, slot: number): BeltSlot {
  const at = potionAt(member, sheets, slot);
  const count = belt_count(member, slot);
  let state: BeltState;
  if (knockedAt(member, clock)) state = "not-now";
  else if (at < 0) state = "empty";
  else if (count === 0) state = "none-left";
  else if (activating(member, clock)) state = "not-now";
  else state = "some";
  if (at < 0) {
    return { slot, item: null, look: "other", count, state, addressing: null, range: 0 };
  }
  const sheet = sheets.potions[at]!;
  return {
    slot,
    item: sheet.id,
    look: potionLook(sheets, at),
    count,
    state,
    addressing: addressingName(sheets.potion_entries[at]!.target),
    range: sheet.range,
  };
}

export const beltOf = (member: Member, sheets: Sheets, clock: number): BeltSlot[] =>
  Array.from({ length: 4 }, (_, slot) => beltSlot(member, sheets, clock, slot));
