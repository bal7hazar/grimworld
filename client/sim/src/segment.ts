// One segment of a played batch (ENG-07, D-248): the mirror of `SegmentTrait::run`
// (`contracts/logic/src/types/play.cairo`, `impl SegmentImpl`), held equal to it by
// `contracts/logic/vectors/segment.jsonl`. Its composition, in Cairo's order: the owed ticks'
// fold, each action against the state it meets, `max(1, ticks)` its cost, the `cost > weight`
// check, the `ran` rule, the Move checked for a reveal before its ticks, the stop after a reveal
// Move, and `fits`. The rules it calls are the other mirrors': `batch.ts` (`admit`),
// `movement.ts` (the board's origin, a position, a Move's ticks), `reveal.ts` (sight's chunks),
// `window.ts` (a Move's tile, an open tile). The rules, their edges and their reasons are the
// Cairo module's documentation.
//
// Only what the table covers is mirrored: no goblin, no class called, every tick on the fast path
// (`TickTrait::idle`: the clock advances and the turned flag clears). Where `run` reaches a
// branch the table has no case for, the mirror throws `NotMirrored`, never a guess: a defeat, the
// combat arm (Attack, Skill, Item through `ActionLibrary`), ticks through `TickLibrary`, a tick
// that would regenerate (`MemberTrait::regenerate` changing health), a companion, an armed trap,
// a tile occupied by a goblin, a Move past the window's edge, a held `MOVEMENT` effect. The goblin
// records of `fits` (new records, first records, the untouched-engaged skip) change only through
// those branches, so `fits` here is `admit` with no fresh record. Energy and adrenaline, which a
// tick also regenerates, are not part of the mirror's world.

import { admit } from "./batch";
import { add, panic, u32, u8 } from "./felt";
import { ORIGIN, board as origin_board, move_ticks, origin, position } from "./movement";
import { chunks as sight } from "./reveal";
import { FAR, HEIGHT, WIDTH, neighbor, shape, shapes } from "./window";

/** An action may run only while the clock is at most this (`types::LAST_TICK`, E-4). */
export const LAST_TICK = 0xfffffff - 0xffff - 10;

/** `MemberState.flags` (`types::tick::flag`). */
export const flag = { TURNED: 1, INSTANT: 2, HIT: 8, HALVED: 16 } as const;
/** The flags a tick's step 0 keeps. */
const KEPT = 0xff - flag.TURNED - flag.INSTANT - flag.HIT;

/** `types::tick::status`. */
export const status = { INSIDE: 0, DOWN: 1, GONE: 2 } as const;

/** `Illegal`, by the `Serde` index of the variants a segment returns. */
export const Illegal = {
  Clock: 0,
  Absent: 1,
  Knocked: 2,
  Turned: 3,
  Kind: 13,
  Blocked: 14,
} as const;
export type Illegal = (typeof Illegal)[keyof typeof Illegal];

/** A branch of `run` the vectors do not cover: the mirror stops there rather than guess. */
export class NotMirrored extends Error {
  constructor(branch: string) {
    super(`not mirrored: ${branch}`);
    this.name = "NotMirrored";
  }
}

/** The branches `NotMirrored` names. */
export const unported = {
  DEFEATED: "the adventurer defeated (world.defeated)",
  COMBAT: "the combat arm (Attack, Skill, Item through ActionLibrary)",
  TICK_LIBRARY: "ticks through TickLibrary (a goblin in the window, or not calm)",
  REGENERATION: "a tick that regenerates (health regen, a condition, effect pips, health over max)",
  COMPANIONS: "a world of more than one member (companions block and regenerate)",
  TRAP: "an armed trap on the tile entered",
  OCCUPIED: "Blocked by a tile a goblin occupies",
  EDGE: "Blocked by a missing neighbour (the window's edge)",
  MOVEMENT: "a held MOVEMENT effect (FX-18)",
} as const;

/** An action of a batch (`actions::Action`); the combat ones only to be refused. */
export type Action =
  | { kind: "move"; direction: number }
  | { kind: "turn"; direction: number }
  | { kind: "wait" }
  | { kind: "attack" | "skill" | "item" }
  | { kind: "interact"; tile: number };

