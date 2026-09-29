// IDX-01b on the local node, registered by scenario.node.test.ts after IDX-01a's describe (the same
// node, the same results file): the queries against what the emitter sent, block time moved by
// devnet_increaseTime, the subscriptions read by the client library through a reorg, R3's stale and
// vanished heads, and the measures on 10 000 lots. It deploys emitters of its own, so its lot and
// trade ids start at 1.
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import type { Call } from "starknet";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { Chain, httpRpc, sameBlock, type Header } from "../src/chain.ts";
import {
  IndexerClient,
  InvitationCache,
  LotCache,
  PresenceCache,
  type Frame,
  type Lot,
  type StreamCache,
} from "../src/client/index.ts";
import { localNode, type LocalNode } from "./node.ts";
import { get, startIndexer, type RunningIndexer } from "./run-indexer.ts";

type Arg = bigint | number | boolean;
const call = (to: string, entrypoint: string, ...args: Arg[]): Call => ({
  contractAddress: to,
  entrypoint,
  calldata: args.map((arg) =>
    typeof arg === "boolean" ? (arg ? "1" : "0") : arg.toString(),
  ),
});

/** The median and the 95th percentile of `values`, in ms. */
function percentiles(values: number[]): string {
  const sorted = [...values].sort((a, b) => a - b);
  const at = (q: number) =>
    sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))]!;
  return `median ${at(0.5).toFixed(2)} ms, p95 ${at(0.95).toFixed(2)} ms (n=${values.length})`;
}

