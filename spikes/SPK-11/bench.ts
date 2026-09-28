// SPK-11 cost figures (AC-5 and the report's cost table):
//   1. gas of each entrypoint and of the LotPosted event, from devnet receipts;
//   2. indexing from scratch: N transactions of K events, then an empty database following them:
//      time, events per second, RPC calls, peak memory, disk per event;
//   3. blocks without our events (most of mainnet's): the cost per block of following them;
//   4. live latency: from a transaction's receipt to the subscription's `posted`.
//   spikes/SPK-11/with-archive.sh node spikes/SPK-11/bench.ts [transactions] [events per transaction]
import { mkdirSync, rmSync, statSync } from "node:fs";
import { deployMarket, rpc, send } from "./chain.ts";
import type { LotEvent } from "./client.ts";
import { startIndexer } from "./run-indexer.ts";

const transactions = Number(process.argv[2] ?? 100);
const perTransaction = Number(process.argv[3] ?? 100);
const tmp = new URL("./.tmp/", import.meta.url).pathname;
mkdirSync(tmp, { recursive: true });
const fresh = (name: string) => {
  for (const suffix of ["", "-wal", "-shm"]) rmSync(`${tmp}${name}${suffix}`, { force: true });
  return `${tmp}${name}`;
};
const size = (path: string) => ["", "-wal", "-shm"].reduce((sum, suffix) => sum + (statSync(`${path}${suffix}`, { throwIfNoEntry: false })?.size ?? 0), 0);
const say = (message: string) => console.log(`[bench] ${message}`);
async function waitHead(client: { head: () => Promise<{ number: number } | null> }, number: number) {
  const deadline = performance.now() + 600_000;
  while ((await client.head())?.number !== number) {
    if (performance.now() > deadline) throw new Error(`indexer not at block ${number} after 600 s`);
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

const market = await deployMarket();
say(`Market at ${market.address}, block ${market.block}`);

// --- 1. gas ------------------------------------------------------------------------------------------
const gas: Record<string, unknown> = {};
for (const [label, calls] of [
  ["post (LotPosted)", [["post", 7, 1, 300]]],
  ["post_silent (no event)", [["post_silent", 7, 1, 300]]],
  // The first post writes lot_count from zero; this one is the like-for-like of post_silent.
  ["post again (LotPosted)", [["post", 7, 1, 300]]],
  ["buy (LotClosed)", [["buy", 1]]],
  ["post ×2 in one transaction", [["post", 7, 1, 300], ["post", 7, 1, 301]]],
  // Lot 2 was posted without an event: the indexer would stop on its LotClosed (unknown lot).
  ["withdraw (LotClosed)", [["withdraw", 3]]],
  ["locate (AdventurerLocated)", [["locate", 1, 1]]],
  ["locate ×2 in one transaction", [["locate", 1, 1], ["locate", 2, 1]]],
] as const) {
  const sent = await send(market.address, calls as any);
  gas[label] = { l2Gas: sent.l2Gas, l1DataGas: sent.l1DataGas, events: sent.events };
}
console.table(gas);

// --- 2. indexing from scratch ------------------------------------------------------------------------
let lot = 5; // the last lot posted above
let started = performance.now();
for (let t = 0; t < transactions; t++) {
  const calls: [string, ...number[]][] = [];
  for (let k = 0; k < perTransaction; k++) {
    if (k % 5 === 4) calls.push(["locate", t * perTransaction + k, 1 + (k % 3)]);
    else if (k % 5 === 3) calls.push(["buy", lot - 1]);
    else {
      calls.push(["post", 1 + (k % 50), 1 + (k % 3), 100 + ((t * 7919 + k * 104729) % 10000)]);
      lot++;
    }
  }
  await send(market.address, calls);
}
const sendMs = performance.now() - started;
const tipOf = async () => (await rpc("starknet_blockHashAndNumber")).block_number as number;
const chainTip = await tipOf();
say(`sent ${transactions} transactions × ${perTransaction} calls in ${(sendMs / 1000).toFixed(1)} s; chain tip ${chainTip}`);

const dbFile = fresh("bench.db");
started = performance.now();
let indexer = await startIndexer({ address: market.address, db: dbFile, from: market.block, quiet: true });
await waitHead(indexer.client, chainTip);
const catchUpMs = performance.now() - started;
const stats = await indexer.client.stats();
await indexer.stop();
const bytes = size(dbFile);
say(`catch-up from an empty database: ${JSON.stringify(stats)}`);
say(
  `${stats.eventsApplied} events over ${stats.blocksApplied} blocks in ${(catchUpMs / 1000).toFixed(2)} s ` +
    `(${Math.round(stats.eventsApplied / (catchUpMs / 1000))} events/s, process start included); ` +
    `database ${(bytes / 2 ** 20).toFixed(2)} MB = ${Math.round(bytes / stats.eventsApplied)} bytes per event ` +
    `→ ${((bytes / stats.eventsApplied) * 1e6 / 2 ** 30).toFixed(2)} GB per million events; peak RSS ${stats.maxRssMB} MB`,
);

// --- 3. blocks without our events --------------------------------------------------------------------
const empty = 1000;
for (let i = 0; i < empty; i++) await rpc("devnet_createBlock");
const emptyTip = await tipOf();
started = performance.now();
indexer = await startIndexer({ address: market.address, db: dbFile, from: market.block, quiet: true });
await waitHead(indexer.client, emptyTip);
const emptyMs = performance.now() - started;
const emptyStats = await indexer.client.stats();
say(
  `${empty} blocks without our events: ${(emptyMs / 1000).toFixed(2)} s (${(emptyMs / empty).toFixed(2)} ms per block), ` +
    `${emptyStats.rpcCalls} RPC calls (${(emptyStats.rpcCalls / empty).toFixed(2)} per block); database now ${(size(dbFile) / 2 ** 20).toFixed(2)} MB`,
);

// --- 4. live latency ---------------------------------------------------------------------------------
const heard = new Map<number, number>();
const subscription = new AbortController();
const listening = indexer.client.subscribe((event: LotEvent) => {
  if (event.type === "posted") heard.set(event.data.lot, performance.now());
}, subscription.signal);
await new Promise((resolve) => setTimeout(resolve, 100));
const latencies: number[] = [];
for (let i = 0; i < 20; i++) {
  lot++;
  await send(market.address, [["post", 999, 1, 1]]);
  const receiptAt = performance.now();
  const deadline = performance.now() + 10_000;
  while (!heard.has(lot)) {
    if (performance.now() > deadline) throw new Error(`lot ${lot} not heard after 10 s`);
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
  latencies.push(heard.get(lot)! - receiptAt);
}
latencies.sort((a, b) => a - b);
say(
  `receipt → subscription, 20 posts, poll 100 ms: median ${latencies[10].toFixed(0)} ms, ` +
    `min ${latencies[0].toFixed(0)}, max ${latencies[19].toFixed(0)} (negative: the indexer saw the block before starknet.js had the receipt)`,
);
subscription.abort();
await listening;
await indexer.stop();
say(`database after the last stop (write-ahead log checkpointed): ${(size(dbFile) / 2 ** 20).toFixed(2)} MB`);
process.exit(0);
