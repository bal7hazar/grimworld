// Where a played batch stops (ENG-07b, D-141): `SegmentTrait::admit` and `SegmentTrait::revealed`
// (`contracts/logic/src/types/play.cairo`), held equal to them by
// `contracts/logic/vectors/batch.jsonl`. E-16's cap of 16 goblin records an invocation and E-1's
// weight, which a first record raises by 1; a reveal weighs 2 a chunk. The rules, their edges and
// their reasons are the Cairo functions' documentation; this file decides none.

import { add, narrow, u32, u8 } from "./felt";

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
  const records = Number(add(u32, BigInt(changed), BigInt(fresh)));
  if (ran && (records > MAX_RECORDS || total > weight)) return undefined;
  return weight > total ? weight - total : 0;
}

/**
 * `SegmentTrait::revealed`: the weight left after a reveal of `chunks` chunks, taken from the
 * weight left after the Move that caused it, floored at 0.
 */
export function revealed(weight: number, chunks: number): number {
  const cost = Number(narrow(u8, BigInt(CHUNK_WEIGHT * chunks)));
  return weight > cost ? weight - cost : 0;
}
