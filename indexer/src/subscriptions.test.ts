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
import {
  KEEP_ALIVE,
  Subscriptions,
  frame,
  type Sink,
  type Topic,
} from "./subscriptions.ts";
import { FakeNode, ev } from "./testing/fake-node.ts";
import { indexerOf, nodeFetch, settle } from "./testing/setup.ts";

/**
 * A sink that keeps the frames. `pause()` plays a reader that stopped: writes are refused (false)
 * and their bytes count as unsent until `resume()`, which drains.
 */
class Collect implements Sink {
  chunks: string[] = [];
  unsent = 0;
  paused = false;
  destroyed = false;
  writes = 0;
  failing = false;
  private read = 0;
  private drains: (() => void)[] = [];
  onWrite: ((chunk: string) => void) | null = null;
  write(chunk: string) {
    if (this.failing) throw new Error("the sink failed");
    this.writes++;
    this.chunks.push(chunk);
    if (this.paused) this.unsent += chunk.length;
    this.onWrite?.(chunk);
    return !this.paused;
  }
  buffered() {
    return this.unsent;
  }
  onDrain(listener: () => void) {
    this.drains.push(listener);
  }
  destroy() {
    this.destroyed = true;
  }
  pause() {
    this.paused = true;
  }
  resume() {
    this.paused = false;
    this.unsent = 0;
    const drains = this.drains;
    this.drains = [];
    for (const drain of drains) drain();
  }
  /** The frames written since the last call (comments left out). */
  take(): Frame[] {
    const frames = framesOf(this.chunks.slice(this.read).join(""));
    this.read = this.chunks.length;
    return frames;
  }
}

const events = (frames: Frame[]) => frames.map((frame) => frame.event);

/** The frames of a stream's text (a chunk may hold several), comments left out. */
function framesOf(text: string): Frame[] {
  return text
    .split("\n\n")
    .map((part) => parseFrame(part))
    .filter((frame): frame is Frame => frame !== null);
}
const LOTS: Topic = { kind: "lots", key: 7n, size: 1 };
const turn = () => new Promise((resolve) => setImmediate(resolve));

function setup(limits = {}) {
  const node = new FakeNode();
  const subject = indexerOf(node);
  const hub = new Subscriptions(subject, limits);
  const client = new IndexerClient({
    url: "http://indexer.invalid",
    node: "http://node.invalid",
    fetch: nodeFetch(node),
  });
  /** The indexer steps until idle, then the subscriptions do their work. */
  const catchUp = async () => {
    await settle(subject);
    await hub.idle();
  };
  return { node, subject, hub, client, catchUp };
}

/** Q1's lots at the served block, all of them. */
function lotsNow(subject: ReturnType<typeof indexerOf>): Lot[] {
  return answer(subject, "/lots?key=0x7&size=1&limit=100").body.lots as Lot[];
}

