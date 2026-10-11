// The seam between `SegmentTrait::run` and the three classes it calls (CLI-02g-A, D-254, D-255):
// `TickLibrary::ticks`, `ActionLibrary::act`, `TrapLibrary::trigger`, one interface. `run`
// computes each call's inputs itself and passes them here; what a class returns is loaded back as
// `run` loads it (`SegmentTrait::reload`). The parity tests plug in a replayer of the recorded
// calls (`parity/replayer.ts`); lots D to F replace it, class by class, with ports.
//
// A call's digest is the Poseidon hash of its inputs' `Serde` felts, the content and the class
// hashes left out, in the recorders' order (`types/play/tests/recorder.cairo`).

import { poseidonHashMany } from "@scure/starknet";
import {
  type Action,
  type Board,
  type Ground,
  type Outcome,
  writeAction,
  writeBoard,
  writeGround,
  writeWords,
} from "./serde";
import type { Content, Words } from "./words";

/** `TickLibrary::ticks(words, content, board, classes, level, ground, n)`. */
export type TicksCall = {
  words: Words;
  content: Content;
  board: Board;
  level: number;
  ground: Ground;
  n: number;
};

/** `ActionLibrary::act(words, content, board, executor, ground, action)`. */
export type ActCall = {
  words: Words;
  content: Content;
  board: Board;
  ground: Ground;
  action: Action;
};

/** `TrapLibrary::trigger(words, content, board, ground, entrant, position, level)`. */
export type TriggerCall = {
  words: Words;
  content: Content;
  board: Board;
  ground: Ground;
  entrant: number;
  position: number;
  level: number;
};

/** The classes a segment calls: each returns the words and the ground after it. */
export type Classes = {
  ticks(call: TicksCall): { words: Words; ground: Ground };
  act(call: ActCall): { words: Words; ground: Ground; outcome: Outcome };
  trigger(call: TriggerCall): { words: Words; ground: Ground; triggered: boolean };
};

/** The digest of a call's inputs (`recorder::digest`), by the call's kind. */
export const digest = {
  ticks: (c: TicksCall): bigint =>
    poseidonHashMany([
      ...writeWords(c.words),
      ...writeBoard(c.board),
      BigInt(c.level),
      ...writeGround(c.ground),
      BigInt(c.n),
    ]),
  act: (c: ActCall): bigint =>
    poseidonHashMany([
      ...writeWords(c.words),
      ...writeBoard(c.board),
      ...writeGround(c.ground),
      ...writeAction(c.action),
    ]),
  trigger: (c: TriggerCall): bigint =>
    poseidonHashMany([
      ...writeWords(c.words),
      ...writeBoard(c.board),
      ...writeGround(c.ground),
      BigInt(c.entrant),
      BigInt(c.position),
      BigInt(c.level),
    ]),
} as const;
