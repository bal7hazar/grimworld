import { spawn, type ChildProcess } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { RpcProvider } from "starknet";
import { afterAll, describe, expect, it } from "vitest";
import {
  LOCAL_ACCOUNT_CLASS,
  STORAGE_KEY,
  STRK,
  createBurnerProvider,
  createFunder,
  createStarknetChain,
  type ExecutionStatus,
  type KeyStorage,
} from "../../../client/app/src/account/index.ts";
import { Secret } from "./secret.ts";

// The service on the real local node, with one of its published keys, and the client's burner
// through it. Run through the script that starts and stops the node:
//   scripts/with-node.sh pnpm --filter @grimworld/funder test:node
// Without a node (the ordinary `pnpm test`), skipped.
const nodeUrl = process.env.NODE_URL;
const PACKAGE = new URL("..", import.meta.url).pathname;

function memoryStorage(): KeyStorage {
  const data = new Map<string, string>();
  return {
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => void data.set(key, value),
    removeItem: (key) => void data.delete(key),
  };
}

async function settled(status: () => Promise<ExecutionStatus>): Promise<ExecutionStatus> {
  for (let i = 0; i < 200; i++) {
    const current = await status();
    if (current !== "pending") return current;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return "pending";
}

/** Everything the service printed and answered: AC-2 looks for the key in all of it. */
const seen: string[] = [];
const running: ChildProcess[] = [];

interface Service {
  url: string;
  stop(): Promise<void>;
}

/**
 * Starts `node src/main.ts` with an environment written here in full (nothing inherited but the
 * PATH): the service sees the funding key under its own name only.
 */
async function start(env: Record<string, string>): Promise<Service> {
  const child = spawn(process.execPath, ["src/main.ts"], {
    cwd: PACKAGE,
    env: { PATH: process.env.PATH ?? "", ...env },
    stdio: ["ignore", "pipe", "pipe"],
  });
  running.push(child);
  let out = "";
  const exited = new Promise<void>((resolve) => child.on("exit", () => resolve()));
  child.stdout!.on("data", (chunk: Buffer) => {
    out += chunk.toString();
    seen.push(chunk.toString());
  });
  child.stderr!.on("data", (chunk: Buffer) => seen.push(chunk.toString()));
  for (let i = 0; i < 200; i++) {
    const port = /"event":"listening","port":"(\d+)"/.exec(out)?.[1];
    if (port) {
      return {
        url: `http://127.0.0.1:${port}/v1/burners`,
        async stop() {
          child.kill("SIGTERM");
          await exited;
        },
      };
    }
    if (child.exitCode !== null) break;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`the service did not start: ${seen.join("")}`);
}

async function post(
  url: string,
  body: object,
): Promise<{ status: number; body: Record<string, string> }> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  seen.push(text);
  return { status: response.status, body: JSON.parse(text) };
}

afterAll(() => {
  for (const child of running) if (child.exitCode === null) child.kill("SIGKILL");
});