/** The adventurer (member 0) as a segment reads it. */
export type Adventurer = {
  /** The location's tile. */
  x: number;
  y: number;
  facing: number;
  status: number;
  health: number;
  max_health: number;
  /** What a tick's regeneration reads (`MemberTrait::regenerate`): refused when it would act. */
  health_regen: number;
  /** The deadlines of Bleeding, Poison and Burning (0: none; held while `t ≤` it). */
  bleeding: number;
  poison: number;
  burning: number;
  /** The held effects' regeneration pips (`effect_regen`) and their deadlines. */
  effects: readonly { pips: number; deadline: number }[];
  /** Crippled's deadline (0: none). */
  crippled: number;
  /** The end of a knock-down (0: none). */
  knocked: number;
  flags: number;
  /** Whether an effect slot holds a `MOVEMENT` effect (FX-18): not mirrored. */
  movement: boolean;
};

/** A location's tile. */
export type Place = { x: number; y: number };

/** The world a segment runs on: the adventurer alone, and what the mirror refuses. */
export type World = {
  clock: number;
  adventurer: Adventurer;
  /** The members, the adventurer with them: a companion is refused. */
  members: number;
  /** The living goblins' tiles: one in the window sends the ticks to `TickLibrary`. */
  goblins: readonly Place[];
  /** `WorldTrait::calm`: no goblin in the awake set and no member activating. */
  calm: boolean;
  defeated: boolean;
  /** The tiles of an armed trap (`AiTrait::armed` on the call's ground). */
  armed: readonly Place[];
};

/** `play::Area`: the chunks a segment's windows may overlap. */
export type Area = {
  width: number;
  height: number;
  /** Bit `15 cy + cx` for each chunk that is not void. */
  known: bigint;
  /** Bit `15 cy + cx` for each chunk revealed. */
  revealed: bigint;
  /** `(chunk, walkable bits)` of the revealed chunks: bit `15 ly + lx`, 1 walkable. */
  chunks: readonly (readonly [number, bigint])[];
  /** The goblins whose records the invocation's earlier segments changed. */
  changed: readonly number[];
  ran: boolean;
};

/** `play::Done`: how a segment ended. */
export type Done = {
  played: number;
  weight: number;
  owed: number;
  reveal: boolean;
  illegal: Illegal | undefined;
  heavy: boolean;
  changed: number[];
  undo: boolean;
};

/** A window's walkable tiles and its origin, each plus `ORIGIN` (`executor::Board`). */
export type Board = { open: bigint; x: number; y: number };

/** Why an action did not run (`play::Halt`). */
type Halt = { illegal: Illegal } | "heavy";
type Result = { ticks: number } | { halt: Halt };

const has = (bits: bigint, index: number): boolean => ((bits >> BigInt(index)) & 1n) === 1n;
const u8add = (a: number, b: number): number => Number(add(u8, BigInt(a), BigInt(b)));
const u32add = (a: number, b: number): number => Number(add(u32, BigInt(a), BigInt(b)));

/** The window's interior, its ring cleared (`play::INTERIOR`). */
const INTERIOR = (0xfff9fff3ffe7ffcfff9fff3fn << 128n) | 0xfe7ffcfff9fff3ffe7ffcfff9fff0000n;

/**
 * `SegmentTrait::piece`: chunk `(cx, cy)` in the assembly: `undefined` when void, its walkable
 * tiles when revealed, all wall (0) when not.
 */
function piece(area: Area, cx: number, cy: number): bigint | undefined {
  if (cx < 0 || cy < 0 || cx >= 15 || cy >= 15) return undefined;
  const chunk = cy * 15 + cx;
  if (!has(area.known, chunk)) return undefined;
  if (!has(area.revealed, chunk)) return 0n;
  for (const [c, bits] of area.chunks) {
    if (c === chunk) return bits;
  }
  return 0n;
}

/**
 * `hexx`'s `AssemblyTrait::assemble`: bit `15 dy + dx` of the window is the tile
 * `(15 cx + ox + dx, 15 cy + oy + dy)`, read from `chunks` (`(cx, cy)`, `(cx + 1, cy)`,
 * `(cx, cy + 1)`, `(cx + 1, cy + 1)`; `undefined` void, wall). Tile by tile, where `hexx` shifts
 * masked rectangles.
 */