async function until(
  condition: () => boolean,
  what: string,
  timeoutMs = 60_000,
): Promise<number> {
  const started = performance.now();
  while (!condition()) {
    if (performance.now() - started > timeoutMs)
      throw new Error(`timed out waiting for ${what}`);
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  return performance.now() - started;
}

const K = 1234n; // a balance: item 1234
const S = 1235n; // the sales of Q3
const M = 1236n; // the 10 000 lots of the measures
const E = 2n ** 40n + 7n * 2n ** 16n + 12n * 2n ** 8n + 3n * 2n + 1n;
const hex = (value: bigint) => `0x${value.toString(16)}`;

export function describeQueries(
  nodeUrl: string | undefined,
  packageDir: string,
  out: (line: string) => void,
) {
  describe.skipIf(!nodeUrl)(
    "IDX-01b: queries, subscriptions and the client library on the local node",
    () => {
      let node: LocalNode;
      let chain: Chain;
      let hub: string;
      let market: string;
      let dir: string;
      let indexer: RunningIndexer;
      let client: IndexerClient;
      let lots = 0;
      let trades = 0;
      const closers: (() => Promise<void>)[] = [];

      const located = (hubId: number, adventurer: number) =>
        call(hub, "adventurer_located", hubId, adventurer);
      const title = (adventurer: number, id: number, tier: number) =>
        call(hub, "title_displayed", adventurer, id, tier);
      const post = (key: bigint, size: number, price: bigint, modifiers = 0n) =>
        call(
          market,
          "lot_posted",
          key,
          size,
          ++lots,
          price,
          1000n,
          0,
          modifiers,
        );
      const close = (lot: number, sold: boolean) =>
        call(market, "lot_closed", lot, sold);
      const invite = (invited: number, inviter: number) =>
        call(market, "trade_opened", invited, ++trades, inviter);
      const closeTrade = (trade: number, outcome: number) =>
        call(market, "trade_closed", trade, outcome);

      /** Waits until the indexer serves the node's block `number` (hash and commitments). */
      async function served(number: number, timeoutMs = 120_000) {
        const started = performance.now();
        for (;;) {
          const { code, body } = await get(indexer.url, "/head");
          const head = body.head as Header | null;
          if (code === 200 && head && head.number === number) {
            const onChain = await chain.header(number);
            if (
              onChain &&
              sameBlock({ ...head, parent: "" }, { ...onChain, parent: "" })
            )
              return;
          }
          if (performance.now() - started > timeoutMs)
            throw new Error(
              `block ${number} not served: ${JSON.stringify(body)}`,
            );
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      }

      /** A 200 answer's body; its head is the node's block, time included. */
      async function query(path: string) {
        const { code, body } = await get(indexer.url, path);
        expect([path, code]).toEqual([path, 200]);
        const head = body.head as Header;
        const onChain = await chain.header(head.number);
        expect(head).toEqual({
          number: onChain!.number,
          hash: onChain!.hash,
          commitments: onChain!.commitments,
          timestamp: onChain!.timestamp,
        });
        return body;
      }

      /** Opens a cache and keeps its frames. */
      function watch<Row>(cache: StreamCache<Row>) {
        const frames: Frame[] = [];
        closers.push(cache.connect((frame) => frames.push(frame)));
        return { cache, frames };
      }

      /** Waits until `cache` is ready at the node's block `number`. */
      async function at<Row>(cache: StreamCache<Row>, number: number) {
        const onChain = await chain.header(number);
        await until(
          () =>
            cache.ready &&
            cache.head?.number === number &&
            cache.head.commitments === onChain!.commitments,
          `a cache at block ${number}`,
        );
      }

      async function fresh<Row>(cache: StreamCache<Row>): Promise<Row[]> {
        const read = await cache.read();
        if (!read.fresh) throw new Error(`not fresh: ${read.reason}`);
        return read.answer.rows;
      }

      beforeAll(async () => {
        node = localNode();
        dir = mkdtempSync(join(packageDir, ".tmp-scenario-b-"));
        const hubDeployed = await node.deploy("HubEmitter");
        const marketDeployed = await node.deploy("MarketEmitter");
        hub = hubDeployed.address;
        market = marketDeployed.address;
        chain = new Chain(httpRpc(node.url), { hub, market });
        indexer = await startIndexer({
          command: "run",
          rpcUrl: node.url,
          hub,
          market,
          from: hubDeployed.block,
          db: join(dir, "b.sqlite"),
          extra: [
            "--max-subscriptions-per-client",
            "1000",
            "--max-subscriptions",
            "1000",
          ],
        });
        client = new IndexerClient({ url: indexer.url, node: node.url });
        out(
          `IDX-01b: emitters deployed at blocks ${hubDeployed.block} and ${marketDeployed.block}; indexer ${indexer.url}`,
        );
      });

      afterAll(async () => {
        for (const closer of closers) await closer();
        if (indexer) await indexer.stop();
        if (dir) rmSync(dir, { recursive: true, force: true });
      });

      it("AC-1, AC-2: every query answers what the emitter sent, as of the served block; block time only", async () => {
        await node.send([
          post(K, 10, 50n), // 1
          post(K, 10, 20n), // 2
          post(K, 10, 30n), // 3
          post(K, 10, 20n), // 4
          post(K, 10, 70n), // 5
          post(K, 10, 10n), // 6
          post(K, 1, 15n), // 7
          post(E, 1, 900n, 0xabcn), // 8
          located(40, 101),
          located(40, 102),
          located(40, 103),
          title(101, 7, 2),
          invite(500, 101), // trade 1
          invite(501, 102), // trade 2
        ]);
        let tip = await node.send([
          close(6, true),
          close(3, false),
          located(0, 103),
          closeTrade(2, 1),
          title(101, 8, 3),
        ]);
        await served(tip);
        const q1 = await query(`/lots?key=${hex(K)}&size=10&limit=2`);
        expect(q1).toMatchObject({ total: 4, next: "20:4" });
        expect((q1.lots as Lot[]).map((lot) => [lot.lot, lot.price])).toEqual([
          ["2", "20"],
          ["4", "20"],
        ]);
        const page2 = await query(`/lots?key=${hex(K)}&size=10&after=20:4`);
        expect((page2.lots as Lot[]).map((lot) => lot.lot)).toEqual(["1", "5"]);
        const q2 = await query(`/market?kind=balance&items=1234,1235`);
        expect(q2.keys).toEqual([
          {
            key: hex(K),
            decoded: { kind: "balance", item: 1234 },
            sizes: [
              {
                size: 1,
                cheapest: expect.objectContaining({ lot: "7", price: "15" }),
              },
              {
                size: 10,
                cheapest: expect.objectContaining({ lot: "2", price: "20" }),
              },
            ],
          },
        ]);
        expect((await query("/market?kind=equipment")).keys).toMatchObject([
          {
            key: hex(E),
            decoded: {
              kind: "equipment",
              base: 7,
              requirement: 12,
              rarity: 3,
              identified: true,
            },
            sizes: [{ size: 1, cheapest: { lot: "8", modifiers: "0xabc" } }],
          },
        ]);
        expect(await query("/hubs/presence?hub=40")).toMatchObject({
          count: 2,
          adventurers: [101, 102],
        });
        expect((await query("/titles?adventurers=101,102,103")).titles).toEqual(
          [
            { adventurer: 101, title: 8, tier: 3 },
            { adventurer: 102, title: null },
            { adventurer: 103, title: null },
          ],
        );
        const q7 = await query("/invitations?account=500");
        expect(q7).toMatchObject({ total: 1, invitations: [{ trade: "1" }] });
        expect((await query("/invitations?account=501")).total).toBe(0);

        // Q3: 4 sales, then 5 (lot 14 withdrawn: not a sale).
        await node.send(
          [100n, 200n, 300n, 400n, 500n, 600n].map((price) =>
            post(S, 1, price),
          ),
        ); // lots 9..14
        tip = await node.send([9, 10, 11, 12].map((lot) => close(lot, true)));
        await served(tip);
        const four = await query(`/prices?key=${hex(S)}&size=1`);
        expect(four).toMatchObject({ sales: 4 });
        expect(four).not.toHaveProperty("mean");
        tip = await node.send([close(13, true), close(14, false)]);
        await served(tip);
        const five = await query(`/prices?key=${hex(S)}&size=1`);
        expect(five).toMatchObject({ sales: 5, mean: "300" });
        out(
          `IDX-01b AC-1: Q1 ${JSON.stringify((q1.lots as Lot[]).map((lot) => `${lot.lot}@${lot.price}`))} of ${q1.total}, next ${q1.next}; Q2 ${JSON.stringify(q2.keys)}; ` +
            `Q4 hub 40 [101,102]; Q5 101 -> title 8 tier 3, 102 and 103 none; Q7 account 500 [trade 1], 501 [] (declined); Q3 4 sales: no mean, 5 sales: mean ${five.mean}; every head is the node's block, time included`,
        );

        // Block time: 10 minutes later the invitation is gone; 7 days later the sales are out.
        const openedAt = (q7.invitations as { openedTime: number }[])[0]!
          .openedTime;
        await node.increaseTime(600);
        tip = await node.send([located(41, 900)]);
        await served(tip);
        const expired = await query("/invitations?account=500");
        const expiredAt = (expired.head as Header).timestamp;
        expect(expiredAt - openedAt).toBeGreaterThanOrEqual(600);
        expect(expired.total).toBe(0);
        await node.increaseTime(7 * 24 * 60 * 60);
        tip = await node.send([located(41, 901)]);
        await served(tip);
        const old = await query(`/prices?key=${hex(S)}&size=1`);
        expect(old.sales).toBe(0);
        expect(old).not.toHaveProperty("mean");
        out(
          `IDX-01b AC-2: after devnet_increaseTime(600) the invitation opened at block time ${openedAt} is gone at block time ${expiredAt}; after 7 more days, Q3 counts ${old.sales} sales and has no mean`,
        );
      });

      it("AC-3, AC-4: the client library's caches follow each block, and resnapshot after a reorg", async () => {
        const lotsK = watch(new LotCache(client, K, 10));
        const presence = watch(new PresenceCache(client, 40));
        const invitations = watch(new InvitationCache(client, 500));
        // One list of the three, for what they share.
        const caches = [lotsK, presence, invitations] as unknown as {
          cache: StreamCache<unknown>;
          frames: Frame[];
        }[];
        let tip = await node.blockNumber();
        for (const { cache } of caches) await at(cache, tip);
        const httpLots = (await query(`/lots?key=${hex(K)}&size=10&limit=100`))
          .lots as Lot[];
        expect(await fresh(lotsK.cache)).toEqual(httpLots);

        // A block with a lot, an adventurer entering, an invitation: every cache follows.
        tip = await node.send([
          post(K, 10, 5n), // 15
          located(40, 104),
          invite(500, 104), // trade 3
        ]);
        for (const { cache } of caches) await at(cache, tip);
        expect((await fresh(lotsK.cache))[0]).toMatchObject({
          lot: "15",
          price: "5",
        });
        expect(await fresh(presence.cache)).toEqual([
          { adventurer: 101 },
          { adventurer: 102 },
          { adventurer: 104 },
        ]);
        expect(
          (await fresh(invitations.cache)).map(
            (invitation) => invitation.trade,
          ),
        ).toEqual(["3"]);

        // The block is aborted and replaced: another lot 15, adventurer 105, no invitation.
        const marks = caches.map(({ frames }) => frames.length);
        const abortedAt = performance.now();
        await node.abortBlocks(tip);
        lots -= 1;
        trades -= 1;
        const replaced = await node.send([post(K, 10, 6n), located(40, 105)]);
        expect(replaced).toBe(tip);
        await served(tip);
        for (const { cache } of caches) await at(cache, tip);
        const resnapshotMs = performance.now() - abortedAt;
        for (const [i, { frames }] of caches.entries()) {
          const after = frames.slice(marks[i]).map((frame) => frame.event);
          const rewind = after.indexOf("rewind");
          expect(rewind).toBeGreaterThanOrEqual(0);
          expect(after.indexOf("reset-end", rewind)).toBeGreaterThan(rewind);
        }
        expect((await fresh(lotsK.cache))[0]).toMatchObject({
          lot: "15",
          price: "6",
        });
        expect(await fresh(lotsK.cache)).toEqual(
          (await query(`/lots?key=${hex(K)}&size=10&limit=100`)).lots,
        );
        expect(await fresh(presence.cache)).toEqual([
          { adventurer: 101 },
          { adventurer: 102 },
          { adventurer: 105 },
        ]);
        expect(await fresh(invitations.cache)).toEqual([]);
        out(
          `IDX-01b AC-3: 3 caches (lots, presence, invitations) followed block ${tip}; block ${tip} aborted and replaced: each got \`rewind\` then a new snapshot, and read() equals the queries at the replacement, ${resnapshotMs.toFixed(0)} ms after the abort`,
        );
      });

      it("AC-4: R3 refuses a head more than 5 blocks behind the node's tip, and a head whose block the node no longer has", async () => {
        let tip = await node.blockNumber();
        await served(tip);
        const answer = (await client.raw("/hubs/presence", { hub: 40 }))
          .body as { status: string; head: Header };
        expect(await client.check(answer)).toMatchObject({ fresh: true });
        await node.createBlocks(6);
        const stale = await client.check(answer);
        expect(stale).toEqual({
          fresh: false,
          reason: "indexer 6 blocks behind the node",
        });
        tip = await node.send([located(42, 1)]);
        await served(tip);
        const cache = watch(new PresenceCache(client, 42));
        await at(cache.cache, tip);
        const before = (await client.raw("/hubs/presence", { hub: 42 }))
          .body as { status: string; head: Header };
        expect(before.head.number).toBe(tip);
        await node.abortBlocks(tip);
        const gone = await client.check(before);
        expect(gone).toEqual({
          fresh: false,
          reason: `block ${tip} is not the node's`,
        });
        const cached = await cache.cache.read();
        expect(cached.fresh).toBe(false);
        tip = await node.send([located(42, 2)]);
        await served(tip);
        await at(cache.cache, tip);
        expect(await fresh(cache.cache)).toEqual([{ adventurer: 2 }]);
        out(
          `IDX-01b AC-4: R3 through the client's own JSON-RPC reader: an answer 6 blocks behind -> "${stale.fresh ? "" : stale.reason}"; an answer at an aborted block -> "${gone.fresh ? "" : gone.reason}", and the cache at it -> "${cached.fresh ? "" : cached.reason}"; after the replacement the cache is fresh again`,
        );
      });

      it("AC-7: measures on 10 000 lots (query latency, snapshot time, memory per subscription, RPC calls per served block)", async () => {
        const stats = async () => (await get(indexer.url, "/stats")).body;
        const rpcTotal = (calls: Record<string, number>) =>
          Object.values(calls).reduce((a, b) => a + b, 0);
        /** RPC calls per block over `count` blocks of one lot and one move each. */
        async function perBlock(count: number) {
          const before = (await stats()).rpcCalls as Record<string, number>;
          let tip = 0;
          for (let i = 0; i < count; i++)
            tip = await node.send([post(K, 1, 1n), located(43, i)]);
          await served(tip);
          const after = (await stats()).rpcCalls as Record<string, number>;
          return (rpcTotal(after) - rpcTotal(before)) / count;
        }

        // 10 000 lots of one key and lot size: 100 transactions of 100.
        const posting = performance.now();
        let tip = 0;
        let seed = 7n;
        for (let t = 0; t < 100; t++) {
          const calls: Call[] = [];
          for (let i = 0; i < 100; i++) {
            seed =
              (seed * 6364136223846793005n + 1442695040888963407n) % 2n ** 64n;
            calls.push(post(M, 1, 1n + (seed % 1_000_000n)));
          }
          tip = await node.send(calls);
        }
        await served(tip, 600_000);
        out(
          `IDX-01b AC-7: 10 000 lots posted in 100 transactions and served in ${((performance.now() - posting) / 1000).toFixed(1)} s`,
        );

        const time = async (path: string) => {
          const started = performance.now();
          const { code } = await get(indexer.url, path);
          expect(code).toBe(200);
          return performance.now() - started;
        };
        // Q1: every page of 100 of the 10 000 lots, by cursor (each a new target: never kept).
        const q1: number[] = [];
        let after: string | null = null;
        let pages = 0;
        do {
          const path: string = `/lots?key=${hex(M)}&size=1&limit=100${after ? `&after=${after}` : ""}`;
          const started = performance.now();
          const { body } = await get(indexer.url, path);
          q1.push(performance.now() - started);
          after = body.next as string | null;
          if ((body.lots as Lot[]).length > 0) pages++; // a full last page is followed by an empty one
        } while (after);
        expect(pages).toBe(100);
        const q1Kept: number[] = [];
        for (let i = 0; i < 100; i++)
          q1Kept.push(await time(`/lots?key=${hex(M)}&size=1&limit=100`));
        const q2: number[] = [];
        for (let i = 1; i <= 100; i++)
          q2.push(await time(`/market?kind=balance&limit=${i}`));
        const q3: number[] = [];
        for (let i = 1; i <= 100; i++)
          q3.push(await time(`/prices?key=${hex(M)}&size=${i}`));
        const q4: number[] = [];
        for (let i = 1; i <= 100; i++)
          q4.push(await time(`/hubs/presence?hub=${i}`));
        const q5: number[] = [];
        for (let i = 1; i <= 100; i++)
          q5.push(
            await time(
              `/titles?adventurers=${Array.from({ length: i }, (_, j) => j + 100).join(",")}`,
            ),
          );
        const q7: number[] = [];
        for (let i = 1; i <= 100; i++)
          q7.push(await time(`/invitations?account=${i}`));
        out(
          "IDX-01b AC-7 latency over HTTP (client in the same machine), 10 000 open lots in the key, each target new (not kept):",
        );
        out(
          `  Q1 a page of 100, by cursor through all 10 000: ${percentiles(q1)}`,
        );
        out(
          `  Q1 the same first page again (kept for the served block, R6): ${percentiles(q1Kept)}`,
        );
        out(`  Q2 kind=balance, limit 1 to 100: ${percentiles(q2)}`);
        out(`  Q3: ${percentiles(q3)}`);
        out(`  Q4: ${percentiles(q4)}`);
        out(`  Q5, 1 to 100 adventurers: ${percentiles(q5)}`);
        out(`  Q7: ${percentiles(q7)}`);

        // RPC calls per served block, before any subscription.
        const without = await perBlock(20);

        // Snapshots of 10 000 lots, to the client library's cache.
        const snapshots: number[] = [];
        const rssBefore = (await stats()).rssMB as number;
        const big: StreamCache<Lot>[] = [];
        for (let i = 0; i < 10; i++) {
          const started = performance.now();
          const { cache } = watch(new LotCache(client, M, 1));
          big.push(cache);
          await until(() => cache.ready, "a snapshot of 10 000 lots");
          snapshots.push(performance.now() - started);
          expect(cache.size()).toBe(10_000);
        }
        const rssBig = (await stats()).rssMB as number;
        // 200 small subscriptions (a hub's presence).
        const small = Array.from(
          { length: 200 },
          () => watch(new PresenceCache(client, 40)).cache,
        );
        await until(
          () => small.every((cache) => cache.ready),
          "200 subscriptions",
        );
        const opened = await stats();
        const rssSmall = opened.rssMB as number;
        expect(opened.subscriptions).toBeGreaterThanOrEqual(210);
        out(
          `IDX-01b AC-7 snapshot of 10 000 lots, 10 pages (open to ready, in the client library): ${percentiles(snapshots)}`,
        );
        out(
          `IDX-01b AC-7 memory (the indexer's rss): ${rssBefore} MB -> ${rssBig} MB with 10 subscriptions of 10 000 lots (${(((rssBig - rssBefore) * 1024) / 10).toFixed(0)} KB each, snapshots sent) -> ${rssSmall} MB with 200 more of a hub's presence (${(((rssSmall - rssBig) * 1024) / 200).toFixed(1)} KB each); ${String(opened.subscriptions)} open`,
        );
        const withSubscriptions = await perBlock(20);
        for (const cache of small) expect(cache.ready).toBe(true);
        out(
          `IDX-01b AC-7 RPC calls per served block (1 lot and 1 move a block, poll 50 ms, idle polls included): ${without.toFixed(2)} without subscriptions, ${withSubscriptions.toFixed(2)} with ${String(opened.subscriptions)} open; RPC ${JSON.stringify((await stats()).rpcCalls)}`,
        );

        // Fix loop 1: a rewind with every subscription open. Each one resnapshots; the work is
        // spread over turns of the event loop and the 10 000-lot pages are read once per block,
        // so the process keeps answering meanwhile.
        const last = await node.blockNumber();
        await node.abortBlocks(last); // its lot and move (perBlock's last block)
        lots -= 1;
        const rewindAt = performance.now();
        const replacement = await node.send([located(44, 1)]);
        expect(replacement).toBe(last);
        const onChain = await chain.header(replacement);
        const caches: StreamCache<unknown>[] = [
          ...(big as unknown as StreamCache<unknown>[]),
          ...(small as unknown as StreamCache<unknown>[]),
        ];
        const again = () =>
          caches.every(
            (cache) =>
              cache.ready &&
              cache.head?.number === replacement &&
              cache.head.commitments === onChain!.commitments,
          );
        const headLatency: number[] = [];
        while (!again()) {
          if (performance.now() - rewindAt > 120_000)
            throw new Error("the caches did not resnapshot");
          const started = performance.now();
          await get(indexer.url, "/head");
          headLatency.push(performance.now() - started);
          await new Promise((resolve) => setTimeout(resolve, 5));
        }
        const resnapshotMs = performance.now() - rewindAt;
        const afterRewind = await stats();
        expect(afterRewind.subscribersDropped).toBe(0);
        out(
          `IDX-01b fix loop 1: a rewind with ${caches.length} subscriptions open (10 of 10 000 lots, 200 small): all ready again at the replacement ${resnapshotMs.toFixed(0)} ms after the abort; GET /head meanwhile ${percentiles(headLatency)}, max ${Math.max(...headLatency).toFixed(2)} ms; none dropped`,
        );
      });
    },
  );
}
