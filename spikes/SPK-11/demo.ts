// SPK-11 scenario (AC-3, AC-4, fix loops 1 and 2): deploys the Market contract, starts the indexer,
// and checks, against the chain's own answer (view calls), that no answer the client ACCEPTS is a
// state the chain does not hold:
//   A. secrets: the indexer's environment is one variable; a key in the RPC URL never reaches a log;
//   B. queries and the subscription cache;
//   V. the freshness rule's read order: a reorg between the rule's two node reads, with the old
//      order (block, then tip) and the new one (tip, then block last);
//   C. live reorg (an aborted purchase and an aborted lot): raw answers sampled every few ms from
//      the abort on, each passed through the freshness rule; the cache likewise;
//   D. a cache through a disconnection, a reorg and a lot id given twice;
//   E. an unplanned close of the stream (the indexer stops): the cache stops answering by itself;
//      then a restart on a database whose tip the chain replaced, with a slow node;
//   F. u64 boundaries (ids 2^53+1, 2^63, 2^64-1; prices 2^53+1, 2^63, 2^64-1) through ingestion,
//      query, purchase and rewind;
//   G. rebuild from the chain, answer for answer;
//   H. completeness: a served block replaced at the same height (devnet keeps its hash) by one
//      holding a lot without its event: reconciliation keyed by block identity halts the indexer,
//      and the replacement is never served; then a rebuild halts on the id gap.
// The large-snapshot case (more than one page, more than 10 000 lots) is snapshot.ts.
//   spikes/SPK-11/with-archive.sh node spikes/SPK-11/demo.ts
import { mkdirSync, rmSync } from "node:fs";
import { abortBlocks, deployMarket, head, provider, rpc, send } from "./chain.ts";
import { LotCache, type Head, type LotEvent } from "./client.ts";
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
const short = (block: { number: number; hash: string } | null | undefined) => (block ? `${block.number} ${block.hash.slice(0, 10)}…` : null);
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

// A cache of item ITEM on the indexer's stream; the cache owns the stream (connect/close).
function listen(indexer: RunningIndexer) {
  const cache = new LotCache(indexer.client, ITEM);
  const log = (event: LotEvent) => {
    if (event.type === "head" || event.type === "reset-page") return;
    const data =
      event.type === "reset-begin" || event.type === "reset-end" ? { head: short(event.data.head), total: event.data.total }
      : event.type === "posted" || event.type === "closed" ? { ...event.data, block: short(event.data.block) }
      : event.data;
    say(`subscription(item ${ITEM}): ${event.type} ${JSON.stringify(data)}`);
  };
  return { cache, close: cache.connect(log) };
}
// What the cache shows through its read API: the lots, or why not.
const shown = async (cache: LotCache) => {
  const read = await cache.read();
  return read.fresh ? show(read.answer.lots) : `(not shown: ${read.reason})`;
};

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
      const read = await cache.read();
      if (read.fresh) {
        counts.cacheAccepted++;
        if (!(await heldAt(read.answer.lots, read.answer.head!))) counts.cacheWrong++;
      }
      done &&= read.fresh && show(read.answer.lots) === latest;
    }
    if (done) break;
    if (performance.now() - started > 20000) throw new Error(`not consistent after 20 s: ${JSON.stringify(counts)}`);
    await sleep(3);
  }
  return { ...counts, latestAcceptedMs: Math.round(firstLatest) };
}

// --- A. deploy, start, secrets ---------------------------------------------------------------------
const ITEM = 7;
const market = await deployMarket();
say(`Market deployed at ${market.address} in block ${market.block}`);
const demoDb = dbPath("demo.db");
const FAKE_KEY = "spk11-fake-provider-key";
const keyedUrl = `${process.env.NODE_URL}/?key=${FAKE_KEY}`;
let indexer = await startIndexer({ address: market.address, db: demoDb, from: market.block, rpcUrl: keyedUrl, poll: 500 });
const environmentLine = indexer.logs.find((line) => line.includes("environment:")) ?? "";
check("the indexer's environment is INDEXER_RPC_URL only", environmentLine.endsWith("environment: INDEXER_RPC_URL"), environmentLine.split("] ")[1]);
let { cache, close } = listen(indexer);
const logs: string[][] = [];

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
await until(() => shown(cache), (lots) => lots === chainB, 5000).catch(() => undefined);
check("the subscription cache, through its read API, = the chain's", (await shown(cache)) === chainB, await shown(cache));