function assemble(chunks: readonly (bigint | undefined)[], ox: number, oy: number): bigint {
  let open = 0n;
  for (let dy = 0; dy < HEIGHT; dy++) {
    for (let dx = 0; dx < WIDTH; dx++) {
      const [gx, gy] = [ox + dx, oy + dy];
      const chunk = chunks[(gx >= 15 ? 1 : 0) + (gy >= 15 ? 2 : 0)];
      if (chunk !== undefined && has(chunk, 15 * (gy % 15) + (gx % 15))) {
        open |= 1n << BigInt(WIDTH * dy + dx);
      }
    }
  }
  return open;
}

/** `SegmentTrait::board`: the board of the window of the adventurer on `(x, y)`. */
export function board(area: Area, x: number, y: number): Board {
  const { cx, cy, ox, oy } = origin(x, y);
  // `AssemblyAssert::assert_even_origin`, whose `odd` (`cy` odd) is all `assemble` reads of it: it
  // never moves a bit, and `origin` always gives an even origin row
  if (oy % 2 !== (cy + 2) % 2) panic("Assembly: odd origin");
  const parts = [
    piece(area, cx, cy),
    piece(area, cx + 1, cy),
    piece(area, cx, cy + 1),
    piece(area, cx + 1, cy + 1),
  ];
  return { open: assemble(parts, ox, oy) & INTERIOR, ...origin_board(x, y) };
}

/** `SegmentTrait::chunk`: the adventurer's chunk, `15 cy + cx`. */
function chunk(at: Adventurer): number {
  return u8add(Math.floor(at.y / 15) * 15, Math.floor(at.x / 15));
}

/** `SegmentTrait::to_reveal`: whether sight from the adventurer touches a chunk not yet revealed. */
function to_reveal(area: Area, at: Adventurer): boolean {
  return sight(at.x, at.y, area.width, area.height).some(
    (c) => has(area.known, c) && !has(area.revealed, c),
  );
}

const alive = (at: Adventurer): boolean => at.status === status.INSIDE && at.health > 0;
/** `MemberTrait::can_act`: not knocked down at `t0`. */
const can_act = (at: Adventurer, t0: number): boolean => !(t0 <= at.knocked);

/** `SegmentTrait::idle`: whether the ticks take the fast path. */
function idle(world: World, on: Board): boolean {
  if (!world.calm) return false;
  return world.goblins.every(({ x, y }) => position(on, x, y) >= FAR);
}

/**
 * Whether `MemberTrait::regenerate` at tick `t` may change the adventurer's health: any pip source
 * held (its health regen, Bleeding, Poison, Burning, an effect's pips), or health above its max
 * (`heal` clamps even 0 pips).
 */
function regenerates(at: Adventurer, t: number): boolean {
  return (
    at.health_regen !== 0 ||
    t <= at.bleeding ||
    t <= at.poison ||
    t <= at.burning ||
    at.effects.some(({ pips, deadline }) => pips !== 0 && t <= deadline) ||
    at.health > at.max_health
  );
}

/** `SegmentTrait::ticks`: `n` ticks on the fast path (`TickTrait::idle`), none that regenerates. */
function ticks(world: World, on: Board, n: number): void {
  if (n === 0 || world.defeated) return;
  if (!idle(world, on)) throw new NotMirrored(unported.TICK_LIBRARY);
  for (let k = 0; k < n && !world.defeated; k++) {
    // A member inside at 0 health is down: the tick does not advance, the world is defeated
    if (world.adventurer.status === status.INSIDE && world.adventurer.health === 0) {
      throw new NotMirrored(unported.DEFEATED);
    }
    world.clock = u32add(world.clock, 1);
    if (alive(world.adventurer) && regenerates(world.adventurer, world.clock)) {
      throw new NotMirrored(unported.REGENERATION);
    }
    world.adventurer.flags &= KEPT;
  }
}

/** `SegmentTrait::step`: a Move of the adventurer toward `direction`; its ticks. */
function step(world: World, on: Board, direction: number, weight: number): Result {
  const c = world.clock;
  if (c > LAST_TICK) return { halt: { illegal: Illegal.Clock } };
  const at = world.adventurer;
  if (!alive(at)) return { halt: { illegal: Illegal.Absent } };
  const t0 = u32add(c, 1);
  if (!can_act(at, t0)) return { halt: { illegal: Illegal.Knocked } };
  const from = position(on, at.x, at.y);
  const to = neighbor(from, direction);
  if (to === undefined) throw new NotMirrored(unported.EDGE);
  if (shape(on.open, shapes.SINGLE, to) === 0n) return { halt: { illegal: Illegal.Blocked } };
  if (world.goblins.some(({ x, y }) => position(on, x, y) === to)) {
    throw new NotMirrored(unported.OCCUPIED);
  }
  if (at.movement) throw new NotMirrored(unported.MOVEMENT);
  const n = move_ticks(at.crippled, t0, false);
  if (n > weight) return { halt: "heavy" };
  at.x = on.x + (to % WIDTH) - ORIGIN;
  at.y = on.y + Math.floor(to / WIDTH) - ORIGIN;
  at.facing = direction;
  if (world.armed.some(({ x, y }) => x === at.x && y === at.y)) {
    throw new NotMirrored(unported.TRAP);
  }
  return { ticks: n };
}

