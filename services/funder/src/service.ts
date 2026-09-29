import { NetworkRefused, NotSent, type FundingChain } from "./chain.ts";
import type { Grant, Ledger } from "./ledger.ts";

/**
 * The funding service's rules (FND-08), with no network or HTTP of its own: the chain and the
 * ledger are given, so the unit tests drive every guard offline. In the order they apply:
 * 1. the request names a public key on the curve, and the address it gives, if any, is that key's;
 * 2. a key is funded once: a key with a grant gets the grant's answer again, and nothing is sent;
 *    requests for the same key at the same time share one answer;
 * 3. an account that exists already is never funded;
 * 4. one funding at a time holds the funding account (fix loop 1, F-1): a funding waits until the
 *    nonce of the one before is consumed (or known never to be), then signs with the next nonce;
 * 5. at that moment, and only then (fix loop 1, F-2), the caps are checked and taken: a client
 *    signs at most `clientRate` fundings per hour, and all clients together at most `dailyBudget`
 *    per day (UTC), counted on the clock at signing; they are given back only when nothing was sent;
 * 6. the chain module checks the network and the fee cap before it signs (`chain.ts`).
 * Checks 5 are also made, without taking anything, before a request queues, so that a request
 * bound to be refused does not wait.
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
  /**
   * How long a nonce stays held with no sign of its execution (the node does not know it, or the
   * send failed with no answer) before it counts as never consumed. While the execution is known
   * to the node, the nonce stays held however long it takes.
   */
  readonly holdMs: number;
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

type Sent =
  | { kind: "sent"; transaction: string }
  | { kind: "limited" | "exhausted" | "refused" | "unavailable" };

export function createFundingService(options: ServiceOptions): FundingService {
  const { chain, ledger, limits } = options;
  const now = options.now ?? Date.now;
  const sleep = options.sleep ?? ((ms) => new Promise<void>((done) => setTimeout(done, ms)));
  const event = options.onEvent ?? (() => undefined);
  const inflight = new Map<string, Promise<Outcome>>();
  // The funding account is used by one funding at a time, from its nonce's hold to its signature.
  let queue: Promise<unknown> = Promise.resolve();

  function queued<T>(work: () => Promise<T>): Promise<T> {
    const run = queue.then(work);
    queue = run.catch(() => undefined);
    return run;
  }

  /** What the caps say now: `undefined` when a funding fits. */
  function capped(client: string, at: number): "limited" | "exhausted" | undefined {
    if (ledger.times(client, at - limits.windowMs).length >= limits.clientRate) return "limited";
    if (ledger.spent(dayOf(at)) >= limits.dailyBudget) return "exhausted";
    return undefined;
  }

  /**
   * Waits until the nonce held by the last funding is consumed, or known never to be; `false` when
   * that takes longer than a request may wait (the hold stays, nothing is sent).
   */
  async function released(): Promise<boolean> {
    const until = now() + limits.settleMs;
    for (;;) {
      const hold = ledger.hold();
      if (!hold) return true;
      if ((await chain.nonce()) > BigInt(hold.nonce)) {
        ledger.setHold(undefined);
        return true;
      }
      // The nonce is not consumed. It stays held while the node knows the execution; it is let go
      // when nothing has shown for `holdMs`: the execution never reached the node. If it does
      // after all, it and the next funding share one nonce, and only one of them can execute.
      const known = hold.transaction ? (await chain.status(hold.transaction)) !== "unknown" : false;
      if (!known && now() - hold.at >= limits.holdMs) {
        event("released", { nonce: hold.nonce });
        ledger.setHold(undefined);
        return true;
      }
      if (now() >= until) return false;
      await sleep(limits.pollMs);
    }
  }

  /** Holds the funding account, takes the caps, signs and sends. Runs in the queue only. */
  async function send(publicKey: string, address: string, client: string): Promise<Sent> {
    if (!(await released())) return { kind: "unavailable" };
    const at = now();
    const day = dayOf(at);
    const full = capped(client, at);
    if (full) {
      event(full, { address });
      return { kind: full };
    }
    ledger.spend(day, 1);
    ledger.addTime(client, at);
    const giveBack = () => {
      ledger.spend(day, -1);
      ledger.removeTime(client, at);
    };
    let nonce: bigint;
    try {
      nonce = await chain.nonce();
    } catch {
      giveBack();
      return { kind: "unavailable" };
    }
    // Held before signing: a stop from here on leaves the hold in the file.
    ledger.setHold({ nonce: String(nonce), at });
    try {
      const transaction = await chain.fund(publicKey, address, nonce);
      ledger.setHold({ nonce: String(nonce), transaction, at });
      return { kind: "sent", transaction };
    } catch (error) {
      if (error instanceof NotSent) {
        // Nothing reached the node: the caps and the nonce are free again.
        giveBack();
        ledger.setHold(undefined);
        event("refused", { address, reason: error.message });
        return { kind: error instanceof NetworkRefused ? "refused" : "unavailable" };
      }
      // It may have been sent: the caps stay spent and the nonce held, until it is consumed or
      // `holdMs` shows nothing of it.
      event("send-failed", { address, reason: error instanceof Error ? error.name : "unknown" });
      return { kind: "unavailable" };
    }
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
    // A request bound to be refused is refused before it waits; nothing is taken here.
    const full = capped(client, now());
    if (full) {
      event(full, { address });
      return { kind: full };
    }
    if (await chain.isDeployed(address)) {
      const done: Grant = { address, status: "succeeded" };
      ledger.setGrant(publicKey, done);
      event("exists", { address });
      return provided(done, true);
    }

    ledger.setGrant(publicKey, { address, status: "sending" });
    let sent: Sent;
    try {
      sent = await queued(() => send(publicKey, address, client));
    } catch (error) {
      ledger.setGrant(publicKey, undefined);
      throw error;
    }
    if (sent.kind !== "sent") {
      // Not sent, or perhaps sent and unanswered: the key may ask again. If it was deployed after
      // all, the chain refuses a second deployment and its transfer with it.
      ledger.setGrant(publicKey, undefined);
      return sent;
    }

    const { transaction } = sent;
    const pending: Grant = { address, transaction, status: "pending" };
    ledger.setGrant(publicKey, pending);
    event("sent", { address, transaction });
    const status = await settle(transaction);
    if (status === "failed") {
      ledger.setGrant(publicKey, undefined);
      event("failed", { address, transaction });
      return { kind: "failed", address, transaction };
    }
    const grant: Grant = { ...pending, status: status === "succeeded" ? "succeeded" : "pending" };
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
