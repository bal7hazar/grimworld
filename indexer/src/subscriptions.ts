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
//   head        {head}              then the block's head, always after the block's last change:
//                                   the changes before it apply together, and the copy is now as
//                                   of that block
//   rewind      {to}                the tables went back to block `to`: a new snapshot follows
//   : keep-alive                    a comment, on a stream idle for `keepAliveMs`
// Rows: a lot (queries.ts, `Lot`), id its lot id; an adventurer `{adventurer}`, id its number as
// text; an invitation (`Invitation`), id its trade id. Invitations also go away by block time alone
// (10 minutes after their block).
//
// Each subscription has its own position: the head its copy is at (`head`), or the snapshot it is
// being sent (a block and a page index). Its next changes are always read over `(head, served]`
// from ITS head, never from the block the indexer served before: a subscription that waited (it
// was slow, or its turn had not come) still receives every block, in order. A position is a block's
// identity (hash and commitments), not only its number: a head or a snapshot whose block is no
// longer the stored one at its height (a rewind it did not hear of) starts a new snapshot. Nothing
// is read above the served block (R6), nothing below the kept history (a position under it starts
// a snapshot).
//
// Work is done in steps (one snapshot page, or at most `page` changes of one block), taken in turns
// across the subscriptions and spread over turns of the event loop (at most `sliceMs` of work per
// turn): a rewind that resnapshots every subscription does not block the process. A snapshot's
// pages are all read as of its block, whatever is served meanwhile (the rows are versioned), and
// nothing else is sent to that subscriber between them; a rewind or a state other than `ok`
// abandons it, with `rewind` or `status`, and a new one starts at the next served block. What the
// subscribers of one topic share is read and serialised once: a snapshot's pages (per topic and
// block), and the changes of a range of blocks (per topic and range, at most `planBlocks` blocks).
//
// Bounded, and stated: at most `perProcess` subscriptions, and `perClient` from one remote address
// (an HTTP/1.1 connection carries one stream: the cap per connection is kept per address).
// Backpressure is respected: a step writes only while the socket accepts (`write` true), else the
// subscription waits for `drain`. A step writes at most `page` rows or changes (about 250 KB at
// most with the default 1 000); a subscription whose unsent output passes `maxBuffered` after a
// write is dropped at once: a reader that keeps up holds at most the socket's high-water mark plus
// one step, under the cap. The memory the streams hold is at most `perProcess × maxBuffered`
// (defaults: 512 × 512 KiB = 256 MiB). The shared snapshot pages hold at most `pagesMaxBytes` (64
// MiB): a page is released once every snapshot reading its topic has passed it, a topic's pages
// once no snapshot reads them, and past the cap the least recently used are evicted (their readers
// start their snapshot again). A subscription that has not accepted a write for `stallMs` (its
// reader stopped) is dropped. Every write and every step is isolated: a throw ends that
// subscription only. Dropping destroys the stream, which the client library reads as the end of
// its copy (R4).
import { headOf, sameBlock, type Header } from "./chain.ts";
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
  /** Rows per snapshot page, and changes per step. */
  page: number;
  /** Work per turn of the event loop, at most (then the next turn). */
  sliceMs: number;
  /** Bytes of shared snapshot pages kept, at most. */
  pagesMaxBytes: number;
  /** Blocks of changes read in one range, at most. */
  planBlocks: number;
};

export const DEFAULT_LIMITS: Limits = {
  perProcess: 512,
  perClient: 16,
  maxBuffered: 512 * 1024,
  stallMs: 30_000,
  keepAliveMs: 15_000,
  page: 1000,
  sliceMs: 10,
  pagesMaxBytes: 64 * 2 ** 20,
  planBlocks: 100,
};

/** Part of a range's changes: at most `page` frames; `block` set on the last part of a block. */
type Chunk = { text: string; block: Header | null };

type Snapshot = {
  block: Header;
  total: number;
  /** The next page to send. */
  page: number;
  /** The shared pages it reads. */
  key: string;
};

