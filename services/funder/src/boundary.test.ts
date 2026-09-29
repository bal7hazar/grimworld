import { describe, expect, it } from "vitest";
import type { FundingChain, FundingStatus } from "./chain.ts";
import { memoryLedger, type Ledger } from "./ledger.ts";
import { HOUR_MS, createFundingService, type Limits } from "./service.ts";

// Fix loop 2: the boundaries of the re-audit of PR 141 at b6b7feb (F-1 and F-2), and a seeded
// search of the same families. The fake node records every execution handed to it, the moment it
// is handed, and whose it is: the invariants are checked on that record, not on the service's
// own counts.

const MIDNIGHT = Date.UTC(2026, 8, 30);
const T0 = Date.UTC(2026, 8, 29, 10);

interface Tx {
  address: string;
  nonce: bigint;
  status: FundingStatus;
}

interface Dispatch {
  nonce: bigint;
  transaction: string;
  address: string;
  at: number;
}

/** What the node does with the next execution it accepts. */
type Mode = "include" | "revert" | "hold" | "drop";

function fakeNode(clock: { now(): number }) {
  let count = 0;
  const node = {
    latest: 0n,
    deployed: new Set<string>(),
    txs: new Map<string, Tx>(),
    /** Every execution handed to the node, first sendings and sendings again alike. */
    dispatches: [] as Dispatch[],
    mode: "include" as Mode,
    /** The node takes the execution, and its answer is lost. */
    loseAnswer: false,
    /** The connection fails before the node gets anything. */
    unreachable: false,
    /** Slow answers: awaited inside `nonce()` and the preparation. */
    onNonce: undefined as undefined | (() => Promise<void>),
    onPrepare: undefined as undefined | (() => Promise<void>),
    include() {
      const pending = [...node.txs.values()].filter((tx) => tx.status === "pending");
      for (const tx of pending.sort((a, b) => Number(a.nonce - b.nonce))) {
        if (tx.nonce !== node.latest) continue;
        tx.status = "succeeded";
        node.latest++;
        node.deployed.add(tx.address);
      }
    },
  };

  function accept(payload: { transaction: string; address: string; nonce: bigint }): string {
    const { transaction, address, nonce } = payload;
    const known = node.txs.get(transaction);
    // The same execution again: the node knows it, and it stays one execution.
    if (known && known.status !== "unknown") return transaction;
    const live = [...node.txs.entries()].some(
      ([id, tx]) => id !== transaction && tx.nonce === nonce && tx.status !== "unknown",
    );
    if (live || nonce !== node.latest) throw new Error(`invalid nonce ${nonce}`);
    const tx: Tx = { address, nonce, status: "pending" };
    node.txs.set(transaction, tx);
    if (node.mode === "drop") tx.status = "unknown";
    if (node.mode === "include" || node.mode === "revert") {
      tx.status = node.mode === "include" ? "succeeded" : "failed";
      node.latest++;
      if (tx.status === "succeeded") node.deployed.add(address);
    }
    if (node.loseAnswer) throw new Error("the answer was lost");
    return transaction;
  }

  /** Hands the execution to the node at the moment of the call, then answers. */
  function hand(payload: string): Promise<string> {
    const parsed = JSON.parse(payload) as { transaction: string; address: string; nonce: string };
    const execution = { ...parsed, nonce: BigInt(parsed.nonce) };
    if (node.unreachable) return Promise.reject(new Error("connection refused"));
    node.dispatches.push({ ...execution, at: clock.now() });
    return Promise.resolve().then(() => accept(execution));
  }

  const chain = {
    addressOf(publicKey: string) {
      if (!/^0x[0-9a-f]{1,64}$/i.test(publicKey) || BigInt(publicKey) === 0n) return undefined;
      const key = `0x${BigInt(publicKey).toString(16)}`;
      return { publicKey: key, address: `0xa${key.slice(2)}` };
    },
    async isDeployed(address: string) {
      return node.deployed.has(address);
    },
    async nonce() {
      if (node.onNonce) await node.onNonce();
      return node.latest;
    },
    async prepare(_publicKey: string, address: string, nonce: bigint) {
      if (node.onPrepare) await node.onPrepare();
      const transaction = `0x7${(++count).toString(16)}`;
      return {
        transaction,
        payload: JSON.stringify({ transaction, address, nonce: String(nonce) }),
      };
    },
    submit: hand,
    async verify() {},
    async status(id: string): Promise<FundingStatus> {
      return node.txs.get(id)?.status ?? "unknown";
    },
  };
  return { node, chain: chain satisfies FundingChain };
}

