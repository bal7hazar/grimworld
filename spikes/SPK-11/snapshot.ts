// SPK-11 fix loop 2: the subscription's snapshot is complete beyond one page and beyond the 10 000
// lots the first version capped it at. Posts LOTS open lots of one item, starts the indexer,
// connects a LotCache and compares what its read API shows with the chain's view calls, lot for lot.
//   spikes/SPK-11/with-archive.sh node spikes/SPK-11/snapshot.ts [lots]
import { mkdirSync, rmSync } from "node:fs";
import { deployMarket, head, provider, send } from "./chain.ts";
import { LotCache, type LotEvent } from "./client.ts";
import { startIndexer } from "./run-indexer.ts";

const LOTS = Number(process.argv[2] ?? 10050);
const ITEM = 5;
const tmp = new URL("./.tmp/", import.meta.url).pathname;
mkdirSync(tmp, { recursive: true });
for (const suffix of ["", "-wal", "-shm"]) rmSync(`${tmp}snapshot.db${suffix}`, { force: true });
const say = (message: string) => console.log(`[snapshot] ${message}`);
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

const market = await deployMarket();
let posted = 0;
while (posted < LOTS) {
  const calls: [string, ...number[]][] = [];
  for (let k = 0; k < 100 && posted < LOTS; k++, posted++) calls.push(["post", ITEM, 1, 1000 + ((posted * 7919) % 5000)]);
  await send(market.address, calls);
}
const tip = (await head()).number;
say(`posted ${posted} lots of item ${ITEM}; chain tip ${tip}`);

const indexer = await startIndexer({ address: market.address, db: `${tmp}snapshot.db`, from: market.block, quiet: true });
while ((await indexer.client.head()).head?.number !== tip) await sleep(10);
const cache = new LotCache(indexer.client, ITEM);
const frames: Record<string, number> = {};
let announced = -1;
const close = cache.connect((event: LotEvent) => {
  frames[event.type] = (frames[event.type] ?? 0) + 1;
  if (event.type === "reset-begin") announced = event.data.total;
});
const started = performance.now();
let read = await cache.read();
while (!read.fresh) {
  if (performance.now() - started > 30000) throw new Error(`cache not fresh after 30 s: ${JSON.stringify(read)}`);
  await sleep(5);
  read = await cache.read();
}
say(`snapshot received in ${(performance.now() - started).toFixed(0)} ms: frames ${JSON.stringify(frames)}, announced total ${announced}`);

// The chain's own answer, by view calls: every lot 1..lot_count, open lots of ITEM sorted.
const [count] = (await provider.callContract({ contractAddress: market.address, entrypoint: "lot_count", calldata: [] })).map(BigInt);
const open: { lot: bigint; price: bigint }[] = [];
for (let lot = 1n; lot <= count; lot++) {
  const [item, , price, isOpen] = (await provider.callContract({ contractAddress: market.address, entrypoint: "lot", calldata: [lot.toString()] })).map(BigInt);
  if (item === BigInt(ITEM) && isOpen === 1n) open.push({ lot, price });
}
open.sort((a, b) => (a.price !== b.price ? (a.price < b.price ? -1 : 1) : a.lot < b.lot ? -1 : 1));
const chain = open.map((lot) => `${lot.lot}:${lot.price}`).join(" ");
const shown = read.fresh ? read.answer.lots.map((lot) => `${lot.lot}:${lot.price}`).join(" ") : "";
const ok = read.fresh && read.answer.lots.length === LOTS && shown === chain && (frames["reset-page"] ?? 0) > 10;
say(`cache shows ${read.fresh ? read.answer.lots.length : 0} lots; the chain holds ${open.length} open lots of item ${ITEM} (lot_count ${count}); identical, lot for lot: ${shown === chain}`);
say(ok ? "ok   complete snapshot beyond one page and beyond 10 000 lots" : "FAIL snapshot incomplete or different");
await close();
await indexer.stop();
process.exit(ok ? 0 : 1);
