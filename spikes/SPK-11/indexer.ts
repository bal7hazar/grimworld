// SPK-11: an indexer of our own, the candidate the spike recommends
// (docs/research/SPK-11-indexer.md). One Node 24 process, no dependency but starknet.js (for the
// event selectors): it follows the chain over JSON-RPC, decodes the Market contract's events,
// keeps tables in SQLite (node:sqlite), serves queries over HTTP and a subscription over
// server-sent events, and rewinds on a reorg.
//
//   node spikes/SPK-11/indexer.ts --rpc <url> --address <contract> --db <file> --port <port>
//        [--from <block>] [--poll <ms>]
//
// Rewind: every row is a version valid over [_from, _to) of block numbers (_to NULL: current),
// the scheme of Apibara's Drizzle plugin (a `_cursor` range per row). Rewinding to block F deletes
// the versions born after F and reopens the ones closed after F, in one transaction. A reorg is
// detected by hashes, never by heights alone: each new block's parent hash must be the hash stored
// for the block below it, and the stored tip must still be on the chain. The events of a block are
// fetched by its hash, and every event must carry that hash, so a block replaced between the two
// calls is never mixed with its replacement. Everything here is rebuilt from the chain by deleting
// the database file and starting again from the contract's deployment block.
import { createServer, type ServerResponse } from "node:http";
import { DatabaseSync } from "node:sqlite";
import { parseArgs } from "node:util";
import { hash } from "starknet";

const { values: args } = parseArgs({
  options: {
    rpc: { type: "string" },
    address: { type: "string" },
    db: { type: "string" },
    port: { type: "string", default: "0" },
    from: { type: "string", default: "0" },
    poll: { type: "string", default: "100" },
  },
});
if (!args.rpc || !args.address || !args.db) {
  console.error("usage: node indexer.ts --rpc <url> --address <contract> --db <file> [--port <n>] [--from <block>] [--poll <ms>]");
  process.exit(2);
}
const rpcUrl = args.rpc;
const address = BigInt(args.address);
const firstBlock = Number(args.from);
const pollMs = Number(args.poll);

// --- JSON-RPC --------------------------------------------------------------------------------------
let rpcId = 0;
let rpcCalls = 0;
async function rpc(method: string, params: unknown): Promise<any> {
  rpcCalls++;
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method, params }),
  });
  const body = await response.json();
  if (body.error) throw Object.assign(new Error(`${method}: ${JSON.stringify(body.error)}`), { rpcError: body.error });
  return body.result;
}

// A block is known by its hash AND its commitments. On Starknet the hash commits to the
// transactions, events, receipts and state diff, so the commitments add nothing; devnet 0.10.0
// gives a replaced block the hash of the aborted one (same number and parent), with other
// commitments (spikes/SPK-11/probe-hash.ts), and only the commitments tell the two apart.
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
};
const selectorName = new Map(Object.entries(SELECTOR).map(([name, selector]) => [BigInt(selector), name]));

type RawEvent = { keys: string[]; data: string[]; block_hash: string; transaction_hash: string };
async function eventsOf(block: Header): Promise<RawEvent[]> {
  const events: RawEvent[] = [];
  let continuation_token: string | undefined;
  do {
    const page = await rpc("starknet_getEvents", {
      filter: {
        from_block: { block_hash: block.hash },
        to_block: { block_hash: block.hash },
        address: `0x${address.toString(16)}`,
        keys: [Object.values(SELECTOR)],
        chunk_size: 1000,
        ...(continuation_token ? { continuation_token } : {}),
      },
    });
    events.push(...page.events);
    continuation_token = page.continuation_token;
  } while (continuation_token);
  // A block replaced between `header` and here would answer with another hash, or nothing: an
  // event of another block aborts this block, and the loop's hash check finds the reorg.
  for (const event of events) {
    if (event.block_hash !== block.hash) throw new Error(`event of block ${event.block_hash}, expected ${block.hash}`);
  }
  return events;
}

