// The client's copies of the subscriptions (R4): the open lots of a market key and lot size, a
// hub's presence, an account's invitations.
// - `connect()` opens the stream, which the cache owns. Whatever ends it (the caller, the server,
//   the network, a drop for not reading) makes the cache not `ready`.
// - It becomes ready only at the end of a complete snapshot (`reset-begin`, the pages, `reset-end`
//   with the announced total and head, the rows received counting that total). A `status` (the
//   indexer is not `ok`) or a `rewind` makes it not ready until the next complete snapshot.
// - Once ready, a block's changes (`add`, `remove`) are held, and applied together with the block's
//   `head`: rows and head never disagree.
// - `read()` is the only way to the rows: it takes the rows and their head together, then passes
//   the head through R3 (client.ts); a cache that is not ready, or whose head fails the rule,
//   answers "not fresh".
import type { Checked, IndexerClient } from "./client.ts";
import type { Frame, Head, Invitation, Lot } from "./protocol.ts";
import { canonical } from "./protocol.ts";

type Query = Record<string, string | number>;

export class StreamCache<Row> {
  readonly client: IndexerClient;
  readonly path: string;
  readonly query: Query;
  private readonly idOf: (row: Row) => string;
  private readonly order: (a: Row, b: Row) => number;
  private rows = new Map<string, Row>();
  private staging: {
    rows: Map<string, Row>;
    head: Head;
    total: number;
  } | null = null;
  private held: (() => void)[] = [];
  head: Head | null = null;
  ready = false;
  /** `disconnected`, `connecting`, the indexer's state, or `ok` once ready. */
  status = "disconnected";

  constructor(
    client: IndexerClient,
    path: string,
    query: Query,
    idOf: (row: Row) => string,
    order: (a: Row, b: Row) => number,
  ) {
    this.client = client;
    this.path = path;
    this.query = query;
    this.idOf = idOf;
    this.order = order;
  }

  /**
   * Opens the stream; returns `close`, which resolves once it has ended. `onEnd` is told why it
   * ended (null: closed by its owner).
   */
  connect(
    onFrame?: (frame: Frame) => void,
    onEnd?: (error: Error | null) => void,
  ): () => Promise<void> {
    const controller = new AbortController();
    this.forget("connecting");
    const done = this.client
      .stream(
        this.path,
        this.query,
        (frame) => {
          this.receive(frame);
          onFrame?.(frame);
        },
        controller.signal,
      )
      .then(
        () => onEnd?.(controller.signal.aborted ? null : new Error("ended")),
        (error: Error) => onEnd?.(error),
      )
      .finally(() => this.forget("disconnected"));
    return async () => {
      controller.abort();
      await done;
    };
  }

  private forget(status: string) {
    this.ready = false;
    this.staging = null;
    this.held = [];
    this.status = status;
  }

  /** Applies one frame of the stream (connect() calls it; public for the tests). */
  receive(frame: Frame) {
    switch (frame.event) {
      case "status":
        this.forget(frame.data.status);
        return;
      case "rewind":
        this.forget("rewinding");
        return;
      case "reset-begin":
        this.forget(this.status);
        this.staging = {
          rows: new Map(),
          head: frame.data.head,
          total: frame.data.total,
        };
        return;
      case "reset-page":
        if (!this.staging) return;
        for (const row of frame.data.rows as Row[])
          this.staging.rows.set(this.idOf(row), row);
        return;
      case "reset-end": {
        const staging = this.staging;
        this.staging = null;
        if (!staging) return;
        const complete =
          staging.total === frame.data.total &&
          staging.rows.size === frame.data.total &&
          sameHead(staging.head, frame.data.head);
        if (!complete) {
          this.forget("incomplete snapshot");
          return;
        }
        this.rows = staging.rows;
        this.head = staging.head;
        this.ready = true;
        this.status = "ok";
        return;
      }
      case "add": {
        if (!this.ready) return;
        const row = frame.data.row as Row;
        this.held.push(() => this.rows.set(this.idOf(row), row));
        return;
      }
      case "remove": {
        if (!this.ready) return;
        const id = frame.data.id;
        this.held.push(() => this.rows.delete(id));
        return;
      }
      case "head": {
        if (!this.ready) return;
        for (const apply of this.held) apply();
        this.held = [];
        this.head = frame.data.head;
        return;
      }
    }
  }

  /** The rows, in order, with their head, if the cache is ready and the head passes R3. */
  async read(): Promise<Checked<{ head: Head; rows: Row[] }>> {
    if (!this.ready || !this.head)
      return { fresh: false, reason: `cache ${this.status}` };
    const head = this.head;
    const rows = [...this.rows.values()].sort(this.order);
    const verdict = await this.client.verify(head);
    return verdict === null
      ? { fresh: true, answer: { head, rows } }
      : { fresh: false, reason: verdict };
  }

  /** How many rows the cache holds, checked or not: tests only. */
  size(): number {
    return this.rows.size;
  }
}

function sameHead(a: Head, b: Head): boolean {
  return (
    a.number === b.number &&
    a.hash === b.hash &&
    a.commitments === b.commitments
  );
}

const compareDecimal = (a: string, b: string) => {
  const x = BigInt(a);
  const y = BigInt(b);
  return x < y ? -1 : x > y ? 1 : 0;
};

/** Q1's order: price, then lot id. */
export const byPriceThenLot = (a: Lot, b: Lot) =>
  compareDecimal(a.price, b.price) || compareDecimal(a.lot, b.lot);

/** The open lots of a market key and lot size, cheapest first (`/subscribe/lots`). */
export class LotCache extends StreamCache<Lot> {
  constructor(client: IndexerClient, key: string | bigint, size: number) {
    super(
      client,
      "/subscribe/lots",
      {
        key: typeof key === "bigint" ? `0x${key.toString(16)}` : canonical(key),
        size,
      },
      (lot) => lot.lot,
      byPriceThenLot,
    );
  }
}

/** The adventurers in a hub, by id (`/subscribe/presence`). */
export class PresenceCache extends StreamCache<{ adventurer: number }> {
  constructor(client: IndexerClient, hub: number) {
    super(
      client,
      "/subscribe/presence",
      { hub },
      (row) => String(row.adventurer),
      (a, b) => a.adventurer - b.adventurer,
    );
  }
}

/** The open invitations of an account under 10 minutes old, by trade id (`/subscribe/invitations`). */
export class InvitationCache extends StreamCache<Invitation> {
  constructor(client: IndexerClient, account: number) {
    super(
      client,
      "/subscribe/invitations",
      { account },
      (invitation) => invitation.trade,
      (a, b) => compareDecimal(a.trade, b.trade),
    );
  }
}
