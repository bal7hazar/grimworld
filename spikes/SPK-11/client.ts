// SPK-11: the game client's side of the indexer: the cheapest open lots of an item, the hub
// presence count, and the lots subscription of an item, over server-sent events. A browser would
// use `EventSource`; Node reads the same stream with `fetch`.
//
// Freshness rule (research §4): the client never shows an indexer answer its own node contradicts.
// An answer is accepted only if
//   1. the indexer says `ok` (not `loading`, `rewinding` or `halted`: those answer 503, no rows);
//   2. the client's node still has the answer's head block, with the same hash and commitments;
//   3. that block is at most `maxLag` blocks below the node's tip.
// The node is read AFTER the answer, so a reorg that happened before the answer is always seen.
// Otherwise the screen says "loading" and the client asks again. The contract stays authoritative:
// acting on an accepted lot that a later reorg removed reverts (`buy`: 'lot not open').
export type Head = { number: number; hash: string; commitments: string } | null;
export type BlockId = NonNullable<Head>;
export type Lot = { lot: string; item: number; quantity: number; price: string; block: number };
export type LotEvent =
  | { type: "status"; data: { status: string; reason?: string } }
  | { type: "reset"; data: { head: Head; lots: Lot[] } }
  | { type: "posted"; data: Lot & { block: BlockId } }
  | { type: "closed"; data: { lot: string; item: number; sold: boolean; block: BlockId } }
  | { type: "rewind"; data: { to: number; head: Head; retracted: string[] } }
  | { type: "head"; data: BlockId };
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

  /** Rules 2 and 3 for one head. */
  async verify(head: NonNullable<Head>): Promise<string> {
    const block = await this.node("starknet_getBlockWithTxHashes", { block_id: { block_number: head.number } });
    if (!block) return `block ${head.number} is gone`;
    const commitments = [block.transaction_commitment, block.event_commitment, block.receipt_commitment, block.state_diff_commitment].join(",");
    if (block.block_hash !== head.hash || commitments !== head.commitments) return `block ${head.number} was replaced`;
    const tip = await this.node("starknet_blockHashAndNumber", []);
    if (tip.block_number - head.number > this.maxLag) return `indexer ${tip.block_number - head.number} blocks behind`;
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

/**
 * The open lots of one item, kept from the subscription. It is rebuilt from every `reset` (sent on
 * each connection and after each rewind) and patched only by the `posted`/`closed` events that
 * follow a reset on the same connection. Until the first reset of a connection it is not `ready`,
 * and a disconnection makes it not ready again: nothing survives a reconnection but a new snapshot.
 */
export class LotCache {
  lots = new Map<string, Lot>();
  head: Head = null;
  ready = false;
  status = "loading";

  apply(event: LotEvent) {
    if (event.type === "status") {
      this.status = event.data.status;
      this.ready = false;
    } else if (event.type === "reset") {
      this.status = "ok";
      this.lots = new Map(event.data.lots.map((lot) => [lot.lot, lot]));
      this.head = event.data.head;
      this.ready = true;
    } else if (event.type === "rewind") {
      this.ready = false; // a reset follows
    } else if (this.ready && event.type === "head") {
      this.head = event.data;
    } else if (this.ready && event.type === "posted") {
      const { block, ...lot } = event.data;
      this.lots.set(lot.lot, { ...lot, block: block.number });
      this.head = block;
    } else if (this.ready && event.type === "closed") {
      this.lots.delete(event.data.lot);
      this.head = event.data.block;
    }
  }

  disconnected() {
    this.ready = false;
  }

  /** Open lots, cheapest first, ties by lot id (numeric). */
  sorted(): Lot[] {
    return [...this.lots.values()].sort((a, b) => {
      const byPrice = BigInt(a.price) - BigInt(b.price);
      return byPrice !== 0n ? (byPrice < 0n ? -1 : 1) : BigInt(a.lot) < BigInt(b.lot) ? -1 : BigInt(a.lot) > BigInt(b.lot) ? 1 : 0;
    });
  }
}
