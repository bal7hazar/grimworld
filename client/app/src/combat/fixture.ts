/**
 * The sandbox's fixed fight (CLI-05 brief §9), read by CLI-05c's `?combat=fight`: Wren with
 * `ADVENTURER`'s bar, a belt with an emptied slot, three chips, and four goblins, one of them
 * activating on Wren. It is a `CombatState` written by hand, as the sandbox's other fixtures are:
 * nothing is computed. Two states: at rest, and Wren activating Charge (activating dims the rest of
 * the bar, §2.2, so it needs its own shot).
 *
 * The figures (Q-4): design/03's starter skills where named (Cleave, Second Wind; Shield bash takes
 * Brace's 5 / 0 / 15 since it carries the BLOCK entry here), the rest PLACEHOLDER until CNT-01's
 * seed. The tiles sit around the sandbox's `edge` fixture's adventurer (23, 7); CLI-05c may place
 * the fight on another world by moving them together.
 */

import type { Tile } from "../render/view";
import type { BarSlot, BeltSlot, Chip, CombatGoblin, CombatState, SkillSheetView } from "./state";

/** The clock of the fight. */
const CLOCK = 40;
const WREN: Tile = { x: 23, y: 7 };
/** The goblins' entities: the first chunk's, `8 + k` (M-5). */
export const FIGHT = { hobgoblin: 8, shaman: 9, runt: 10, skirmisher: 11 } as const;

/** The five skills of `ADVENTURER`'s bar (sandbox/fixtures/hubs.ts), with their figures. */
const SKILLS: readonly SkillSheetView[] = [
  // design/03: Axes attack, 4 adrenaline; Wren holds a sword, so it needs its weapon
  {
    id: 1,
    name: "Cleave",
    look: "attack",
    energy: 0,
    strikes: 4,
    activation: 0,
    recharge: 0,
    range: 1,
    addressing: "foe",
  },
  // Brace's figures (design/03), with the BLOCK entry the chip comes from
  {
    id: 2,
    name: "Shield bash",
    look: "stance",
    energy: 5,
    strikes: 0,
    activation: 0,
    recharge: 15,
    range: 0,
    addressing: "self",
  },
  /** PLACEHOLDER until CNT-01: an activation of 2 ticks on a foe within 4 tiles. */
  {
    id: 3,
    name: "Charge",
    look: "attack",
    energy: 3,
    strikes: 0,
    activation: 2,
    recharge: 10,
    range: 4,
    addressing: "foe",
  },
  /** PLACEHOLDER until CNT-01: a shout around Wren, 2 strikes of adrenaline. */
  {
    id: 4,
    name: "Taunt",
    look: "shout",
    energy: 0,
    strikes: 2,
    activation: 0,
    recharge: 20,
    range: 0,
    addressing: "self",
  },
  // design/03: Second Wind, 5 / 1 / 20
  {
    id: 5,
    name: "Second wind",
    look: "other",
    energy: 5,
    strikes: 0,
    activation: 1,
    recharge: 20,
    range: 0,
    addressing: "self",
  },
];

/** At rest: one slot of each state of §2.2 but "not now" and "activating", and three empty. */
const REST: readonly Pick<BarSlot, "state" | "ticks">[] = [
  { state: "wrong-weapon", ticks: null },
  { state: "recharging", ticks: 3 },
  { state: "ready", ticks: null },
  { state: "short-adrenaline", ticks: null },
  { state: "short-energy", ticks: null },
];

function bar(activating: boolean): BarSlot[] {
  return Array.from({ length: 8 }, (_, slot): BarSlot => {
    const skill = SKILLS[slot] ?? null;
    if (skill === null) return { slot, skill, state: "empty", ticks: null };
    if (!activating) return { slot, skill, ...REST[slot]! };
    return slot === 2
      ? { slot, skill, state: "activating", ticks: 1 }
      : { slot, skill, state: "not-now", ticks: null };
  });
}

