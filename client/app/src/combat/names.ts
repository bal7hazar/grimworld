/**
 * The names of the seed's skills and items, for the screens and the log (CLI-05 brief Q-1). The
 * registry holds no names and none is planned (track game, 2026-10-12); this is a copy of the table
 * `contracts/seed/README.md` keeps under "Names for the client", the single source: change it there
 * first. An id the table does not know is named by its number ("Skill 12"), never guessed.
 */

import { DEFAULT_NAMES, type Names } from "./state";

/** `SKILL` ids 1 to 4 of the seed. */
export const SKILL_NAMES: Readonly<Record<number, string>> = {
  1: "Strike",
  2: "Second Wind",
  3: "Snare",
  4: "Mending",
};

/** The healing potions (`ITEM` 1, 8, 15, 22) and the REGENERATION potion (23). */
const HEALING = "Healing Potion";
export const POTION_NAMES: Readonly<Record<number, string>> = {
  1: HEALING,
  8: HEALING,
  15: HEALING,
  22: HEALING,
  23: "Regeneration Potion",
};

/** The seed's ingredients, named by their id until the content pass names them. */
const INGREDIENT = (id: number): boolean => id >= 2 && id <= 21 && ![8, 15].includes(id);

export const skillName = (id: number): string => SKILL_NAMES[id] ?? `Skill ${id}`;

export const itemName = (id: number): string => {
  const known = POTION_NAMES[id];
  if (known !== undefined) return known;
  return INGREDIENT(id) ? `Ingredient ${id}` : `Item ${id}`;
};

/** The seed's names; the castes are the art's, as `chain/world.ts` draws them. */
export const NAMES: Names = {
  skill: skillName,
  potion: itemName,
  caste: DEFAULT_NAMES.caste,
};
