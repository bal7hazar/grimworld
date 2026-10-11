import type { PlayAction } from "./actions";
import { type ChainOutcome, Stop } from "./trace";

/**
 * The chain's result of a batch against the mirror's prediction (D-257): the chain wins, and every
 * field both produce that differs is a parity bug, logged.
 *
 * The prediction is client/sim's `runSegment` on the same state, passed in as `Predict` (the app
 * does not depend on client/sim yet): its `Ran` fits `Prediction` as it is, so the wiring is
 * `(actions) => runSegment({ ...segment, actions }, classes)`. A segment that reaches a class the
 * mirror does not port throws `NotMirrored`: that is no prediction, never a mismatch. So are the
 * parts of a batch beyond one segment: a reveal (the chain reveals, then runs the next segment) and
 * a batch refused at admission (sequence, closed, version: nothing ran, the client's state is old).
 */

/** client/sim's `MemberWords`, as `Words` holds them (stored layout). */
export type MirrorMemberWords = {
  state: bigint;
  timers: bigint;
  effects: bigint;
  recharges: bigint;
  stats: bigint;
  bar: bigint;
  kit: bigint;
};

/** client/sim's `Words`, the fields compared. */
export type MirrorWords = {
  clock: number;
  members: readonly MirrorMemberWords[];
  goblins: readonly { entity: number; awake: boolean; state: bigint; timers: bigint }[];
  killed: readonly number[];
  defeated: boolean;
};

/** client/sim's `Done`, the fields read. */
export type MirrorDone = {
  played: number;
  reveal: boolean;
  illegal: number | undefined;
  heavy: boolean;
  undo: boolean;
};

/** client/sim's `Ran`, the fields read. */
export type Prediction = { words: MirrorWords; done: MirrorDone };

/** The mirror run on the batch's state with these actions; may throw `NotMirrored`. */
export type Predict = (actions: readonly PlayAction[]) => Prediction;

export type MirrorResult =
  | { kind: "predicted"; played: number; stop: Stop; words: MirrorWords }
  | { kind: "not-mirrored"; reason: string };

export type Mismatch = { field: string; chain: unknown; mirror: unknown };

export type Reconciliation = { chain: ChainOutcome; mirror: MirrorResult; mismatches: Mismatch[] };

/** A parity bug, as the console receives it now and a reporting hook later. */
export type ParityRecord = {
  kind: "grimworld.parity";
  actions: readonly PlayAction[];
  mismatches: Mismatch[];
};

export type ParityLog = (record: ParityRecord) => void;

export const consoleParityLog: ParityLog = (record) => console.warn(record.kind, record);

const MEMBER_KEYS = ["state", "timers", "effects", "recharges", "stats", "bar", "kit"] as const;

/** The admission's stops: nothing ran, the mirror has nothing to say. */
const ADMISSION = new Set<Stop>([Stop.Sequence, Stop.Closed, Stop.Version]);

const notMirrored = (reason: string): MirrorResult => ({ kind: "not-mirrored", reason });

/**
 * `PlayLibrary`'s loop over one segment (contracts/ephemeral/src/systems/play.cairo, around the
 * `segment.segment` call): a `done.undo` runs the segment again on the actions before the one that
 * stopped it and keeps those words; the stop is the first `done`'s.
 */
function predict(actions: readonly PlayAction[], run: Predict): MirrorResult {
  let first: Prediction;
  let words: MirrorWords;
  try {
    first = run(actions);
    if (first.done.reveal) {
      return notMirrored("a Move revealed a chunk: the reveal and what follows are not mirrored");
    }
    words = first.done.undo ? run(actions.slice(0, first.done.played)).words : first.words;
  } catch (error) {
    if (error instanceof Error && error.name === "NotMirrored") return notMirrored(error.message);
    throw error;
  }
  const { done } = first;
  const stop =
    done.illegal !== undefined
      ? Stop.Invalid
      : done.heavy
        ? Stop.Weight
        : words.defeated
          ? Stop.Defeated
          : Stop.None;
  return { kind: "predicted", played: done.played, stop, words };
}

/**
 * Compares the chain's outcome with the mirror's on every field both produce: the actions played,
 * the stop, the clock, the defeat, the goblins killed; and, while the instance stays open (closing
 * writes beyond the segment), each member's seven words and each goblin both list (by entity:
 * the view lists the windows' goblins, the mirror the ones its world loaded).
 */
export function reconcile(
  chain: ChainOutcome,
  actions: readonly PlayAction[],
  run: Predict | undefined,
  log: ParityLog = consoleParityLog,
): Reconciliation {
  let mirror: MirrorResult;
  if (chain.kind === "reverted") mirror = notMirrored("the chain reverted: nothing ran");
  else if (ADMISSION.has(chain.batch.stop)) {
    mirror = notMirrored(`refused at admission (stop ${chain.batch.stop}): nothing ran`);
  } else if (run === undefined) mirror = notMirrored("no mirror wired");
  else mirror = predict(actions, run);
  if (chain.kind === "reverted" || mirror.kind === "not-mirrored") {
    return { chain, mirror, mismatches: [] };
  }
  const mismatches: Mismatch[] = [];
  const check = (field: string, onChain: unknown, mirrored: unknown) => {
    if (onChain !== mirrored) mismatches.push({ field, chain: onChain, mirror: mirrored });
  };
  const { words } = mirror;
  check("played", chain.batch.played, mirror.played);
  check("stop", chain.batch.stop, mirror.stop);
  check("clock", chain.view.header.clock, words.clock);
  check("defeated", chain.defeated, words.defeated);
  const sorted = (entities: readonly number[]) => [...entities].sort((a, b) => a - b).join(",");
  check("killed", sorted(chain.killed.map((k) => k.entity)), sorted(words.killed));
  if (chain.closed === undefined) {
    words.members.forEach((member, i) => {
      const onChain = chain.view.members[i];
      if (onChain === undefined) {
        mismatches.push({ field: `members[${i}]`, chain: undefined, mirror: member });
        return;
      }
      for (const key of MEMBER_KEYS) check(`members[${i}].${key}`, onChain[key], member[key]);
    });
    for (const goblin of words.goblins) {
      const onChain = chain.view.goblins.find((g) => g.entity === goblin.entity);
      if (onChain === undefined) continue;
      check(`goblins[${goblin.entity}].state`, onChain.state, goblin.state);
      check(`goblins[${goblin.entity}].timers`, onChain.timers, goblin.timers);
    }
  }
  if (mismatches.length > 0) log({ kind: "grimworld.parity", actions, mismatches });
  return { chain, mirror, mismatches };
}
