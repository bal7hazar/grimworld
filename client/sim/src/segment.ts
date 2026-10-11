// One segment of a played batch (ENG-07, D-248): the mirror of `SegmentTrait::run`
// (`contracts/logic/src/types/play.cairo`, `impl SegmentImpl`), held equal to it by
// `contracts/logic/vectors/segment.jsonl` and `segment2.jsonl` (CLI-02g-A, D-254). Its
// composition, in Cairo's order: the owed ticks' fold, each action against the state it meets,
// `max(1, ticks)` its cost, the `cost > weight` check, the `ran` rule, the Move checked for a
// reveal before its ticks, the stop after a reveal Move, the goblin records of `fits`, and
// `world.defeated` ending the loop. The rules it calls are the other mirrors': `batch.ts`
// (`admit`), `movement.ts` (the board's origin, a position, a Move's ticks), `reveal.ts` (sight's
// chunks), `window.ts` (a Move's tile, an open tile). The rules, their edges and their reasons are
// the Cairo module's documentation.
//
// It runs on the real world: the words that cross the calls (`segment/words.ts`), the area and the
// ground. **Native**, as `run` holds them: the loop and its branches, Move (open, occupied by a
// living member or goblin, Crippled and a held `MOVEMENT` effect), Turn, Wait, the followed window,
// the trap lookup (`AiTrait::armed`) and the words it sends, the ticks' fast path
// (`TickTrait::idle`: the clock, the flags, the members' regeneration out of combat, the defeat
// check) and `idle`'s choice, the records of `fits`. **Behind the seam** (`segment/classes.ts`):
// `TickLibrary::ticks`, `ActionLibrary::act` and `TrapLibrary::trigger`, whose words and ground are
// loaded back as `SegmentTrait::reload` loads them. Two branches are not mirrored and throw
// `NotMirrored`, never a guess: a Move whose neighbour is missing (`LayoutTrait::neighbor` →
// `None`, the window's edge), which `run` never reaches (D-255); and a combat action refused as
// Heavy whose call changed the ground, which `run` keeps, a bug game fixes after RV-02 (the fix
// restores the input ground).

import { admit } from "./batch";
import { P, add, panic, u8 } from "./felt";
import { ORIGIN, board as origin_board, move_ticks, origin, position } from "./movement";
import { chunks as sight } from "./reveal";
import type { Classes } from "./segment/classes";
import {
  type Action,
  type Area,
  type Board,
  type Done,
  type Ground,
  Illegal,
  writeGround,
} from "./segment/serde";
import {
  ABSENT_LANE,
  DEAD,
  ENGAGED,
  type Content,
  type GoblinWords,
  type Member,
  NO_SLOT,
  type Sheets,
  type Words,
  type World,
  crippled,
  downs,
  goblinAi,
  goblinPlace,
  held,
  is_alive,
  kind,
  load,
  place,
  set_facing,
  set_place,
  sheets as index,
  store,
  u16add,
  u32add,
  world as reload,
  words as stored,
} from "./segment/words";
import { FAR, HEIGHT, WIDTH, neighbor, shape, shapes } from "./window";

export { Illegal };

/** An action may run only while the clock is at most this (`types::LAST_TICK`, E-4). */
export const LAST_TICK = 0xfffffff - 0xffff - 10;

/** `MemberState.flags` (`types::tick::flag`). */
export const flag = { TURNED: 1, INSTANT: 2, HIT: 8, HALVED: 16 } as const;
/** The flags a tick's step 0 keeps. */
const KEPT = 0xff - flag.TURNED - flag.INSTANT - flag.HIT;

/** `types::tick::status`. */
export const status = { INSIDE: 0, DOWN: 1, GONE: 2 } as const;

/** The distinct goblin records an invocation may change (E-16): `MAX_GOBLINS` of a tick's world. */
const MAX_GOBLINS = 100;
/** The first goblin's entity, and the ids a chunk's goblins take (M-5: `8 + 16 chunk + k`). */
const FIRST_GOBLIN = 8;
const GOBLINS_STRIDE = 16;

/** A branch of `run` the mirror does not reach: it stops there rather than guess. */
export class NotMirrored extends Error {
  constructor(branch: string) {
    super(`not mirrored: ${branch}`);
    this.name = "NotMirrored";
  }
}

/** The branches `NotMirrored` names. */
export const unported = {
  EDGE: "Blocked by a missing neighbour (the window's edge)",
  /** `combat` keeps `ActionLibrary`'s ground on a Heavy refusal: a bug, game's fix pending. */
  HEAVY_GROUND: "heavy refusal with a changed ground: game fix pending",
} as const;

