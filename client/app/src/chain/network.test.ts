import { describe, expect, it, vi } from "vitest";
import type { BurnerChain, Funder, KeyStorage, NodeFunderConfig } from "../account";
import { LOCAL_ACCOUNT_CLASS } from "../account";
import { createRpc } from "../preview";
import {
  ChainRefused,
  type Deployment,
  SN_MAIN,
  SN_SEPOLIA,
  assertRecordedClasses,
  assertTestChain,
  fetchDeployment,
  fetchSepoliaEndpoint,
  openChain,
  openSepolia,
  parseDeployment,
} from "./network";
import { CONTRACT_NAMES, SEPOLIA } from "./networks";
import { type Credit, createCredit } from "./credit";
import { BURNER_FUNDS } from "./setup";

const NODE = "http://127.0.0.1:5050";
const hex = (n: bigint) => `0x${n.toString(16)}`;

const deploymentJson = {
  node_url: NODE,
  chain_id: "SN_SEPOLIA",
  commit: "abc",
  account: "0x64b4",
  classes: { hub: "0x1" },
  contracts: { registry: "0x11", tx_hash_fate: "0x12", hub: "0x13", instances: "0x14" },
  adventurer_id: 1,
  instance_id: 4294967297,
  slot: 1,
};
const deployment = parseDeployment(deploymentJson)!;

/** Accounts as the node publishes them: the keys are fake, and never leave the funder's config. */
const ACCOUNTS = [
  { address: "0xa0", private_key: "0xk0", public_key: "0xp0" },
  { address: "0xa1", private_key: "0xk1", public_key: "0xp1" },
];

/** A node answering JSON-RPC from `answers`; a method it lacks is a JSON-RPC error. */
function fakeNode(answers: Record<string, unknown>) {
  const calls: string[] = [];
  const fetch = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const { method, id } = JSON.parse(String(init?.body)) as { method: string; id: number };
    calls.push(method);
    const body = Object.hasOwn(answers, method)
      ? { jsonrpc: "2.0", id, result: answers[method] }
      : { jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found" } };
    return new Response(JSON.stringify(body));
  }) as unknown as typeof globalThis.fetch;
  return { fetch, calls, answers };
}

const devnet = () =>
  fakeNode({ starknet_chainId: hex(SN_SEPOLIA), devnet_getPredeployedAccounts: ACCOUNTS });

function memoryStorage(): KeyStorage {
  const data = new Map<string, string>();
  return {
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => void data.set(key, value),
    removeItem: (key) => void data.delete(key),
  };
}

/** A burner chain and funder that only count: nothing reaches a node. */
function fakes(deployed = false) {
  const sent = vi.fn(async () => "0xtx");
  const provided = vi.fn(async () => undefined);
  const configs: NodeFunderConfig[] = [];
  const chain: BurnerChain = {
    binding: async () => "0x534e5f5345504f4c4941/0x5b4",
    newKey: () => "0x1234",
    derive: () => ({ publicKey: "0xpub", address: "0xb0" }),
    isDeployed: async () => deployed,
    send: sent,
    status: async () => "succeeded",
  };
  const funder: Funder = { provide: provided };
  return {
    sent,
    provided,
    configs,
    makeChain: () => chain,
    makeFunder: (config: NodeFunderConfig) => {
      configs.push(config);
      return funder;
    },
  };
}

describe("parseDeployment (§2.2)", () => {
  it("keeps the node, the chain id and the four contracts", () => {
    expect(deployment).toEqual({
      nodeUrl: NODE,
      chainId: SN_SEPOLIA,
      contracts: deploymentJson.contracts,
    });
    // The id as `starknet_chainId` answers it, too
    expect(parseDeployment({ ...deploymentJson, chain_id: hex(SN_SEPOLIA) })?.chainId).toBe(
      SN_SEPOLIA,
    );
  });

  it("refuses anything without the deployment's shape", () => {
    const { contracts } = deploymentJson;
    for (const body of [
      null,
      "text",
      [],
      {},
      { ...deploymentJson, node_url: 5 },
      { ...deploymentJson, chain_id: undefined },
      { ...deploymentJson, chain_id: "" },
      { ...deploymentJson, contracts: undefined },
      { ...deploymentJson, contracts: { ...contracts, hub: undefined } },
      { ...deploymentJson, contracts: { ...contracts, instances: "hub" } },
      { ...deploymentJson, contracts: { ...contracts, registry: 17 } },
    ]) {
      expect(parseDeployment(body), JSON.stringify(body)).toBeUndefined();
    }
  });
});

