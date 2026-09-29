import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  FeeRefused,
  NetworkRefused,
  NotSent,
  type FundingChain,
  type FundingStatus,
} from "./chain.ts";
import { LedgerLocked, fileLedger, memoryLedger, type Ledger } from "./ledger.ts";
import { HOUR_MS, createFundingService, type Limits } from "./service.ts";

// The guards of the service, offline. The fake chain keeps the funding account's nonce as a node
// does: an execution must carry the next nonce, a nonce is consumed when its execution is included
// (succeeded or reverted), and one already used by an execution the node knows is refused.

const DAY_MS = 24 * HOUR_MS;
const T0 = Date.UTC(2026, 8, 29, 10);
const TODAY = "2026-09-29";

interface Tx {
  address: string;
  nonce: bigint;
  status: FundingStatus;
}

/** What the node does with the next execution. */
type Mode = "include" | "revert" | "hold" | "drop";

interface FakeChain extends FundingChain {
  /** Addresses funded, in order of first acceptance by the node. */
  sent: string[];
  /** The nonce of each execution the node accepted first. */
  nonces: bigint[];
  deployed: Set<string>;
  txs: Map<string, Tx>;
  latest: bigint;
  mode: Mode;
  /** Thrown by `prepare`: nothing reaches the node. */
  before: (() => never) | undefined;
  /** The node takes the execution, and its answer is lost. */
  loseAnswer: boolean;
  /** The connection fails before the node gets anything. */
  unreachable: boolean;
  /** Includes every execution the node holds, in nonce order. */
  include(): void;
}

function fakeChain(): FakeChain {
  let count = 0;
  function accept(payload: { transaction: string; address: string; nonce: bigint }): string {
    const { transaction, address, nonce } = payload;
    const known = chain.txs.get(transaction);
    if (known && known.status !== "unknown") return transaction;
    const live = [...chain.txs.entries()].some(
      ([id, tx]) => id !== transaction && tx.nonce === nonce && tx.status !== "unknown",
    );
    if (live || nonce !== chain.latest) throw new Error(`invalid nonce ${nonce}`);
    if (!known) {
      chain.sent.push(address);
      chain.nonces.push(nonce);
    }
    const tx: Tx = { address, nonce, status: "pending" };
    chain.txs.set(transaction, tx);
    if (chain.mode === "drop") tx.status = "unknown";
    if (chain.mode === "include" || chain.mode === "revert") {
      tx.status = chain.mode === "include" ? "succeeded" : "failed";
      chain.latest++;
      if (tx.status === "succeeded") chain.deployed.add(address);
    }
    if (chain.loseAnswer) throw new Error("the answer was lost");
    return transaction;
  }
  const chain: FakeChain = {
    sent: [],
    nonces: [],
    deployed: new Set(),
    txs: new Map(),
    latest: 0n,
    mode: "include",
    before: undefined,
    loseAnswer: false,
    unreachable: false,
    addressOf(publicKey) {
      if (!/^0x[0-9a-f]{1,64}$/i.test(publicKey) || BigInt(publicKey) === 0n) return undefined;
      const key = `0x${BigInt(publicKey).toString(16)}`;
      return { publicKey: key, address: `0xa${key.slice(2)}` };
    },
    async isDeployed(address) {
      return chain.deployed.has(address);
    },
    async nonce() {
      return chain.latest;
    },
    async prepare(_publicKey, address, nonce) {
      await Promise.resolve();
      if (chain.before) chain.before();
      const transaction = `0x7${(++count).toString(16)}`;
      return {
        transaction,
        payload: JSON.stringify({ transaction, address, nonce: String(nonce) }),
      };
    },
    submit(payload) {
      const parsed = JSON.parse(payload) as { transaction: string; address: string; nonce: string };
      if (chain.unreachable) return Promise.reject(new Error("connection refused"));
      return Promise.resolve().then(() => accept({ ...parsed, nonce: BigInt(parsed.nonce) }));
    },
    async verify() {},
    async status(hash) {
      return chain.txs.get(hash)?.status ?? "unknown";
    },
    include() {
      for (const tx of [...chain.txs.values()].sort((a, b) => Number(a.nonce - b.nonce))) {
        if (tx.status !== "pending" || tx.nonce !== chain.latest) continue;
        tx.status = "succeeded";
        chain.latest++;
        chain.deployed.add(tx.address);
      }
    },
  };
  return chain;
}

