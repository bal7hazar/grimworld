// The goblins' acts (CLI-02g-F, D-257): the mirror of `AiLibrary::act`
// (`contracts/logic/src/systems/ai.cairo`) and of `AiTrait` (`types/ai.cairo`), with `Delegate`'s
// rules: each carrier through the executor (`action.ts`'s `carry`, on the class's whole world), the
// trap a goblin enters through `TrapLibrary` (`trap.ts`'s `triggerClass`). Held equal to them by
// `contracts/logic/vectors/tick.jsonl`, through `TickLibrary::ticks` (`tick.ts`), which computes
// the class's inputs. The rules and their readings are the Cairo module's documentation.
//
// The class's world holds the members and the awake set alone; the other living goblins are its
// `frozen` tiles (occupied for the moves and the flood) and its `listed` roster entries (D-238).

import { carry } from "./action";
import * as gm from "./body/goblin";
import { activation, skill_kind } from "./combat";
import {
  type Actor,
  type Board,
  type Cache,
  type Carrier,
  FIRST_GOBLIN,
  cache,
  entry,
  legal,
  target as addressed,
} from "./executor";
import { kind } from "./effect";
import { P, add, div, mul, panic, sub, u16, u8 } from "./felt";
import {
  type Flood,
  ORIGIN,
  flood as bfs,
  next_step,
  next_step_away,
  position as boardPosition,
} from "./movement";
import { armed } from "./segment";
import type { Words } from "./segment/words";
import * as goblinModel from "./segment/goblin";
import type { Goblin } from "./segment/goblin";
import type { Ground } from "./segment/serde";
import { ai } from "./segment/tick";
import {
  ABSENT,
  type Content,
  type Sheets,
  is_alive,
  load as loadMember,
  place as memberPlace,
  sheets as indexed,
  store as storeMember,
} from "./segment/words";
import { type World, world as load, words as store } from "./segment/world";
import { triggerClass } from "./trap";
import { FAR, WIDTH, facing } from "./window";

/** `ai::FLOOD_DEPTH`: a goblin farther on foot holds its tile (D-127). */
export const FLOOD_DEPTH = 15;
/** `ai::MAX_ATTACKERS`: the goblins that may attack in one step 2; 8, no cap (R-2). */
export const MAX_ATTACKERS = 8;
/** `types::MAX_ROSTER`: the goblins away from their spawn chunk an instance lists (D-238). */
export const MAX_ROSTER = 60;
const GOBLINS_STRIDE = 16;
const OUT = "Index out of bounds";

/** `AiLibrary::act(words, content, board, executor, trap, ground, level, frozen, listed, resolved)`. */
export type AiCall = {
  words: Words;
  content: Content;
  board: Board;
  ground: Ground;
  level: number;
  frozen: bigint;
  listed: number;
  resolved: number;
};

/** The rules `AiLibrary` runs (`Delegate`): `action.ts`'s, with what a trap and a step read. */
export type Rules = {
  board: Board;
  cache: Cache;
  ground: Ground;
  content: Content;
  level: number;
  frozen: bigint;
  listed: number;
};

/** A list's element, or Cairo's panic past its end. */
function at<T>(list: readonly T[], index: number): T {
  const item = list[index];
  if (item === undefined) panic(OUT);
  return item;
}

const u8add = (a: number, b: number): number => Number(add(u8, BigInt(a), BigInt(b)));
const u8sub = (a: number, b: number): number => Number(sub(u8, BigInt(a), BigInt(b)));
/** Two felts of the window's bitmaps added, as Cairo's `felt252` `+`. */
const felt = (a: bigint, b: bigint): bigint => (a + b) % P;

/** `WorldTrait::is_down`: a member inside at 0 health. */
const is_down = (world: World): boolean =>
  world.members.some((member) => member.status === 0 && member.health === 0);

/**
 * `DelegateEnter::enter`: `entrant` entered the window's `position`; its unused trap triggers
 * through `TrapLibrary` with every member and the entrant, and they are written back. Whether it
 * did.
 */
function enter(
  world: World,
  sheets: Sheets,
  rules: Rules,
  index: number,
  position: number,
): boolean {
  if (armed(rules.ground, rules.board, position) === undefined) return false;
  const goblin = at(world.goblins, index);
  const out = triggerClass({
    words: {
      clock: world.clock,
      members: world.members.map(storeMember),
      goblins: [goblinModel.store(goblin)],
      killed: [],
      defeated: false,
    },
    content: rules.content,
    board: rules.board,
    ground: rules.ground,
    entrant: goblin.entity,
    position,
    level: rules.level,
  });
  rules.ground = out.ground;
  out.words.members.forEach((words, m) => {
    at(world.members, m);
    world.members[m] = loadMember(words, sheets);
  });
  for (const words of out.words.goblins) world.goblins[index] = goblinModel.load(words, sheets);
  world.killed.push(...out.words.killed);
  return out.triggered;
}

