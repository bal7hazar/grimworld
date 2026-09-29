// The client's own view of its node, for R3: two JSON-RPC read methods and nothing else. No
// account, no key, nothing that can send. A client may inject its own reader instead.
import { canonical } from "./protocol.ts";

/** A block as the node has it: its hash and its four commitments, as the indexer joins them. */
export type NodeBlock = { hash: string; commitments: string };

export type NodeReader = {
  /** The number of the node's latest accepted block. */
  tip(): Promise<number>;
  /** The node's accepted block at `number`, or null if it has none there. */
  block(number: number): Promise<NodeBlock | null>;
};

const BLOCK_NOT_FOUND = 24;

type BlockResult = {
  status?: string;
  block_hash?: string;
  transaction_commitment?: string;
  event_commitment?: string;
  receipt_commitment?: string;
  state_diff_commitment?: string;
};

/** A NodeReader over JSON-RPC 0.10 at `url` (starknet_blockHashAndNumber, starknet_getBlockWithTxHashes). */
export function jsonRpcReader(
  url: string,
  fetchFn: typeof fetch = globalThis.fetch.bind(globalThis),
): NodeReader {
  let id = 0;
  const call = async (
    method: string,
    params: unknown,
  ): Promise<{ result?: unknown; error?: { code: number } }> => {
    const response = await fetchFn(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
    });
    if (!response.ok) throw new Error(`${method}: HTTP ${response.status}`);
    return (await response.json()) as {
      result?: unknown;
      error?: { code: number };
    };
  };
  return {
    async tip() {
      const { result, error } = await call("starknet_blockHashAndNumber", []);
      const number = (result as { block_number?: unknown } | undefined)
        ?.block_number;
      if (error || typeof number !== "number" || !Number.isInteger(number))
        throw new Error("starknet_blockHashAndNumber: no block number");
      return number;
    },
    async block(number) {
      const { result, error } = await call("starknet_getBlockWithTxHashes", {
        block_id: { block_number: number },
      });
      if (error?.code === BLOCK_NOT_FOUND) return null;
      if (error)
        throw new Error(
          `starknet_getBlockWithTxHashes: JSON-RPC error ${error.code}`,
        );
      const block = result as BlockResult;
      if (block.status === "PRE_CONFIRMED" || !block.block_hash) return null;
      const commitments = [
        block.transaction_commitment,
        block.event_commitment,
        block.receipt_commitment,
        block.state_diff_commitment,
      ];
      if (commitments.some((value) => !value)) return null;
      return {
        hash: canonical(block.block_hash),
        commitments: commitments.map((value) => canonical(value!)).join(","),
      };
    },
  };
}