function setup(
  limits: Partial<Limits> = {},
  ledger: Ledger = memoryLedger(),
  start = T0,
  chain: FakeChain = fakeChain(),
) {
  let clock = start;
  const service = createFundingService({
    chain,
    ledger,
    limits: {
      dailyBudget: 50,
      clientRate: 3,
      windowMs: HOUR_MS,
      settleMs: 1_000,
      pollMs: 100,
      ...limits,
    },
    now: () => clock,
    sleep: async (ms) => {
      clock += ms;
    },
  });
  return {
    chain,
    service,
    ledger,
    advance: (ms: number) => {
      clock += ms;
    },
    now: () => clock,
  };
}

const key = (n: number) => ({ publicKey: `0x${n.toString(16)}` });

const dirs: string[] = [];
function stateFile(): string {
  mkdirSync(join(import.meta.dirname, "..", ".state"), { recursive: true });
  const dir = mkdtempSync(join(import.meta.dirname, "..", ".state", "unit-"));
  dirs.push(dir);
  return join(dir, "ledger.json");
}

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true });
});

describe("a request", () => {
  it.each([
    undefined,
    null,
    "0x1",
    {},
    { publicKey: 1 },
    { publicKey: "zz" },
    { publicKey: "0x0" },
    { publicKey: "0x1", address: 5 },
    { publicKey: "0x1", address: "a1" },
  ])("that is not a key on the curve is invalid, and sends nothing: %j", async (body) => {
    const { service, chain } = setup();
    expect(await service.fund(body, "c")).toEqual({ kind: "invalid" });
    expect(chain.sent).toEqual([]);
  });

  it("with an address that is not its key's is invalid", async () => {
    const { service, chain } = setup();
    expect(await service.fund({ publicKey: "0x1", address: "0xa2" }, "c")).toEqual({
      kind: "invalid",
    });
    expect(chain.sent).toEqual([]);
  });

  it("for a new key deploys and funds its account, with the key's address", async () => {
    const { service, chain } = setup();
    expect(await service.fund({ publicKey: "0x1", address: "0xa1" }, "c")).toEqual({
      kind: "provided",
      address: "0xa1",
      status: "succeeded",
      transaction: "0x71",
      repeated: false,
    });
    expect(chain.sent).toEqual(["0xa1"]);
  });
});

describe("a key is funded once", () => {
  it("a second request gets the recorded answer, and nothing is sent", async () => {
    const { service, chain } = setup();
    await service.fund(key(1), "c");
    expect(await service.fund(key(1), "other")).toEqual({
      kind: "provided",
      address: "0xa1",
      status: "succeeded",
      transaction: "0x71",
      repeated: true,
    });
    expect(chain.sent).toEqual(["0xa1"]);
  });

  it("the same key written another way is the same key", async () => {
    const { service, chain } = setup();
    await service.fund({ publicKey: "0x01" }, "c");
    expect((await service.fund({ publicKey: "0x0001" }, "c")).kind).toBe("provided");
    expect(chain.sent).toEqual(["0xa1"]);
  });

  it("requests at the same time share one funding", async () => {
    const { service, chain } = setup();
    const answers = await Promise.all([1, 2, 3, 4, 5].map(() => service.fund(key(1), "c")));
    expect(chain.sent).toEqual(["0xa1"]);
    expect(new Set(answers.map((a) => JSON.stringify(a))).size).toBe(1);
  });

  it("an account that exists already is never funded, and costs no cap", async () => {
    const { service, chain, ledger } = setup({ dailyBudget: 1 });
    chain.deployed.add("0xa1");
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "succeeded", repeated: true });
    expect(chain.sent).toEqual([]);
    expect(ledger.spent(TODAY)).toBe(0);
    expect((await service.fund(key(2), "c")).kind).toBe("provided");
  });

  it("a funding still pending is asked about, not sent again", async () => {
    const { service, chain } = setup();
    chain.mode = "hold";
    expect(await service.fund(key(1), "c")).toMatchObject({
      status: "pending",
      transaction: "0x71",
      repeated: false,
    });
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "pending", repeated: true });
    chain.include();
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "succeeded", repeated: true });
    expect(chain.sent).toEqual(["0xa1"]);
  });

  it("a funding that reverted gave nothing: the key may ask again, within the caps", async () => {
    const { service, chain, ledger } = setup();
    chain.mode = "revert";
    expect(await service.fund(key(1), "c")).toEqual({
      kind: "failed",
      address: "0xa1",
      transaction: "0x71",
    });
    chain.mode = "include";
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "succeeded", repeated: false });
    expect(chain.sent).toEqual(["0xa1", "0xa1"]);
    expect(chain.nonces).toEqual([0n, 1n]);
    expect(ledger.spent(TODAY)).toBe(2);
  });

  it("a stop while sending: the next request asks the chain whether it went through", async () => {
    const ledger = memoryLedger();
    ledger.setGrant("0x1", { address: "0xa1", status: "sending" });
    const { service, chain } = setup({}, ledger);
    chain.deployed.add("0xa1");
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "succeeded", repeated: true });
    expect(chain.sent).toEqual([]);
  });
});

