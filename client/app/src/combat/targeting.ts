/**
 * Targeting (CLI-05 brief §4.1–§4.3): what an armed slot addresses, the tiles it reaches, the tiles
 * in range but out of sight, a TRAP skill's tiles, the tiles its entries' shapes touch and the actors
 * they take. Nothing here re-derives a rule: the addressing is client/sim's `addressing`, a tile or
 * an actor is tinted only when client/sim's `aim` accepts it (`Illegal.Reach` is distance and line of
 * sight), a trap's tile only when `spot` finds it a place (`Illegal.Trap`), a shape's tiles are
 * `shape`'s.
 *
 * Positions are the window's (`15 y + x` of the board), converted to the location's tiles here.
 */

import {
  ABSENT_LANE,
  type Actor,
  type Carrier,
  type Ground,
  ORIGIN,
  type SegmentBoard,
  type Sheets,
  type World,
  addressing,
  aiState,
  aim,
  filter,
  goblinPlace,
  kind,
  memberPlace,
  position,
  reach,
  shape,
  shapes,
  skillKind,
  spot,
  target,
} from "@grimworld/sim";
import { addressingName, barCarrier, potionAt } from "./bar";
import type { Addressing, Armed } from "./state";
import type { Tile } from "../render/view";

/** What targeting reads: the world client/sim loaded, its sheets, the window's board, the ground. */
export interface CombatWorld {
  readonly world: World;
  readonly sheets: Sheets;
  readonly board: SegmentBoard;
  readonly ground: Ground;
}

/** What an armed slot shows on the map before a target is chosen (§4.1, §4.3). */
export interface Aiming {
  readonly addressing: Addressing;
  readonly range: number;
  /** The tiles the action class accepts as the target, or that hold an actor it accepts. */
  readonly reach: readonly Tile[];
  /** Walkable tiles in range it refuses: out of sight, or (a trap) where no trap can go. */
  readonly greyed: readonly Tile[];
  /** The actors that can be chosen (`FOE`: goblins; `ALLY`: members; `SELF`: the adventurer). */
  readonly marked: readonly number[];
  /** A TRAP skill: its tiles are `spot`'s. */
  readonly trap: boolean;
}

/** The tiles a carrier's entries touch around a centre, and the actors they take (§4.2). */
export interface Area {
  readonly tiles: readonly Tile[];
  readonly marked: readonly number[];
}

/** Every tile of the window walkable: `reach` on it is the range alone, walls ignored. */
const EVERY = (1n << 240n) - 1n;
const WINDOW = 240;
const ADVENTURER: Actor = { kind: "M", i: 0 };

/** The location's tile of the window's position `p` (`BoardTrait::position` read backwards). */
export const tileOf = (board: SegmentBoard, p: number): Tile => ({
  x: board.x + (p % 15) - ORIGIN,
  y: board.y + Math.floor(p / 15) - ORIGIN,
});

/** The window's position of a location's tile; 255 outside. */
export const positionOf = (board: SegmentBoard, tile: Tile): number =>
  position(board, tile.x, tile.y);

/** A tile as an action's `Target.value`: `x + 256 y` (`BoardTrait::tile`). */
export const tileValue = (tile: Tile): number => tile.x + 256 * tile.y;

/** A bar skill's or a belt potion's carrier (never a weapon's). */
export type SlotCarrier = Exclude<Carrier, { kind: "Weapon" }>;

/** The carrier of an armed slot; null for an empty one. */
export function carrierOf(cw: CombatWorld, armed: Armed): SlotCarrier | null {
  const member = cw.world.members[0]!;
  if (armed.kind === "skill") {
    if (member.bar_at[armed.slot] === ABSENT_LANE) return null;
    return barCarrier(member, armed.slot);
  }
  const at = potionAt(member, cw.sheets, armed.slot);
  return at < 0 ? null : { kind: "Potion", at, slot: armed.slot };
}

/** The adventurer's window position. */
export function adventurerAt(cw: CombatWorld): number {
  const { x, y } = memberPlace(cw.world.members[0]!);
  return position(cw.board, x, y);
}

/** Every actor alive in the window with its entity and position: members, then goblins. */
function actorsOf(cw: CombatWorld): { entity: number; member: boolean; at: number }[] {
  const out: { entity: number; member: boolean; at: number }[] = [];
  cw.world.members.forEach((m, i) => {
    if (m.status === 0 && m.health > 0) {
      const { x, y } = memberPlace(m);
      out.push({ entity: i, member: true, at: position(cw.board, x, y) });
    }
  });
  for (const g of cw.world.goblins) {
    if (g.ai < aiState.DEAD && g.health > 0) {
      const { x, y } = goblinPlace(g);
      out.push({ entity: g.entity, member: false, at: position(cw.board, x, y) });
    }
  }
  return out.filter((a) => a.at < WINDOW);
}

