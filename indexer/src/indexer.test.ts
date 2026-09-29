import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { BadAnswer, Chain } from "./chain.ts";
import { Indexer, REWINDS_KEPT, type Depth } from "./indexer.ts";
import { answer } from "./server.ts";
import { Halt, Store } from "./store.ts";
import {
  FakeNode,
  HUB,
  MARKET,
  ev,
  type FakeTransaction,
} from "./testing/fake-node.ts";

function indexer(
  node: FakeNode,
  options: {
    db?: string;
    depth?: Depth;
    batch?: number;
    from?: number;
    recheck?: { depth: number; everyMs: number };
  } = {},
) {
  return new Indexer({
    recheck: options.recheck,
    chain: new Chain(node.rpc, { hub: HUB, market: MARKET }),
    store: new Store(options.db ?? ":memory:"),
    config: {
      hub: HUB,
      market: MARKET,
      from: options.from ?? 1,
      lotCount: 0n,
      tradeCount: 0n,
    },
    depth: options.depth ?? 1000,
    batch: options.batch,
  });
}

/** Steps until idle or halted, as the process's loop does. */
async function settle(subject: Indexer) {
  for (let i = 0; i < 1000; i++) {
    try {
      if (!(await subject.step())) return;
    } catch (error) {
      if (!(error instanceof Halt)) throw error;
      subject.halt(error.message);
      return;
    }
  }
  throw new Error("did not settle");
}

/** Block k posts lot k at 10k, moves adventurer 9 to hub k, and closes lot k-1 (sold when k is even). */
function history(node: FakeNode, blocks: number) {
  for (let k = 1; k <= blocks; k++) {
    const transactions: FakeTransaction[] = [
      [ev.posted(k, { price: BigInt(10 * k) }), ev.located(k, 9)],
    ];
    if (k > 1)
      transactions.push([ev.closed(k - 1, k % 2 === 0), ev.rank(9, k)]);
    node.mine(...transactions);
  }
}

/** The same chain, indexed from nothing. */
async function rebuilt(node: FakeNode) {
  const fresh = indexer(node);
  await settle(fresh);
  return fresh.store.dump();
}