/** `SegmentTrait::turn`: once between two ticks, its facing set, 0 ticks. */
function turn(world: World, direction: number, weight: number): Result {
  if (weight === 0) return { halt: "heavy" };
  if (world.clock > LAST_TICK) return { halt: { illegal: Illegal.Clock } };
  const at = world.adventurer;
  if (!alive(at)) return { halt: { illegal: Illegal.Absent } };
  if (!can_act(at, u32add(world.clock, 1))) return { halt: { illegal: Illegal.Knocked } };
  if ((at.flags & flag.TURNED) !== 0) return { halt: { illegal: Illegal.Turned } };
  at.flags |= flag.TURNED;
  at.facing = direction;
  return { ticks: 0 };
}

/** `SegmentTrait::wait`: 1 tick, legal while the adventurer stands and the clock allows. */
function wait(world: World): Result {
  if (world.clock > LAST_TICK) return { halt: { illegal: Illegal.Clock } };
  if (!alive(world.adventurer)) return { halt: { illegal: Illegal.Absent } };
  return { ticks: 1 };
}

const copy = (world: World): World => ({ ...world, adventurer: { ...world.adventurer } });

/**
 * `SegmentTrait::run`: `owed` ticks first, then `actions` within `weight`. Returns the world after
 * (a copy: `world` is not changed) and how the segment ended.
 */
export function run(
  world: World,
  area: Area,
  actions: readonly Action[],
  owed: number,
  weight: number,
): { world: World; done: Done } {
  if (world.members !== 1) throw new NotMirrored(unported.COMPANIONS);
  const out = copy(world);
  let on = board(area, out.adventurer.x, out.adventurer.y);
  const changed = [...area.changed];
  const done: Done = {
    played: 0,
    weight,
    owed: 0,
    reveal: false,
    illegal: undefined,
    heavy: false,
    changed: [],
    undo: false,
  };
  // The last segment's Move's owed ticks
  ticks(out, on, owed);
  const start = chunk(out.adventurer);
  for (const next of actions) {
    if (out.defeated) throw new NotMirrored(unported.DEFEATED);
    let result: Result;
    switch (next.kind) {
      case "move":
        result = step(out, on, next.direction, done.weight);
        break;
      case "turn":
        result = turn(out, next.direction, done.weight);
        break;
      case "wait":
        result = wait(out);
        break;
      case "interact":
        result = { halt: { illegal: Illegal.Kind } };
        break;
      default:
        throw new NotMirrored(unported.COMBAT);
    }
    if ("halt" in result) {
      if (result.halt === "heavy") done.heavy = true;
      else done.illegal = result.halt.illegal;
      break;
    }
    const n = result.ticks;
    const cost = n === 0 ? 1 : n;
    if (cost > done.weight) {
      done.heavy = true;
      break;
    }
    // A Move that brings sight onto a chunk to reveal, or the adventurer into another chunk, ends
    // the segment before its ticks
    let reveal = false;
    if (next.kind === "move") {
      reveal = to_reveal(area, out.adventurer) || chunk(out.adventurer) !== start;
      if (!reveal) on = board(area, out.adventurer.x, out.adventurer.y);
    }
    if (!reveal) ticks(out, on, n);
    const ran = area.ran || done.played > 0;
    // `fits` with no goblin: no record is fresh
    const left = admit(changed.length, 0, 0, cost, ran, done.weight);
    if (left === undefined) {
      done.heavy = true;
      done.undo = true;
      break;
    }
    done.weight = left;
    done.played = u8add(done.played, 1);
    if (reveal) {
      done.owed = n;
      done.reveal = true;
      break;
    }
  }
  done.changed = changed;
  return { world: out, done };
}
