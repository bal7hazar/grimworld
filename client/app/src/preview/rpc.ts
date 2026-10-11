import type { Call } from "../account";
import { executeCalldata } from "./calls";
import { type InvokeTrace, TraceError } from "./trace";

/**
 * The simulation behind one small interface, so that tests fake it: the calls in, the trace out.
 * `createRpcSimulator` asks a node over JSON-RPC (`starknet_simulateTransactions`, starknet-specs
 * v0.8+) with `SKIP_VALIDATE` and `SKIP_FEE_CHARGE`: no signature, no prompt, no fee taken. It
 * speaks the RPC itself rather than through starknet.js so that the account module stays the only
 * importer of the library (ADR-0005 §1); the burner's account address is all it needs.
 */
export interface Simulator {
  simulate(calls: readonly Call[]): Promise<InvokeTrace>;
}

/** A gas bound of a v3 transaction. */
export type ResourceBound = { maxAmount: bigint; maxPricePerUnit: bigint };

export interface RpcSimulatorConfig {
  nodeUrl: string;
  /** The burner's account: the caller `play` sees. */
  sender: string;
  /** The block the batch runs on; `pre_confirmed` (RPC 0.9+) by default. */
  block?: string;
  /**
   * The v3 bounds. Nothing is charged (`SKIP_FEE_CHARGE`) and every price is 0 by default; the L2
   * gas amount bounds the execution. Part 2 checks these on starknet-devnet.
   */
  bounds?: { l1Gas: ResourceBound; l2Gas: ResourceBound; l1DataGas: ResourceBound };
  /** Every request goes through it (tests answer offline). */
  fetch?: typeof fetch;
}

/** The node refused the simulation itself (not a revert of the batch: that is a trace). */
export class SimulationError extends Error {
  constructor(
    message: string,
    readonly code?: number,
  ) {
    super(message);
    this.name = "SimulationError";
  }
}

const hex = (value: bigint): string => `0x${value.toString(16)}`;
const bound = (b: ResourceBound) => ({
  max_amount: hex(b.maxAmount),
  max_price_per_unit: hex(b.maxPricePerUnit),
});
const ZERO: ResourceBound = { maxAmount: 0n, maxPricePerUnit: 0n };
/**
 * L2 gas for the execution: far above the costliest `play` test in contracts/ephemeral/GAS.md (about
 * 6 × 10^8, its setup included); the node caps an execution at its own maximum.
 */
const DEFAULT_L2: ResourceBound = { maxAmount: 1n << 40n, maxPricePerUnit: 0n };

export function createRpcSimulator(config: RpcSimulatorConfig): Simulator {
  const nodeUrl = String(config.nodeUrl);
  const sender = hex(BigInt(config.sender));
  const block = config.block ?? "pre_confirmed";
  const bounds = config.bounds ?? { l1Gas: ZERO, l2Gas: DEFAULT_L2, l1DataGas: ZERO };
  const fetchImpl = config.fetch ?? globalThis.fetch.bind(globalThis);
  let id = 0;
  const rpc = async (method: string, params: unknown): Promise<unknown> => {
    const response = await fetchImpl(nodeUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
    });
    const body = (await response.json()) as {
      result?: unknown;
      error?: { code?: number; message?: string; data?: unknown };
    };
    if (body.error !== undefined) {
      const detail = body.error.data === undefined ? "" : `: ${JSON.stringify(body.error.data)}`;
      throw new SimulationError(`${method}: ${body.error.message ?? "error"}${detail}`, body.error.code);
    }
    if (body.result === undefined) throw new SimulationError(`${method}: no result`);
    return body.result;
  };
  return {
    async simulate(calls) {
      const nonce = await rpc("starknet_getNonce", { block_id: block, contract_address: sender });
      const transaction = {
        type: "INVOKE",
        version: "0x3",
        sender_address: sender,
        calldata: executeCalldata(calls).map(hex),
        signature: [],
        nonce,
        resource_bounds: {
          l1_gas: bound(bounds.l1Gas),
          l2_gas: bound(bounds.l2Gas),
          l1_data_gas: bound(bounds.l1DataGas),
        },
        tip: "0x0",
        paymaster_data: [],
        account_deployment_data: [],
        nonce_data_availability_mode: "L1",
        fee_data_availability_mode: "L1",
      };
      const result = await rpc("starknet_simulateTransactions", {
        block_id: block,
        transactions: [transaction],
        simulation_flags: ["SKIP_VALIDATE", "SKIP_FEE_CHARGE"],
      });
      const [simulated] = Array.isArray(result) ? result : [];
      const trace = (simulated as { transaction_trace?: InvokeTrace } | undefined)
        ?.transaction_trace;
      if (trace?.execute_invocation === undefined) {
        throw new TraceError("the node returned no invoke trace");
      }
      return trace;
    },
  };
}
