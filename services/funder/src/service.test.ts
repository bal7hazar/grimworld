import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { FeeRefused, NetworkRefused, type FundingChain, type FundingStatus } from "./chain.ts";
import { fileLedger, memoryLedger, type Ledger } from "./ledger.ts";
import { HOUR_MS, createFundingService, type Limits } from "./service.ts";

// The guards of the service, offline: a fake chain records what would be sent.

const DAY_MS = 24 * HOUR_MS;
const T0 = Date.UTC(2026, 8, 29, 10);

interface FakeChain extends FundingChain {
  sent: string[];
  deployed: Set<string>;
  /** What `fund` does next: send (default), or throw. */
  next: (() => never) | undefined;
  /** The status every execution reports. */
  answer: FundingStatus;
}

function fakeChain(): FakeChain {
  const chain: FakeChain = {
    sent: [],
    deployed: new Set(),
    next: undefined,
    answer: "succeeded",
    addressOf(publicKey) {
      if (!/^0x[0-9a-f]{1,64}$/i.test(publicKey) || BigInt(publicKey) === 0n) return undefined;
      const key = `0x${BigInt(publicKey).toString(16)}`;
      return { publicKey: key, address: `0xa${key.slice(2)}` };
    },
    async isDeployed(address) {
      return chain.deployed.has(address);
    },
    async fund(_publicKey, address) {
      await Promise.resolve();
      if (chain.next) chain.next();
      chain.sent.push(address);
      if (chain.answer === "succeeded") chain.deployed.add(address);
      return `0x7${chain.sent.length}`;
    },
    async status() {
      return chain.answer;
    },
  };
  return chain;
}

function setup(limits: Partial<Limits> = {}, ledger: Ledger = memoryLedger()) {
  const chain = fakeChain();
  let clock = T0;
  const events: string[] = [];
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
    onEvent: (event) => events.push(event),
  });
  return {
    chain,
    service,
    ledger,
    events,
    advance: (ms: number) => {
      clock += ms;
    },
  };
}

const key = (n: number) => ({ publicKey: `0x${n.toString(16)}` });

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
    expect(ledger.spent("2026-09-29")).toBe(0);
    expect((await service.fund(key(2), "c")).kind).toBe("provided");
  });

  it("a funding still pending is asked about, not sent again", async () => {
    const { service, chain } = setup();
    chain.answer = "pending";
    expect(await service.fund(key(1), "c")).toMatchObject({
      status: "pending",
      transaction: "0x71",
      repeated: false,
    });
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "pending", repeated: true });
    chain.answer = "succeeded";
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "succeeded", repeated: true });
    expect(chain.sent).toEqual(["0xa1"]);
  });

  it("a funding that reverted gave nothing: the key may ask again, within the caps", async () => {
    const { service, chain, ledger } = setup();
    chain.answer = "failed";
    expect(await service.fund(key(1), "c")).toEqual({
      kind: "failed",
      address: "0xa1",
      transaction: "0x71",
    });
    chain.answer = "succeeded";
    expect(await service.fund(key(1), "c")).toMatchObject({ status: "succeeded", repeated: false });
    expect(chain.sent).toEqual(["0xa1", "0xa1"]);
    expect(ledger.spent("2026-09-29")).toBe(2);
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
});

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

  it("holds when the requests arrive at the same time", async () => {
    const { service, chain } = setup({ dailyBudget: 2, clientRate: 100 });
    const answers = await Promise.all(
      Array.from({ length: 10 }, (_, n) => service.fund(key(n + 1), `c${n}`)),
    );
    expect(answers.filter((a) => a.kind === "exhausted")).toHaveLength(8);
    expect(chain.sent).toHaveLength(2);
  });

  it("is kept across a restart with a state file", async () => {
    mkdirSync(join(import.meta.dirname, "..", ".state"), { recursive: true });
    const dir = mkdtempSync(join(import.meta.dirname, "..", ".state", "unit-"));
    try {
      const path = join(dir, "ledger.json");
      const first = setup({ dailyBudget: 1 }, fileLedger(path));
      expect((await first.service.fund(key(1), "c")).kind).toBe("provided");
      const second = setup({ dailyBudget: 1 }, fileLedger(path));
      expect(await second.service.fund(key(2), "c")).toEqual({ kind: "exhausted" });
      expect(await second.service.fund(key(1), "c")).toMatchObject({ repeated: true });
      expect(second.chain.sent).toEqual([]);
    } finally {
      rmSync(dir, { recursive: true });
    }
  });
});

describe("a refusal before signing gives the caps back; a failure after may not", () => {
  it("a network refused: refused, and nothing spent", async () => {
    const { service, chain, ledger } = setup({ dailyBudget: 1, clientRate: 1 });
    chain.next = () => {
      throw new NetworkRefused("the chain is mainnet");
    };
    expect(await service.fund(key(1), "c")).toEqual({ kind: "refused" });
    expect(ledger.spent("2026-09-29")).toBe(0);
    chain.next = undefined;
    expect((await service.fund(key(1), "c")).kind).toBe("provided");
  });

  it("a fee above the cap: unavailable, and nothing spent", async () => {
    const { service, chain, ledger } = setup({ dailyBudget: 1 });
    chain.next = () => {
      throw new FeeRefused();
    };
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    expect(ledger.spent("2026-09-29")).toBe(0);
  });

  it("a failure while sending: unavailable, the budget stays spent, the key may ask again", async () => {
    const { service, chain, ledger } = setup({ dailyBudget: 2 });
    chain.next = () => {
      throw new Error("lost");
    };
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    expect(ledger.spent("2026-09-29")).toBe(1);
    expect(ledger.grant("0x1")).toBeUndefined();
    chain.next = undefined;
    expect((await service.fund(key(1), "c")).kind).toBe("provided");
    expect(await service.fund(key(2), "c")).toEqual({ kind: "exhausted" });
  });

  it("a chain that cannot be read: unavailable, and nothing spent", async () => {
    const { service, chain, ledger } = setup();
    chain.isDeployed = () => Promise.reject(new Error("down"));
    expect(await service.fund(key(1), "c")).toEqual({ kind: "unavailable" });
    expect(ledger.spent("2026-09-29")).toBe(0);
    expect(chain.sent).toEqual([]);
  });
});

describe("sending", () => {
  it("one funding at a time: the funder's executions never race", async () => {
    const { service, chain } = setup({ clientRate: 10 });
    let active = 0;
    let most = 0;
    const fund = chain.fund;
    chain.fund = async (publicKey, address) => {
      active++;
      most = Math.max(most, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active--;
      return fund(publicKey, address);
    };
    await Promise.all([1, 2, 3, 4].map((n) => service.fund(key(n), "c")));
    expect(most).toBe(1);
    expect(chain.sent).toHaveLength(4);
  });
});