// Fix loop 1, F-1: the funding account's nonce is held from one funding's signature until it is
// consumed, across pending executions, lost answers and restarts.
describe("the funding account's nonce", () => {
  it("fundings at the same time each sign with the next nonce", async () => {
    const { service, chain } = setup({ clientRate: 10 });
    const answers = await Promise.all([1, 2, 3, 4].map((n) => service.fund(key(n), "c")));
    expect(answers.every((a) => a.kind === "provided")).toBe(true);
    expect(chain.nonces).toEqual([0n, 1n, 2n, 3n]);
  });

  it("is not reused while the funding before is pending: the next one waits, then signs after", async () => {
    const { service, chain, ledger } = setup({ clientRate: 10 });
    chain.mode = "hold";
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "pending" });
    chain.mode = "include";
    // The first is still pending past a request's wait: the second sends nothing, spends nothing.
    expect(await service.fund(key(2), "c")).toEqual({ kind: "unavailable" });
    expect(chain.nonces).toEqual([0n]);
    expect(ledger.spent(TODAY)).toBe(1);
    chain.include();
    expect(await service.fund(key(2), "c")).toMatchObject({ status: "succeeded" });
    expect(chain.nonces).toEqual([0n, 1n]);
  });

  it("the race of the audit: two burners, the first pending, never share nonce 0", async () => {
    const { service, chain } = setup({ clientRate: 10, settleMs: 300 });
    chain.mode = "hold";
    const [first, second] = await Promise.all([
      service.fund(key(1), "c"),
      service.fund(key(2), "d"),
    ]);
    expect(first).toMatchObject({ status: "pending" });
    expect(second).toEqual({ kind: "unavailable" });
    expect(chain.nonces).toEqual([0n]);
  });

  it("a lost answer holds the nonce: when the execution shows up, the next signs after it", async () => {
    const { service, chain, ledger } = setup({ clientRate: 10 });
    chain.mode = "hold";
    chain.loseAnswer = true;
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    // It may have been sent: the caps stay spent and the nonce held.
    expect(ledger.spent(TODAY)).toBe(1);
    expect(ledger.hold()).toMatchObject({ nonce: "0" });
    chain.loseAnswer = false;
    chain.mode = "include";
    expect(await service.fund(key(2), "c")).toEqual({ kind: "unavailable" });
    chain.include();
    expect(await service.fund(key(2), "c")).toMatchObject({ status: "succeeded" });
    expect(chain.nonces).toEqual([0n, 1n]);
  });

  // Fix loop 2, F-1: a hold ends only when its nonce is consumed; until then the node is handed
  // the same execution again, never another.
  it("a handing that never reached the node: the same execution is handed again, then the next", async () => {
    const { service, chain, ledger } = setup({ clientRate: 10 });
    chain.unreachable = true;
    // The service cannot know that nothing reached the node.
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    expect(ledger.grant("0x1")).toMatchObject({ transaction: "0x71", status: "pending" });
    chain.unreachable = false;
    expect(await service.fund(key(2), "c")).toMatchObject({ status: "succeeded" });
    expect(chain.sent).toEqual(["0xa1", "0xa2"]);
    expect(chain.nonces).toEqual([0n, 1n]);
    // The first key's request, asked again, finds its funding done.
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "succeeded", repeated: true });
  });

  it("an execution the node dropped is handed again as it was, never replaced", async () => {
    const { service, chain } = setup({ clientRate: 10 });
    chain.mode = "drop";
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "pending" });
    chain.mode = "include";
    expect(await service.fund(key(2), "c")).toMatchObject({ status: "succeeded" });
    expect([...chain.txs.keys()]).toEqual(["0x71", "0x72"]);
    expect(chain.nonces).toEqual([0n, 1n]);
    expect(chain.deployed).toEqual(new Set(["0xa1", "0xa2"]));
  });

  it("a handing again is refused by the caps while they are full, and waits", async () => {
    const { service, chain, ledger, advance } = setup({ clientRate: 1, dailyBudget: 50 });
    chain.unreachable = true;
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    chain.unreachable = false;
    // Client c's hour is taken by its first handing: its execution waits, nothing is handed.
    expect(await service.fund(key(2), "d")).toEqual({ kind: "unavailable" });
    expect(chain.sent).toEqual([]);
    advance(HOUR_MS);
    expect(await service.fund(key(2), "d")).toMatchObject({ status: "succeeded" });
    expect(chain.sent).toEqual(["0xa1", "0xa2"]);
    // Counted twice (the first handing may have arrived): only ever an over-count.
    expect(ledger.spent(TODAY)).toBe(3);
  });

  it("a pending execution the node knows holds its nonce however long it takes", async () => {
    const { service, chain, advance } = setup({ clientRate: 10 });
    chain.mode = "hold";
    await service.fund(key(1), "c");
    advance(10 * HOUR_MS);
    expect(await service.fund(key(2), "c")).toEqual({ kind: "unavailable" });
    expect(chain.nonces).toEqual([0n]);
  });

  it("the hold survives a restart with a state file", async () => {
    const path = stateFile();
    const first = setup({ clientRate: 10 }, fileLedger(path));
    first.chain.mode = "hold";
    expect(await first.service.fund(key(1), "c")).toMatchObject({ status: "pending" });
    // The same node, a new process with the same ledger.
    first.ledger.close();
    const second = setup({ clientRate: 10 }, fileLedger(path), T0, first.chain);
    expect(await second.service.fund(key(2), "c")).toEqual({ kind: "unavailable" });
    expect(first.chain.nonces).toEqual([0n]);
    first.chain.mode = "include";
    first.chain.include();
    expect(await second.service.fund(key(2), "c")).toMatchObject({ status: "succeeded" });
    expect(first.chain.nonces).toEqual([0n, 1n]);
  });
});

