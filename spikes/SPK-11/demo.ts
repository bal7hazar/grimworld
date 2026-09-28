// SPK-11 scenario (AC-3, AC-4): deploys the Market contract, starts the indexer, posts lots and
// locates adventurers, queries the cheapest lot and the hub presence, listens to the lots
// subscription, then simulates three reorgs and checks the indexer against the chain:
//   1. live: blocks aborted while the indexer runs; time until the query and the subscription
//      show the rewound state;
//   2. replaced: after the abort, a new transaction takes the same block number (another hash,
//      and the same lot id with another price);
//   3. offline: blocks aborted and replaced while the indexer is stopped; it restarts on its
//      database and must find the fork by hashes;
// and a rebuild from the chain into an empty database, compared row for row, and with the view
// calls of the contract (the chain's own answer).
//   spikes/SPK-11/with-archive.sh node spikes/SPK-11/demo.ts
import { mkdirSync, rmSync } from "node:fs";
import { abortBlocks, deployMarket, head, provider, send } from "./chain.ts";
import type { LotEvent } from "./client.ts";
import { startIndexer, type RunningIndexer } from "./run-indexer.ts";

const tmp = new URL("./.tmp/", import.meta.url).pathname;
mkdirSync(tmp, { recursive: true });
const dbPath = (name: string) => {
  for (const suffix of ["", "-wal", "-shm"]) rmSync(`${tmp}${name}${suffix}`, { force: true });
  return `${tmp}${name}`;
};
const t0 = performance.now();
const say = (message: string) => console.log(`[demo +${((performance.now() - t0) / 1000).toFixed(2)}s] ${message}`);
const ms = (from: number) => `${(performance.now() - from).toFixed(0)} ms`;
let failures = 0;
function check(label: string, ok: boolean, detail: unknown) {
  if (!ok) failures++;
  say(`${ok ? "ok  " : "FAIL"} ${label}: ${JSON.stringify(detail)}`);
}
async function until<T>(read: () => Promise<T>, ok: (value: T) => boolean, timeoutMs = 20000): Promise<T> {
  const deadline = performance.now() + timeoutMs;
  for (;;) {
    const value = await read();
    if (ok(value)) return value;
    if (performance.now() > deadline) throw new Error(`timeout; last value ${JSON.stringify(value)}`);
    await new Promise((resolve) => setTimeout(resolve, 2));
  }
}
const prices = (lots: { price: string }[]) => lots.map((lot) => Number(lot.price));
const caughtUp = async (indexer: RunningIndexer) => {
  const chain = await head();
  return until(() => indexer.client.head(), (h) => h?.number === chain.number && h?.hash === chain.hash);
};

// The chain's own answer, by view calls: the open lots of an item, cheapest first, ties by lot id.
async function chainCheapest(address: string, item: number): Promise<number[]> {
  const open: { lot: number; price: number }[] = [];
  for (let lot = 1; ; lot++) {
    const [lotItem, , price, isOpen] = (await provider.callContract({ contractAddress: address, entrypoint: "lot", calldata: [String(lot)] })).map(BigInt);
    if (lotItem === 0n && price === 0n) break;
    if (lotItem === BigInt(item) && isOpen === 1n) open.push({ lot, price: Number(price) });
  }
  return open.sort((a, b) => a.price - b.price || a.lot - b.lot).map((lot) => lot.price);
}

// --- deploy, index, subscribe ------------------------------------------------------------------------
const market = await deployMarket();
say(`Market deployed at ${market.address} in block ${market.block}`);
const demoDb = dbPath("demo.db");
let indexer = await startIndexer({ address: market.address, db: demoDb, from: market.block });

const heard: { at: number; event: LotEvent }[] = [];
let subscription = new AbortController();
const listen = (client: RunningIndexer["client"]) =>
  client.subscribe((event) => {
    heard.push({ at: performance.now(), event });
    if (event.type !== "head") say(`subscription: ${event.type} ${JSON.stringify(event.data)}`);
  }, subscription.signal);
let listening = listen(indexer.client);

const ITEM = 7;
for (const [item, quantity, price] of [[ITEM, 1, 300], [ITEM, 1, 250], [ITEM, 2, 400], [9, 1, 100]]) {
  const sent = await send(market.address, [["post", item, quantity, price]]);
  say(`post(item ${item}, quantity ${quantity}, price ${price}) in block ${sent.block}`);
}
let sent = await send(market.address, [["locate", 1, 1], ["locate", 2, 1], ["locate", 3, 1], ["locate", 3, 2]]);
say(`locate adventurers 1, 2, 3 in hub 1, then 3 in hub 2, in block ${sent.block}`);
sent = await send(market.address, [["buy", 2]]);
say(`buy(lot 2) in block ${sent.block}`);

await caughtUp(indexer);
let cheapest = await indexer.client.cheapest(ITEM, 3);
say(`query cheapest(item ${ITEM}, 3) = ${JSON.stringify(cheapest)}`);
check("cheapest open lots of item 7 after lot 2 was bought", JSON.stringify(prices(cheapest.lots)) === "[300,400]", prices(cheapest.lots));
check("presence hub 1 / hub 2", (await indexer.client.presence(1)).count === 2 && (await indexer.client.presence(2)).count === 1, [(await indexer.client.presence(1)).count, (await indexer.client.presence(2)).count]);

