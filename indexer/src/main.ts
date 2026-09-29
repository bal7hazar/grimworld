#!/usr/bin/env node
// The indexer's process (D-130, IDX-01a).
//
//   INDEXER_RPC_URL=<url> grimworld-indexer run     --hub <address> --market <address> --from <block>
//                                                   --db <file> [options]
//   INDEXER_RPC_URL=<url> grimworld-indexer rebuild --from <block> ...the same options
//
// `run` follows the node from the database's tip (a new database: from `--from`); `rebuild` empties
// the database, then runs from `--from` (docs/research/SPK-11-indexer.md, *Rebuild from the chain*).
// Options: --port <n> (0: any free port; the log says which), --host (127.0.0.1), --poll <ms> (1000),
// --depth <blocks>|l1 (the history kept below the tip; `l1`: down to the last block accepted on L1,
// production's setting; default l1), --batch <blocks> (100), --lot-count and --trade-count (the
// contracts' counters at the block before --from; 0 at their deployment), --rpc <url> (else
// INDEXER_RPC_URL; the environment is preferred: argv is visible to every user of the machine).
// The RPC URL may carry a provider's key: it is never logged in full. The indexer holds no key.
import { parseArgs } from "node:util";
import { Chain, httpRpc, redact } from "./chain.ts";
import { Indexer, type Depth } from "./indexer.ts";
import { serve } from "./server.ts";
import { Store } from "./store.ts";

const USAGE =
  "usage: grimworld-indexer run|rebuild --hub <address> --market <address> --from <block> --db <file> [--port <n>] [--host <h>] [--poll <ms>] [--depth <blocks>|l1] [--batch <n>] [--lot-count <n>] [--trade-count <n>] [--rpc <url>]";

function log(message: string) {
  console.log(`[indexer ${new Date().toISOString()}] ${message}`);
}

function fail(message: string): never {
  console.error(message);
  console.error(USAGE);
  process.exit(2);
}

function integer(
  value: string | undefined,
  name: string,
  fallback?: number,
): number {
  if (value === undefined) {
    if (fallback === undefined) fail(`--${name} is required`);
    return fallback;
  }
  if (!/^\d+$/.test(value)) fail(`--${name} ${value} is not a whole number`);
  return Number(value);
}

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    hub: { type: "string" },
    market: { type: "string" },
    from: { type: "string" },
    db: { type: "string" },
    port: { type: "string" },
    host: { type: "string" },
    poll: { type: "string" },
    depth: { type: "string" },
    batch: { type: "string" },
    "lot-count": { type: "string" },
    "trade-count": { type: "string" },
    rpc: { type: "string" },
  },
});

const command = positionals[0];
if (command !== "run" && command !== "rebuild") fail("run or rebuild?");
const rpcUrl = values.rpc ?? process.env.INDEXER_RPC_URL;
if (!rpcUrl) fail("no RPC URL: INDEXER_RPC_URL or --rpc");
if (!values.hub || !values.market) fail("--hub and --market are required");
if (!values.db) fail("--db is required");
const depth: Depth =
  values.depth === undefined || values.depth === "l1"
    ? "l1"
    : integer(values.depth, "depth");
const config = {
  hub: values.hub,
  market: values.market,
  from: integer(values.from, "from"),
  lotCount: BigInt(integer(values["lot-count"], "lot-count", 0)),
  tradeCount: BigInt(integer(values["trade-count"], "trade-count", 0)),
};

const store = new Store(values.db);
if (command === "rebuild") {
  store.clear();
  log(`rebuild: the database is empty; following from block ${config.from}`);
}
let indexer: Indexer;
try {
  indexer = new Indexer({
    chain: new Chain(httpRpc(rpcUrl), {
      hub: config.hub,
      market: config.market,
    }),
    store,
    config,
    depth,
    batch: integer(values.batch, "batch", 100),
    log,
  });
} catch (error) {
  console.error((error as Error).message);
  process.exit(2);
}

const server = serve(indexer);
const abort = new AbortController();
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => abort.abort());
}
server.listen(
  integer(values.port, "port", 0),
  values.host ?? "127.0.0.1",
  () => {
    const address = server.address();
    const where =
      typeof address === "object" && address
        ? `http://${address.address}:${address.port}`
        : String(address);
    const tip = store.tip();
    log(
      `serving on ${where}, following ${redact(rpcUrl)} from block ${config.from}; stored tip ${tip ? `${tip.number} ${tip.hash}` : "none"}; depth ${depth}`,
    );
  },
);
await indexer.run(integer(values.poll, "poll", 1000), abort.signal);
if (!abort.signal.aborted) {
  // Halted: keep answering `halted` until stopped.
  await new Promise<void>((resolve) =>
    abort.signal.addEventListener("abort", () => resolve()),
  );
}
server.close();
server.closeAllConnections();
store.close();
log("stopped");
