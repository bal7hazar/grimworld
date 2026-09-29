// Subscriptions (IDX-01b; SPK-11 §4, R4 and R6): the open lots of a market key and lot size (Q1), a
// hub's presence (Q4), and the invitations of an account (Q7), streamed as server-sent events.
//
// The protocol, one stream per subscription (the client library, client/, reads it):
//   status      {status, reason?}   the indexer is not `ok` (loading, rewinding, halted): the
//                                   subscriber's copy is not ready; a snapshot follows once it is
//   reset-begin {head, total}       a snapshot as of the served block `head`, of `total` rows,
//   reset-page  {rows}              in pages of at most `page` (1 000) rows,
//   reset-end   {head, total}       and its end: complete when the rows received count `total`
//   add         {row}               after the snapshot, per block, in block order: a row that
//   remove      {id}                appeared or went away in that block,
//   head        {head}              then the block's head: the changes before it apply together,
//                                   and the copy is now as of that block
//   rewind      {to}                the tables went back to block `to`: a new snapshot follows
//   : keep-alive                    a comment, on a stream idle for `keepAliveMs`
// Rows: a lot (queries.ts, `Lot`), id its lot id; an adventurer `{adventurer}`, id its number as
// text; an invitation (`Invitation`), id its trade id. Invitations also go away by block time alone
// (10 minutes after their block).
//
// Each subscription has its own position: the head its copy is at (`head`), or the snapshot it is
// being sent (a block and a page index). Its next changes are always read over `(head, served]`
// from ITS head, never from the block the indexer served before: a subscription that waited (it
// was slow, or its turn had not come) still receives every block, in order. Nothing is read above
// the served block (R6), nothing below the kept history (a position under it starts a snapshot).
//
// Work is done in steps (one snapshot page, or one block's changes), taken in turns across the
// subscriptions and spread over turns of the event loop (at most `sliceMs` of work per turn): a
// rewind that resnapshots every subscription does not block the process. A snapshot's pages are
// all read as of its block, whatever is served meanwhile (the rows are versioned), and nothing else
// is sent to that subscriber between them; a rewind or a state other than `ok` abandons it, with
// `rewind` or `status`, and a new one starts at the next served block. What the subscribers of one
// topic share is read and serialised once: a snapshot's pages (per topic and block), and the
// changes of a range of blocks (per topic and range).
//
// Bounded, and stated: at most `perProcess` subscriptions, and `perClient` from one remote address
// (an HTTP/1.1 connection carries one stream: the cap per connection is kept per address).
// Backpressure is respected: a step writes only while the socket accepts (`write` true), else the
// subscription waits for `drain`. A step writes one page (at most `page` rows) or one block's
// changes; a subscription whose unsent output passes `maxBuffered` after a write is dropped at
// once. The memory the streams hold is thus at most `perProcess × maxBuffered` (defaults: 512 ×
// 512 KiB = 256 MiB), besides the shared pages being sent. A subscription that has not accepted a
// write for `stallMs` (its reader stopped) is dropped. A step that throws ends that subscription
// only. Dropping destroys the stream, which the client library reads as the end of its copy (R4).
import { headOf, type Header } from "./chain.ts";
import type { Indexer, Status } from "./indexer.ts";
import { Queries, type Invitation, type LotCursor } from "./queries.ts";

export type Topic =
  | { kind: "lots"; key: bigint; size: number }
  | { kind: "presence"; hub: number }
  | { kind: "invitations"; account: number };

/** Where a stream's frames go: an HTTP response in the server, an object in the tests. */
export type Sink = {
  /** Writes a chunk; false when the socket accepts no more for now (then `onDrain`). */
  write(chunk: string): boolean;
  /** Bytes written and not yet sent. */
  buffered(): number;
  /** Calls `listener` once, when the socket accepts writes again. */
  onDrain(listener: () => void): void;
  /** Ends the stream at once (dropped, or the process stopping). */
  destroy(): void;
};

