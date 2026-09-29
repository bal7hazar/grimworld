import { Account, Signer, ec } from "starknet";
import { afterEach, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import {
  LOCAL_ACCOUNT_CLASS,
  LocalNodeRefused,
  createNodeFunder,
  createStarknetChain,
  type NodeFunderConfig,
} from "./starknet";

// Fix loops 1 and 2, F-1: the development funder refuses anything but the local node, before
// anything is signed or sent. Offline: every request goes through a fake `fetch` that records its
// URL and method, and spies on the library's signer and `Account.execute` show directly that no
// refused path reaches a signature or an execution.

const FUNDER = "0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691";
const KEY = "0x71d7bb07b9a64f6f78ac4c816aff4da9";
const LOCAL = "http://127.0.0.1:5050";
const SN_SEPOLIA = "0x534e5f5345504f4c4941";
const SN_MAIN = "0x534e5f4d41494e";

/** Methods that sign or send, or prepare to: none may be reached when the funder refuses. */
const SENDING = /addInvokeTransaction|addDeployAccount|estimateFee|getNonce|simulate/;

interface Node {
  /** `undefined`: the method does not exist on this node. */
  predeployed?: { address: string; private_key: string }[];
  chainId?: string;
  deployed?: boolean;
}

function fakeFetch(node: Node, onRequest?: (method: string) => void) {
  const methods: string[] = [];
  const urls: string[] = [];
  const fetch = async (url: unknown, init?: { body?: unknown }) => {
    const { id, method } = JSON.parse(String(init?.body)) as { id: number; method: string };
    methods.push(method);
    urls.push(String(url));
    onRequest?.(method);
    const answer = (result: unknown) =>
      new Response(JSON.stringify({ jsonrpc: "2.0", id, result }));
    const error = (code: number, message: string) =>
      new Response(JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }));
    switch (method) {
      case "devnet_getPredeployedAccounts":
        return node.predeployed ? answer(node.predeployed) : error(-32601, "Method not found");
      case "starknet_chainId":
        return answer(node.chainId ?? SN_SEPOLIA);
      case "starknet_specVersion":
        return answer("0.10.0");
      case "starknet_getClassHashAt":
        return node.deployed ? answer(LOCAL_ACCOUNT_CLASS) : error(20, "Contract not found");
      default:
        return error(-32601, "Method not found");
    }
  };
  return { fetch: fetch as unknown as typeof globalThis.fetch, methods, urls };
}

function funder(
  nodeUrl: string,
  node: Node,
  overrides: { key?: string; address?: string } = {},
  onRequest?: (method: string, config: NodeFunderConfig) => void,
) {
  const config: NodeFunderConfig = {
    nodeUrl,
    accountClass: LOCAL_ACCOUNT_CLASS,
    funderAddress: overrides.address ?? FUNDER,
    funderKey: overrides.key ?? KEY,
    amount: 1n,
  };
  const { fetch, methods, urls } = fakeFetch(node, (method) => onRequest?.(method, config));
  config.fetch = fetch;
  const provider = createNodeFunder(config);
  return { provider, methods, urls, config };
}

const PUBLIC = "https://starknet-sepolia.public.blastapi.io/rpc/v0_9";

let execute: MockInstance;
let signs: MockInstance[];

beforeEach(() => {
  execute = vi.spyOn(Account.prototype, "execute");
  signs = (
    [
      "signTransaction",
      "signMessage",
      "signDeployAccountTransaction",
      "signDeclareTransaction",
    ] as const
  ).map((method) => vi.spyOn(Signer.prototype, method));
});

afterEach(() => {
  vi.restoreAllMocks();
});

/** Asserted directly on the library: no execution was started and nothing was signed. */
function expectNothingSignedOrExecuted() {
  expect(execute).not.toHaveBeenCalled();
  for (const sign of signs) expect(sign).not.toHaveBeenCalled();
}

const LOCAL_NODE: Node = { predeployed: [{ address: FUNDER, private_key: KEY }] };

async function refusal(promise: Promise<unknown>): Promise<string> {
  const error = await promise.then(
    () => undefined,
    (e: unknown) => e,
  );
  expect(error).toBeInstanceOf(LocalNodeRefused);
  return (error as Error).message;
}