type Subscription = {
  topic: Topic;
  /** The topic as text: the key of what its subscribers share. */
  name: string;
  sink: Sink;
  client: string;
  /** The block the subscriber's copy is at; null until a snapshot is complete. */
  head: Header | null;
  /** The snapshot being sent, if any. */
  snapshot: Snapshot | null;
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

/** A snapshot's pages, read once per topic and block, as its readers reach them. */
type Pages = {
  /** The topic and block they are of: new snapshots join while page 0 is still held. */
  base: string;
  /** Page texts; null once every reader has passed it. */
  texts: (string | null)[];
  bytes: number;
  /** The cursor after the last page read. */
  cursor: unknown;
  done: boolean;
  readers: Set<Subscription>;
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
  /** Shared pages by key, least recently used first. */
  private readonly pages = new Map<string, Pages>();
  /** The pages a new snapshot of a topic and block joins (page 0 still held). */
  private readonly joinable = new Map<string, string>();
  private pagesCount = 0;
  /** Bytes of every shared page held. */
  pagesBytes = 0;
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

  /** The topics and blocks whose pages are held (tests, `/stats`). */
  get pagesHeld(): number {
    return this.pages.size;
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
    for (const subscription of [...this.all]) {
      this.remove(subscription);
      try {
        subscription.sink.destroy();
      } catch {
        // already gone
      }
    }
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
    this.plans = new Map();
    for (const subscription of this.all) this.leave(subscription);
    this.pages.clear();
    this.joinable.clear();
    this.pagesBytes = 0;
  }

  /** The copy is void: a snapshot starts again at the next served block. */
  private reset(subscription: Subscription) {
    this.leave(subscription);
    subscription.head = null;
    subscription.plan = null;
  }

  // --- the shared pages ----------------------------------------------------------------------------

  /** The subscription stops reading its snapshot's pages; they are released as far as possible. */
  private leave(subscription: Subscription) {
    const snapshot = subscription.snapshot;
    subscription.snapshot = null;
    if (!snapshot) return;
    const pages = this.pages.get(snapshot.key);
    if (!pages) return;
    pages.readers.delete(subscription);
    this.release(snapshot.key, pages);
  }

  /** Frees the pages every reader has passed; all of them, and the entry, once none reads it. */
  private release(key: string, pages: Pages) {
    if (pages.readers.size === 0) {
      this.evict(key, pages);
      return;
    }
    let first = Infinity;
    for (const reader of pages.readers)
      first = Math.min(first, reader.snapshot?.page ?? 0);
    for (let page = 0; page < first && page < pages.texts.length; page++) {
      const text = pages.texts[page];
      if (text === null || text === undefined) continue;
      pages.texts[page] = null;
      pages.bytes -= text.length;
      this.pagesBytes -= text.length;
      // A new snapshot cannot join pages whose first one is gone.
      if (page === 0 && this.joinable.get(pages.base) === key)
        this.joinable.delete(pages.base);
    }
  }

  /** Forgets an entry; its readers, if any, start their snapshot again. */
  private evict(key: string, pages: Pages) {
    this.pages.delete(key);
    this.pagesBytes -= pages.bytes;
    if (this.joinable.get(pages.base) === key) this.joinable.delete(pages.base);
    for (const reader of pages.readers) {
      reader.snapshot = null;
      this.schedule(reader);
    }
    pages.readers.clear();
  }

  /** The pages a new snapshot of `subscription` at `block` reads: joined, or new. */
  private join(subscription: Subscription, block: Header): string {
    const base = `${subscription.name}@${blockKey(block)}`;
    let key = this.joinable.get(base);
    if (key === undefined || !this.pages.has(key)) {
      key = `${base}#${++this.pagesCount}`;
      this.pages.set(key, {
        base,
        texts: [],
        bytes: 0,
        cursor: undefined,
        done: false,
        readers: new Set(),
      });
      this.joinable.set(base, key);
    }
    this.pages.get(key)!.readers.add(subscription);
    return key;
  }

  // --- writing -------------------------------------------------------------------------------------

  private remove(subscription: Subscription) {
    this.leave(subscription);
    this.all.delete(subscription);
    this.queue.delete(subscription);
  }

  private drop(subscription: Subscription, why: keyof Drops, detail: string) {
    if (!this.all.has(subscription)) return;
    this.remove(subscription);
    this.drops[why]++;
    this.log(`a subscriber of ${subscription.name} dropped: ${detail}`);
    try {
      subscription.sink.destroy();
    } catch {
      // already gone
    }
  }

  /**
   * Writes; false if the subscription is gone or must wait for `drain`. A sink that throws ends
   * that subscription only, wherever the write comes from (a step, a rewind, a state, a tick).
   */
  private write(subscription: Subscription, chunk: string): boolean {
    if (!this.all.has(subscription)) return false;
    let accepted: boolean;
    let unsent: number;
    try {
      accepted = subscription.sink.write(chunk);
      unsent = subscription.sink.buffered();
    } catch (error) {
      this.drop(subscription, "failed", (error as Error).message);
      return false;
    }
    subscription.lastWrite = Date.now();
    if (unsent > this.limits.maxBuffered) {
      this.drop(subscription, "buffered", `${unsent} bytes unsent`);
      return false;
    }
    if (!accepted && subscription.blockedSince === null) {
      subscription.blockedSince = Date.now();
      try {
        subscription.sink.onDrain(() => {
          subscription.blockedSince = null;
          this.schedule(subscription);
        });
      } catch (error) {
        this.drop(subscription, "failed", (error as Error).message);
        return false;
      }
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

  /** Whether `block` is still the stored (or served) block at its height. */
  private current(block: Header, served: Header): boolean {
    const now =
      block.number === served.number
        ? served
        : this.indexer.store.block(block.number);
    return now !== undefined && sameBlock(now, block);
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
      if (
        snapshot.block.number < lowest ||
        !this.current(snapshot.block, served)
      ) {
        this.leave(subscription); // its block is no longer readable: start again
        return true;
      }
      const pages = this.pagesOf(subscription, snapshot);
      if (!pages) {
        subscription.snapshot = null; // its pages were evicted: start again
        return true;
      }
      if (snapshot.page < pages.texts.length) {
        const text = pages.texts[snapshot.page]!;
        snapshot.page++;
        this.release(snapshot.key, pages);
        return this.write(subscription, text);
      }
      this.leave(subscription);
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
    if (
      !head ||
      head.number < lowest ||
      head.number > served.number ||
      !this.current(head, served)
    ) {
      // No copy yet, or one that can no longer be continued: a snapshot at the served block.
      const total = this.total(subscription.topic, served);
      subscription.head = null;
      subscription.plan = null;
      subscription.snapshot = {
        block: served,
        total,
        page: 0,
        key: this.join(subscription, served),
      };
      return this.write(
        subscription,
        frame("reset-begin", { head: headOf(served), total }),
      );
    }
    if (head.number === served.number && !subscription.plan) return false;
    if (
      !subscription.plan ||
      subscription.plan.next >= subscription.plan.chunks.length
    ) {
      subscription.plan = null;
      if (head.number === served.number) return false;
      subscription.plan = {
        chunks: this.planOf(subscription, head, served),
        next: 0,
      };
    }
    const chunk = subscription.plan.chunks[subscription.plan.next++]!;
    if (chunk.block) subscription.head = chunk.block;
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
   * The snapshot's pages, read up to the one the subscription needs next, once for every reader
   * of the topic and block; null if they were evicted. Past `pagesMaxBytes`, the least recently
   * used other entries are evicted.
   */
  private pagesOf(
    subscription: Subscription,
    snapshot: Snapshot,
  ): Pages | null {
    const pages = this.pages.get(snapshot.key);
    if (!pages) return null;
    // Least recently used first: this one goes to the end.
    this.pages.delete(snapshot.key);
    this.pages.set(snapshot.key, pages);
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
    if (rows.length > 0) {
      const text = frame("reset-page", { rows });
      pages.texts.push(text);
      pages.bytes += text.length;
      this.pagesBytes += text.length;
    }
    if (rows.length < size) pages.done = true;
    this.bound(subscription, snapshot.key, pages);
    return pages;
  }

  /**
   * Past `pagesMaxBytes`: the other entries go first, least recently used first; then this
   * entry's slowest readers (never `asking`) are detached and start their snapshot again, which
   * releases the pages they held. What remains is at most the pages `asking` has not passed: one.
   */
  private bound(asking: Subscription, key: string, pages: Pages) {
    for (const [other, entry] of this.pages) {
      if (this.pagesBytes <= this.limits.pagesMaxBytes) return;
      if (other !== key) this.evict(other, entry);
    }
    while (this.pagesBytes > this.limits.pagesMaxBytes) {
      let slowest: Subscription | null = null;
      for (const reader of pages.readers)
        if (
          reader !== asking &&
          (!slowest || reader.snapshot!.page < slowest.snapshot!.page)
        )
          slowest = reader;
      if (!slowest) return;
      pages.readers.delete(slowest);
      slowest.snapshot = null;
      this.schedule(slowest);
      this.release(key, pages);
    }
  }

  /**
   * The chunks of `(from, to]` for the subscription's topic, `to` the served block or `planBlocks`
   * after `from`, whichever is lower; once for every subscriber.
   */
  private planOf(
    subscription: Subscription,
    from: Header,
    served: Header,
  ): Chunk[] {
    const number = Math.min(
      served.number,
      from.number + this.limits.planBlocks,
    );
    const to =
      number === served.number ? served : this.indexer.store.block(number)!;
    const key = `${subscription.name}|${blockKey(from)}|${blockKey(to)}`;
    let chunks = this.plans.get(key);
    if (!chunks) {
      chunks = this.chunks(subscription.topic, from, to);
      this.plans.set(key, chunks);
    }
    return chunks;
  }

  /**
   * Every block of `(from, to]` that changed the topic, in block order: its changes in chunks of at
   * most `page` frames, then its head, in the block's last chunk. The last chunk is always at `to`
   * (its head alone if it changed nothing).
   */
  private chunks(topic: Topic, from: Header, to: Header): Chunk[] {
    const perBlock = new Map<number, { added: unknown[]; removed: string[] }>();
    if (topic.kind === "lots") {
      for (const [block, change] of this.queries.lotChanges(
        topic.key,
        topic.size,
        from.number,
        to.number,
      ))
        perBlock.set(block, change);
    } else if (topic.kind === "presence") {
      for (const [block, { added, removed }] of this.queries.presenceChanges(
        topic.hub,
        from.number,
        to.number,
      ))
        perBlock.set(block, {
          added: added.map((adventurer) => ({ adventurer })),
          removed: removed.map(String),
        });
    } else {
      for (const [block, { added, removed }] of this.queries.invitationChanges(
        topic.account,
        from,
        to.number,
      ))
        perBlock.set(block, { added: added as Invitation[], removed });
    }
    const chunks: Chunk[] = [];
    for (const [number, { added, removed }] of [...perBlock].sort(
      ([a], [b]) => a - b,
    )) {
      const block =
        number === to.number ? to : this.indexer.store.block(number)!;
      const frames = [
        ...removed.map((id) => frame("remove", { id })),
        ...added.map((row) => frame("add", { row })),
      ];
      for (let at = 0; at < frames.length; at += this.limits.page) {
        const last = at + this.limits.page >= frames.length;
        let text = frames.slice(at, at + this.limits.page).join("");
        if (last) text += frame("head", { head: headOf(block) });
        chunks.push({ text, block: last ? block : null });
      }
    }
    if (chunks[chunks.length - 1]?.block?.number !== to.number)
      chunks.push({ text: frame("head", { head: headOf(to) }), block: to });
    return chunks;
  }
}

function statusOf(status: Status, reason: string) {
  return { status, ...(reason ? { reason } : {}) };
}