/**
 * `AiTrait::step` (`capped` at `MAX_ATTACKERS`): every goblin of the awake set free to act acts,
 * ascending id; `resolved` holds those that resolved in step 1 (bit `2^k` for the `k`-th). Whether
 * the adventurer reached 0.
 */
export function step(world: World, sheets: Sheets, rules: Rules, resolved: number): boolean {
  return capped(world, sheets, rules, resolved, MAX_ATTACKERS)[0];
}

/** `AiTrait::capped`: the step with at most `cap` goblins attacking; whether down, and how many attacked. */
export function capped(
  world: World,
  sheets: Sheets,
  rules: Rules,
  resolved: number,
  cap: number,
): [boolean, number] {
  const t = world.clock;
  let attacks = 0;
  const state: Step = { flood: undefined, listed: u8add(rules.listed, away(world)) };
  const woken = world.goblins.flatMap((goblin, i) => (goblin.awake ? [i] : []));
  for (let k = 0; k < woken.length; k++) {
    const index = woken[k]!;
    const goblin = { ...at(world.goblins, index) };
    if (
      goblin.act_slot === activation.NONE &&
      goblin.knocked < t &&
      goblinModel.is_alive(goblin) &&
      (resolved & (2 ** k)) === 0
    ) {
      if (act(world, sheets, rules, state, index, goblin, attacks < cap, t)) attacks += 1;
      if (is_down(world)) return [true, attacks];
    }
  }
  return [false, attacks];
}

/** The flood shared by the step's walkers, computed when one first needs it, and the roster's count. */
type Step = { flood: Flood | undefined; listed: number };

/**
 * `AiTrait::act`: goblin `index`'s act at `t` (design/04's state machine): Engaged, its first usable
 * skill, else its weapon in reach, else a step toward; Alerted, a step toward; Fleeing, a step
 * away, Engaged again when cornered. An Engaged goblin past the cap holds. Whether it attacked.
 */
function act(
  world: World,
  sheets: Sheets,
  rules: Rules,
  state: Step,
  index: number,
  goblin: Goblin,
  attack: boolean,
  t: number,
): boolean {
  const mode = goblin.ai;
  if (mode !== ai.ENGAGED && mode !== ai.ALERTED && mode !== ai.FLEEING) return false;
  const found = target(world, rules.board);
  if (found === undefined) return false;
  const [address, target_at] = found;
  const source: Actor = { kind: "G", i: index };
  if (mode === ai.ENGAGED) {
    if (!attack) return false;
    if (skill(world, sheets, rules, source, goblin, address, target_at, t)) return true;
    const weapon: Carrier = { kind: "Weapon" };
    if (legal(world, sheets, rules.board, source, weapon, address)) {
      const { x, y, facing: facing0 } = goblinModel.place(goblin);
      const from = boardPosition(rules.board, x, y);
      const moved = { ...goblin };
      goblinModel.set_place(moved, x, y, facing(from, target_at, facing0));
      gm.recover(moved, at(sheets.kits, moved.caste_at).weapon_ticks, t);
      world.goblins[index] = moved;
      carry(rules, world, sheets, source, 0, weapon, address, t);
      return true;
    }
  }
  const fleeing = mode === ai.FLEEING;
  if (!walk(world, sheets, rules, state, index, goblin, fleeing, t) && fleeing) {
    world.goblins[index] = { ...goblin, ai: ai.ENGAGED };
  }
  return false;
}

/**
 * `AiTrait::skill`: the first usable skill of the caste's priority list (not recharging, its energy
 * and adrenaline there, not a `TRAP`, its target legal), used on `address`; whether one was.
 */