// --- V. the freshness rule's read order ---------------------------------------------------------------
// The old order read the answer's block, then the tip: a reorg between the two passes an orphan.
async function verifyBlockThenTip(headOfAnswer: NonNullable<Head>, between: () => Promise<void>) {
  const block = await indexer.client.blockIs(headOfAnswer);
  if (block !== "fresh") return block;
  await between();
  const tip = await rpc("starknet_blockHashAndNumber");
  return tip.block_number - headOfAnswer.number > indexer.client.maxLag ? "behind" : "fresh";
}
sent = await send(market.address, [["post", ITEM, 1, 111]]);
await caughtUp(indexer);
let raw = await indexer.client.cheapestRaw(ITEM, 50);
const oldVerdict = await verifyBlockThenTip(raw.head, async () => void (await abortBlocks(sent.block)));
say(`answer at ${short(raw.head)} with lot 5 at 111; block ${sent.block} aborted between the rule's two reads; old order says "${oldVerdict}"; chain now ${await truth(market.address, ITEM)}`);
check("old order (block, then tip) accepts the answer holding the orphaned lot 5: the defect", oldVerdict === "fresh" && show(raw.lots).includes("5:111"), { oldVerdict, lots: show(raw.lots) });
sent = await send(market.address, [["post", ITEM, 1, 112]]);
await caughtUp(indexer);
raw = await indexer.client.cheapestRaw(ITEM, 50);
const newVerdict = await indexer.client.verify(raw.head, async () => void (await abortBlocks(sent.block)));
say(`answer at ${short(raw.head)} with lot 5 at 112; block ${sent.block} aborted between the rule's two reads; new order says "${newVerdict}"`);
check("new order (tip, then the answer's block last) rejects it", newVerdict !== "fresh", newVerdict);
await caughtUp(indexer);

// --- C. live reorg -----------------------------------------------------------------------------------
sent = await send(market.address, [["post", ITEM, 1, 120], ["buy", 1]]);
const reorgBlock = sent.block;
say(`post(item ${ITEM}, price 120) as lot 5 and buy(lot 1), in block ${reorgBlock}`);
sent = await send(market.address, [["locate", 1, 2]]);
await caughtUp(indexer);
const beforeLive = await truth(market.address, ITEM);
await until(() => shown(cache), (lots) => lots === beforeLive);
say(`before the abort: chain ${beforeLive}; cache ${await shown(cache)}`);
const aborted = await abortBlocks(reorgBlock);
const afterLive = await truth(market.address, ITEM);
say(`devnet_abortBlocks from ${reorgBlock}: ${aborted.length} blocks aborted; the chain's answer is now ${afterLive} (lot 1 open again, lot 5 gone)`);
const live = await sample(indexer, ITEM, afterLive, cache);
say(`live reorg, sampled from the abort until consistent: ${JSON.stringify(live)}`);
check("live: no accepted answer (query or cache) is a state the chain does not hold at its head", live.acceptedWrong === 0 && live.cacheWrong === 0, { acceptedWrong: live.acceptedWrong, cacheWrong: live.cacheWrong });
check("live: raw answers were orphaned in the window, and the rule rejected every one", live.rawWrong > 0, { rawWrong: live.rawWrong, accepted: live.accepted });
check("live: the cache reopened lot 1 (snapshot after rewind)", (await shown(cache)) === afterLive, await shown(cache));
const presenceAfter = await indexer.client.presence(1);
check("live: presence hub 1 = 2 again", presenceAfter.fresh && presenceAfter.answer.count === 2, presenceAfter.fresh ? presenceAfter.answer.count : presenceAfter.reason);

// --- D. a cache through a disconnection, a reorg and a reused lot id ---------------------------------
await close();
say(`cache closed: ready=${cache.ready}, shows ${await shown(cache)}`);
sent = await send(market.address, [["post", ITEM, 1, 500]]);
say(`post 500 in block ${sent.block} (lot 5)`);
await caughtUp(indexer);
await abortBlocks(sent.block);
sent = await send(market.address, [["post", ITEM, 1, 650], ["withdraw", 3]]);
say(`aborted it; post 650 (lot 5 again) and withdraw(lot 3) in block ${sent.block}`);
await caughtUp(indexer);
close = cache.connect();
await until(async () => (await cache.read()).fresh, (fresh) => fresh);
const afterReconnect = await truth(market.address, ITEM);
check("reconnected cache, through its read API, = the chain's (lot 5 is 650, lot 3 withdrawn)", (await shown(cache)) === afterReconnect, { cache: await shown(cache), chain: afterReconnect });

// --- E. unplanned close, then restart on a replaced tip with a slow node ------------------------------
check("before the indexer stops, the cache answers", (await cache.read()).fresh);
logs.push(indexer.logs);
await indexer.stop(); // the stream is closed by the server, not by the cache's owner
await until(async () => cache.ready, (ready) => !ready, 5000).catch(() => undefined);
const afterClose = await cache.read();
say(`indexer stopped; nobody closed the cache; it says ${JSON.stringify(afterClose)}`);
check("unplanned close: the cache is not ready and read() refuses, by itself", !cache.ready && !afterClose.fresh && cache.status === "disconnected", { ready: cache.ready, status: cache.status });
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
logs.push(indexer.logs);
await indexer.stop();
indexer = await startIndexer({ address: market.address, db: demoDb, from: market.block, rpcUrl: keyedUrl, poll: 100 });
await caughtUp(indexer);
({ cache, close } = listen(indexer));
await until(async () => (await cache.read()).fresh, (fresh) => fresh);
check("restart: cache = the chain's", (await shown(cache)) === afterOffline, await shown(cache));

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
answer = await indexer.client.cheapest(ITEM, 50);
check("u64: the lot counter rewound with it: the next lot id is 7, the chain's", answer.fresh && show(answer.answer.lots).includes("7:800"));

