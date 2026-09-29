import { describe, expect, it } from "vitest";
import { STORAGE_KEY, createBurnerProvider, type BurnerChain, type Funder } from "./burner";
import {
  AccountError,
  type AccountErrorCode,
  type Call,
  type ExecutionStatus,
  type KeyStorage,
} from "./types";

function memoryStorage(): KeyStorage & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return {
    data,
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => void data.set(key, value),
    removeItem: (key) => void data.delete(key),
  };
}

/**
 * Holds an asynchronous step pending: the step calls `arrived()` then waits for `promise`; the test
 * awaits `reached`, acts, then calls `open()`.
 */
function gate() {
  let open!: () => void;
  let arrived!: () => void;
  const promise = new Promise<void>((resolve) => (open = resolve));
  const reached = new Promise<void>((resolve) => (arrived = resolve));
  return { promise, reached, open: () => open(), arrived: () => arrived() };
}

/**
 * A chain in memory: keys k1, k2…, the address of k is `addr<class>:k` (`addr:k` for the default
 * class), ids are `x1`, `x2`… `reset()` loses every account, as a restarted local node does.
 */
class FakeChain implements BurnerChain {
  network = "local";
  accountClass = "";
  keys = 0;
  deployed = new Set<string>();
  checking?: ReturnType<typeof gate>;
  async binding() {
    return `${this.network}/${this.accountClass}`;
  }
  reset() {
    this.deployed.clear();
  }
  sent: { key: string; address: string; calls: readonly Call[] }[] = [];
  statuses = new Map<string, ExecutionStatus>();
  sendDelayMs = 0;
  inFlight = 0;
  maxInFlight = 0;
  failSend: unknown;
  failStatus: unknown;

  newKey() {
    return `k${++this.keys}`;
  }
  derive(key: string) {
    return { publicKey: `pub:${key}`, address: `addr${this.accountClass}:${key}` };
  }
  async isDeployed(address: string) {
    if (this.checking) {
      this.checking.arrived();
      await this.checking.promise;
    }
    return this.deployed.has(address);
  }
  async send(key: string, address: string, calls: readonly Call[]) {
    this.inFlight++;
    this.maxInFlight = Math.max(this.maxInFlight, this.inFlight);
    await new Promise((resolve) => setTimeout(resolve, this.sendDelayMs));
    this.inFlight--;
    if (this.failSend !== undefined) throw this.failSend;
    this.sent.push({ key, address, calls });
    const id = `x${this.sent.length}`;
    this.statuses.set(id, "pending");
    return id;
  }
  async status(id: string) {
    if (this.failStatus !== undefined) throw this.failStatus;
    return this.statuses.get(id) ?? "unknown";
  }
}

class FakeFunder implements Funder {
  provided: string[] = [];
  fail: unknown;
  funding?: ReturnType<typeof gate>;
  constructor(private chain: FakeChain) {}
  async provide(publicKey: string, address: string) {
    if (this.funding) {
      this.funding.arrived();
      await this.funding.promise;
    }
    if (this.fail !== undefined) throw this.fail;
    this.provided.push(publicKey);
    this.chain.deployed.add(address);
  }
}

function setup(storage = memoryStorage()) {
  const chain = new FakeChain();
  const funder = new FakeFunder(chain);
  const provider = createBurnerProvider({ chain, funder, storage });
  return { chain, funder, storage, provider };
}

const CALL: Call = { to: "0x1", entrypoint: "play", calldata: [1n, "0x2", 3] };

async function rejection(promise: Promise<unknown>): Promise<AccountErrorCode> {
  const error = await promise.then(
    () => undefined,
    (e: unknown) => e,
  );
  expect(error).toBeInstanceOf(AccountError);
  return (error as AccountError).code;
}