/** What a segment runs from: `SegmentLibrary::segment`'s inputs, the classes aside. */
export type Segment = {
  words: Words;
  content: Content;
  area: Area;
  level: number;
  ground: Ground;
  owed: number;
  weight: number;
  actions: readonly Action[];
};

/** The words, the ground after and how the segment ended. */
export type Ran = { words: Words; ground: Ground; done: Done };

/** What `run` threads through its calls (`executor::Delegate`'s part it reads). */
type Rules = {
  board: Board;
  ground: Ground;
  level: number;
  content: Content;
  sheets: Sheets;
  classes: Classes;
};

/** Why an action did not run (`play::Halt`). */
type Halt = { illegal: Illegal } | "heavy";
type Result = { ticks: number } | { halt: Halt };

const has = (bits: bigint, index: number): boolean => ((bits >> BigInt(index)) & 1n) === 1n;
const felt = (value: bigint): bigint => ((value % P) + P) % P;
const u8add = (a: number, b: number): number => Number(add(u8, BigInt(a), BigInt(b)));

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

/** `SegmentTrait::board`: the board of the window of an adventurer on `(x, y)`. */
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

/** The adventurer (member 0); a world holds it. */
function adventurer(world: World): Member {
  const member = world.members[0];
  if (member === undefined) panic("Index out of bounds");
  return member;
}

/** `SegmentTrait::chunk`: the adventurer's chunk, `15 cy + cx`. */
function chunk(world: World): number {
  const { x, y } = place(adventurer(world));
  return u8add(Math.floor(y / 15) * 15, Math.floor(x / 15));
}

/** `SegmentTrait::to_reveal`: whether sight from the adventurer touches a chunk not yet revealed. */
function to_reveal(area: Area, world: World): boolean {
  const { x, y } = place(adventurer(world));
  return sight(x, y, area.width, area.height).some(
    (c) => has(area.known, c) && !has(area.revealed, c),
  );
}

/** `MemberConditionTrait::can_act`: not knocked down at `t0`. */
const can_act = (member: Member, t0: number): boolean => !(t0 <= member.knocked);

/** `WorldTrait::alive`: the goblins alive (`ai` below `DEAD`), with their index. */
const alive = (world: World): GoblinWords[] =>
  world.goblins.filter((goblin) => goblinAi(goblin.state) < DEAD);

/** `WorldTrait::calm`: no goblin in the awake set and no member activating. */
const calm = (world: World): boolean =>
  world.goblins.every((goblin) => !goblin.awake) &&
  world.members.every((member) => member.act_slot === NO_SLOT);

/** `SegmentTrait::idle`: whether the ticks take the fast path (no living goblin in the window). */
function idle(world: World, on: Board): boolean {
  if (!calm(world)) return false;
  return alive(world).every((goblin) => {
    const { x, y } = goblinPlace(goblin.state);
    return position(on, x, y) >= FAR;
  });
}

/** `TickMathTrait::heal`: `health + 2 × clamp(pips, −10, 10)`, clamped to `[0, max]`. */
function heal(health: number, pips: number, max: number): number {
  const change = 2 * Math.min(10, Math.max(-10, pips));
  if (change < 0) return -change >= health ? 0 : health - -change;
  return Math.min(health + change, max);
}

/**
 * `MemberTickTrait::regenerate` out of combat (the fast path's): health by its pips (its own, the
 * degenerating conditions' −3, −4, −7, its `REGENERATION` effects' while they last), energy by its
 * regeneration up to its max, adrenaline decayed by 1.
 */
function regenerate(member: Member, t: number): void {
  let pips = member.health_regen;
  if (t <= member.bleeding) pips -= 3;
  if (t <= member.poison) pips -= 4;
  if (t <= member.burning) pips -= 7;
  member.effect_regen.forEach((regen, slot) => {
    if (regen !== 0 && t <= member.effect_deadlines[slot]!) pips += regen;
  });
  member.health = heal(member.health, pips, member.max_health);
  member.energy = Math.min(u16add(member.energy, member.energy_regen), member.max_energy);
  member.adrenaline = member.adrenaline < 1 ? 0 : member.adrenaline - 1;
}

/** `TickTrait::check`: a member inside at 0 is down, and the adventurer defeated. */
function check(world: World): void {
  if (!world.members.some((member) => downs(member) === 1)) return;
  for (const member of world.members) {
    if (downs(member) === 1) member.status = status.DOWN;
  }
  world.defeated = true;
}