export type Limits = {
  perProcess: number;
  perClient: number;
  /** Unsent bytes a subscription may hold; above, it is dropped. */
  maxBuffered: number;
  /** A subscription that accepted no write for this long is dropped. */
  stallMs: number;
  /** An idle stream gets a comment frame this often. */
  keepAliveMs: number;
  /** Rows per snapshot page. */
  page: number;
  /** Work per turn of the event loop, at most (then the next turn). */
  sliceMs: number;
};

export const DEFAULT_LIMITS: Limits = {
  perProcess: 512,
  perClient: 16,
  maxBuffered: 512 * 1024,
  stallMs: 30_000,
  keepAliveMs: 15_000,
  page: 1000,
  sliceMs: 10,
};

type Chunk = { text: string; block: Header };

type Subscription = {
  topic: Topic;
  /** The topic as text: the key of what its subscribers share. */
  name: string;
  sink: Sink;
  client: string;
  /** The block the subscriber's copy is at; null until a snapshot is complete. */
  head: Header | null;
  /** The snapshot being sent: its block, its size, the next page. */
  snapshot: { block: Header; total: number; page: number } | null;
  /** The changes being sent: the chunks of a range, and the next one. */
  plan: { chunks: Chunk[]; next: number } | null;
  /** Waiting for `drain` since then (ms), or null. */
  blockedSince: number | null;
  lastWrite: number;
};

/** Why subscribers were dropped, since the start. */
export type Drops = { buffered: number; stalled: number; failed: number };