/** Whether client/sim's `aim` accepts `value` as the armed carrier's target. */
function accepts(cw: CombatWorld, carrier: Carrier, tile: boolean, value: number): boolean {
  const from = adventurerAt(cw);
  const out = aim(cw.world, cw.sheets, cw.board, ADVENTURER, from, carrier, { tile, value });
  return typeof out !== "number";
}

/** A skill carrier's first entry is a TRAP. */
const isTrap = (cw: CombatWorld, carrier: Carrier): boolean =>
  carrier.kind === "Skill" && cw.sheets.entries[3 * carrier.at]!.kind === kind.TRAP;

/** What the armed slot shows before its target is chosen (§4.1, §4.3); null for an empty slot. */
export function aiming(cw: CombatWorld, armed: Armed): Aiming | null {
  const carrier = carrierOf(cw, armed);
  if (carrier === null) return null;
  const [addressed, range] = addressing(cw.world, cw.sheets, ADVENTURER, carrier);
  const from = adventurerAt(cw);
  const open = cw.board.open;
  const trap = isTrap(cw, carrier);
  const reachTiles: Tile[] = [];
  const greyed: Tile[] = [];
  let marked: number[] = [];
  if (addressed === target.SELF) {
    marked = [0];
  } else {
    for (let p = 0; p < WINDOW; p++) {
      if (!reach(EVERY, from, p, range)) continue;
      const walkable = ((open >> BigInt(p)) & 1n) === 1n;
      const tile = tileOf(cw.board, p);
      let tinted: boolean;
      if (addressed === target.TILE) {
        tinted =
          accepts(cw, carrier, true, tileValue(tile)) &&
          (!trap || spot(cw.world, cw.board, cw.ground, p) !== undefined);
      } else {
        tinted = reach(open, from, p, range);
      }
      if (tinted) reachTiles.push(tile);
      else if (walkable) greyed.push(tile);
    }
    if (addressed !== target.TILE) {
      const wanted = addressed === target.ALLY;
      marked = actorsOf(cw)
        .filter((a) => a.member === wanted && accepts(cw, carrier, false, a.entity))
        .map((a) => a.entity);
    }
  }
  return {
    addressing: addressingName(addressed),
    range,
    reach: reachTiles,
    greyed,
    marked,
    trap,
  };
}

/**
 * The tiles the armed carrier's entries touch with `centre` as its target (§4.2), and the actors on
 * them its entries take by their filter. A `SELF` entry centres on the adventurer, any other on
 * `centre`; an attack skill's implicit hit is the target's tile. A TRAP, a hit modifier and an empty
 * entry touch nothing; `DISC_2` and `DISC_3` touch nothing either (the contracts refuse them, and
 * client/sim's `near` computes none).
 */
export function areaOf(cw: CombatWorld, armed: Armed, centre: Tile): Area {
  const carrier = carrierOf(cw, armed);
  if (carrier === null) return { tiles: [], marked: [] };
  const open = cw.board.open;
  const self = adventurerAt(cw);
  const at = positionOf(cw.board, centre);
  const entries =
    carrier.kind === "Skill"
      ? [0, 1, 2].map((k) => cw.sheets.entries[3 * carrier.at + k]!)
      : [cw.sheets.potion_entries[carrier.at]!];
  let bits = 0n;
  const filters = new Set<number>();
  if (carrier.kind === "Skill" && cw.sheets.skills[carrier.at]!.kind === skillKind.ATTACK) {
    if (at < WINDOW) bits |= shape(open, shapes.SINGLE, at);
    filters.add(filter.FOES);
  }
  for (const e of entries) {
    if (e.kind === kind.EMPTY) break;
    if (e.kind === kind.TRAP || e.kind === kind.ATTACK_BONUS || e.kind === kind.HIT_PENETRATION) {
      continue;
    }
    if (e.shape < shapes.SINGLE || e.shape > shapes.DISC_1) continue;
    const c = e.target === target.SELF ? self : at;
    if (c >= WINDOW) continue;
    bits |= shape(open, e.shape, c);
    filters.add(e.filter);
  }
  const tiles: Tile[] = [];
  for (let p = 0; p < WINDOW; p++) if (((bits >> BigInt(p)) & 1n) === 1n) tiles.push(tileOf(cw.board, p));
  const marked = actorsOf(cw)
    .filter((a) => ((bits >> BigInt(a.at)) & 1n) === 1n)
    .filter((a) => filters.has(a.member ? filter.ALLIES : filter.FOES))
    .map((a) => a.entity);
  return { tiles, marked };
}