describe("the client rate", () => {
  it("is 3 new keys per client per hour; other clients are not affected", async () => {
    const { service, chain, advance } = setup({ clientRate: 3 });
    for (const n of [1, 2, 3]) expect((await service.fund(key(n), "c")).kind).toBe("provided");
    expect(await service.fund(key(4), "c")).toEqual({ kind: "limited" });
    expect((await service.fund(key(4), "d")).kind).toBe("provided");
    // A key already funded is answered whatever the rate.
    expect((await service.fund(key(1), "c")).kind).toBe("provided");
    advance(HOUR_MS);
    expect((await service.fund(key(5), "c")).kind).toBe("provided");
    expect(chain.sent).toEqual(["0xa1", "0xa2", "0xa3", "0xa4", "0xa5"]);
  });

  it("holds when the requests arrive at the same time", async () => {
    const { service, chain } = setup({ clientRate: 3 });
    const answers = await Promise.all([1, 2, 3, 4, 5, 6].map((n) => service.fund(key(n), "c")));
    expect(answers.filter((a) => a.kind === "limited")).toHaveLength(3);
    expect(chain.sent).toHaveLength(3);
  });

  // Fix loop 1, F-3: the audit's case, a restart within the hour, fresh keys, the same client.
  it("survives a restart within the hour with a state file", async () => {
    const path = stateFile();
    const first = setup({ clientRate: 1 }, fileLedger(path));
    expect((await first.service.fund(key(1), "c")).kind).toBe("provided");
    expect(await first.service.fund(key(2), "c")).toEqual({ kind: "limited" });
    first.ledger.close();
    // A new process, the same node.
    const second = setup({ clientRate: 1 }, fileLedger(path), T0 + HOUR_MS / 2, first.chain);
    expect(await second.service.fund(key(3), "c")).toEqual({ kind: "limited" });
    // Nothing new: only the first process's funding.
    expect(second.chain.sent).toEqual(["0xa1"]);
    second.advance(HOUR_MS / 2);
    expect((await second.service.fund(key(3), "c")).kind).toBe("provided");
  });
});