function skill(
  world: World,
  sheets: Sheets,
  rules: Rules,
  source: Actor & { kind: "G" },
  goblin: Goblin,
  address: number,
  target_at: number,
  t: number,
): boolean {
  const positions = at(sheets.kits, goblin.caste_at).skills;
  for (let slot = 0; slot < 4; slot++) {
    const position = at(positions, slot);
    if (position === ABSENT || !(t > goblinModel.recharge(goblin, slot))) continue;
    const sheet = at(sheets.skills, position);
    const energy = sheet.energy * 3;
    const adrenaline = sheet.adrenaline * 4;
    const first = entry(sheets, position, 0);
    if (first.kind === kind.TRAP || goblin.energy < energy || goblin.adrenaline < adrenaline) {
      continue;
    }
    const carried: Carrier = {
      kind: "Skill",
      at: position,
      rank: at(sheets.castes, goblin.caste_at).rank,
    };
    const [aimed, to] = aim(world, goblin, first.target, sheet.kind, address, target_at);
    if (legal(world, sheets, rules.board, source, carried, aimed)) {
      use_skill(
        world,
        sheets,
        rules,
        source,
        goblin,
        slot,
        carried,
        aimed,
        to,
        energy,
        adrenaline,
        t,
      );
      return true;
    }
  }
  return false;
}

/**
 * `AiTrait::address`: what the goblin's skill addresses, an attack skill or a `FOE` entry the
 * target, a `TILE` one the target's tile `x + 256 y`, `SELF` and `ALLY` itself; and its position.
 */
function aim(
  world: World,
  goblin: Goblin,
  addressing: number,
  sheet_kind: number,
  address: number,
  target_at: number,
): [number, number] {
  if (sheet_kind === skill_kind.ATTACK || addressing === addressed.FOE) return [address, target_at];
  if (addressing === addressed.TILE) {
    const { x, y } = memberPlace(at(world.members, address));
    return [x + 256 * y, target_at];
  }
  return [goblin.entity, FAR];
}

/**
 * `AiTrait::use_skill`: caste skill `slot` used on `address` at `t`: its costs, its facing, then an
 * activation (`n ≥ 1`) or the carrier now (an attack skill recovering for its weapon's `k`).
 */
function use_skill(
  world: World,
  sheets: Sheets,
  rules: Rules,
  source: Actor & { kind: "G" },
  goblin: Goblin,
  slot: number,
  carried: Carrier & { kind: "Skill" },
  address: number,
  to: number,
  energy: number,
  adrenaline: number,
  t: number,
): void {
  const sheet = at(sheets.skills, carried.at);
  const used = { ...goblin };
  used.energy = u8sub(used.energy, Number(narrowU8(energy)));
  used.adrenaline = u8sub(used.adrenaline, Number(narrowU8(adrenaline)));
  const { x, y, facing: facing0 } = goblinModel.place(used);
  const from = boardPosition(rules.board, x, y);
  goblinModel.set_place(used, x, y, facing(from, to, facing0));
  if (sheet.activation >= 1) {
    gm.start(used, slot, address, sheet.activation, t);
    world.goblins[source.i] = used;
    return;
  }
  gm.use_instant(used, slot, t, sheets);
  if (sheet.kind === skill_kind.ATTACK) {
    gm.recover(used, at(sheets.kits, used.caste_at).weapon_ticks, t);
  }
  world.goblins[source.i] = used;
  carry(rules, world, sheets, source, slot, carried, address, t);
}

/** A `u16` cost as Cairo's `try_into::<u8>().unwrap()`. */
function narrowU8(value: number): bigint {
  if (value > 0xff) panic("Option::unwrap failed.");
  return BigInt(value);
}

/**
 * `AiTrait::walk`: one step toward the adventurer (away when `fleeing`) on the tick's flood, the
 * current occupancy blocked; its facing, a crippled step's recovery, then the trap of the tile
 * entered. A step out of its spawn chunk needs a roster entry: with `MAX_ROSTER` listed it holds.
 * Whether it stepped.
 */
function walk(
  world: World,
  sheets: Sheets,
  rules: Rules,
  state: Step,
  index: number,
  goblin: Goblin,
  fleeing: boolean,
  t: number,
): boolean {
  const board = rules.board;
  const { x, y, facing: facing0 } = goblinModel.place(goblin);
  const from = boardPosition(board, x, y);
  if (from >= FAR) return false;
  const blocked = felt(occupancy(world, board, undefined), rules.frozen);
  state.flood ??= flood(world, board, rules.frozen);
  const found = state.flood;
  if (found === undefined) return false;
  const to = fleeing ? next_step_away(found, from, blocked) : next_step(found, from, blocked);
  if (to === undefined) return false;
  const dy = Math.floor(to / WIDTH);
  const dx = to % WIDTH;
  const nx = u8sub(u8add(board.x, dx), ORIGIN);
  const ny = u8sub(u8add(board.y, dy), ORIGIN);
  const spawn = spawnOf(goblin.entity);
  const here = chunk(x, y);
  const there = chunk(nx, ny);
  if (here === spawn && there !== spawn) {
    if (state.listed >= MAX_ROSTER) return true;
    state.listed = u8add(state.listed, 1);
  } else if (here !== spawn && there === spawn) {
    state.listed = u8sub(state.listed, 1);
  }
  const moved = { ...goblin };
  goblinModel.set_place(moved, nx, ny, facing(from, to, facing0));
  const cost = gm.move_ticks(moved, t, movement(moved, sheets, t));
  gm.recover(moved, cost, t);
  world.goblins[index] = moved;
  enter(world, sheets, rules, index, to);
  return true;
}

