// SPK-11: an indexer of our own, the candidate the spike recommends
// (docs/research/SPK-11-indexer.md). One Node 24 process, no dependency but starknet.js (for the
// selectors): it follows the chain over JSON-RPC, decodes the Market contract's events, keeps
// tables in SQLite (node:sqlite), serves queries over HTTP and a subscription over server-sent
// events, and rewinds on a reorg.
//
//   INDEXER_RPC_URL=<url> node spikes/SPK-11/indexer.ts --address <contract> --db <file>
//        [--port <n>] [--from <block>] [--poll <ms>] [--rpc-delay <ms>]
//
// The RPC URL comes from the environment only (it may carry a provider's key: never in argv,
// never in a log). The process needs nothing else from its environment; run-indexer.ts starts it
// with exactly that one variable.
//
// Correctness rules (research §4):
// - Serving states. `loading` until the first step has checked the stored tip against the chain;
//   `rewinding` from the moment a divergence is seen until the fork point is served again; `halted`
//   when an invariant fails (research §6). In those states every query answers 503 with the state,
//   never rows. `ok` otherwise.
// - Served block (R6). Queries, snapshots and stream events are read AS OF the served block: the
//   highest stored block whose counter reconciliation passed, keyed by hash and commitments, cleared
//   on every rewind. A block just applied is not served until then; its events wait.
// - Every answer carries `head {number, hash, commitments}`: the block it is consistent with. A
//   client accepts an answer only if its own node still has that block (client.ts, `verify`):
//   between a reorg on the node and the indexer's next step, the indexer cannot know, the client can.
// - Rows are versions valid over [_from, _to) of block numbers; rewinding to F deletes the versions
//   born after F and reopens those closed after F, in one transaction (Apibara's and Checkpoint's
//   scheme). A block is known by its hash AND its commitments (devnet 0.10.0 re-uses the hash of an
//   aborted block for its replacement, probe-hash.ts). Events are fetched by block hash.
// - Subscriptions carry block identity and start with a complete, paged `reset` snapshot; every
//   rewind is followed by a new one. A client never patches a cache across a connection or a rewind.
// - u64 values (lot ids, prices) are stored as 16-digit hexadecimal text: lossless, and ordered like
//   the numbers. They leave as decimal strings.
// - Completeness: lot ids come from a counter; a LotPosted whose id is not the next one, or a
//   counter on the chain (view call `lot_count` at the block about to be served) that differs from
//   the indexed one, halts the indexer. Presence has no such check (research §6).
import { createServer, type ServerResponse } from "node:http";
import { DatabaseSync } from "node:sqlite";
import { parseArgs } from "node:util";
import { hash } from "starknet";

const { values: args } = parseArgs({
  options: {
    address: { type: "string" },
    db: { type: "string" },
    port: { type: "string", default: "0" },
    from: { type: "string", default: "0" },
    poll: { type: "string", default: "100" },
    "rpc-delay": { type: "string", default: "0" },
  },
});
const rpcUrl = process.env.INDEXER_RPC_URL;
if (!rpcUrl || !args.address || !args.db) {
  console.error("usage: INDEXER_RPC_URL=<url> node indexer.ts --address <contract> --db <file> [--port <n>] [--from <block>] [--poll <ms>] [--rpc-delay <ms>]");
  process.exit(2);
}
const address = `0x${BigInt(args.address).toString(16)}`;
const firstBlock = Number(args.from);
const pollMs = Number(args.poll);
const rpcDelayMs = Number(args["rpc-delay"]); // fault injection for the tests: a slow node

/** The URL without credentials, path or query: what may appear in a log. */
export function redact(url: string): string {
  const parsed = new URL(url);
  const hidden = parsed.username || parsed.password || parsed.pathname !== "/" || parsed.search || parsed.hash;
  return `${parsed.protocol}//${parsed.host}${hidden ? "/…(redacted)" : ""}`;
}

