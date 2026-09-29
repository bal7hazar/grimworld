// Subscriptions (IDX-01b; SPK-11 §4, R4 and R6): the open lots of a market key and lot size (Q1), a
// hub's presence (Q4), and the invitations of an account (Q7), streamed as server-sent events.
//
// The protocol, one stream per subscription (the client library, client/, reads it):
//   status      {status, reason?}   the indexer is not `ok` (loading, rewinding, halted): the
//                                   subscriber's copy is not ready; a snapshot follows once it is
//   reset-begin {head, total}       a snapshot as of the served block `head`, of `total` rows,
//   reset-page  {rows}              in pages of at most `page` (1 000) rows,
//   reset-end   {head, total}       and its end: complete when the rows received count `total`
//   add         {row}               per block, in block order, after the snapshot: a row that
//   remove      {id}                appeared or went away in that block,
//   head        {head}              then the block's head: the changes before it apply together,
//                                   and the copy is now as of that block
//   rewind      {to}                the tables went back to block `to`: a new snapshot follows
// A snapshot is read and written in one synchronous run, so nothing falls between its pages; one
// is sent at the start of a stream, and at the first served block after a rewind or any state but
// `ok`. Changes are published only for served blocks (the `served` listener of the Indexer, called
// after the block's check), read from the tables between the previously served block and the new
// one. Rows: a lot (queries.ts, `Lot`), id its lot id; an adventurer `{adventurer}`, id its number
// as text; an invitation (`Invitation`), id its trade id. Invitations also go away by block time
// alone (10 minutes after their block): each served block's set is compared with the one before.
//
// Bounded: at most `perProcess` subscriptions, and `perClient` from one remote address (an HTTP/1.1
// connection carries one stream, so the cap per connection is kept per address). A subscriber whose
// unsent output passes `maxBuffered` bytes (it stops reading) is dropped: its stream is destroyed,
// which the client library reads as the end of its copy (R4).
import { headOf, type Header } from "./chain.ts";
import type { Indexer, Status } from "./indexer.ts";
import { Queries, type Invitation, type Lot } from "./queries.ts";

export type Topic =
  | { kind: "lots"; key: bigint; size: number }
  | { kind: "presence"; hub: number }
  | { kind: "invitations"; account: number };

/** Where a stream's frames go: an HTTP response in the server, an array in the tests. */
export type Sink = {
  write(chunk: string): void;
  /** Bytes written and not yet sent. */
  buffered(): number;
  /** Ends the stream at once (a slow consumer, or the process stopping). */
  destroy(): void;
};

export type Limits = {
  perProcess: number;
  perClient: number;
  maxBuffered: number;
  page: number;
};

export const DEFAULT_LIMITS: Limits = {
  perProcess: 1000,
  perClient: 16,
  maxBuffered: 16 * 2 ** 20,
  page: 1000,
};

type Subscription = {
  topic: Topic;
  sink: Sink;
  client: string;
  /** A snapshot is due at the next served block (start, rewind, a state but `ok`). */
  stale: boolean;
  /** Invitations: the ids sent, to compare with the next block's set. */
  sent: Map<string, Invitation>;
};

