// A trap's trigger (CLI-02g-D, D-257): the mirror of `contracts/logic/src/types/trap.cairo`'s
// `TrapTrait` (the lookup, the source, the trigger) and of `TrapLibrary::trigger`
// (`contracts/logic/src/systems/trap.cairo`), held equal to them by `contracts/logic/vectors/
// trap.jsonl`. `trigger` is the class itself, computed: `run`'s seam (`segment/classes.ts`) takes
// it for `Classes.trigger`. Placing a trap (`spot`, `place`) is `act`'s (lot E); `free`, its index,
// is here with the lookup it shares.

import { NONE, type Infliction } from "./body/infliction";
import * as m from "./body/member";
import type { Entry } from "./effect";
import { kind } from "./effect";
import * as executor from "./executor";
import { type Actor, type Board, entry, guards } from "./executor";
import { panic } from "./felt";
import { ORIGIN, position as boardPosition } from "./movement";
import {
  is_alive as is_goblin_alive,
  level as goblinLevel,
  place as goblinPlace,
} from "./segment/goblin";
import type { Features } from "./reveal";
import type { Ground } from "./segment/serde";
import type { Classes, TriggerCall } from "./segment/classes";
import { ABSENT_LANE, type Sheets, is_alive, place, sheets as indexed } from "./segment/words";
import { type World, world as load, words as store } from "./segment/world";
import { FAR } from "./window";

/** `chunk::object`: the kinds a trap is (`TRAP`, a terrain one; `PLACED_TRAP`, an actor's). */
export const object = { NONE: 0, TRAP: 4, PLACED_TRAP: 9 } as const;
/** The used state of an object. */
const USED = 1;
/** Every guard of a terrain trap's payload holds: its entries carry none (FX-14). */
const ALL_HELD = 7;
/** A chunk's side, and a location's chunks (`types::CHUNK_SIDE`, `MAX_CHUNKS`). */
const CHUNK_SIDE = 15;
const MAX_CHUNKS = 225;
const OUT = "Index out of bounds";
const UNWRAP = "Option::unwrap failed.";

type Object = Features["objects"][number];

/** `combat::Placer` of a placed trap's `param`: `(member, bar slot)` or `(entity, caste slot)`. */
export type Placer =
  { kind: "M"; member: number; slot: number } | { kind: "G"; entity: number; slot: number };

/** `PlacerTrait::from_param`: a goblin's above `0x8000`, a member's below. */
export function from_param(param: number): Placer {
  if (param >= 0x8000) {
    const rest = param - 0x8000;
    return {
      kind: "G",
      entity: (rest % 0x1000) + executor.FIRST_GOBLIN,
      slot: Math.floor(rest / 0x1000),
    };
  }
  const slot = Math.floor(param / 8);
  // `slot.try_into().unwrap()`: a `u8`
  if (slot > 0xff) panic(UNWRAP);
  return { kind: "M", member: param % 8, slot };
}

/** `TrapTrait::locate`: the chunk `15 cy + cx` and its tile `15 ly + lx` of the window's `position`. */
export function locate(board: Board, position: number): [number, number] | undefined {
  if (position >= FAR || position >= 240) return undefined;
  const [dy, dx] = [Math.floor(position / 15), position % 15];
  // The location's tile: the board's origin is held plus `ORIGIN` (D-134)
  const [x, y] = [board.x + dx, board.y + dy];
  // Cairo's guard, before its `x - ORIGIN` would underflow; its removal is not killed by any row
  // (a table hole, RV-03a2: `mutants.test.ts`)
  if (x < ORIGIN || y < ORIGIN) return undefined;
  const [cy, ly] = [Math.floor((y - ORIGIN) / 15), (y - ORIGIN) % 15];
  const [cx, lx] = [Math.floor((x - ORIGIN) / 15), (x - ORIGIN) % 15];
  const chunk = cy * CHUNK_SIDE + cx;
  if (chunk >= MAX_CHUNKS || cx >= CHUNK_SIDE) return undefined;
  return [chunk, ly * CHUNK_SIDE + lx];
}

/** `TrapTrait::is_trap`: a terrain trap or a placed one. */
const is_trap = (o: Object): boolean => o.kind === object.TRAP || o.kind === object.PLACED_TRAP;

/**
 * `TrapTrait::free`: the object index a trap placed on `tile` takes, the lowest that is empty or a
 * used trap; none when the tile holds another object, or no index is free.
 */
export function free(features: Features, tile: number): number | undefined {
  let found: number | undefined;
  for (const [k, o] of features.objects.entries()) {
    const spent = is_trap(o) && o.state === USED;
    if (o.kind !== object.NONE && !spent && o.tile === tile) return undefined;
    if (found === undefined && (o.kind === object.NONE || spent)) found = k;
  }
  return found;
}

/** `TrapTrait::occupied`: a living actor stands on the window's `position` (remains do not block). */
export function occupied(world: World, board: Board, position: number): boolean {
  for (const member of world.members) {
    const { x, y } = place(member);
    if (is_alive(member) && boardPosition(board, x, y) === position) return true;
  }
  return world.goblins.filter(is_goblin_alive).some((goblin) => {
    const { x, y } = goblinPlace(goblin);
    return boardPosition(board, x, y) === position;
  });
}