describe("createOrRestore", () => {
  it("creates an account: a new key kept on the device, deployed and funded by the game once", async () => {
    const { chain, funder, storage, provider } = setup();
    const handle = await provider.createOrRestore();
    expect(handle).toEqual({ address: "addr:k1" });
    expect(funder.provided).toEqual(["pub:k1"]);
    expect(JSON.parse(storage.data.get(STORAGE_KEY)!)).toEqual({
      v: 2,
      key: "k1",
      binding: "local/",
      address: "addr:k1",
    });
    expect(await provider.createOrRestore()).toEqual(handle);
    expect(chain.keys).toBe(1);
  });

  it("restores the account kept on the device without creating or funding again", async () => {
    const first = setup();
    await first.provider.createOrRestore();
    const funder = new FakeFunder(first.chain);
    const provider = createBurnerProvider({ chain: first.chain, funder, storage: first.storage });
    expect(await provider.createOrRestore()).toEqual({ address: "addr:k1" });
    expect(first.chain.keys).toBe(1);
    expect(funder.provided).toEqual([]);
  });

  it("keeps the key before funding: an interrupted creation resumes with the same key", async () => {
    const { chain, funder, storage, provider } = setup();
    funder.fail = new Error("down");
    expect(await rejection(provider.createOrRestore())).toBe("unavailable");
    expect(JSON.parse(storage.data.get(STORAGE_KEY)!)).toMatchObject({ key: "k1" });
    funder.fail = undefined;
    expect(await provider.createOrRestore()).toEqual({ address: "addr:k1" });
    expect(chain.keys).toBe(1);
    expect(funder.provided).toEqual(["pub:k1"]);
  });

  it("does not fund an account the chain already has", async () => {
    const { chain, funder, storage, provider } = setup();
    storage.setItem(STORAGE_KEY, JSON.stringify({ v: 1, key: "k9", address: "addr:k9" }));
    chain.deployed.add("addr:k9");
    expect(await provider.createOrRestore()).toEqual({ address: "addr:k9" });
    expect(funder.provided).toEqual([]);
    expect(JSON.parse(storage.data.get(STORAGE_KEY)!)).toMatchObject({ v: 2, binding: "local/" });
  });

  // F-3: a local node that was reset has lost every account; a record written as ready before the
  // reset must not be trusted.
  it("after a reset of the local node, deploys and funds the same key again", async () => {
    const { chain, funder, storage, provider } = setup();
    await provider.createOrRestore();
    chain.reset();
    const again = createBurnerProvider({ chain, funder, storage });
    expect(await again.createOrRestore()).toEqual({ address: "addr:k1" });
    expect(funder.provided).toEqual(["pub:k1", "pub:k1"]);
    expect(chain.deployed.has("addr:k1")).toBe(true);
    expect(await again.execute([CALL])).toBe("x1");
    expect(chain.keys).toBe(1);
  });

  it("after a sign-out, a new session checks the chain again", async () => {
    const { chain, funder, provider } = setup();
    await provider.createOrRestore();
    await provider.signOut();
    chain.reset();
    expect(await provider.createOrRestore()).toEqual({ address: "addr:k1" });
    expect(funder.provided).toEqual(["pub:k1", "pub:k1"]);
  });

  it("binds the kept account to its network and class: another binding derives it again", async () => {
    const { chain, funder, storage, provider } = setup();
    await provider.createOrRestore();
    chain.accountClass = "B";
    const other = createBurnerProvider({ chain, funder, storage });
    expect(await other.createOrRestore()).toEqual({ address: "addrB:k1" });
    expect(funder.provided).toEqual(["pub:k1", "pub:k1"]);
    expect(JSON.parse(storage.data.get(STORAGE_KEY)!)).toEqual({
      v: 2,
      key: "k1",
      binding: "local/B",
      address: "addrB:k1",
    });
    chain.accountClass = "";
    chain.network = "elsewhere";
    const third = createBurnerProvider({ chain, funder, storage });
    expect(await third.createOrRestore()).toEqual({ address: "addr:k1" });
    expect(JSON.parse(storage.data.get(STORAGE_KEY)!)).toMatchObject({
      binding: "elsewhere/",
      address: "addr:k1",
    });
  });

  it("creates one account when asked twice at once", async () => {
    const { chain, funder, provider } = setup();
    const [a, b] = await Promise.all([provider.createOrRestore(), provider.createOrRestore()]);
    expect(a).toEqual(b);
    expect(chain.keys).toBe(1);
    expect(funder.provided).toHaveLength(1);
  });

  it("replaces an unreadable record with a new account", async () => {
    const { storage, provider } = setup();
    storage.setItem(STORAGE_KEY, "{not json");
    expect(await provider.createOrRestore()).toEqual({ address: "addr:k1" });
  });
});

