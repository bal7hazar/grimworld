// The enumerations of combat the mirror reads (`contracts/logic/src/types/combat.cairo`, frozen by
// CBT-01, X-2): conditions, damage types, skill kinds and the goblin's activation field.

/** `condition`: ids 1–9; 1–5 are the MVP's, stored as deadlines (`LAST_MVP`). */
export const condition = {
  BLEEDING: 1,
  POISON: 2,
  BURNING: 3,
  CRIPPLED: 4,
  KNOCKED_DOWN: 5,
  LAST_MVP: 5,
} as const;

/** `damage`: types 1–9 (`LAST`), one per-type armor each. */
export const damage = { LAST: 9 } as const;

/** `skill_kind`: the kinds the mirror reads. */
export const skill_kind = { ATTACK: 1, ENCHANTMENT: 4, STANCE: 5 } as const;

/** `activation`: a goblin's activation field, a caste skill `0..=LAST_SLOT` or one of these. */
export const activation = { LAST_SLOT: 3, RECOVERING: 254, NONE: 255 } as const;
