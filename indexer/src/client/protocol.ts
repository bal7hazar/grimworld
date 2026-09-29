// What the indexer answers and streams (src/server.ts, src/subscriptions.ts), as the client reads
// it. This folder runs in a browser: no `node:` module, no import from outside it.

/** The block an answer is read at (R2). */
export type Head = {
  number: number;
  hash: string;
  commitments: string;
  /** The block's time, in seconds: the clock of Q3's window and Q7's expiry. */
  timestamp: number;
};

export type Status = "loading" | "ok" | "rewinding" | "halted";

/** A lot of Q1 and of the lots subscription: u64 values as decimal strings, felts as 0x hex. */
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

/** An open trade inviting an account (Q7), shown until `expiresAt` (block time). */
export type Invitation = {
  trade: string;
  invited: number;
  inviter: number;
  opened: number;
  openedTime: number;
  expiresAt: number;
};

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

/** Every answer of a query in state `ok`. */
export type Answered = { status: "ok"; head: Head; behind: number };

export type LotsAnswer = Answered & {
  total: number;
  lots: Lot[];
  /** The `after` of the next page, or null on the last one. */
  next: string | null;
};
export type MarketAnswer = Answered & {
  keys: {
    key: string;
    decoded: MarketKey;
    sizes: { size: number; open: number; cheapest: Lot }[];
  }[];
  next: string | null;
};
export type PriceAnswer = Answered & {
  sales: number;
  /** Absent under 5 sales (never zero for "no price"). */
  mean?: string;
  window: { after: number; until: number };
};
export type PresenceAnswer = Answered & {
  hub: number;
  count: number;
  adventurers: number[];
  next: string | null;
};
export type TitlesAnswer = Answered & {
  titles: (
    | { adventurer: number; title: number; tier: number }
    | { adventurer: number; title: null }
  )[];
};
export type InvitationsAnswer = Answered & {
  account: number;
  total: number;
  invitations: Invitation[];
  next: string | null;
};

/** A frame of a subscription's stream (src/subscriptions.ts has the protocol). */
export type Frame =
  | { event: "status"; data: { status: Status; reason?: string } }
  | { event: "reset-begin"; data: { head: Head; total: number } }
  | { event: "reset-page"; data: { rows: unknown[] } }
  | { event: "reset-end"; data: { head: Head; total: number } }
  | { event: "add"; data: { row: unknown } }
  | { event: "remove"; data: { id: string } }
  | { event: "head"; data: { head: Head } }
  | { event: "rewind"; data: { to: number } };

/** The canonical text of a felt: lowercase 0x hex, no leading zeros. */
export const canonical = (value: string): string =>
  `0x${BigInt(value).toString(16)}`;
