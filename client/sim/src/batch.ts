// Two functions of the batch's stop points, `SegmentTrait::admit` and `SegmentTrait::revealed`
// (`contracts/logic/src/types/play.cairo`; ENG-07b, D-141), held equal to them by
// `contracts/logic/vectors/batch.jsonl`: E-16's cap of 16 goblin records an invocation, E-1's
// weight (a first record raises it by 1), and a reveal's 2 a chunk. This file mirrors those two
// only; the rules, their edges and their reasons are the Cairo functions' documentation.
//
// A preview of a batch also needs `SegmentTrait::run`'s composition, not mirrored here: the owed
// ticks' fold, the Move counted before `revealed`, the cost `max(1, ticks)`, the `cost > weight`
// check, the `ran` rule, the stop after a reveal Move, and `fits`. A later lot mirrors them.

import { add, mul, narrow, u32, u8 } from "./felt";

/** E-16: the goblin records an invocation may count before a later action stops. */
export const MAX_RECORDS = 16;
/** A reveal's weight a chunk (design/02). */
export const CHUNK_WEIGHT = 2;

/**
 * `SegmentTrait::admit`: with `changed` records counted before an action, `fresh` new ones,
 * `firsts` of them first records and `cost` ticks, the weight left after it, floored at 0;
 * `undefined` (`None`) when `ran` (not the invocation's first action, E-21) and it would pass
 * `MAX_RECORDS` or the weight.
 */
export function admit(
  changed: number,
  fresh: number,
  firsts: number,
  cost: number,
  ran: boolean,
  weight: number,
): number | undefined {
  const total = Number(add(u8, BigInt(cost), BigInt(firsts)));
  // `ran &&` short-circuits: with `ran` false the u32 sum is never computed (it may overflow)
  if (ran && (Number(add(u32, BigInt(changed), BigInt(fresh))) > MAX_RECORDS || total > weight)) {
    return undefined;
  }
  return weight > total ? weight - total : 0;
}

/**
 * `SegmentTrait::revealed`: the weight left after a reveal of `chunks` chunks, taken from the
 * weight left after the Move that caused it, floored at 0.
 */
export function revealed(weight: number, chunks: number): number {
  // `chunks.try_into().unwrap()` first, then the product in u8
  const cost = Number(mul(u8, BigInt(CHUNK_WEIGHT), narrow(u8, BigInt(chunks))));
  return weight > cost ? weight - cost : 0;
}