function belt(activating: boolean): BeltSlot[] {
  const some = activating ? "not-now" : "some";
  return [
    {
      slot: 0,
      item: 101,
      name: "Healing potion",
      look: "heal",
      count: 3,
      state: some,
      addressing: "self",
      range: 0,
    },
    {
      slot: 1,
      item: 102,
      name: "Antidote",
      look: "other",
      count: 1,
      state: some,
      addressing: "self",
      range: 0,
    },
    // Drunk already: its REGENERATION is one of Wren's chips
    {
      slot: 2,
      item: 103,
      name: "Regeneration potion",
      look: "regeneration",
      count: 0,
      state: "none-left",
      addressing: "self",
      range: 0,
    },
    { slot: 3, item: null, look: "other", count: 0, state: "empty", addressing: null, range: 0 },
  ];
}

const condition = (letter: string, name: string, ticks: number): Chip => ({
  kind: "condition",
  letter,
  name,
  ticks,
  charges: null,
  pips: null,
  source: null,
});

/** Wren's chips: bleeding (4 ticks), the potion's REGENERATION, Shield bash's BLOCK (2 charges, 6 ticks). */
const CHIPS: readonly Chip[] = [
  condition("B", "Bleeding", 4),
  {
    kind: "effect",
    letter: "R",
    name: "Regeneration",
    ticks: 5,
    charges: null,
    pips: 2,
    source: { potion: true, id: 103 },
  },
  {
    kind: "effect",
    letter: "▣",
    name: "Block",
    ticks: 6,
    charges: 2,
    pips: null,
    source: { potion: false, id: 2 },
  },
];

const goblin = (
  g: Partial<CombatGoblin> & Pick<CombatGoblin, "entity" | "caste" | "casteName" | "tile">,
): CombatGoblin => ({
  health: 80,
  maxHealth: 80,
  alive: true,
  mark: "engaged",
  activation: null,
  recovering: false,
  chips: [],
  knocked: false,
  ...g,
});

const GOBLINS: readonly CombatGoblin[] = [
  // Beside Wren, Overhead Smash on Wren, 2 ticks left
  goblin({
    entity: FIGHT.hobgoblin,
    caste: 5,
    casteName: "hobgoblin",
    tile: { x: 24, y: 7 },
    health: 210,
    maxHealth: 240,
    activation: {
      slot: 1,
      skill: 51,
      name: "Overhead Smash",
      ticks: 2,
      total: 3,
      target: { tile: false, entity: 0 },
      area: [],
      interruptible: false,
    },
  }),
  // Mend Kin on the runt, 1 tick left
  goblin({
    entity: FIGHT.shaman,
    caste: 4,
    casteName: "shaman",
    tile: { x: 26, y: 9 },
    activation: {
      slot: 0,
      skill: 41,
      name: "Mend Kin",
      ticks: 1,
      total: 2,
      target: { tile: false, entity: FIGHT.runt },
      area: [],
      interruptible: false,
    },
  }),
  goblin({
    entity: FIGHT.runt,
    caste: 1,
    casteName: "runt",
    tile: { x: 21, y: 3 },
    health: 22,
    maxHealth: 60,
  }),
  goblin({
    entity: FIGHT.skirmisher,
    caste: 2,
    casteName: "skirmisher",
    tile: { x: 19, y: 10 },
    chips: [condition("P", "Poison", 5)],
  }),
];

/** The fight at rest, or with Wren activating Charge on the runt (1 tick left of 2). */
export function combatFixture(which: "rest" | "activating" = "rest"): CombatState {
  const activating = which === "activating";
  return {
    clock: CLOCK,
    adventurer: {
      entity: 0,
      tile: WREN,
      health: 118,
      maxHealth: 160,
      energy: 3,
      maxEnergy: 20,
      adrenaline: 0,
      adrenalineCap: 4,
      bar: bar(activating),
      belt: belt(activating),
      activation: activating
        ? {
            slot: 2,
            skill: 3,
            name: "Charge",
            ticks: 1,
            total: 2,
            target: { tile: false, entity: FIGHT.runt },
            area: [],
          }
        : null,
      chips: CHIPS,
      knocked: false,
    },
    goblins: GOBLINS,
    traps: [],
  };
}
