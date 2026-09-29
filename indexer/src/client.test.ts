// The client library (src/client/), under Node: R3 in its order, the caches under R4, and what it
// may import. The same library against the indexer on the local node: test-node/scenario.node.test.ts.
import { readdirSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  IndexerClient,
  LotCache,
  PresenceCache,
  StreamCache,
  type Frame,
  type Head,
  type NodeReader,
} from "./client/index.ts";
import { serve } from "./server.ts";
import { FakeNode, ev } from "./testing/fake-node.ts";
import { indexerOf, nodeFetch, settle } from "./testing/setup.ts";

const HEAD: Head = {
  number: 10,
  hash: "0xb10",
  commitments: "0x1,0x2,0x3,0x4",
  timestamp: 1,
};

/** A node reader that logs its reads in `log`, beside the indexer's answers. */
function reader(
  log: string[],
  tip: number,
  block: { hash: string; commitments: string } | null = HEAD,
): NodeReader {
  return {
    tip: async () => {
      log.push("tip");
      return tip;
    },
    block: async (number) => {
      log.push(`block ${number}`);
      return block;
    },
  };
}

/** A `fetch` for the indexer's side that answers `body` with `code`, and logs it. */
function indexerFetch(
  log: string[],
  code: number,
  body: unknown,
): typeof fetch {
  return (async () => {
    log.push("indexer");
    return new Response(JSON.stringify(body), { status: code });
  }) as typeof fetch;
}

const okBody = { status: "ok", head: HEAD, behind: 0, total: 0, lots: [] };

describe("R3: the indexer's answer, then the node's tip, then the node's block, last", () => {
  it("accepts an answer whose head is the node's, reading in that order", async () => {
    const log: string[] = [];
    const client = new IndexerClient({
      url: "http://indexer",
      node: reader(log, 15),
      fetch: indexerFetch(log, 200, okBody),
    });
    const checked = await client.lots("0x7", 1);
    expect(checked).toEqual({ fresh: true, answer: okBody });
    expect(log).toEqual(["indexer", "tip", "block 10"]);
  });

  it("refuses a head more than maxLag (5) blocks below the tip, without reading its block", async () => {
    const log: string[] = [];
    const client = new IndexerClient({
      url: "http://indexer",
      node: reader(log, 16),
      fetch: indexerFetch(log, 200, okBody),
    });
    expect(await client.lots("0x7", 1)).toEqual({
      fresh: false,
      reason: "indexer 6 blocks behind the node",
    });
    expect(log).toEqual(["indexer", "tip"]);
  });

  it("refuses a head whose block the node no longer has, or has replaced (hash or commitments)", async () => {
    for (const [block, reason] of [
      [null, "block 10 is not the node's"],
      [{ ...HEAD, hash: "0xb11" }, "block 10 was replaced"],
      [{ ...HEAD, commitments: "0x1,0x2,0x3,0x5" }, "block 10 was replaced"],
    ] as const) {
      const log: string[] = [];
      const client = new IndexerClient({
        url: "http://indexer",
        node: reader(log, 10, block),
        fetch: indexerFetch(log, 200, okBody),
      });
      expect(await client.presence(3)).toEqual({ fresh: false, reason });
    }
    // The same hash written with leading zeros is the same block.
    const client = new IndexerClient({
      url: "http://indexer",
      node: reader([], 10, { ...HEAD, hash: "0x0000b10" }),
      fetch: indexerFetch([], 200, okBody),
    });
    expect((await client.titles([1])).fresh).toBe(true);
  });

  it("sees a block aborted between its two node reads (the tip first, the block last)", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    const subject = indexerOf(node);
    await settle(subject);
    const client = new IndexerClient({
      url: "http://indexer",
      node: "http://node",
      fetch: nodeFetch(node),
    });
    const head = { ...subject.served!, parent: undefined };
    expect(await client.verify(head)).toBe(null);
    expect(
      await client.verify(head, async () => {
        node.reorg(1, [[[ev.posted(1, { price: 2n })]]], true);
      }),
    ).toBe("block 1 was replaced");
  });

  it("refuses a 503 without reading the node, and throws on a 400 (a bug of the caller)", async () => {
    const log: string[] = [];
    const client = new IndexerClient({
      url: "http://indexer",
      node: reader(log, 10),
      fetch: indexerFetch(log, 503, { status: "rewinding", head: null }),
    });
    expect(await client.invitations(12)).toEqual({
      fresh: false,
      reason: "indexer rewinding",
    });
    expect(log).toEqual(["indexer"]);
    const bad = new IndexerClient({
      url: "http://indexer",
      node: reader([], 10),
      fetch: indexerFetch([], 400, { error: "size must be from 1 to 255" }),
    });
    await expect(bad.lots("0x7", 0)).rejects.toThrow(/size must be/);
  });
});