function setup(limits: Partial<Limits> = {}, start = T0) {
  let clock = start;
  const time = {
    now: () => clock,
    advance: (ms: number) => {
      clock += ms;
    },
    to: (at: number) => {
      if (clock < at) clock = at;
    },
  };
  const { node, chain } = fakeNode(time);
  const all: Limits = {
    dailyBudget: 50,
    clientRate: 3,
    windowMs: HOUR_MS,
    settleMs: 1_000,
    pollMs: 100,
    ...limits,
  };
  const start_ = (ledger: Ledger) =>
    createFundingService({
      chain,
      ledger,
      limits: all,
      now: time.now,
      sleep: async (ms) => time.advance(ms),
    });
  const ledger = memoryLedger();
  return { node, chain, ledger, service: start_(ledger), restart: () => start_(ledger), ...time };
}

const key = (n: number) => ({ publicKey: `0x${n.toString(16)}` });

/** Nonces that more than one execution was handed with: must always be empty. */
function reused(dispatches: readonly Dispatch[]): string[] {
  const byNonce = new Map<bigint, Set<string>>();
  for (const d of dispatches) {
    byNonce.set(d.nonce, (byNonce.get(d.nonce) ?? new Set()).add(d.transaction));
  }
  return [...byNonce.entries()]
    .filter(([, ids]) => ids.size > 1)
    .map(([nonce, ids]) => `${nonce}: ${[...ids].join(", ")}`);
}

/** The first handing of each execution: the executions the service decided to send. */
function firsts(dispatches: readonly Dispatch[]): Dispatch[] {
  const seen = new Set<string>();
  return dispatches.filter((d) => !seen.has(d.transaction) && seen.add(d.transaction));
}

function dayOf(at: number): string {
  return new Date(at).toISOString().slice(0, 10);
}

describe("F-1 at its boundary: a nonce is never used by two executions", () => {
  it("the audit's case: an answer lost, the execution still pending past five minutes", async () => {
    const { node, service, advance } = setup({ clientRate: 10 });
    node.mode = "hold";
    node.loseAnswer = true;
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    node.loseAnswer = false;
    node.mode = "include";
    advance(300_001);
    expect(await service.fund(key(2), "c")).toEqual({ kind: "unavailable" });
    expect(reused(node.dispatches)).toEqual([]);
    node.include();
    expect(await service.fund(key(2), "c")).toMatchObject({ kind: "provided" });
    expect(reused(node.dispatches)).toEqual([]);
    expect(firsts(node.dispatches).map((d) => d.nonce)).toEqual([0n, 1n]);
  });

  it("the audit's case across a restart with the same ledger", async () => {
    const { node, service, restart, advance } = setup({ clientRate: 10 });
    node.mode = "hold";
    node.loseAnswer = true;
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    node.loseAnswer = false;
    node.mode = "include";
    const again = restart();
    advance(300_001);
    expect(await again.fund(key(2), "c")).toEqual({ kind: "unavailable" });
    expect(reused(node.dispatches)).toEqual([]);
  });

  it("an execution the node answers `unknown` for past five minutes is sent again, never replaced", async () => {
    const { node, service, advance } = setup({ clientRate: 10 });
    node.mode = "drop";
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "pending" });
    node.mode = "include";
    advance(300_001);
    expect(await service.fund(key(2), "c")).toMatchObject({ kind: "provided" });
    expect(reused(node.dispatches)).toEqual([]);
    // The first execution was handed again, as it was signed; then the second, on the next nonce.
    const [first, second] = firsts(node.dispatches);
    expect(node.dispatches.map((d) => d.transaction)).toEqual([
      first!.transaction,
      first!.transaction,
      second!.transaction,
    ]);
    expect(second!.nonce).toBe(1n);
    expect(node.deployed.has("0xa1")).toBe(true);
  });
});

