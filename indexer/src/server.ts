// Serving: `GET /head`, `GET /stats` (IDX-01a), the queries Q1 to Q5 and Q7, and the subscriptions
// (IDX-01b; README has the routes and their parameters).
// R1: in the states `loading`, `rewinding` and `halted` every query answers 503 with the state (and
// the reason), never rows. R2: every answer, errors included, carries `head {number, hash,
// commitments, timestamp}`, the served block it is read at (null while none is served). R6: rows
// are read as of the served block, and an answer is kept for that block only (by hash and
// commitments): the cache empties when another block is served and at every rewind.
// Every parameter is checked before anything is read: an unknown route is 404, a missing, unknown,
// repeated or malformed parameter 400, each with the head. Nothing a client sends stops the process:
// a target that is not a path is 400, an exception while answering is 500.
import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";
import { headOf, sameBlock, type Header } from "./chain.ts";
import {
  DecodeError,
  decodeMarketKey,
  felt,
  type MarketKey,
} from "./events.ts";
import type { Indexer } from "./indexer.ts";
import { Queries, type LotCursor } from "./queries.ts";
import {
  Subscriptions,
  type Limits,
  type Sink,
  type Topic,
} from "./subscriptions.ts";

export { headOf };

export type Answer = { code: number; body: Record<string, unknown> };

const started = Date.now();

/** Page sizes: the default, and the cap. */
export const LIMIT = { default: 20, max: 100 };
/** The most adventurers of one Q5 question, and of item ids of one Q2 question. */
export const MAX_LIST = 100;

class BadRequest extends Error {}

/** An error answer: the error, the state and the served head. */
function refusal(indexer: Indexer, code: number, error: string): Answer {
  return {
    code,
    body: { error, status: indexer.status, head: headOf(indexer.served) },
  };
}

// --- parameters ----------------------------------------------------------------------------------

type Parameters = Record<string, string | undefined>;

/** The parameters of `url`: only the allowed names, each at most once, the required ones present. */
function parameters(
  url: URL,
  required: readonly string[],
  optional: readonly string[] = [],
): Parameters {
  const allowed = new Set([...required, ...optional]);
  const result: Parameters = {};
  for (const [name, value] of url.searchParams) {
    if (!allowed.has(name)) throw new BadRequest(`unknown parameter ${name}`);
    if (result[name] !== undefined)
      throw new BadRequest(`parameter ${name} given twice`);
    result[name] = value;
  }
  for (const name of required) {
    if (result[name] === undefined)
      throw new BadRequest(`parameter ${name} is required`);
  }
  return result;
}

/** A whole number in `[min, max]`, decimal, without sign or leading zeros. */
function integer(
  value: string | undefined,
  name: string,
  min: number,
  max: number,
): number {
  if (value === undefined || !/^(0|[1-9]\d{0,15})$/.test(value))
    throw new BadRequest(`${name} must be a whole number`);
  const number = Number(value);
  if (number < min || number > max)
    throw new BadRequest(`${name} must be from ${min} to ${max}`);
  return number;
}

const U32_MAX = 2 ** 32 - 1;
const U64_MAX = 2n ** 64n - 1n;

function u64(value: string, name: string): bigint {
  if (!/^(0|[1-9]\d{0,19})$/.test(value) || BigInt(value) > U64_MAX)
    throw new BadRequest(`${name} must be a u64`);
  return BigInt(value);
}

/** A market key: a felt252 as 0x hex, one of ENG-01's encodings (events.ts, rarity < 128). */
function marketKey(value: string | undefined, name = "key"): bigint {
  let key: bigint;
  try {
    key = felt(value);
    decodeMarketKey(key);
  } catch (error) {
    if (error instanceof DecodeError)
      throw new BadRequest(`${name} must be a market key, as 0x hex`);
    throw error;
  }
  return key;
}

const limitOf = (value: string | undefined) =>
  value === undefined ? LIMIT.default : integer(value, "limit", 1, LIMIT.max);

