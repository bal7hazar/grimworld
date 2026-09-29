// The queries of the game's screens (IDX-01b; SPK-11 §1, Q1 to Q5 and Q7), read AS OF a block B:
// the versions valid at B, `_from <= B AND (_to IS NULL OR _to > B)` (store.ts). The server reads
// them at the served block (R6); the subscriptions read them at every newly served block. Every
// value is bound as a parameter, never spliced into the SQL. Times are block times (store.ts),
// never the clock of this machine.
//
// u64 values leave as decimal strings; the market key and modifiers as canonical 0x hex (felts).
import type { SQLInputValue } from "node:sqlite";
import type { Header } from "./chain.ts";
import { canonical, decodeMarketKey, type MarketKey } from "./events.ts";
import { u64Decimal, u64Text, type Store } from "./store.ts";

/** Q2: the lot sizes read per key, at most (design/16's are 1, 10 and 100). */
export const MAX_SIZES = 8;
/** Q3's window: the sales of the last 7 days of block time, `(T - 7 days, T]`. */
export const PRICE_WINDOW_SECONDS = 7 * 24 * 60 * 60;
/** Q3: under this many sales in the window, the mean price is absent (scope 6). */
export const MIN_SALES = 5;
/** Q7: an invitation is shown while it is under 10 minutes old, `T - opened < 600` (scope 4). */
export const INVITATION_SECONDS = 10 * 60;

const AS_OF = "_from <= :at AND (_to IS NULL OR _to > :at)";

type Row = Record<string, SQLInputValue>;

/** A lot, as the queries and the lots subscription give it. */
export type Lot = {
  lot: string;
  key: string;
  size: number;
  price: string;
  expiry: string;
  equipment: number;
  modifiers: string;
  /** The block it was posted in. */
  posted: number;
};

export type Invitation = {
  trade: string;
  invited: number;
  inviter: number;
  /** The block it was opened in, and that block's time. */
  opened: number;
  openedTime: number;
  /** The block time from which it is no longer shown: `openedTime + 600`. */
  expiresAt: number;
};

export type Title = { adventurer: number; title: number; tier: number };

const LOT_COLUMNS =
  "lot, market_key, lot_size, price, expiry, equipment, modifiers, posted";

export function lotOut(row: Row): Lot {
  return {
    lot: u64Decimal(String(row.lot)),
    key: canonical(BigInt(row.market_key as number)),
    size: Number(row.lot_size),
    price: u64Decimal(String(row.price)),
    expiry: u64Decimal(String(row.expiry)),
    equipment: Number(row.equipment),
    modifiers: String(row.modifiers),
    posted: Number(row.posted),
  };
}

function invitationOut(row: Row): Invitation {
  const openedTime = Number(row.opened_time);
  return {
    trade: u64Decimal(String(row.trade)),
    invited: Number(row.invited),
    inviter: Number(row.inviter),
    opened: Number(row.opened),
    openedTime,
    expiresAt: openedTime + INVITATION_SECONDS,
  };
}

/** A position in Q1's order (price, then lot id): the page after it. */
export type LotCursor = { price: bigint; lot: bigint };

export class Queries {
  readonly store: Store;
  constructor(store: Store) {
    this.store = store;
  }

  private all(sql: string, params: Record<string, SQLInputValue>): Row[] {
    return this.store.statement(sql).all(params) as Row[];
  }

  private get(sql: string, params: Record<string, SQLInputValue>): Row {
    return this.store.statement(sql).get(params) as Row;
  }

  /**
   * Q1: the open lots of `(key, size)` at block `at`, cheapest first, ties by lot id; `limit` of
   * them after `after` (a cursor: the last lot of the page before). `total`: every open lot of the
   * key and size, for paging.
   */
  lots(
    at: number,
    key: bigint,
    size: number,
    limit: number,
    after?: LotCursor,
  ): { total: number; lots: Lot[] } {
    return {
      total: this.lotCount(at, key, size),
      lots: this.lotPage(at, key, size, limit, after),
    };
  }

  /** The count of Q1's lots. */
  lotCount(at: number, key: bigint, size: number): number {
    return Number(
      this.get(
        `SELECT count(*) AS count FROM lots
         WHERE market_key = :key AND lot_size = :size AND open = 1 AND ${AS_OF}`,
        { at, key, size },
      ).count,
    );
  }