describe("execute and status", () => {
  it("refuses before an account is open", async () => {
    const { provider } = setup();
    expect(await rejection(provider.execute([CALL]))).toBe("not-ready");
  });

  it("sends the calls with the kept key, without any prompt, and reports their status", async () => {
    const { chain, provider } = setup();
    await provider.createOrRestore();
    const id = await provider.execute([CALL, CALL]);
    expect(chain.sent).toEqual([{ key: "k1", address: "addr:k1", calls: [CALL, CALL] }]);
    expect(await provider.status(id)).toBe("pending");
    chain.statuses.set(id, "succeeded");
    expect(await provider.status(id)).toBe("succeeded");
  });

  it("refuses an empty list of calls", async () => {
    const { provider } = setup();
    await provider.createOrRestore();
    expect(await rejection(provider.execute([]))).toBe("invalid");
  });

  it("sends one execution at a time, in the order asked", async () => {
    const { chain, provider } = setup();
    await provider.createOrRestore();
    chain.sendDelayMs = 5;
    const ids = await Promise.all(
      [1, 2, 3].map((n) => provider.execute([{ ...CALL, calldata: [n] }])),
    );
    expect(ids).toEqual(["x1", "x2", "x3"]);
    expect(chain.maxInFlight).toBe(1);
    expect(chain.sent.map((s) => s.calls[0]!.calldata[0])).toEqual([1, 2, 3]);
  });

  it("keeps sending after a failed execution", async () => {
    const { chain, provider } = setup();
    await provider.createOrRestore();
    chain.failSend = new AccountError("refused");
    expect(await rejection(provider.execute([CALL]))).toBe("refused");
    chain.failSend = new Error("socket closed");
    expect(await rejection(provider.execute([CALL]))).toBe("unavailable");
    chain.failSend = undefined;
    expect(await provider.execute([CALL])).toBe("x1");
  });

  it("reports an unknown execution, and an unreachable network as unavailable", async () => {
    const { chain, provider } = setup();
    await provider.createOrRestore();
    expect(await provider.status("nope" as never)).toBe("unknown");
    chain.failStatus = new Error("timeout");
    expect(await rejection(provider.status("x1" as never))).toBe("unavailable");
  });
});

describe("signOut", () => {
  it("ends the session and keeps the account on the device, to be restored", async () => {
    const { chain, funder, storage, provider } = setup();
    await provider.createOrRestore();
    await provider.signOut();
    expect(await rejection(provider.execute([CALL]))).toBe("not-ready");
    expect(storage.data.has(STORAGE_KEY)).toBe(true);
    expect(await provider.createOrRestore()).toEqual({ address: "addr:k1" });
    expect(await provider.execute([CALL])).toBe("x1");
    expect(chain.keys).toBe(1);
    expect(funder.provided).toHaveLength(1);
  });

  // F-2: an open that was pending when the player signed out does not open a session when it ends.
  it("while the account's deployment is being checked, cancels the pending open", async () => {
    const { chain, storage, provider } = setup();
    chain.checking = gate();
    const opening = provider.createOrRestore();
    await chain.checking.reached;
    await provider.signOut();
    chain.checking.open();
    expect(await rejection(opening)).toBe("not-ready");
    expect(await rejection(provider.execute([CALL]))).toBe("not-ready");
    expect(chain.sent).toEqual([]);
    expect(JSON.parse(storage.data.get(STORAGE_KEY)!)).toMatchObject({ key: "k1" });
  });

  it("while the game deploys and funds the account, cancels the pending open", async () => {
    const { chain, funder, storage, provider } = setup();
    funder.funding = gate();
    const opening = provider.createOrRestore();
    await funder.funding.reached;
    await provider.signOut();
    funder.funding.open();
    expect(await rejection(opening)).toBe("not-ready");
    expect(await rejection(provider.execute([CALL]))).toBe("not-ready");
    expect(chain.sent).toEqual([]);
    // The account was made and stays kept: signing in again restores it without funding again.
    expect(JSON.parse(storage.data.get(STORAGE_KEY)!)).toMatchObject({ key: "k1" });
    funder.funding = undefined;
    expect(await provider.createOrRestore()).toEqual({ address: "addr:k1" });
    expect(funder.provided).toEqual(["pub:k1"]);
  });

  it("an open asked again after the sign-out joins the same funding, and opens", async () => {
    const { funder, provider } = setup();
    funder.funding = gate();
    const first = provider.createOrRestore();
    await funder.funding.reached;
    await provider.signOut();
    const second = provider.createOrRestore();
    funder.funding.open();
    expect(await rejection(first)).toBe("not-ready");
    expect(await second).toEqual({ address: "addr:k1" });
    expect(funder.provided).toEqual(["pub:k1"]);
  });

  it("an execution waiting for its turn is not sent after the sign-out", async () => {
    const { chain, provider } = setup();
    await provider.createOrRestore();
    chain.sendDelayMs = 5;
    const first = provider.execute([CALL]);
    const second = provider.execute([CALL]);
    await new Promise((resolve) => setTimeout(resolve, 1));
    expect(chain.inFlight).toBe(1);
    await provider.signOut();
    expect(await first).toBe("x1");
    expect(await rejection(second)).toBe("not-ready");
    expect(chain.sent).toHaveLength(1);
  });
});

describe("what a player could see", () => {
  it("every error message is neutral: no word of the chain", () => {
    const codes: AccountErrorCode[] = ["not-ready", "unavailable", "refused", "invalid"];
    for (const code of codes) {
      const { message } = new AccountError(code);
      expect(message).not.toMatch(
        /fee|gas|wallet|sign|transaction|token|strk|chain|block|account|key|address|burner|starknet|nonce|contract|deploy|fund|pay/i,
      );
    }
  });
});