// --- JSON-RPC --------------------------------------------------------------------------------------
let rpcId = 0;
const rpcCalls: Record<string, number> = {};
async function rpc(method: string, params: unknown): Promise<any> {
  rpcCalls[method] = (rpcCalls[method] ?? 0) + 1;
  if (rpcDelayMs > 0) await new Promise((resolve) => setTimeout(resolve, rpcDelayMs));
  const response = await fetch(rpcUrl!, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method, params }),
  });
  const body = await response.json();
  if (body.error) throw Object.assign(new Error(`${method}: ${JSON.stringify(body.error)}`), { rpcError: body.error });
  return body.result;
}

type Header = { number: number; hash: string; parent: string; commitments: string };
const sameBlock = (a: Header, b: Header) => a.hash === b.hash && a.commitments === b.commitments;
const BLOCK_NOT_FOUND = 24;
async function header(number: number): Promise<Header | null> {
  try {
    const block = await rpc("starknet_getBlockWithTxHashes", { block_id: { block_number: number } });
    const commitments = [block.transaction_commitment, block.event_commitment, block.receipt_commitment, block.state_diff_commitment].join(",");
    return { number, hash: block.block_hash, parent: block.parent_hash, commitments };
  } catch (error: any) {
    if (error.rpcError?.code === BLOCK_NOT_FOUND) return null;
    throw error;
  }
}

const SELECTOR = {
  LotPosted: hash.getSelectorFromName("LotPosted"),
  LotClosed: hash.getSelectorFromName("LotClosed"),
  AdventurerLocated: hash.getSelectorFromName("AdventurerLocated"),
  LotCountSet: hash.getSelectorFromName("LotCountSet"),
};
const selectorName = new Map(Object.entries(SELECTOR).map(([name, selector]) => [BigInt(selector), name]));
const LOT_COUNT = hash.getSelectorFromName("lot_count");

type RawEvent = { keys: string[]; data: string[]; block_hash: string; transaction_hash: string };
async function eventsOf(block: Header): Promise<RawEvent[]> {
  const events: RawEvent[] = [];
  let continuation_token: string | undefined;
  do {
    const page = await rpc("starknet_getEvents", {
      filter: {
        from_block: { block_hash: block.hash },
        to_block: { block_hash: block.hash },
        address,
        keys: [Object.values(SELECTOR)],
        chunk_size: 1000,
        ...(continuation_token ? { continuation_token } : {}),
      },
    });
    events.push(...page.events);
    continuation_token = page.continuation_token;
  } while (continuation_token);
  for (const event of events) {
    if (event.block_hash !== block.hash) throw new Error(`event of block ${event.block_hash}, expected ${block.hash}`);
  }
  return events;
}

// --- storage ---------------------------------------------------------------------------------------
const U64 = (1n << 64n) - 1n;
function u64(value: string): string {
  const number = BigInt(value);
  if (number < 0n || number > U64) throw new Halt(`value ${value} is not a u64`);
  return number.toString(16).padStart(16, "0");
}
const decimal = (hex16: string) => BigInt(`0x${hex16}`).toString();
const small = (value: string) => Number(BigInt(value)); // u16 and u32 fields only

