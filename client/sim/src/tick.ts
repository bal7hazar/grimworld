// The ticks with a fight (CLI-02g-F, D-257): the mirror of `TickLibrary::ticks`
// (`contracts/logic/src/systems/tick.cairo`), which runs `TickTrait::run` (`types/world.cairo`)
// with `Delegate`'s rules (`types/executor.cairo`), held equal to it by
// `contracts/logic/vectors/tick.jsonl`. `ticksClass` is the class itself, computed: `run`'s seam
// (`segment/classes.ts`) takes it for `Classes.ticks`.
//
// One tick `T` (design/19 §5.1): the adventurer at 0 before it stops it at once (step 5 only);
// step 0 the clock, the flags, perception and the awake set (`perceive`); step 1 the members'
// activations due, then the awake set's, ascending (`conclude`), each concluded carrier through the
// executor (`resolve`); step 2 the goblins' acts in one call of `AiLibrary` (`step`, `ai.ts`); step 3
// regeneration (`regenerate`); step 5 the defeat (`segment.ts`'s `check`). A member at 0 in steps 1
// or 2 stops the tick there.
//
// The world is one array of goblins, each with its awake flag (`segment/world.ts`), where Cairo
// keeps the awake set apart: a goblin is written at once where Cairo gathers pending writes, which
// it puts in the set before every executor call and when the step ends, so the executor and every
// later goblin read the same values. Step 1's carriers run on the whole world, as lot E's: equal to
// `Delegate`'s sub-world for carriers whose entries share a target kind (`action.ts`'s `mixed`).
// Step 2 crosses the class boundary as Cairo does: the members and the awake set stored, the frozen
// goblins' tiles and the roster count computed here, the words loaded back (`ai.ts`'s `aiClass`).

import { aiClass } from "./ai";
import { carry } from "./action";
import * as body from "./body";
import * as gm from "./body/goblin";
import * as mm from "./body/member";
import { activation } from "./combat";
import {
  type Actor,
  type Board,
  type Cache,
  FIRST_GOBLIN,
  cache,
  carrier,
  legal,
} from "./executor";
import { add, div, mul, panic, u16, u8 } from "./felt";
import { awake, position as boardPosition } from "./movement";
import { MAX_GOBLINS, check } from "./segment";
import type { Classes, TicksCall } from "./segment/classes";
import * as goblinModel from "./segment/goblin";
import type { Ground } from "./segment/serde";
import { KEPT, ai, regenerate as memberRegenerate } from "./segment/tick";
import {
  type Content,
  type Sheets,
  NO_SLOT,
  downs,
  place as memberPlace,
  sheets as indexed,
  store as storeMember,
  u32add,
} from "./segment/words";
import { type World, assert_awake, world as load, words as store } from "./segment/world";
import { Arc, FAR, arc, distance, range, sight } from "./window";

/** The rules `TickLibrary` runs (`Delegate`): the board, the cache, the ground, the content, the level. */
export type Rules = {
  board: Board;
  cache: Cache;
  ground: Ground;
  content: Content;
  level: number;
};

const GOBLINS_STRIDE = 16;
const OUT = "Index out of bounds";

/** A list's element, or Cairo's panic past its end. */
function at<T>(list: readonly T[], index: number): T {
  const item = list[index];
  if (item === undefined) panic(OUT);
  return item;
}

/** `WorldTrait::is_down`: a member inside at 0 health. */
const is_down = (world: World): boolean => world.members.some((member) => downs(member) === 1);

/** `World.woken`: the awake set's indexes, ascending. */
const woken = (world: World): number[] =>
  world.goblins.flatMap((goblin, i) => (goblin.awake ? [i] : []));

/** `WorldAssert::assert_goblins`: at most `MAX_GOBLINS`, so their indexes fit step 1's mask. */
function assert_goblins(world: World): void {
  if (world.goblins.length > MAX_GOBLINS) panic("tick: too many goblins");
}

/** `TickTrait::run`: up to `n` ticks, stopping after the one that defeats the adventurer. */
export function run(world: World, sheets: Sheets, n: number, rules: Rules): void {
  for (let k = 0; k < n && !world.defeated; k++) tick(world, sheets, rules);
}

/** `TickTrait::tick`: one world tick, steps 0 to 5. */
export function tick(world: World, sheets: Sheets, rules: Rules): void {
  assert_goblins(world);
  if (is_down(world)) {
    check(world);
    return;
  }
  world.clock = u32add(world.clock, 1);
  clear_flags(world);
  perceive(world, rules.board);
  const [stopped, resolved] = conclude(world, sheets, rules);
  if (!stopped && !step(world, sheets, rules, resolved)) regenerate(world, sheets);
  check(world);
}