describe("following the node", () => {
  it("applies both contracts' events in block order and serves a block only after checking it", async () => {
    const node = new FakeNode();
    // One transaction interleaving the two contracts, then a second transaction.
    node.mine(
      [
        ev.located(3, 9),
        ev.posted(1, { price: 2n ** 64n - 1n }),
        ev.title(9, 4, 2),
        ev.opened(1, 12, 9),
      ],
      [
        ev.trial(9, 1, true),
        ev.cleared(9, 6),
        ev.rank(9, 1),
        ev.closed(1, true),
        ev.tradeClosed(1, 1),
      ],
    );
    const subject = indexer(node);
    expect(subject.status).toBe("loading");
    expect(await subject.step()).toBe(true);
    expect(subject.status).toBe("loading"); // applied, not yet checked
    expect(subject.store.tip()?.number).toBe(1);
    await settle(subject);
    expect(subject.status).toBe("ok");
    expect(subject.served?.number).toBe(1);
    const events = subject.store
      .at("events", 1)
      .sort(
        (a, b) => Number(a.tx) - Number(b.tx) || Number(a.idx) - Number(b.idx),
      );
    expect(events.map((row) => row.name)).toEqual([
      "AdventurerLocated",
      "LotPosted",
      "TitleDisplayed",
      "TradeOpened",
      "TrialPassed",
      "DungeonCleared",
      "RankReached",
      "LotClosed",
      "TradeClosed",
    ]);
    expect(subject.store.at("lots", 1)).toMatchObject([
      { lot: "1", price: "18446744073709551615", open: 0, sold: 1 },
    ]);
    expect(subject.store.at("trades", 1)).toMatchObject([
      { trade: "1", open: 0, outcome: 1 },
    ]);
  });

  it("reads events page by page", async () => {
    const node = new FakeNode();
    node.mine(Array.from({ length: 2500 }, (_, i) => ev.located(1, i)));
    const subject = indexer(node);
    await settle(subject);
    expect(subject.store.countsAt(1).presence).toBe(2500);
    expect(subject.chain.calls.starknet_getEvents).toBe(3 + 1); // 3 pages of hub, 1 of market
  });

  for (const depth of [1, 2, 3, 4, 5]) {
    it(`rewinds a reorg of depth ${depth}, detected by commitments under the same hashes, to the tables of a rebuild`, async () => {
      const node = new FakeNode();
      history(node, 8);
      const subject = indexer(node);
      await settle(subject);
      expect(subject.served?.number).toBe(8);
      const tip = node.tip;
      // Replacements at the same heights, keeping the aborted hashes (devnet): lots re-posted at
      // other prices, ids reused, a trade that was not there.
      const replacements = Array.from({ length: depth }, (_, j) => {
        const k = tip - depth + 1 + j;
        return [
          [ev.posted(k, { price: BigInt(1000 * k) }), ev.located(100 + k, 9)],
          [ev.opened(j + 1, 5, 6)],
        ];
      });
      node.reorg(depth, replacements, true);
      expect(node.blocks[tip]!.hash).toBe(subject.served?.hash); // same hash, other commitments
      expect(await subject.step()).toBe(true);
      expect(subject.status).toBe("rewinding");
      expect(subject.rewinds).toMatchObject([{ from: tip, to: tip - depth }]);
      expect(answer(subject, "/head").code).toBe(503);
      await settle(subject);
      expect(subject.status).toBe("ok");
      expect(subject.served?.commitments).not.toBe(undefined);
      expect(subject.store.dump()).toEqual(await rebuilt(node));
    });
  }

  it("catches a replacement that happens between two blocks of one step (devnet: the parent hash does not prove it)", async () => {
    const node = new FakeNode();
    history(node, 6);
    const subject = indexer(node);
    let done = false;
    node.beforeCall = (method) => {
      // Once block 5 is applied and the header of block 6 is about to be read: replace 5 and 6.
      if (
        !done &&
        method === "starknet_getBlockWithTxHashes" &&
        subject.store.tip()?.number === 5
      ) {
        done = true;
        node.reorg(
          2,
          [
            [[ev.posted(5, { price: 5555n })]],
            [[ev.posted(6, { price: 6666n })]],
          ],
          true,
        );
      }
    };
    await settle(subject);
    expect(done).toBe(true);
    expect(subject.rewinds).toHaveLength(1);
    expect(subject.rewinds[0]).toMatchObject({ to: 4 });
    expect(subject.store.dump()).toEqual(await rebuilt(node));
  });

  it("rewinds a reorg that removes blocks without replacing them", async () => {
    const node = new FakeNode();
    history(node, 5);
    const subject = indexer(node);
    await settle(subject);
    node.reorg(3);
    await settle(subject);
    expect(subject.served?.number).toBe(2);
    expect(subject.store.dump()).toEqual(await rebuilt(node));
  });
});

describe("halting", () => {
  it("halts on an undecodable event, says why, and answers 503 halted", async () => {
    const node = new FakeNode();
    history(node, 2);
    node.mine([{ source: "hub", keys: ["0x1234", "0x1"], data: [] }]);
    const subject = indexer(node);
    await settle(subject);
    expect(subject.status).toBe("halted");
    expect(subject.reason).toMatch(
      /undecodable event of hub in block 3 \(transaction 0, event 0\): unknown event of hub/,
    );
    expect(subject.store.tip()?.number).toBe(2);
    expect(answer(subject, "/head")).toMatchObject({
      code: 503,
      body: { status: "halted", reason: subject.reason },
    });
    expect(await subject.step()).toBe(false); // halted for good
  });

  it("halts on a value wider than its type", async () => {
    const node = new FakeNode();
    node.mine([ev.closed(2n ** 64n, true)]);
    const subject = indexer(node);
    await settle(subject);
    expect(subject.reason).toMatch(/wider than u64/);
  });

  it("halts on a gap in lot ids", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)], [ev.posted(3)]);
    const subject = indexer(node);
    await settle(subject);
    expect(subject.status).toBe("halted");
    expect(subject.reason).toMatch(
      /gap: LotPosted of lot 3 in block 1 \(transaction 1, event 0\), expected lot 2/,
    );
    expect(subject.store.tip()).toBe(undefined); // the block was not applied
  });

  it("halts when the node goes back below the kept history", async () => {
    const node = new FakeNode();
    history(node, 10);
    const subject = indexer(node, { depth: 2 });
    await settle(subject);
    expect(subject.store.lowest()?.number).toBe(8);
    node.reorg(5, [[[ev.located(1, 1)]]]);
    await settle(subject);
    expect(subject.status).toBe("halted");
    expect(subject.reason).toMatch(/below the kept history: block 8/);
  });
});

