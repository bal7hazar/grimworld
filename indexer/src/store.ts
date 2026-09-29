// The indexer's tables, in SQLite (node:sqlite; D-130: SQLite for the MVP and the test networks).
//
// Every row is a version valid over the blocks [_from, _to): `_to` is null while the version is
// current. Changing a thing closes its current version (`_to` = the block) and inserts the new one
// (`_from` = the block); a fact (a trial passed, a dungeon cleared, a raw event) is inserted and
// never closed. Rewinding to a block F deletes the versions born after F and reopens those closed
// after F, in one transaction (SPK-11 §4, Apibara's and Checkpoint's scheme). Pruning below the
// kept history deletes the versions closed at or below it, which no block of the kept history can
// read. Any past block B of the kept history is readable: `_from <= B AND (_to IS NULL OR _to > B)`.
//
// u64 values (lot and trade ids, prices, expiries) are 16-digit lowercase hex text: lossless, and
// ordered like the numbers (SPK-11 §6 point 4); they leave as decimal strings. felt252 values that
// are not decoded into columns (modifiers) are canonical 0x hex text. The market key, below 2^42 by
// ENG-01's encoding, is an INTEGER beside its decoded columns.
//
// Lot and trade ids come from the contracts' counters (ENG-01 §3.4: never reused, "the indexer
// detects a gap"): a LotPosted or TradeOpened whose id is not the next one halts the indexer, and
// so does a close of a lot or trade the tables do not hold open.
import {
  DatabaseSync,
  type SQLInputValue,
  type StatementSync,
} from "node:sqlite";
import type { Header, RawEvent } from "./chain.ts";
import { canonical, type Decoded } from "./events.ts";

/** An invariant failed: the indexer stops following and answers `halted`, with this reason. */
export class Halt extends Error {}

/** What a database was built for; a database is never reused for another configuration. */
export type Config = {
  hub: string;
  market: string;
  /** The first block indexed (the contracts' deployment block). */
  from: number;
  /** `lot_count` and `trade_count` at the block before `from` (0 at deployment). */
  lotCount: bigint;
  tradeCount: bigint;
};

export type Applied = { raw: RawEvent; event: Decoded };

const SCHEMA_VERSION = "1";

/** The versioned tables, in the order of their creation. */
export const TABLES = [
  "events",
  "lots",
  "trades",
  "presence",
  "titles",
  "trial_passes",
  "clears",
  "ranks",
] as const;
export type Table = (typeof TABLES)[number];