/** `TickTrait::clear_flags`: step 0, the flags "since the last tick" and "hit this tick". */
export function clear_flags(world: World): void {
  for (const member of world.members) member.flags &= KEPT;
}

/** `TickTrait::pack`: a goblin's pack, its spawn chunk's 0 (`k` below 5) or 1. */
export function pack(entity: number): number {
  const offset = BigInt(entity - FIRST_GOBLIN);
  if (offset < 0n) panic("u16_sub Overflow");
  const stride = BigInt(GOBLINS_STRIDE);
  return Number(add(u16, mul(u16, div(u16, offset, stride), 2n), (offset % stride) / 5n));
}

/** `TickTrait::notices`: design/18's table, a goblin of `state` on `at` facing `facing`, `d` tiles away. */
export function notices(
  state: number,
  board: Board,
  from: number,
  member: number,
  facing: number,
  d: number,
): boolean {
  if (state === ai.ASLEEP) return d <= 2;
  if (state !== ai.WATCH) return false;
  if (d <= 2) return true;
  if (d > range.ALERT || !sight(board.open, from, member)) return false;
  const seen = arc(member, from, facing);
  return seen === Arc.Front || seen === Arc.FrontSide;
}

/**
 * `TickTrait::perceive`: step 0 on the tick's board, every goblin asleep or on watch checking
 * design/18's table against every member inside, one that notices engaging its pack; then the
 * awake set, the `MAX_AWAKE` goblins of the window alive and not asleep nearest to a member, ties
 * by the lowest entity id (`movement.ts`'s `awake`).
 */
export function perceive(world: World, board: Board): void {
  const seen: number[] = [];
  for (const member of world.members) {
    if (member.status === 0 && member.health > 0) {
      const { x, y } = memberPlace(member);
      const position = boardPosition(board, x, y);
      if (position < FAR) seen.push(position);
    }
  }
  const distances: number[] = [];
  const packs: number[] = [];
  for (const goblin of world.goblins) {
    const { x, y, facing } = goblinModel.place(goblin);
    const position = boardPosition(board, x, y);
    let near = FAR;
    let noticed = false;
    for (const member of seen) {
      const d = distance(position, member);
      if (d < near) near = d;
      if (goblinModel.is_alive(goblin) && !noticed) {
        noticed = notices(goblin.ai, board, position, member, facing, d);
      }
    }
    if (noticed) packs.push(pack(goblin.entity));
    distances.push(near);
  }
  for (const goblin of world.goblins) {
    if (
      packs.length > 0 &&
      goblinModel.is_alive(goblin) &&
      goblin.ai <= ai.ALERTED &&
      packs.includes(pack(goblin.entity))
    ) {
      goblin.ai = ai.ENGAGED;
    }
  }
  const set = awake(
    world.goblins.map((goblin, i) => ({
      entity: goblin.entity,
      alive: goblinModel.is_alive(goblin) && distances[i]! < FAR,
      asleep: goblin.ai === ai.ASLEEP,
    })),
    distances,
  );
  world.goblins.forEach((goblin, i) => {
    goblin.awake = set.includes(i);
  });
  assert_awake(set);
}

/**
 * `DelegateRules::resolve`: step 1's hook, the carrier of the activation that concluded and its
 * target still legal (else nothing, the costs stay paid), then `DelegateCarry::carry`.
 */
export function resolve(
  world: World,
  sheets: Sheets,
  rules: Rules,
  actor: Actor,
  slot: number,
  address: number,
): void {
  const carried = carrier(world, sheets, actor, slot);
  if (!legal(world, sheets, rules.board, actor, carried, address)) return;
  carry(rules, world, sheets, actor, slot, carried, address, world.clock);
}

/**
 * `TickTrait::conclude`: step 1, the members' activations due, then the awake set's, ascending; a
 * goblin's from before `T` lapses (FX-29), a recovery over clears. Whether the adventurer reached 0,
 * and the awake goblins that resolved (bit `2^k` for the set's `k`-th).
 */
