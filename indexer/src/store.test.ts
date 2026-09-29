import { describe, expect, it } from "vitest";
import type { Header, RawEvent } from "./chain.ts";
import { decode } from "./events.ts";
import { Halt, Store, type Applied, type Config } from "./store.ts";
import { HUB, MARKET, ev, type FakeEvent } from "./testing/fake-node.ts";

const config: Config = {
  hub: HUB,
  market: MARKET,
  from: 1,
  lotCount: 0n,
  tradeCount: 0n,
};

function store(options: Partial<Config> = {}) {
  const s = new Store(":memory:");
  s.open({ ...config, ...options });
  return s;
}

const header = (number: number): Header => ({
  number,
  hash: `0xb${number}`,
  parent: `0xb${number - 1}`,
  commitments: `0xc${number}`,
  timestamp: 1000 + number,
});

function applied(...events: FakeEvent[]): Applied[] {
  return events.map((event, index) => {
    const raw: RawEvent = {
      ...event,
      transaction: "0x7",
      transactionIndex: 0,
      eventIndex: index,
    };
    return { raw, event: decode(event.source, event.keys, event.data) };
  });
}

describe("the store", () => {
  it("keeps versions: a lot posted then sold, readable at each block", () => {
    const s = store();
    s.apply(header(1), applied(ev.posted(1, { price: 500n })));
    s.apply(header(2), applied(ev.closed(1, true)));
    expect(s.at("lots", 1)).toMatchObject([
      { lot: "1", price: "500", open: 1, sold: 0, _from: 1, _to: 2 },
    ]);
    expect(s.at("lots", 2)).toMatchObject([
      {
        lot: "1",
        price: "500",
        open: 0,
        sold: 1,
        posted: 1,
        _from: 2,
        _to: null,
      },
    ]);
    expect(s.countsAt(1)).toMatchObject({ lots: 1, events: 1 });
    expect(s.countsAt(2)).toMatchObject({ lots: 1, events: 2 });
  });

  it("orders u64 prices like the numbers, losslessly, and serves them as decimal strings", () => {
    const s = store();
    const prices = [2n ** 64n - 1n, 2n ** 53n + 1n, 2n ** 63n, 255n, 256n];
    s.apply(
      header(1),
      applied(...prices.map((price, i) => ev.posted(i + 1, { price }))),
    );
    const ordered = s.at("lots", 1).map((row) => row.price);
    expect(new Set(ordered)).toEqual(new Set(prices.map(String)));
    const byPrice = [...prices].sort((a, b) => (a < b ? -1 : 1)).map(String);
    // The stored text sorts like the numbers.
    const texts = prices.map((p) => p.toString(16).padStart(16, "0")).sort();
    expect(texts.map((t) => BigInt(`0x${t}`).toString())).toEqual(byPrice);
  });

  it("decodes the market key into its columns", () => {
    const s = store();
    const equipment =
      2n ** 40n + 7n * 2n ** 16n + 12n * 2n ** 8n + 3n * 2n + 1n;
    s.apply(
      header(1),
      applied(
        ev.posted(1, { key: 77n }),
        ev.posted(2, { key: equipment, modifiers: 0xabcn }),
        ev.posted(3, { key: 2n ** 41n + 5n }),
      ),
    );
    expect(
      s
        .at("lots", 1)
        .map(
          ({
            kind,
            item,
            base,
            requirement,
            rarity,
            identified,
            modifiers,
          }) => ({
            kind,
            item,
            base,
            requirement,
            rarity,
            identified,
            modifiers,
          }),
        ),
    ).toEqual([
      {
        kind: "balance",
        item: 77,
        base: null,
        requirement: null,
        rarity: null,
        identified: null,
        modifiers: "0x0",
      },
      {
        kind: "equipment",
        item: null,
        base: 7,
        requirement: 12,
        rarity: 3,
        identified: 1,
        modifiers: "0xabc",
      },
      {
        kind: "boss",
        item: null,
        base: 5,
        requirement: null,
        rarity: null,
        identified: null,
        modifiers: "0x0",
      },
    ]);
  });

  it("keeps presence, titles and ranks current per adventurer, and trial passes and clears as facts", () => {
    const s = store();
    s.apply(
      header(1),
      applied(
        ev.located(3, 9),
        ev.title(9, 4, 2),
        ev.rank(9, 1),
        ev.trial(9, 1, true),
        ev.cleared(9, 6),
      ),
    );
    s.apply(
      header(2),
      applied(
        ev.located(0, 9),
        ev.located(5, 9),
        ev.title(9, 5, 1),
        ev.rank(9, 2),
        ev.trial(9, 2, false),
        ev.cleared(9, 6),
      ),
    );
    expect(s.at("presence", 2)).toMatchObject([{ adventurer: 9, hub: 5 }]);
    expect(s.at("presence", 1)).toMatchObject([{ adventurer: 9, hub: 3 }]);
    expect(s.at("titles", 2)).toMatchObject([{ title: 5, tier: 1 }]);
    expect(s.at("ranks", 2)).toMatchObject([{ rank: 2 }]);
    expect(s.at("trial_passes", 2)).toHaveLength(2);
    expect(s.at("clears", 2)).toHaveLength(2);
    expect(s.at("clears", 1)).toHaveLength(1);
  });

  it("opens and closes trades with their three outcomes", () => {
    const s = store();
    s.apply(
      header(1),
      applied(ev.opened(1, 12, 9), ev.opened(2, 12, 9), ev.opened(3, 13, 9)),
    );
    s.apply(
      header(2),
      applied(ev.tradeClosed(1, 0), ev.tradeClosed(2, 1), ev.tradeClosed(3, 2)),
    );
    expect(
      s
        .at("trades", 2)
        .map((row) => [row.trade, row.open, row.outcome, row.opened]),
    ).toEqual([
      ["1", 0, 0, 1],
      ["2", 0, 1, 1],
      ["3", 0, 2, 1],
    ]);
  });

  it("rewinds every table in one go: versions born after the block go, those closed after it reopen", () => {
    const s = store();
    s.apply(
      header(1),
      applied(ev.posted(1), ev.located(3, 9), ev.opened(1, 12, 9)),
    );
    const before = s.dump();
    s.apply(
      header(2),
      applied(
        ev.closed(1, false),
        ev.located(4, 9),
        ev.tradeClosed(1, 2),
        ev.posted(2),
        ev.trial(9, 1, true),
      ),
    );
    s.apply(header(3), applied(ev.posted(3)));
    s.rewind(1);
    expect(s.dump()).toEqual(before);
    expect(s.tip()?.number).toBe(1);
    expect(s.counters()).toEqual({ lotCount: 1n, tradeCount: 1n });
  });

  it("halts on a gap in lot or trade ids, and on a close of what is not open, leaving the tables as they were", () => {
    const s = store();
    s.apply(header(1), applied(ev.posted(1), ev.opened(1, 12, 9)));
    const before = s.dump();
    expect(() => s.apply(header(2), applied(ev.posted(3)))).toThrow(Halt);
    expect(() =>
      s.apply(header(2), applied(ev.posted(2), ev.opened(3, 1, 1))),
    ).toThrow(/gap: TradeOpened of trade 3/);
    expect(() => s.apply(header(2), applied(ev.closed(9, true)))).toThrow(
      /no such lot/,
    );
    expect(() =>
      s.apply(header(2), applied(ev.closed(1, true), ev.closed(1, false))),
    ).toThrow(/not open/);
    expect(() => s.apply(header(2), applied(ev.tradeClosed(4, 0)))).toThrow(
      /no such trade/,
    );
    expect(s.dump()).toEqual(before);
  });

  it("starts the id counters where the configuration says (a start after deployment)", () => {
    const s = store({ lotCount: 2n ** 64n - 3n, tradeCount: 2n ** 64n - 2n });
    s.apply(
      header(1),
      applied(
        ev.posted(2n ** 64n - 2n),
        ev.posted(2n ** 64n - 1n),
        ev.opened(2n ** 64n - 1n, 1, 2),
      ),
    );
    expect(s.at("lots", 1).map((row) => row.lot)).toEqual([
      "18446744073709551614",
      "18446744073709551615",
    ]);
    expect(s.counters()).toEqual({
      lotCount: 2n ** 64n - 1n,
      tradeCount: 2n ** 64n - 1n,
    });
  });

  it("prunes what no kept block can read, and keeps what it can", () => {
    const s = store();
    s.apply(header(1), applied(ev.posted(1), ev.located(1, 9)));
    s.apply(header(2), applied(ev.closed(1, true), ev.located(2, 9)));
    s.apply(header(3), applied(ev.located(3, 9)));
    const atThree = s.at("presence", 3);
    s.prune(3);
    expect(s.lowest()?.number).toBe(3);
    expect(s.at("presence", 3)).toEqual(atThree);
    expect(s.at("lots", 3)).toMatchObject([{ lot: "1", open: 0, sold: 1 }]);
    expect(s.dump().presence).toHaveLength(1);
    expect(s.dump().events).toHaveLength(5); // raw events are kept
  });

  it("refuses a database built for other contracts", () => {
    const s = store();
    expect(() => s.open({ ...config, hub: "0x9" })).toThrow(/rebuild it/);
    s.open({ ...config, hub: "0x01111" }); // the same address, written otherwise
  });
});
