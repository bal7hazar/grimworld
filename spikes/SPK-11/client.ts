// SPK-11: the game client's side of the indexer: the cheapest open lots of an item, the hub
// presence count, and the lots subscription of an item, over server-sent events. A browser would
// use `EventSource`; Node reads the same stream with `fetch`.
//
// Freshness rule (research §4): the client never shows an indexer answer its own node contradicts.
// An answer is accepted only if
//   1. the indexer says `ok` (not `loading`, `rewinding` or `halted`: those answer 503, no rows);
//   2. that block is at most `maxLag` blocks below the node's tip;
//   3. the client's node has the answer's head block, with the same hash and commitments.
// Order: the answer first, then the node's tip, then the answer's block, LAST. The guarantee is as of
// that last read: at that moment the node held the answer's block, so the answer was a state of the
// node's chain then. (Reading the block before the tip, as fix loop 1 did, lets a reorg between the
// two reads pass an orphaned answer: demo.ts shows it.) A reorg after the last read is not seen:
// the contract stays authoritative, and acting on an accepted lot that a later reorg removed
// reverts (`buy`: 'lot not open'). Otherwise the screen says "loading" and the client asks again.
export type Head = { number: number; hash: string; commitments: string } | null;
export type BlockId = NonNullable<Head>;
export type Lot = { lot: string; item: number; quantity: number; price: string; block: number };
export type LotEvent =
  | { type: "status"; data: { status: string; reason?: string } }
  | { type: "reset-begin"; data: { head: Head; total: number } }
  | { type: "reset-page"; data: { lots: Lot[] } }
  | { type: "reset-end"; data: { head: Head; total: number } }
  | { type: "posted"; data: Lot & { block: BlockId } }
  | { type: "closed"; data: { lot: string; item: number; sold: boolean; block: BlockId } }
  | { type: "rewind"; data: { to: number; retracted: string[] } }
  | { type: "head"; data: Head };
export type Checked<T> = { fresh: true; answer: T } | { fresh: false; reason: string };

export class IndexerClient {
  readonly url: string;
  readonly nodeUrl: string;
  readonly maxLag: number;
  constructor(url: string, nodeUrl: string, maxLag = 5) {
    this.url = url;
    this.nodeUrl = nodeUrl;
    this.maxLag = maxLag;
  }

  /** The raw answer: `{status: "ok", head, behind, lots}`, or `{status}` with HTTP 503. */
  async cheapestRaw(item: number, limit = 1): Promise<any> {
    return this.get(`/lots/cheapest?item=${item}&limit=${limit}`);
  }

  /** The cheapest open lots of `item`, cheapest first, ties by lot id; accepted by the freshness rule, or not. */
  async cheapest(item: number, limit = 1): Promise<Checked<{ head: Head; lots: Lot[] }>> {
    return this.check(await this.cheapestRaw(item, limit));
  }

  async presence(hub: number): Promise<Checked<{ head: Head; count: number }>> {
    return this.check(await this.get(`/hubs/presence?hub=${hub}`));
  }

  async head(): Promise<any> {
    return this.get("/head");
  }

  async stats(): Promise<any> {
    return this.get("/stats");
  }

  /** Applies rules 1–3 to a raw answer. */
  async check<T extends { status: string; head?: Head }>(answer: T): Promise<Checked<T>> {
    if (answer.status !== "ok" || !answer.head) return { fresh: false, reason: `indexer ${answer.status}` };
    const verdict = await this.verify(answer.head);
    return verdict === "fresh" ? { fresh: true, answer } : { fresh: false, reason: verdict };
  }

  /**
   * Rules 2 and 3 for one head: the tip first, the head's block last. `between` runs between the two
   * reads (tests only: demo.ts aborts blocks there).
   */
  async verify(head: NonNullable<Head>, between?: () => Promise<void>): Promise<string> {
    const tip = await this.node("starknet_blockHashAndNumber", []);
    if (tip.block_number - head.number > this.maxLag) return `indexer ${tip.block_number - head.number} blocks behind`;
    if (between) await between();
    return this.blockIs(head);
  }

  /** Whether the node has `head`'s block now, by hash and commitments. */
  async blockIs(head: NonNullable<Head>): Promise<string> {
    const block = await this.node("starknet_getBlockWithTxHashes", { block_id: { block_number: head.number } });
    if (!block) return `block ${head.number} is gone`;
    const commitments = [block.transaction_commitment, block.event_commitment, block.receipt_commitment, block.state_diff_commitment].join(",");
    if (block.block_hash !== head.hash || commitments !== head.commitments) return `block ${head.number} was replaced`;
    return "fresh";
  }