// --- storage ---------------------------------------------------------------------------------------
const db = new DatabaseSync(args.db);
db.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA synchronous = NORMAL;
  CREATE TABLE IF NOT EXISTS blocks (
    number INTEGER PRIMARY KEY, hash TEXT NOT NULL, parent TEXT NOT NULL, commitments TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS lots (
    lot INTEGER NOT NULL, item INTEGER NOT NULL, quantity INTEGER NOT NULL, price INTEGER NOT NULL,
    open INTEGER NOT NULL, sold INTEGER NOT NULL, _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS lots_open ON lots (item, price, lot) WHERE _to IS NULL AND open = 1;
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
  touchedLots: db.prepare("SELECT DISTINCT lot FROM lots WHERE _from > ? OR _to > ? ORDER BY lot"),
  cheapest: db.prepare(
    "SELECT lot, item, quantity, price, _from AS block FROM lots WHERE item = ? AND open = 1 AND _to IS NULL ORDER BY price, lot LIMIT ?",
  ),
  presence: db.prepare("SELECT count(*) AS count FROM locations WHERE hub = ? AND _to IS NULL"),
  events: db.prepare("SELECT (SELECT count(*) FROM lots) + (SELECT count(*) FROM locations) AS count"),
};
const rewindSql = [
  db.prepare("DELETE FROM lots WHERE _from > ?"),
  db.prepare("UPDATE lots SET _to = NULL WHERE _to > ?"),
  db.prepare("DELETE FROM locations WHERE _from > ?"),
  db.prepare("UPDATE locations SET _to = NULL WHERE _to > ?"),
  db.prepare("DELETE FROM blocks WHERE number > ?"),
];
const tip = (): Header | undefined => sql.tip.get() as Header | undefined;

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

// --- subscriptions (server-sent events) -------------------------------------------------------------
const subscribers = new Set<ServerResponse>();
function publish(event: string, data: unknown) {
  const frame = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const subscriber of subscribers) subscriber.write(frame);
}
const headOf = (header: Header | undefined) => (header ? { number: header.number, hash: header.hash } : null);

// --- applying a block ------------------------------------------------------------------------------
const felt = (value: string) => Number(BigInt(value)); // every field of these events fits 2^53 but the price, below
function apply(block: Header, events: RawEvent[]) {
  const posted: unknown[] = [];
  const closed: unknown[] = [];
  transaction(() => {
    for (const event of events) {
      const name = selectorName.get(BigInt(event.keys[0]));
      if (name === "LotPosted") {
        const [lot, quantity, price] = event.data;
        const row = { lot: felt(lot), item: felt(event.keys[1]), quantity: felt(quantity), price: BigInt(price) };
        sql.insertLot.run(row.lot, row.item, row.quantity, row.price, 1, 0, block.number);
        posted.push({ ...row, price: row.price.toString(), block: block.number });
      } else if (name === "LotClosed") {
        const lot = felt(event.keys[1]);
        const sold = felt(event.data[0]);
        const current = sql.currentLot.get(lot) as any;
        if (!current) throw new Error(`LotClosed for unknown lot ${lot} in block ${block.number}`);
        sql.closeLot.run(block.number, lot);
        sql.insertLot.run(lot, current.item, current.quantity, current.price, 0, sold, block.number);
        closed.push({ lot, item: current.item, sold: sold === 1, block: block.number });
      } else if (name === "AdventurerLocated") {
        const hub = felt(event.keys[1]);
        const adventurer = felt(event.data[0]);
        sql.closeLocation.run(block.number, adventurer);
        sql.insertLocation.run(adventurer, hub, block.number);
      }
    }
    sql.insertBlock.run(block.number, block.hash, block.parent, block.commitments);
  });
  // Published after the commit: a subscriber never hears of a row a query could not return.
  for (const lot of posted) publish("posted", lot);
  for (const lot of closed) publish("closed", lot);
  if (events.length > 0 || block.number % 50 === 0) publish("head", headOf(block));
}

function rewind(to: number, reason: string) {
  const retracted = transaction(() => {
    const lots = (sql.touchedLots.all(to, to) as { lot: number }[]).map((row) => row.lot);
    for (const statement of rewindSql) statement.run(to);
    return lots;
  });
  const head = headOf(tip());
  log(`rewind to ${to} (${reason}); ${retracted.length} lots retracted`);
  publish("rewind", { to, head, retracted });
}

