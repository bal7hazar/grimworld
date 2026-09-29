// The indexer on the local node (IDX-01a, AC-1, AC-2, AC-3, AC-8), run by `pnpm test:node`, which
// starts starknet-devnet with its full state archive (devnet_abortBlocks needs it) through
// scripts/with-node.sh. Without a node (the ordinary `pnpm test`) it is skipped.
//
// It deploys the emitter, starts the indexer as a child process, emits every event, checks every
// table; aborts blocks (reorgs of depth 1 to 5) and checks the rewind and that the tables equal a
// rebuild's; stops and restarts the indexer and checks it resumes; rebuilds from the deployment
// block and compares; and measures as SPK-11 did. Its figures go to .scenario-results.txt and to
// the console.
import {
  appendFileSync,
  mkdtempSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Call } from "starknet";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { Chain, httpRpc, sameBlock, type Header } from "../src/chain.ts";
import { Store, TABLES } from "../src/store.ts";
import { localNode, type LocalNode } from "./node.ts";
import { get, startIndexer, type RunningIndexer } from "./run-indexer.ts";

const nodeUrl = process.env.NODE_URL;
const PACKAGE = fileURLToPath(new URL("..", import.meta.url));
const RESULTS = join(PACKAGE, ".scenario-results.txt");
const U64_MAX = 2n ** 64n - 1n;

function out(line: string) {
  console.log(line);
  appendFileSync(RESULTS, `${line}\n`);
}

type Arg = bigint | number | boolean;
const call = (to: string, entrypoint: string, ...args: Arg[]): Call => ({
  contractAddress: to,
  entrypoint,
  calldata: args.map((arg) =>
    typeof arg === "boolean" ? (arg ? "1" : "0") : arg.toString(),
  ),
});

const equipmentKey = (
  base: number,
  requirement: number,
  rarity: number,
  identified: boolean,
) =>
  2n ** 40n +
  BigInt(base) * 2n ** 16n +
  BigInt(requirement) * 2n ** 8n +
  BigInt(rarity) * 2n +
  (identified ? 1n : 0n);

