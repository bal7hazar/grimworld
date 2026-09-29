import { connect } from "node:net";
import { describe, expect, it } from "vitest";
import {
  IndexerClient,
  LotCache,
  parseFrame,
  type Frame,
  type Lot,
} from "./client/index.ts";
import { answer, serve } from "./server.ts";
import { Subscriptions, type Sink, type Topic } from "./subscriptions.ts";
import { FakeNode, ev } from "./testing/fake-node.ts";
import { indexerOf, nodeFetch, settle } from "./testing/setup.ts";

/** A sink that keeps the frames; `unsent` plays the bytes a socket did not send yet. */
class Collect implements Sink {
  chunks: string[] = [];
  unsent = 0;
  destroyed = false;
  private read = 0;
  onWrite: ((frame: Frame) => void) | null = null;
  write(chunk: string) {
    this.chunks.push(chunk);
    this.onWrite?.(parseFrame(chunk)!);
  }
  buffered() {
    return this.unsent;
  }
  destroy() {
    this.destroyed = true;
  }
  /** The frames written since the last call. */
  take(): Frame[] {
    const frames = this.chunks
      .slice(this.read)
      .map((chunk) => parseFrame(chunk)!);
    this.read = this.chunks.length;
    return frames;
  }
}

const events = (frames: Frame[]) => frames.map((frame) => frame.event);
const LOTS: Topic = { kind: "lots", key: 7n, size: 1 };

function setup(limits = {}) {
  const node = new FakeNode();
  const subject = indexerOf(node);
  const hub = new Subscriptions(subject, limits);
  const client = new IndexerClient({
    url: "http://indexer.invalid",
    node: "http://node.invalid",
    fetch: nodeFetch(node),
  });
  return { node, subject, hub, client };
}

/** Q1's lots at the served block, all of them. */
function lotsNow(subject: ReturnType<typeof indexerOf>): Lot[] {
  return answer(subject, "/lots?key=0x7&size=1&limit=100").body.lots as Lot[];
}

