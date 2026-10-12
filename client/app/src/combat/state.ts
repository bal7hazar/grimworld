/**
 * What the combat screens read (CLI-05 brief §2–§6): the adventurer's bar, belt, gauges, activation,
 * conditions and held effects, the goblins', the traps on the ground and the clock, as data. It
 * decides no rule: in the chain mode `fromWords.ts` fills it from client/sim's loaders, every
 * figure read by client/sim's own function; in the sandbox `fixture.ts` writes it by hand.
 *
 * Tiles are the location's, in global offset coordinates, as `render/view.ts`'s.
 */

import type { Mark, Tile } from "../render/view";

/**
 * A bar slot's one state (§2.2), in the order `act` refuses a skill: "not now" first (`Knocked`, or
 * activating another skill), then empty, the weapon (`Kind`), recharging, adrenaline, energy.
 * `unavailable` is a carrier client/sim cannot mirror (`NotMirrored`, `unported.MIXED`, §4.4).
 */
export type SlotState =
  | "empty"
  | "not-now"
  | "activating"
  | "unavailable"
  | "wrong-weapon"
  | "recharging"
  | "short-adrenaline"
  | "short-energy"
  | "ready";

/** What a carrier addresses (`executor.ts`'s `target`), in words. */
export type Addressing = "self" | "foe" | "ally" | "tile";

/** A skill's kind as the monogram's ground shows it (§8). */
export type SkillLook = "attack" | "spell" | "stance" | "shout" | "trap" | "other";

/** A potion's look (§8): what fills its flask. */
export type PotionLook = "heal" | "regeneration" | "other";

/** A skill on the bar, its sheet's figures as the screen shows them. */
export interface SkillSheetView {
  readonly id: number;
  /** Its name when one is known (the fixture's; CLI-11d's `names.ts` on chain). */
  readonly name?: string;
  readonly look: SkillLook;
  /** Energy it costs now, whole points (client/sim's `energy`, Fieldcraft and glyphs taken off). */
  readonly energy: number;
  /** Strikes of adrenaline it costs (`adrenaline`, in strikes of 4 quarters). */
  readonly strikes: number;
  /** Activation in ticks; 0 is instant. */
  readonly activation: number;
  readonly recharge: number;
  readonly range: number;
  readonly addressing: Addressing;
}

export interface BarSlot {
  /** 0–7. */
  readonly slot: number;
  /** The skill, or null for an empty slot. */
  readonly skill: SkillSheetView | null;
  readonly state: SlotState;
  /**
   * The ticks the state counts down: a recharge's `recharge − clock`, an activation's
   * `act_deadline − clock`; null for the other states.
   */
  readonly ticks: number | null;
}

/** A belt slot's state (§3): has some, none left (`Belt`), not now, or no item. */
export type BeltState = "empty" | "some" | "none-left" | "not-now";

export interface BeltSlot {
  /** 0–3. */
  readonly slot: number;
  /** The potion's id, or null for a slot with no item. */
  readonly item: number | null;
  readonly name?: string;
  readonly look: PotionLook;
  readonly count: number;
  readonly state: BeltState;
  readonly addressing: Addressing | null;
  readonly range: number;
}

/** A condition or held effect as a chip (§6.1). */
export interface Chip {
  readonly kind: "condition" | "effect";
  /** The letter that carries its meaning (`B`, `P`, `F`, `C`, `K`, `R`, `▣`, an initial). */
  readonly letter: string;
  /** Its name in words, for an inspection and the log. */
  readonly name: string;
  /** `deadline − clock`; null for an effect that lasts by charges only (`MAX_CLOCK`). */
  readonly ticks: number | null;
  /** Charges left, for an effect that holds some (BLOCK's blocks); null otherwise. */
  readonly charges: number | null;
  /** A REGENERATION's pips a tick, signed; null otherwise. */
  readonly pips: number | null;
  /** An effect's carrier, a skill's or a potion's id; null for a condition. */
  readonly source: { readonly potion: boolean; readonly id: number } | null;
}

/** What an activation is aimed at: an entity, or a tile (a member's `act_tile`). */
export type Aimed =
  { readonly tile: false; readonly entity: number } | { readonly tile: true; readonly at: Tile };

/** An activation in progress (§5). */
export interface ActivationView {
  /** A member's bar slot, a goblin's caste slot. */
  readonly slot: number;
  readonly skill: number;
  readonly name?: string;
  /** `act_deadline − clock`, at least 1 while it lasts. */
  readonly ticks: number;
  /** The skill's whole activation, the ring's full turn. */
  readonly total: number;
  readonly target: Aimed;
  /** The tiles a `RING_1` entry centred on the caster touches (a shout), else none. */
  readonly area: readonly Tile[];
}

export interface CombatAdventurer {
  readonly entity: number;
  readonly tile: Tile;
  readonly health: number;
  readonly maxHealth: number;
  /** Whole points (the words hold thirds). */
  readonly energy: number;
  readonly maxEnergy: number;
  /** Strikes (the words hold quarters). */
  readonly adrenaline: number;
  readonly adrenalineCap: number;
  readonly bar: readonly BarSlot[];
  readonly belt: readonly BeltSlot[];
  readonly activation: ActivationView | null;
  readonly chips: readonly Chip[];
  /** Knocked down at the next tick (`can_act` false): the bar is "not now", the sprite flat. */
  readonly knocked: boolean;
}

export interface GoblinActivationView extends ActivationView {
  /** A ready slot of the bar can interrupt it, and the goblin is in that skill's reach (§5). */
  readonly interruptible: boolean;
}

export interface CombatGoblin {
  readonly entity: number;
  readonly caste: number;
  readonly casteName?: string;
  readonly tile: Tile;
  readonly health: number;
  readonly maxHealth: number;
  readonly alive: boolean;
  readonly mark: Mark | null;
  readonly activation: GoblinActivationView | null;
  /** `act_slot` 254 with its deadline not passed. */
  readonly recovering: boolean;
  readonly chips: readonly Chip[];
  readonly knocked: boolean;
}

/** A trap on the ground: a terrain trap, or one an actor placed. */
export interface CombatTrap {
  readonly tile: Tile;
  readonly placed: boolean;
}

export interface CombatState {
  readonly clock: number;
  readonly adventurer: CombatAdventurer;
  readonly goblins: readonly CombatGoblin[];
  readonly traps: readonly CombatTrap[];
}

/**
 * The names the screens and the log write (Q-1: the registry holds none). CLI-11d's `names.ts` gives
 * the seed's; `DEFAULT_NAMES` stands in until then.
 */
export interface Names {
  skill(id: number): string;
  potion(id: number): string;
  caste(id: number): string;
}

/** The art's castes, by order, the seed's caste ids (1 …) wrapping over them, as `chain/world.ts` draws them. */
const CASTES = ["runt", "skirmisher", "slinger", "shaman", "hobgoblin"] as const;

export const DEFAULT_NAMES: Names = {
  skill: (id) => `Skill ${id}`,
  potion: (id) => `Potion ${id}`,
  caste: (id) => CASTES[(Math.max(id, 1) - 1) % CASTES.length] ?? "goblin",
};

/** A slot armed on the bar or the belt (§2.4, §3). */
export type Armed =
  | { readonly kind: "skill"; readonly slot: number }
  | { readonly kind: "item"; readonly slot: number };
