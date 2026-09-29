import { FeeRefused, NetworkRefused, type FundingChain } from "./chain.ts";
import type { Grant, Ledger } from "./ledger.ts";

/**
 * The funding service's rules (FND-08), with no network or HTTP of its own: the chain and the
 * ledger are given, so the unit tests drive every guard offline. In the order they apply:
 * 1. the request names a public key on the curve, and the address it gives, if any, is that key's;
 * 2. a key is funded once: a key with a grant gets the grant's answer again, and nothing is sent;
 *    requests for the same key at the same time share one answer;
 * 3. a client funds at most `clientRate` new keys per hour;
 * 4. all clients together fund at most `dailyBudget` new keys per day (UTC);
 * 5. an account that exists already is never funded;
 * 6. the chain module checks the network and the fee cap before it signs (`chain.ts`).
 * A funding counts against both caps from the moment it is decided, before anything is sent, and
 * is given back only when nothing was signed.
 */

export type Outcome =
  | {
      kind: "provided";
      address: string;
      status: "succeeded" | "pending";
      transaction?: string;
      /** The key had been funded already: this answer sent nothing. */
      repeated: boolean;
    }
  | { kind: "failed"; address: string; transaction: string }
  | { kind: "invalid" | "limited" | "exhausted" | "refused" | "unavailable" };

export interface Limits {
  readonly dailyBudget: number;
  readonly clientRate: number;
  /** The client rate's window, in milliseconds (an hour). */
  readonly windowMs: number;
  /** How long a request waits for its funding to settle before answering `pending`. */
  readonly settleMs: number;
  readonly pollMs: number;
}

export interface ServiceOptions {
  chain: FundingChain;
  ledger: Ledger;
  limits: Limits;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
  /** What happened, for the log: public values only (addresses, execution ids, reasons). */
  onEvent?: (event: string, fields: Record<string, string>) => void;
}

export interface FundingService {
  /** `request` is the parsed body of a request; `client` who sent it (an address, or a /64). */
  fund(request: unknown, client: string): Promise<Outcome>;
}

const FELT = /^0x[0-9a-fA-F]{1,64}$/;
export const HOUR_MS = 3_600_000;

function dayOf(at: number): string {
  return new Date(at).toISOString().slice(0, 10);
}

function parse(request: unknown): { publicKey: string; address?: string } | undefined {
  if (typeof request !== "object" || request === null) return undefined;
  const { publicKey, address } = request as Record<string, unknown>;
  if (typeof publicKey !== "string") return undefined;
  if (address !== undefined && (typeof address !== "string" || !FELT.test(address))) {
    return undefined;
  }
  return { publicKey, address };
}