describe("F-2 at its boundary: the caps count the moment an execution is handed to the node", () => {
  it("the audit's case: a nonce answer that ends after midnight", async () => {
    const { node, service, ledger, to } = setup(
      { dailyBudget: 2, clientRate: 100 },
      MIDNIGHT - 100,
    );
    let slow = true;
    node.onNonce = async () => {
      if (slow) to(MIDNIGHT + 1_000);
      slow = false;
    };
    const answers = [await service.fund(key(1), "a")];
    answers.push(
      ...(await Promise.all([service.fund(key(2), "b"), service.fund(key(3), "c")])),
      await service.fund(key(4), "d"),
    );
    const newDay = firsts(node.dispatches).filter((d) => d.at >= MIDNIGHT);
    expect(newDay.length).toBeLessThanOrEqual(2);
    expect(ledger.spent(dayOf(MIDNIGHT))).toBe(newDay.length);
    expect(answers.filter((a) => a.kind === "provided")).toHaveLength(newDay.length);
  });

  it("the audit's case: a rate of one, a slow nonce, a second funding an hour after the first was taken", async () => {
    const { node, service, advance, now } = setup({ clientRate: 1 });
    let slow = true;
    node.onNonce = async () => {
      if (slow) advance(2_000);
      slow = false;
    };
    expect(await service.fund(key(1), "c")).toMatchObject({ kind: "provided" });
    const handed = node.dispatches[0]!.at;
    advance(T0 + HOUR_MS + 1 - now());
    const second = await service.fund(key(2), "c");
    const times = firsts(node.dispatches).map((d) => d.at);
    for (let i = 1; i < times.length; i++) {
      expect(times[i]! - times[i - 1]!).toBeGreaterThanOrEqual(HOUR_MS);
    }
    expect(second).toEqual({ kind: "limited" });
    // An hour after it was handed, the client may fund again.
    advance(handed + HOUR_MS - now());
    expect(await service.fund(key(2), "c")).toMatchObject({ kind: "provided" });
  });

  it("a slow preparation across midnight, with requests of the new day waiting", async () => {
    const { node, service, to } = setup({ dailyBudget: 2, clientRate: 100 }, MIDNIGHT - 100);
    let slow = true;
    node.onPrepare = async () => {
      if (slow) to(MIDNIGHT + 1_000);
      slow = false;
    };
    await Promise.all([1, 2, 3, 4, 5].map((n) => service.fund(key(n), `c${n}`)));
    const byDay = new Map<string, number>();
    for (const d of firsts(node.dispatches))
      byDay.set(dayOf(d.at), (byDay.get(dayOf(d.at)) ?? 0) + 1);
    for (const count of byDay.values()) expect(count).toBeLessThanOrEqual(2);
  });
});

/** A small deterministic generator (mulberry32). */
function random(seed: number): () => number {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// The same families searched: lost answers, drops, reverts, unreachable nodes, slow answers at
// every await, restarts, midnights and hours crossed, requests at the same time. After every run:
// no nonce with two executions; no UTC day with more first handings than the budget; no client
// with more first handings than its rate in any hour.
describe("a seeded search of the same families", () => {
  // 200 seeds in CI; `FUNDER_SEEDS=5000` for a longer search.
  const seeds = Number(process.env.FUNDER_SEEDS ?? 200);
  it.each(Array.from({ length: seeds }, (_, i) => i + 1))("seed %i", async (seed) => {
    const rand = random(seed);
    const budget = 1 + Math.floor(rand() * 4);
    const rate = 1 + Math.floor(rand() * 3);
    const t = setup({ dailyBudget: budget, clientRate: rate }, MIDNIGHT - 3 * HOUR_MS);
    let service = t.service;
    const owner = new Map<string, string>();
    let n = 0;
    const slow = () => (rand() < 0.3 ? t.advance(Math.floor(rand() * 90 * 60_000)) : undefined);
    t.node.onNonce = async () => slow();
    t.node.onPrepare = async () => slow();
    for (let step = 0; step < 40; step++) {
      const modes: Mode[] = ["include", "include", "revert", "hold", "drop"];
      t.node.mode = modes[Math.floor(rand() * modes.length)]!;
      t.node.loseAnswer = rand() < 0.2;
      t.node.unreachable = rand() < 0.1;
      if (rand() < 0.3) t.node.include();
      if (rand() < 0.1) service = t.restart();
      const burst = 1 + Math.floor(rand() * 3);
      await Promise.all(
        Array.from({ length: burst }, () => {
          const client = `c${Math.floor(rand() * 3)}`;
          const k = key(++n);
          owner.set(`0xa${n.toString(16)}`, client);
          return service.fund(k, client);
        }),
      );
      t.advance(Math.floor(rand() * 2 * HOUR_MS));
    }
    expect(reused(t.node.dispatches)).toEqual([]);
    const sent = firsts(t.node.dispatches);
    const byDay = new Map<string, number>();
    for (const d of sent) byDay.set(dayOf(d.at), (byDay.get(dayOf(d.at)) ?? 0) + 1);
    for (const count of byDay.values()) expect(count).toBeLessThanOrEqual(budget);
    for (const client of new Set(owner.values())) {
      const times = sent.filter((d) => owner.get(d.address) === client).map((d) => d.at);
      for (let i = rate; i < times.length; i++) {
        expect(times[i]! - times[i - rate]!).toBeGreaterThanOrEqual(HOUR_MS);
      }
    }
  });
});