describe("parseDeployment's build (CLI-11d3)", () => {
  const build = {
    mode: "full",
    bar: [1, 2, 3, 4, 0, 0, 0, 0],
    belt: [
      { item: 1, count: 2 },
      { item: 23, count: 1 },
    ],
  };

  it("keeps a full build's bar and belt", () => {
    expect(parseDeployment({ ...deploymentJson, build })).toEqual({
      ...deployment,
      build: { bar: build.bar, belt: build.belt },
    });
  });

  it("drops an empty build, or a build of another shape, and keeps the rest", () => {
    for (const bad of [
      { ...build, mode: "empty" },
      { ...build, bar: [0, 0, 0, 0, 0, 0, 0, 0] },
      { ...build, bar: [1, 2, 3] },
      { ...build, bar: [1, 2, 3, 4, 0, 0, 0, 65536] },
      { ...build, belt: [{ item: 1 }] },
      { ...build, belt: [{ item: 1, count: 256 }] },
      { ...build, belt: [1, 2, 3, 4, 5].map((item) => ({ item, count: 1 })) },
      null,
      "full",
    ]) {
      expect(parseDeployment({ ...deploymentJson, build: bad }), JSON.stringify(bad)).toEqual(
        deployment,
      );
    }
  });
});

describe("fetchDeployment (§2.2, §2.4)", () => {
  const answering = (response: () => Response | Promise<Response>) =>
    vi.fn(async () => response()) as unknown as typeof globalThis.fetch;

  it("reads the development server's /deployment.json", async () => {
    const fetch = answering(() => new Response(JSON.stringify(deploymentJson)));
    expect(await fetchDeployment(fetch)).toEqual(deployment);
    expect(fetch).toHaveBeenCalledWith("/deployment.json", expect.anything());
  });

  it("is no deployment for the site's index.html with a 200, a 404, or a network error", async () => {
    const html = '<!doctype html><html><head><title>Grim World</title></head><body><div id="root">';
    for (const fetch of [
      answering(
        () => new Response(html, { status: 200, headers: { "content-type": "text/html" } }),
      ),
      answering(() => new Response("", { status: 404 })),
      answering(() => new Response(JSON.stringify(deploymentJson), { status: 500 })),
      answering(() => new Response(JSON.stringify({ node_url: NODE }))),
      answering(() => Promise.reject(new TypeError("fetch failed"))),
    ]) {
      await expect(fetchDeployment(fetch)).rejects.toEqual(new ChainRefused("no deployment"));
    }
  });
});

describe("assertTestChain (§2.3)", () => {
  it("passes on SN_SEPOLIA with the local node's own method", async () => {
    const node = devnet();
    await expect(assertTestChain(createRpc(NODE, node.fetch))).resolves.toBeUndefined();
    expect(node.calls).toEqual(["starknet_chainId", "devnet_getPredeployedAccounts"]);
  });

  it("refuses SN_MAIN by name, and any other id, before its second probe", async () => {
    for (const id of [SN_MAIN, 0x534e5f474f45524c49n, 1n]) {
      const node = fakeNode({ starknet_chainId: hex(id), devnet_getPredeployedAccounts: [] });
      await expect(assertTestChain(createRpc(NODE, node.fetch))).rejects.toEqual(
        new ChainRefused("not a test chain"),
      );
      expect(node.calls).toEqual(["starknet_chainId"]);
    }
  });

  it("refuses a Sepolia node that is not the local one (no devnet_getPredeployedAccounts)", async () => {
    const node = fakeNode({ starknet_chainId: hex(SN_SEPOLIA) });
    await expect(assertTestChain(createRpc(NODE, node.fetch))).rejects.toEqual(
      new ChainRefused("not a test chain"),
    );
  });
});