describe("R4: a cache is ready only after a complete snapshot, and read() applies R3", () => {
  const client = new IndexerClient({
    url: "http://indexer",
    node: reader([], 10),
  });
  const begin = (total: number, head = HEAD): Frame => ({
    event: "reset-begin",
    data: { head, total },
  });
  const end = (total: number, head = HEAD): Frame => ({
    event: "reset-end",
    data: { head, total },
  });
  const page = (...adventurers: number[]): Frame => ({
    event: "reset-page",
    data: { rows: adventurers.map((adventurer) => ({ adventurer })) },
  });

  it("is ready at a reset-end whose total the rows count, not before, not otherwise", async () => {
    const cache = new PresenceCache(client, 3);
    expect(await cache.read()).toEqual({
      fresh: false,
      reason: "cache disconnected",
    });
    cache.receive(begin(3));
    cache.receive(page(1, 2));
    expect(cache.ready).toBe(false);
    cache.receive(end(3)); // 2 rows for 3 announced
    expect(cache.ready).toBe(false);
    expect(cache.status).toBe("incomplete snapshot");
    cache.receive(page(3)); // a page outside a snapshot: ignored
    cache.receive(begin(3));
    cache.receive(page(1, 2));
    cache.receive(page(3));
    cache.receive(end(3));
    expect(cache.ready).toBe(true);
    const read = await cache.read();
    expect(read).toEqual({
      fresh: true,
      answer: {
        head: HEAD,
        rows: [{ adventurer: 1 }, { adventurer: 2 }, { adventurer: 3 }],
      },
    });
  });

  it("a rewind in the middle of a snapshot: the partial one is dropped, only the next complete one counts", () => {
    const cache = new PresenceCache(client, 3);
    cache.receive(begin(3));
    cache.receive(page(1, 2));
    cache.receive({ event: "rewind", data: { to: 8 } });
    cache.receive(page(3)); // the rest of the dropped snapshot, if any: ignored
    cache.receive(end(3));
    expect(cache.ready).toBe(false);
    const head = { ...HEAD, number: 8, hash: "0xb8" };
    cache.receive(begin(1, head));
    cache.receive(page(7));
    cache.receive(end(1, head));
    expect(cache.ready).toBe(true);
    expect(cache.head).toEqual(head);
    expect(cache.size()).toBe(1);
  });

  it("applies a block's changes together with its head; a status makes it not ready", async () => {
    const cache = new PresenceCache(client, 3);
    cache.receive(begin(1));
    cache.receive(page(1));
    cache.receive(end(1));
    cache.receive({ event: "add", data: { row: { adventurer: 2 } } });
    cache.receive({ event: "remove", data: { id: "1" } });
    expect(cache.size()).toBe(1); // held until the head
    const next = { ...HEAD, number: 11, hash: "0xb11" };
    cache.receive({ event: "head", data: { head: next } });
    expect(cache.head).toEqual(next);
    expect(cache.size()).toBe(1);
    const read = await cache.read(); // the node's block 11 is not HEAD's: refused
    expect(read).toEqual({ fresh: false, reason: "block 11 was replaced" });
    cache.receive({ event: "status", data: { status: "halted" } });
    expect(cache.ready).toBe(false);
    expect(await cache.read()).toEqual({
      fresh: false,
      reason: "cache halted",
    });
  });
});