// --- G. rebuild from the chain ----------------------------------------------------------------------
started = performance.now();
const rebuilt = await startIndexer({ address: market.address, db: dbPath("rebuilt.db"), from: market.block, quiet: true });
await caughtUp(rebuilt);
say(`rebuild from block ${market.block} into an empty database: ${(performance.now() - started).toFixed(0)} ms`);
const answers = async (indexer: RunningIndexer) => {
  const items = [];
  for (const item of [ITEM, 9, BIG]) items.push(((await indexer.client.cheapestRaw(item, 50)) as any).lots);
  const hubs = [];
  for (const hub of [0, 1, 2]) hubs.push(((await indexer.client.presence(hub)) as any).answer.count);
  return JSON.stringify({ items, hubs, head: (await indexer.client.head()).head });
};
const kept = await answers(indexer);
const fresh = await answers(rebuilt);
say(`indexer that lived through the reorgs: ${kept}`);
say(`indexer rebuilt from the chain:        ${fresh}`);
check("rebuilt == rewound, answer for answer", kept === fresh);
logs.push(rebuilt.logs);
await rebuilt.stop();

// --- H. completeness: a served block replaced at the same height by a silent lot ----------------------
sent = await send(market.address, [["post", ITEM, 1, 900]]);
const served = sent.block;
await caughtUp(indexer);
say(`post 900 (lot 8) in block ${served}; served`);
const seen: { status: string; head?: string; commitments?: string }[] = [];
let sampling = true;
const sampler = (async () => {
  while (sampling) {
    const answer = await indexer.client.cheapestRaw(ITEM, 50);
    seen.push({ status: answer.status, head: answer.head ? `${answer.head.number}` : undefined, commitments: answer.head?.commitments });
    if (answer.status === "halted") break;
    await sleep(1);
  }
})();
const hashBefore = (await rpc("starknet_getBlockWithTxHashes", { block_id: { block_number: served } })).block_hash;
await abortBlocks(served);
sent = await send(market.address, [["post_silent", ITEM, 1, 900]]);
const replacement = await rpc("starknet_getBlockWithTxHashes", { block_id: { block_number: sent.block } });
const replacementCommitments = [replacement.transaction_commitment, replacement.event_commitment, replacement.receipt_commitment, replacement.state_diff_commitment].join(",");
say(`aborted block ${served}; post_silent (lot 8, no event) in block ${sent.block}; same hash as the aborted block: ${replacement.block_hash === hashBefore}`);
const halted = await until(() => indexer.client.head(), (value) => value.status === "halted", 10000);
sampling = false;
await sampler;
const servedReplacement = seen.filter((answer) => answer.head === `${sent.block}` && answer.commitments === replacementCommitments).length;
say(`sampled ${seen.length} answers during the replacement: ${JSON.stringify(Object.entries(seen.reduce((counts: Record<string, number>, answer) => ((counts[`${answer.status}@${answer.head ?? "-"}`] = (counts[`${answer.status}@${answer.head ?? "-"}`] ?? 0) + 1), counts), {})))}`);
check(`the replaced block (same height ${served}, same hash) is reconciled and halts the indexer`, new RegExp(`at block ${served} is 8, indexed 7`).test(halted.reason), halted);
check("the replacement block was never served (0 answers at its identity)", servedReplacement === 0, { servedReplacement });
check("halted: queries answer 503 halted, no rows", (await indexer.client.cheapestRaw(ITEM, 10)).status === "halted");
check("halted: the cache knows, and read() refuses", cache.status === "halted" && !cache.ready && !(await cache.read()).fresh, { status: cache.status, ready: cache.ready });
await send(market.address, [["post", ITEM, 1, 60]]);
const gap = await startIndexer({ address: market.address, db: dbPath("gap.db"), from: market.block, quiet: true });
const gapHalt = await until(() => gap.client.head(), (value) => value.status === "halted", 10000);
check("a rebuild halts on the id gap (LotPosted 9 after 7)", /expected lot 8/.test(gapHalt.reason), gapHalt);
logs.push(gap.logs);
await gap.stop();

const allLogs = [...logs.flat(), ...indexer.logs].join("\n");
check("no log line holds the provider key of the RPC URL", !allLogs.includes(FAKE_KEY) && allLogs.includes("/…(redacted)"));
check("no log line holds the node account's private key", !allLogs.includes(process.env.NODE_ACCOUNT_PRIVATE_KEY!));
await close();
await indexer.stop();
say(`timings: ${JSON.stringify({ liveLatestAcceptedMs: live.latestAcceptedMs, restartLatestAcceptedMs: restart.latestAcceptedMs })}`);
say(failures === 0 ? "all checks passed" : `${failures} checks FAILED`);
process.exit(failures === 0 ? 0 : 1);