const SCHEMA = `
  CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS blocks (
    number INTEGER PRIMARY KEY, hash TEXT NOT NULL, parent TEXT NOT NULL, commitments TEXT NOT NULL
  );
  -- The raw events of both contracts, in block order, for audit.
  CREATE TABLE IF NOT EXISTS events (
    source TEXT NOT NULL, name TEXT NOT NULL, keys TEXT NOT NULL, data TEXT NOT NULL,
    tx_hash TEXT NOT NULL, tx INTEGER NOT NULL, idx INTEGER NOT NULL,
    _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS events_position ON events (_from, tx, idx);
  CREATE TABLE IF NOT EXISTS lots (
    lot TEXT NOT NULL, market_key INTEGER NOT NULL, kind TEXT NOT NULL, item INTEGER,
    base INTEGER, requirement INTEGER, rarity INTEGER, identified INTEGER,
    lot_size INTEGER NOT NULL, price TEXT NOT NULL, expiry TEXT NOT NULL,
    equipment INTEGER NOT NULL, modifiers TEXT NOT NULL,
    open INTEGER NOT NULL, sold INTEGER NOT NULL, posted INTEGER NOT NULL,
    _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS lots_current ON lots (lot) WHERE _to IS NULL;
  CREATE INDEX IF NOT EXISTS lots_key ON lots (market_key, lot_size, price, lot) WHERE open = 1;
  CREATE TABLE IF NOT EXISTS trades (
    trade TEXT NOT NULL, invited INTEGER NOT NULL, inviter INTEGER NOT NULL,
    open INTEGER NOT NULL, outcome INTEGER, opened INTEGER NOT NULL,
    _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS trades_current ON trades (trade) WHERE _to IS NULL;
  CREATE INDEX IF NOT EXISTS trades_invited ON trades (invited) WHERE open = 1;
  -- Who is in which hub: one current row per adventurer; hub 0 is in no hub (inside an instance).
  CREATE TABLE IF NOT EXISTS presence (
    adventurer INTEGER NOT NULL, hub INTEGER NOT NULL, _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS presence_current ON presence (adventurer) WHERE _to IS NULL;
  CREATE INDEX IF NOT EXISTS presence_hub ON presence (hub);
  -- The displayed title, emitted only (scope 3): one current row per adventurer.
  CREATE TABLE IF NOT EXISTS titles (
    adventurer INTEGER NOT NULL, title INTEGER NOT NULL, tier INTEGER NOT NULL,
    _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS titles_current ON titles (adventurer) WHERE _to IS NULL;
  -- Facts of the rankings (version 1), one row per event.
  CREATE TABLE IF NOT EXISTS trial_passes (
    adventurer INTEGER NOT NULL, rank INTEGER NOT NULL, first_attempt INTEGER NOT NULL,
    tx INTEGER NOT NULL, idx INTEGER NOT NULL, _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS trial_passes_adventurer ON trial_passes (adventurer);
  CREATE TABLE IF NOT EXISTS clears (
    adventurer INTEGER NOT NULL, dungeon INTEGER NOT NULL,
    tx INTEGER NOT NULL, idx INTEGER NOT NULL, _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS clears_adventurer ON clears (adventurer);
  -- The rank reached last: one current row per adventurer.
  CREATE TABLE IF NOT EXISTS ranks (
    adventurer INTEGER NOT NULL, rank INTEGER NOT NULL, _from INTEGER NOT NULL, _to INTEGER
  );
  CREATE INDEX IF NOT EXISTS ranks_current ON ranks (adventurer) WHERE _to IS NULL;
`;

const U64_TEXT = 16;
export const u64Text = (value: bigint) =>
  value.toString(16).padStart(U64_TEXT, "0");
export const u64Decimal = (text: string) => BigInt(`0x${text}`).toString();

/** The columns of each table whose values are u64 text, served as decimal strings. */
const U64_COLUMNS: Partial<Record<Table, string[]>> = {
  lots: ["lot", "price", "expiry"],
  trades: ["trade"],
};

type Row = Record<string, SQLInputValue>;

/** The columns a closed lot keeps from its open version. */
const LOT_COLUMNS = [
  "lot",
  "market_key",
  "kind",
  "item",
  "base",
  "requirement",
  "rarity",
  "identified",
  "lot_size",
  "price",
  "expiry",
  "equipment",
  "modifiers",
  "posted",
];
const pick = (row: Row, columns: string[]): Row =>
  Object.fromEntries(columns.map((column) => [column, row[column] ?? null]));

export class Store {
  private readonly db: DatabaseSync;
  private readonly sql: ReturnType<typeof statements>;

  constructor(path: string) {
    this.db = new DatabaseSync(path);
    this.db.exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;");
    this.db.exec(SCHEMA);
    for (const table of TABLES) {
      this.db.exec(
        `CREATE INDEX IF NOT EXISTS ${table}_from ON ${table} (_from);
         CREATE INDEX IF NOT EXISTS ${table}_to ON ${table} (_to) WHERE _to IS NOT NULL;`,
      );
    }
    this.sql = statements(this.db);
  }

  close() {
    this.db.close();
  }

