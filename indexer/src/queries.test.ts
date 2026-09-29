import { describe, expect, it } from "vitest";
import {
  INVITATION_SECONDS,
  MAX_SIZES,
  MIN_SALES,
  PRICE_WINDOW_SECONDS,
} from "./queries.ts";
import { AnswerCache, answer, respond } from "./server.ts";
import { FakeNode, ev } from "./testing/fake-node.ts";
import { indexerOf, settle } from "./testing/setup.ts";

const EQUIPMENT = 2n ** 40n + 7n * 2n ** 16n + 12n * 2n ** 8n + 3n * 2n + 1n;
const BOSS = 2n ** 41n + 5n;
const hex = (value: bigint | number) => `0x${BigInt(value).toString(16)}`;

/** The answer's body, which must be 200. */
function ok(subject: ReturnType<typeof indexerOf>, target: string) {
  const { code, body } = answer(subject, target);
  expect(body).toMatchObject({ status: "ok" });
  expect(code).toBe(200);
  return body as Record<string, unknown> & { head: { number: number } };
}

/** Lots 1..6: key 7 size 1 at 30, 10, 20, 10; key 7 size 10 at 1; key 8 size 1 at 5. */
async function market() {
  const node = new FakeNode();
  node.mine([
    ev.posted(1, { price: 30n }),
    ev.posted(2, { price: 10n }),
    ev.posted(3, { price: 20n }),
    ev.posted(4, { price: 10n }),
    ev.posted(5, { size: 10, price: 1n }),
    ev.posted(6, { key: 8n, price: 5n }),
  ]);
  const subject = indexerOf(node);
  await settle(subject);
  return { node, subject };
}

describe("Q1: the open lots of a market key and lot size", () => {
  it("cheapest first, ties by lot id, paged by a cursor, with the total", async () => {
    const { subject } = await market();
    const first = ok(subject, "/lots?key=0x7&size=1&limit=2");
    expect(first.total).toBe(4);
    expect((first.lots as { lot: string }[]).map((lot) => lot.lot)).toEqual([
      "2",
      "4",
    ]);
    expect(first.next).toBe("10:4");
    expect((first.lots as unknown[])[0]).toEqual({
      lot: "2",
      key: "0x7",
      size: 1,
      price: "10",
      expiry: "1000",
      equipment: 0,
      modifiers: "0x0",
      posted: 1,
    });
    const second = ok(subject, "/lots?key=0x7&size=1&limit=2&after=10:4");
    expect((second.lots as { lot: string }[]).map((lot) => lot.lot)).toEqual([
      "3",
      "1",
    ]);
    const last = ok(subject, "/lots?key=0x7&size=1&limit=2&after=30:1");
    expect(last).toMatchObject({ lots: [], next: null, total: 4 });
    expect(ok(subject, "/lots?key=0x7&size=10").lots).toHaveLength(1);
  });

  it("are read as of the served block, not the stored tip (R6), and a closed lot leaves", async () => {
    const { node, subject } = await market();
    node.mine([ev.closed(2, true)]);
    await subject.step(); // block 2 applied, not yet checked: block 1 is still served
    expect(subject.store.tip()?.number).toBe(2);
    let body = ok(subject, "/lots?key=0x7&size=1");
    expect(body.head.number).toBe(1);
    expect(body.total).toBe(4);
    await settle(subject);
    body = ok(subject, "/lots?key=0x7&size=1");
    expect(body.head.number).toBe(2);
    expect((body.lots as { lot: string }[]).map((lot) => lot.lot)).toEqual([
      "4",
      "3",
      "1",
    ]);
  });
});

describe("Q2: the market keys of a kind, the cheapest lot per lot size", () => {
  it("groups by key and lot size, filters balances by item ids, pages by key", async () => {
    const { node, subject } = await market();
    node.mine([
      ev.posted(7, { key: EQUIPMENT, price: 900n }),
      ev.posted(8, { key: BOSS, price: 50n }),
    ]);
    await settle(subject);
    const body = ok(subject, "/market?kind=balance");
    expect(body.next).toBe(null);
    expect(body.keys).toEqual([
      {
        key: "0x7",
        decoded: { kind: "balance", item: 7 },
        sizes: [
          {
            size: 1,
            cheapest: expect.objectContaining({ lot: "2", price: "10" }),
          },
          {
            size: 10,
            cheapest: expect.objectContaining({ lot: "5", price: "1" }),
          },
        ],
      },
      {
        key: "0x8",
        decoded: { kind: "balance", item: 8 },
        sizes: [
          {
            size: 1,
            cheapest: expect.objectContaining({ lot: "6" }),
          },
        ],
      },
    ]);
    const paged = ok(subject, "/market?kind=balance&limit=1");
    expect((paged.keys as { key: string }[]).map((key) => key.key)).toEqual([
      "0x7",
    ]);
    expect(paged.next).toBe("0x7");
    expect(
      (
        ok(subject, "/market?kind=balance&limit=1&after=0x7").keys as {
          key: string;
        }[]
      ).map((key) => key.key),
    ).toEqual(["0x8"]);
    expect(
      (
        ok(subject, "/market?kind=balance&items=8,99").keys as {
          key: string;
        }[]
      ).map((key) => key.key),
    ).toEqual(["0x8"]);
    expect(ok(subject, "/market?kind=equipment").keys).toEqual([
      {
        key: hex(EQUIPMENT),
        decoded: {
          kind: "equipment",
          base: 7,
          requirement: 12,
          rarity: 3,
          identified: true,
        },
        sizes: [
          {
            size: 1,
            cheapest: expect.objectContaining({ lot: "7" }),
          },
        ],
      },
    ]);
    expect(ok(subject, "/market?kind=boss").keys).toMatchObject([
      { key: hex(BOSS), decoded: { kind: "boss", base: 5 } },
    ]);
  });
});