describe.skipIf(!nodeUrl)("the indexer on the local node", () => {
  let node: LocalNode;
  let chain: Chain;
  let hub: string;
  let market: string;
  let from: number;
  let dir: string;
  let lived: RunningIndexer;
  let lots = 0; // the last lot id posted on the canonical chain
  const running = new Set<RunningIndexer>();

  const h = {
    located: (hubId: number, adventurer: number) =>
      call(hub, "adventurer_located", hubId, adventurer),
    title: (adventurer: number, title: number, tier: number) =>
      call(hub, "title_displayed", adventurer, title, tier),
    trial: (adventurer: number, rank: number, first: boolean) =>
      call(hub, "trial_passed", adventurer, rank, first),
    cleared: (adventurer: number, dungeon: number) =>
      call(hub, "dungeon_cleared", adventurer, dungeon),
    rank: (adventurer: number, rank: number) =>
      call(hub, "rank_reached", adventurer, rank),
  };
  const m = {
    posted: (
      key: bigint,
      size: number,
      lot: bigint | number,
      price: bigint,
      expiry: bigint,
      equipment: number,
      modifiers: bigint,
    ) =>
      call(
        market,
        "lot_posted",
        key,
        size,
        lot,
        price,
        expiry,
        equipment,
        modifiers,
      ),
    closed: (lot: number, sold: boolean) =>
      call(market, "lot_closed", lot, sold),
    opened: (invited: number, trade: number, inviter: number) =>
      call(market, "trade_opened", invited, trade, inviter),
    tradeClosed: (trade: number, outcome: number) =>
      call(market, "trade_closed", trade, outcome),
  };
  /** The next lot, posted at `price`. */
  const nextLot = (price: bigint) =>
    m.posted(77n, 1, ++lots, price, 1000n, 0, 0n);

  async function start(
    command: "run" | "rebuild",
    db: string,
    fromBlock = from,
    depth?: number,
  ) {
    const indexer = await startIndexer({
      command,
      rpcUrl: node.url,
      hub,
      market,
      from: fromBlock,
      db,
      depth,
    });
    running.add(indexer);
    return indexer;
  }
  async function stop(indexer: RunningIndexer) {
    const code = await indexer.stop();
    running.delete(indexer);
    return code;
  }

  /** Waits until `indexer` serves the node's block `number` (same hash and commitments); ms waited. */
  async function served(
    indexer: RunningIndexer,
    number: number,
    timeoutMs = 60_000,
  ): Promise<number> {
    const started = performance.now();
    for (;;) {
      const { code, body } = await get(indexer.url, "/head");
      const head = body.head as Header | null;
      if (code === 200 && head && head.number === number) {
        const onChain = await chain.header(number);
        if (
          onChain &&
          sameBlock({ ...head, parent: "" }, { ...onChain, parent: "" })
        ) {
          return performance.now() - started;
        }
      }
      if (body.status === "halted")
        throw new Error(`halted: ${String(body.reason)}`);
      if (performance.now() - started > timeoutMs) {
        throw new Error(
          `block ${number} not served: ${JSON.stringify(body)}\n${indexer.logs.join("\n")}`,
        );
      }
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
  }

  const dump = (db: string) => {
    const store = new Store(db, { readOnly: true });
    try {
      return store.dump();
    } finally {
      store.close();
    }
  };

  /** Rebuilds a database from `fromBlock` to the node's tip; its dump and the rebuild's figures. */
  async function rebuild(file: string, fromBlock = from) {
    const tip = await node.blockNumber();
    const started = performance.now();
    const indexer = await start("rebuild", join(dir, file), fromBlock);
    await served(indexer, tip, 300_000);
    const ms = performance.now() - started;
    const stats = (await get(indexer.url, "/stats")).body;
    expect(await stop(indexer)).toBe(0);
    return {
      dump: dump(join(dir, file)),
      ms,
      stats,
      blocks: tip - fromBlock + 1,
      logs: indexer.logs,
    };
  }

  beforeAll(async () => {
    writeFileSync(
      RESULTS,
      `# IDX-01a local-node scenario, ${new Date().toISOString()}\n`,
    );
    node = localNode();
    dir = mkdtempSync(join(PACKAGE, ".tmp-scenario-"));
    const hubDeployed = await node.deploy("HubEmitter");
    const marketDeployed = await node.deploy("MarketEmitter");
    hub = hubDeployed.address;
    market = marketDeployed.address;
    from = hubDeployed.block;
    chain = new Chain(httpRpc(node.url), { hub, market });
    out(
      `deployed: HubEmitter at block ${hubDeployed.block}, MarketEmitter at block ${marketDeployed.block}; indexing from ${from}`,
    );
    lived = await start("run", join(dir, "lived.sqlite"));
    out(`indexer: ${lived.logs.find((line) => line.includes("serving on"))}`);
  });

  afterAll(async () => {
    for (const indexer of [...running]) await stop(indexer);
    if (dir) rmSync(dir, { recursive: true, force: true });
  });

  it("AC-1: decodes the nine events into their tables, every field", async () => {
    const tx1 = await node.send([
      h.located(3, 9),
      m.posted(77n, 10, 1, U64_MAX, 2n ** 63n, 0, 0n),
      h.title(9, 0xffff, 0xff),
      m.opened(12, 1, 9),
    ]);
    await node.send([
      m.posted(
        equipmentKey(7, 12, 3, true),
        1,
        2,
        2n ** 53n + 1n,
        U64_MAX,
        0xffffffff,
        0x1234abcdn,
      ),
      m.posted(2n ** 41n + 5n, 1, 3, 1n, 0n, 0, 0n),
    ]);
    await node.send([
      h.trial(9, 3, true),
      h.trial(9, 4, false),
      h.cleared(9, 6),
      h.rank(9, 2),
      h.located(0, 9),
      h.located(0xffff, 0xffffffff),
    ]);
    await node.send([
      m.closed(1, true),
      m.closed(2, false),
      m.opened(13, 2, 9),
      m.opened(14, 3, 9),
    ]);
    const tip = await node.send([
      m.tradeClosed(1, 0),
      m.tradeClosed(2, 1),
      m.tradeClosed(3, 2),
    ]);
    lots = 3;
    const ms = await served(lived, tip);
    out(
      `AC-1: blocks ${tx1}..${tip} served ${ms.toFixed(0)} ms after the last receipt`,
    );

    const store = new Store(join(dir, "lived.sqlite"), { readOnly: true });
    try {
      const pick = (rows: Record<string, unknown>[], keys: string[]) =>
        rows.map((row) =>
          Object.fromEntries(keys.map((key) => [key, row[key]])),
        );
      expect(
        pick(store.at("lots", tip), [
          "lot",
          "market_key",
          "kind",
          "item",
          "base",
          "requirement",
          "rarity",
          "identified",
          "lot_size",
          "price",
          "expiry",
          "equipment",
          "modifiers",
          "open",
          "sold",
        ]),
      ).toEqual([
        {
          lot: "1",
          market_key: 77,
          kind: "balance",
          item: 77,
          base: null,
          requirement: null,
          rarity: null,
          identified: null,
          lot_size: 10,
          price: "18446744073709551615",
          expiry: "9223372036854775808",
          equipment: 0,
          modifiers: "0x0",
          open: 0,
          sold: 1,
        },
        {
          lot: "2",
          market_key: Number(equipmentKey(7, 12, 3, true)),
          kind: "equipment",
          item: null,
          base: 7,
          requirement: 12,
          rarity: 3,
          identified: 1,
          lot_size: 1,
          price: "9007199254740993",
          expiry: "18446744073709551615",
          equipment: 4294967295,
          modifiers: "0x1234abcd",
          open: 0,
          sold: 0,
        },
        {
          lot: "3",
          market_key: 2 ** 41 + 5,
          kind: "boss",
          item: null,
          base: 5,
          requirement: null,
          rarity: null,
          identified: null,
          lot_size: 1,
          price: "1",
          expiry: "0",
          equipment: 0,
          modifiers: "0x0",
          open: 1,
          sold: 0,
        },
      ]);
      expect(
        pick(store.at("trades", tip), [
          "trade",
          "invited",
          "inviter",
          "open",
          "outcome",
        ]),
      ).toEqual([
        { trade: "1", invited: 12, inviter: 9, open: 0, outcome: 0 },
        { trade: "2", invited: 13, inviter: 9, open: 0, outcome: 1 },
        { trade: "3", invited: 14, inviter: 9, open: 0, outcome: 2 },
      ]);
      expect(pick(store.at("presence", tip), ["adventurer", "hub"])).toEqual([
        { adventurer: 4294967295, hub: 65535 },
        { adventurer: 9, hub: 0 },
      ]);
      expect(pick(store.at("presence", tx1), ["adventurer", "hub"])).toEqual([
        { adventurer: 9, hub: 3 },
      ]);
      expect(
        pick(store.at("titles", tip), ["adventurer", "title", "tier"]),
      ).toEqual([{ adventurer: 9, title: 65535, tier: 255 }]);
      expect(
        pick(store.at("trial_passes", tip), [
          "adventurer",
          "rank",
          "first_attempt",
        ]),
      ).toEqual([
        { adventurer: 9, rank: 3, first_attempt: 1 },
        { adventurer: 9, rank: 4, first_attempt: 0 },
      ]);
      expect(pick(store.at("clears", tip), ["adventurer", "dungeon"])).toEqual([
        { adventurer: 9, dungeon: 6 },
      ]);
      expect(pick(store.at("ranks", tip), ["adventurer", "rank"])).toEqual([
        { adventurer: 9, rank: 2 },
      ]);
      const names = store
        .at("events", tip)
        .sort(
          (a, b) =>
            Number(a._from) - Number(b._from) || Number(a.idx) - Number(b.idx),
        )
        .map((row) => row.name);
      expect(names).toEqual([
        "AdventurerLocated",
        "LotPosted",
        "TitleDisplayed",
        "TradeOpened",
        "LotPosted",
        "LotPosted",
        "TrialPassed",
        "TrialPassed",
        "DungeonCleared",
        "RankReached",
        "AdventurerLocated",
        "AdventurerLocated",
        "LotClosed",
        "LotClosed",
        "TradeOpened",
        "TradeOpened",
        "TradeClosed",
        "TradeClosed",
        "TradeClosed",
      ]);
      out(
        `AC-1: 19 events in 9 kinds; lots, trades, presence, titles, trial_passes, clears, ranks as sent`,
      );
    } finally {
      store.close();
    }
  });

  for (const depth of [1, 2, 3, 4, 5]) {
    it(`AC-2: a reorg of depth ${depth} (devnet_abortBlocks) is rewound, and the tables equal a rebuild's`, async () => {
      const before = lots;
      let tip = 0;
      for (let i = 0; i < depth; i++)
        tip = await node.send([
          nextLot(BigInt(10 + i)),
          h.located(20 + i, 500 + depth),
        ]);
      await served(lived, tip);
      const first = tip - depth + 1;
      const aborted = await Promise.all(
        Array.from({ length: depth }, (_, i) => chain.header(first + i)),
      );
      const rewindsBefore = (
        (await get(lived.url, "/stats")).body.rewinds as unknown[]
      ).length;
      const abortedAt = performance.now();
      await node.abortBlocks(first);
      lots = before;
      let newTip = 0;
      for (let i = 0; i < depth; i++)
        newTip = await node.send([
          nextLot(BigInt(1000 + i)),
          h.title(500 + depth, i, 1),
        ]);
      expect(newTip).toBe(tip);
      await served(lived, newTip);
      const consistentMs = performance.now() - abortedAt;
      const replaced = await Promise.all(
        Array.from({ length: depth }, (_, i) => chain.header(first + i)),
      );
      const sameHashes = replaced.every(
        (block, i) => block!.hash === aborted[i]!.hash,
      );
      const otherCommitments = replaced.every(
        (block, i) => block!.commitments !== aborted[i]!.commitments,
      );
      expect(otherCommitments).toBe(true);
      const stats = (await get(lived.url, "/stats")).body;
      const rewinds = (
        stats.rewinds as { from: number; to: number; ms: number }[]
      ).slice(rewindsBefore);
      expect(rewinds.length).toBeGreaterThanOrEqual(1);
      expect(rewinds[rewinds.length - 1]!.to).toBe(first - 1);
      const rebuilt = await rebuild("rebuilt.sqlite");
      expect(dump(join(dir, "lived.sqlite"))).toEqual(rebuilt.dump);
      out(
        `AC-2 depth ${depth}: blocks ${first}..${tip} aborted and replaced; replacement hashes equal the aborted ones: ${sameHashes}; commitments differ: ${otherCommitments}; ` +
          `rewinds ${rewinds.map((r) => `${r.from}->${r.to} in ${r.ms.toFixed(2)} ms`).join(", ")}; new tip served ${consistentMs.toFixed(0)} ms after the abort; tables equal a rebuild: true`,
      );
    });
  }

  it("AC-3: a restart resumes from the database without re-applying a block, and `rebuild --from` gives the same tables", async () => {
    const stoppedAt = await node.blockNumber();
    expect(await stop(lived)).toBe(0);
    let tip = 0;
    for (let i = 0; i < 3; i++)
      tip = await node.send([nextLot(BigInt(7 + i)), h.rank(9, 3 + i)]);
    lived = await start("run", join(dir, "lived.sqlite"));
    expect(lived.logs.join("\n")).toContain(`stored tip ${stoppedAt} `);
    await served(lived, tip);
    const stats = (await get(lived.url, "/stats")).body;
    expect(stats.blocksApplied).toBe(tip - stoppedAt);
    const events = dump(join(dir, "lived.sqlite")).events;
    const positions = new Set(events.map((row) => `${row.tx_hash}:${row.idx}`));
    expect(positions.size).toBe(events.length);
    const rebuilt = await rebuild("rebuilt.sqlite");
    expect(dump(join(dir, "lived.sqlite"))).toEqual(rebuilt.dump);
    out(
      `AC-3: stopped at block ${stoppedAt}; 3 blocks sent while stopped; restarted: blocksApplied ${stats.blocksApplied} (blocks ${stoppedAt + 1}..${tip}); ${events.length} raw events, no position twice; rebuild --from ${from}: same tables`,
    );
  });

  it("AC-8: measures (catch-up, RSS, RPC calls per empty block and per idle poll, disk)", async () => {
    // Bulk: 50 transactions of 100 events each (90 AdventurerLocated, 10 LotPosted).
    let tip = 0;
    for (let t = 0; t < 50; t++) {
      const calls: Call[] = [];
      for (let i = 0; i < 100; i++)
        calls.push(
          i % 10 === 0
            ? nextLot(BigInt(t * 100 + i))
            : h.located(1 + (i % 7), t * 100 + i),
        );
      tip = await node.send(calls);
    }
    await served(lived, tip);
    const firstEmpty = tip + 1;
    await node.createBlocks(200);
    tip = await node.blockNumber();
    await served(lived, tip);

    const catchUp = await rebuild("catchup.sqlite");
    const events = catchUp.dump.events.length;
    expect(dump(join(dir, "lived.sqlite"))).toEqual(catchUp.dump);
    const size = ["", "-wal"].reduce((sum, suffix) => {
      try {
        return sum + statSync(join(dir, `catchup.sqlite${suffix}`)).size;
      } catch {
        return sum;
      }
    }, 0);
    out(
      `AC-8 catch-up: rebuild --from ${from} to ${tip}: ${catchUp.blocks} blocks, ${events} events in ${(catchUp.ms / 1000).toFixed(2)} s (process start included): ` +
        `${((catchUp.blocks * 1000) / catchUp.ms).toFixed(0)} blocks/s, ${((events * 1000) / catchUp.ms).toFixed(0)} events/s; maxRSS ${catchUp.stats.maxRssMB} MB; ` +
        `RPC ${JSON.stringify(catchUp.stats.rpcCalls)}; database ${(size / 1e6).toFixed(2)} MB (${(size / events).toFixed(0)} bytes per event, all blocks kept); same tables as the live indexer: true`,
    );

    const empty = await rebuild("empty.sqlite", firstEmpty);
    const calls = empty.stats.rpcCalls as Record<string, number>;
    const total = Object.values(calls).reduce((a, b) => a + b, 0);
    out(
      `AC-8 empty blocks: rebuild --from ${firstEmpty} to ${tip}: ${empty.blocks} blocks without events in ${(empty.ms / 1000).toFixed(2)} s ` +
        `(${(empty.ms / empty.blocks).toFixed(2)} ms per block); RPC ${JSON.stringify(calls)} = ${(total / empty.blocks).toFixed(2)} calls per block`,
    );

    const idleBefore = (await get(lived.url, "/stats")).body.rpcCalls as Record<
      string,
      number
    >;
    await new Promise((resolve) => setTimeout(resolve, 5000));
    const idleAfter = (await get(lived.url, "/stats")).body.rpcCalls as Record<
      string,
      number
    >;
    const delta = Object.fromEntries(
      Object.keys(idleAfter).map((key) => [
        key,
        (idleAfter[key] ?? 0) - (idleBefore[key] ?? 0),
      ]),
    );
    const polls = delta.starknet_blockHashAndNumber ?? 0;
    const idleTotal = Object.values(delta).reduce((a, b) => a + b, 0);
    out(
      `AC-8 idle following (poll 50 ms), 5 s: RPC ${JSON.stringify(delta)} = ${(idleTotal / 5).toFixed(1)} calls per second, ${(idleTotal / polls).toFixed(2)} per poll`,
    );
    const stats = (await get(lived.url, "/stats")).body;
    out(
      `AC-8 live indexer: maxRSS ${stats.maxRssMB} MB, rss ${stats.rssMB} MB, ${stats.blocksApplied} blocks and ${stats.eventsApplied} events applied since its restart`,
    );

    // Nothing secret in the indexer's logs: the node account's key never reaches it.
    const key = process.env.NODE_ACCOUNT_PRIVATE_KEY!;
    for (const logs of [lived.logs, catchUp.logs, empty.logs]) {
      expect(logs.some((line) => line.includes(key))).toBe(false);
    }
    out(
      `logs: ${lived.logs
        .filter((line) => /rewind|status|serving|stopped/.test(line))
        .slice(0, 12)
        .join("\n      ")}`,
    );
  });

  it("fix loop 1: pruning on the local node keeps what the kept blocks read, and a reorg inside the kept history is rewound", async () => {
    const DEPTH = 20;
    const db = join(dir, "pruned.sqlite");
    const pruned = await start("run", db, from, DEPTH);
    let tip = await node.blockNumber();
    await served(pruned, tip, 300_000);
    // One more block, so that the step that checks the tip also prunes up to it.
    tip = await node.send([nextLot(1n), h.located(2, 7)]);
    await served(pruned, tip);
    await served(lived, tip);
    const stats = (await get(pruned.url, "/stats")).body;
    expect(stats.lowest).toBe(tip - DEPTH);
    // A reorg of depth 3, inside the kept history.
    const first = tip - 2;
    await node.abortBlocks(first);
    lots -= 1; // the last block posted one lot
    for (let i = 0; i < 3; i++) await node.send([h.title(7, i, 2)]);
    tip = await node.send([nextLot(3n)]);
    await served(pruned, tip);
    await served(lived, tip);
    const after = (await get(pruned.url, "/stats")).body;
    expect(after.rewindCount).toBeGreaterThanOrEqual(1);
    // Every table read as of the tip equals the unpruned indexer's.
    const a = new Store(db, { readOnly: true });
    const b = new Store(join(dir, "lived.sqlite"), { readOnly: true });
    try {
      for (const table of TABLES)
        expect(a.at(table, tip)).toEqual(b.at(table, tip));
      const versions = a.rows();
      const all = b.rows();
      out(
        `fix loop 1, pruning: --depth ${DEPTH}: lowest kept block ${after.lowest} at tip ${tip}; ${versions} row versions kept of ${all} in the unpruned database; ` +
          `abort of blocks ${first}.. rewound (${after.rewindCount} rewind); tables as of the tip equal the unpruned indexer's: true`,
      );
    } finally {
      a.close();
      b.close();
    }
    expect(await stop(pruned)).toBe(0);
  });
});