describe("the client library against a running indexer (fake node)", () => {
  it("queries, subscribes, follows the blocks, and is not ready once its stream ends", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1, { price: 5n }), ev.posted(2, { price: 3n })]);
    const subject = indexerOf(node);
    await settle(subject);
    const server = serve(subject);
    await new Promise<void>((resolve) =>
      server.listen(0, "127.0.0.1", resolve),
    );
    const { port } = server.address() as { port: number };
    const client = new IndexerClient({
      url: `http://127.0.0.1:${port}`,
      node: "http://node",
      fetch: ((input: Parameters<typeof fetch>[0], init?: RequestInit) =>
        String(input).startsWith("http://node")
          ? nodeFetch(node)(input, init)
          : fetch(input, init)) as typeof fetch,
    });
    try {
      const lots = await client.lots(7n, 1);
      expect(lots.fresh).toBe(true);
      if (lots.fresh)
        expect(lots.answer.lots.map((lot) => lot.lot)).toEqual(["2", "1"]);
      const cache = new LotCache(client, 7n, 1);
      const ends: (Error | null)[] = [];
      const close = cache.connect(undefined, (error) => ends.push(error));
      while (!cache.ready) await new Promise((r) => setTimeout(r, 5));
      node.mine([ev.posted(3, { price: 1n })]);
      await settle(subject);
      while (cache.head?.number !== 2)
        await new Promise((r) => setTimeout(r, 5));
      const read = await cache.read();
      expect(read.fresh).toBe(true);
      if (read.fresh)
        expect(read.answer.rows.map((lot) => lot.lot)).toEqual(["3", "2", "1"]);
      // Five more blocks the indexer does not follow: the node's tip is 6 blocks ahead.
      for (let i = 0; i < 6; i++) node.mine();
      expect(await cache.read()).toEqual({
        fresh: false,
        reason: "indexer 6 blocks behind the node",
      });
      // The server ends every stream: the cache is not ready, by itself.
      server.subscriptions.close();
      while (cache.status !== "disconnected")
        await new Promise((r) => setTimeout(r, 5));
      expect(cache.ready).toBe(false);
      expect(ends).toHaveLength(1);
      await close();
    } finally {
      server.close();
      server.closeAllConnections();
    }
  });

  it("a subscription over the caps fails to open, and the cache stays not ready", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    const subject = indexerOf(node);
    await settle(subject);
    const server = serve(subject, { limits: { perProcess: 0 } });
    await new Promise<void>((resolve) =>
      server.listen(0, "127.0.0.1", resolve),
    );
    const { port } = server.address() as { port: number };
    try {
      const client = new IndexerClient({
        url: `http://127.0.0.1:${port}`,
        node: reader([], 1),
      });
      const cache = new StreamCache(
        client,
        "/subscribe/presence",
        { hub: 3 },
        (row: { adventurer: number }) => String(row.adventurer),
        (a, b) => a.adventurer - b.adventurer,
      );
      const ended = new Promise<Error | null>((resolve) =>
        cache.connect(undefined, resolve),
      );
      expect(String(await ended)).toMatch(/429 too many subscriptions/);
      expect(cache.ready).toBe(false);
    } finally {
      server.close();
      server.closeAllConnections();
    }
  });
});

describe("AC-4: the library runs in a browser and holds no key", () => {
  it("imports no `node:` module and nothing outside its folder; knows no account or key", () => {
    const folder = new URL("./client/", import.meta.url);
    const files = readdirSync(folder).filter((file) => file.endsWith(".ts"));
    expect(files.length).toBeGreaterThan(3);
    for (const file of files) {
      const text = readFileSync(new URL(file, folder), "utf8");
      const imports = [...text.matchAll(/from\s+"([^"]+)"/g)].map(
        (match) => match[1]!,
      );
      for (const source of imports) expect(source).toMatch(/^\.\/[\w-]+\.ts$/);
      expect(text).not.toMatch(
        /["']node:|import\(|require\(|\bprocess\.|\bBuffer\b/,
      );
      expect(text).not.toMatch(/private_?key|signer|starknet_add/i);
      expect(text).not.toMatch(/\bAccount\b/); // starknet.js's sending account
    }
  });
});
