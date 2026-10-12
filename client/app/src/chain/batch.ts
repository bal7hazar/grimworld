import { MAX_ACTIONS, type PlayAction } from "../preview/actions";
import { Stop } from "../preview/trace";

/**
 * The batch of the chain mode (CLI-11 §4.2): the actions planned, in order, and where a batch
 * ends. The client counts as the contract does and sets no limit of its own: 10 actions is the
 * encoding's bound (`MAX_ACTIONS`); the chain's stops (weight, the goblin records) are the
 * preview's to say, the mirror's at once and the simulation's where the mirror does not predict.
 * This module only applies what a preview or a sent batch said:
 * - `Stop.Weight`: the batch is full; the action that did not fit is kept, it opens the next one;
 * - `Stop.Invalid`: the actions played stay, the refused one and every one after it are dropped
 *   (design/02: an invalid action drops the rest);
 * - `Stop.Sequence`, `Stop.Version`: nothing ran; every action stays, and the state and the
 *   content version are read again;
 * - `Stop.Defeated`, `Stop.Closed`, or a batch that closed the instance: the batch and the
 *   instance end;
 * - after each sent batch, the steps of a path not played yet are dropped: the player taps again.
 */

/** One planned action; `path` marks a step of a tapped path (§4.1), dropped once a batch is sent. */
export type Planned = { readonly action: PlayAction; readonly path: boolean };

export type Batch = readonly Planned[];

/** What a preview or a sent batch says of it: the actions played and the stop. */
export type Played = { readonly played: number; readonly stop: Stop };

/** Where a sent batch leaves the plan. */
export type Ending =
  /** The batch ran (wholly or in part); `planned` opens the next one. */
  | { kind: "next"; planned: Batch }
  /** Refused at admission: nothing ran, every action stays, the state is read again. */
  | { kind: "reread"; planned: Batch }
  /** The instance ended (a defeat, a closing): nothing stays planned. */
  | { kind: "closed" };

export const actionsOf = (batch: Batch): PlayAction[] => batch.map((p) => p.action);

/** The actions a batch can still take. */
export const roomOf = (batch: Batch): number => Math.max(0, MAX_ACTIONS - batch.length);

/** Full: 10 actions, or a preview stopped by the weight. A full batch takes no input until sent. */
export function isFull(batch: Batch, stop?: Stop): boolean {
  return roomOf(batch) === 0 || stop === Stop.Weight;
}

/**
 * The batch with `actions` added, cut to its room (a path longer than the room plays its first
 * steps); the batch as it is when full.
 */
export function add(
  batch: Batch,
  actions: readonly PlayAction[],
  options: { path?: boolean; stop?: Stop } = {},
): Batch {
  if (isFull(batch, options.stop)) return batch;
  const path = options.path ?? false;
  return [...batch, ...actions.slice(0, roomOf(batch)).map((action) => ({ action, path }))];
}

/** The admission's refusals: the client's state is old, nothing ran. */
const STALE = new Set<Stop>([Stop.Sequence, Stop.Version]);

export const isStale = (stop: Stop): boolean => STALE.has(stop);

/**
 * The batch after its preview: a `Stop.Invalid` drops the refused action and every one after it
 * (all of them for a batch refused before its first action); any other stop leaves it as it is.
 */
export function afterPreview(batch: Batch, { played, stop }: Played): Batch {
  return stop === Stop.Invalid ? batch.slice(0, played) : batch;
}

/**
 * The plan after a sent batch: what it played is gone; of the rest, `Stop.Weight` keeps the action
 * that did not fit and the actions after it but the path's steps, `Stop.Invalid` drops everything,
 * any other stop keeps all but the path's steps.
 */
export function afterSend(
  batch: Batch,
  outcome: Played & { readonly defeated?: boolean; readonly closed?: number },
): Ending {
  const { played, stop } = outcome;
  if (
    stop === Stop.Defeated ||
    stop === Stop.Closed ||
    outcome.defeated === true ||
    outcome.closed !== undefined
  ) {
    return { kind: "closed" };
  }
  if (isStale(stop)) return { kind: "reread", planned: batch };
  const rest = batch.slice(played);
  if (stop === Stop.Invalid) return { kind: "next", planned: [] };
  const steps = (planned: Batch) => planned.filter((p) => !p.path);
  if (stop === Stop.Weight) {
    const [unplayed, ...after] = rest;
    return { kind: "next", planned: unplayed === undefined ? [] : [unplayed, ...steps(after)] };
  }
  return { kind: "next", planned: steps(rest) };
}