// Fix loop 1, F-2: the caps are taken at signing, on the clock of signing.
describe("the day's budget", () => {
  it("is shared by every client, and opens again the next day (UTC)", async () => {
    const { service, chain, advance } = setup({ dailyBudget: 2, clientRate: 100 });
    expect((await service.fund(key(1), "a")).kind).toBe("provided");
    expect((await service.fund(key(2), "b")).kind).toBe("provided");
    expect(await service.fund(key(3), "c")).toEqual({ kind: "exhausted" });
    advance(DAY_MS);
    expect((await service.fund(key(3), "c")).kind).toBe("provided");
    expect(chain.sent).toHaveLength(3);
  });

  it("holds at the boundary when the requests arrive at the same time", async () => {
    const { service, chain, ledger } = setup({ dailyBudget: 3, clientRate: 100 });
    expect((await service.fund(key(100), "z")).kind).toBe("provided");
    const answers = await Promise.all(
      Array.from({ length: 10 }, (_, n) => service.fund(key(n + 1), `c${n}`)),
    );
    expect(answers.filter((a) => a.kind === "provided")).toHaveLength(2);
    expect(answers.filter((a) => a.kind === "exhausted")).toHaveLength(8);
    expect(chain.sent).toHaveLength(3);
    expect(ledger.spent(TODAY)).toBe(3);
  });

  it("the audit's midnight: requests admitted before midnight and signed after count on the new day", async () => {
    const midnight = Date.UTC(2026, 8, 30);
    const { service, chain, ledger, advance, now } = setup(
      { dailyBudget: 2, clientRate: 100 },
      memoryLedger(),
      midnight - 100,
    );
    // The deployment checks of the first two are slow: they end after midnight.
    const isDeployed = chain.isDeployed;
    let slow = 2;
    chain.isDeployed = async (address) => {
      if (slow-- > 0) {
        await new Promise((resolve) => setTimeout(resolve, 5));
        if (now() < midnight) advance(midnight - now());
      }
      return isDeployed(address);
    };
    const late = [service.fund(key(1), "a"), service.fund(key(2), "b")];
    await new Promise((resolve) => setTimeout(resolve, 20));
    const fresh = [service.fund(key(3), "c"), service.fund(key(4), "d")];
    const answers = await Promise.all([...late, ...fresh]);
    expect(answers.filter((a) => a.kind === "provided")).toHaveLength(2);
    expect(answers.filter((a) => a.kind === "exhausted")).toHaveLength(2);
    expect(chain.sent).toHaveLength(2);
    expect(ledger.spent("2026-09-29")).toBe(0);
    expect(ledger.spent("2026-09-30")).toBe(2);
  });

  it("the worst drain: 24 hours of 40 new clients an hour sign exactly the budget each day", async () => {
    const { service, chain, ledger, advance } = setup({ dailyBudget: 50, clientRate: 3 });
    let n = 0;
    // From 10:00 on the 29th to 09:00 on the 30th: 960 requests, all of fresh clients and keys.
    for (let hour = 0; hour < 24; hour++) {
      await Promise.all(
        Array.from({ length: 40 }, (_, c) => service.fund(key(++n), `h${hour}c${c}`)),
      );
      advance(HOUR_MS);
    }
    expect(ledger.spent("2026-09-29")).toBe(50);
    expect(ledger.spent("2026-09-30")).toBe(50);
    expect(chain.sent).toHaveLength(100);
  });

  it("is kept across a restart with a state file", async () => {
    const path = stateFile();
    const first = setup({ dailyBudget: 1 }, fileLedger(path));
    expect((await first.service.fund(key(1), "c")).kind).toBe("provided");
    first.ledger.close();
    const second = setup({ dailyBudget: 1 }, fileLedger(path), T0, first.chain);
    expect(await second.service.fund(key(2), "c")).toEqual({ kind: "exhausted" });
    expect(await second.service.fund(key(1), "c")).toMatchObject({ repeated: true });
    // Nothing new: only the first process's funding.
    expect(second.chain.sent).toEqual(["0xa1"]);
  });
});

