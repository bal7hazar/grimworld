// The tables the mirror replays, one entry each: the file in `contracts/logic/vectors/`, its floor
// (the cases it holds today: a table that loses cases fails) and the mirror's function per `fn`,
// adapting the felts of a case to the mirror's arguments and its result to Cairo's `Serde`.
// A new table of the game is one entry here.

import { fromFelt, u8 } from "../felt";
import { hitFromFelts, outcomeToFelts, resolve } from "../hit";
import { arc, distance, facing, front, reach, shape, sight } from "../window";
import type { Entry, Mirror } from "./replay";

/** The felts of a case, exactly `count` of them. */
function args(felts: readonly bigint[], count: number): readonly bigint[] {
  if (felts.length !== count) throw new RangeError(`${felts.length} arguments, expected ${count}`);
  return felts;
}

/** A `u8` argument (a position, a facing, a range, a shape) as the mirror's `number`. */
const small = (felt: bigint): number => Number(fromFelt(u8, felt));
const bool = (value: boolean): bigint[] => [value ? 1n : 0n];

const window: Record<string, Mirror> = {
  sight: (c) => {
    const [open, from, to] = args(c, 3);
    return bool(sight(open!, small(from!), small(to!)));
  },
  reach: (c) => {
    const [open, from, to, range] = args(c, 4);
    return bool(reach(open!, small(from!), small(to!), small(range!)));
  },
  arc: (c) => {
    const [source, target, facing] = args(c, 3);
    const result = arc(small(source!), small(target!), small(facing!));
    return result === undefined ? [1n] : [0n, BigInt(result)];
  },
  facing: (c) => {
    const [from, to, turn] = args(c, 3);
    return [BigInt(facing(small(from!), small(to!), small(turn!)))];
  },
  front: (c) => {
    const [source, target, facing] = args(c, 3);
    return bool(front(small(source!), small(target!), small(facing!)));
  },
  distance: (c) => {
    const [from, to] = args(c, 2);
    return [BigInt(distance(small(from!), small(to!)))];
  },
  shape: (c) => {
    const [open, id, centre] = args(c, 3);
    return [shape(open!, small(id!), small(centre!))];
  },
};

const hit: Record<string, Mirror> = {
  "": (c) => outcomeToFelts(resolve(...hitFromFelts(c))),
};

export const TABLES: readonly Entry[] = [
  { file: "window.jsonl", floor: 2065, fns: window },
  { file: "hit.jsonl", floor: 200, fns: hit },
];