/** A comma-separated list of 1 to MAX_LIST u32 values, without repeats. */
function u32List(value: string | undefined, name: string): number[] {
  const parts = (value ?? "").split(",");
  if (parts.length > MAX_LIST)
    throw new BadRequest(`${name}: at most ${MAX_LIST}`);
  const list = parts.map((part) => integer(part, name, 0, U32_MAX));
  if (new Set(list).size !== list.length)
    throw new BadRequest(`${name}: a value given twice`);
  return list;
}

/** Q1's cursor: `<price>:<lot>` of the last lot of the page before. */
function lotCursor(value: string | undefined): LotCursor | undefined {
  if (value === undefined) return undefined;
  const [price, lot, ...rest] = value.split(":");
  if (price === undefined || lot === undefined || rest.length > 0)
    throw new BadRequest("after must be <price>:<lot>");
  return { price: u64(price, "after"), lot: u64(lot, "after") };
}

const KINDS: readonly MarketKey["kind"][] = ["balance", "equipment", "boss"];

// --- routes --------------------------------------------------------------------------------------

type Read = (queries: Queries, served: Header) => Record<string, unknown>;

/** The route of a query: its parameters checked, and the read to make as of the served block. */
function route(url: URL): Read | null {
  switch (url.pathname) {
    case "/lots": {
      // Q1
      const p = parameters(url, ["key", "size"], ["limit", "after"]);
      const key = marketKey(p.key);
      const size = integer(p.size, "size", 1, 255);
      const limit = limitOf(p.limit);
      const after = lotCursor(p.after);
      return (queries, served) => {
        const { total, lots } = queries.lots(
          served.number,
          key,
          size,
          limit,
          after,
        );
        const last = lots[lots.length - 1];
        const next =
          last && lots.length === limit ? `${last.price}:${last.lot}` : null;
        return { total, lots, next };
      };
    }
    case "/market": {
      // Q2
      const p = parameters(url, ["kind"], ["items", "limit", "after"]);
      const kind = p.kind as MarketKey["kind"];
      if (!KINDS.includes(kind))
        throw new BadRequest(`kind must be one of ${KINDS.join(", ")}`);
      if (p.items !== undefined && kind !== "balance")
        throw new BadRequest("items is for kind=balance only");
      const items =
        p.items === undefined ? undefined : u32List(p.items, "items");
      const limit = limitOf(p.limit);
      const after =
        p.after === undefined ? undefined : marketKey(p.after, "after");
      return (queries, served) =>
        queries.market(served.number, kind, limit, after, items);
    }
    case "/prices": {
      // Q3
      const p = parameters(url, ["key", "size"]);
      const key = marketKey(p.key);
      const size = integer(p.size, "size", 1, 255);
      return (queries, served) => queries.price(served, key, size);
    }
    case "/hubs/presence": {
      // Q4
      const p = parameters(url, ["hub"], ["limit", "after"]);
      const hub = integer(p.hub, "hub", 1, 0xffff);
      const limit = limitOf(p.limit);
      const after =
        p.after === undefined ? -1 : integer(p.after, "after", 0, U32_MAX);
      return (queries, served) => {
        const { count, adventurers } = queries.presence(
          served.number,
          hub,
          limit,
          after,
        );
        const next =
          adventurers.length === limit
            ? String(adventurers[adventurers.length - 1])
            : null;
        return { hub, count, adventurers, next };
      };
    }
    case "/titles": {
      // Q5
      const p = parameters(url, ["adventurers"]);
      const adventurers = u32List(p.adventurers, "adventurers");
      return (queries, served) => ({
        titles: queries.titles(served.number, adventurers),
      });
    }
    case "/invitations": {
      // Q7
      const p = parameters(url, ["account"], ["limit", "after"]);
      const account = integer(p.account, "account", 0, U32_MAX);
      const limit = limitOf(p.limit);
      const after = p.after === undefined ? undefined : u64(p.after, "after");
      return (queries, served) => {
        const { total, invitations } = queries.invitations(
          served,
          account,
          limit,
          after,
        );
        const next =
          invitations.length === limit
            ? invitations[invitations.length - 1]!.trade
            : null;
        return { account, total, invitations, next };
      };
    }
    default:
      return null;
  }
}

