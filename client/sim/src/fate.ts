// Values from a Fate word (ADR-0002, rule 2): the mirror of `contracts/logic/src/fate.cairo`, held
// equal to it by `contracts/logic/vectors/fate.jsonl` (VEC-01). A domain is
// `poseidon(subject, counter, purpose)`, a value `poseidon(word, domain, index)`; Poseidon is
// `poseidon_hash_span`, the Starknet sponge, which `@scure/starknet`'s `poseidonHashMany` computes.

import { poseidonHashMany } from "@scure/starknet";
import { arg, feltArg, shortString, u32 } from "./felt";

/** The entry draw of a location (design/02). */
export const ENTRY = shortString("fate:entry");
/** What remains hold, a boss's drop included (design/15). */
export const LOOT = shortString("fate:loot");
/** A chest's content (design/18). */
export const CHEST = shortString("fate:chest");
/** Identifying an item (design/15). */
export const IDENTIFY = shortString("fate:identify");
/** Lifting a modifier without a stillstone (design/15). */
export const LIFT = shortString("fate:lift");
/** Brewing a pair not yet tried (design/07). */
export const BREW = shortString("fate:brew");
/** A hint of a book (design/07). */
export const HINT = shortString("fate:hint");
/** The day's five Rift identities (design/17). */
export const RIFT_BOARD = shortString("fate:rift-board");

/** Every purpose, in Cairo's order (`fate::PURPOSES`). */
export const PURPOSES: readonly bigint[] = [
  ENTRY,
  LOOT,
  CHEST,
  IDENTIFY,
  LIFT,
  BREW,
  HINT,
  RIFT_BOARD,
];

/** The domain of one draw: `poseidon(subject, counter, purpose)`. */
export function domain(subject: bigint, counter: bigint, purpose: bigint): bigint {
  return poseidonHashMany([feltArg(subject), feltArg(counter), feltArg(purpose)]);
}

/** The value at `index` (a `u32`) of a decision drawn under `domain`: `poseidon(word, domain, index)`. */
export function derive(word: bigint, domain: bigint, index: number): bigint {
  return poseidonHashMany([feltArg(word), feltArg(domain), arg(u32, BigInt(index))]);
}
