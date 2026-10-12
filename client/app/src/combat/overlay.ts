/**
 * What the map draws of combat (CLI-05 brief §4.2, §4.3, §5, §6.1): `CombatOverlay`, the contract
 * between CLI-05c, which fills `ViewState.combat`, and CLI-05d, which draws it. It is computed from a
 * `CombatState` and the armed slot's aiming (`targeting.ts` in the chain mode, the placeholders in the
 * sandbox): it decides nothing, it places what those give on the location's tiles.
 */

import type { Tile } from "../render/view";
import type { CombatState } from "./state";

/** An activation in progress, on the map (§5). */
export interface OverlayActivation {
  /** The caster's entity (the adventurer's 0, a goblin's id). */
  readonly actor: number;
  readonly tile: Tile;
  readonly ticks: number;
  readonly total: number;
  /** The target's tile, for the line from the caster; null when the target is the caster or gone. */
  readonly target: Tile | null;
  /** A shout's ring of tiles, tinted faintly. */
  readonly area: readonly Tile[];
  /** A ready slot can interrupt it now (a goblin's only). */
  readonly interruptible: boolean;
}

/** A goblin's condition letters under its feet (§6.1): at most three, then `+`. */
export interface OverlayLetters {
  readonly actor: number;
  readonly tile: Tile;
  readonly letters: readonly string[];
  readonly more: boolean;
}

export interface CombatOverlay {
  /** The tiles the armed slot reaches, tinted. */
  readonly range: readonly Tile[];
  /** The tiles in range it refuses (out of sight; a trap's tiles that take none), greyed. */
  readonly greyed: readonly Tile[];
  /** The tiles the carrier's shapes touch around the previewed target. */
  readonly area: readonly Tile[];
  /** The tiles of the actors marked as targets (who can be chosen, or who the area takes). */
  readonly targets: readonly Tile[];
  readonly activations: readonly OverlayActivation[];
  readonly letters: readonly OverlayLetters[];
  /** The tiles of the actors knocked down: their sprite is laid flat. */
  readonly knocked: readonly Tile[];
}

/** The armed slot's aiming as the overlay places it: `targeting.ts`'s `Aiming` and `Area` fit it. */
export interface OverlayAim {
  readonly reach: readonly Tile[];
  readonly greyed: readonly Tile[];
  readonly marked: readonly number[];
  /** The area around the previewed target, if one is previewed. */
  readonly area?: { readonly tiles: readonly Tile[]; readonly marked: readonly number[] };
}

/** The most letters drawn under a goblin before a `+` (§6.1). */
export const MAX_LETTERS = 3;

/** The map's combat overlay of a state, and of the armed slot's aiming if one is armed. */
export function combatOverlay(state: CombatState, aim: OverlayAim | null = null): CombatOverlay {
  const tiles = new Map<number, Tile>([[state.adventurer.entity, state.adventurer.tile]]);
  const living = state.goblins.filter((g) => g.alive);
  for (const g of living) tiles.set(g.entity, g.tile);
  const tileOf = (entity: number): Tile | null => tiles.get(entity) ?? null;
  const activations: OverlayActivation[] = [];
  const { adventurer } = state;
  if (adventurer.activation) {
    const a = adventurer.activation;
    activations.push({
      actor: adventurer.entity,
      tile: adventurer.tile,
      ticks: a.ticks,
      total: a.total,
      target: a.target.tile
        ? a.target.at
        : a.target.entity === adventurer.entity
          ? null
          : tileOf(a.target.entity),
      area: a.area,
      interruptible: false,
    });
  }
  for (const g of living) {
    const a = g.activation;
    if (!a) continue;
    activations.push({
      actor: g.entity,
      tile: g.tile,
      ticks: a.ticks,
      total: a.total,
      target: a.target.tile
        ? a.target.at
        : a.target.entity === g.entity
          ? null
          : tileOf(a.target.entity),
      area: a.area,
      interruptible: a.interruptible,
    });
  }
  const letters = living.flatMap((g) => {
    const conditions = g.chips.filter((c) => c.kind === "condition").map((c) => c.letter);
    if (conditions.length === 0) return [];
    return [
      {
        actor: g.entity,
        tile: g.tile,
        letters: conditions.slice(0, MAX_LETTERS),
        more: conditions.length > MAX_LETTERS,
      },
    ];
  });
  const knocked = [
    ...(adventurer.knocked ? [adventurer.tile] : []),
    ...living.filter((g) => g.knocked).map((g) => g.tile),
  ];
  const marked = [...new Set([...(aim?.marked ?? []), ...(aim?.area?.marked ?? [])])];
  return {
    range: aim?.reach ?? [],
    greyed: aim?.greyed ?? [],
    area: aim?.area?.tiles ?? [],
    targets: marked.map(tileOf).filter((t): t is Tile => t !== null),
    activations,
    letters,
    knocked,
  };
}