export const frame = (event: string, data: unknown) =>
  `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;

export const KEEP_ALIVE = ": keep-alive\n\n";

const blockKey = (block: Header) =>
  `${block.number}:${block.hash}:${block.commitments}`;

function nameOf(topic: Topic): string {
  switch (topic.kind) {
    case "lots":
      return `lots ${topic.key}/${topic.size}`;
    case "presence":
      return `presence of hub ${topic.hub}`;
    case "invitations":
      return `invitations of ${topic.account}`;
  }
}

/** A snapshot's pages, read once per topic and block, as its subscribers reach them. */
type Pages = {
  texts: string[];
  /** The cursor after the last page read. */
  cursor: unknown;
  done: boolean;
};

export class Subscriptions {
  private readonly indexer: Indexer;
  private readonly queries: Queries;
  readonly limits: Limits;
  private readonly all = new Set<Subscription>();
  private readonly log: (message: string) => void;
  private readonly unlisten: () => void;
  private readonly timer: ReturnType<typeof setInterval>;
  /** Subscriptions with work to do, in turn. */
  private readonly queue = new Set<Subscription>();
  private scheduled = false;
  private readonly pages = new Map<string, Pages>();
  private plans = new Map<string, Chunk[]>();
  readonly drops: Drops = { buffered: 0, stalled: 0, failed: 0 };
  /** For the tests: called at each step, before it writes. */
  onStep: ((topic: Topic) => void) | null = null;

  constructor(
    indexer: Indexer,
    limits: Partial<Limits> = {},
    log: (message: string) => void = () => {},
  ) {
    this.indexer = indexer;
    this.queries = new Queries(indexer.store);
    this.limits = { ...DEFAULT_LIMITS, ...limits };
    this.log = log;
    this.unlisten = indexer.listen({
      served: () => this.served(),
      rewound: (to) => this.rewound(to),
      status: (status, reason) => this.status(status, reason),
    });
    const tick = Math.max(
      5,
      Math.min(this.limits.keepAliveMs, this.limits.stallMs) / 4,
    );
    this.timer = setInterval(() => this.tick(), tick);
    this.timer.unref();
  }

  get size(): number {
    return this.all.size;
  }

  /** Subscribers dropped since the start, for every reason. */
  get dropped(): number {
    return this.drops.buffered + this.drops.stalled + this.drops.failed;
  }

  /** Why a new subscription from `client` is refused, or null if it may open. */
  refusal(client: string): string | null {
    if (this.all.size >= this.limits.perProcess)
      return "too many subscriptions";
    let mine = 0;
    for (const subscription of this.all)
      if (subscription.client === client) mine++;
    if (mine >= this.limits.perClient)
      return "too many subscriptions from this client";
    return null;
  }

  /** Opens a subscription (the caller checked `refusal` first); returns its closing. */
  open(topic: Topic, sink: Sink, client: string): () => void {
    const subscription: Subscription = {
      topic,
      name: nameOf(topic),
      sink,
      client,
      head: null,
      snapshot: null,
      plan: null,
      blockedSince: null,
      lastWrite: Date.now(),
    };
    this.all.add(subscription);
    if (this.indexer.status !== "ok" || !this.indexer.served)
      this.write(
        subscription,
        frame("status", statusOf(this.indexer.status, this.indexer.reason)),
      );
    this.schedule(subscription);
    return () => this.remove(subscription);
  }

  /** Ends every stream (the process stops). */
  close() {
    this.unlisten();
    clearInterval(this.timer);
    for (const subscription of this.all) subscription.sink.destroy();
    this.all.clear();
    this.queue.clear();
  }

  /** Resolves once no subscription has work it can do now (tests, measures). */
  async idle(): Promise<void> {
    while (this.queue.size > 0 || this.scheduled)
      await new Promise((resolve) => setImmediate(resolve));
  }

  // --- the indexer's events ------------------------------------------------------------------------

  private served() {
    // The ranges planned up to the previous served block are not shared any more.
    this.plans = new Map();
    const reading = new Set(
      [...this.all]
        .filter((subscription) => subscription.snapshot)
        .map((subscription) =>
          pagesKey(subscription.name, subscription.snapshot!.block),
        ),
    );
    for (const key of this.pages.keys())
      if (!reading.has(key)) this.pages.delete(key);
    for (const subscription of this.all) this.schedule(subscription);
  }

  private rewound(to: number) {
    this.forgetShared();
    for (const subscription of [...this.all]) {
      this.reset(subscription);
      this.write(subscription, frame("rewind", { to }));
    }
  }

  private status(status: Status, reason: string) {
    if (status === "ok") return;
    this.forgetShared();
    for (const subscription of [...this.all]) {
      this.reset(subscription);
      this.write(subscription, frame("status", statusOf(status, reason)));
    }
  }

  private forgetShared() {
    this.pages.clear();
    this.plans = new Map();
  }

  /** The copy is void: a snapshot starts again at the next served block. */
  private reset(subscription: Subscription) {
    subscription.head = null;
    subscription.snapshot = null;
    subscription.plan = null;
  }

  // --- writing -------------------------------------------------------------------------------------

  private remove(subscription: Subscription) {
    this.all.delete(subscription);
    this.queue.delete(subscription);
  }

  private drop(subscription: Subscription, why: keyof Drops, detail: string) {
    if (!this.all.has(subscription)) return;
    this.remove(subscription);
    this.drops[why]++;
    this.log(`a subscriber of ${subscription.name} dropped: ${detail}`);
    subscription.sink.destroy();
  }

  /** Writes; false if the subscription is gone or must wait for `drain`. */
  private write(subscription: Subscription, chunk: string): boolean {
    if (!this.all.has(subscription)) return false;
    const accepted = subscription.sink.write(chunk);
    subscription.lastWrite = Date.now();
    const unsent = subscription.sink.buffered();
    if (unsent > this.limits.maxBuffered) {
      this.drop(subscription, "buffered", `${unsent} bytes unsent`);
      return false;
    }
    if (!accepted && subscription.blockedSince === null) {
      subscription.blockedSince = Date.now();
      subscription.sink.onDrain(() => {
        subscription.blockedSince = null;
        this.schedule(subscription);
      });
    }
    return accepted;
  }

  /** Keep-alive comments on idle streams; drops the subscriptions stalled for `stallMs`. */
  private tick() {
    const now = Date.now();
    for (const subscription of [...this.all]) {
      if (subscription.blockedSince !== null) {
        if (now - subscription.blockedSince >= this.limits.stallMs)
          this.drop(
            subscription,
            "stalled",
            `no write accepted for ${now - subscription.blockedSince} ms`,
          );
      } else if (now - subscription.lastWrite >= this.limits.keepAliveMs) {
        this.write(subscription, KEEP_ALIVE);
      }
    }
  }

  // --- the work, in steps --------------------------------------------------------------------------

  private schedule(subscription: Subscription) {
    if (!this.all.has(subscription)) return;
    this.queue.add(subscription);
    if (this.scheduled) return;
    this.scheduled = true;
    setImmediate(() => this.run());
  }

  /** Steps in turn across the subscriptions for at most `sliceMs`, then yields the event loop. */
  private run() {
    this.scheduled = false;
    const deadline = performance.now() + this.limits.sliceMs;
    // At least one step per turn, then as many as `sliceMs` allows.
    let first = true;
    while (this.queue.size > 0 && (first || performance.now() < deadline)) {
      first = false;
      for (const subscription of [...this.queue]) {
        let more = false;
        try {
          more = this.step(subscription);
        } catch (error) {
          // This subscription only: the others go on.
          this.drop(subscription, "failed", (error as Error).message);
        }
        if (!more) this.queue.delete(subscription);
        if (performance.now() >= deadline) break;
      }
    }
    if (this.queue.size > 0 && !this.scheduled) {
      this.scheduled = true;
      setImmediate(() => this.run());
    }
  }

  /** One step of one subscription; true if it has more to do now. */
  private step(subscription: Subscription): boolean {
    if (!this.all.has(subscription) || subscription.blockedSince !== null)
      return false;
    const served = this.indexer.served;
    if (this.indexer.status !== "ok" || !served) return false;
    this.onStep?.(subscription.topic);
    const lowest = this.indexer.store.lowest()?.number ?? served.number;
    const { snapshot } = subscription;
    if (snapshot) {
      if (snapshot.block.number < lowest) {
        subscription.snapshot = null; // its block is no longer readable: start again
        return true;
      }
      const pages = this.pagesOf(subscription, snapshot);
      if (snapshot.page < pages.texts.length) {
        const text = pages.texts[snapshot.page]!;
        snapshot.page++;
        return this.write(subscription, text);
      }
      subscription.snapshot = null;
      subscription.head = snapshot.block;
      return this.write(
        subscription,
        frame("reset-end", {
          head: headOf(snapshot.block),
          total: snapshot.total,
        }),
      );
    }
    const head = subscription.head;
    if (!head || head.number < lowest || head.number > served.number) {
      // No copy yet, or one that can no longer be continued: a snapshot at the served block.
      const total = this.total(subscription.topic, served);
      subscription.head = null;
      subscription.plan = null;
      subscription.snapshot = { block: served, total, page: 0 };
      return this.write(
        subscription,
        frame("reset-begin", { head: headOf(served), total }),
      );
    }
    if (head.number === served.number) return false;
    if (
      !subscription.plan ||
      subscription.plan.next >= subscription.plan.chunks.length
    )
      subscription.plan = {
        chunks: this.planOf(subscription, head, served),
        next: 0,
      };
    const chunk = subscription.plan.chunks[subscription.plan.next++]!;
    subscription.head = chunk.block;
    return this.write(subscription, chunk.text);
  }

  private total(topic: Topic, block: Header): number {
    switch (topic.kind) {
      case "lots":
        return this.queries.lotCount(block.number, topic.key, topic.size);
      case "presence":
        return this.queries.presence(block.number, topic.hub, 0).count;
      case "invitations":
        return this.queries.invitations(block, topic.account, 0).total;
    }
  }

  /**
   * The snapshot's pages at its block, read up to the one the subscription needs next, once for
   * every subscriber of the topic.
   */
  private pagesOf(
    subscription: Subscription,
    snapshot: { block: Header; page: number },
  ): Pages {
    const key = pagesKey(subscription.name, snapshot.block);
    let pages = this.pages.get(key);
    if (!pages) {
      pages = { texts: [], cursor: undefined, done: false };
      this.pages.set(key, pages);
    }
    if (snapshot.page < pages.texts.length || pages.done) return pages;
    const { topic } = subscription;
    const size = this.limits.page;
    const block = snapshot.block;
    let rows: unknown[];
    switch (topic.kind) {
      case "lots": {
        const lots = this.queries.lotPage(
          block.number,
          topic.key,
          topic.size,
          size,
          pages.cursor as LotCursor | undefined,
        );
        const last = lots[lots.length - 1];
        if (last)
          pages.cursor = { price: BigInt(last.price), lot: BigInt(last.lot) };
        rows = lots;
        break;
      }
      case "presence": {
        const { adventurers } = this.queries.presence(
          block.number,
          topic.hub,
          size,
          (pages.cursor as number | undefined) ?? -1,
          false,
        );
        if (adventurers.length)
          pages.cursor = adventurers[adventurers.length - 1];
        rows = adventurers.map((adventurer) => ({ adventurer }));
        break;
      }
      case "invitations": {
        const { invitations } = this.queries.invitations(
          block,
          topic.account,
          size,
          pages.cursor as bigint | undefined,
          false,
        );
        const last = invitations[invitations.length - 1];
        if (last) pages.cursor = BigInt(last.trade);
        rows = invitations;
        break;
      }
    }
    if (rows.length > 0) pages.texts.push(frame("reset-page", { rows }));
    if (rows.length < size) pages.done = true;
    return pages;
  }

  /** The chunks of `(from, served]` for the subscription's topic, once for every subscriber. */
  private planOf(
    subscription: Subscription,
    from: Header,
    served: Header,
  ): Chunk[] {
    const key = `${subscription.name}|${blockKey(from)}|${blockKey(served)}`;
    let chunks = this.plans.get(key);
    if (!chunks) {
      chunks = this.chunks(subscription.topic, from, served);
      this.plans.set(key, chunks);
    }
    return chunks;
  }

  /**
   * Every block of `(from, served]` that changed the topic, as a chunk (its changes, then its
   * head), in block order; the last chunk is always at `served` (its head alone if it changed
   * nothing).
   */
  private chunks(topic: Topic, from: Header, served: Header): Chunk[] {
    const perBlock = new Map<number, { added: unknown[]; removed: string[] }>();
    if (topic.kind === "lots") {
      for (const [block, change] of this.queries.lotChanges(
        topic.key,
        topic.size,
        from.number,
        served.number,
      ))
        perBlock.set(block, change);
    } else if (topic.kind === "presence") {
      for (const [block, { added, removed }] of this.queries.presenceChanges(
        topic.hub,
        from.number,
        served.number,
      ))
        perBlock.set(block, {
          added: added.map((adventurer) => ({ adventurer })),
          removed: removed.map(String),
        });
    } else {
      for (const [block, { added, removed }] of this.queries.invitationChanges(
        topic.account,
        from,
        served.number,
      ))
        perBlock.set(block, { added: added as Invitation[], removed });
    }
    const chunks: Chunk[] = [];
    for (const [number, { added, removed }] of [...perBlock].sort(
      ([a], [b]) => a - b,
    )) {
      const block =
        number === served.number ? served : this.indexer.store.block(number)!;
      let text = "";
      for (const id of removed) text += frame("remove", { id });
      for (const row of added) text += frame("add", { row });
      text += frame("head", { head: headOf(block) });
      chunks.push({ text, block });
    }
    if (chunks[chunks.length - 1]?.block.number !== served.number)
      chunks.push({
        text: frame("head", { head: headOf(served) }),
        block: served,
      });
    return chunks;
  }
}

const pagesKey = (name: string, block: Header) => `${name}@${blockKey(block)}`;

function statusOf(status: Status, reason: string) {
  return { status, ...(reason ? { reason } : {}) };
}