  /** A page of Q1's lots after `after`, without the count (the snapshots' pages). */
  lotPage(
    at: number,
    key: bigint,
    size: number,
    limit: number,
    after?: LotCursor,
  ): Lot[] {
    const params = { at, key, size };
    // Without a cursor, the empty text is below every 16-digit u64 text: the first page.
    const rows = this.all(
      `SELECT ${LOT_COLUMNS} FROM lots
       WHERE market_key = :key AND lot_size = :size AND open = 1 AND ${AS_OF}
         AND (price > :price OR (price = :price AND lot > :lot))
       ORDER BY price, lot LIMIT :limit`,
      {
        ...params,
        price: after ? u64Text(after.price) : "",
        lot: after ? u64Text(after.lot) : "",
        limit,
      },
    );
    return rows.map(lotOut);
  }

  /**
   * Q2: the market keys of a kind (`balance`, `equipment`, `boss`; ENG-01 §3.4) with an open lot at
   * `at`, by key; for each, per lot size, the cheapest open lot (ties by lot id). `items`: only
   * these balance item ids (the client's category, from the registry). `limit` keys after the key
   * `after`. Every step is an index seek (the next key, the next lot size, the cheapest lot), never
   * a scan of a key's lots, and at most MAX_SIZES lot sizes are read per key (`truncated` when a key
   * has more; design/16's sizes are 1, 10 and 100): a request makes at most
   * `(limit + 1) × (2 × MAX_SIZES + 2)` seeks, whatever the number of lots.
   */
  market(
    at: number,
    kind: MarketKey["kind"],
    limit: number,
    after: bigint | undefined,
    items: number[] | undefined,
  ): {
    keys: {
      key: string;
      decoded: MarketKey;
      sizes: { size: number; cheapest: Lot }[];
      truncated?: true;
    }[];
    next: string | null;
  } {
    let cursor = after ?? -1n;
    const candidates = items
      ?.map((item) => BigInt(item))
      .filter((key) => key > cursor)
      .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    const found: {
      key: string;
      decoded: MarketKey;
      sizes: { size: number; cheapest: Lot }[];
      truncated?: true;
    }[] = [];
    // One key more than the page: whether there is a next page.
    while (found.length <= limit) {
      let key: bigint;
      if (candidates) {
        const candidate = candidates.shift();
        if (candidate === undefined) break;
        key = candidate;
      } else {
        const row = this.store
          .statement(
            `SELECT market_key FROM lots
             WHERE kind = :kind AND open = 1 AND ${AS_OF} AND market_key > :after
             ORDER BY market_key LIMIT 1`,
          )
          .get({ at, kind, after: cursor }) as Row | undefined;
        if (!row) break;
        key = BigInt(row.market_key as number);
      }
      cursor = key;
      const { sizes, truncated } = this.cheapestPerSize(at, key);
      if (sizes.length === 0) continue;
      found.push({
        key: canonical(key),
        decoded: decodeMarketKey(key),
        sizes,
        ...(truncated ? { truncated } : {}),
      });
    }
    const more = found.length > limit;
    const keys = found.slice(0, limit);
    return {
      keys,
      next: more ? keys[keys.length - 1]!.key : null,
    };
  }

  /** The cheapest open lot of `key` at `at`, per lot size, by lot size: the first MAX_SIZES. */
  private cheapestPerSize(
    at: number,
    key: bigint,
  ): { sizes: { size: number; cheapest: Lot }[]; truncated?: true } {
    const sizes: { size: number; cheapest: Lot }[] = [];
    let size = 0;
    for (;;) {
      const next = this.store
        .statement(
          `SELECT lot_size FROM lots
           WHERE market_key = :key AND lot_size > :size AND open = 1 AND ${AS_OF}
           ORDER BY lot_size LIMIT 1`,
        )
        .get({ at, key, size }) as Row | undefined;
      if (!next) return { sizes };
      if (sizes.length === MAX_SIZES) return { sizes, truncated: true };
      size = Number(next.lot_size);
      const [cheapest] = this.lotPage(at, key, size, 1);
      sizes.push({ size, cheapest: cheapest! });
    }
  }