describe("openChain (§2.2, §2.3, §3.1)", () => {
  it("refuses a deployment of another node before any request", async () => {
    const node = devnet();
    const other: Deployment = { ...deployment, nodeUrl: "http://127.0.0.1:5051" };
    await expect(openChain(NODE, other, { fetch: node.fetch })).rejects.toEqual(
      new ChainRefused("deployment of another node"),
    );
    // The same node, written otherwise, is another string: §2.2 compares them as written
    await expect(openChain(`${NODE}/`, deployment, { fetch: node.fetch })).rejects.toEqual(
      new ChainRefused("deployment of another node"),
    );
    expect(node.calls).toEqual([]);
  });

  it("refuses a node whose chain id is not the deployment's", async () => {
    const node = fakeNode({ starknet_chainId: "0x1", devnet_getPredeployedAccounts: ACCOUNTS });
    await expect(openChain(NODE, deployment, { fetch: node.fetch })).rejects.toEqual(
      new ChainRefused("deployment of another node"),
    );
  });

  it("refuses SN_MAIN (faked) before any read of the game, and builds no chain", async () => {
    const node = fakeNode({ starknet_chainId: hex(SN_MAIN), devnet_getPredeployedAccounts: [] });
    const f = fakes();
    const main = { ...deployment, chainId: SN_MAIN };
    await expect(openChain(NODE, main, { fetch: node.fetch, ...f })).rejects.toEqual(
      new ChainRefused("not a test chain"),
    );
    expect(node.calls.every((m) => m === "starknet_chainId")).toBe(true);
    expect(f.configs).toEqual([]);
    expect(f.sent).not.toHaveBeenCalled();
  });

  it("funds burners from the node's account 1, 100 STRK, held in memory only", async () => {
    const node = devnet();
    const f = fakes();
    const storage = memoryStorage();
    await openChain(NODE, deployment, { fetch: node.fetch, storage, ...f });
    expect(f.configs).toHaveLength(1);
    expect(f.configs[0]).toMatchObject({
      nodeUrl: NODE,
      accountClass: LOCAL_ACCOUNT_CLASS,
      funderAddress: "0xa1",
      funderKey: "0xk1",
      amount: BURNER_FUNDS,
    });
    expect(BURNER_FUNDS).toBe(100n * 10n ** 18n);
    // Opening stores nothing: the burner's key is kept only once it is created
    expect(storage.getItem("grimworld.account")).toBeNull();
  });

  it("on SN_MAIN (faked) after opening, refuses the funding before `provide`", async () => {
    const node = devnet();
    const f = fakes(false);
    const { provider } = await openChain(NODE, deployment, {
      fetch: node.fetch,
      storage: memoryStorage(),
      ...f,
    });
    node.answers.starknet_chainId = hex(SN_MAIN);
    await expect(provider.createOrRestore()).rejects.toMatchObject({
      code: "unavailable",
      cause: new ChainRefused("not a test chain"),
    });
    expect(f.provided).not.toHaveBeenCalled();
    // Back on the local node, the funding goes through the same guard and reaches `provide`
    node.answers.starknet_chainId = hex(SN_SEPOLIA);
    await provider.createOrRestore();
    expect(f.provided).toHaveBeenCalledTimes(1);
  });

  it("on SN_MAIN (faked) after opening, refuses the setup's executions before `send`", async () => {
    const node = devnet();
    const f = fakes(true);
    const { provider, assertChain } = await openChain(NODE, deployment, {
      fetch: node.fetch,
      storage: memoryStorage(),
      ...f,
    });
    await provider.createOrRestore();
    const register = { to: "0x13", entrypoint: "register", calldata: [] };
    await provider.execute([register]);
    expect(f.sent).toHaveBeenCalledTimes(1);
    node.answers.starknet_chainId = hex(SN_MAIN);
    await expect(provider.execute([register])).rejects.toMatchObject({
      cause: new ChainRefused("not a test chain"),
    });
    await expect(assertChain()).rejects.toEqual(new ChainRefused("not a test chain"));
    expect(f.sent).toHaveBeenCalledTimes(1);
    // A node that drops the local node's method behind the same URL is refused too
    node.answers.starknet_chainId = hex(SN_SEPOLIA);
    delete node.answers.devnet_getPredeployedAccounts;
    await expect(provider.execute([register])).rejects.toMatchObject({
      cause: new ChainRefused("not a test chain"),
    });
    expect(f.sent).toHaveBeenCalledTimes(1);
  });
});

