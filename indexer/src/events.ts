// The nine events of the indexer, frozen by ENG-01 (docs/architecture/ENG-01-interfaces.md §5,
// contracts/persistent/src/events.cairo): Hub emits the first five, Market the last four. The
// first key is the selector of the event's name; then the declared keys, then the data, in the
// declared order. Decoding is strict: a selector of neither list, a count of keys or data that
// differs, or a value wider than its type is a DecodeError, and the indexer halts on it (it never
// guesses). A change of layout is a new event name (ENG-01 §5), decoded beside the old one.
import { hash } from "starknet";

export type Source = "hub" | "market";

export class DecodeError extends Error {}

/** The market key of ENG-01 §3.4 (`models::market::market_key`), decoded. */
export type MarketKey =
  | { kind: "balance"; item: number }
  | {
      kind: "equipment";
      base: number;
      requirement: number;
      rarity: number;
      identified: boolean;
    }
  | { kind: "boss"; base: number };

export type Decoded =
  | { name: "AdventurerLocated"; hub: number; adventurer: number }
  | { name: "TitleDisplayed"; adventurer: number; title: number; tier: number }
  | {
      name: "TrialPassed";
      adventurer: number;
      rank: number;
      firstAttempt: boolean;
    }
  | { name: "DungeonCleared"; adventurer: number; dungeon: number }
  | { name: "RankReached"; adventurer: number; rank: number }
  | {
      name: "LotPosted";
      marketKey: bigint;
      key: MarketKey;
      lotSize: number;
      lot: bigint;
      price: bigint;
      expiry: bigint;
      equipment: number;
      modifiers: bigint;
    }
  | { name: "LotClosed"; lot: bigint; sold: boolean }
  | { name: "TradeOpened"; invited: number; trade: bigint; inviter: number }
  | { name: "TradeClosed"; trade: bigint; outcome: 0 | 1 | 2 };

export type EventName = Decoded["name"];

export const EVENTS: Record<Source, readonly EventName[]> = {
  hub: [
    "AdventurerLocated",
    "TitleDisplayed",
    "TrialPassed",
    "DungeonCleared",
    "RankReached",
  ],
  market: ["LotPosted", "LotClosed", "TradeOpened", "TradeClosed"],
};

/** Selector (a lowercase 0x hex without leading zeros) of every event, by name. */
export const SELECTORS = Object.fromEntries(
  [...EVENTS.hub, ...EVENTS.market].map((name) => [
    name,
    canonical(hash.getSelectorFromName(name)),
  ]),
) as Record<EventName, string>;

const bySelector: Record<Source, Map<string, EventName>> = {
  hub: new Map(EVENTS.hub.map((name) => [SELECTORS[name], name])),
  market: new Map(EVENTS.market.map((name) => [SELECTORS[name], name])),
};

const FELT_PRIME = 2n ** 251n + 17n * 2n ** 192n + 1n;

/** A felt from its JSON-RPC form (0x hex); anything else is a DecodeError. */
export function felt(value: string | undefined): bigint {
  if (value === undefined || !/^0x[0-9a-fA-F]{1,64}$/.test(value)) {
    throw new DecodeError(`${JSON.stringify(value)} is not a felt`);
  }
  const number = BigInt(value);
  if (number >= FELT_PRIME) throw new DecodeError(`${value} is not a felt`);
  return number;
}

/** The canonical text of a felt: lowercase 0x hex, no leading zeros. */
export function canonical(value: string | bigint): string {
  return `0x${BigInt(value).toString(16)}`;
}

function uint(value: string | undefined, bits: number, field: string): bigint {
  const number = felt(value);
  if (number >= 1n << BigInt(bits)) {
    throw new DecodeError(`${field} ${value} is wider than u${bits}`);
  }
  return number;
}
const small = (value: string | undefined, bits: 8 | 16 | 32, field: string) =>
  Number(uint(value, bits, field));
function bool(value: string | undefined, field: string): boolean {
  const number = felt(value);
  if (number > 1n) throw new DecodeError(`${field} ${value} is not a bool`);
  return number === 1n;
}

const TWO_32 = 1n << 32n;
const TWO_40 = 1n << 40n;
const TWO_41 = 1n << 41n;
const TWO_16 = 1n << 16n;

/**
 * ENG-01 §3.4: a balance is its item id (u32); equipment `2^40 + base × 2^16 + requirement × 2^8
 * + rarity × 2 + identified`; a boss item `2^41 + base`. Any other felt is a DecodeError.
 */
