// The indexer's view of the node: JSON-RPC 0.10 read methods only, counted by method. The node
// is one node we trust, never several mixed within a step (SPK-11 §4). The indexer holds no key and
// sends nothing: this module knows only the read methods below.
import { canonical, type Source } from "./events.ts";

/** A JSON-RPC transport: the method's result, or an RpcError. */
export type Rpc = (method: string, params: unknown) => Promise<unknown>;

export class RpcError extends Error {
  readonly code: number;
  constructor(method: string, error: { code: number; message?: string }) {
    super(`${method}: ${error.code} ${error.message ?? ""}`.trim());
    this.code = error.code;
  }
}

export const BLOCK_NOT_FOUND = 24;

/** The URL without credentials, path or query: what may appear in a log. */
export function redact(url: string): string {
  const parsed = new URL(url);
  const hidden =
    parsed.username ||
    parsed.password ||
    parsed.pathname !== "/" ||
    parsed.search ||
    parsed.hash;
  return `${parsed.protocol}//${parsed.host}${hidden ? "/…(redacted)" : ""}`;
}

/** JSON-RPC over HTTP POST. */
export function httpRpc(url: string): Rpc {
  let id = 0;
  return async (method, params) => {
    const response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
    });
    if (!response.ok) throw new Error(`${method}: HTTP ${response.status}`);
    const body = (await response.json()) as {
      result?: unknown;
      error?: { code: number; message?: string };
    };
    if (body.error) throw new RpcError(method, body.error);
    return body.result;
  };
}

/**
 * A block, known by its hash AND its commitments: devnet gives a replacement block the hash of the
 * block it replaces (SPK-11 §4), so a hash alone does not identify it.
 */
export type Header = {
  number: number;
  hash: string;
  parent: string;
  commitments: string;
};

export const sameBlock = (a: Header, b: Header) =>
  a.hash === b.hash && a.commitments === b.commitments;

/** An event of one of the two contracts, with its position in its block. */
export type RawEvent = {
  source: Source;
  keys: string[];
  data: string[];
  transaction: string;
  transactionIndex: number;
  eventIndex: number;
};

type BlockResult = {
  status?: string;
  block_hash?: string;
  parent_hash: string;
  block_number?: number;
  transaction_commitment?: string;
  event_commitment?: string;
  receipt_commitment?: string;
  state_diff_commitment?: string;
};

type EventsPage = {
  events: {
    block_hash?: string;
    transaction_hash: string;
    transaction_index?: number;
    event_index?: number;
    from_address: string;
    keys: string[];
    data: string[];
  }[];
  continuation_token?: string;
};

export type Addresses = Record<Source, string>;

export class Chain {
  readonly calls: Record<string, number> = {};
  private readonly rpc: Rpc;
  private readonly addresses: Addresses;

  constructor(rpc: Rpc, addresses: Addresses) {
    this.rpc = rpc;
    this.addresses = {
      hub: canonical(addresses.hub),
      market: canonical(addresses.market),
    };
  }

  private call(method: string, params: unknown): Promise<unknown> {
    this.calls[method] = (this.calls[method] ?? 0) + 1;
    return this.rpc(method, params);
  }

  /** The node's latest accepted block (never a pre-confirmed one). */
  async tip(): Promise<{ number: number; hash: string }> {
    const result = (await this.call("starknet_blockHashAndNumber", [])) as {
      block_number: number;
      block_hash: string;
    };
    return { number: result.block_number, hash: canonical(result.block_hash) };
  }

  private static header(block: BlockResult): Header | null {
    // A pre-confirmed block has no hash: it is never indexed.
    if (!block.block_hash || block.block_number === undefined) return null;
    if (block.status === "PRE_CONFIRMED") return null;
    const commitments = [
      block.transaction_commitment,
      block.event_commitment,
      block.receipt_commitment,
      block.state_diff_commitment,
    ]
      .map((value) => (value === undefined ? "-" : canonical(value)))
      .join(",");
    return {
      number: block.block_number,
      hash: canonical(block.block_hash),
      parent: canonical(block.parent_hash),
      commitments,
    };
  }

  /** The block at `number`, or null when the node has none there. */
  async header(number: number): Promise<Header | null> {
    try {
      return Chain.header(
        (await this.call("starknet_getBlockWithTxHashes", {
          block_id: { block_number: number },
        })) as BlockResult,
      );
    } catch (error) {
      if (error instanceof RpcError && error.code === BLOCK_NOT_FOUND)
        return null;
      throw error;
    }
  }

  /** The number of the last block accepted on L1, or null when there is none yet. */
  async l1Accepted(): Promise<number | null> {
    try {
      const block = (await this.call("starknet_getBlockWithTxHashes", {
        block_id: "l1_accepted",
      })) as BlockResult;
      return block.block_number ?? null;
    } catch (error) {
      if (error instanceof RpcError && error.code === BLOCK_NOT_FOUND)
        return null;
      throw error;
    }
  }

  /**
   * The events of both contracts in `block`, fetched by the block's hash, in block order
   * (transaction index, then event index within the transaction). An event reported for another
   * block, or without its position, is an Error (the step is tried again).
   */
  async events(block: Header): Promise<RawEvent[]> {
    const events: RawEvent[] = [];
    for (const source of ["hub", "market"] as const) {
      let token: string | undefined;
      do {
        const page = (await this.call("starknet_getEvents", {
          filter: {
            from_block: { block_hash: block.hash },
            to_block: { block_hash: block.hash },
            address: this.addresses[source],
            chunk_size: 1000,
            ...(token ? { continuation_token: token } : {}),
          },
        })) as EventsPage;
        for (const event of page.events) {
          if (!event.block_hash || canonical(event.block_hash) !== block.hash) {
            throw new Error(
              `an event of block ${event.block_hash} in the answer for ${block.hash}`,
            );
          }
          if (canonical(event.from_address) !== this.addresses[source]) {
            throw new Error(
              `an event of ${event.from_address} in the answer for ${source}`,
            );
          }
          if (
            event.transaction_index === undefined ||
            event.event_index === undefined
          ) {
            throw new Error(
              "an event without its position (JSON-RPC 0.10 is needed)",
            );
          }
          events.push({
            source,
            keys: event.keys,
            data: event.data,
            transaction: canonical(event.transaction_hash),
            transactionIndex: event.transaction_index,
            eventIndex: event.event_index,
          });
        }
        token = page.continuation_token;
      } while (token);
    }
    return events.sort(
      (a, b) =>
        a.transactionIndex - b.transactionIndex || a.eventIndex - b.eventIndex,
    );
  }
}
