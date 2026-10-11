import type { Call } from "../account";
import { type PlayAction, encodeBatch } from "./actions";

/**
 * The preview's multicall: `[Instances.play(...), Instances.instance_state(id)]`
 * (`contracts/ephemeral/src/systems/instances.cairo` :149, :200). The second call reads the state
 * the first leaves, in the same execution, so its result is the view after the batch.
 */

/** Selectors (`sn_keccak` of the names), held to starknet.js's by `calls.test.ts`. */
export const selector = {
  play: 0x21c4a0db2b08b026c4e31bf76d5dd9b92aa54c0978df57474355786073775e8n,
  instance_state: 0x1e4d6c33e5214ce405a5d1dd6d428568012ee76916228bc17cbce305cbc163cn,
} as const;

/** What `play` is called with, the actions aside. */
export interface PlayTarget {
  /** The `Instances` contract. */
  readonly instances: string;
  /** `InstanceId`, a u64. */
  readonly instanceId: bigint;
  readonly adventurerId: number;
  /** The sequence the client plays from. */
  readonly sequence: number;
  /** The content version the batch was computed under (D-141). */
  readonly version: number;
}

/** The two calls; `undefined` when the actions do not encode (count or an argument out of range). */
export function previewCalls(
  target: PlayTarget,
  actions: readonly PlayAction[],
): Call[] | undefined {
  const batch = encodeBatch(actions);
  if (batch === undefined) return undefined;
  return [
    {
      to: target.instances,
      entrypoint: "play",
      calldata: [
        target.instanceId,
        BigInt(target.adventurerId),
        BigInt(target.sequence),
        BigInt(target.version),
        batch,
      ],
    },
    { to: target.instances, entrypoint: "instance_state", calldata: [target.instanceId] },
  ];
}

const SELECTORS: Record<string, bigint> = selector;

/**
 * The calldata of a Cairo 1 account's `__execute__` (OpenZeppelin's, the burner's): the number of
 * calls, then each as `to, selector, calldata length, calldata…`. Only the preview's entrypoints
 * are known by name.
 */
export function executeCalldata(calls: readonly Call[]): bigint[] {
  return [
    BigInt(calls.length),
    ...calls.flatMap((call) => {
      const entry = SELECTORS[call.entrypoint];
      if (entry === undefined) throw new Error(`no selector for ${call.entrypoint}`);
      return [BigInt(call.to), entry, BigInt(call.calldata.length), ...call.calldata.map(BigInt)];
    }),
  ];
}
