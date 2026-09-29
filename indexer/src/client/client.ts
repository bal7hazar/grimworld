// The client's side of the indexer (IDX-01b): its queries, each passed through the freshness rule,
// and its streams (caches.ts keeps them).
//
// R3, the freshness rule (SPK-11 §4), in this order:
//   1. the indexer's answer: `ok` (503 `loading`, `rewinding`, `halted` carry no rows) and its head;
//   2. then the node's tip: the head at most `maxLag` (5) blocks below it;
//   3. then, LAST, the node's block at the head's number: the same hash and the same commitments.
// The guarantee is as of that last read: then the client's node held the answer's block, so the
// answer was a state of the node's chain. A reorg after it is not seen: the contract stays
// authoritative (R5). Otherwise the answer is refused ("loading"): the screen says so and the
// client asks again.
import type {
  Frame,
  Head,
  InvitationsAnswer,
  LotsAnswer,
  MarketAnswer,
  MarketKey,
  PresenceAnswer,
  PriceAnswer,
  TitlesAnswer,
} from "./protocol.ts";
import { canonical } from "./protocol.ts";
import { jsonRpcReader, type NodeReader } from "./reader.ts";

/** An answer the freshness rule accepted, or the reason it did not ("loading"). */
export type Checked<T> =
  { fresh: true; answer: T } | { fresh: false; reason: string };

export type ClientOptions = {
  /** The indexer's base URL (`http://host:port`). */
  url: string;
  /** The client's node: a JSON-RPC URL (read methods only), or a reader of its own. */
  node: string | NodeReader;
  /** How many blocks below the node's tip an answer may be (R3; default 5). */
  maxLag?: number;
  fetch?: typeof fetch;
};

type Query = Record<string, string | number | bigint | undefined>;

const search = (query: Query) => {
  const parts = Object.entries(query)
    .filter(([, value]) => value !== undefined)
    .map(
      ([name, value]) =>
        `${encodeURIComponent(name)}=${encodeURIComponent(String(value))}`,
    );
  return parts.length ? `?${parts.join("&")}` : "";
};

const hex = (key: string | bigint) =>
  typeof key === "bigint" ? `0x${key.toString(16)}` : canonical(key);

export class IndexerClient {
  readonly url: string;
  readonly node: NodeReader;
  readonly maxLag: number;
  private readonly fetchFn: typeof fetch;

  constructor(options: ClientOptions) {
    this.url = options.url.replace(/\/+$/, "");
    this.fetchFn = options.fetch ?? globalThis.fetch.bind(globalThis);
    this.node =
      typeof options.node === "string"
        ? jsonRpcReader(options.node, this.fetchFn)
        : options.node;
    this.maxLag = options.maxLag ?? 5;
  }

  /** Q1: the open lots of a market key and lot size, cheapest first; `after` from `next`. */
  lots(
    key: string | bigint,
    size: number,
    page: { limit?: number; after?: string } = {},
  ): Promise<Checked<LotsAnswer>> {
    return this.query("/lots", { key: hex(key), size, ...page });
  }

  /** Q2: the market keys of a kind, the cheapest open lot per lot size; `items` for balances. */
  market(
    kind: MarketKey["kind"],
    options: { items?: number[]; limit?: number; after?: string } = {},
  ): Promise<Checked<MarketAnswer>> {
    return this.query("/market", {
      kind,
      items: options.items?.join(","),
      limit: options.limit,
      after: options.after,
    });
  }

  /** Q3: the mean price of the last 7 days' sales of a key and lot size (absent under 5). */
  prices(key: string | bigint, size: number): Promise<Checked<PriceAnswer>> {
    return this.query("/prices", { key: hex(key), size });
  }

  /** Q4: the adventurers in a hub, and their count. */
  presence(
    hub: number,
    page: { limit?: number; after?: string } = {},
  ): Promise<Checked<PresenceAnswer>> {
    return this.query("/hubs/presence", { hub, ...page });
  }

  /** Q5: the displayed title of each adventurer (at most 100). */
  titles(adventurers: number[]): Promise<Checked<TitlesAnswer>> {
    return this.query("/titles", { adventurers: adventurers.join(",") });
  }