describe("R4 on the server: snapshot, then the changes of each served block", () => {
  it("sends the state until a block is served, then a snapshot, then per-block changes; nothing from an unserved block", async () => {
    const { node, subject, hub, client } = setup({ page: 2 });
    node.mine([ev.posted(1, { price: 30n }), ev.posted(2, { price: 10n })]);
    node.mine([ev.posted(3, { price: 20n }), ev.posted(4, { key: 8n })]);
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    expect(sink.take()).toEqual([
      { event: "status", data: { status: "loading" } },
    ]);
    await settle(subject);
    const snapshot = sink.take();
    expect(events(snapshot)).toEqual([
      "reset-begin",
      "reset-page",
      "reset-page",
      "reset-end",
    ]);
    expect(snapshot[0]!.data).toMatchObject({ head: { number: 2 }, total: 3 });
    expect(
      snapshot
        .filter((frame) => frame.event === "reset-page")
        .flatMap((frame) => (frame.data as { rows: Lot[] }).rows)
        .map((lot) => lot.lot),
    ).toEqual(["2", "3", "1"]);

    const cache = new LotCache(client, "0x7", 1);
    for (const frame of snapshot) cache.receive(frame);
    expect(cache.ready).toBe(true);

    node.mine([ev.posted(5, { price: 1n }), ev.closed(2, true)]);
    await subject.step(); // applied, not served
    expect(sink.take()).toEqual([]);
    await settle(subject);
    const changes = sink.take();
    expect(changes).toEqual([
      { event: "remove", data: { id: "2" } },
      {
        event: "add",
        data: { row: expect.objectContaining({ lot: "5", price: "1" }) },
      },
      {
        event: "head",
        data: { head: expect.objectContaining({ number: 3 }) },
      },
    ]);
    for (const frame of changes) cache.receive(frame);
    const read = await cache.read();
    expect(read).toMatchObject({ fresh: true });
    if (read.fresh) {
      expect(read.answer.head.number).toBe(3);
      expect(read.answer.rows).toEqual(lotsNow(subject));
    }
  });

  it("publishes several newly served blocks one by one, in block order, each with its head", async () => {
    const { node, subject, hub } = setup();
    node.mine([ev.posted(1)]);
    await settle(subject);
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    sink.take();
    node.mine([ev.posted(2)]);
    node.mine([ev.posted(3, { key: 8n })]); // another key: only a head at the end
    node.mine([ev.closed(1, false), ev.posted(4), ev.closed(4, true)]); // 4 opened and closed in one block: nothing
    node.mine();
    await subject.step(); // applies 2..5
    expect(sink.take()).toEqual([]);
    await subject.step(); // checks and serves 5
    expect(
      sink
        .take()
        .map((frame) =>
          frame.event === "head"
            ? `head ${frame.data.head.number}`
            : frame.event === "add"
              ? `add ${(frame.data.row as Lot).lot}`
              : `${frame.event} ${JSON.stringify(frame.data)}`,
        ),
    ).toEqual(["add 2", "head 2", 'remove {"id":"1"}', "head 4", "head 5"]);
  });

  it("after a rewind: the state, the rewind, then a new snapshot of the replacement", async () => {
    const { node, subject, hub, client } = setup();
    node.mine([ev.posted(1)]);
    node.mine([ev.posted(2, { price: 5n })]);
    await settle(subject);
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    const cache = new LotCache(client, "0x7", 1);
    for (const frame of sink.take()) cache.receive(frame);
    expect(cache.size()).toBe(2);
    node.reorg(1, [[[ev.posted(2, { price: 9n })]], []], true);
    await settle(subject);
    const frames = sink.take();
    // The snapshot is at the fork point, the first block served again; the replacement blocks
    // follow as changes.
    expect(events(frames)).toEqual([
      "status",
      "rewind",
      "reset-begin",
      "reset-page",
      "reset-end",
      "add",
      "head",
      "head",
    ]);
    expect(frames[0]!.data).toMatchObject({ status: "rewinding" });
    expect(frames[1]!.data).toEqual({ to: 1 });
    expect(frames[2]!.data).toMatchObject({ head: { number: 1 }, total: 1 });
    for (const frame of frames) cache.receive(frame);
    const read = await cache.read();
    expect(read.fresh).toBe(true);
    if (read.fresh) {
      expect(read.answer.head.number).toBe(3);
      expect(read.answer.rows.map((lot) => [lot.lot, lot.price])).toEqual([
        ["2", "9"],
        ["1", "100"],
      ]);
    }
  });

  it("a rewind in the middle of a snapshot: the snapshot is whole at its head, then the rewind and a new one", async () => {
    const { node, subject, hub, client } = setup({ page: 2 });
    node.mine(
      [1, 2, 3, 4, 5].map((lot) => ev.posted(lot, { price: BigInt(lot) })),
    );
    node.mine([ev.posted(6, { price: 6n })]);
    await settle(subject);
    const sink = new Collect();
    let reorged = false;
    // At the first page, the node drops block 2 for a block without lot 6: the snapshot being
    // written must still be whole and at block 2 (written in one run).
    sink.onWrite = (frame) => {
      if (frame.event === "reset-page" && !reorged) {
        reorged = true;
        node.reorg(1, [[[ev.posted(6, { price: 60n })]]], true);
      }
    };
    hub.open(LOTS, sink, "a");
    const first = sink.take();
    expect(reorged).toBe(true);
    expect(events(first)).toEqual([
      "reset-begin",
      "reset-page",
      "reset-page",
      "reset-page",
      "reset-end",
    ]);
    expect(first[0]!.data).toEqual(first[4]!.data);
    const cache = new LotCache(client, "0x7", 1);
    for (const frame of first) cache.receive(frame);
    expect(cache.ready).toBe(true);
    // The head it holds is no longer the node's (same hash, other commitments): R3 refuses it.
    expect(await cache.read()).toEqual({
      fresh: false,
      reason: "block 2 was replaced",
    });
    await settle(subject);
    const second = sink.take();
    expect(events(second).slice(0, 2)).toEqual(["status", "rewind"]);
    expect(events(second).slice(2)).toEqual([
      "reset-begin",
      "reset-page",
      "reset-page",
      "reset-page",
      "reset-end",
      "add",
      "head",
    ]);
    expect(second[2]!.data).toMatchObject({ head: { number: 1 }, total: 5 });
    for (const frame of second) cache.receive(frame);
    const read = await cache.read();
    expect(read.fresh).toBe(true);
    if (read.fresh) {
      expect(read.answer.rows.find((lot) => lot.lot === "6")?.price).toBe("60");
      expect(read.answer.rows).toEqual(lotsNow(subject));
    }
  });
});

describe("the presence and invitation subscriptions", () => {
  it("presence: who entered and who left the hub, per block", async () => {
    const { node, subject, hub } = setup();
    node.mine([ev.located(3, 9), ev.located(3, 4)]);
    await settle(subject);
    const sink = new Collect();
    hub.open({ kind: "presence", hub: 3 }, sink, "a");
    expect(sink.take()[1]).toEqual({
      event: "reset-page",
      data: { rows: [{ adventurer: 4 }, { adventurer: 9 }] },
    });
    node.mine([ev.located(0, 4), ev.located(3, 7), ev.located(5, 8)]);
    await settle(subject);
    expect(sink.take()).toEqual([
      { event: "remove", data: { id: "4" } },
      { event: "add", data: { row: { adventurer: 7 } } },
      {
        event: "head",
        data: { head: expect.objectContaining({ number: 2 }) },
      },
    ]);
  });

  it("invitations: filtered on the account; one goes away by block time alone, 10 minutes after its block", async () => {
    const { node, subject, hub } = setup();
    node.time = 5000;
    node.mine([ev.opened(1, 12, 9), ev.opened(2, 13, 9)]);
    await settle(subject);
    const sink = new Collect();
    hub.open({ kind: "invitations", account: 12 }, sink, "a");
    const snapshot = sink.take();
    expect(snapshot[0]!.data).toMatchObject({ total: 1 });
    expect(snapshot[1]!.data).toEqual({
      rows: [
        {
          trade: "1",
          invited: 12,
          inviter: 9,
          opened: 1,
          openedTime: 5000,
          expiresAt: 5600,
        },
      ],
    });
    node.time = 5100;
    node.mine([ev.opened(3, 12, 7), ev.opened(4, 14, 7)]);
    await settle(subject);
    expect(events(sink.take())).toEqual(["add", "head"]);
    node.time = 5599;
    node.mine(); // 599 s: still shown
    await settle(subject);
    expect(events(sink.take())).toEqual(["head"]);
    node.time = 5600;
    node.mine(); // no event: trade 1 is 600 s old
    await settle(subject);
    expect(sink.take()).toEqual([
      { event: "remove", data: { id: "1" } },
      {
        event: "head",
        data: { head: expect.objectContaining({ number: 4, timestamp: 5600 }) },
      },
    ]);
    node.time = 5601;
    node.mine([ev.tradeClosed(3, 1)]); // declined
    await settle(subject);
    expect(sink.take()[0]).toEqual({ event: "remove", data: { id: "3" } });
  });
});

