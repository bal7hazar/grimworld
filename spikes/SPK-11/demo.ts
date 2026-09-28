// SPK-11 scenario (AC-3, AC-4, and fix loop 1): deploys the Market contract, starts the indexer,
// and checks, against the chain's own answer (view calls), that no answer the client ACCEPTS is a
// state the chain does not hold:
//   A. secrets: the indexer's environment is one variable; a key in the RPC URL never reaches a log;
//   B. queries and the subscription cache;
//   C. live reorg (an aborted purchase and an aborted lot): raw answers sampled every few ms from
//      the abort on, each passed through the client's freshness rule; the cache likewise;
//   D. a cache through a disconnection, a reorg and a lot id given twice;
//   E. restart on a database whose tip the chain replaced, with a slow node: every answer from the
//      first one on is either 503 `loading` or the chain's;
//   F. u64 boundaries (ids 2^53+1, 2^63, 2^64-1; prices 2^53+1, 2^63, 2^64-1) through ingestion,
//      query, purchase and rewind;
//   G. rebuild from the chain, answer for answer;
//   H. completeness: a lot created without its event halts the indexer, by reconciliation (the
//      running indexer) and by the id gap (a rebuild).
//   spikes/SPK-11/with-archive.sh node spikes/SPK-11/demo.ts
import { mkdirSync, rmSync } from "node:fs";
import { abortBlocks, deployMarket, head, provider, send } from "./chain.ts";
import { LotCache, type Lot, type LotEvent } from "./client.ts";
import { startIndexer, type RunningIndexer } from "./run-indexer.ts";

const tmp = new URL("./.tmp/", import.meta.url).pathname;
mkdirSync(tmp, { recursive: true });
const dbPath = (name: string) => {
  for (const suffix of ["", "-wal", "-shm"]) rmSync(`${tmp}${name}${suffix}`, { force: true });
  return `${tmp}${name}`;
};
const t0 = performance.now();
const say = (message: string) => console.log(`[demo +${((performance.now() - t0) / 1000).toFixed(2)}s] ${message}`);
let failures = 0;
function check(label: string, ok: boolean, detail?: unknown) {
  if (!ok) failures++;
  say(`${ok ? "ok  " : "FAIL"} ${label}${detail === undefined ? "" : `: ${JSON.stringify(detail)}`}`);
}
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
async function until<T>(read: () => Promise<T>, ok: (value: T) => boolean, timeoutMs = 20000): Promise<T> {
  const deadline = performance.now() + timeoutMs;
  for (;;) {
    const value = await read();
    if (ok(value)) return value;
    if (performance.now() > deadline) throw new Error(`timeout; last value ${JSON.stringify(value)}`);
    await sleep(2);
  }
}
const show = (lots: { lot: string; price: string }[]) => lots.map((lot) => `${lot.lot}:${lot.price}`).join(" ");
// Caught up = at the chain's tip, by the freshness rule (hash AND commitments: devnet re-uses hashes).
const caughtUp = async (indexer: RunningIndexer) => {
  const chain = await head();
  await until(
    async () => {
      const answer = await indexer.client.head();
      return answer.head?.number === chain.number && (await indexer.client.check(answer)).fresh;
    },
    (ok) => ok,
  );
};

// The chain's own answer, by view calls: the open lots of an item, cheapest first, ties by lot id;
// at the latest block, or at the block of the given hash (the state the chain holds there).
async function truth(address: string, item: number, ids?: bigint[], blockHash?: string): Promise<string> {
  const open: { lot: bigint; price: bigint }[] = [];
  const visit = async (lot: bigint) => {
    const [lotItem, , price, isOpen] = (await provider.callContract({ contractAddress: address, entrypoint: "lot", calldata: [lot.toString()] }, blockHash ?? "latest")).map(BigInt);
    if (lotItem === BigInt(item) && isOpen === 1n) open.push({ lot, price });
    return lotItem !== 0n || price !== 0n;
  };
  if (ids) for (const id of ids) await visit(id);
  else for (let lot = 1n; await visit(lot); lot++);
  open.sort((a, b) => (a.price !== b.price ? (a.price < b.price ? -1 : 1) : a.lot < b.lot ? -1 : 1));
  return open.map((lot) => `${lot.lot}:${lot.price}`).join(" ");
}

