import { describe, expect, it } from "vitest";
import { Chain } from "./chain.ts";
import { Indexer } from "./indexer.ts";
import { connect } from "node:net";
import { answer, respond, serve } from "./server.ts";
import { Store } from "./store.ts";
import { FakeNode, HUB, MARKET, ev } from "./testing/fake-node.ts";

function indexer(node: FakeNode) {
  return new Indexer({
    chain: new Chain(node.rpc, { hub: HUB, market: MARKET }),
    store: new Store(":memory:"),
    config: { hub: HUB, market: MARKET, from: 1, lotCount: 0n, tradeCount: 0n },
    depth: 100,
  });
}

const ROWS = ["tables", "versions"];

describe("R1 and R2: /head and /stats", () => {
  it("answer 503 `loading`, with no rows and no head, until a block is served", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    const subject = indexer(node);
    for (const path of ["/head", "/stats"]) {
      const { code, body } = answer(subject, path);
      expect(code).toBe(503);
      expect(body).toMatchObject({ status: "loading", head: null });
      for (const key of ROWS) expect(body).not.toHaveProperty(key);
    }
    await subject.step(); // applied, not checked
    expect(answer(subject, "/head").code).toBe(503);
  });

  it("answer 200 `ok` with the served block's number, hash and commitments", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    const subject = indexer(node);
    await subject.step();
    await subject.step();
    const block = node.blocks[1]!;
    const head = {
      number: 1,
      hash: block.hash,
      commitments: [1, 2, 3, 4].map(() => block.commitment).join(","),
      timestamp: block.timestamp,
    };
    expect(answer(subject, "/head")).toEqual({
      code: 200,
      body: { status: "ok", head, behind: 0 },
    });
    const stats = answer(subject, "/stats");
    expect(stats.code).toBe(200);
    expect(stats.body).toMatchObject({
      status: "ok",
      head,
      tables: { lots: 1, events: 1 },
      blocksApplied: 1,
      eventsApplied: 1,
    });
    expect(stats.body.rpcCalls).toMatchObject({
      starknet_blockHashAndNumber: 2,
    });
    node.mine();
    await subject.step();
    expect(answer(subject, "/head").body).toMatchObject({
      head: { number: 1 },
      behind: 1,
    });
  });

  it("answer 503 `rewinding` from the divergence until the fork point is served again", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    node.mine([ev.posted(2)]);
    const subject = indexer(node);
    for (let i = 0; i < 3; i++) await subject.step();
    expect(subject.status).toBe("ok");
    node.reorg(1, [[[ev.posted(2, { price: 3n })]]], true);
    await subject.step();
    const { code, body } = answer(subject, "/stats");
    expect(code).toBe(503);
    expect(body).toMatchObject({ status: "rewinding", head: null });
    expect(body.reason).toMatch(/no longer the node's/);
    for (const key of ROWS) expect(body).not.toHaveProperty(key);
    await subject.step(); // the fork point is checked and served again; block 2' applied
    expect(answer(subject, "/head")).toMatchObject({
      code: 200,
      body: { head: { number: 1 } },
    });
  });

  it("answer 503 `halted` with the reason", async () => {
    const node = new FakeNode();
    node.mine([ev.closed(1, true)]);
    const subject = indexer(node);
    await subject.step().catch((error: Error) => subject.halt(error.message));
    expect(answer(subject, "/head")).toMatchObject({
      code: 503,
      body: { status: "halted", reason: expect.stringMatching(/no such lot/) },
    });
  });

  it("serve them over HTTP, GET only, 404 otherwise", async () => {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    const subject = indexer(node);
    await subject.step();
    await subject.step();
    const server = serve(subject);
    await new Promise<void>((resolve) =>
      server.listen(0, "127.0.0.1", resolve),
    );
    const { port } = server.address() as { port: number };
    try {
      const head = await fetch(`http://127.0.0.1:${port}/head`);
      expect(head.status).toBe(200);
      expect(head.headers.get("content-type")).toBe("application/json");
      expect(await head.json()).toMatchObject({
        status: "ok",
        head: { number: 1 },
      });
      expect((await fetch(`http://127.0.0.1:${port}/nothing`)).status).toBe(
        404,
      );
      expect(
        (await fetch(`http://127.0.0.1:${port}/head`, { method: "POST" }))
          .status,
      ).toBe(405);
    } finally {
      server.close();
    }
  });
});

describe("fix loop 1: nothing a client sends stops the process", () => {
  async function served() {
    const node = new FakeNode();
    node.mine([ev.posted(1)]);
    const subject = indexer(node);
    await subject.step();
    await subject.step();
    return subject;
  }

  it("answers 400 to a target that is not a path, 405 to another method, 404 elsewhere, each with the head (Opus 1, 8)", async () => {
    const subject = await served();
    const head = { number: 1 };
    for (const target of ["//[", "http://indexer/head", "*", "//"]) {
      expect(respond(subject, "GET", target)).toMatchObject({
        code: 400,
        body: { error: "bad request", status: "ok", head },
      });
    }
    expect(respond(subject, "POST", "/head")).toMatchObject({
      code: 405,
      body: { head },
    });
    expect(respond(subject, "GET", "/nothing")).toMatchObject({
      code: 404,
      body: { head },
    });
    expect(respond(subject, "GET", "/head?x=1")).toMatchObject({ code: 200 });
  });

  it("answers 500, with no detail, when answering throws (Opus 1)", async () => {
    const subject = await served();
    subject.store.countsAt = () => {
      throw new Error("disk says no");
    };
    const { code, body } = respond(subject, "GET", "/stats");
    expect(code).toBe(500);
    expect(body).toEqual({
      error: "internal error",
      status: "ok",
      head: expect.objectContaining({ number: 1 }),
    });
  });

  it("keeps serving after `GET //[` on the socket (Opus 1)", async () => {
    const subject = await served();
    const server = serve(subject);
    await new Promise<void>((resolve) =>
      server.listen(0, "127.0.0.1", resolve),
    );
    const { port } = server.address() as { port: number };
    try {
      const raw = await new Promise<string>((resolve, reject) => {
        const socket = connect(port, "127.0.0.1", () =>
          socket.write(
            "GET //[ HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n",
          ),
        );
        let text = "";
        socket.on("data", (chunk) => (text += String(chunk)));
        socket.on("end", () => resolve(text));
        socket.on("error", reject);
      });
      expect(raw).toMatch(/^HTTP\/1\.1 400/);
      const head = await fetch(`http://127.0.0.1:${port}/head`);
      expect(head.status).toBe(200);
    } finally {
      server.close();
    }
  });
});