export const frame = (event: string, data: unknown) =>
  `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;

export class Subscriptions {
  private readonly indexer: Indexer;
  private readonly queries: Queries;
  readonly limits: Limits;
  private readonly all = new Set<Subscription>();
  private readonly log: (message: string) => void;
  /** Subscribers dropped for not reading, since the start. */
  dropped = 0;
  private readonly unlisten: () => void;

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
      served: (previous, next) => this.served(previous, next),
      rewound: (to) => this.rewound(to),
      status: (status, reason) => this.status(status, reason),
    });
  }

  get size(): number {
    return this.all.size;
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

  /**
   * Opens a subscription (the caller checked `refusal` first): a snapshot now if a block is
   * served, else the state; returns its closing.
   */
  open(topic: Topic, sink: Sink, client: string): () => void {
    const subscription: Subscription = {
      topic,
      sink,
      client,
      stale: true,
      sent: new Map(),
    };
    this.all.add(subscription);
    const served = this.indexer.served;
    if (this.indexer.status === "ok" && served)
      this.snapshot(subscription, served);
    else
      this.write(
        subscription,
        frame(
          "status",
          this.statusOf(this.indexer.status, this.indexer.reason),
        ),
      );
    return () => this.all.delete(subscription);
  }

  /** Ends every stream (the process stops). */
  close() {
    this.unlisten();
    for (const subscription of this.all) subscription.sink.destroy();
    this.all.clear();
  }

  private statusOf(status: Status, reason: string) {
    return { status, ...(reason ? { reason } : {}) };
  }

  /** Writes, then drops the subscriber if its unsent output passed the cap. False once dropped. */
  private write(subscription: Subscription, chunk: string): boolean {
    if (!this.all.has(subscription)) return false;
    subscription.sink.write(chunk);
    if (subscription.sink.buffered() > this.limits.maxBuffered) {
      this.all.delete(subscription);
      this.dropped++;
      this.log(
        `a subscriber of ${describe(subscription.topic)} dropped: ${subscription.sink.buffered()} bytes unsent`,
      );
      subscription.sink.destroy();
      return false;
    }
    return true;
  }

  private status(status: Status, reason: string) {
    if (status === "ok") return;
    for (const subscription of [...this.all]) {
      subscription.stale = true;
      this.write(subscription, frame("status", this.statusOf(status, reason)));
    }
  }

  private rewound(to: number) {
    for (const subscription of [...this.all]) {
      subscription.stale = true;
      this.write(subscription, frame("rewind", { to }));
    }
  }

  private served(previous: Header | null, next: Header) {
    for (const subscription of [...this.all]) {
      if (subscription.stale || !previous) this.snapshot(subscription, next);
      else this.changes(subscription, previous, next);
    }
  }

  /** A complete snapshot as of `block`, in one synchronous run. */
  private snapshot(subscription: Subscription, block: Header) {
    const head = headOf(block);
    const rows = this.rows(subscription, block);
    const total = rows.total;
    if (!this.write(subscription, frame("reset-begin", { head, total })))
      return;
    for (const page of rows.pages) {
      if (!this.write(subscription, frame("reset-page", { rows: page })))
        return;
    }
    if (this.write(subscription, frame("reset-end", { head, total })))
      subscription.stale = false;
  }

  private rows(
    subscription: Subscription,
    block: Header,
  ): { total: number; pages: Iterable<unknown[]> } {
    const { topic } = subscription;
    const page = this.limits.page;
    const at = block.number;
    switch (topic.kind) {
      case "lots": {
        const total = this.queries.lotCount(at, topic.key, topic.size);
        return {
          total,
          pages: this.queries.lotPages(at, topic.key, topic.size, page),
        };
      }
      case "presence": {
        const queries = this.queries;
        const { count } = queries.presence(at, topic.hub, 0);
        return {
          total: count,
          pages: (function* () {
            let after = -1;
            for (;;) {
              const { adventurers } = queries.presence(
                at,
                topic.hub,
                page,
                after,
              );
              if (adventurers.length === 0) return;
              yield adventurers.map((adventurer) => ({ adventurer }));
              after = adventurers[adventurers.length - 1]!;
              if (adventurers.length < page) return;
            }
          })(),
        };
      }
      case "invitations": {
        const { invitations } = this.queries.invitations(block, topic.account);
        subscription.sent = new Map(
          invitations.map((invitation) => [invitation.trade, invitation]),
        );
        const pages: Invitation[][] = [];
        for (let i = 0; i < invitations.length; i += page)
          pages.push(invitations.slice(i, i + page));
        return { total: invitations.length, pages };
      }
    }
  }

  /** The changes of every block of `(previous, next]`, each followed by its head, in block order. */
  private changes(subscription: Subscription, previous: Header, next: Header) {
    const { topic } = subscription;
    const perBlock = new Map<number, { added: unknown[]; removed: string[] }>();
    if (topic.kind === "lots") {
      const changes = this.queries.lotChanges(
        topic.key,
        topic.size,
        previous.number,
        next.number,
      );
      for (const [block, { added, removed }] of changes)
        perBlock.set(block, { added: added as Lot[], removed });
    } else if (topic.kind === "presence") {
      const changes = this.queries.presenceChanges(
        topic.hub,
        previous.number,
        next.number,
      );
      for (const [block, { added, removed }] of changes) {
        perBlock.set(block, {
          added: added.map((adventurer) => ({ adventurer })),
          removed: removed.map(String),
        });
      }
    } else {
      // By block time as well as by events: every block's set, compared with the one before.
      for (let number = previous.number + 1; number <= next.number; number++) {
        const block =
          number === next.number ? next : this.indexer.store.block(number);
        if (!block) continue;
        const now = new Map(
          this.queries
            .invitations(block, topic.account)
            .invitations.map((invitation) => [invitation.trade, invitation]),
        );
        const added = [...now.values()].filter(
          (invitation) => !subscription.sent.has(invitation.trade),
        );
        const removed = [...subscription.sent.keys()].filter(
          (trade) => !now.has(trade),
        );
        subscription.sent = now;
        if (added.length || removed.length)
          perBlock.set(number, { added, removed });
      }
    }
    let last = previous.number;
    for (const [number, { added, removed }] of [...perBlock].sort(
      ([a], [b]) => a - b,
    )) {
      for (const id of removed)
        if (!this.write(subscription, frame("remove", { id }))) return;
      for (const row of added)
        if (!this.write(subscription, frame("add", { row }))) return;
      const block =
        number === next.number ? next : this.indexer.store.block(number);
      if (!this.write(subscription, frame("head", { head: headOf(block) })))
        return;
      last = number;
    }
    if (last !== next.number)
      this.write(subscription, frame("head", { head: headOf(next) }));
  }
}

function describe(topic: Topic): string {
  switch (topic.kind) {
    case "lots":
      return `lots ${topic.key}/${topic.size}`;
    case "presence":
      return `presence of hub ${topic.hub}`;
    case "invitations":
      return `invitations of ${topic.account}`;
  }
}