/**
 * `TickTrait::idle`: up to `n` ticks of the fast path, stopping after the one that defeats: with no
 * member down the clock advances, the flags clear, the members alive regenerate; then the check.
 */
function fast(world: World, n: number): void {
  for (let k = 0; k < n && !world.defeated; k++) {
    if (world.goblins.length > MAX_GOBLINS) panic("tick: too many goblins");
    if (!world.members.some((member) => downs(member) === 1)) {
      world.clock = u32add(world.clock, 1);
      for (const member of world.members) member.flags &= KEPT;
      for (const member of world.members) {
        if (member.status === status.INSIDE && member.health > 0) regenerate(member, world.clock);
      }
    }
    check(world);
  }
}

/** The world after a class: its words loaded (`SegmentTrait::reload`). */
function into(world: World, words: Words, sheets: Sheets): void {
  Object.assign(world, reload(words, sheets));
}

/** `SegmentTrait::ticks`: `n` ticks, on the fast path, else through `TickLibrary`. */
function ticks(world: World, rules: Rules, n: number): void {
  if (n === 0 || world.defeated) return;
  if (idle(world, rules.board)) {
    fast(world, n);
    return;
  }
  const out = rules.classes.ticks({
    words: stored(world),
    content: rules.content,
    board: rules.board,
    level: rules.level,
    ground: rules.ground,
    n,
  });
  rules.ground = out.ground;
  into(world, out.words, rules.sheets);
}

/** `play::Placer` of a placed trap's `param`: a goblin's entity, or a member. */
function placer(param: number): number | undefined {
  return param >= 0x8000 ? ((param - 0x8000) % 0x1000) + FIRST_GOBLIN : undefined;
}

/** `TrapTrait::locate`: the chunk and its tile of the window's `position`. */
function locate(on: Board, at: number): [number, number] | undefined {
  if (at >= FAR || at >= 240) return undefined;
  const [dy, dx] = [Math.floor(at / 15), at % 15];
  const [x, y] = [on.x + dx, on.y + dy];
  if (x < ORIGIN || y < ORIGIN) return undefined;
  const [cy, ly] = [Math.floor((y - ORIGIN) / 15), (y - ORIGIN) % 15];
  const [cx, lx] = [Math.floor((x - ORIGIN) / 15), (x - ORIGIN) % 15];
  const c = cy * 15 + cx;
  if (c >= 225 || cx >= 15) return undefined;
  return [c, ly * 15 + lx];
}

/**
 * `AiTrait::armed`: the unused trap (a terrain one, kind 4, or a placed one, 9) on the window's
 * `position` in the ground: `null` for a terrain trap, its placer's param for a placed one.
 */
function armed(ground: Ground, on: Board, at: number): { param: number | null } | undefined {
  const where = locate(on, at);
  if (where === undefined) return undefined;
  const [c, tile] = where;
  const features = ground.find(([chunk]) => chunk === c)?.[1];
  if (features === undefined) return undefined;
  for (const object of features.objects) {
    if ((object.kind === 4 || object.kind === 9) && object.state === 0 && object.tile === tile) {
      return { param: object.kind === 9 ? object.param : null };
    }
  }
  return undefined;
}

/**
 * `SegmentTrait::trap`: the trap of the window's `position` the adventurer entered, through
 * `TrapLibrary` with the members' words and, for a goblin's placed trap, its placer's; the members
 * and that goblin written back.
 */
function trap(world: World, rules: Rules, at: number): void {
  const found = armed(rules.ground, rules.board, at);
  if (found === undefined) return;
  const entity = found.param === null ? undefined : placer(found.param);
  const index = entity === undefined ? -1 : world.goblins.findIndex((g) => g.entity === entity);
  const goblins = index < 0 ? [] : [{ ...world.goblins[index]! }];
  const out = rules.classes.trigger({
    words: {
      clock: world.clock,
      members: world.members.map(store),
      goblins,
      killed: [],
      defeated: false,
    },
    content: rules.content,
    board: rules.board,
    ground: rules.ground,
    entrant: 0,
    position: at,
    level: rules.level,
  });
  rules.ground = out.ground;
  out.words.members.forEach((member, m) => {
    if (m >= world.members.length) panic("Index out of bounds");
    world.members[m] = load(member, rules.sheets);
  });
  if (index >= 0) {
    for (const goblin of out.words.goblins) world.goblins[index] = { ...goblin };
  }
}

