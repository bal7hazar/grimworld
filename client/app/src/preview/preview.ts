import { type BatchAction, type PlayAction, isFate } from "./actions";
import { type PlayTarget, previewCalls } from "./calls";
import { type ParityLog, type Predict, type Reconciliation, reconcile } from "./reconcile";
import type { Simulator } from "./rpc";
import { extractOutcome } from "./trace";

/**
 * The batch preview by simulation (D-257): the batch's multicall simulated against the current
 * state, the chain's own result read from the trace, and the mirror's prediction checked against
 * it. Simulation is exact for `play`: it draws no Fate (the only draw is `begin`'s), a reveal uses
 * the stored entropy and combat has no randomness.
 */

export interface PreviewInput extends PlayTarget {
  readonly actions: readonly BatchAction[];
}

export interface PreviewDeps {
  readonly simulator: Simulator;
  /** client/sim's segment on the same state; without it the mirror is "not mirrored". */
  readonly predict?: Predict;
  readonly log?: ParityLog;
}

/** Refused before anything is simulated, with the reason in one line. */
export type Refused = { kind: "refused"; reason: string };

export type Preview = Refused | ({ kind: "simulated" } & Reconciliation);

export const refusals = {
  FATE: "draws Fate from its own transaction and ends a batch: it is sent alone, never previewed",
  ENCODING: "a batch is 1 to 10 actions with their arguments in range",
} as const;

/**
 * The preview of a batch. A batch holding a Fate action, or one that does not encode, is refused
 * before any request. A `play` that panics is an outcome (`chain.kind` `reverted`, its reason), not
 * an exception; the simulator's own failures (the node unreachable, a refused request) do throw.
 */
export async function previewBatch(input: PreviewInput, deps: PreviewDeps): Promise<Preview> {
  const fate = input.actions.find(isFate);
  if (fate !== undefined) return { kind: "refused", reason: `${fate.kind} ${refusals.FATE}` };
  const actions = input.actions as readonly PlayAction[];
  const calls = previewCalls(input, actions);
  if (calls === undefined) return { kind: "refused", reason: refusals.ENCODING };
  const chain = extractOutcome(await deps.simulator.simulate(calls));
  return { kind: "simulated", ...reconcile(chain, actions, deps.predict, deps.log) };
}