// A cache fed by the subscription of one item, on a connection that can be dropped and reopened.
function subscription(indexer: RunningIndexer, item: number, cache: LotCache) {
  const controller = new AbortController();
  const done = indexer.client
    .subscribe(item, (event: LotEvent) => {
      cache.apply(event);
      const short = (block: { number: number; hash: string } | null) => (block ? `${block.number} ${block.hash.slice(0, 10)}…` : null);
      const data =
        event.type === "reset" ? { head: short(event.data.head), lots: show(event.data.lots) }
        : event.type === "posted" || event.type === "closed" ? { ...event.data, block: short(event.data.block) }
        : event.type === "rewind" ? { ...event.data, head: short(event.data.head) }
        : event.data;
      if (event.type !== "head") say(`subscription(item ${item}): ${event.type} ${JSON.stringify(data)}`);
    }, controller.signal)
    .catch(() => undefined);
  return async () => {
    controller.abort();
    await done;
    cache.disconnected();
  };
}

// Samples raw answers (and the cache) from now until an answer is accepted and equals `latest`
// (the chain's state at its tip; the cache too). Each answer with rows is compared with the chain's
// state AT ITS OWN HEAD (view calls at that block): "wrong" is a state the chain does not hold
// there. Each is also passed through the freshness rule: "accepted wrong" must never happen. An
// accepted answer may be older than `latest` (up to maxLag blocks): a past state of the chain.
async function sample(indexer: RunningIndexer, item: number, latest: string, cache: LotCache | null) {
  const counts = { answers: 0, loading: 0, rawOk: 0, rawWrong: 0, accepted: 0, acceptedWrong: 0, acceptedOlder: 0, cacheAccepted: 0, cacheWrong: 0 };
  const started = performance.now();
  let firstLatest = -1;
  const heldAt = async (lots: { lot: string; price: string }[], at: { hash: string }) =>
    show(lots) === (await truth(market.address, item, undefined, at.hash).catch(() => "block gone"));
  for (;;) {
    const raw = await indexer.client.cheapestRaw(item, 50);
    counts.answers++;
    let rawRight = false;
    if (raw.status !== "ok") counts.loading++;
    else {
      counts.rawOk++;
      rawRight = await heldAt(raw.lots, raw.head);
      if (!rawRight) counts.rawWrong++;
    }
    const checked = await indexer.client.check(raw);
    let done = false;
    if (checked.fresh) {
      counts.accepted++;
      if (!rawRight) counts.acceptedWrong++;
      else if (show(checked.answer.lots) !== latest) counts.acceptedOlder++;
      else {
        done = true;
        if (firstLatest < 0) firstLatest = performance.now() - started;
      }
    }
    if (cache) {
      done &&= cache.ready && show(cache.sorted()) === latest;
      if (cache.ready && cache.head && (await indexer.client.verify(cache.head)) === "fresh") {
        counts.cacheAccepted++;
        if (!(await heldAt(cache.sorted(), cache.head))) counts.cacheWrong++;
      }
    }
    if (done) break;
    if (performance.now() - started > 20000) throw new Error(`not consistent after 20 s: ${JSON.stringify(counts)}`);
    await sleep(3);
  }
  return { ...counts, latestAcceptedMs: Math.round(firstLatest) };
}