  /** Calls `onEvent` for every event of the item's stream until `signal` aborts. */
  async subscribe(item: number, onEvent: (event: LotEvent) => void, signal: AbortSignal): Promise<void> {
    const response = await fetch(`${this.url}/lots/subscribe?item=${item}`, { signal });
    if (!response.ok || !response.body) throw new Error(`subscribe: ${response.status}`);
    const decoder = new TextDecoder();
    let buffer = "";
    try {
      for await (const chunk of response.body) {
        buffer += decoder.decode(chunk, { stream: true });
        let end: number;
        while ((end = buffer.indexOf("\n\n")) >= 0) {
          const frame = buffer.slice(0, end);
          buffer = buffer.slice(end + 2);
          const type = /^event: (.*)$/m.exec(frame)?.[1];
          const data = /^data: (.*)$/m.exec(frame)?.[1];
          if (type && data) onEvent({ type, data: JSON.parse(data) } as LotEvent);
        }
      }
    } catch (error) {
      if (!signal.aborted) throw error;
    }
  }

  private async get(path: string): Promise<any> {
    const response = await fetch(`${this.url}${path}`);
    if (response.status !== 200 && response.status !== 503) throw new Error(`${path}: ${response.status}`);
    return response.json();
  }

  private async node(method: string, params: unknown): Promise<any> {
    const response = await fetch(this.nodeUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    const body = await response.json();
    return body.result ?? null;
  }
}

const byPriceThenLot = (a: Lot, b: Lot) => {
  const byPrice = BigInt(a.price) - BigInt(b.price);
  return byPrice !== 0n ? (byPrice < 0n ? -1 : 1) : BigInt(a.lot) < BigInt(b.lot) ? -1 : BigInt(a.lot) > BigInt(b.lot) ? 1 : 0;
};

/**
 * The open lots of one item, kept from the subscription, which the cache owns.
 * - `connect()` opens the stream. Whatever ends it (the caller, the server, the network) makes
 *   the cache not `ready`: readiness is bound to the stream's life.
 * - It becomes ready only at the end of a complete snapshot (`reset-begin`, the pages,
 *   `reset-end` with the announced total), sent on each connection and after each rewind, and is
 *   patched only by the `posted`/`closed` events that follow it on the same connection.
 * - `read()` is the only way to the lots: it takes the lots and their head together, then passes
 *   the head through the freshness rule; a cache that is not ready, or whose head fails the rule,
 *   answers "not fresh".
 */
export class LotCache {
  readonly client: IndexerClient;
  readonly item: number;
  private lots = new Map<string, Lot>();
  private staging: { lots: Map<string, Lot>; head: Head; total: number } | null = null;
  head: Head = null;
  ready = false;
  status = "disconnected";
  constructor(client: IndexerClient, item: number) {
    this.client = client;
    this.item = item;
  }

  /** Opens the stream; returns `close`, which resolves once the stream has ended. */
  connect(onEvent?: (event: LotEvent) => void): () => Promise<void> {
    const controller = new AbortController();
    this.ready = false;
    this.status = "connecting";
    const done = this.client
      .subscribe(this.item, (event) => {
        this.apply(event);
        onEvent?.(event);
      }, controller.signal)
      .catch(() => undefined)
      .finally(() => {
        this.ready = false;
        this.staging = null;
        this.status = "disconnected";
      });
    return async () => {
      controller.abort();
      await done;
    };
  }

  private apply(event: LotEvent) {
    if (event.type === "status") {
      this.status = event.data.status;
      this.ready = false;
      this.staging = null;
    } else if (event.type === "reset-begin") {
      this.ready = false;
      this.staging = { lots: new Map(), head: event.data.head, total: event.data.total };
    } else if (event.type === "reset-page" && this.staging) {
      for (const lot of event.data.lots) this.staging.lots.set(lot.lot, lot);
    } else if (event.type === "reset-end" && this.staging) {
      const complete = this.staging.lots.size === event.data.total && this.staging.total === event.data.total;
      if (complete) {
        this.lots = this.staging.lots;
        this.head = this.staging.head;
        this.ready = true;
        this.status = "ok";
      }
      this.staging = null;
    } else if (event.type === "rewind") {
      this.ready = false; // a snapshot follows
    } else if (this.ready && event.type === "head") {
      // The events of a block apply together with its head, so lots and head never disagree.
      for (const apply of this.held) apply();
      this.held = [];
      this.head = event.data;
    } else if (this.ready && event.type === "posted") {
      const { block, ...lot } = event.data;
      this.held.push(() => this.lots.set(lot.lot, { ...lot, block: block.number }));
    } else if (this.ready && event.type === "closed") {
      const lot = event.data.lot;
      this.held.push(() => this.lots.delete(lot));
    }
    if (!this.ready) this.held = [];
  }
  private held: (() => unknown)[] = [];

  /** The open lots, cheapest first, ties by lot id, if the cache is ready and its head passes the freshness rule. */
  async read(): Promise<Checked<{ head: Head; lots: Lot[] }>> {
    if (!this.ready || !this.head) return { fresh: false, reason: `cache ${this.status}` };
    const head = this.head;
    const lots = [...this.lots.values()].sort(byPriceThenLot);
    const verdict = await this.client.verify(head);
    return verdict === "fresh" ? { fresh: true, answer: { head, lots } } : { fresh: false, reason: verdict };
  }

  /** How many lots the cache holds, checked or not: tests only. */
  size(): number {
    return this.lots.size;
  }
}
