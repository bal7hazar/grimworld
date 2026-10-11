import { type InstanceView, decodeInstanceView } from "./view";

/**
 * What the chain answers a simulated batch with, taken from the trace of `starknet_simulateTransactions`
 * (starknet-specs v0.8+, `starknet_trace_api_openrpc.json`: `INVOKE_TXN_TRACE`,
 * `FUNCTION_INVOCATION`, `ORDERED_EVENT`). Only the fields read are typed; felts are hex strings.
 *
 * The account's `__execute__` is `execute_invocation`; its `calls` are the multicall's, in order:
 * `play`, then `instance_state`. `play`'s body runs in `PlayLibrary` by `library_call`, so most of
 * its events sit in a nested invocation: they are collected from the whole subtree of `play` and
 * put back in the execution's order (`order`).
 */

export type TraceEvent = { order?: number; keys: readonly string[]; data: readonly string[] };

export type FunctionInvocation = {
  contract_address?: string;
  entry_point_selector?: string;
  /** The call's return, as felts. */
  result: readonly string[];
  calls: readonly FunctionInvocation[];
  events: readonly TraceEvent[];
  /** v0.8: an inner call that failed and was caught. */
  is_reverted?: boolean;
};

/** `INVOKE_TXN_TRACE`, the part read. */
export type InvokeTrace = {
  type?: "INVOKE";
  execute_invocation: FunctionInvocation | { revert_reason: string };
};

/** Event selectors (`sn_keccak` of the names), held to starknet.js's by `calls.test.ts`. */
export const eventSelector = {
  BatchPlayed: 0x26842a87b04dae550c97a6f2a1e36c2cb714a15a696322f03e3019023f9f1ebn,
  GoblinKilled: 0x35fda013e8e6a6c6a712506bd0f0dd00c23a211ec726334e5db64566dd19fb6n,
  ChunkRevealed: 0x2959f53785b944820da6582143d3f2c78c528f286aefd541ce61c0fe6fc4204n,
  Defeated: 0x2ad55916176bdb43a2d8d2a6d01c6aa4ac34123d5664c1324c443960d27ab7bn,
  InstanceClosed: 0x9bc680e05fe8ff80e30b61548c6af8921d7e7f115164652d117d6b74916128n,
} as const;

/** `types::Stop`, by index. */
export const Stop = {
  None: 0,
  Sequence: 1,
  Invalid: 2,
  Weight: 3,
  Defeated: 4,
  Closed: 5,
  Version: 6,
} as const;
export type Stop = (typeof Stop)[keyof typeof Stop];

/** `types::Outcome`, by index. */
export const Outcome = { Open: 0, Returned: 1, Defeated: 2, Moved: 3 } as const;
export type Outcome = (typeof Outcome)[keyof typeof Outcome];

/** `events::BatchPlayed` (contracts/ephemeral/src/events.cairo :23). */
export type BatchPlayed = {
  instanceId: bigint;
  adventurerId: number;
  from: number;
  played: number;
  stop: Stop;
  sequence: number;
  clock: number;
  version: number;
};

/** `events::GoblinKilled`. */
export type GoblinKilled = { entity: number; caste: number; tile: number; by: number };

/** The chain's result of a batch that ran (it may still have stopped early: `batch.stop`). */
export type Played = {
  kind: "played";
  batch: BatchPlayed;
  killed: GoblinKilled[];
  /** The chunks revealed, in order. */
  revealed: number[];
  defeated: boolean;
  /** `InstanceClosed`'s outcome when the batch closed the instance. */
  closed: Outcome | undefined;
  /** The state after the batch, from `instance_state`. */
  view: InstanceView;
};

/** The execution panicked: nothing it did holds. `reason` is the panic's message when it has one. */
export type Reverted = { kind: "reverted"; reason: string; raw: string };

export type ChainOutcome = Played | Reverted;

/** A trace this module cannot read (a node's error, or a shape outside the spec). */
export class TraceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TraceError";
  }
}

/** The account's frames around a panic, not its reason. */
const WRAPPERS = new Set(["ENTRYPOINT_FAILED", "argent/multicall-failed"]);

