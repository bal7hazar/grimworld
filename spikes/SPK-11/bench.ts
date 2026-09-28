// SPK-11 cost figures (AC-5 and the report's cost table). Every figure printed here is measured on
// devnet; projections are in docs/research/SPK-11-indexer.md §5, apart.
//   1. gas of each event: each entrypoint against the same write without the event, from devnet
//      receipts, on a contract of its own (the silent variants break the completeness invariant);
//   2. indexing from scratch: N transactions of K calls, then an empty database following them:
//      time, events per second, RPC calls per method, peak memory, disk per event;
//   3. blocks without our events (most of mainnet's): cost per block, RPC calls per method;
//   4. idle following: RPC calls per method per second at a 100 ms poll;
//   5. live latency: from a transaction's receipt to the subscription's `posted`.
//   spikes/SPK-11/with-archive.sh node spikes/SPK-11/bench.ts [transactions] [calls per transaction]
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
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
async function waitHead(client: { head: () => Promise<any> }, number: number) {
  const deadline = performance.now() + 600_000;
  while ((await client.head()).head?.number !== number) {
    if (performance.now() > deadline) throw new Error(`indexer not at block ${number} after 600 s`);
    await sleep(5);
  }
}
const diff = (after: Record<string, number>, before: Record<string, number>) =>
  Object.fromEntries(Object.entries(after).map(([method, count]) => [method, count - (before[method] ?? 0)]).filter(([, count]) => count !== 0));

// --- 1. gas ------------------------------------------------------------------------------------------
const gasMarket = await deployMarket();
say(`gas: Market at ${gasMarket.address}, block ${gasMarket.block}`);
const gas: Record<string, { l2Gas: number; l1DataGas: number; events: number }> = {};
for (const [label, calls] of [
  ["post, first (writes lot_count from zero)", [["post", 7, 1, 300]]],
  ["post_silent (no event)", [["post_silent", 7, 1, 300]]],
  ["post (LotPosted)", [["post", 7, 1, 300]]],
  ["post, fourth lot", [["post", 7, 1, 300]]],
  ["withdraw_silent lot 1 (no event)", [["withdraw_silent", 1]]],
  ["withdraw lot 3 (LotClosed)", [["withdraw", 3]]],
  ["buy lot 4 (LotClosed)", [["buy", 4]]],
  ["locate_silent (no event)", [["locate_silent", 1, 1]]],
  ["locate (AdventurerLocated)", [["locate", 1, 1]]],
] as const) {
  const sent = await send(gasMarket.address, calls as any);
  gas[label] = { l2Gas: sent.l2Gas, l1DataGas: sent.l1DataGas, events: sent.events };
}
console.table(gas);
const delta = (a: string, b: string) => ({ l2Gas: gas[a].l2Gas - gas[b].l2Gas, l1DataGas: gas[a].l1DataGas - gas[b].l1DataGas });
say(`event gas (receipt deltas, like for like): ${JSON.stringify({
  LotPosted: delta("post (LotPosted)", "post_silent (no event)"),
  LotClosed: delta("withdraw lot 3 (LotClosed)", "withdraw_silent lot 1 (no event)"),
  AdventurerLocated: delta("locate (AdventurerLocated)", "locate_silent (no event)"),
})}`);

// --- 2. indexing from scratch ------------------------------------------------------------------------
const market = await deployMarket();
say(`throughput: Market at ${market.address}, block ${market.block}`);
let lot = 0; // the last lot posted
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
    `database ${(bytes / 2 ** 20).toFixed(2)} MB after stop = ${Math.round(bytes / stats.eventsApplied)} bytes per event; peak RSS ${stats.maxRssMB} MB`,
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
const emptyCalls = Object.values(emptyStats.rpcCalls as Record<string, number>).reduce((a, b) => a + b, 0);
say(
  `${empty} blocks without our events: ${(emptyMs / 1000).toFixed(2)} s (${(emptyMs / empty).toFixed(2)} ms per block); ` +
    `RPC calls ${JSON.stringify(emptyStats.rpcCalls)} = ${(emptyCalls / empty).toFixed(2)} per block`,
);

// --- 4. idle following -------------------------------------------------------------------------------
const before = (await indexer.client.stats()).rpcCalls;
await sleep(5000);
const idle = diff((await indexer.client.stats()).rpcCalls, before);
say(`idle, 5 s at a 100 ms poll: RPC calls ${JSON.stringify(idle)} = ${(Object.values(idle).reduce((a, b) => a + b, 0) / 5).toFixed(1)} per second`);

// --- 5. live latency ---------------------------------------------------------------------------------
const heard = new Map<string, number>();
const subscription = new AbortController();
const listening = indexer.client.subscribe(999, (event: LotEvent) => {
  if (event.type === "posted") heard.set(event.data.lot, performance.now());
}, subscription.signal);
await sleep(100);
const latencies: number[] = [];
const perPost = (await indexer.client.stats()).rpcCalls;
for (let i = 0; i < 20; i++) {
  lot++;
  await send(market.address, [["post", 999, 1, 1]]);
  const receiptAt = performance.now();
  const deadline = receiptAt + 10_000;
  while (!heard.has(String(lot))) {
    if (performance.now() > deadline) throw new Error(`lot ${lot} not heard after 10 s`);
    await sleep(1);
  }
  latencies.push(heard.get(String(lot))! - receiptAt);
}
latencies.sort((a, b) => a - b);
say(`receipt → subscription, 20 posts, poll 100 ms: median ${latencies[10].toFixed(0)} ms, min ${latencies[0].toFixed(0)}, max ${latencies[19].toFixed(0)}`);
say(`RPC calls during those 20 blocks (idle polls included): ${JSON.stringify(diff((await indexer.client.stats()).rpcCalls, perPost))}`);
subscription.abort();
await listening;
await indexer.stop();
say(`database after the last stop (write-ahead log checkpointed): ${(size(dbFile) / 2 ** 20).toFixed(2)} MB`);
process.exit(0);