// --- A. deploy, start, secrets ---------------------------------------------------------------------
const market = await deployMarket();
say(`Market deployed at ${market.address} in block ${market.block}`);
const demoDb = dbPath("demo.db");
const FAKE_KEY = "spk11-fake-provider-key";
const keyedUrl = `${process.env.NODE_URL}/?key=${FAKE_KEY}`;
let indexer = await startIndexer({ address: market.address, db: demoDb, from: market.block, rpcUrl: keyedUrl, poll: 500 });
const environmentLine = indexer.logs.find((line) => line.includes("environment:")) ?? "";
check("the indexer's environment is INDEXER_RPC_URL only", environmentLine.endsWith("environment: INDEXER_RPC_URL"), environmentLine.split("] ")[1]);
const ITEM = 7;
const cache = new LotCache();
let unsubscribe = subscription(indexer, ITEM, cache);

// --- B. queries --------------------------------------------------------------------------------------
for (const [item, quantity, price] of [[ITEM, 1, 300], [ITEM, 1, 250], [ITEM, 2, 400], [9, 1, 100]]) {
  const sent = await send(market.address, [["post", item, quantity, price]]);
  say(`post(item ${item}, quantity ${quantity}, price ${price}) in block ${sent.block}`);
}
let sent = await send(market.address, [["locate", 1, 1], ["locate", 2, 1], ["locate", 3, 1], ["locate", 3, 2]]);
say(`locate adventurers 1, 2, 3 in hub 1, then 3 in hub 2, in block ${sent.block}`);
sent = await send(market.address, [["buy", 2]]);
say(`buy(lot 2) in block ${sent.block}`);
await caughtUp(indexer);
let answer = await indexer.client.cheapest(ITEM, 10);
say(`query cheapest(item ${ITEM}) = ${answer.fresh ? JSON.stringify({ head: answer.answer.head?.number, behind: (answer.answer as any).behind, lots: answer.answer.lots }) : answer.reason}`);
check("cheapest open lots of item 7 = the chain's (lot 2 bought)", answer.fresh && show(answer.answer.lots) === (await truth(market.address, ITEM)), answer.fresh && show(answer.answer.lots));
const presence = [await indexer.client.presence(1), await indexer.client.presence(2)].map((p) => (p.fresh ? p.answer.count : -1));
check("presence hub 1 / hub 2", presence[0] === 2 && presence[1] === 1, presence);
const chainB = await truth(market.address, ITEM);
await until(async () => show(cache.sorted()), (lots) => lots === chainB, 5000).catch(() => undefined);
check("the subscription cache = the chain's", show(cache.sorted()) === chainB, show(cache.sorted()));

// --- C. live reorg -----------------------------------------------------------------------------------
const fork = (await head()).number;
sent = await send(market.address, [["post", ITEM, 1, 120], ["buy", 1]]);
const reorgBlock = sent.block;
say(`post(item ${ITEM}, price 120) as lot 5 and buy(lot 1), in block ${reorgBlock}`);
sent = await send(market.address, [["locate", 1, 2]]);
await caughtUp(indexer);
const beforeLive = await truth(market.address, ITEM);
await until(async () => show(cache.sorted()), (lots) => lots === beforeLive);
say(`before the abort: chain ${beforeLive}; cache ${show(cache.sorted())}`);
const aborted = await abortBlocks(reorgBlock);
const afterLive = await truth(market.address, ITEM);
say(`devnet_abortBlocks from ${reorgBlock}: ${aborted.length} blocks aborted; the chain's answer is now ${afterLive} (lot 1 open again, lot 5 gone)`);
const live = await sample(indexer, ITEM, afterLive, cache);
say(`live reorg, sampled from the abort until consistent: ${JSON.stringify(live)}`);
check("live: no accepted answer (query or cache) is a state the chain does not hold at its head", live.acceptedWrong === 0 && live.cacheWrong === 0, { acceptedWrong: live.acceptedWrong, cacheWrong: live.cacheWrong });
check("live: raw answers were orphaned in the window, and the rule rejected every one", live.rawWrong > 0, { rawWrong: live.rawWrong, accepted: live.accepted });
check("live: the cache reopened lot 1 (reset after rewind)", show(cache.sorted()) === afterLive, show(cache.sorted()));
const presenceAfter = await indexer.client.presence(1);
check("live: presence hub 1 = 2 again", presenceAfter.fresh && presenceAfter.answer.count === 2, presenceAfter.fresh ? presenceAfter.answer.count : presenceAfter.reason);