describe("Q3: the mean price of the last 7 days' sales, by block time", () => {
  it("counts the sales in (T - 7 days, T], hides the mean under 5 sales, ignores the lots not sold", async () => {
    const node = new FakeNode();
    const posts = [100n, 200n, 300n, 400n, 500n, 600n, 700n].map((price, i) =>
      ev.posted(i + 1, { key: 9n, price }),
    );
    node.time = 1000;
    node.mine(posts);
    const subject = indexerOf(node);
    const at = async (
      time: number,
      ...events: ReturnType<typeof ev.closed>[]
    ) => {
      node.time = time;
      node.mine(events);
      await settle(subject);
      const body = ok(subject, "/prices?key=0x9&size=1");
      expect(body.head).toMatchObject({ timestamp: time });
      return body;
    };
    const T = 10_000 + PRICE_WINDOW_SECONDS;
    await at(10_000, ev.closed(1, true)); // exactly 7 days before T: out of the window at T
    await at(10_001, ev.closed(2, true));
    await at(10_002, ev.closed(3, true), ev.closed(4, false)); // 4 withdrawn: not a sale
    expect(await at(10_003, ev.closed(5, true))).toMatchObject({ sales: 4 });
    // At T: 200, 300, 500 and 600; 100 (at T - 7 days) is out: 4 sales, no mean.
    const four = await at(T, ev.closed(6, true));
    expect(four).toMatchObject({
      sales: MIN_SALES - 1,
      window: { after: 10_000, until: T },
    });
    expect(four).not.toHaveProperty("mean");
    // A fifth sale at T: the mean is (200 + 300 + 500 + 600 + 700) / 5.
    expect(await at(T, ev.closed(7, true))).toMatchObject({
      sales: 5,
      mean: "460",
    });
    // One second later, the sale at 10 001 is exactly 7 days old: out again, no mean.
    const later = await at(T + 1);
    expect(later).toMatchObject({ sales: 4 });
    expect(later).not.toHaveProperty("mean");
  });

  it("gives the floor of the mean, u64 prices included", async () => {
    const node = new FakeNode();
    const max = 2n ** 64n - 1n;
    node.mine(
      [1, 2, 3, 4, 5].map((lot) =>
        ev.posted(lot, { price: lot === 5 ? 2n : max }),
      ),
    );
    node.mine([1, 2, 3, 4, 5].map((lot) => ev.closed(lot, true)));
    const subject = indexerOf(node);
    await settle(subject);
    expect(ok(subject, "/prices?key=0x7&size=1")).toMatchObject({
      sales: 5,
      mean: ((max * 4n + 2n) / 5n).toString(),
    });
  });
});

describe("Q4 and Q5: presence in a hub, displayed titles", () => {
  it("lists the adventurers of a hub by id, with the count, paged", async () => {
    const node = new FakeNode();
    node.mine([ev.located(3, 9), ev.located(3, 4), ev.located(3, 7)]);
    node.mine([ev.located(0, 7), ev.located(5, 9), ev.located(3, 9)]);
    const subject = indexerOf(node);
    await settle(subject);
    expect(ok(subject, "/hubs/presence?hub=3")).toMatchObject({
      hub: 3,
      count: 2,
      adventurers: [4, 9],
      next: null,
    });
    expect(ok(subject, "/hubs/presence?hub=3&limit=1")).toMatchObject({
      adventurers: [4],
      next: "4",
    });
    expect(ok(subject, "/hubs/presence?hub=3&limit=1&after=4")).toMatchObject({
      adventurers: [9],
    });
    expect(ok(subject, "/hubs/presence?hub=5")).toMatchObject({ count: 0 });
  });

  it("gives the last displayed title of each adventurer asked, null for none", async () => {
    const node = new FakeNode();
    node.mine([ev.title(9, 5, 2)]);
    node.mine([ev.title(9, 6, 3)]);
    const subject = indexerOf(node);
    await settle(subject);
    expect(ok(subject, "/titles?adventurers=9,4").titles).toEqual([
      { adventurer: 9, title: 6, tier: 3 },
      { adventurer: 4, title: null },
    ]);
  });
});