describe("openChain with the credit (CLI-11d3, caveat c)", () => {
  /** A credit whose state the test sets. */
  function credit(
    state: "idle" | "running" | "unusable",
  ): Credit & { set(next: typeof state): void } {
    let now = state;
    const base = createCredit(async () => ({
      status: 200,
      body: JSON.stringify({ state: now, credits: 0 }),
    }));
    return { ...base, set: (next) => void (now = next) };
  }

  it("refuses every send and funding once the devnet was left mid-credit", async () => {
    const node = devnet();
    const f = fakes(true);
    const devnetCredit = credit("idle");
    const opened = await openChain(NODE, deployment, {
      fetch: node.fetch,
      storage: memoryStorage(),
      credit: devnetCredit,
      ...f,
    });
    expect(opened.credit).toBe(devnetCredit);
    await opened.provider.createOrRestore();
    const register = { to: "0x13", entrypoint: "register", calldata: [] };
    await opened.provider.execute([register]);
    expect(f.sent).toHaveBeenCalledTimes(1);
    devnetCredit.set("unusable");
    const refused = new ChainRefused("devnet left mid-credit: redeploy");
    await expect(opened.provider.execute([register])).rejects.toMatchObject({ cause: refused });
    await expect(opened.assertChain()).rejects.toEqual(refused);
    expect(f.sent).toHaveBeenCalledTimes(1);
  });

  it("opens without a credit as before", async () => {
    const opened = await openChain(NODE, deployment, {
      fetch: devnet().fetch,
      storage: memoryStorage(),
      ...fakes(),
    });
    expect(opened.credit).toBeUndefined();
    await expect(opened.assertChain()).resolves.toBeUndefined();
  });
});