/** `TrapTrait::occupied`: a living member or goblin on the window's `position`. */
function occupied(world: World, on: Board, at: number): boolean {
  for (const member of world.members) {
    const { x, y } = place(member);
    if (is_alive(member) && position(on, x, y) === at) return true;
  }
  return alive(world).some((goblin) => {
    const { x, y } = goblinPlace(goblin.state);
    return position(on, x, y) === at;
  });
}

/** `SegmentTrait::movement`: whether the member holds a `MOVEMENT` effect at clock `c` (FX-18). */
function movement(member: Member, sheets: Sheets, c: number): boolean {
  for (let slot = 0; slot < 4; slot++) {
    const at = member.effect_at[slot]!;
    const effect = held(member.words.effects, slot);
    if (at !== ABSENT_LANE && !effect.potion && c < effect.deadline) {
      for (let k = 0; k < 3; k++) {
        if (sheets.entries[3 * at + k]!.kind === kind.MOVEMENT) return true;
      }
    }
  }
  return false;
}

/** `SegmentTrait::step`: a Move of the adventurer toward `direction`, then its trap; its ticks. */
function step(world: World, rules: Rules, direction: number, weight: number): Result {
  const c = world.clock;
  if (c > LAST_TICK) return { halt: { illegal: Illegal.Clock } };
  const member = adventurer(world);
  if (!is_alive(member)) return { halt: { illegal: Illegal.Absent } };
  const t0 = u32add(c, 1);
  if (!can_act(member, t0)) return { halt: { illegal: Illegal.Knocked } };
  const on = rules.board;
  const { x, y } = place(member);
  const to = neighbor(position(on, x, y), direction);
  if (to === undefined) throw new NotMirrored(unported.EDGE);
  if (shape(on.open, shapes.SINGLE, to) === 0n || occupied(world, on, to)) {
    return { halt: { illegal: Illegal.Blocked } };
  }
  const n = move_ticks(crippled(member), t0, movement(member, rules.sheets, c));
  if (n > weight) return { halt: "heavy" };
  set_place(
    member,
    on.x + (to % WIDTH) - ORIGIN,
    on.y + Math.floor(to / WIDTH) - ORIGIN,
    direction,
  );
  trap(world, rules, to);
  return { ticks: n };
}

/** `SegmentTrait::turn`: once between two ticks, its facing set, 0 ticks. */
function turn(world: World, direction: number, weight: number): Result {
  if (weight === 0) return { halt: "heavy" };
  if (world.clock > LAST_TICK) return { halt: { illegal: Illegal.Clock } };
  const member = adventurer(world);
  if (!is_alive(member)) return { halt: { illegal: Illegal.Absent } };
  if (!can_act(member, u32add(world.clock, 1))) return { halt: { illegal: Illegal.Knocked } };
  if ((member.flags & flag.TURNED) !== 0) return { halt: { illegal: Illegal.Turned } };
  member.flags |= flag.TURNED;
  set_facing(member, direction);
  return { ticks: 0 };
}

/** `SegmentTrait::wait`: 1 tick, legal while the adventurer stands and the clock allows. */
function wait(world: World): Result {
  if (world.clock > LAST_TICK) return { halt: { illegal: Illegal.Clock } };
  if (!is_alive(adventurer(world))) return { halt: { illegal: Illegal.Absent } };
  return { ticks: 1 };
}

/**
 * `SegmentTrait::combat`: an Attack, a Skill or an Item through `ActionLibrary` with the whole
 * words: kept only if legal and within `weight`, else the words as they were.
 */
function combat(world: World, rules: Rules, action: Action, weight: number): Result {
  const words = stored(world);
  const out = rules.classes.act({
    words,
    content: rules.content,
    board: rules.board,
    ground: rules.ground,
    action,
  });
  let kept = words;
  let result: Result;
  if ("illegal" in out.outcome) {
    result = { halt: { illegal: out.outcome.illegal } };
  } else if (out.outcome.ticks > weight || (out.outcome.ticks === 0 && weight === 0)) {
    // Cairo keeps the ground the call returned, where the fix restores the input ground: the two
    // agree only when the call left it as it was
    if (!same(out.ground, rules.ground)) throw new NotMirrored(unported.HEAVY_GROUND);
    result = { halt: "heavy" };
  } else {
    kept = out.words;
    result = { ticks: out.outcome.ticks };
  }
  rules.ground = out.ground;
  into(world, kept, rules.sheets);
  return result;
}