// --- D. a cache through a disconnection, a reorg and a reused lot id ---------------------------------
await unsubscribe();
say(`cache disconnected: ready=${cache.ready}, holds ${show(cache.sorted())}`);
sent = await send(market.address, [["post", ITEM, 1, 500]]);
say(`post 500 in block ${sent.block} (lot 5)`);
await caughtUp(indexer);
await abortBlocks(sent.block);
sent = await send(market.address, [["post", ITEM, 1, 650], ["withdraw", 3]]);
say(`aborted it; post 650 (lot 5 again) and withdraw(lot 3) in block ${sent.block}`);
await caughtUp(indexer);
unsubscribe = subscription(indexer, ITEM, cache);
await until(async () => cache.ready && !!cache.head && (await indexer.client.verify(cache.head)) === "fresh", (ok) => ok);
const afterReconnect = await truth(market.address, ITEM);
check("reconnected cache, accepted by the freshness rule, = the chain's (lot 5 is 650, lot 3 withdrawn)", show(cache.sorted()) === afterReconnect, { cache: show(cache.sorted()), chain: afterReconnect });

// --- E. restart on a replaced tip, with a slow node --------------------------------------------------
await unsubscribe();
await indexer.stop();
say("indexer stopped");
const replaced = sent.block;
await abortBlocks(replaced);
const a = await send(market.address, [["post", ITEM, 1, 700]]);
const b = await send(market.address, [["post", 9, 1, 90]]);
const afterOffline = await truth(market.address, ITEM);
say(`aborted block ${replaced}; posted 700 (lot 5, item ${ITEM}) in block ${a.block} and 90 (item 9) in block ${b.block}; the chain's answer is ${afterOffline}`);
let started = performance.now();
indexer = await startIndexer({ address: market.address, db: demoDb, from: market.block, rpcUrl: keyedUrl, poll: 500, rpcDelay: 50 });
const restart = await sample(indexer, ITEM, afterOffline, null);
say(`restart with a 50 ms node, sampled from the first answer until consistent (${(performance.now() - started).toFixed(0)} ms from spawn): ${JSON.stringify(restart)}`);
check("restart: every answer with rows, raw or accepted, is a state the chain holds at its head (gate)", restart.rawWrong === 0 && restart.acceptedWrong === 0, { loading: restart.loading, rawOk: restart.rawOk, rawWrong: restart.rawWrong, acceptedOlder: restart.acceptedOlder });
check("restart: the gate was observed", restart.loading > 0, { loading: restart.loading });
await indexer.stop();
indexer = await startIndexer({ address: market.address, db: demoDb, from: market.block, rpcUrl: keyedUrl, poll: 100 });
await caughtUp(indexer);
unsubscribe = subscription(indexer, ITEM, cache);
await until(async () => cache.ready, (ready) => ready);
check("restart: cache = the chain's", show(cache.sorted()) === afterOffline, show(cache.sorted()));