describe("AC-5: bounded", () => {
  it("caps the subscriptions per process and per client", () => {
    const { hub } = setup({ perProcess: 3, perClient: 2 });
    expect(hub.refusal("a")).toBe(null);
    hub.open(LOTS, new Collect(), "a");
    const close = hub.open(LOTS, new Collect(), "a");
    expect(hub.refusal("a")).toBe("too many subscriptions from this client");
    expect(hub.refusal("b")).toBe(null);
    hub.open(LOTS, new Collect(), "b");
    expect(hub.refusal("c")).toBe("too many subscriptions");
    close();
    expect(hub.refusal("c")).toBe(null);
    expect(hub.size).toBe(2);
  });

  it("drops a subscriber whose unsent output is still above the cap at the next block, not one that reads", async () => {
    const { node, subject, hub } = setup({ maxBuffered: 100 });
    node.mine([ev.posted(1)]);
    await settle(subject);
    const reader = new Collect();
    const stopped = new Collect();
    hub.open(LOTS, reader, "a");
    hub.open(LOTS, stopped, "b");
    // A snapshot larger than the cap is not a drop: the check comes before a publication.
    expect(stopped.destroyed).toBe(false);
    stopped.unsent = 101;
    node.mine([ev.posted(2)]);
    await settle(subject);
    expect(stopped.destroyed).toBe(true);
    expect(reader.destroyed).toBe(false);
    expect(hub.dropped).toBe(1);
    expect(hub.size).toBe(1);
    expect(events(reader.take()).slice(-2)).toEqual(["add", "head"]);
  });

  it("over HTTP: 400 on a bad parameter, 429 over a cap (with the head), and a socket that stops reading is dropped", async () => {
    const node = new FakeNode();
    node.mine(
      Array.from({ length: 5_000 }, (_, i) =>
        ev.posted(i + 1, { price: BigInt(i) }),
      ),
    );
    const subject = indexerOf(node);
    await settle(subject);
    const server = serve(subject, {
      limits: { perClient: 1, maxBuffered: 64 * 1024 },
    });
    await new Promise<void>((resolve) =>
      server.listen(0, "127.0.0.1", resolve),
    );
    const { port } = server.address() as { port: number };
    const base = `http://127.0.0.1:${port}`;
    try {
      const bad = await fetch(`${base}/subscribe/lots?key=0x7`);
      expect(bad.status).toBe(400);
      expect(await bad.json()).toMatchObject({ head: { number: 1 } });
      // A subscriber that never reads: its socket is paused.
      const socket = connect(port, "127.0.0.1");
      await new Promise<void>((resolve) => socket.once("connect", resolve));
      socket.write(
        "GET /subscribe/lots?key=0x7&size=1 HTTP/1.1\r\nHost: x\r\n\r\n",
      );
      socket.pause();
      const closed = new Promise<void>((resolve) =>
        socket.once("close", () => resolve()),
      );
      while (server.subscriptions.size === 0)
        await new Promise((resolve) => setTimeout(resolve, 5));
      const refused = await fetch(`${base}/subscribe/lots?key=0x7&size=1`);
      expect(refused.status).toBe(429);
      expect(await refused.json()).toMatchObject({
        error: "too many subscriptions from this client",
        head: { number: 1 },
      });
      // Blocks of 2 000 lots (about 350 KB of frames each) until the sockets' buffers are full (a
      // few MB on macOS) and a publication finds more than the cap still unsent: dropped. At most
      // 40 blocks (about 14 MB).
      let lot = 5_000;
      for (let block = 0; block < 40; block++) {
        node.mine(
          Array.from({ length: 2_000 }, () =>
            ev.posted(++lot, { price: BigInt(lot) }),
          ),
        );
        await settle(subject);
        if (server.subscriptions.dropped > 0) break;
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
      expect(server.subscriptions.dropped).toBe(1);
      expect(server.subscriptions.size).toBe(0);
      socket.resume(); // the stream ends: the server destroyed it
      await closed;
    } finally {
      server.close();
      server.closeAllConnections();
    }
  });
});
