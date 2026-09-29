// The indexer over the fake node, as the unit tests of the queries, the subscriptions and the client
// library use it.
import { Chain } from "../chain.ts";
import { Indexer } from "../indexer.ts";
import { Halt, Store } from "../store.ts";
import { FakeNode, HUB, MARKET } from "./fake-node.ts";

export function indexerOf(node: FakeNode, depth = 1000): Indexer {
  return new Indexer({
    chain: new Chain(node.rpc, { hub: HUB, market: MARKET }),
    store: new Store(":memory:"),
    config: { hub: HUB, market: MARKET, from: 1, lotCount: 0n, tradeCount: 0n },
    depth,
  });
}

/** Steps until idle or halted, as the process's loop does. */
export async function settle(subject: Indexer) {
  for (let i = 0; i < 1000; i++) {
    try {
      if (!(await subject.step())) return;
    } catch (error) {
      if (!(error instanceof Halt)) throw error;
      subject.halt(error.message);
      return;
    }
  }
  throw new Error("did not settle");
}

/** A `fetch` that answers JSON-RPC POSTs from the fake node (the client's node, in the tests). */
export function nodeFetch(node: FakeNode): typeof fetch {
  return (async (_url: unknown, init?: RequestInit) => {
    const { id, method, params } = JSON.parse(String(init?.body)) as {
      id: number;
      method: string;
      params: unknown;
    };
    let body: unknown;
    try {
      body = { jsonrpc: "2.0", id, result: await node.rpc(method, params) };
    } catch (error) {
      body = {
        jsonrpc: "2.0",
        id,
        error: { code: (error as { code?: number }).code ?? -1 },
      };
    }
    return new Response(JSON.stringify(body), {
      headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;
}