// --- F. u64 boundaries ------------------------------------------------------------------------------
const BIG = 77;
const [i53, i63, i64] = [2n ** 53n + 1n, 2n ** 63n, 2n ** 64n - 1n];
const big = await send(market.address, [
  ["skip_lots", 2n ** 53n], ["post", BIG, 1, 2n ** 64n - 1n],
  ["skip_lots", 2n ** 63n - 1n], ["post", BIG, 1, 2n ** 63n],
  ["skip_lots", 2n ** 64n - 2n], ["post", BIG, 1, 2n ** 53n + 1n],
]);
await send(market.address, [["buy", i63]]);
await caughtUp(indexer);
const bigTruth = await truth(market.address, BIG, [i53, i63, i64]);
answer = await indexer.client.cheapest(BIG, 10);
say(`u64: chain ${bigTruth}; indexer ${answer.fresh ? show(answer.answer.lots) : answer.reason}`);
check("u64: ids and prices at 2^53+1, 2^63, 2^64-1 ingested and ordered losslessly", answer.fresh && show(answer.answer.lots) === bigTruth && bigTruth === `${i64}:${2n ** 53n + 1n} ${i53}:${2n ** 64n - 1n}`);
await abortBlocks(big.block);
await caughtUp(indexer);
answer = await indexer.client.cheapest(BIG, 10);
check("u64: rewound (item 77 empty, like the chain)", answer.fresh && answer.answer.lots.length === 0 && (await truth(market.address, BIG, [i53, i63, i64])) === "", answer.fresh ? answer.answer.lots : answer.reason);
sent = await send(market.address, [["post", ITEM, 1, 800]]);
await caughtUp(indexer);
check("u64: the lot counter rewound with it: the next lot id is 7, the chain's", (await indexer.client.cheapest(ITEM, 50)).fresh && show(((await indexer.client.cheapest(ITEM, 50)) as any).answer.lots).includes("7:800"));

// --- G. rebuild from the chain ----------------------------------------------------------------------
started = performance.now();
const rebuilt = await startIndexer({ address: market.address, db: dbPath("rebuilt.db"), from: market.block, quiet: true });
await caughtUp(rebuilt);
say(`rebuild from block ${market.block} into an empty database: ${(performance.now() - started).toFixed(0)} ms`);
const answers = async (indexer: RunningIndexer) => {
  const items = [];
  for (const item of [ITEM, 9, BIG]) items.push(((await indexer.client.cheapestRaw(item, 50)) as any).lots);
  const hubs = [];
  for (const hub of [0, 1, 2]) hubs.push((await indexer.client.presence(hub) as any).answer.count);
  return JSON.stringify({ items, hubs, head: (await indexer.client.head()).head });
};
const kept = await answers(indexer);
const fresh = await answers(rebuilt);
say(`indexer that lived through the reorgs: ${kept}`);
say(`indexer rebuilt from the chain:        ${fresh}`);
check("rebuilt == rewound, answer for answer", kept === fresh);
await rebuilt.stop();

// --- H. completeness ---------------------------------------------------------------------------------
sent = await send(market.address, [["post_silent", ITEM, 1, 50]]);
say(`post_silent (a lot without its event) in block ${sent.block}`);
const halted = await until(() => indexer.client.head(), (value) => value.status === "halted", 5000);
check("reconciliation halts the running indexer (view call lot_count at its tip)", /lot_count on the chain/.test(halted.reason), halted);
check("halted: queries answer 503 halted, no rows", (await indexer.client.cheapestRaw(ITEM, 10)).status === "halted");
check("halted: the cache knows", cache.status === "halted" && !cache.ready, { status: cache.status, ready: cache.ready });
await send(market.address, [["post", ITEM, 1, 60]]);
const gap = await startIndexer({ address: market.address, db: dbPath("gap.db"), from: market.block, quiet: true });
const gapHalt = await until(() => gap.client.head(), (value) => value.status === "halted", 10000);
check("a rebuild halts on the id gap (LotPosted 9 after 7)", /expected lot 8/.test(gapHalt.reason), gapHalt);
await gap.stop();

const allLogs = [...indexer.logs, ...rebuilt.logs, ...gap.logs].join("\n");
check("no log line holds the provider key of the RPC URL", !allLogs.includes(FAKE_KEY) && allLogs.includes("/…(redacted)"));
check("no log line holds the node account's private key", !allLogs.includes(process.env.NODE_ACCOUNT_PRIVATE_KEY!));
await unsubscribe();
await indexer.stop();
say(`timings: ${JSON.stringify({ liveLatestAcceptedMs: live.latestAcceptedMs, restartLatestAcceptedMs: restart.latestAcceptedMs })}`);
say(failures === 0 ? "all checks passed" : `${failures} checks FAILED`);
process.exit(failures === 0 ? 0 : 1);