// The highest stored block still on the chain (by hash), or firstBlock - 1.
async function forkPoint(): Promise<number> {
  for (let stored = tip(); stored && stored.number >= firstBlock; stored = sql.block.get(stored.number - 1) as Header | undefined) {
    const onChain = await header(stored.number);
    if (onChain && sameBlock(onChain, stored)) return stored.number;
  }
  return firstBlock - 1;
}

// --- the follow loop -------------------------------------------------------------------------------
let blocksApplied = 0;
let eventsApplied = 0;
async function step(): Promise<boolean> {
  const chain = await rpc("starknet_blockHashAndNumber", []);
  const stored = tip();
  if (stored) {
    const onChain = await header(stored.number);
    if (!onChain || !sameBlock(onChain, stored)) {
      rewind(await forkPoint(), `tip ${stored.number} ${stored.hash.slice(0, 10)}… no longer on the chain`);
      return true;
    }
  }
  let next = (stored?.number ?? firstBlock - 1) + 1;
  if (next > chain.block_number) return false;
  const last = Math.min(chain.block_number, next + 99); // a bounded batch, then the tip is checked again
  for (; next <= last; next++) {
    const block = await header(next);
    if (!block) return true; // the chain shrank since blockHashAndNumber: the next step rewinds
    const below = tip();
    if (below && block.parent !== below.hash) {
      rewind(await forkPoint(), `parent of ${next} is not the stored ${below.number}`);
      return true;
    }
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
  return true;
}

function log(message: string) {
  console.log(`[indexer ${new Date().toISOString()}] ${message}`);
}

// --- HTTP ------------------------------------------------------------------------------------------
const started = Date.now();
const server = createServer((request, response) => {
  const url = new URL(request.url ?? "/", "http://indexer");
  const json = (status: number, body: unknown) => {
    response.writeHead(status, { "content-type": "application/json" });
    response.end(JSON.stringify(body));
  };
  // Every answer carries the head it was read at, from the same synchronous read of the database.
  if (url.pathname === "/head") return json(200, { head: headOf(tip()) });
  if (url.pathname === "/lots/cheapest") {
    const item = Number(url.searchParams.get("item"));
    const limit = Math.min(Number(url.searchParams.get("limit") ?? 1), 50);
    const lots = (sql.cheapest.all(item, limit) as any[]).map((lot) => ({ ...lot, price: String(lot.price) }));
    return json(200, { head: headOf(tip()), lots });
  }
  if (url.pathname === "/hubs/presence") {
    const hub = Number(url.searchParams.get("hub"));
    return json(200, { head: headOf(tip()), count: (sql.presence.get(hub) as any).count });
  }
  if (url.pathname === "/lots/subscribe") {
    response.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive" });
    response.write(`event: head\ndata: ${JSON.stringify(headOf(tip()))}\n\n`);
    subscribers.add(response);
    request.on("close", () => subscribers.delete(response));
    return;
  }
  if (url.pathname === "/stats") {
    const usage = process.resourceUsage();
    return json(200, {
      head: headOf(tip()),
      blocksApplied,
      eventsApplied,
      rows: (sql.events.get() as any).count,
      rpcCalls,
      rssMB: Math.round(process.memoryUsage().rss / 2 ** 20),
      maxRssMB: Math.round(usage.maxRSS / 1024),
      uptimeMs: Date.now() - started,
    });
  }
  json(404, { error: "not found" });
});
server.listen(Number(args.port), "127.0.0.1", () => {
  const { port } = server.address() as { port: number };
  log(`serving on http://127.0.0.1:${port}, following ${rpcUrl} from block ${firstBlock}, tip ${JSON.stringify(headOf(tip()))}`);
});

// The loop: as fast as blocks come, then every pollMs. An RPC failure waits and tries again.
let stopping = false;
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => {
    stopping = true;
    server.close();
    for (const subscriber of subscribers) subscriber.end();
    db.close();
    process.exit(0);
  });
}
while (!stopping) {
  let more = false;
  try {
    more = await step();
  } catch (error) {
    log(`step failed: ${(error as Error).message}`);
  }
  if (!more) await new Promise((resolve) => setTimeout(resolve, pollMs));
}