describe("the development funder refuses anything but the local node", () => {
  it.each([
    "https://starknet-sepolia.public.blastapi.io/rpc/v0_9",
    "https://starknet-mainnet.infura.io/v3/x",
    "http://10.0.0.5:5050",
    "http://127.0.0.1.example.com:5050",
    "ws://127.0.0.1:5050",
    "not a url",
  ])("an endpoint off this machine, before any request: %s", async (url) => {
    const { provider, methods } = funder(url, LOCAL_NODE);
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/endpoint/);
    expect(methods).toEqual([]);
    expectNothingSignedOrExecuted();
  });

  it("a loopback endpoint that is not the local node (a tunnel to a public node)", async () => {
    const { provider, methods } = funder(LOCAL, { chainId: SN_SEPOLIA });
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/devnet_getPredeployedAccounts/);
    expect(methods).toEqual(["devnet_getPredeployedAccounts"]);
    expectNothingSignedOrExecuted();
  });

  it("a funder the node does not publish", async () => {
    const { provider, methods } = funder(LOCAL, LOCAL_NODE, { address: "0xbad" });
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/pre-funded/);
    expect(methods).toEqual(["devnet_getPredeployedAccounts"]);
    expectNothingSignedOrExecuted();
  });

  it("a published funder address with another key", async () => {
    const { provider, methods } = funder(LOCAL, LOCAL_NODE, { key: "0x1234" });
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/pre-funded/);
    expect(methods).toEqual(["devnet_getPredeployedAccounts"]);
    expectNothingSignedOrExecuted();
  });

  it("mainnet's chain id", async () => {
    const { provider, methods } = funder(LOCAL, { ...LOCAL_NODE, chainId: SN_MAIN });
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/mainnet/);
    expect(methods.some((m) => SENDING.test(m))).toBe(false);
    expectNothingSignedOrExecuted();
  });
});

// Fix loop 2, F-1: the funder reads a frozen copy of its configuration, taken at construction.
describe("a configuration changed after the funder is made changes nothing", () => {
  it("a public URL changed to loopback after construction is still refused, before any request", async () => {
    const { provider, config, urls } = funder(PUBLIC, LOCAL_NODE);
    config.nodeUrl = LOCAL;
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/endpoint/);
    expect(urls).toEqual([]);
    expectNothingSignedOrExecuted();
  });

  it("a loopback URL changed to a public one after construction: every request stays local", async () => {
    const { provider, config, urls } = funder(LOCAL, { ...LOCAL_NODE, deployed: true });
    config.nodeUrl = PUBLIC;
    await provider.provide("0x1", "0x2");
    expect(urls.length).toBeGreaterThanOrEqual(3);
    expect(new Set(urls)).toEqual(new Set([LOCAL]));
    expectNothingSignedOrExecuted();
  });

  it("credentials refused at construction stay refused when changed to published ones", async () => {
    const { provider, config } = funder(LOCAL, LOCAL_NODE, { key: "0x1234" });
    config.funderKey = KEY;
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/pre-funded/);
    expectNothingSignedOrExecuted();
  });

  it("while the check is pending, changed credentials, class and URL are not the ones used", async () => {
    // A real burner's key and address, so the deployment reaches the execution.
    const chain = createStarknetChain({ nodeUrl: LOCAL, accountClass: LOCAL_ACCOUNT_CLASS });
    const burner = chain.derive("0x5eed");
    const { provider, urls } = funder(LOCAL, LOCAL_NODE, {}, (method, config) => {
      if (method !== "devnet_getPredeployedAccounts") return;
      config.funderKey = "0x1234";
      config.funderAddress = "0xbad";
      config.accountClass = "0x1";
      config.nodeUrl = PUBLIC;
    });
    const used: { address?: string; publicKey?: string } = {};
    execute.mockImplementation(async function (this: Account) {
      used.address = this.address;
      used.publicKey = await this.signer.getPubKey();
      throw new Error("stopped by the test");
    });
    const error = await provider.provide(burner.publicKey, burner.address).catch((e: Error) => e);
    expect((error as Error).message).toBe("stopped by the test");
    expect(execute).toHaveBeenCalledTimes(1);
    expect(BigInt(used.address!)).toBe(BigInt(FUNDER));
    expect(BigInt(used.publicKey!)).toBe(BigInt(ec.starkCurve.getStarkKey(KEY)));
    expect(new Set(urls)).toEqual(new Set([LOCAL]));
    for (const sign of signs) expect(sign).not.toHaveBeenCalled();
  });

  it("passes the local node, then signs nothing for an account that exists", async () => {
    const { provider, methods } = funder("http://localhost:5050", {
      ...LOCAL_NODE,
      deployed: true,
    });
    await provider.provide("0x1", "0x2");
    expect(methods.slice(0, 2)).toEqual(["devnet_getPredeployedAccounts", "starknet_chainId"]);
    expect(methods).toContain("starknet_getClassHashAt");
    expect(methods.some((m) => SENDING.test(m))).toBe(false);
  });
});