/** Whether two grounds hold the same felts. */
function same(a: Ground, b: Ground): boolean {
  const [x, y] = [writeGround(a), writeGround(b)];
  return x.length === y.length && x.every((felt, i) => felt === y[i]);
}

/** `SegmentTrait::first`: whether the goblin has no record yet (its chunk's `touched` bit clear). */
function first(ground: Ground, entity: number): boolean {
  const offset = entity - FIRST_GOBLIN;
  const c = Math.floor(offset / GOBLINS_STRIDE);
  const features = ground.find(([chunk]) => chunk === c)?.[1];
  return features !== undefined && !has(BigInt(features.touched), offset % GOBLINS_STRIDE);
}

/**
 * `SegmentTrait::fits`: the goblins whose words differ from `before` and that `changed` does not
 * hold, but an untouched one engaged and nothing else, added to `changed`, weighed with `admit`;
 * `undefined` when the action passes the cap or the weight (`Done.undo`). Returns the goblins as
 * they are now and the weight left.
 */
function fits(
  world: World,
  changed: number[],
  before: readonly GoblinWords[],
  ground: Ground,
  cost: number,
  ran: boolean,
  weight: number,
): { after: GoblinWords[]; weight: number } | undefined {
  const fresh: number[] = [];
  let firsts = 0;
  world.goblins.forEach((now, i) => {
    const was = before[i];
    if (was === undefined) panic("Index out of bounds");
    if ((was.state === now.state && was.timers === now.timers) || changed.includes(now.entity)) {
      return;
    }
    const untouched = first(ground, now.entity);
    // Its AI state moved to Engaged and nothing else: its pack's `alert` holds it, not a record
    const engaged =
      goblinAi(now.state) === ENGAGED &&
      was.timers === now.timers &&
      felt(now.state - was.state) === felt(BigInt(ENGAGED - goblinAi(was.state)) * (1n << 24n));
    if (untouched && engaged) return;
    if (untouched) firsts = u8add(firsts, 1);
    fresh.push(now.entity);
  });
  const left = admit(changed.length, fresh.length, firsts, cost, ran, weight);
  if (left === undefined) return undefined;
  changed.push(...fresh);
  return { after: world.goblins.map((goblin) => ({ ...goblin })), weight: left };
}

/**
 * `SegmentTrait::run`: `owed` ticks first, then the actions within `weight`, the classes behind
 * `classes`. Returns the words and the ground after it, and how it ended (`segment` is not changed).
 */
export function run(segment: Segment, classes: Classes): Ran {
  const sheets = index(segment.content);
  const world = reload(segment.words, sheets);
  const { area } = segment;
  const { x, y } = place(adventurer(world));
  const rules: Rules = {
    board: board(area, x, y),
    ground: segment.ground,
    level: segment.level,
    content: segment.content,
    sheets,
    classes,
  };
  const changed = [...area.changed];
  const done: Done = {
    played: 0,
    weight: segment.weight,
    owed: 0,
    reveal: false,
    illegal: undefined,
    heavy: false,
    changed: [],
    undo: false,
  };
  // The last segment's Move's owed ticks: their records count with the first action
  let before = world.goblins.map((goblin) => ({ ...goblin }));
  ticks(world, rules, segment.owed);
  const start = chunk(world);
  for (const next of segment.actions) {
    if (world.defeated) break;
    let result: Result;
    switch (next.kind) {
      case "move":
        result = step(world, rules, next.direction, done.weight);
        break;
      case "turn":
        result = turn(world, next.direction, done.weight);
        break;
      case "wait":
        result = wait(world);
        break;
      case "interact":
        result = { halt: { illegal: Illegal.Kind } };
        break;
      default:
        result = combat(world, rules, next, done.weight);
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
    // the segment before its ticks; one that reveals nothing moves the window with it
    let reveal = false;
    if (next.kind === "move") {
      reveal = to_reveal(area, world) || chunk(world) !== start;
      if (!reveal) {
        const at = place(adventurer(world));
        rules.board = board(area, at.x, at.y);
      }
    }
    if (!reveal) ticks(world, rules, n);
    const ran = area.ran || done.played > 0;
    const fit = fits(world, changed, before, rules.ground, cost, ran, done.weight);
    if (fit === undefined) {
      done.heavy = true;
      done.undo = true;
      break;
    }
    before = fit.after;
    done.weight = fit.weight;
    done.played = u8add(done.played, 1);
    if (reveal) {
      done.owed = n;
      done.reveal = true;
      break;
    }
  }
  done.changed = changed;
  return { words: stored(world), ground: rules.ground, done };
}