export function conclude(world: World, sheets: Sheets, rules: Rules): [boolean, number] {
  const t = world.clock;
  for (let i = 0; i < world.members.length; i++) {
    const member = world.members[i]!;
    if (
      member.act_slot !== NO_SLOT &&
      member.act_deadline <= t &&
      member.status === 0 &&
      member.health > 0
    ) {
      const concluded = body.copyUnit({ kind: "M", member });
      if (concluded.kind !== "M") panic(OUT);
      const [slot, address] = mm.conclude(concluded.member, sheets);
      world.members[i] = concluded.member;
      resolve(world, sheets, rules, { kind: "M", i }, slot, address);
      if (is_down(world)) return [true, 0];
    }
  }
  let resolved = 0;
  const set = woken(world);
  for (let k = 0; k < set.length; k++) {
    const index = set[k]!;
    const goblin = { ...at(world.goblins, index) };
    const slot = goblin.act_slot;
    const deadline = goblin.act_deadline;
    if (slot <= activation.LAST_SLOT) {
      if (deadline <= t && goblinModel.is_alive(goblin)) {
        if (deadline === t) {
          const [concluded, address] = gm.conclude(goblin, sheets);
          world.goblins[index] = goblin;
          resolved += 2 ** k;
          resolve(world, sheets, rules, { kind: "G", i: index }, concluded, address);
          if (is_down(world)) return [true, resolved];
        } else {
          gm.lapse(goblin, sheets);
          world.goblins[index] = goblin;
        }
      }
    } else if (slot === activation.RECOVERING && deadline < t) {
      gm.clear(goblin);
      world.goblins[index] = goblin;
    }
  }
  return [false, resolved];
}

/**
 * `DelegateRules::step`: step 2 in one call of `AiLibrary`, none when no goblin of the awake set is
 * free to act; every member and the awake set cross it, with the window's tiles of the other living
 * goblins (`frozen`) and those of them away from their spawn chunk (`listed`, D-238). Whether the
 * adventurer reached 0.
 */
export function step(world: World, sheets: Sheets, rules: Rules, resolved: number): boolean {
  const t = world.clock;
  const set = woken(world);
  const free = set.some((index, k) => {
    const goblin = at(world.goblins, index);
    return (
      goblin.act_slot === activation.NONE &&
      goblin.knocked < t &&
      goblinModel.is_alive(goblin) &&
      (resolved & (2 ** k)) === 0
    );
  });
  if (!free) return false;
  const board = rules.board;
  let frozen = 0n;
  let listed = 0;
  for (const goblin of world.goblins) {
    if (!goblinModel.is_alive(goblin) || goblin.awake) continue;
    const { x, y } = goblinModel.place(goblin);
    const spawn = Number(div(u16, BigInt(goblin.entity - FIRST_GOBLIN), BigInt(GOBLINS_STRIDE)));
    const chunk = add(u8, mul(u8, BigInt(Math.floor(y / 15)), 15n), BigInt(Math.floor(x / 15)));
    if (BigInt(spawn) !== chunk) listed = Number(add(u8, BigInt(listed), 1n));
    const position = boardPosition(board, x, y);
    if (position < FAR) frozen |= 1n << BigInt(position);
  }
  const out = aiClass({
    words: {
      clock: t,
      members: world.members.map(storeMember),
      goblins: set.map((index) => goblinModel.store(at(world.goblins, index))),
      killed: [],
      defeated: false,
    },
    content: rules.content,
    board,
    ground: rules.ground,
    level: rules.level,
    frozen,
    listed,
    resolved,
  });
  rules.ground = out.ground;
  const back = load(out.words, sheets);
  back.members.forEach((member, m) => {
    at(world.members, m);
    world.members[m] = member;
  });
  back.goblins.forEach((goblin, k) => {
    world.goblins[at(set, k)] = goblin;
  });
  world.killed.push(...out.words.killed);
  return is_down(world);
}

/**
 * `TickTrait::regenerate`: step 3, members, then the awake set, ascending. Out of combat is, for a
 * member, no goblin of the awake set Engaged; for a goblin, not Engaged. A goblin at 0 dies, in id
 * order.
 */
export function regenerate(world: World, sheets: Sheets): void {
  const t = world.clock;
  const engaged = world.goblins.some((goblin) => goblin.awake && goblin.ai === ai.ENGAGED);
  for (const member of world.members) {
    if (member.status === 0 && member.health > 0) memberRegenerate(member, t, engaged);
  }
  for (const goblin of world.goblins) {
    if (!goblin.awake || !goblinModel.is_alive(goblin)) continue;
    gm.regenerate(goblin, t, sheets);
    if (goblin.health === 0) {
      goblin.ai = ai.DEAD;
      world.killed.push(goblin.entity);
    }
  }
}

/**
 * `TickLibrary::ticks`, the class: the words loaded through the content, `run` with `Delegate`'s
 * rules and a fresh `Cache`; the words stored back and the ground the rules hold. Its inputs are
 * not changed.
 */
export const ticksClass: Classes["ticks"] = (call: TicksCall) => {
  const sheets = indexed(call.content);
  const world = load(call.words, sheets);
  const rules: Rules = {
    board: call.board,
    cache: cache(),
    ground: call.ground,
    content: call.content,
    level: call.level,
  };
  run(world, sheets, call.n, rules);
  return { words: store(world), ground: rules.ground };
};