describe("the chain mode's files (§2.3)", () => {
  const sources = import.meta.glob<string>("./**/*.{ts,tsx}", {
    query: "?raw",
    import: "default",
    eager: true,
  });
  const files = Object.entries(sources).filter(([path]) => path !== "./network.test.ts");

  it("import nothing of account/starknet directly", () => {
    expect(files.length).toBeGreaterThanOrEqual(6);
    const direct = files
      .filter(([, text]) => /from\s+["'][^"']*account\/starknet["']|starknet["']\)/.test(text))
      .map(([path]) => path);
    expect(direct).toEqual([]);
    // Nor the library itself, tests apart (they hold selectors to its hash, as calls.test.ts does)
    const library = files
      .filter(([path]) => !/\.test\.tsx?$/.test(path))
      .filter(([, text]) => /from\s+["']starknet["']/.test(text));
    expect(library).toEqual([]);
  });

  it("hold no call of account 0's: no set_contracts, no report, no admin (D-273, CLI-11d3)", () => {
    const admin = files
      .filter(([path]) => !/\.test\.tsx?$/.test(path))
      .filter(([, text]) => /set_contracts|["'`]report["'`]|set_admin|"instances"\s*:/.test(text))
      .map(([path]) => path);
    expect(admin).toEqual([]);
  });

  it("name the burner's chain and funder factories in network.ts only", () => {
    const naming = files
      .filter(([, text]) => /createStarknetChain|createNodeFunder|createServiceFunder/.test(text))
      .map(([path]) => path);
    expect(naming).toEqual(["./network.ts"]);
  });
});

/**
 * A Sepolia node: its chain id and, per address, the class hash it answers; an address it lacks is
 * CONTRACT_NOT_FOUND (20), as a node answers it. Any other method is an error.
 */
function sepoliaNode(chainId: bigint, classes: Record<string, string>) {
  const calls: string[] = [];
  const fetch = vi.fn(async (_url: unknown, init?: RequestInit) => {
    const { method, id, params } = JSON.parse(String(init?.body)) as {
      method: string;
      id: number;
      params: { contract_address?: string };
    };
    calls.push(method);
    const result =
      method === "starknet_chainId"
        ? hex(chainId)
        : method === "starknet_getClassHashAt"
          ? classes[params.contract_address ?? ""]
          : undefined;
    const body =
      result !== undefined
        ? { jsonrpc: "2.0", id, result }
        : method === "starknet_getClassHashAt"
          ? { jsonrpc: "2.0", id, error: { code: 20, message: "Contract not found" } }
          : { jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found" } };
    return new Response(JSON.stringify(body));
  }) as unknown as typeof globalThis.fetch;
  return { fetch, calls };
}

const recorded = () =>
  Object.fromEntries(
    CONTRACT_NAMES.map((name) => [
      SEPOLIA.contracts[name].address,
      SEPOLIA.contracts[name].classHash,
    ]),
  );
const ENDPOINT = "https://sepolia.example.org/rpc";

describe("assertRecordedClasses (CLI-11e1, D-154)", () => {
  it("passes when the class at each of the four addresses is the recorded one", async () => {
    const node = sepoliaNode(SN_SEPOLIA, recorded());
    await assertRecordedClasses(createRpc(ENDPOINT, node.fetch), SEPOLIA);
    expect(node.calls).toEqual(CONTRACT_NAMES.map(() => "starknet_getClassHashAt"));
  });

  it("compares the hashes as numbers: a node's unpadded spelling still matches", async () => {
    const classes = recorded();
    const hub = SEPOLIA.contracts.hub.address;
    classes[hub] = hex(BigInt(classes[hub]!));
    await assertRecordedClasses(
      createRpc(ENDPOINT, sepoliaNode(SN_SEPOLIA, classes).fetch),
      SEPOLIA,
    );
  });

  it("refuses a class hash that is not the recorded one, the reason only", async () => {
    for (const name of CONTRACT_NAMES) {
      const classes = recorded();
      classes[SEPOLIA.contracts[name].address] = "0x1234";
      const rpc = createRpc(ENDPOINT, sepoliaNode(SN_SEPOLIA, classes).fetch);
      const refused = await assertRecordedClasses(rpc, SEPOLIA).catch((error: unknown) => error);
      expect(refused, name).toBeInstanceOf(ChainRefused);
      expect((refused as ChainRefused).reason).toBe("Sepolia contracts differ from the record");
      expect((refused as Error).message).not.toContain("0x1234");
    }
  });

  it("refuses a missing contract (CONTRACT_NOT_FOUND)", async () => {
    const classes = recorded();
    delete classes[SEPOLIA.contracts.instances.address];
    const rpc = createRpc(ENDPOINT, sepoliaNode(SN_SEPOLIA, classes).fetch);
    await expect(assertRecordedClasses(rpc, SEPOLIA)).rejects.toMatchObject({
      name: "ChainRefused",
      reason: "Sepolia contracts differ from the record",
    });
  });

  it("throws a node error as it is: not a refusal", async () => {
    const down = vi.fn(async () => {
      throw new TypeError("fetch failed");
    }) as unknown as typeof globalThis.fetch;
    await expect(assertRecordedClasses(createRpc(ENDPOINT, down), SEPOLIA)).rejects.toThrow(
      TypeError,
    );
    const failing = vi.fn(
      async (_url: unknown, init?: RequestInit) =>
        new Response(
          JSON.stringify({
            jsonrpc: "2.0",
            id: (JSON.parse(String(init?.body)) as { id: number }).id,
            error: { code: -32603, message: "Internal error" },
          }),
        ),
    ) as unknown as typeof globalThis.fetch;
    const error = await assertRecordedClasses(createRpc(ENDPOINT, failing), SEPOLIA).catch(
      (caught: unknown) => caught,
    );
    expect(error).not.toBeInstanceOf(ChainRefused);
    expect(error).toMatchObject({ name: "SimulationError", code: -32603 });
  });
});

describe("openSepolia (CLI-11e1)", () => {
  it("checks the chain id and the classes, then stops before any funding", async () => {
    const node = sepoliaNode(SN_SEPOLIA, recorded());
    await expect(openSepolia(ENDPOINT, { fetch: node.fetch })).rejects.toMatchObject({
      name: "ChainRefused",
      reason: "Sepolia: funding service not configured (CLI-11e2)",
      message: "chain mode refused: Sepolia: funding service not configured (CLI-11e2)",
    });
    // Reads only: the chain id, then the four classes; no send, no estimate, no account
    expect(node.calls).toEqual([
      "starknet_chainId",
      ...CONTRACT_NAMES.map(() => "starknet_getClassHashAt"),
    ]);
  });

  it("refuses SN_MAIN, and any other chain, before reading a class", async () => {
    for (const id of [SN_MAIN, 0x1234n]) {
      const node = sepoliaNode(id, recorded());
      await expect(openSepolia(ENDPOINT, { fetch: node.fetch })).rejects.toMatchObject({
        reason: "not a test chain",
      });
      expect(node.calls).toEqual(["starknet_chainId"]);
    }
  });

  it("refuses a class mismatch or a missing contract before the funding line", async () => {
    const mismatch = recorded();
    mismatch[SEPOLIA.contracts.registry.address] = "0x1";
    const missing = recorded();
    delete missing[SEPOLIA.contracts.hub.address];
    for (const classes of [mismatch, missing]) {
      const node = sepoliaNode(SN_SEPOLIA, classes);
      await expect(openSepolia(ENDPOINT, { fetch: node.fetch })).rejects.toMatchObject({
        reason: "Sepolia contracts differ from the record",
      });
    }
  });

  it("does not ask the node for pre-funded accounts: a public node has none", async () => {
    const node = sepoliaNode(SN_SEPOLIA, recorded());
    await openSepolia(ENDPOINT, { fetch: node.fetch }).catch(() => undefined);
    expect(node.calls).not.toContain("devnet_getPredeployedAccounts");
  });
});

describe("fetchSepoliaEndpoint (CLI-11e1)", () => {
  const answering = (status: number, body: string) =>
    vi.fn(async () => new Response(body, { status })) as unknown as typeof globalThis.fetch;

  it("takes the development server's keyless https endpoint", async () => {
    const body = JSON.stringify({ node_url: ENDPOINT });
    await expect(fetchSepoliaEndpoint(answering(200, body))).resolves.toBe(ENDPOINT);
  });

  it("is no Sepolia endpoint for a 404, the site's index.html, a network error or a keyed URL", async () => {
    const down = vi.fn(async () => {
      throw new TypeError("fetch failed");
    }) as unknown as typeof globalThis.fetch;
    for (const fetch of [
      answering(404, ""),
      answering(200, "<!doctype html><html></html>"),
      answering(200, JSON.stringify({ node_url: "http://sepolia.example.org/rpc" })),
      answering(200, JSON.stringify({ node_url: "https://sepolia.example.org/rpc?apikey=k" })),
      answering(200, JSON.stringify({ node_url: "https://user:k@sepolia.example.org/rpc" })),
      answering(200, JSON.stringify({})),
      down,
    ]) {
      await expect(fetchSepoliaEndpoint(fetch)).rejects.toMatchObject({
        reason: "no Sepolia endpoint",
      });
    }
  });
});