  /**
   * Q3: the sales of `(key, size)` whose block time is in `(T - 7 days, T]`, T the time of block
   * `block`: their count, and their mean lot price (the floor of the sum over the count) when
   * there are at least 5, else no mean (absent, not zero).
   */
  price(
    block: Header,
    key: bigint,
    size: number,
  ): {
    sales: number;
    mean?: string;
    window: { after: number; until: number };
  } {
    const until = block.timestamp;
    const after = until - PRICE_WINDOW_SECONDS;
    // One aggregate row, from the index `lots_sales` alone (market_key, lot_size, closed_time,
    // price_hi, price_lo, _from, _to WHERE sold = 1): a range seek on the key, the size and the
    // window, memory bounded whatever the number of sales. A u64 price is summed as its two 32-bit
    // halves (SQLite's integers are signed 64-bit): each sum stays below 2^63 up to 2^31 sales in the
    // window, and SQLite raises an error rather than wrap past it. The sums are read only from 5
    // sales on.
    const row = this.store
      .statement(
        `SELECT count(*) AS sales,
           CASE WHEN count(*) >= :min THEN sum(price_hi) END AS hi,
           CASE WHEN count(*) >= :min THEN sum(price_lo) END AS lo
         FROM lots INDEXED BY lots_sales
         WHERE market_key = :key AND lot_size = :size AND sold = 1 AND ${AS_OF}
           AND closed_time > :after AND closed_time <= :until`,
        true,
      )
      .get({
        at: block.number,
        key,
        size,
        after,
        until,
        min: MIN_SALES,
      }) as { sales: bigint; hi: bigint | null; lo: bigint | null };
    const window = { after, until };
    const sales = Number(row.sales);
    if (row.hi === null || row.lo === null) return { sales, window };
    const sum = (row.hi << 32n) + row.lo;
    return { sales, mean: (sum / row.sales).toString(), window };
  }

  /**
   * Q4: the adventurers in hub `hub` at `at`, by id, `limit` after `after`; and their count (-1
   * when not `counted`: a snapshot's later pages).
   */
  presence(
    at: number,
    hub: number,
    limit: number,
    after = -1,
    counted = true,
  ): { count: number; adventurers: number[] } {
    const count = counted
      ? Number(
          this.get(
            `SELECT count(*) AS count FROM presence WHERE hub = :hub AND ${AS_OF}`,
            { at, hub },
          ).count,
        )
      : -1;
    const adventurers = this.all(
      `SELECT adventurer FROM presence
       WHERE hub = :hub AND ${AS_OF} AND adventurer > :after
       ORDER BY adventurer LIMIT :limit`,
      { at, hub, after, limit },
    ).map((row) => Number(row.adventurer));
    return { count, adventurers };
  }

  /** Q5: the displayed title of each adventurer at `at`, in the order asked; null for none. */
  titles(
    at: number,
    adventurers: number[],
  ): (Title | { adventurer: number; title: null })[] {
    const rows = this.all(
      `SELECT adventurer, title, tier FROM titles
       WHERE adventurer IN (SELECT value FROM json_each(:ids)) AND ${AS_OF}`,
      { at, ids: JSON.stringify(adventurers) },
    );
    const found = new Map(
      rows.map((row) => [
        Number(row.adventurer),
        {
          adventurer: Number(row.adventurer),
          title: Number(row.title),
          tier: Number(row.tier),
        },
      ]),
    );
    return adventurers.map(
      (adventurer) => found.get(adventurer) ?? { adventurer, title: null },
    );
  }

  /**
   * Q7: the trades open at block `block` that invite `invited`, opened under 10 minutes of block
   * time before it (`T - opened < 600`), by trade id; `limit` after the trade `after`.
   */
  invitations(
    block: Header,
    invited: number,
    limit = Number.MAX_SAFE_INTEGER,
    after?: bigint,
    counted = true,
  ): { total: number; invitations: Invitation[] } {
    const params = {
      at: block.number,
      invited,
      after: block.timestamp - INVITATION_SECONDS,
      until: block.timestamp,
    };
    const where = `invited = :invited AND open = 1 AND ${AS_OF}
      AND opened_time > :after AND opened_time <= :until`;
    const total = counted
      ? Number(
          this.get(
            `SELECT count(*) AS count FROM trades WHERE ${where}`,
            params,
          ).count,
        )
      : -1;
    const rows = this.all(
      `SELECT trade, invited, inviter, opened, opened_time FROM trades
       WHERE ${where} AND trade > :cursor ORDER BY trade LIMIT :limit`,
      { ...params, cursor: after === undefined ? "" : u64Text(after), limit },
    );
    return { total, invitations: rows.map(invitationOut) };
  }