describe("Q7: the open invitations of an account, under 10 minutes of block time", () => {
  it("shows an invitation while T - opened < 600, and never a closed one", async () => {
    const node = new FakeNode();
    node.time = 5000;
    node.mine([ev.opened(1, 12, 9), ev.opened(2, 13, 9), ev.opened(3, 12, 8)]);
    const subject = indexerOf(node);
    await settle(subject);
    const at = async (
      time: number,
      ...events: ReturnType<typeof ev.opened>[]
    ) => {
      node.time = time;
      node.mine(events);
      await settle(subject);
      return ok(subject, "/invitations?account=12");
    };
    expect(await at(5001, ev.tradeClosed(3, 1))).toMatchObject({
      account: 12,
      total: 1,
      invitations: [
        {
          trade: "1",
          invited: 12,
          inviter: 9,
          opened: 1,
          openedTime: 5000,
          expiresAt: 5000 + INVITATION_SECONDS,
        },
      ],
    });
    expect(await at(5000 + INVITATION_SECONDS - 1)).toMatchObject({ total: 1 });
    expect(await at(5000 + INVITATION_SECONDS)).toMatchObject({
      total: 0,
      invitations: [],
    });
  });
});

describe("R1, R2 and the parameters", () => {
  const QUERIES = [
    "/lots?key=0x7&size=1",
    "/market?kind=balance",
    "/prices?key=0x7&size=1",
    "/hubs/presence?hub=3",
    "/titles?adventurers=9",
    "/invitations?account=12",
  ];

  it("every query answers 503 with the state and the head, and no rows, in loading, rewinding and halted", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    node.mine([ev.posted(2)]);
    const subject = indexerOf(node);
    const refused = (status: string) => {
      for (const target of QUERIES) {
        const { code, body } = answer(subject, target);
        expect(code).toBe(503);
        expect(body).toMatchObject({ status });
        expect(body).toHaveProperty("head");
        for (const key of ["lots", "keys", "sales", "adventurers", "titles"])
          expect(body).not.toHaveProperty(key);
      }
    };
    refused("loading");
    await settle(subject);
    for (const target of QUERIES)
      expect(answer(subject, target).body.head).toMatchObject({ number: 2 });
    node.reorg(1, [[[ev.posted(2, { price: 3n })]]], true);
    await subject.step();
    expect(subject.status).toBe("rewinding");
    refused("rewinding");
    subject.halt("a test");
    refused("halted");
    expect(answer(subject, QUERIES[0]!).body.reason).toBe("a test");
  });

  it("refuses a bad parameter with 400 and the head, an unknown route with 404", async () => {
    const { subject } = await market();
    const bad = [
      "/lots?size=1",
      "/lots?key=7&size=1",
      "/lots?key=0x7&size=0",
      "/lots?key=0x7&size=256",
      "/lots?key=0x7&size=1&limit=101",
      "/lots?key=0x7&size=1&limit=0",
      "/lots?key=0x7&size=1&after=10",
      "/lots?key=0x7&size=1&after=18446744073709551616:1",
      "/lots?key=0x7&size=1&size=1",
      "/lots?key=0x7&size=1&extra=1",
      "/lots?key=0x100000000&size=1", // no ENG-01 encoding
      "/lots?key=0x7;DROP TABLE lots&size=1",
      "/market?kind=weapons",
      "/market?kind=equipment&items=1",
      `/market?kind=balance&items=${Array.from({ length: 101 }, (_, i) => i).join(",")}`,
      "/market?kind=balance&items=1,1",
      "/prices?key=0x7",
      "/hubs/presence?hub=0",
      "/hubs/presence?hub=65536",
      "/hubs/presence?hub=-1",
      "/titles?adventurers=",
      "/titles?adventurers=4294967296",
      "/invitations?account=1.5",
      "/invitations?account=01",
    ];
    for (const target of bad) {
      const { code, body } = answer(subject, target);
      expect([target, code]).toEqual([target, 400]);
      expect(body).toMatchObject({
        status: "error",
        state: "ok",
        head: { number: 1 },
      });
    }
    expect(respond(subject, "GET", "/lotss?key=0x7")).toMatchObject({
      code: 404,
      body: { head: { number: 1 } },
    });
    expect(answer(subject, "/lots?key=0x7&size=1").code).toBe(200); // still serving
  });
});