/** `TrapTrait::write`: the ground's chunk at `entry` with object `index` replaced. */
export function write(ground: Ground, at: number, index: number, o: Object): Ground {
  return ground.map(([chunk, features], k) => {
    if (k !== at) return [chunk, features];
    // Index 0, 1, or else 2, as Cairo's
    const objects = features.objects.map((old, i) => (i === Math.min(index, 2) ? o : old));
    return [chunk, { ...features, objects }];
  });
}

/** A trap's source (§5.11 step 1): `(payload, rank, level, held, infliction)`. */
type Source = {
  payload: number;
  rank: number;
  level: number;
  held: number;
  infliction: Infliction;
};

/** `TrapTrait::entries`: the skill at `at`'s entries, up to the first empty one. */
export function entries(sheets: Sheets, at: number): Entry[] {
  const list: Entry[] = [];
  for (let k = 0; k < 3; k++) {
    const e = entry(sheets, at, k);
    if (e.kind === kind.EMPTY) break;
    list.push(e);
  }
  return list;
}

/** `TrapTrait::terrain`: its `SKILL` found in the sheets, the band's lower level, rank 0. */
export function terrain(sheets: Sheets, skill: number, level: number): Source | undefined {
  const payload = sheets.skills.findIndex((sheet) => sheet.id === skill);
  if (payload < 0) return undefined;
  return { payload, rank: 0, level, held: ALL_HELD, infliction: NONE };
}

/** `TrapTrait::by_member`: its bar slot's skill at the slot's rank, its level, its guards now. */
export function by_member(
  world: World,
  sheets: Sheets,
  i: number,
  slot: number,
): Source | undefined {
  if (i >= world.members.length) return undefined;
  const member = world.members[i]!;
  const payload = executor.position(member, slot);
  if (payload === ABSENT_LANE) return undefined;
  const held = guards({ kind: "M", member }, entries(sheets, payload));
  return {
    payload,
    rank: executor.rank(member, slot),
    level: executor.level(member),
    held,
    infliction: m.infliction(member),
  };
}

/**
 * `TrapTrait::by_goblin`: the placer's caste skill `slot`, its record's level, its caste's rank (a
 * dead placer's record still holds them); none if the call does not carry it.
 */
export function by_goblin(
  world: World,
  sheets: Sheets,
  entity: number,
  slot: number,
): Source | undefined {
  const i = executor.find(world, entity);
  if (i === undefined) return undefined;
  const goblin = world.goblins[i]!;
  const kit = sheets.kits[goblin.caste_at];
  if (kit === undefined) panic(OUT);
  const payload = kit.skills[slot];
  if (payload === undefined) panic(OUT);
  const held = guards({ kind: "G", goblin }, entries(sheets, payload));
  const rank = sheets.castes[goblin.caste_at]!.rank;
  return { payload, rank, level: goblinLevel(goblin), held, infliction: NONE };
}

/**
 * `TrapTrait::trigger`: the tile's unused trap after `entrant` entered the window's `position`,
 * triggered once if the entrant is a foe of its side (a placed trap: its placer's foes; a terrain
 * trap: members only), its payload through the executor, then the object marked used. Returns the
 * ground after and whether a trap triggered; the world is changed in place.
 */
export function trigger(
  c: executor.Cache,
  world: World,
  sheets: Sheets,
  ground: Ground,
  board: Board,
  entrant: Actor,
  position: number,
  level: number,
): { ground: Ground; triggered: boolean } {
  const untouched = { ground, triggered: false };
  const where = locate(board, position);
  if (where === undefined) return untouched;
  const [chunk, tile] = where;
  // The first entry of the chunk alone is read
  const at = ground.findIndex(([c]) => c === chunk);
  if (at < 0) return untouched;
  const index = ground[at]![1].objects.findIndex(
    (o) => is_trap(o) && o.state !== USED && o.tile === tile,
  );
  if (index < 0) return untouched;
  const trap = ground[at]![1].objects[index]!;
  const on_member = entrant.kind === "M";
  let source: Source | undefined;
  if (trap.kind === object.TRAP) {
    if (!on_member) return untouched;
    source = terrain(sheets, trap.param, level);
  } else {
    const placer = from_param(trap.param);
    if (placer.kind === "M") {
      if (on_member) return untouched;
      source = by_member(world, sheets, placer.member, placer.slot);
    } else {
      if (!on_member) return untouched;
      source = by_goblin(world, sheets, placer.entity, placer.slot);
    }
  }
  if (source === undefined) return untouched;
  executor.trigger(
    c,
    world,
    sheets,
    source.payload,
    source.rank,
    source.level,
    source.held,
    source.infliction,
    entrant,
    world.clock,
  );
  return { ground: write(ground, at, index, { ...trap, state: USED }), triggered: true };
}

/**
 * `TrapLibrary::trigger`, the class: the words loaded through the content, the entrant found by
 * its entity (none, nothing triggers), `TrapTrait::trigger` with a fresh `Cache`, the words stored
 * back. Its inputs are not changed.
 */
export const triggerClass: Classes["trigger"] = (call: TriggerCall) => {
  const sheets = indexed(call.content);
  const world = load(call.words, sheets);
  const found = executor.actor(world, call.entrant);
  let ground = call.ground;
  let triggered = false;
  if (found !== undefined) {
    ({ ground, triggered } = trigger(
      executor.cache(),
      world,
      sheets,
      call.ground,
      call.board,
      found,
      call.position,
      call.level,
    ));
  }
  return { words: store(world), ground, triggered };
};