  /**
   * The invitations of `invited` that appeared (`added`) or went away (`removed`, by trade id) in
   * each block of `(from, to]`, by events or by block time alone. Two queries for the whole range
   * (its blocks, then every trade version that may be shown in it), then each block's set is
   * compared with the one before, in memory.
   */
  invitationChanges(
    invited: number,
    from: Header,
    to: number,
  ): Map<number, { added: Invitation[]; removed: string[] }> {
    const blocks = this.all(
      `SELECT number, timestamp FROM blocks
       WHERE number > :from AND number <= :to ORDER BY number`,
      { from: from.number, to },
    ).map((row) => ({
      number: Number(row.number),
      timestamp: Number(row.timestamp),
    }));
    const changes = new Map<
      number,
      { added: Invitation[]; removed: string[] }
    >();
    if (blocks.length === 0) return changes;
    const earliest = Math.min(
      from.timestamp,
      ...blocks.map((block) => block.timestamp),
    );
    const versions = this.all(
      `SELECT trade, invited, inviter, opened, opened_time, _from, _to FROM trades
       WHERE invited = :invited AND open = 1 AND _from <= :to
         AND (_to IS NULL OR _to > :from) AND opened_time > :after`,
      {
        invited,
        from: from.number,
        to,
        after: earliest - INVITATION_SECONDS,
      },
    );
    const shown = (number: number, timestamp: number) =>
      new Map(
        versions
          .filter(
            (row) =>
              Number(row._from) <= number &&
              (row._to === null || Number(row._to) > number) &&
              Number(row.opened_time) > timestamp - INVITATION_SECONDS &&
              Number(row.opened_time) <= timestamp,
          )
          .map((row) => {
            const invitation = invitationOut(row);
            return [invitation.trade, invitation] as const;
          }),
      );
    let before = shown(from.number, from.timestamp);
    for (const block of blocks) {
      const now = shown(block.number, block.timestamp);
      const added = [...now.values()].filter(
        (invitation) => !before.has(invitation.trade),
      );
      const removed = [...before.keys()].filter((trade) => !now.has(trade));
      if (added.length || removed.length)
        changes.set(block.number, { added, removed });
      before = now;
    }
    return changes;
  }

  // --- changes between two blocks (the subscriptions) --------------------------------------------

  /** The open version of lot `lot` (u64 text) at `at`, if the lot is open then. */
  private openLot(lot: string, at: number): Lot | null {
    const row = this.store
      .statement(
        `SELECT ${LOT_COLUMNS} FROM lots
         WHERE lot = :lot AND open = 1 AND ${AS_OF}`,
      )
      .get({ lot, at }) as Row | undefined;
    return row ? lotOut(row) : null;
  }

  /**
   * The lots of `(key, size)` whose openness changed in a block of `(from, to]`: per block, in
   * block order, the lots it opened (`added`) and those it closed (`removed`, by id). A lot posted
   * and closed in one block changes nothing.
   */
  lotChanges(
    key: bigint,
    size: number,
    from: number,
    to: number,
  ): Map<number, { added: Lot[]; removed: string[] }> {
    const touched = this.all(
      `SELECT lot, _from AS block FROM lots
         WHERE market_key = :key AND lot_size = :size AND _from > :from AND _from <= :to
       UNION
       SELECT lot, _to AS block FROM lots
         WHERE market_key = :key AND lot_size = :size AND _to > :from AND _to <= :to
       ORDER BY block, lot`,
      { key, size, from, to },
    );
    const changes = new Map<number, { added: Lot[]; removed: string[] }>();
    for (const row of touched) {
      const block = Number(row.block);
      const lot = String(row.lot);
      const before = this.openLot(lot, block - 1);
      const after = this.openLot(lot, block);
      if (Boolean(before) === Boolean(after)) continue;
      const change = changes.get(block) ?? { added: [], removed: [] };
      if (after) change.added.push(after);
      else change.removed.push(u64Decimal(lot));
      changes.set(block, change);
    }
    return changes;
  }

  private inHub(adventurer: number, hub: number, at: number): boolean {
    return (
      this.store
        .statement(
          `SELECT 1 FROM presence WHERE adventurer = :adventurer AND hub = :hub AND ${AS_OF}`,
        )
        .get({ adventurer, hub, at }) !== undefined
    );
  }

  /** The adventurers who entered (`added`) or left (`removed`) hub `hub` in a block of `(from, to]`. */
  presenceChanges(
    hub: number,
    from: number,
    to: number,
  ): Map<number, { added: number[]; removed: number[] }> {
    const touched = this.all(
      `SELECT adventurer, _from AS block FROM presence
         WHERE hub = :hub AND _from > :from AND _from <= :to
       UNION
       SELECT adventurer, _to AS block FROM presence
         WHERE hub = :hub AND _to > :from AND _to <= :to
       ORDER BY block, adventurer`,
      { hub, from, to },
    );
    const changes = new Map<number, { added: number[]; removed: number[] }>();
    for (const row of touched) {
      const block = Number(row.block);
      const adventurer = Number(row.adventurer);
      const before = this.inHub(adventurer, hub, block - 1);
      const after = this.inHub(adventurer, hub, block);
      if (before === after) continue;
      const change = changes.get(block) ?? { added: [], removed: [] };
      (after ? change.added : change.removed).push(adventurer);
      changes.set(block, change);
    }
    return changes;
  }
}