describe("history", () => {
  it("keeps a number of blocks below the tip", async () => {
    const node = new FakeNode();
    history(node, 10);
    const subject = indexer(node, { depth: 3 });
    await settle(subject);
    expect(subject.store.lowest()?.number).toBe(7);
    // A reorg within the kept history is rewound as usual.
    node.reorg(3, [[[ev.posted(8, { price: 1n })]]], true);
    await settle(subject);
    expect(subject.status).toBe("ok");
    expect(subject.store.at("lots", 8)).toContainEqual(
      expect.objectContaining({ lot: "8", price: "1" }),
    );
  });

  it("counts the kept depth from its own checked tip during a catch-up, not from the node's (GPT 1, fix loop 2)", async () => {
    const node = new FakeNode();
    for (let k = 1; k <= 1000; k++) node.mine([ev.located(k, 9)]);
    const subject = indexer(node, { depth: 20, batch: 100 });
    await subject.step(); // applies 1..100
    await subject.step(); // checks 100, prunes at 100 - 20, then applies 101..200
    // 20 blocks below the checked tip (100) are kept; the node's tip (1000) gave 980, clamped to 100.
    expect(subject.store.lowest()?.number).toBe(80);
    // Blocks 99 onwards replaced: a reorg of depth 2 below the checked tip, within the depth.
    node.reorg(
      902,
      Array.from({ length: 902 }, (_, i) => [[ev.located(i, 10)]]),
    );
    await settle(subject);
    expect(subject.status).toBe("ok");
    expect(subject.rewinds[0]).toMatchObject({ to: 98 });
    expect(subject.served?.number).toBe(1000);
    // The tables as of the tip equal a rebuild's (a pruned database keeps fewer old versions).
    const fresh = indexer(node, { depth: 20, batch: 100 });
    await settle(fresh);
    for (const table of ["presence", "events"] as const) {
      expect(subject.store.at(table, 1000)).toEqual(
        fresh.store.at(table, 1000),
      );
    }
  });

  it("keeps everything down to the last block accepted on L1 (depth l1)", async () => {
    const node = new FakeNode();
    history(node, 6);
    const subject = indexer(node, { depth: "l1" });
    await settle(subject);
    expect(subject.store.lowest()?.number).toBe(1); // nothing accepted on L1 yet
    node.l1Accepted = 4;
    node.mine();
    await settle(subject);
    expect(subject.store.lowest()?.number).toBe(4);
  });
});

describe("restart and rebuild", () => {
  const dirs: string[] = [];
  afterEach(() => {
    for (const dir of dirs.splice(0))
      rmSync(dir, { recursive: true, force: true });
  });
  const tempDir = () => {
    const dir = mkdtempSync(
      join(fileURLToPath(new URL("..", import.meta.url)), ".tmp-"),
    );
    dirs.push(dir);
    return dir;
  };

  it("resumes from its database without applying a block twice, and checks the stored tip before serving", async () => {
    const db = join(tempDir(), "indexer.sqlite");
    const node = new FakeNode();
    history(node, 5);
    const first = indexer(node, { db });
    await settle(first);
    first.store.close();
    history(node, 0);
    node.mine([ev.posted(6), ev.located(1, 2)], [ev.closed(6, false)]);
    node.mine();
    const second = indexer(node, { db });
    expect(second.status).toBe("loading");
    expect(answer(second, "/head").code).toBe(503);
    await settle(second);
    expect(second.blocksApplied).toBe(2);
    expect(second.served?.number).toBe(7);
    expect(second.store.dump()).toEqual(await rebuilt(node));
  });

  it("rewinds at restart when the stored tip was replaced while it was stopped", async () => {
    const db = join(tempDir(), "indexer.sqlite");
    const node = new FakeNode();
    history(node, 5);
    const first = indexer(node, { db });
    await settle(first);
    first.store.close();
    node.reorg(
      2,
      [[[ev.posted(4, { price: 4n })]], [[ev.posted(5, { price: 5n })]]],
      true,
    );
    const second = indexer(node, { db });
    await settle(second);
    expect(second.rewinds).toMatchObject([{ from: 5, to: 3 }]);
    expect(second.store.dump()).toEqual(await rebuilt(node));
  });

  it("rebuilds from the chain: an emptied database gives the same tables", async () => {
    const db = join(tempDir(), "indexer.sqlite");
    const node = new FakeNode();
    history(node, 6);
    const lived = indexer(node, { db });
    await settle(lived);
    node.reorg(2, [[[ev.posted(5, { price: 9n })]]], true);
    await settle(lived);
    const before = lived.store.dump();
    lived.store.clear();
    lived.store.close();
    const again = indexer(node, { db });
    await settle(again);
    expect(again.store.dump()).toEqual(before);
  });
});

