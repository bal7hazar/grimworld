/**
 * Conditions and held effects as chips (CLI-05 brief §6.1): a letter that carries the meaning, the
 * ticks left, a BLOCK's charges, a REGENERATION's pips.
 *
 * The ticks are read as client/sim reads the deadlines: a condition is held at the next tick while
 * `held(deadline, clock + 1)` (`segment/tick.ts`: `act` checks `can_act(member, c + 1)`, and
 * `regenerate` runs once the clock has advanced), and a held effect while `clock < deadline` (the
 * glyphs', `MOVEMENT`'s reading), which is the same test. So a chip shows `deadline − clock`, reads 1
 * before its last tick and is gone once `clock >= deadline`. An effect of deadline `MAX_CLOCK` lasts
 * by charges only: its charges, no ticks.
 */

import {
  ABSENT,
  ABSENT_LANE,
  type Goblin,
  MAX_CLOCK,
  type Member,
  type Sheets,
  condition,
  goblinCrippled,
  goblinEffect,
  heldEffect,
  held,
  holding,
  kind,
  memberCrippled,
} from "@grimworld/sim";
import type { Chip } from "./state";

/** The five conditions of the MVP (`combat.ts`'s `condition`), their letter and name (§6.1). */
export const CONDITIONS = [
  { id: condition.BLEEDING, letter: "B", name: "Bleeding" },
  { id: condition.POISON, letter: "P", name: "Poison" },
  { id: condition.BURNING, letter: "F", name: "Burning" },
  { id: condition.CRIPPLED, letter: "C", name: "Crippled" },
  { id: condition.KNOCKED_DOWN, letter: "K", name: "Knocked down" },
] as const;

/** A held effect's letter and name by its holding entry's kind (§6.1's last row: an initial). */
const EFFECTS: Readonly<Record<number, { letter: string; name: string }>> = {
  [kind.REGENERATION]: { letter: "R", name: "Regeneration" },
  [kind.BLOCK]: { letter: "▣", name: "Block" },
  [kind.ARMOR]: { letter: "A", name: "Armor" },
  [kind.EVADE]: { letter: "E", name: "Evade" },
  [kind.MOVEMENT]: { letter: "M", name: "Movement" },
  [kind.NEXT_SPELL_COST]: { letter: "G", name: "Glyph" },
  [kind.PENETRATION]: { letter: "N", name: "Penetration" },
  [kind.ON_ATTACK_CONDITION]: { letter: "O", name: "On attack" },
};
/** `combat.cairo`'s `skill_kind::STANCE`: a stance's chip is an `S`. */
const STANCE = 5;

/** The chip of a condition of deadline `deadline` at `clock`, if it is still held at the next tick. */
export function conditionChip(id: number, deadline: number, clock: number): Chip | null {
  if (!held(deadline, clock + 1)) return null;
  const { letter, name } = CONDITIONS.find((c) => c.id === id)!;
  return {
    kind: "condition",
    letter,
    name,
    ticks: deadline - clock,
    charges: null,
    pips: null,
    source: null,
  };
}

/**
 * The chip of a held effect: its carrier's holding entry (`holding`), its deadline and charges, its
 * pips; null when it no longer holds at `clock`.
 */
export function effectChip(
  sheets: Sheets,
  potion: boolean,
  at: number,
  deadline: number,
  charges: number,
  pips: number,
  clock: number,
): Chip | null {
  if (!(clock < deadline)) return null;
  const entry = holding(sheets, potion, at);
  const stance = !potion && sheets.skills[at]?.kind === STANCE;
  const { letter, name } = stance
    ? { letter: "S", name: "Stance" }
    : (EFFECTS[entry.kind] ?? { letter: "?", name: "Effect" });
  return {
    kind: "effect",
    letter,
    name,
    ticks: deadline === MAX_CLOCK ? null : deadline - clock,
    charges: charges > 0 || entry.kind === kind.BLOCK ? charges : null,
    pips: entry.kind === kind.REGENERATION || pips !== 0 ? pips : null,
    source: { potion, id: potion ? sheets.potions[at]!.id : sheets.skills[at]!.id },
  };
}

const present = (chip: Chip | null): chip is Chip => chip !== null;

/** A member's chips: its conditions first, then its effects in slot order (§6.1). */
export function memberChips(member: Member, sheets: Sheets, clock: number): Chip[] {
  const deadlines = [
    member.bleeding,
    member.poison,
    member.burning,
    memberCrippled(member),
    member.knocked,
  ];
  const conditions = CONDITIONS.map((c, k) => conditionChip(c.id, deadlines[k]!, clock));
  const effects = [0, 1, 2, 3].map((slot) => {
    const at = member.effect_at[slot]!;
    if (at === ABSENT_LANE) return null;
    const h = heldEffect(member.words.effects, slot);
    return effectChip(
      sheets,
      h.potion,
      at,
      h.deadline,
      h.charges,
      member.effect_regen[slot]!,
      clock,
    );
  });
  return [...conditions, ...effects].filter(present);
}

/** A goblin's chips: its conditions, then its one held effect (a skill's). */
export function goblinChips(goblin: Goblin, sheets: Sheets, clock: number): Chip[] {
  const deadlines = [
    goblin.bleeding,
    goblin.poison,
    goblin.burning,
    goblinCrippled(goblin),
    goblin.knocked,
  ];
  const conditions = CONDITIONS.map((c, k) => conditionChip(c.id, deadlines[k]!, clock));
  const h = goblinEffect(goblin);
  const effect =
    h.carrier === 0 || goblin.effect_at === ABSENT
      ? null
      : effectChip(
          sheets,
          false,
          goblin.effect_at,
          h.deadline,
          h.charges,
          goblin.effect_regen,
          clock,
        );
  return [...conditions, effect].filter(present);
}
