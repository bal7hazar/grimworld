import { NetworkRefused, type FundingChain, type Signed } from "./chain.ts";
import type { Grant, Hold, Ledger } from "./ledger.ts";

/**
 * The funding service's rules (FND-08), with no network or HTTP of its own: the chain and the
 * ledger are given, so the unit tests drive every guard offline. In the order they apply:
 * 1. the request names a public key on the curve, and the address it gives, if any, is that key's;
 * 2. a key is funded once: a key with a grant gets the grant's answer again, and nothing is sent;
 *    requests for the same key at the same time share one answer;
 * 3. an account that exists already is never funded;
 * 4. one funding at a time holds the funding account (fix loops 1 and 2, F-1): a funding waits
 *    until the nonce of the one before is consumed, then signs with the next nonce, and keeps the
 *    signed execution before handing it over; a nonce carries one execution, ever;
 * 5. the chain module checks the network and the fee cap before it signs (`chain.ts`);
 * 6. with no await between them and the handing (fix loop 2, F-2), the caps are checked and
 *    taken: at most `clientRate` executions handed to the node per client in any hour, and at most
 *    `dailyBudget` per UTC day for all clients together, counted at the moment of handing. Once
 *    taken they are never given back: from then on the execution may be on the chain.
 * Checks 6 are also made, without taking anything, before a request queues and before signing, so
 * that a request bound to be refused neither waits nor signs.
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

type Sent =
  | { kind: "sent"; transaction: string }
  | { kind: "lost"; transaction: string }
  | { kind: "exists" }
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
   * Waits until the nonce of the last execution handed to the node is consumed; `false` when that
   * takes longer than a request may wait (the hold stays, nothing is sent). A hold ends only on
   * that proof (fix loop 2, F-1), never on time and never on an `unknown`: until then, whenever
   * the node does not know the execution, the same signed execution is handed again. Its nonce
   * therefore never carries a second one.
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
      // A hold written before fix loop 2 has no signed execution to hand again: it waits for its
      // nonce like the others.
      if (hold.payload && (await chain.status(hold.transaction)) === "unknown") {
        await handAgain(hold);
      }
      if (now() >= until) return false;
      await sleep(limits.pollMs);
    }
  }

  /**
   * Hands the held execution again, as it was signed. The node does not know it, so this handing
   * may be its first arrival: it is counted like one, at this moment, and waits while the caps are
   * full. Counting it twice when the first did arrive only ever over-counts.
   */
  async function handAgain(hold: Hold): Promise<void> {
    try {
      await chain.verify(hold.payload);
    } catch {
      return;
    }
    // From here to the handing there is no await.
    const at = now();
    const client = hold.client ?? "";
    if (capped(client, at)) {
      event("held", { transaction: hold.transaction });
      return;
    }
    ledger.spend(dayOf(at), 1);
    ledger.addTime(client, at);
    ledger.setHold({ ...hold, client, at });
    event("resent", { transaction: hold.transaction });
    await chain.submit(hold.payload).catch(() => undefined);
  }

  /**
   * Holds the funding account, signs, takes the caps and hands the execution to the node. Runs in
   * the queue only. Every await comes before the caps are taken (fix loop 2, F-2): from the check
   * to the handing, the code runs without a pause, so the day and the hour that count an execution
   * are those of the moment it is handed to the node.
   */
  async function send(publicKey: string, address: string, client: string): Promise<Sent> {
    if (!(await released())) return { kind: "unavailable" };
    // Deployed while this request waited (a funding of the same key that was thought lost).
    if (await chain.isDeployed(address)) return { kind: "exists" };
    // Not signed for a request the caps refuse already; checked again, for good, below.
    const early = capped(client, now());
    if (early) {
      event(early, { address });
      return { kind: early };
    }
    const nonce = await chain.nonce();
    let signed: Signed;
    try {
      signed = await chain.prepare(publicKey, address, nonce);
    } catch (error) {
      // Nothing was handed to the node: nothing was taken, and the nonce was never held.
      event("refused", { address, reason: error instanceof Error ? error.message : "unknown" });
      return { kind: error instanceof NetworkRefused ? "refused" : "unavailable" };
    }

    // From here to the handing there is no await.
    const at = now();
    const full = capped(client, at);
    if (full) {
      // The signed execution is dropped, never handed: its nonce stays free.
      event(full, { address });
      return { kind: full };
    }
    ledger.spend(dayOf(at), 1);
    ledger.addTime(client, at);
    // Kept before it is handed: whatever happens next, this nonce carries this execution only.
    ledger.setHold({
      nonce: String(nonce),
      transaction: signed.transaction,
      payload: signed.payload,
      client,
      at,
    });
    const handed = chain.submit(signed.payload);

    try {
      await handed;
    } catch (error) {
      // It may have reached the node: the caps stay spent and the nonce held, with the execution
      // to hand again.
      event("send-failed", { address, reason: error instanceof Error ? error.name : "unknown" });
      return { kind: "lost", transaction: signed.transaction };
    }
    return { kind: "sent", transaction: signed.transaction };
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
    if (sent.kind === "exists") {
      const done: Grant = { address, status: "succeeded" };
      ledger.setGrant(publicKey, done);
      event("exists", { address });
      return provided(done, true);
    }
    if (sent.kind === "lost") {
      // Perhaps on the node: the key's next request asks about this execution before anything.
      ledger.setGrant(publicKey, { address, transaction: sent.transaction, status: "pending" });
      return { kind: "unavailable" };
    }
    if (sent.kind !== "sent") {
      // Nothing was handed to the node: the key may ask again.
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
