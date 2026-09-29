#!/usr/bin/env node
// The indexer's process (D-130, IDX-01a). indexer/README.md has the options and their rules.
//
//   INDEXER_RPC_URL=<url> grimworld-indexer run     --hub <address> --market <address> --from <block>
//                                                   --db <file> [options]
//   INDEXER_RPC_URL=<url> grimworld-indexer rebuild --from <block> ...the same options
//
// `run` follows the node from the database's tip (a new database: from `--from`); `rebuild` empties
// the database, then runs from `--from` (docs/research/SPK-11-indexer.md, *Rebuild from the chain*).
// `--from` is the deployment block of the two contracts: a database remembers the one it was built
// from, and `rebuild` refuses another (a later start would need the lots and trades open at that
// block, which no event gives; see the README).
// The RPC URL may carry a provider's key: it is never logged, not even when it is refused.
import { parseArgs } from "node:util";
import { Chain, httpRpc, parseRpcUrl, redact } from "./chain.ts";
import { Indexer, type Depth } from "./indexer.ts";
import { serve } from "./server.ts";
import { Store } from "./store.ts";

const USAGE =
  "usage: grimworld-indexer run|rebuild --hub <address> --market <address> --from <block> --db <file> [--port <n>] [--host <h>] [--poll <ms>] [--depth <blocks>|l1] [--batch <n>] [--recheck <blocks>] [--recheck-every <ms>] [--lot-count <n>] [--trade-count <n>] [--max-subscriptions <n>] [--max-subscriptions-per-client <n>] [--max-buffered <bytes>] [--stall <ms>] [--keep-alive <ms>] [--allow-origin <origin>]... [--rpc <url>]";

function log(message: string) {
  console.log(`[indexer ${new Date().toISOString()}] ${message}`);
}

function fail(message: string): never {
  console.error(message);
  console.error(USAGE);
  process.exit(2);
}

/** A whole number option, at least `min`. */
function integer(
  value: string | undefined,
  name: string,
  fallback: number | undefined,
  min = 0,
): number {
  if (value === undefined) {
    if (fallback === undefined) fail(`--${name} is required`);
    return fallback;
  }
  if (!/^\d{1,15}$/.test(value) || Number(value) < min) {
    fail(`--${name} must be a whole number of at least ${min}`);
  }
  return Number(value);
}

const U64 = 2n ** 64n;
/** A u64 option (a contract counter), parsed exactly. */
function u64(value: string | undefined, name: string): bigint {
  if (value === undefined) return 0n;
  if (!/^\d+$/.test(value) || BigInt(value) >= U64) {
    fail(`--${name} must be a whole number below 2^64`);
  }
  return BigInt(value);
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
    recheck: { type: "string" },
    "recheck-every": { type: "string" },
    "lot-count": { type: "string" },
    "trade-count": { type: "string" },
    "max-subscriptions": { type: "string" },
    "max-subscriptions-per-client": { type: "string" },
    "max-buffered": { type: "string" },
    stall: { type: "string" },
    "keep-alive": { type: "string" },
    "allow-origin": { type: "string", multiple: true },
    rpc: { type: "string" },
  },
});

const command = positionals[0];
if (command !== "run" && command !== "rebuild") fail("run or rebuild?");
const rpcUrl = values.rpc ?? process.env.INDEXER_RPC_URL;
if (!rpcUrl) fail("no RPC URL: INDEXER_RPC_URL or --rpc");
if (!parseRpcUrl(rpcUrl)) fail("the RPC URL is not an http(s) URL (not shown)");
if (!values.hub || !values.market) fail("--hub and --market are required");
for (const name of ["hub", "market"] as const) {
  if (!/^0x[0-9a-fA-F]{1,64}$/.test(values[name]!)) {
    fail(`--${name} must be a 0x hex address`);
  }
}
if (!values.db) fail("--db is required");
const depth: Depth =
  values.depth === undefined || values.depth === "l1"
    ? "l1"
    : integer(values.depth, "depth", undefined, 1);
const config = {
  hub: values.hub!,
  market: values.market!,
  from: integer(values.from, "from", undefined),
  lotCount: u64(values["lot-count"], "lot-count"),
  tradeCount: u64(values["trade-count"], "trade-count"),
};
const batch = integer(values.batch, "batch", 100, 1);
const poll = integer(values.poll, "poll", 1000, 1);
const recheck = {
  depth: integer(values.recheck, "recheck", 10),
  everyMs: integer(values["recheck-every"], "recheck-every", 10_000, 1),
};

const store = new Store(values.db);
if (command === "rebuild") {
  const built = store.config();
  if (built && built.from !== config.from) {
    fail(
      `rebuild --from ${config.from}: this database was built from block ${built.from}, the contracts' deployment; a rebuild starts there (a later start would need the lots and trades open at that block)`,
    );
  }
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
    batch,
    recheck,
    log,
  });
} catch (error) {
  console.error((error as Error).message);
  process.exit(2);
}

for (const origin of values["allow-origin"] ?? []) {
  if (!URL.canParse(origin) || new URL(origin).origin !== origin)
    fail(`--allow-origin ${origin}: an origin, scheme://host[:port]`);
}
// The defaults bound the streams' memory: 512 subscriptions × 512 KiB unsent = 256 MiB at most.
const server = serve(indexer, {
  allowedOrigins: values["allow-origin"] ?? [],
  limits: {
    perProcess: integer(values["max-subscriptions"], "max-subscriptions", 512),
    perClient: integer(
      values["max-subscriptions-per-client"],
      "max-subscriptions-per-client",
      16,
    ),
    maxBuffered: integer(values["max-buffered"], "max-buffered", 512 * 1024, 1),
    stallMs: integer(values.stall, "stall", 30_000, 1),
    keepAliveMs: integer(values["keep-alive"], "keep-alive", 15_000, 1),
  },
  log,
});
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
await indexer.run(poll, abort.signal);
if (!abort.signal.aborted) {
  // Halted: keep answering `halted` until stopped.
  await new Promise<void>((resolve) =>
    abort.signal.addEventListener("abort", () => resolve()),
  );
}
server.subscriptions.close();
server.close();
server.closeAllConnections();
store.close();
log("stopped");