export function decodeMarketKey(key: bigint): MarketKey {
  if (key < TWO_32) return { kind: "balance", item: Number(key) };
  if (key >= TWO_40 && key < TWO_41) {
    const rest = key - TWO_40;
    const base = rest >> 16n;
    if (base >= TWO_16) throw new DecodeError(`market key ${canonical(key)}`);
    return {
      kind: "equipment",
      base: Number(base),
      requirement: Number((rest >> 8n) & 0xffn),
      rarity: Number((rest >> 1n) & 0x7fn),
      identified: (rest & 1n) === 1n,
    };
  }
  if (key >= TWO_41 && key < TWO_41 + TWO_16) {
    return { kind: "boss", base: Number(key - TWO_41) };
  }
  throw new DecodeError(
    `market key ${canonical(key)} is none of ENG-01's encodings`,
  );
}

function shape(
  name: EventName,
  keys: readonly string[],
  data: readonly string[],
  keyCount: number,
  dataCount: number,
) {
  if (keys.length !== 1 + keyCount || data.length !== dataCount) {
    throw new DecodeError(
      `${name}: ${keys.length - 1} keys and ${data.length} data, expected ${keyCount} and ${dataCount}`,
    );
  }
}

/** The event of `source` with these raw keys and data; a DecodeError if it is none of the nine. */
export function decode(
  source: Source,
  keys: readonly string[],
  data: readonly string[],
): Decoded {
  const selector = keys[0] === undefined ? undefined : canonical(felt(keys[0]));
  const name =
    selector === undefined ? undefined : bySelector[source].get(selector);
  if (name === undefined) {
    throw new DecodeError(
      `unknown event of ${source}: selector ${selector ?? "(none)"}`,
    );
  }
  switch (name) {
    case "AdventurerLocated":
      shape(name, keys, data, 1, 1);
      return {
        name,
        hub: small(keys[1], 16, "hub"),
        adventurer: small(data[0], 32, "adventurer"),
      };
    case "TitleDisplayed":
      shape(name, keys, data, 1, 2);
      return {
        name,
        adventurer: small(keys[1], 32, "adventurer"),
        title: small(data[0], 16, "title"),
        tier: small(data[1], 8, "tier"),
      };
    case "TrialPassed":
      shape(name, keys, data, 1, 2);
      return {
        name,
        adventurer: small(keys[1], 32, "adventurer"),
        rank: small(data[0], 8, "rank"),
        firstAttempt: bool(data[1], "first_attempt"),
      };
    case "DungeonCleared":
      shape(name, keys, data, 1, 1);
      return {
        name,
        adventurer: small(keys[1], 32, "adventurer"),
        dungeon: small(data[0], 16, "dungeon"),
      };
    case "RankReached":
      shape(name, keys, data, 1, 1);
      return {
        name,
        adventurer: small(keys[1], 32, "adventurer"),
        rank: small(data[0], 8, "rank"),
      };
    case "LotPosted": {
      shape(name, keys, data, 2, 5);
      const marketKey = felt(keys[1]);
      return {
        name,
        marketKey,
        key: decodeMarketKey(marketKey),
        lotSize: small(keys[2], 8, "lot_size"),
        lot: uint(data[0], 64, "lot"),
        price: uint(data[1], 64, "price"),
        expiry: uint(data[2], 64, "expiry"),
        equipment: small(data[3], 32, "equipment"),
        modifiers: felt(data[4]),
      };
    }
    case "LotClosed":
      shape(name, keys, data, 1, 1);
      return {
        name,
        lot: uint(keys[1], 64, "lot"),
        sold: bool(data[0], "sold"),
      };
    case "TradeOpened":
      shape(name, keys, data, 1, 2);
      return {
        name,
        invited: small(keys[1], 32, "invited"),
        trade: uint(data[0], 64, "trade"),
        inviter: small(data[1], 32, "inviter"),
      };
    case "TradeClosed": {
      shape(name, keys, data, 1, 1);
      const outcome = small(data[0], 8, "outcome");
      if (outcome !== 0 && outcome !== 1 && outcome !== 2) {
        throw new DecodeError(
          `TradeClosed: outcome ${outcome} is not 0, 1 or 2`,
        );
      }
      return { name, trade: uint(keys[1], 64, "trade"), outcome };
    }
  }
}