describe("R6: answers kept for the served block, by hash and commitments", () => {
  it("serves a kept answer at the same block, reads again at the next, and forgets on a rewind", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    node.mine([ev.posted(2, { price: 5n })]);
    const subject = indexerOf(node);
    await settle(subject);
    const first = answer(subject, "/lots?key=0x7&size=1").body;
    const again = answer(subject, "/lots?key=0x7&size=1").body;
    expect(again.lots).toBe(first.lots); // the same rows: kept
    expect(
      (answer(subject, "/stats").body.answerCache as { hits: number }).hits,
    ).toBe(1);
    // Block 2 replaced under the same hash (devnet), without lot 2: other commitments.
    node.reorg(1, [[]], true);
    await settle(subject);
    const after = answer(subject, "/lots?key=0x7&size=1").body as {
      head: { number: number; hash: string };
      lots: { lot: string }[];
    };
    expect(after.head.number).toBe(2);
    expect(after.head.hash).toBe((first.head as { hash: string }).hash);
    expect(after.lots.map((lot) => lot.lot)).toEqual(["1"]);
  });
});

describe("fix loop 1: R6's rewind clear, Q2's bound, the cache's bytes", () => {
  it("R6: a block served again with the same hash AND commitments after a rewind is read again (the rewind's clear is the only defence)", async () => {
    // Blocks 5 and 6 are empty; block 4 is replaced (lot 4 at 44 instead of 40) under replacement
    // blocks 5' and 6' that keep the hashes and the commitments of 5 and 6, as devnet's empty blocks
    // do. The served block is 6 before and after: only the rewind, found by the ancestors' check,
    // tells the cache its answers are void.
    const node = new FakeNode();
    for (let lot = 1; lot <= 4; lot++)
      node.mine([ev.posted(lot, { price: BigInt(10 * lot) })]);
    node.mine();
    node.mine();
    const subject = indexerOf(node, 1000, { depth: 10, everyMs: 0 });
    await settle(subject);
    const before = ok(subject, "/lots?key=0x7&size=1&limit=100");
    expect(before.head.number).toBe(6);
    const prices = (body: Record<string, unknown>) =>
      (body.lots as { lot: string; price: string }[]).map(
        (lot) => `${lot.lot}@${lot.price}`,
      );
    expect(prices(before)).toContain("4@40");
    const old = node.blocks.slice(4, 7).map((block) => block.commitment);
    node.reorg(3, [[[ev.posted(4, { price: 44n })]], [], []], true);
    node.blocks[5]!.commitment = old[1]!;
    node.blocks[6]!.commitment = old[2]!;
    await settle(subject);
    expect(subject.rewindCount).toBe(1);
    const after = ok(subject, "/lots?key=0x7&size=1&limit=100");
    // The same block 6 (hash and commitments) is served...
    expect(after.head).toMatchObject({
      number: 6,
      hash: (before.head as unknown as { hash: string }).hash,
      commitments: (before.head as unknown as { commitments: string })
        .commitments,
    });
    // ...and the answer is the replacement's, not the one kept before the rewind.
    expect(prices(after)).toContain("4@44");
    expect(prices(after)).not.toContain("4@40");
  });

  it("Q2 reads at most MAX_SIZES lot sizes per key, and says so", async () => {
    const node = new FakeNode();
    node.mine(
      Array.from({ length: MAX_SIZES + 1 }, (_, i) =>
        ev.posted(i + 1, { size: i + 1, price: BigInt(100 - i) }),
      ),
    );
    const subject = indexerOf(node);
    await settle(subject);
    const [key] = ok(subject, "/market?kind=balance").keys as {
      sizes: { size: number }[];
      truncated?: boolean;
    }[];
    expect(key!.sizes.map((size) => size.size)).toEqual(
      Array.from({ length: MAX_SIZES }, (_, i) => i + 1),
    );
    expect(key!.truncated).toBe(true);
  });

  it("the answer cache is bounded in bytes: the oldest go first, and an answer too large is not kept", async () => {
    const node = new FakeNode();
    node.mine(Array.from({ length: 30 }, (_, i) => ev.posted(i + 1)));
    const subject = indexerOf(node);
    await settle(subject);
    const served = subject.served!;
    const cache = new AnswerCache(subject, 1000, 600);
    const read = (limit: number) => () => ({
      rows: "x".repeat(limit),
    });
    for (let i = 0; i < 10; i++) cache.read(served, `/a${i}`, read(250));
    expect(cache.bytes).toBeLessThanOrEqual(1000);
    cache.read(served, "/a9", read(250));
    expect(cache.hits).toBe(1); // the newest is kept
    cache.read(served, "/a0", read(250));
    expect(cache.misses).toBe(11); // the oldest was forgotten
    cache.read(served, "/big", read(700));
    cache.read(served, "/big", read(700));
    expect(cache.misses).toBe(13); // over MAX_ENTRY: read each time, never kept
    expect(cache.bytes).toBeLessThanOrEqual(1000);
  });
});