/**
 * The panic's message in a node's `revert_reason`: the first short string quoted in it
 * (`0x… ('message')`) that is not one of the frames the call stack adds; the whole text when none.
 */
export function panicReason(raw: string): string {
  for (const match of raw.matchAll(/\('([^']*)'\)/g)) {
    const text = match[1] ?? "";
    if (text !== "" && !WRAPPERS.has(text)) return text;
  }
  return raw.trim();
}

const felt = (hex: string | undefined): bigint => {
  if (hex === undefined) throw new TraceError("a felt is missing");
  return BigInt(hex);
};
const small = (hex: string | undefined, width: number): number => {
  const value = felt(hex);
  if (value >= 1n << BigInt(width)) throw new TraceError(`${hex} above u${width}`);
  return Number(value);
};
const index = (hex: string | undefined, variants: number): number => {
  const value = felt(hex);
  if (value >= BigInt(variants)) throw new TraceError(`variant ${hex} of ${variants}`);
  return Number(value);
};

/** Every event of an invocation and of the calls under it, in the execution's order. */
function eventsOf(call: FunctionInvocation): TraceEvent[] {
  const all: TraceEvent[] = [];
  const walk = (at: FunctionInvocation) => {
    all.push(...at.events);
    at.calls.forEach(walk);
  };
  walk(call);
  return all
    .map((event, i) => ({ event, i }))
    .sort((a, b) => (a.event.order ?? a.i) - (b.event.order ?? b.i))
    .map(({ event }) => event);
}

function decodeBatchPlayed(event: TraceEvent): BatchPlayed {
  const [, id] = event.keys;
  const [adventurer, from, played, stop, sequence, clock, version] = event.data;
  if (event.data.length !== 7) {
    throw new TraceError("BatchPlayed: unexpected layout");
  }
  return {
    instanceId: felt(id),
    adventurerId: small(adventurer, 32),
    from: small(from, 32),
    played: small(played, 8),
    stop: index(stop, 7) as Stop,
    sequence: small(sequence, 32),
    clock: small(clock, 32),
    version: small(version, 32),
  };
}

/** The outcome of the preview's two calls (`previewCalls`) from the simulation's trace. */
export function extractOutcome(trace: InvokeTrace): ChainOutcome {
  const execute = trace.execute_invocation;
  if ("revert_reason" in execute) {
    return {
      kind: "reverted",
      reason: panicReason(execute.revert_reason),
      raw: execute.revert_reason,
    };
  }
  const [play, state] = execute.calls;
  if (play === undefined || state === undefined || execute.calls.length !== 2) {
    throw new TraceError(`${execute.calls.length} calls, the preview makes 2`);
  }
  let batch: BatchPlayed | undefined;
  const killed: GoblinKilled[] = [];
  const revealed: number[] = [];
  let defeated = false;
  let closed: Outcome | undefined;
  for (const event of eventsOf(play)) {
    const [name] = event.keys;
    if (name === undefined) continue;
    switch (felt(name)) {
      case eventSelector.BatchPlayed:
        if (batch !== undefined) throw new TraceError("two BatchPlayed in one play");
        batch = decodeBatchPlayed(event);
        break;
      case eventSelector.GoblinKilled: {
        const [entity, caste, tile, by] = event.data;
        killed.push({
          entity: small(entity, 16),
          caste: small(caste, 16),
          tile: small(tile, 16),
          by: small(by, 16),
        });
        break;
      }
      case eventSelector.ChunkRevealed:
        revealed.push(small(event.data[0], 8));
        break;
      case eventSelector.Defeated:
        defeated = true;
        break;
      case eventSelector.InstanceClosed:
        closed = index(event.data[0], 4) as Outcome;
        break;
    }
  }
  if (batch === undefined) throw new TraceError("play emitted no BatchPlayed");
  let view: InstanceView;
  try {
    view = decodeInstanceView(state.result.map(felt));
  } catch (error) {
    throw new TraceError(`instance_state: ${(error as Error).message}`);
  }
  return { kind: "played", batch, killed, revealed, defeated, closed, view };
}