describe("R4 on the server: snapshot, then the changes of each served block", () => {
  it("sends the state until a block is served, then a snapshot, then per-block changes; nothing from an unserved block", async () => {
    const { node, subject, hub, client, catchUp } = setup({ page: 2 });
    node.mine([ev.posted(1, { price: 30n }), ev.posted(2, { price: 10n })]);
    node.mine([ev.posted(3, { price: 20n }), ev.posted(4, { key: 8n })]);
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    await hub.idle();
    expect(sink.take()).toEqual([
      { event: "status", data: { status: "loading" } },
    ]);
    await catchUp();
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
    await hub.idle();
    expect(sink.take()).toEqual([]);
    await catchUp();
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
    const { node, subject, hub, catchUp } = setup();
    node.mine([ev.posted(1)]);
    await settle(subject);
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    await hub.idle();
    sink.take();
    node.mine([ev.posted(2)]);
    node.mine([ev.posted(3, { key: 8n })]); // another key: only a head at the end
    node.mine([ev.closed(1, false), ev.posted(4), ev.closed(4, true)]); // 4 opened and closed in one block: nothing
    node.mine();
    await subject.step(); // applies 2..5
    await hub.idle();
    expect(sink.take()).toEqual([]);
    await catchUp(); // checks and serves 5
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

  it("after a rewind: the state, the rewind, then a new snapshot at the block served next", async () => {
    const { node, hub, client, catchUp } = setup();
    node.mine([ev.posted(1)]);
    node.mine([ev.posted(2, { price: 5n })]);
    await catchUp();
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    await hub.idle();
    const cache = new LotCache(client, "0x7", 1);
    for (const frame of sink.take()) cache.receive(frame);
    expect(cache.size()).toBe(2);
    node.reorg(1, [[[ev.posted(2, { price: 9n })]], []], true);
    await catchUp();
    const frames = sink.take();
    expect(events(frames)).toEqual([
      "status",
      "rewind",
      "reset-begin",
      "reset-page",
      "reset-end",
    ]);
    expect(frames[0]!.data).toMatchObject({ status: "rewinding" });
    expect(frames[1]!.data).toEqual({ to: 1 });
    expect(frames[2]!.data).toMatchObject({ head: { number: 3 }, total: 2 });
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

  it("a rewind in the middle of a snapshot: the snapshot stops, then the rewind and a whole new one", async () => {
    // One step per turn of the event loop: the rewind comes between two pages.
    const { node, subject, hub, client } = setup({ page: 2, sliceMs: 0 });
    node.mine(
      [1, 2, 3, 4, 5].map((lot) => ev.posted(lot, { price: BigInt(lot) })),
    );
    node.mine([ev.posted(6, { price: 6n })]);
    await settle(subject);
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    while (!events(framesOf(sink.chunks.join(""))).includes("reset-page"))
      await turn();
    // Block 2 is replaced by one where lot 6 is at 60, with the snapshot half sent.
    node.reorg(1, [[[ev.posted(6, { price: 60n })]]], true);
    await settle(subject);
    await hub.idle();
    const frames = sink.take();
    expect(events(frames)).toEqual([
      "reset-begin",
      "reset-page", // the first page of the snapshot at the old block 2
      "status",
      "rewind",
      "reset-begin",
      "reset-page",
      "reset-page",
      "reset-page",
      "reset-end",
    ]);
    expect(frames[4]!.data).toMatchObject({ head: { number: 2 }, total: 6 });
    expect(frames[8]!.data).toEqual(frames[4]!.data);
    const cache = new LotCache(client, "0x7", 1);
    for (const [i, frame] of frames.entries()) {
      cache.receive(frame);
      if (i < 8) expect(cache.ready).toBe(false); // never ready on the half snapshot
    }
    const read = await cache.read();
    expect(read.fresh).toBe(true);
    if (read.fresh) {
      expect(read.answer.rows.find((lot) => lot.lot === "6")?.price).toBe("60");
      expect(read.answer.rows).toEqual(lotsNow(subject));
    }
  });

  it("each subscription continues from its own head: a slow one gets every block it missed, in order", async () => {
    const { node, subject, hub } = setup();
    node.mine([ev.posted(1)]);
    await settle(subject);
    const fast = new Collect();
    const slow = new Collect();
    hub.open(LOTS, fast, "a");
    hub.open(LOTS, slow, "b");
    await hub.idle();
    fast.take();
    slow.take();
    slow.pause(); // its reader stops: the hub learns it at its next write (refused)
    node.mine([ev.posted(2)]);
    await settle(subject);
    await hub.idle();
    const blockedWrites = slow.writes;
    node.mine([ev.posted(3)]);
    node.mine([ev.closed(1, true)]);
    await settle(subject);
    await hub.idle();
    expect(slow.writes).toBe(blockedWrites); // nothing written while it waits for drain
    slow.resume();
    await hub.idle();
    const heads = (sink: Collect) =>
      sink
        .take()
        .map((frame) =>
          frame.event === "head"
            ? `head ${frame.data.head.number}`
            : `${frame.event} ${JSON.stringify(frame.data).slice(0, 18)}`,
        );
    const fastFrames = heads(fast);
    // The slow one received, after what it had, the rest of the same sequence.
    const slowFrames = heads(slow);
    expect(fastFrames.slice(-slowFrames.length)).toEqual(slowFrames);
    expect(slowFrames.at(-1)).toBe("head 4");
    expect(fastFrames.filter((f) => f.startsWith("head"))).toEqual([
      "head 2",
      "head 3",
      "head 4",
    ]);
  });

  it("a subscription whose step throws ends alone; the others get the block", async () => {
    const { node, hub, catchUp } = setup();
    node.mine([ev.posted(1)]);
    await catchUp();
    const broken = new Collect();
    const first = new Collect();
    const last = new Collect();
    hub.open(LOTS, first, "a");
    hub.open(LOTS, broken, "b");
    hub.open(LOTS, last, "c");
    await hub.idle();
    broken.failing = true;
    node.mine([ev.posted(2)]);
    await catchUp();
    expect(broken.destroyed).toBe(true);
    expect(hub.drops.failed).toBe(1);
    for (const sink of [first, last])
      expect(events(sink.take()).slice(-2)).toEqual(["add", "head"]);
  });
});

describe("the presence and invitation subscriptions", () => {
  it("presence: who entered and who left the hub, per block", async () => {
    const { node, hub, catchUp } = setup();
    node.mine([ev.located(3, 9), ev.located(3, 4)]);
    await catchUp();
    const sink = new Collect();
    hub.open({ kind: "presence", hub: 3 }, sink, "a");
    await hub.idle();
    expect(sink.take()[1]).toEqual({
      event: "reset-page",
      data: { rows: [{ adventurer: 4 }, { adventurer: 9 }] },
    });
    node.mine([ev.located(0, 4), ev.located(3, 7), ev.located(5, 8)]);
    await catchUp();
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
    const { node, hub, catchUp } = setup();
    node.time = 5000;
    node.mine([ev.opened(1, 12, 9), ev.opened(2, 13, 9)]);
    await catchUp();
    const sink = new Collect();
    hub.open({ kind: "invitations", account: 12 }, sink, "a");
    await hub.idle();
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
    await catchUp();
    expect(events(sink.take())).toEqual(["add", "head"]);
    node.time = 5599;
    node.mine(); // 599 s: still shown
    await catchUp();
    expect(events(sink.take())).toEqual(["head"]);
    node.time = 5600;
    node.mine(); // no event: trade 1 is 600 s old
    await catchUp();
    expect(sink.take()).toEqual([
      { event: "remove", data: { id: "1" } },
      {
        event: "head",
        data: { head: expect.objectContaining({ number: 4, timestamp: 5600 }) },
      },
    ]);
    node.time = 5601;
    node.mine([ev.tradeClosed(3, 1)]); // declined
    await catchUp();
    expect(sink.take()[0]).toEqual({ event: "remove", data: { id: "3" } });
  });

  it("invitations over several blocks at once: the same changes, block by block, as one block at a time", async () => {
    const one = setup();
    const many = setup();
    for (const { node } of [one, many]) {
      node.time = 1000;
      node.mine([ev.opened(1, 12, 9)]);
    }
    const sinks = [new Collect(), new Collect()];
    for (const [i, { hub, catchUp }] of [one, many].entries()) {
      await catchUp();
      hub.open({ kind: "invitations", account: 12 }, sinks[i]!, "a");
      await hub.idle();
      sinks[i]!.take();
    }
    const blocks: [number, ReturnType<typeof ev.opened>[]][] = [
      [1300, [ev.opened(2, 12, 8)]],
      [1600, []], // trade 1 out by time
      [1700, [ev.tradeClosed(2, 2)]],
      [1800, [ev.opened(3, 12, 7)]],
    ];
    for (const [time, events_] of blocks) {
      for (const { node } of [one, many]) {
        node.time = time;
        node.mine(events_);
      }
      await one.catchUp();
    }
    await many.catchUp();
    const oneByOne = sinks[0]!.take();
    expect(events(oneByOne)).toEqual([
      "add", // trade 2
      "head",
      "remove", // trade 1, by time
      "head",
      "remove", // trade 2, declined
      "head",
      "add", // trade 3
      "head",
    ]);
    expect(sinks[1]!.take()).toEqual(oneByOne);
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

  it("respects backpressure during a snapshot: no page is written until drain", async () => {
    const { node, hub, catchUp } = setup({ page: 10 });
    node.mine(
      Array.from({ length: 100 }, (_, i) => ev.posted(i + 1, { price: 5n })),
    );
    await catchUp();
    const sink = new Collect();
    sink.pause(); // the reader stopped at once
    hub.open(LOTS, sink, "a");
    await hub.idle();
    expect(events(sink.take())).toEqual(["reset-begin"]); // then it waits
    sink.resume();
    await hub.idle();
    const rest = sink.take();
    expect(events(rest).filter((e) => e === "reset-page")).toHaveLength(10);
    expect(rest.at(-1)?.event).toBe("reset-end");
  });

  it("drops a subscriber the moment its unsent output passes the cap, and one stalled for stallMs", async () => {
    const { node, hub, catchUp } = setup({
      page: 10,
      maxBuffered: 500,
      stallMs: 60,
    });
    node.mine(
      Array.from({ length: 100 }, (_, i) => ev.posted(i + 1, { price: 5n })),
    );
    await catchUp();
    const over = new Collect();
    over.pause();
    over.unsent = 400; // a page more is past 500 bytes
    const stalled = new Collect();
    stalled.pause();
    const reader = new Collect();
    hub.open(LOTS, over, "a");
    hub.open({ kind: "presence", hub: 1 }, stalled, "b");
    hub.open(LOTS, reader, "c");
    await hub.idle();
    expect(over.destroyed).toBe(true);
    expect(hub.drops.buffered).toBe(1);
    expect(stalled.destroyed).toBe(false);
    await new Promise((resolve) => setTimeout(resolve, 150));
    expect(stalled.destroyed).toBe(true);
    expect(hub.drops.stalled).toBe(1);
    expect(reader.destroyed).toBe(false);
    expect(events(reader.take()).at(-1)).toBe("reset-end");
  });

  it("writes a keep-alive comment on an idle stream every keepAliveMs", async () => {
    const { node, hub, catchUp } = setup({ keepAliveMs: 30 });
    node.mine([ev.posted(1)]);
    await catchUp();
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    await hub.idle();
    const before = sink.chunks.length;
    await new Promise((resolve) => setTimeout(resolve, 120));
    const comments = sink.chunks.slice(before);
    expect(comments.length).toBeGreaterThanOrEqual(2);
    expect(new Set(comments)).toEqual(new Set([KEEP_ALIVE]));
    hub.close();
  });

  it("over HTTP: 400 on a bad parameter, 429 over a cap (with the head), CORS for an allowed origin, and a client that stops reading during a snapshot is dropped without passing the cap", async () => {
    const node = new FakeNode();
    // 20 000 lots: a snapshot of about 3.5 MB, more than the sockets' buffers hold.
    node.mine(
      Array.from({ length: 20_000 }, (_, i) =>
        ev.posted(i + 1, { price: BigInt(i) }),
      ),
    );
    const subject = indexerOf(node);
    await settle(subject);
    const logs: string[] = [];
    const server = serve(subject, {
      limits: { perClient: 1, maxBuffered: 512 * 1024, stallMs: 300 },
      allowedOrigins: ["https://game.example"],
      log: (line) => logs.push(line),
    });
    await new Promise<void>((resolve) =>
      server.listen(0, "127.0.0.1", resolve),
    );
    const { port } = server.address() as { port: number };
    const base = `http://127.0.0.1:${port}`;
    try {
      const bad = await fetch(`${base}/subscribe/lots?key=0x7`, {
        headers: { origin: "https://game.example" },
      });
      expect(bad.status).toBe(400);
      expect(bad.headers.get("access-control-allow-origin")).toBe(
        "https://game.example",
      );
      expect(await bad.json()).toMatchObject({
        status: "error",
        state: "ok",
        head: { number: 1 },
      });
      // A subscriber that reads nothing: its socket is paused from the start.
      const socket = connect(port, "127.0.0.1");
      await new Promise<void>((resolve) => socket.once("connect", resolve));
      socket.pause();
      socket.write(
        "GET /subscribe/lots?key=0x7&size=1 HTTP/1.1\r\nHost: x\r\nOrigin: https://game.example\r\n\r\n",
      );
      const closed = new Promise<void>((resolve) =>
        socket.once("close", () => resolve()),
      );
      while (server.subscriptions.size === 0)
        await new Promise((resolve) => setTimeout(resolve, 5));
      const refused = await fetch(`${base}/subscribe/lots?key=0x7&size=1`, {
        headers: { origin: "https://other.example" },
      });
      expect(refused.status).toBe(429);
      expect(refused.headers.get("access-control-allow-origin")).toBe(null);
      expect(await refused.json()).toMatchObject({
        status: "error",
        error: "too many subscriptions from this client",
        head: { number: 1 },
      });
      // Its stream stops at the sockets' buffers; it is dropped for the stall, never for bytes. On
      // Linux the loopback buffers can hold the whole snapshot: blocks of 2 000 lots follow until
      // they are full (at most 40, about 14 MB).
      const started = performance.now();
      let lot = 20_000;
      for (let block = 0; server.subscriptions.dropped === 0; block++) {
        if (performance.now() - started > 25_000)
          throw new Error("not dropped");
        if (block < 40) {
          node.mine(
            Array.from({ length: 2_000 }, () =>
              ev.posted(++lot, { price: BigInt(lot) }),
            ),
          );
          await settle(subject);
        }
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      expect(server.subscriptions.drops).toEqual({
        buffered: 0,
        stalled: 1,
        failed: 0,
      });
      expect(logs.join("\n")).toMatch(/dropped: no write accepted for \d+ ms/);
      socket.resume();
      await closed;
      // CORS on an event stream too.
      const controller = new AbortController();
      const stream = await fetch(`${base}/subscribe/lots?key=0x7&size=1`, {
        headers: { origin: "https://game.example" },
        signal: controller.signal,
      });
      expect(stream.status).toBe(200);
      expect(stream.headers.get("content-type")).toBe("text/event-stream");
      expect(stream.headers.get("access-control-allow-origin")).toBe(
        "https://game.example",
      );
      controller.abort();
    } finally {
      server.close();
      server.closeAllConnections();
    }
  }, 40_000);
});

/**
 * A reader that keeps up: a write is accepted while less than a socket's high-water mark is
 * unsent, and everything unsent is read at the next turn of the event loop.
 */
class Reader extends Collect {
  largest = 0;
  override write(chunk: string) {
    this.largest = Math.max(this.largest, chunk.length);
    super.write(chunk);
    this.unsent += chunk.length;
    const accepted = this.unsent < 16 * 1024;
    if (!accepted)
      setImmediate(() => {
        this.unsent = 0;
        this.resume();
      });
    return accepted;
  }
}

describe("fix loop 2", () => {
  it("GPT 1: shared pages are released as their readers pass them and when a snapshot ends or its subscriber closes: topics asked one after another do not accumulate", async () => {
    const { node, hub, catchUp } = setup({ page: 10, sliceMs: 0 });
    node.mine(
      Array.from({ length: 5 * 60 }, (_, i) =>
        ev.posted(i + 1, { key: BigInt(1 + (i % 5)), price: BigInt(i) }),
      ),
    );
    await catchUp();
    for (let key = 1n; key <= 5n; key++) {
      // One topic read whole, then one left after its first page: nothing is kept after either.
      const whole = new Collect();
      hub.open({ kind: "lots", key, size: 1 }, whole, "a");
      await hub.idle();
      expect(events(whole.take()).at(-1)).toBe("reset-end");
      expect(hub.pagesHeld).toBe(0);
      expect(hub.pagesBytes).toBe(0);
      const left = new Collect();
      const close = hub.open({ kind: "lots", key, size: 1 }, left, "a");
      while (!events(framesOf(left.chunks.join(""))).includes("reset-page"))
        await turn();
      // A single reader holds the page it is at, never the ones it passed.
      expect(hub.pagesBytes).toBeLessThanOrEqual(left.chunks.at(-1)!.length);
      close();
      expect(hub.pagesHeld).toBe(0);
      expect(hub.pagesBytes).toBe(0);
    }
  });

  it("GPT 1: past pagesMaxBytes the other topics' pages go first, then a slow reader's hold: it starts its snapshot again, complete", async () => {
    const { node, hub, client, catchUp } = setup({
      page: 10,
      pagesMaxBytes: 4000,
    });
    node.mine(
      Array.from({ length: 200 }, (_, i) =>
        ev.posted(i + 1, { key: BigInt(1 + (i % 2)), price: BigInt(i) }),
      ),
    );
    await catchUp();
    let largest = 0;
    hub.onStep = () => (largest = Math.max(largest, hub.pagesBytes));
    // A reader that stopped at the start of topic 1 would hold all its pages for a faster one.
    const behind = new Collect();
    behind.pause();
    hub.open({ kind: "lots", key: 1n, size: 1 }, behind, "a");
    const ahead = new Collect();
    hub.open({ kind: "lots", key: 1n, size: 1 }, ahead, "b");
    const other = new Collect();
    hub.open({ kind: "lots", key: 2n, size: 1 }, other, "c");
    await hub.idle();
    const page = Math.max(...ahead.chunks.map((chunk) => chunk.length));
    expect(largest).toBeLessThanOrEqual(4000 + page);
    behind.resume();
    await hub.idle();
    expect(largest).toBeLessThanOrEqual(4000 + page);
    // The detached reader got a second reset-begin, then a whole snapshot: its copy is complete.
    const frames = behind.take();
    expect(
      events(frames).filter((e) => e === "reset-begin").length,
    ).toBeGreaterThanOrEqual(2);
    for (const [sink, key] of [
      [behind, 1n],
      [ahead, 1n],
      [other, 2n],
    ] as const) {
      const cache = new LotCache(client, key, 1);
      for (const f of sink === behind ? frames : sink.take()) cache.receive(f);
      expect(cache.ready).toBe(true);
      expect(cache.size()).toBe(100);
    }
    expect(hub.pagesBytes).toBe(0);
  });

  it("GPT 2: a sink that throws on the rewind's write ends alone; the others get the rewind and a new snapshot", async () => {
    const { node, subject, hub, client, catchUp } = setup();
    node.mine([ev.posted(1)]);
    node.mine([ev.posted(2, { price: 5n })]);
    await catchUp();
    const sinks = [new Collect(), new Collect(), new Collect()];
    for (const [i, sink] of sinks.entries()) hub.open(LOTS, sink, `c${i}`);
    await hub.idle();
    for (const sink of sinks) sink.take();
    sinks[0]!.failing = true; // the first in turn
    node.reorg(1, [[[ev.posted(2, { price: 9n })]]], true);
    await catchUp();
    expect(sinks[0]!.destroyed).toBe(true);
    expect(hub.drops.failed).toBe(1);
    for (const sink of sinks.slice(1)) {
      const frames = sink.take();
      expect(events(frames).slice(0, 3)).toEqual([
        "status",
        "rewind",
        "reset-begin",
      ]);
      const cache = new LotCache(client, "0x7", 1);
      for (const frame of frames) cache.receive(frame);
      const read = await cache.read();
      expect(read.fresh).toBe(true);
      if (read.fresh) expect(read.answer.rows).toEqual(lotsNow(subject));
    }
  });

  it("GPT 2: a subscription that did not hear of a rewind resnapshots when its head's block was replaced at the same height", async () => {
    const { node, subject, hub, client, catchUp } = setup();
    node.mine([ev.posted(1)]);
    node.mine([ev.posted(2, { price: 5n })]);
    await catchUp();
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    await hub.idle();
    const cache = new LotCache(client, "0x7", 1);
    for (const frame of sink.take()) cache.receive(frame);
    const before = cache.head!;
    // The hub misses the rewind and the state: only the identity of its head can tell it.
    const deaf = hub as unknown as {
      rewound: (to: number) => void;
      status: (status: string, reason: string) => void;
    };
    deaf.rewound = () => {};
    deaf.status = () => {};
    node.reorg(1, [[[ev.posted(2, { price: 9n })]]], true);
    await catchUp();
    expect(subject.served!.number).toBe(before.number); // the same height
    expect(subject.served!.commitments).not.toBe(before.commitments);
    const frames = sink.take();
    expect(events(frames)).toEqual(["reset-begin", "reset-page", "reset-end"]);
    for (const frame of frames) cache.receive(frame);
    const read = await cache.read();
    expect(read.fresh).toBe(true);
    if (read.fresh) {
      expect(read.answer.head.commitments).toBe(subject.served!.commitments);
      expect(read.answer.rows).toEqual(lotsNow(subject));
    }
  });

  it("Opus N2: a block's changes go in frames of at most `page`, its head last: a reader that keeps up through 3 000 lots in one block is not dropped", async () => {
    const { node, hub, catchUp } = setup({ maxBuffered: 300 * 1024 });
    node.mine([ev.posted(1)]);
    await catchUp();
    const reader = new Reader();
    hub.open(LOTS, reader, "a");
    await hub.idle();
    reader.take();
    const writes = reader.writes;
    node.mine(
      Array.from({ length: 3000 }, (_, i) =>
        ev.posted(i + 2, { price: BigInt(i) }),
      ),
    );
    await catchUp();
    // The reader drains a turn after each refused write: wait for the block's head.
    for (
      let i = 0;
      i < 100 && !reader.chunks.at(-1)?.includes("event: head");
      i++
    ) {
      await turn();
      await hub.idle();
    }
    expect(reader.destroyed).toBe(false);
    expect(hub.dropped).toBe(0);
    const frames = reader.take();
    expect(frames.filter((f) => f.event === "add")).toHaveLength(3000);
    expect(events(frames).at(-1)).toBe("head");
    expect(events(frames).filter((e) => e === "head")).toHaveLength(1);
    expect(reader.writes - writes).toBe(3); // 1 000 changes a write, the head in the last
    // Every write stayed well under the cap; the whole block's frames would not have.
    expect(reader.largest).toBeLessThan(300 * 1024);
    expect(
      frames.map((f) => frame(f.event, f.data)).join("").length,
    ).toBeGreaterThan(300 * 1024);
  });

  it("Opus N3: a block served while a snapshot is spread: the pages stay at the snapshot's block, and that block's changes come after reset-end", async () => {
    const { node, subject, hub, client } = setup({ page: 2, sliceMs: 0 });
    node.mine(
      [1, 2, 3, 4, 5].map((lot) => ev.posted(lot, { price: BigInt(10 * lot) })),
    );
    await settle(subject);
    const sink = new Collect();
    hub.open(LOTS, sink, "a");
    while (!events(framesOf(sink.chunks.join(""))).includes("reset-page"))
      await turn();
    // Block 2 is served with the snapshot at block 1 half sent: lot 6 is posted, lot 3 closed.
    node.mine([ev.posted(6, { price: 1n }), ev.closed(3, true)]);
    await settle(subject);
    expect(subject.served!.number).toBe(2);
    await hub.idle();
    const frames = sink.take();
    expect(events(frames)).toEqual([
      "reset-begin",
      "reset-page",
      "reset-page",
      "reset-page",
      "reset-end",
      "remove",
      "add",
      "head",
    ]);
    expect(frames[0]!.data).toMatchObject({ head: { number: 1 }, total: 5 });
    expect(frames[4]!.data).toMatchObject({ head: { number: 1 }, total: 5 });
    const pageLots = frames
      .filter((f) => f.event === "reset-page")
      .flatMap((f) => (f.data as { rows: Lot[] }).rows.map((lot) => lot.lot));
    expect(pageLots).toEqual(["1", "2", "3", "4", "5"]); // block 1's: 3 still open, no 6
    expect(frames[5]!.data).toEqual({ id: "3" });
    expect(frames[7]!.data).toMatchObject({ head: { number: 2 } });
    const cache = new LotCache(client, "0x7", 1);
    for (const [i, f] of frames.entries()) {
      cache.receive(f);
      if (i < 4) expect(cache.ready).toBe(false);
      if (i >= 4 && i < 7) expect(cache.head?.number).toBe(1); // never block 2's rows under head 1
    }
    const read = await cache.read();
    expect(read.fresh).toBe(true);
    if (read.fresh) {
      expect(read.answer.head.number).toBe(2);
      expect(read.answer.rows).toEqual(lotsNow(subject));
    }
  });
});