/** The topic of a subscription route, its parameters checked; null if `url` is none. */
export function topicOf(url: URL): Topic | null {
  switch (url.pathname) {
    case "/subscribe/lots": {
      const p = parameters(url, ["key", "size"]);
      return {
        kind: "lots",
        key: marketKey(p.key),
        size: integer(p.size, "size", 1, 255),
      };
    }
    case "/subscribe/presence": {
      const p = parameters(url, ["hub"]);
      return { kind: "presence", hub: integer(p.hub, "hub", 1, 0xffff) };
    }
    case "/subscribe/invitations": {
      const p = parameters(url, ["account"]);
      return {
        kind: "invitations",
        account: integer(p.account, "account", 0, U32_MAX),
      };
    }
    default:
      return null;
  }
}

// --- R6: answers kept for the served block ---------------------------------------------------------

/** The rows of the answers read at one served block, by target; emptied at every rewind. */
class AnswerCache {
  static readonly MAX = 1000;
  private block: Header | null = null;
  private readonly answers = new Map<string, Record<string, unknown>>();
  readonly queries: Queries;
  hits = 0;
  misses = 0;

  constructor(indexer: Indexer) {
    this.queries = new Queries(indexer.store);
    indexer.listen({ rewound: () => this.clear() });
  }

  clear() {
    this.block = null;
    this.answers.clear();
  }

  read(served: Header, target: string, read: Read): Record<string, unknown> {
    if (!this.block || !sameBlock(this.block, served)) {
      this.clear();
      this.block = served;
    }
    const kept = this.answers.get(target);
    if (kept) {
      this.hits++;
      return kept;
    }
    this.misses++;
    const rows = read(this.queries, served);
    if (this.answers.size >= AnswerCache.MAX)
      this.answers.delete(this.answers.keys().next().value!);
    this.answers.set(target, rows);
    return rows;
  }
}

const caches = new WeakMap<Indexer, AnswerCache>();
function cacheOf(indexer: Indexer): AnswerCache {
  let cache = caches.get(indexer);
  if (!cache) {
    cache = new AnswerCache(indexer);
    caches.set(indexer, cache);
  }
  return cache;
}

// --- answers -------------------------------------------------------------------------------------

/** The answer to a GET of `target`, a path and its query (the HTTP server's, without the socket). */
export function answer(
  indexer: Indexer,
  target: string,
  subscriptions?: Subscriptions,
): Answer {
  const url = new URL(target, "http://indexer");
  const path = url.pathname;
  if (path !== "/head" && path !== "/stats") {
    let read: Read | null;
    try {
      read = route(url);
      if (!read && topicOf(url))
        return refusal(
          indexer,
          406,
          "a subscription: accept text/event-stream",
        );
    } catch (error) {
      if (error instanceof BadRequest)
        return refusal(indexer, 400, error.message);
      throw error;
    }
    if (!read) return refusal(indexer, 404, "not found");
    const served = indexer.served;
    if (indexer.status !== "ok" || !served) {
      const body: Record<string, unknown> = {
        status: indexer.status,
        reason: indexer.reason || undefined,
        head: headOf(served),
      };
      return { code: 503, body };
    }
    const rows = cacheOf(indexer).read(served, `${path}${url.search}`, read);
    return {
      code: 200,
      body: {
        status: "ok",
        head: headOf(served),
        behind: Math.max(0, indexer.chainTip - served.number),
        ...rows,
      },
    };
  }
  const head = headOf(indexer.served);
  const cache = cacheOf(indexer);
  const process_ = {
    blocksApplied: indexer.blocksApplied,
    eventsApplied: indexer.eventsApplied,
    rewindCount: indexer.rewindCount,
    rewinds: indexer.rewinds,
    rpcCalls: { ...indexer.chain.calls },
    subscriptions: subscriptions?.size ?? 0,
    subscribersDropped: subscriptions?.dropped ?? 0,
    answerCache: { hits: cache.hits, misses: cache.misses },
    rssMB: Math.round(process.memoryUsage().rss / 2 ** 20),
    maxRssMB: Math.round(process.resourceUsage().maxRSS / 1024),
    uptimeMs: Date.now() - started,
  };
  if (indexer.status !== "ok" || !indexer.served) {
    const body: Record<string, unknown> = {
      status: indexer.status,
      reason: indexer.reason || undefined,
      head,
    };
    // The process's own figures, never rows.
    if (path === "/stats") Object.assign(body, process_);
    return { code: 503, body };
  }
  const served = indexer.served;
  const behind = Math.max(0, indexer.chainTip - served.number);
  if (path === "/head")
    return { code: 200, body: { status: "ok", head, behind } };
  return {
    code: 200,
    body: {
      status: "ok",
      head,
      behind,
      stored: headOf(indexer.store.tip()),
      lowest: indexer.store.lowest()?.number ?? null,
      tables: indexer.store.countsAt(served.number),
      versions: indexer.store.rows(),
      ...process_,
    },
  };
}

