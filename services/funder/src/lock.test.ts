import { spawn } from "node:child_process";
import * as fs from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { FundingChain, FundingStatus } from "./chain.ts";
import { fileLedger, type Ledger } from "./ledger.ts";
import { HOUR_MS, createFundingService } from "./service.ts";

// Fix loop 3, F-5: at most one service owns a state file, whatever the timing of starts and of
// recoveries from a lock left by a service that stopped.

/** Runs once, at the first unlink of a lock file: the audit's moment, between A's check and act. */
const hook: { before?: (path: string) => void } = {};

vi.mock("node:fs", async (original) => {
  const real = await original<typeof import("node:fs")>();
  return {
    ...real,
    unlinkSync: (path: fs.PathLike) => {
      const run = hook.before;
      if (run && String(path).endsWith(".lock")) {
        hook.before = undefined;
        run(String(path));
      }
      return real.unlinkSync(path);
    },
  };
});

const dirs: string[] = [];
function stateFile(): string {
  fs.mkdirSync(join(import.meta.dirname, "..", ".state"), { recursive: true });
  const dir = fs.mkdtempSync(join(import.meta.dirname, "..", ".state", "lock-"));
  dirs.push(dir);
  return join(dir, "ledger.json");
}

afterEach(() => {
  hook.before = undefined;
  for (const dir of dirs.splice(0)) fs.rmSync(dir, { recursive: true });
});

/** Above any pid Linux hands out (pid_max is at most 2^22): a service that stopped. */
const STOPPED = String(2 ** 30);

function open(path: string): Ledger | Error {
  try {
    return fileLedger(path);
  } catch (error) {
    return error as Error;
  }
}

/**
 * Starter A opens the ledger; at the audit's moment (A about to remove a lock it found stale), or
 * when A is done if it never gets there, starter B opens it too.
 */
function twoStarts(path: string): (Ledger | Error)[] {
  let b: Ledger | Error | undefined;
  hook.before = () => {
    b = open(path);
  };
  const a = open(path);
  if (hook.before) {
    hook.before = undefined;
    b = open(path);
  }
  return [a, b!];
}

/** One node for every service admitted: an execution must carry the account's next nonce. */
function sharedNode() {
  const txs = new Map<string, { nonce: bigint; status: FundingStatus }>();
  const handed: { transaction: string; nonce: bigint }[] = [];
  let latest = 0n;
  let count = 0;
  const chain: FundingChain = {
    addressOf: (publicKey) => ({ publicKey, address: `0xa${BigInt(publicKey).toString(16)}` }),
    isDeployed: async () => false,
    nonce: async () => latest,
    async prepare(_publicKey, _address, nonce) {
      const transaction = `0x7${(++count).toString(16)}`;
      return { transaction, payload: JSON.stringify({ transaction, nonce: String(nonce) }) };
    },
    submit(payload) {
      const { transaction, nonce } = JSON.parse(payload) as { transaction: string; nonce: string };
      handed.push({ transaction, nonce: BigInt(nonce) });
      if (BigInt(nonce) !== latest) return Promise.reject(new Error("invalid nonce"));
      txs.set(transaction, { nonce: BigInt(nonce), status: "succeeded" });
      latest++;
      return Promise.resolve(transaction);
    },
    verify: async () => undefined,
    status: async (id) => txs.get(id)?.status ?? "unknown",
  };
  return { chain, handed };
}

/** Every service admitted funds a key of its own, with a day's budget of one. */
async function fundWithEach(ledgers: Ledger[]) {
  const node = sharedNode();
  let n = 0;
  for (const ledger of ledgers) {
    const service = createFundingService({
      chain: node.chain,
      ledger,
      limits: { dailyBudget: 1, clientRate: 10, windowMs: HOUR_MS, settleMs: 1_000, pollMs: 100 },
      now: () => Date.UTC(2026, 8, 29, 10),
      sleep: async () => undefined,
    });
    await service.fund({ publicKey: `0x${(++n).toString(16)}` }, "c");
  }
  return node.handed;
}

describe("two starts against a lock left by a service that stopped", () => {
  it("admit at most one service, and so at most the day's budget", async () => {
    const path = stateFile();
    fs.writeFileSync(`${path}.lock`, STOPPED);
    const starts = twoStarts(path);
    const admitted = starts.filter((s): s is Ledger => !(s instanceof Error));
    const handed = await fundWithEach(admitted);
    for (const ledger of admitted) ledger.close();
    // What the node received, with a day's budget of one: the audit's consequence.
    expect(handed.map((h) => `${h.transaction}@${h.nonce}`)).toHaveLength(
      Math.min(handed.length, 1),
    );
    expect(admitted.length).toBeLessThanOrEqual(1);
  });

  it("admit none: a lock is never taken over, the operator removes it", () => {
    const path = stateFile();
    fs.writeFileSync(`${path}.lock`, STOPPED);
    const starts = twoStarts(path);
    expect(starts.every((s) => s instanceof Error)).toBe(true);
    expect(fs.readFileSync(`${path}.lock`, "utf8")).toBe(STOPPED);
    // The operator's step: no service runs on this host, the lock is removed.
    fs.unlinkSync(`${path}.lock`);
    const admitted = twoStarts(path).filter((s): s is Ledger => !(s instanceof Error));
    expect(admitted).toHaveLength(1);
    for (const ledger of admitted) ledger.close();
  });
});

/** Starts `count` processes at once, each opening the ledger and holding it for a moment. */
function race(path: string, count: number): Promise<string[]> {
  const ledger = new URL("./ledger.ts", import.meta.url).href;
  const script = `
    import { fileLedger } from ${JSON.stringify(ledger)};
    let ledger;
    try { ledger = fileLedger(${JSON.stringify(path)}); } catch (e) { console.log(e.name); process.exit(0); }
    console.log("admitted");
    // Held long enough that every other process has tried while it is held.
    setTimeout(() => ledger.close(), 5000);
  `;
  return Promise.all(
    Array.from(
      { length: count },
      () =>
        new Promise<string>((resolve, reject) => {
          const child = spawn(process.execPath, ["--input-type=module", "-e", script], {
            stdio: ["ignore", "pipe", "inherit"],
          });
          let out = "";
          child.stdout.on("data", (chunk: Buffer) => (out += chunk.toString()));
          child.on("error", reject);
          child.on("exit", () => resolve(out.trim()));
        }),
    ),
  );
}

describe("processes started at the same time", () => {
  it("one is admitted when no lock is there; none when a stopped service left one", async () => {
    const free = stateFile();
    const first = await race(free, 8);
    expect(first.filter((r) => r === "admitted")).toHaveLength(1);
    expect(first.filter((r) => r === "LedgerLocked")).toHaveLength(7);
    // The admitted process removed its lock when it closed the ledger.
    expect(fs.existsSync(`${free}.lock`)).toBe(false);

    const stale = stateFile();
    fs.writeFileSync(`${stale}.lock`, STOPPED);
    const second = await race(stale, 8);
    expect(second.filter((r) => r === "admitted")).toHaveLength(0);
  }, 30_000);
});