describe("fix loop 1", () => {
  /**
   * Blocks 1..5 indexed and served, block 6 empty on the node. While the step reads block 6, block
   * 5 and 6 are replaced (devnet: same hashes): 5' posts lot 6, 6' closes it. On the stale 5, 6'
   * would halt for good with "no such lot".
   */
  function raced() {
    const node = new FakeNode();
    history(node, 5);
    const subject = indexer(node);
    return { node, subject };
  }
  const replace = (node: FakeNode) =>
    node.reorg(
      2,
      [[[ev.posted(5, { price: 55n }), ev.posted(6)]], [[ev.closed(6, true)]]],
      true,
    );
  const asks = (params: unknown, number: number) =>
    (params as { block_id?: { block_number?: number } }).block_id
      ?.block_number === number;

  it("applies a block only if its parent is still the stored one, read after the block (Opus 2)", async () => {
    const { node, subject } = raced();
    await settle(subject);
    node.mine();
    let replaced = false;
    node.beforeCall = (method, params) => {
      if (
        !replaced &&
        method === "starknet_getBlockWithTxHashes" &&
        asks(params, 6)
      ) {
        replaced = true;
        replace(node);
      }
    };
    const logs: string[] = [];
    const logged = new Indexer({
      chain: new Chain(node.rpc, { hub: HUB, market: MARKET }),
      store: subject.store,
      config: {
        hub: HUB,
        market: MARKET,
        from: 1,
        lotCount: 0n,
        tradeCount: 0n,
      },
      depth: 1000,
      log: (message) => logs.push(message),
    });
    await settle(logged);
    expect(replaced).toBe(true);
    expect(logged.status).toBe("ok");
    expect(logged.rewindCount).toBe(1);
    // Block 6' never reached the tables on the stale block 5: the parent's re-read stopped it
    // before the apply (the halt's re-check, the second guard, was not needed).
    expect(logs.some((line) => /changed while it was applied/.test(line))).toBe(
      false,
    );
    expect(logged.store.dump()).toEqual(await rebuilt(node));
  });

  it("does not make a halt permanent when the block or its parent changed meanwhile (Opus 2)", async () => {
    const { node, subject } = raced();
    await settle(subject);
    node.mine();
    const stale = node.blocks[5]!;
    const staleAnswer = {
      status: "ACCEPTED_ON_L2",
      block_hash: stale.hash,
      parent_hash: stale.parent,
      block_number: 5,
      transaction_commitment: stale.commitment,
      event_commitment: stale.commitment,
      receipt_commitment: stale.commitment,
      state_diff_commitment: stale.commitment,
    };
    let phase = 0;
    node.beforeCall = (method, params) => {
      if (
        phase === 0 &&
        method === "starknet_getBlockWithTxHashes" &&
        asks(params, 6)
      ) {
        phase = 1;
        replace(node);
      }
    };
    // The re-read of block 5 answers the stale block once: the parent check passes, the apply halts.
    node.tamper = (method, params, result) => {
      if (
        phase === 1 &&
        method === "starknet_getBlockWithTxHashes" &&
        asks(params, 5)
      ) {
        phase = 2;
        return staleAnswer;
      }
      return result;
    };
    const logs: string[] = [];
    const logged = new Indexer({
      chain: new Chain(node.rpc, { hub: HUB, market: MARKET }),
      store: subject.store,
      config: {
        hub: HUB,
        market: MARKET,
        from: 1,
        lotCount: 0n,
        tradeCount: 0n,
      },
      depth: 1000,
      log: (message) => logs.push(message),
    });
    await settle(logged);
    expect(phase).toBe(2);
    expect(
      logs.some((line) =>
        /changed while it was applied \(LotClosed of lot 6 .*no such lot\)/.test(
          line,
        ),
      ),
    ).toBe(true);
    expect(logged.status).toBe("ok");
    expect(logged.store.dump()).toEqual(await rebuilt(node));
  });

  it("still halts for good when the block and its parent are the node's (Opus 2)", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    node.mine([ev.closed(7, true)]);
    const subject = indexer(node);
    await settle(subject);
    expect(subject.status).toBe("halted");
    expect(subject.reason).toMatch(/LotClosed of lot 7 .*no such lot/);
  });

  it("checks a window of ancestors again: a replaced ancestor under a tip of the same hash and commitments (Opus 4)", async () => {
    for (const depth of [0, 10]) {
      const node = new FakeNode();
      history(node, 4);
      node.mine();
      node.mine();
      const subject = indexer(node, { recheck: { depth, everyMs: 0 } });
      await settle(subject);
      expect(subject.store.checked()).toBe(6);
      const old = node.blocks.slice(4, 7).map((block) => block.commitment);
      node.reorg(3, [[[ev.posted(4, { price: 44n })]], [], []], true);
      // The empty replacements keep the aborted commitments too: only block 4 differs.
      node.blocks[5]!.commitment = old[1]!;
      node.blocks[6]!.commitment = old[2]!;
      await settle(subject);
      if (depth === 0) {
        expect(subject.rewindCount).toBe(0); // unseen without the window
        expect(subject.store.dump()).not.toEqual(await rebuilt(node));
      } else {
        expect(subject.rewinds).toMatchObject([{ from: 6, to: 3 }]);
        expect(subject.store.dump()).toEqual(await rebuilt(node));
      }
    }
  });

  it("retries, never applies, a block of another height or without commitments (GPT 2, 3)", async () => {
    for (const bad of ["height", "commitments"]) {
      const node = new FakeNode();
      node.mine([ev.posted(1)]);
      const subject = indexer(node);
      node.tamper = (method, params, result) => {
        if (method !== "starknet_getBlockWithTxHashes" || !asks(params, 1))
          return result;
        const block = { ...(result as Record<string, unknown>) };
        if (bad === "height") block.block_number = 2;
        else delete block.event_commitment;
        return block;
      };
      await expect(subject.step()).rejects.toThrow(BadAnswer);
      expect(subject.status).toBe("loading");
      expect(subject.store.tip()).toBe(undefined);
      node.tamper = null;
      await settle(subject);
      expect(subject.served?.number).toBe(1);
    }
  });

  it("never indexes a pre-confirmed or hash-less block", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    const subject = indexer(node);
    node.tamper = (method, params, result) =>
      method === "starknet_getBlockWithTxHashes" && asks(params, 1)
        ? { status: "PRE_CONFIRMED", block_number: 1, transactions: [] }
        : result;
    expect(await subject.step()).toBe(true);
    expect(subject.store.tip()).toBe(undefined);
    expect(subject.chain.calls.starknet_getEvents).toBe(undefined);
  });

  it("keeps a count of rewinds and only the last ones (Opus 9)", async () => {
    const node = new FakeNode();
    history(node, 2);
    const subject = indexer(node);
    await settle(subject);
    for (let i = 0; i < REWINDS_KEPT + 5; i++) {
      node.reorg(1, [[[ev.located(i, 1)]]]);
      await settle(subject);
    }
    expect(subject.rewindCount).toBe(REWINDS_KEPT + 5);
    expect(subject.rewinds).toHaveLength(REWINDS_KEPT);
  });

  it("runs at least one block per step and waits at least 1 ms (Opus 5)", async () => {
    const node = new FakeNode();
    history(node, 3);
    const subject = indexer(node, { batch: 0 });
    await settle(subject);
    expect(subject.served?.number).toBe(3);
    const abort = new AbortController();
    const run = subject.run(0, abort.signal);
    await new Promise((resolve) => setTimeout(resolve, 20));
    abort.abort();
    await run;
    // At least 1 ms between idle polls: far fewer than a spin would make in 20 ms.
    expect(subject.chain.calls.starknet_blockHashAndNumber).toBeLessThan(60);
  });
});