export function createFundingService(options: ServiceOptions): FundingService {
  const { chain, ledger, limits } = options;
  const now = options.now ?? Date.now;
  const sleep = options.sleep ?? ((ms) => new Promise<void>((done) => setTimeout(done, ms)));
  const event = options.onEvent ?? (() => undefined);
  const inflight = new Map<string, Promise<Outcome>>();
  // The times of each client's fundings in the last window. An entry is made only by a funding,
  // so the map holds at most `dailyBudget` times.
  const rates = new Map<string, number[]>();
  // The funder's executions go one after the other: two sent at once would race for its nonce.
  let queue: Promise<unknown> = Promise.resolve();

  function send(publicKey: string, address: string): Promise<string> {
    const sent = queue.then(() => chain.fund(publicKey, address));
    queue = sent.catch(() => undefined);
    return sent;
  }

  function recent(client: string, at: number): number[] {
    const times = (rates.get(client) ?? []).filter((t) => t > at - limits.windowMs);
    if (times.length > 0) rates.set(client, times);
    else rates.delete(client);
    return times;
  }

  function provided(grant: Grant, repeated: boolean): Outcome {
    return {
      kind: "provided",
      address: grant.address,
      status: grant.status === "succeeded" ? "succeeded" : "pending",
      ...(grant.transaction ? { transaction: grant.transaction } : {}),
      repeated,
    };
  }

  /** Waits for the execution to settle, up to `settleMs`; not known yet counts as pending. */
  async function settle(transaction: string): Promise<"succeeded" | "pending" | "failed"> {
    const until = now() + limits.settleMs;
    for (;;) {
      const status = await chain.status(transaction).catch(() => "pending" as const);
      if (status === "succeeded" || status === "failed") return status;
      if (now() >= until) return "pending";
      await sleep(limits.pollMs);
    }
  }

  /** A grant already kept for the key: its answer, or `undefined` when the key may be funded. */
  async function again(publicKey: string, grant: Grant): Promise<Outcome | undefined> {
    if (grant.status === "succeeded") return provided(grant, true);
    if (grant.transaction) {
      const status = await chain.status(grant.transaction);
      if (status === "pending") return provided(grant, true);
      if (status === "succeeded") {
        const done: Grant = { ...grant, status: "succeeded" };
        ledger.setGrant(publicKey, done);
        return provided(done, true);
      }
      // Reverted or dropped: nothing was given, the key may be funded again within the caps.
    } else if (await chain.isDeployed(grant.address)) {
      // Stopped while sending, and it went through.
      const done: Grant = { address: grant.address, status: "succeeded" };
      ledger.setGrant(publicKey, done);
      return provided(done, true);
    }
    ledger.setGrant(publicKey, undefined);
    return undefined;
  }

  async function provide(publicKey: string, address: string, client: string): Promise<Outcome> {
    const kept = ledger.grant(publicKey);
    if (kept) {
      const answer = await again(publicKey, kept);
      if (answer) return answer;
    }

    // The caps are checked and taken with no await in between: requests running at the same time
    // cannot all pass a check that only one of them fits.
    const at = now();
    const day = dayOf(at);
    const times = recent(client, at);
    if (times.length >= limits.clientRate) {
      event("limited", { address });
      return { kind: "limited" };
    }
    if (ledger.spent(day) >= limits.dailyBudget) {
      event("exhausted", { address });
      return { kind: "exhausted" };
    }
    ledger.spend(day, 1);
    rates.set(client, [...times, at]);
    const giveBack = () => {
      ledger.spend(day, -1);
      const mine = rates.get(client) ?? [];
      const index = mine.indexOf(at);
      if (index >= 0) mine.splice(index, 1);
      if (mine.length === 0) rates.delete(client);
    };

    try {
      if (await chain.isDeployed(address)) {
        giveBack();
        const done: Grant = { address, status: "succeeded" };
        ledger.setGrant(publicKey, done);
        event("exists", { address });
        return provided(done, true);
      }
    } catch (error) {
      giveBack();
      throw error;
    }

    ledger.setGrant(publicKey, { address, status: "sending" });
    let transaction: string;
    try {
      transaction = await send(publicKey, address);
    } catch (error) {
      ledger.setGrant(publicKey, undefined);
      if (error instanceof NetworkRefused || error instanceof FeeRefused) {
        // Nothing was signed for sending: the caps are given back.
        giveBack();
        event("refused", { address, reason: error.message });
        return { kind: error instanceof NetworkRefused ? "refused" : "unavailable" };
      }
      // It may have been sent: the caps stay spent. The key may ask again; if the account was
      // deployed after all, the chain refuses a second deployment and its transfer with it.
      event("send-failed", { address, reason: error instanceof Error ? error.name : "unknown" });
      return { kind: "unavailable" };
    }

    const sent: Grant = { address, transaction, status: "pending" };
    ledger.setGrant(publicKey, sent);
    event("sent", { address, transaction });
    const status = await settle(transaction);
    if (status === "failed") {
      ledger.setGrant(publicKey, undefined);
      event("failed", { address, transaction });
      return { kind: "failed", address, transaction };
    }
    const grant: Grant = { ...sent, status: status === "succeeded" ? "succeeded" : "pending" };
    ledger.setGrant(publicKey, grant);
    if (status === "succeeded") event("funded", { address, transaction });
    return provided(grant, false);
  }

  return {
    fund(request, client) {
      const parsed = parse(request);
      const derived = parsed && chain.addressOf(parsed.publicKey);
      if (!parsed || !derived) return Promise.resolve({ kind: "invalid" });
      if (parsed.address !== undefined && BigInt(parsed.address) !== BigInt(derived.address)) {
        return Promise.resolve({ kind: "invalid" });
      }
      const running = inflight.get(derived.publicKey);
      if (running) return running;
      const work = provide(derived.publicKey, derived.address, client)
        .catch((error: unknown): Outcome => {
          event("unavailable", { reason: error instanceof Error ? error.name : "unknown" });
          return { kind: "unavailable" };
        })
        .finally(() => inflight.delete(derived.publicKey));
      inflight.set(derived.publicKey, work);
      return work;
    },
  };
}