describe("a refusal before signing gives the caps back; a failure after may not", () => {
  it("a network refused: refused, and nothing spent", async () => {
    const { service, chain, ledger } = setup({ dailyBudget: 1, clientRate: 1 });
    chain.before = () => {
      throw new NetworkRefused("the chain is mainnet");
    };
    expect(await service.fund(key(1), "c")).toEqual({ kind: "refused" });
    expect(ledger.spent(TODAY)).toBe(0);
    expect(ledger.hold()).toBeUndefined();
    chain.before = undefined;
    expect((await service.fund(key(1), "c")).kind).toBe("provided");
  });

  it.each([new FeeRefused(), new NotSent("estimate failed")])(
    "%s: unavailable, and nothing spent",
    async (error) => {
      const { service, chain, ledger } = setup({ dailyBudget: 1 });
      chain.before = () => {
        throw error;
      };
      expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
      expect(ledger.spent(TODAY)).toBe(0);
      expect(ledger.times("c", 0)).toEqual([]);
      expect(ledger.hold()).toBeUndefined();
    },
  );

  it("a failure while handing: unavailable, the budget stays spent, the key's next request asks about it", async () => {
    const { service, chain, ledger } = setup({ dailyBudget: 2 });
    chain.loseAnswer = true;
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    expect(ledger.spent(TODAY)).toBe(1);
    expect(ledger.grant("0x1")).toMatchObject({ transaction: "0x71", status: "pending" });
    chain.loseAnswer = false;
    // It had arrived: the key's request is answered, nothing is sent again.
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "succeeded", repeated: true });
    expect((await service.fund(key(2), "c")).kind).toBe("provided");
    expect(await service.fund(key(3), "c")).toEqual({ kind: "exhausted" });
    expect(chain.sent).toEqual(["0xa1", "0xa2"]);
  });

  it("a nonce that cannot be read: unavailable, nothing spent, nothing held", async () => {
    const { service, chain, ledger } = setup();
    chain.nonce = () => Promise.reject(new Error("down"));
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    expect(ledger.spent(TODAY)).toBe(0);
    expect(ledger.hold()).toBeUndefined();
    expect(ledger.grant("0x1")).toBeUndefined();
  });

  it("a chain that cannot be read: unavailable, and nothing spent", async () => {
    const { service, chain, ledger } = setup();
    chain.isDeployed = () => Promise.reject(new Error("down"));
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    expect(ledger.spent(TODAY)).toBe(0);
    expect(chain.sent).toEqual([]);
  });
});

// Fix loop 2: one process per state file.
describe("the state file", () => {
  it("is refused to a second ledger while the first is open, and given after close", () => {
    const path = stateFile();
    const first = fileLedger(path);
    expect(() => fileLedger(path)).toThrow(LedgerLocked);
    first.close();
    fileLedger(path).close();
  });

  it("a lock left by a process that stopped is taken over", () => {
    const path = stateFile();
    // Above any pid Linux hands out (pid_max is at most 2^22).
    writeFileSync(`${path}.lock`, String(2 ** 30));
    const ledger = fileLedger(path);
    expect(readFileSync(`${path}.lock`, "utf8")).toBe(String(process.pid));
    ledger.close();
  });
});

describe("sending", () => {
  it("one funding at a time: the funder's executions never overlap", async () => {
    const { service, chain } = setup({ clientRate: 10 });
    let active = 0;
    let most = 0;
    const prepare = chain.prepare;
    chain.prepare = async (publicKey, address, nonce) => {
      active++;
      most = Math.max(most, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active--;
      return prepare(publicKey, address, nonce);
    };
    await Promise.all([1, 2, 3, 4].map((n) => service.fund(key(n), "c")));
    expect(most).toBe(1);
    expect(chain.sent).toHaveLength(4);
  });
});
