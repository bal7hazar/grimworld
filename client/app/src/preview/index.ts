/**
 * The batch preview by simulation (CLI-10a, D-257): what the game imports. No screen shows it yet;
 * the planned queue (`sandbox/session.ts`) is where it goes once the client plays on chain.
 */
export type { BatchAction, FateAction, PlayAction, Target } from "./actions";
export { MAX_ACTIONS, encodeAction, encodeBatch, isFate } from "./actions";
export type { PlayTarget } from "./calls";
export { executeCalldata, previewCalls, selector } from "./calls";
export type { Preview, PreviewDeps, PreviewInput, Refused } from "./preview";
export { previewBatch, refusals } from "./preview";
export type {
  Mismatch,
  MirrorDone,
  MirrorMemberWords,
  MirrorResult,
  MirrorWords,
  ParityLog,
  ParityRecord,
  Predict,
  Prediction,
  Reconciliation,
} from "./reconcile";
export { consoleParityLog, reconcile } from "./reconcile";
export type { ResourceBound, RpcSimulatorConfig, Simulator } from "./rpc";
export { SimulationError, createRpcSimulator } from "./rpc";
export type {
  BatchPlayed,
  ChainOutcome,
  FunctionInvocation,
  GoblinKilled,
  InvokeTrace,
  Played,
  Reverted,
  TraceEvent,
} from "./trace";
export { Outcome, Stop, TraceError, eventSelector, extractOutcome, panicReason } from "./trace";
export type { GoblinView, Header, InstanceView, MemberView, RegionChunk } from "./view";
export { ChunkKind, decodeInstanceView, encodeInstanceView, unpackHeader } from "./view";