// --- reorg 1: live -------------------------------------------------------------------------------------
const fork = (await head()).number;
sent = await send(market.address, [["post", ITEM, 1, 120]]);
const reorgBlock = sent.block;
say(`post(item ${ITEM}, price 120) in block ${reorgBlock} (lot 5)`);
sent = await send(market.address, [["locate", 1, 2]]);
say(`locate adventurer 1 in hub 2 in block ${sent.block}`);
await caughtUp(indexer);
cheapest = await indexer.client.cheapest(ITEM, 3);
check("before the reorg the query shows the 120 lot", prices(cheapest.lots)[0] === 120, cheapest);
check("before the reorg presence hub 1 = 1", (await indexer.client.presence(1)).count === 1, await indexer.client.presence(1));
check("the subscription heard lot 5 posted", heard.some(({ event }) => event.type === "posted" && event.data.lot === 5), null);

let heardBefore = heard.length;
let started = performance.now();
const aborted = await abortBlocks(reorgBlock);
const abortReturned = performance.now();
say(`devnet_abortBlocks from ${reorgBlock}: ${aborted.length} blocks aborted, chain head now ${JSON.stringify(await head())}`);
cheapest = await until(() => indexer.client.cheapest(ITEM, 3), (value) => value.head?.number === fork && prices(value.lots)[0] === 300);
const liveQuery = performance.now() - started;
const rewindHeard = await until(async () => heard.slice(heardBefore).find(({ event }) => event.type === "rewind"), (value) => value !== undefined);
const liveSubscription = rewindHeard!.at - started;
say(`reorg 1 (live): query consistent ${liveQuery.toFixed(0)} ms after the abort was sent (abort call itself ${(abortReturned - started).toFixed(0)} ms); subscription rewind heard at ${liveSubscription.toFixed(0)} ms: ${JSON.stringify(rewindHeard!.event.data)}`);
check("after reorg 1 the query is the chain's", JSON.stringify(prices(cheapest.lots)) === JSON.stringify(await chainCheapest(market.address, ITEM)), { indexer: prices(cheapest.lots), chain: await chainCheapest(market.address, ITEM) });
check("after reorg 1 presence hub 1 = 2 again", (await indexer.client.presence(1)).count === 2, await indexer.client.presence(1));

// --- reorg 2: the same height, another block -----------------------------------------------------------
sent = await send(market.address, [["post", ITEM, 1, 500]]);
say(`post(item ${ITEM}, price 500) in block ${sent.block}: the same number as the aborted block, lot id 5 again`);
await caughtUp(indexer);
cheapest = await indexer.client.cheapest(ITEM, 3);
check("replaced block indexed: lots 300, 400, 500", JSON.stringify(prices(cheapest.lots)) === "[300,400,500]", prices(cheapest.lots));

// --- reorg 3: while the indexer is stopped -------------------------------------------------------------
subscription.abort();
await listening;
await indexer.stop();
say("indexer stopped");
const replaced = sent.block;
await abortBlocks(replaced);
const a = await send(market.address, [["post", ITEM, 1, 600]]);
const b = await send(market.address, [["post", 9, 1, 90]]);
say(`aborted block ${replaced}; posted 600 (item ${ITEM}) in block ${a.block} and 90 (item 9) in block ${b.block}: the chain is now one block past the indexer's tip, whose hash is gone`);
started = performance.now();
indexer = await startIndexer({ address: market.address, db: demoDb, from: market.block });
heardBefore = heard.length;
subscription = new AbortController();
listening = listen(indexer.client);
cheapest = await until(() => indexer.client.cheapest(ITEM, 3), (value) => value.head?.number === b.block && prices(value.lots).includes(600));
const offline = performance.now() - started;
say(`reorg 3 (offline): restart to consistent query in ${offline.toFixed(0)} ms (process start included)`);
check("after reorg 3 the query is the chain's", JSON.stringify(prices(cheapest.lots)) === JSON.stringify(await chainCheapest(market.address, ITEM)), { indexer: prices(cheapest.lots), chain: await chainCheapest(market.address, ITEM) });
check("after reorg 3 item 9 is the chain's", JSON.stringify(prices((await indexer.client.cheapest(9, 3)).lots)) === JSON.stringify(await chainCheapest(market.address, 9)), prices((await indexer.client.cheapest(9, 3)).lots));

// --- rebuild from the chain ----------------------------------------------------------------------------
started = performance.now();
const rebuilt = await startIndexer({ address: market.address, db: dbPath("rebuilt.db"), from: market.block });
await caughtUp(rebuilt);
say(`rebuild from block ${market.block} into an empty database: ${ms(started)}`);
const answers = async (client: RunningIndexer["client"]) =>
  JSON.stringify({
    item7: (await client.cheapest(ITEM, 50)).lots,
    item9: (await client.cheapest(9, 50)).lots,
    hubs: [await client.presence(0), await client.presence(1), await client.presence(2)].map((p) => p.count),
    head: await client.head(),
  });
const kept = await answers(indexer.client);
const fresh = await answers(rebuilt.client);
say(`indexer that lived through the reorgs: ${kept}`);
say(`indexer rebuilt from the chain:        ${fresh}`);
check("rebuilt == rewound, answer for answer", kept === fresh, null);

subscription.abort();
await listening;
await Promise.all([indexer.stop(), rebuilt.stop()]);
say(`timings: ${JSON.stringify({ liveQueryMs: Math.round(liveQuery), liveSubscriptionMs: Math.round(liveSubscription), offlineRestartMs: Math.round(offline) })}`);
say(failures === 0 ? "all checks passed" : `${failures} checks FAILED`);
process.exit(failures === 0 ? 0 : 1);