  /** Runs `work` in one transaction: all of it, or nothing. */
  transaction<T>(work: () => T): T {
    this.db.exec("BEGIN");
    try {
      const result = work();
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  // --- configuration -------------------------------------------------------------------------------

  private meta(key: string): string | undefined {
    return (this.sql.meta.get(key) as { value: string } | undefined)?.value;
  }

  /** The configuration the database was built for, if any. */
  config(): Config | undefined {
    const text = this.meta("config");
    if (text === undefined) return undefined;
    const stored = JSON.parse(text) as Record<keyof Config, string | number>;
    return {
      hub: String(stored.hub),
      market: String(stored.market),
      from: Number(stored.from),
      lotCount: BigInt(stored.lotCount),
      tradeCount: BigInt(stored.tradeCount),
    };
  }

  /**
   * Opens the database for `config`: a new database takes it; a database built for another one is
   * refused (an Error: `rebuild` starts it again).
   */
  open(config: Config) {
    const normal = normalize(config);
    const stored = this.config();
    if (stored === undefined) {
      if (this.tip())
        throw new Error("the database holds blocks but no configuration");
      this.transaction(() => {
        this.sql.setMeta.run("schema", SCHEMA_VERSION);
        this.sql.setMeta.run("config", serialize(normal));
      });
      return;
    }
    if (this.meta("schema") !== SCHEMA_VERSION) {
      throw new Error(
        `the database has schema ${this.meta("schema")}, this indexer ${SCHEMA_VERSION}: rebuild it`,
      );
    }
    if (serialize(stored) !== serialize(normal)) {
      throw new Error(
        `the database was built for ${serialize(stored)}, not ${serialize(normal)}: rebuild it`,
      );
    }
  }

  /** Empties every table and forgets the configuration, in one transaction (`rebuild`). */
  clear() {
    this.transaction(() => {
      for (const table of [...TABLES, "blocks", "meta"])
        this.db.exec(`DELETE FROM ${table}`);
    });
  }

  // --- blocks --------------------------------------------------------------------------------------

  tip(): Header | undefined {
    return this.sql.tip.get() as Header | undefined;
  }

  /** The lowest block of the kept history. */
  lowest(): Header | undefined {
    return this.sql.lowest.get() as Header | undefined;
  }

  block(number: number): Header | undefined {
    return this.sql.block.get(number) as Header | undefined;
  }

  /**
   * The highest block checked against the node after it was applied (indexer.ts): the blocks above
   * it are checked before any of them is served. -1 when none is.
   */
  checked(): number {
    return Number(this.meta("checked") ?? -1);
  }

  setChecked(number: number) {
    this.sql.setMeta.run("checked", String(number));
  }

  /** The last lot and trade ids handed out, as the tables say. */
  counters(): { lotCount: bigint; tradeCount: bigint } {
    const config = this.config();
    const lot = (this.sql.maxLot.get() as { lot: string | null }).lot;
    const trade = (this.sql.maxTrade.get() as { trade: string | null }).trade;
    return {
      lotCount: lot === null ? (config?.lotCount ?? 0n) : BigInt(`0x${lot}`),
      tradeCount:
        trade === null ? (config?.tradeCount ?? 0n) : BigInt(`0x${trade}`),
    };
  }

  /**
   * Applies a block and its events, in block order, in one transaction. A Halt (a gap, a close of
   * something not open) leaves the tables as they were.
   */
  apply(block: Header, events: readonly Applied[]) {
    this.transaction(() => {
      let { lotCount, tradeCount } = this.counters();
      const at = block.number;
      for (const { raw, event } of events) {
        this.sql.insertEvent.run(
          raw.source,
          event.name,
          JSON.stringify(raw.keys.map((key) => canonical(key))),
          JSON.stringify(raw.data.map((datum) => canonical(datum))),
          raw.transaction,
          raw.transactionIndex,
          raw.eventIndex,
          at,
        );
        const where = `in block ${at} (transaction ${raw.transactionIndex}, event ${raw.eventIndex})`;
        switch (event.name) {
          case "LotPosted": {
            if (event.lot !== lotCount + 1n) {
              throw new Halt(
                `gap: LotPosted of lot ${event.lot} ${where}, expected lot ${lotCount + 1n}`,
              );
            }
            lotCount = event.lot;
            const key = event.key;
            this.sql.insertLot.run({
              lot: u64Text(event.lot),
              market_key: event.marketKey,
              kind: key.kind,
              item: key.kind === "balance" ? key.item : null,
              base: key.kind === "balance" ? null : key.base,
              requirement: key.kind === "equipment" ? key.requirement : null,
              rarity: key.kind === "equipment" ? key.rarity : null,
              identified:
                key.kind === "equipment" ? Number(key.identified) : null,
              lot_size: event.lotSize,
              price: u64Text(event.price),
              expiry: u64Text(event.expiry),
              equipment: event.equipment,
              modifiers: canonical(event.modifiers),
              open: 1,
              sold: 0,
              posted: at,
              _from: at,
            });
            break;
          }
          case "LotClosed": {
            const lot = u64Text(event.lot);
            const current = this.sql.currentLot.get(lot) as Row | undefined;
            if (!current)
              throw new Halt(
                `LotClosed of lot ${event.lot} ${where}: no such lot`,
              );
            if (current.open !== 1) {
              throw new Halt(
                `LotClosed of lot ${event.lot} ${where}: the lot is not open`,
              );
            }
            this.sql.closeLot.run(at, lot);
            this.sql.insertLot.run({
              ...pick(current, LOT_COLUMNS),
              open: 0,
              sold: Number(event.sold),
              _from: at,
            });
            break;
          }
          case "TradeOpened": {
            if (event.trade !== tradeCount + 1n) {
              throw new Halt(
                `gap: TradeOpened of trade ${event.trade} ${where}, expected trade ${tradeCount + 1n}`,
              );
            }
            tradeCount = event.trade;
            this.sql.insertTrade.run({
              trade: u64Text(event.trade),
              invited: event.invited,
              inviter: event.inviter,
              open: 1,
              outcome: null,
              opened: at,
              _from: at,
            });
            break;
          }
          case "TradeClosed": {
            const trade = u64Text(event.trade);
            const current = this.sql.currentTrade.get(trade) as Row | undefined;
            if (!current)
              throw new Halt(
                `TradeClosed of trade ${event.trade} ${where}: no such trade`,
              );
            if (current.open !== 1) {
              throw new Halt(
                `TradeClosed of trade ${event.trade} ${where}: the trade is not open`,
              );
            }
            this.sql.closeTrade.run(at, trade);
            this.sql.insertTrade.run({
              trade,
              invited: current.invited ?? null,
              inviter: current.inviter ?? null,
              open: 0,
              outcome: event.outcome,
              opened: current.opened ?? null,
              _from: at,
            });
            break;
          }
          case "AdventurerLocated":
            this.sql.closePresence.run(at, event.adventurer);
            this.sql.insertPresence.run(event.adventurer, event.hub, at);
            break;
          case "TitleDisplayed":
            this.sql.closeTitle.run(at, event.adventurer);
            this.sql.insertTitle.run(
              event.adventurer,
              event.title,
              event.tier,
              at,
            );
            break;
          case "TrialPassed":
            this.sql.insertTrial.run(
              event.adventurer,
              event.rank,
              Number(event.firstAttempt),
              raw.transactionIndex,
              raw.eventIndex,
              at,
            );
            break;
          case "DungeonCleared":
            this.sql.insertClear.run(
              event.adventurer,
              event.dungeon,
              raw.transactionIndex,
              raw.eventIndex,
              at,
            );
            break;
          case "RankReached":
            this.sql.closeRank.run(at, event.adventurer);
            this.sql.insertRank.run(event.adventurer, event.rank, at);
            break;
        }
      }
      this.sql.insertBlock.run(
        block.number,
        block.hash,
        block.parent,
        block.commitments,
      );
    });
  }

  /** Every table back to block `to` (its state after `to`), in one transaction. */
  rewind(to: number) {
    this.transaction(() => {
      for (const [remove, reopen] of this.sql.rewind) {
        remove!.run(to);
        reopen!.run(to);
      }
      this.sql.rewindBlocks.run(to);
      if (this.checked() > to) this.setChecked(to);
    });
  }

  /** Forgets what no block from `floor` on can read, and the blocks below `floor`. */
  prune(floor: number) {
    this.transaction(() => {
      for (const statement of this.sql.prune) statement.run(floor);
      this.sql.pruneBlocks.run(floor);
    });
  }

  // --- reading -------------------------------------------------------------------------------------

  /** The number of rows of each table valid at block `at`. */
  countsAt(at: number): Record<Table, number> {
    return Object.fromEntries(
      TABLES.map((table) => [
        table,
        (this.sql.countAt[table].get(at, at) as { count: number }).count,
      ]),
    ) as Record<Table, number>;
  }

  /** The number of rows of every version, all tables together. */
  rows(): number {
    return (this.sql.countAll.get() as { count: number }).count;
  }

  /**
   * Every row of every table, every version, u64 values as decimal strings, in a fixed order: two
   * databases hold the same tables when their dumps are equal (a rewound one and a rebuilt one).
   */
  dump(): Record<Table | "blocks", Row[]> {
    const result = {} as Record<Table | "blocks", Row[]>;
    for (const table of TABLES) {
      const rows = this.db.prepare(`SELECT * FROM ${table}`).all() as Row[];
      const columns = U64_COLUMNS[table] ?? [];
      result[table] = rows
        .map((row) => {
          const out: Row = { ...row };
          for (const column of columns)
            out[column] = u64Decimal(String(row[column]));
          return out;
        })
        .sort(compareRows);
    }
    result.blocks = this.db
      .prepare("SELECT * FROM blocks ORDER BY number")
      .all() as Row[];
    return result;
  }

  /** The rows of `table` valid at block `at` (tests and the scenario), u64 values as decimals. */
  at(table: Table, at: number): Row[] {
    const rows = this.db
      .prepare(
        `SELECT * FROM ${table} WHERE _from <= ? AND (_to IS NULL OR _to > ?)`,
      )
      .all(at, at) as Row[];
    const columns = U64_COLUMNS[table] ?? [];
    return rows
      .map((row) => {
        const out: Row = { ...row };
        for (const column of columns)
          out[column] = u64Decimal(String(row[column]));
        return out;
      })
      .sort(compareRows);
  }
}

function statements(db: DatabaseSync) {
  return {
    meta: db.prepare("SELECT value FROM meta WHERE key = ?"),
    setMeta: db.prepare(
      "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
    ),
    tip: db.prepare(
      "SELECT number, hash, parent, commitments FROM blocks ORDER BY number DESC LIMIT 1",
    ),
    lowest: db.prepare(
      "SELECT number, hash, parent, commitments FROM blocks ORDER BY number LIMIT 1",
    ),
    block: db.prepare(
      "SELECT number, hash, parent, commitments FROM blocks WHERE number = ?",
    ),
    insertBlock: db.prepare(
      "INSERT INTO blocks (number, hash, parent, commitments) VALUES (?, ?, ?, ?)",
    ),
    insertEvent: db.prepare(
      "INSERT INTO events (source, name, keys, data, tx_hash, tx, idx, _from) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    ),
    maxLot: db.prepare("SELECT max(lot) AS lot FROM lots"),
    currentLot: db.prepare("SELECT * FROM lots WHERE lot = ? AND _to IS NULL"),
    insertLot: db.prepare(
      `INSERT INTO lots (lot, market_key, kind, item, base, requirement, rarity, identified,
         lot_size, price, expiry, equipment, modifiers, open, sold, posted, _from)
       VALUES (:lot, :market_key, :kind, :item, :base, :requirement, :rarity, :identified,
         :lot_size, :price, :expiry, :equipment, :modifiers, :open, :sold, :posted, :_from)`,
    ),
    closeLot: db.prepare(
      "UPDATE lots SET _to = ? WHERE lot = ? AND _to IS NULL",
    ),
    maxTrade: db.prepare("SELECT max(trade) AS trade FROM trades"),
    currentTrade: db.prepare(
      "SELECT * FROM trades WHERE trade = ? AND _to IS NULL",
    ),
    insertTrade: db.prepare(
      `INSERT INTO trades (trade, invited, inviter, open, outcome, opened, _from)
       VALUES (:trade, :invited, :inviter, :open, :outcome, :opened, :_from)`,
    ),
    closeTrade: db.prepare(
      "UPDATE trades SET _to = ? WHERE trade = ? AND _to IS NULL",
    ),
    closePresence: db.prepare(
      "UPDATE presence SET _to = ? WHERE adventurer = ? AND _to IS NULL",
    ),
    insertPresence: db.prepare(
      "INSERT INTO presence (adventurer, hub, _from) VALUES (?, ?, ?)",
    ),
    closeTitle: db.prepare(
      "UPDATE titles SET _to = ? WHERE adventurer = ? AND _to IS NULL",
    ),
    insertTitle: db.prepare(
      "INSERT INTO titles (adventurer, title, tier, _from) VALUES (?, ?, ?, ?)",
    ),
    insertTrial: db.prepare(
      "INSERT INTO trial_passes (adventurer, rank, first_attempt, tx, idx, _from) VALUES (?, ?, ?, ?, ?, ?)",
    ),
    insertClear: db.prepare(
      "INSERT INTO clears (adventurer, dungeon, tx, idx, _from) VALUES (?, ?, ?, ?, ?)",
    ),
    closeRank: db.prepare(
      "UPDATE ranks SET _to = ? WHERE adventurer = ? AND _to IS NULL",
    ),
    insertRank: db.prepare(
      "INSERT INTO ranks (adventurer, rank, _from) VALUES (?, ?, ?)",
    ),
    rewind: TABLES.map((table) => [
      db.prepare(`DELETE FROM ${table} WHERE _from > ?`),
      db.prepare(`UPDATE ${table} SET _to = NULL WHERE _to > ?`),
    ]),
    rewindBlocks: db.prepare("DELETE FROM blocks WHERE number > ?"),
    prune: TABLES.map((table) =>
      db.prepare(`DELETE FROM ${table} WHERE _to IS NOT NULL AND _to <= ?`),
    ),
    pruneBlocks: db.prepare("DELETE FROM blocks WHERE number < ?"),
    countAt: Object.fromEntries(
      TABLES.map((table) => [
        table,
        db.prepare(
          `SELECT count(*) AS count FROM ${table} WHERE _from <= ? AND (_to IS NULL OR _to > ?)`,
        ),
      ]),
    ) as Record<Table, StatementSync>,
    countAll: db.prepare(
      `SELECT ${TABLES.map((table) => `(SELECT count(*) FROM ${table})`).join(" + ")} AS count`,
    ),
  };
}

function compareRows(a: Row, b: Row): number {
  const x = JSON.stringify(a, replacer);
  const y = JSON.stringify(b, replacer);
  return x < y ? -1 : x > y ? 1 : 0;
}

const replacer = (_: string, value: unknown) =>
  typeof value === "bigint" ? value.toString() : value;

function normalize(config: Config): Config {
  return {
    ...config,
    hub: canonical(config.hub),
    market: canonical(config.market),
  };
}

function serialize(config: Config): string {
  return JSON.stringify({
    hub: config.hub,
    market: config.market,
    from: config.from,
    lotCount: config.lotCount.toString(),
    tradeCount: config.tradeCount.toString(),
  });
}