  /** Q7: the open invitations of an account under 10 minutes old (block time). */
  invitations(
    account: number,
    page: { limit?: number; after?: string } = {},
  ): Promise<Checked<InvitationsAnswer>> {
    return this.query("/invitations", { account, ...page });
  }

  /** The raw answer of a GET: its HTTP code and body (no rule applied). */
  async raw(
    path: string,
    query: Query = {},
  ): Promise<{ code: number; body: Record<string, unknown> }> {
    const response = await this.fetchFn(`${this.url}${path}${search(query)}`);
    let body: Record<string, unknown>;
    try {
      body = (await response.json()) as Record<string, unknown>;
    } catch {
      body = {};
    }
    return { code: response.status, body };
  }

  private async query<T extends { status: "ok"; head: Head }>(
    path: string,
    query: Query,
  ): Promise<Checked<T>> {
    let answer: { code: number; body: Record<string, unknown> };
    try {
      answer = await this.raw(path, query); // 1. the indexer's answer
    } catch (error) {
      return { fresh: false, reason: `indexer: ${(error as Error).message}` };
    }
    if (answer.code === 400 || answer.code === 404)
      throw new Error(`${path}: ${String(answer.body.error)}`);
    return this.check(answer.body as unknown as T);
  }

  /** Applies R3 to an answer already read (step 1 done): its state, then the tip, then its block. */
  async check<T extends { status: string; head?: Head | null }>(
    answer: T,
  ): Promise<Checked<T>> {
    if (answer.status !== "ok" || !answer.head)
      return { fresh: false, reason: `indexer ${answer.status}` };
    const verdict = await this.verify(answer.head);
    return verdict === null
      ? { fresh: true, answer }
      : { fresh: false, reason: verdict };
  }

  /**
   * Steps 2 and 3 of R3 for `head`: the node's tip, then the node's block at the head's number,
   * last. Null if the head passes, else why not. `between` runs between the two reads (tests).
   */
  async verify(
    head: Head,
    between?: () => Promise<void>,
  ): Promise<string | null> {
    try {
      const tip = await this.node.tip();
      if (tip - head.number > this.maxLag)
        return `indexer ${tip - head.number} blocks behind the node`;
      if (between) await between();
      const block = await this.node.block(head.number);
      if (!block) return `block ${head.number} is not the node's`;
      if (
        canonical(block.hash) !== canonical(head.hash) ||
        block.commitments !== head.commitments
      )
        return `block ${head.number} was replaced`;
      return null;
    } catch (error) {
      return `node: ${(error as Error).message}`;
    }
  }

  /**
   * Reads the stream of a subscription route, frame by frame, until it ends or `signal` aborts.
   * Resolves when it ends; throws if it could not open (a 4xx, 429 over a cap).
   */
  async stream(
    path: string,
    query: Query,
    onFrame: (frame: Frame) => void,
    signal: AbortSignal,
  ): Promise<void> {
    const response = await this.fetchFn(`${this.url}${path}${search(query)}`, {
      headers: { accept: "text/event-stream" },
      signal,
    });
    if (response.status !== 200 || !response.body) {
      let error = "";
      try {
        error = String(
          ((await response.json()) as { error?: unknown }).error ?? "",
        );
      } catch {
        // not JSON
      }
      throw new Error(`${path}: ${response.status} ${error}`.trim());
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) return;
        buffer += decoder.decode(value, { stream: true });
        let end: number;
        while ((end = buffer.indexOf("\n\n")) >= 0) {
          const text = buffer.slice(0, end);
          buffer = buffer.slice(end + 2);
          const frame = parseFrame(text);
          if (frame) onFrame(frame);
        }
      }
    } catch (error) {
      if (!signal.aborted) throw error;
    } finally {
      reader.releaseLock();
    }
  }
}

/** One server-sent event (`event:` and `data:` lines); null for a comment or an unreadable one. */
export function parseFrame(text: string): Frame | null {
  let event = "";
  const data: string[] = [];
  for (const line of text.split("\n")) {
    if (line.startsWith("event:")) event = line.slice(6).trim();
    else if (line.startsWith("data:")) data.push(line.slice(5).trimStart());
  }
  if (!event || data.length === 0) return null;
  try {
    return { event, data: JSON.parse(data.join("\n")) } as Frame;
  } catch {
    return null;
  }
}