/** Whether `target` is a path this server can parse (else 400). */
function parsable(target: string | undefined): target is string {
  return (
    target !== undefined &&
    target.startsWith("/") &&
    URL.canParse(target, "http://indexer")
  );
}

/** The answer to a request: 405 unless GET, 400 for a target that is not a path, 500 on a throw. */
export function respond(
  indexer: Indexer,
  method: string | undefined,
  target: string | undefined,
  subscriptions?: Subscriptions,
): Answer {
  try {
    if (method !== "GET") return refusal(indexer, 405, "GET only");
    const raw = target ?? "/";
    if (!parsable(raw)) return refusal(indexer, 400, "bad request");
    return answer(indexer, raw, subscriptions);
  } catch {
    return refusal(indexer, 500, "internal error");
  }
}

function send(response: ServerResponse, result: Answer) {
  response.writeHead(result.code, {
    "content-type": "application/json",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(result.body));
}

/**
 * Opens the stream of a subscription route: 400 on a bad parameter, 429 over a cap, else a
 * server-sent event stream (subscriptions.ts). True if `target` was a subscription route.
 */
function stream(
  indexer: Indexer,
  subscriptions: Subscriptions,
  request: IncomingMessage,
  response: ServerResponse,
): boolean {
  if (request.method !== "GET" || !parsable(request.url)) return false;
  const url = new URL(request.url, "http://indexer");
  let topic: Topic | null;
  try {
    topic = topicOf(url);
  } catch (error) {
    if (!(error instanceof BadRequest)) throw error;
    send(response, refusal(indexer, 400, error.message));
    return true;
  }
  if (!topic) return false;
  const client = request.socket.remoteAddress ?? "";
  const refused = subscriptions.refusal(client);
  if (refused) {
    send(response, refusal(indexer, 429, refused));
    return true;
  }
  response.writeHead(200, {
    "content-type": "text/event-stream",
    "cache-control": "no-store",
    connection: "keep-alive",
  });
  response.flushHeaders();
  const sink: Sink = {
    write: (chunk) => void response.write(chunk),
    buffered: () => response.writableLength,
    destroy: () => response.destroy(),
  };
  const close = subscriptions.open(topic, sink, client);
  response.on("close", close);
  return true;
}

export type ServeOptions = {
  limits?: Partial<Limits>;
  log?: (message: string) => void;
};

/** The HTTP server; `server.subscriptions` holds its streams, ended when the server closes. */
export function serve(
  indexer: Indexer,
  options: ServeOptions = {},
): Server & { subscriptions: Subscriptions } {
  const subscriptions = new Subscriptions(indexer, options.limits, options.log);
  const server = createServer(
    (request: IncomingMessage, response: ServerResponse) => {
      try {
        if (stream(indexer, subscriptions, request, response)) return;
      } catch {
        if (!response.headersSent)
          send(response, refusal(indexer, 500, "internal error"));
        else response.destroy();
        return;
      }
      let result: Answer;
      try {
        result = respond(indexer, request.method, request.url, subscriptions);
      } catch {
        result = { code: 500, body: { error: "internal error", head: null } };
      }
      send(response, result);
    },
  );
  server.on("close", () => subscriptions.close());
  return Object.assign(server, { subscriptions });
}