/**
 * `AiTrait::flood`: the tick's flood from the adventurer (member 0) on the window, every other
 * living actor's tile an obstacle, stopped at `FLOOD_DEPTH`; `undefined` when the adventurer is not
 * in the window or not on a walkable tile.
 */
export function flood(world: World, board: Board, frozen: bigint): Flood | undefined {
  const { x, y } = memberPlace(at(world.members, 0));
  const from = boardPosition(board, x, y);
  if (from >= FAR || (board.open & (1n << BigInt(from))) === 0n) return undefined;
  const obstacles = felt(occupancy(world, board, from), frozen);
  return bfs(board.open, from, obstacles, FLOOD_DEPTH);
}

/** `AiTrait::occupancy`: the window's tiles of every member and every living goblin, but `except`. */
export function occupancy(world: World, board: Board, except: number | undefined): bigint {
  let tiles = 0n;
  const mark = (position: number): void => {
    if (position >= FAR || position === except) return;
    tiles |= 1n << BigInt(position);
  };
  for (const member of world.members) {
    const { x, y } = memberPlace(member);
    mark(boardPosition(board, x, y));
  }
  for (const goblin of world.goblins) {
    if (!goblinModel.is_alive(goblin)) continue;
    const { x, y } = goblinModel.place(goblin);
    mark(boardPosition(board, x, y));
  }
  return tiles;
}

/** `AiTrait::target`: the nearest living member inside the window, ties by the lowest index. */
export function target(world: World, board: Board): [number, number] | undefined {
  for (let m = 0; m < world.members.length; m++) {
    const member = world.members[m]!;
    const { x, y } = memberPlace(member);
    const position = boardPosition(board, x, y);
    if (is_alive(member) && position < FAR) return [m, position];
  }
  return undefined;
}

/** `AiTrait::away`: the living goblins of the world away from their spawn chunk (D-238). */
export function away(world: World): number {
  let count = 0;
  for (const goblin of world.goblins) {
    if (!goblinModel.is_alive(goblin)) continue;
    const { x, y } = goblinModel.place(goblin);
    if (chunk(x, y) !== spawnOf(goblin.entity)) count = u8add(count, 1);
  }
  return count;
}

/** `AiTrait::spawn`: a goblin's spawn chunk, from its entity id (M-5: `8 + 16 chunk + k`). */
export function spawnOf(entity: number): number {
  const chunk = div(u16, sub(u16, BigInt(entity), BigInt(FIRST_GOBLIN)), BigInt(GOBLINS_STRIDE));
  if (chunk > 0xffn) panic("Option::unwrap failed.");
  return Number(chunk);
}

/** `AiTrait::chunk`: the chunk of the location's tile `(x, y)`. */
export const chunk = (x: number, y: number): number =>
  Number(add(u8, mul(u8, BigInt(Math.floor(y / 15)), 15n), BigInt(Math.floor(x / 15))));

/** `AiTrait::movement`: whether the goblin holds a `MOVEMENT` effect at `t` (FX-18). */
export function movement(goblin: Goblin, sheets: Sheets, t: number): boolean {
  if (goblin.effect_at === ABSENT || t > goblin.effect_deadline) return false;
  for (let k = 0; k < 3; k++) {
    if (entry(sheets, goblin.effect_at, k).kind === kind.MOVEMENT) return true;
  }
  return false;
}

/**
 * `AiLibrary::act`, the class: the words loaded through the content, `AiTrait::step` with
 * `Delegate`'s rules and a fresh `Cache`; the words stored back and the ground the rules hold.
 */
export function aiClass(call: AiCall): { words: Words; ground: Ground } {
  const sheets = indexed(call.content);
  const world = load(call.words, sheets);
  const rules: Rules = {
    board: call.board,
    cache: cache(),
    ground: call.ground,
    content: call.content,
    level: call.level,
    frozen: call.frozen,
    listed: call.listed,
  };
  step(world, sheets, rules, call.resolved);
  return { words: store(world), ground: rules.ground };
}