const db = new DatabaseSync(args.db);
db.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA synchronous = NORMAL;
  CREATE TABLE IF NOT EXISTS blocks (
    number INTEGER PRIMARY KEY, hash TEXT NOT NULL, parent TEXT NOT NULL, commitments TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS lots (
    lot TEXT NOT NULL, item INTEGER NOT NULL, quantity INTEGER NOT NULL, price TEXT NOT NULL,
    open INTEGER NOT NULL, sold INTEGER NOT NULL, _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS lots_item ON lots (item, price, lot) WHERE open = 1;
  CREATE INDEX IF NOT EXISTS lots_current ON lots (lot) WHERE _to IS NULL;
  CREATE INDEX IF NOT EXISTS lots_from ON lots (_from);
  CREATE INDEX IF NOT EXISTS lots_to ON lots (_to) WHERE _to IS NOT NULL;
  CREATE TABLE IF NOT EXISTS locations (
    adventurer INTEGER NOT NULL, hub INTEGER NOT NULL, _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS locations_hub ON locations (hub) WHERE _to IS NULL;
  CREATE INDEX IF NOT EXISTS locations_current ON locations (adventurer) WHERE _to IS NULL;
  CREATE INDEX IF NOT EXISTS locations_from ON locations (_from);
  CREATE INDEX IF NOT EXISTS locations_to ON locations (_to) WHERE _to IS NOT NULL;
  CREATE TABLE IF NOT EXISTS counters (name TEXT NOT NULL, value TEXT NOT NULL, _from INTEGER NOT NULL, _to INTEGER);
  CREATE INDEX IF NOT EXISTS counters_current ON counters (name) WHERE _to IS NULL;
`);
const sql = {
  tip: db.prepare("SELECT number, hash, parent, commitments FROM blocks ORDER BY number DESC LIMIT 1"),
  block: db.prepare("SELECT number, hash, parent, commitments FROM blocks WHERE number = ?"),
  insertBlock: db.prepare("INSERT INTO blocks (number, hash, parent, commitments) VALUES (?, ?, ?, ?)"),
  currentLot: db.prepare("SELECT lot, item, quantity, price FROM lots WHERE lot = ? AND _to IS NULL"),
  insertLot: db.prepare("INSERT INTO lots (lot, item, quantity, price, open, sold, _from) VALUES (?, ?, ?, ?, ?, ?, ?)"),
  closeLot: db.prepare("UPDATE lots SET _to = ? WHERE lot = ? AND _to IS NULL"),
  closeLocation: db.prepare("UPDATE locations SET _to = ? WHERE adventurer = ? AND _to IS NULL"),
  insertLocation: db.prepare("INSERT INTO locations (adventurer, hub, _from) VALUES (?, ?, ?)"),
  counter: db.prepare("SELECT value FROM counters WHERE name = ? AND _to IS NULL"),
  closeCounter: db.prepare("UPDATE counters SET _to = ? WHERE name = ? AND _to IS NULL"),
  insertCounter: db.prepare("INSERT INTO counters (name, value, _from) VALUES (?, ?, ?)"),
  touchedLots: db.prepare("SELECT DISTINCT lot FROM lots WHERE _from > ? OR _to > ? ORDER BY lot"),
  // Reads AS OF a block B: the versions valid at B, _from <= B < _to. Queries read at the served
  // block (R6), which may be below the stored tip while that tip awaits its reconciliation.
  openLots: db.prepare(
    "SELECT lot, item, quantity, price, _from AS block FROM lots WHERE item = ? AND open = 1 AND _from <= ? AND (_to IS NULL OR _to > ?) ORDER BY price, lot LIMIT ? OFFSET ?",
  ),
  openCount: db.prepare("SELECT count(*) AS count FROM lots WHERE item = ? AND open = 1 AND _from <= ? AND (_to IS NULL OR _to > ?)"),
  presence: db.prepare("SELECT count(*) AS count FROM locations WHERE hub = ? AND _from <= ? AND (_to IS NULL OR _to > ?)"),
  rows: db.prepare("SELECT (SELECT count(*) FROM lots) + (SELECT count(*) FROM locations) AS count"),
};
const rewindSql = ["lots", "locations", "counters"].flatMap((table) => [
  db.prepare(`DELETE FROM ${table} WHERE _from > ?`),
  db.prepare(`UPDATE ${table} SET _to = NULL WHERE _to > ?`),
]);
rewindSql.push(db.prepare("DELETE FROM blocks WHERE number > ?"));
const tip = (): Header | undefined => sql.tip.get() as Header | undefined;
const lotCount = (): bigint => BigInt(`0x${(sql.counter.get("lot_count") as any)?.value ?? "0"}`);
function setCounter(name: string, value: bigint, block: number) {
  sql.closeCounter.run(block, name);
  sql.insertCounter.run(name, value.toString(16).padStart(16, "0"), block);
}

function transaction<T>(work: () => T): T {
  db.exec("BEGIN");
  try {
    const result = work();
    db.exec("COMMIT");
    return result;
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

// --- state -----------------------------------------------------------------------------------------
class Halt extends Error {}
type Status = "loading" | "ok" | "rewinding" | "halted";
let status: Status = "loading";
let haltReason = "";
let chainTip = -1;
// The served block (R6): the highest stored block whose reconciliation passed, keyed by identity
// (hash and commitments), cleared on every rewind. Queries, snapshots and stream events never go
// past it; events of later blocks wait in `pending` until their block is served.
let served: Header | null = null;
let pending: { block: number; event: string; item: number; data: unknown }[] = [];
const headOf = (header: Header | undefined | null) => (header ? { number: header.number, hash: header.hash, commitments: header.commitments } : null);
const servedNumber = () => served?.number ?? -1;
function setStatus(next: Status, reason = "") {
  if (status === next) return;
  status = next;
  haltReason = reason;
  log(`status ${next}${reason ? `: ${reason}` : ""}`);
  broadcast("status", { status, reason: reason || undefined });
  if (next === "ok") for (const subscriber of subscribers) reset(subscriber);
}

// --- subscriptions (server-sent events) -------------------------------------------------------------
type Subscriber = { response: ServerResponse; item: number };
const subscribers = new Set<Subscriber>();
const frame = (event: string, data: unknown) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
function broadcast(event: string, data: unknown, item?: number) {
  for (const subscriber of subscribers) if (item === undefined || subscriber.item === item) subscriber.response.write(frame(event, data));
}
const lotOut = (row: any) => ({ lot: decimal(row.lot), item: row.item, quantity: row.quantity, price: decimal(row.price), block: row.block });
// A complete snapshot of the subscribed item's open lots at the served block, in pages of
// SNAPSHOT_PAGE: `reset-begin {head, total}`, `reset-page {lots}`…, `reset-end {head, total}`. All
// pages are read and written in one synchronous run: no event can fall between them.
const SNAPSHOT_PAGE = 1000;
function reset(subscriber: Subscriber) {
  if (status !== "ok") return subscriber.response.write(frame("status", { status, reason: haltReason || undefined }));
  const at = servedNumber();
  const head = headOf(served);
  const total = (sql.openCount.get(subscriber.item, at, at) as any).count as number;
  subscriber.response.write(frame("reset-begin", { head, total }));
  for (let offset = 0; offset < total; offset += SNAPSHOT_PAGE) {
    const lots = (sql.openLots.all(subscriber.item, at, at, SNAPSHOT_PAGE, offset) as any[]).map(lotOut);
    subscriber.response.write(frame("reset-page", { lots }));
  }
  subscriber.response.write(frame("reset-end", { head, total }));
}

// Publishes the events of every block up to the served one, then the served head.
function flush() {
  const now = pending.filter((event) => event.block <= servedNumber());
  pending = pending.filter((event) => event.block > servedNumber());
  for (const { event, item, data } of now) broadcast(event, data, item);
  broadcast("head", headOf(served));
}

// --- applying a block ------------------------------------------------------------------------------
function apply(block: Header, events: RawEvent[]) {
  const out: [string, number, unknown][] = [];
  const blockId = headOf(block);
  transaction(() => {
    for (const event of events) {
      const name = selectorName.get(BigInt(event.keys[0]));
      if (name === "LotPosted") {
        const [lot, quantity, price] = event.data;
        const expected = lotCount() + 1n;
        if (BigInt(lot) !== expected) throw new Halt(`LotPosted ${BigInt(lot)} in block ${block.number}, expected lot ${expected}: a lot was created without its event`);
        const row = { lot: u64(lot), item: small(event.keys[1]), quantity: small(quantity), price: u64(price) };
        sql.insertLot.run(row.lot, row.item, row.quantity, row.price, 1, 0, block.number);
        setCounter("lot_count", expected, block.number);
        out.push(["posted", row.item, { ...lotOut({ ...row, block: block.number }), block: blockId }]);
      } else if (name === "LotClosed") {
        const lot = u64(event.keys[1]);
        const sold = small(event.data[0]);
        const current = sql.currentLot.get(lot) as any;
        if (!current) throw new Halt(`LotClosed for unknown lot ${decimal(lot)} in block ${block.number}`);
        sql.closeLot.run(block.number, lot);
        sql.insertLot.run(lot, current.item, current.quantity, current.price, 0, sold, block.number);
        out.push(["closed", current.item, { lot: decimal(lot), item: current.item, sold: sold === 1, block: blockId }]);
      } else if (name === "AdventurerLocated") {
        const hub = small(event.keys[1]);
        const adventurer = small(event.data[0]);
        sql.closeLocation.run(block.number, adventurer);
        sql.insertLocation.run(adventurer, hub, block.number);
      } else if (name === "LotCountSet") {
        u64(event.data[0]);
        setCounter("lot_count", BigInt(event.data[0]), block.number);
      }
    }
    sql.insertBlock.run(block.number, block.hash, block.parent, block.commitments);
  });
  // Held until the block is served (R6): a subscriber never hears of a row a query could not return.
  for (const [event, item, data] of out) pending.push({ block: block.number, event, item, data });
}

function rewind(to: number, reason: string) {
  const retracted = transaction(() => {
    const lots = (sql.touchedLots.all(to, to) as { lot: string }[]).map((row) => decimal(row.lot));
    for (const statement of rewindSql) statement.run(to);
    return lots;
  });
  pending = pending.filter((event) => event.block <= to);
  served = null; // the fork point is served again only after its own reconciliation
  log(`rewind to ${to} (${reason}); ${retracted.length} lots retracted`);
  broadcast("rewind", { to, retracted });
}

// The highest stored block still on the chain (by hash and commitments), or firstBlock - 1.
async function forkPoint(): Promise<number> {
  for (let stored = tip(); stored && stored.number >= firstBlock; stored = sql.block.get(stored.number - 1) as Header | undefined) {
    const onChain = await header(stored.number);
    if (onChain && sameBlock(onChain, stored)) return stored.number;
  }
  return firstBlock - 1;
}

// Reconciliation of one stored block (the tip): the chain's lot counter at that block must be the
// indexed one. True: the block may be served. False: the block changed under us (the next step
// rewinds). A mismatch on a block that is still the chain's halts.
async function reconcile(stored: Header): Promise<boolean> {
  let onChain: bigint;
  try {
    const [value] = await rpc("starknet_call", {
      request: { contract_address: address, entry_point_selector: LOT_COUNT, calldata: [] },
      block_id: { block_hash: stored.hash },
    });
    onChain = BigInt(value);
  } catch {
    return false;
  }
  // The call was made by hash; devnet re-uses hashes, so the block must still be this one after it.
  const now = await header(stored.number);
  if (!now || !sameBlock(now, stored)) return false;
  const indexed = lotCount();
  if (onChain !== indexed) throw new Halt(`lot_count on the chain at block ${stored.number} is ${onChain}, indexed ${indexed}: a lot was created without its event`);
  return true;
}

// --- the follow loop -------------------------------------------------------------------------------
let blocksApplied = 0;
let eventsApplied = 0;
async function step(): Promise<boolean> {
  const chain = await rpc("starknet_blockHashAndNumber", []);
  chainTip = chain.block_number;
  const stored = tip();
  if (stored) {
    const onChain = await header(stored.number);
    if (!onChain || !sameBlock(onChain, stored)) {
      setStatus("rewinding", `block ${stored.number} ${stored.hash.slice(0, 10)}… no longer on the chain`);
      rewind(await forkPoint(), `tip ${stored.number} no longer on the chain`);
      return true; // `ok` again only once the fork point is reconciled and served
    }
    // The stored tip is the chain's. It is served only after its own reconciliation (R6).
    if (!served || !sameBlock(served, stored)) {
      if (!(await reconcile(stored))) return true;
      served = stored;
      setStatus("ok");
      flush();
    }
  } else setStatus("ok"); // nothing indexed yet: answers are empty, with no head
  let next = (stored?.number ?? firstBlock - 1) + 1;
  if (next > chain.block_number) return false;
  const last = Math.min(chain.block_number, next + 99); // a bounded batch, then the tip is checked again
  for (; next <= last; next++) {
    const block = await header(next);
    if (!block) return true;
    const below = tip();
    if (below && block.parent !== below.hash) return true; // the next step's tip check rewinds
    let events: RawEvent[];
    try {
      events = await eventsOf(block);
    } catch (error) {
      log(`block ${next}: ${(error as Error).message}; checking again`);
      return true;
    }
    apply(block, events);
    blocksApplied++;
    eventsApplied += events.length;
  }
  return true; // the next step checks the new tip, reconciles it, then serves it
}

function log(message: string) {
  console.log(`[indexer ${new Date().toISOString()}] ${message}`);
}

// --- HTTP ------------------------------------------------------------------------------------------
const started = Date.now();
const server = createServer((request, response) => {
  const url = new URL(request.url ?? "/", "http://indexer");
  const json = (code: number, body: unknown) => {
    response.writeHead(code, { "content-type": "application/json" });
    response.end(JSON.stringify(body));
  };
  if (url.pathname === "/stats") {
    const usage = process.resourceUsage();
    return json(200, {
      status,
      head: headOf(served),
      stored: headOf(tip()),
      blocksApplied,
      eventsApplied,
      rows: (sql.rows.get() as any).count,
      rpcCalls,
      rssMB: Math.round(process.memoryUsage().rss / 2 ** 20),
      maxRssMB: Math.round(usage.maxRSS / 1024),
      uptimeMs: Date.now() - started,
    });
  }
  if (url.pathname === "/lots/subscribe") {
    const subscriber = { response, item: Number(url.searchParams.get("item")) };
    response.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive" });
    reset(subscriber);
    subscribers.add(subscriber);
    request.on("close", () => subscribers.delete(subscriber));
    return;
  }
  // Queries: rows only in state `ok`, with the head they were read at, from one synchronous read.
  if (status !== "ok") return json(503, { status, reason: haltReason || undefined });
  // Every answer is read AS OF the served block (R6), never the stored tip.
  const at = servedNumber();
  const answer = { status, head: headOf(served), behind: Math.max(0, chainTip - at) };
  if (url.pathname === "/head") return json(200, answer);
  if (url.pathname === "/lots/cheapest") {
    const item = Number(url.searchParams.get("item"));
    const limit = Math.min(Number(url.searchParams.get("limit") ?? 1), 50);
    return json(200, { ...answer, lots: (sql.openLots.all(item, at, at, limit, 0) as any[]).map(lotOut) });
  }
  if (url.pathname === "/hubs/presence") {
    const hub = Number(url.searchParams.get("hub"));
    return json(200, { ...answer, count: (sql.presence.get(hub, at, at) as any).count });
  }
  json(404, { error: "not found" });
});
server.listen(Number(args.port), "127.0.0.1", () => {
  const { port } = server.address() as { port: number };
  log(`environment: ${Object.keys(process.env).sort().join(", ")}`);
  log(`serving on http://127.0.0.1:${port}, following ${redact(rpcUrl)} from block ${firstBlock}, tip ${JSON.stringify(headOf(tip()))}, status ${status}`);
});

// The loop: as fast as blocks come, then every pollMs. An RPC failure waits and tries again; an
// invariant failure halts for good (the process keeps answering 503 halted).
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => {
    server.close();
    for (const { response } of subscribers) response.end();
    db.close();
    process.exit(0);
  });
}
for (;;) {
  let more = false;
  try {
    more = await step();
  } catch (error) {
    if (error instanceof Halt) {
      setStatus("halted", error.message);
      break;
    }
    log(`step failed: ${(error as Error).message}`);
  }
  if (!more) await new Promise((resolve) => setTimeout(resolve, pollMs));
}