describe.skipIf(!nodeUrl)("the funding service on the local node", () => {
  it("funds a burner once, idempotently, within the day's budget, and never shows its key", async () => {
    const funderAddress = process.env.NODE_ACCOUNT_ADDRESS!;
    const funderKey = process.env.NODE_ACCOUNT_PRIVATE_KEY!;
    mkdirSync(join(PACKAGE, ".state"), { recursive: true });
    const stateDir = mkdtempSync(join(PACKAGE, ".state", "run-"));
    const stateFile = join(stateDir, "ledger.json");
    const env = {
      FUNDER_RPC_URL: nodeUrl!,
      FUNDER_ACCOUNT_ADDRESS: funderAddress,
      FUNDER_PRIVATE_KEY: funderKey,
      FUNDER_ACCOUNT_CLASS: LOCAL_ACCOUNT_CLASS,
      // The local node reports Sepolia's chain id.
      FUNDER_NETWORKS: "SN_SEPOLIA",
      FUNDER_AMOUNT: String(10n ** 19n),
      FUNDER_DAILY_BUDGET: "2",
      FUNDER_CLIENT_RATE: "10",
      FUNDER_PORT: "0",
      FUNDER_STATE_FILE: stateFile,
    };
    const node = new RpcProvider({ nodeUrl: nodeUrl! });
    const funderNonce = () => node.getNonceForAddress(funderAddress);
    const chain = createStarknetChain({ nodeUrl: nodeUrl!, accountClass: LOCAL_ACCOUNT_CLASS });
    const keyOf = (storage: KeyStorage) =>
      chain.derive((JSON.parse(storage.getItem(STORAGE_KEY)!) as { key: string }).key);

    // Fix loop 1, F-4: every answer the client's funder receives is recorded for the key's scan.
    const clientAnswers: string[] = [];
    const recording = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const response = await fetch(input, init);
      const text = await response.clone().text();
      clientAnswers.push(text);
      seen.push(text);
      return response;
    }) as typeof fetch;

    let service = await start(env);
    try {
      // 1. Two players at the same time (fix loop 1, F-1: two fundings on the real node, each with
      // its own nonce); the first's burner executes a call.
      const funder = createFunder({
        kind: "service",
        url: service.url,
        retryMs: 100,
        fetch: recording,
      });
      const storage = memoryStorage();
      const player = createBurnerProvider({ chain, funder, storage });
      const second = createBurnerProvider({ chain, funder, storage: memoryStorage() });
      const nonceBefore = await funderNonce();
      const [{ address }, { address: secondAddress }] = await Promise.all([
        player.createOrRestore(),
        second.createOrRestore(),
      ]);
      expect(await chain.isDeployed(address)).toBe(true);
      expect(await chain.isDeployed(secondAddress)).toBe(true);
      expect(BigInt(await funderNonce())).toBe(BigInt(nonceBefore) + 2n);
      expect(clientAnswers.filter((a) => a.includes('"repeated":false'))).toHaveLength(2);
      const id = await player.execute([
        { to: STRK, entrypoint: "approve", calldata: [funderAddress, 1n, 0n] },
      ]);
      expect(await settled(() => player.status(id))).toBe("succeeded");

      // 2. The same key again: the recorded answer, and nothing sent.
      const first = keyOf(storage);
      const before = await funderNonce();
      const again = await post(service.url, { publicKey: first.publicKey, address });
      expect(again.status).toBe(200);
      expect(again.body).toMatchObject({ status: "succeeded", repeated: true });
      expect(BigInt(again.body.address!)).toBe(BigInt(address));
      expect(await funderNonce()).toBe(before);

      // 3. The two burners used the day's budget of 2; a third is refused, and not deployed.
      const third = chain.derive(chain.newKey());
      const beforeThird = await funderNonce();
      const refused = await post(service.url, third);
      expect(refused).toEqual({ status: 503, body: { error: "exhausted" } });
      expect(await chain.isDeployed(third.address)).toBe(false);
      expect(await funderNonce()).toBe(beforeThird);

      // 4. A restart forgets neither: the budget stays spent, the first key stays funded.
      await service.stop();
      service = await start(env);
      expect(await post(service.url, third)).toEqual({ status: 503, body: { error: "exhausted" } });
      expect((await post(service.url, { publicKey: first.publicKey })).body).toMatchObject({
        status: "succeeded",
        repeated: true,
      });
      await service.stop();

      // 5. A network the configuration does not name is refused, and nothing is sent.
      service = await start({
        ...env,
        FUNDER_NETWORKS: "SN_OTHER",
        FUNDER_STATE_FILE: "",
        FUNDER_EPHEMERAL: "1",
      });
      const elsewhere = chain.derive(chain.newKey());
      const beforeElsewhere = await funderNonce();
      expect(await post(service.url, elsewhere)).toEqual({
        status: 403,
        body: { error: "refused" },
      });
      expect(await funderNonce()).toBe(beforeElsewhere);
      expect(await chain.isDeployed(elsewhere.address)).toBe(false);
      await service.stop();

      // AC-2: the key is in no line printed, no answer and no file the service wrote.
      const state = readFileSync(stateFile, "utf8");
      expect(JSON.parse(state).days).toEqual({ [new Date().toISOString().slice(0, 10)]: 2 });
      const everything = [...seen, state].join("\n").toLowerCase();
      expect(seen.join("")).toContain('"event":"funded"');
      // The client's own answers are in the scan: the two first fundings among them.
      for (const answer of clientAnswers) expect(seen).toContain(answer);
      expect(clientAnswers.length).toBeGreaterThanOrEqual(2);
      for (const form of new Secret(funderKey).forms()) {
        expect(everything).not.toContain(form.toLowerCase());
      }
    } finally {
      await service.stop();
      rmSync(stateDir, { recursive: true });
    }
  }, 180_000);
});
