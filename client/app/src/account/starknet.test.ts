import { describe, expect, it } from "vitest";
import { LOCAL_ACCOUNT_CLASS, LocalNodeRefused, createNodeFunder } from "./starknet";

// Fix loop 1, F-1: the development funder refuses anything but the local node, before anything is
// signed or sent. Offline: every request goes through a fake `fetch` that records its method.

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

function fakeFetch(node: Node) {
  const methods: string[] = [];
  const fetch = async (_url: unknown, init?: { body?: unknown }) => {
    const { id, method } = JSON.parse(String(init?.body)) as { id: number; method: string };
    methods.push(method);
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
  return { fetch: fetch as unknown as typeof globalThis.fetch, methods };
}

function funder(nodeUrl: string, node: Node, overrides: { key?: string; address?: string } = {}) {
  const { fetch, methods } = fakeFetch(node);
  const provider = createNodeFunder({
    nodeUrl,
    accountClass: LOCAL_ACCOUNT_CLASS,
    funderAddress: overrides.address ?? FUNDER,
    funderKey: overrides.key ?? KEY,
    amount: 1n,
    fetch,
  });
  return { provider, methods };
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
  });

  it("a loopback endpoint that is not the local node (a tunnel to a public node)", async () => {
    const { provider, methods } = funder(LOCAL, { chainId: SN_SEPOLIA });
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/devnet_getPredeployedAccounts/);
    expect(methods).toEqual(["devnet_getPredeployedAccounts"]);
  });

  it("a funder the node does not publish", async () => {
    const { provider, methods } = funder(LOCAL, LOCAL_NODE, { address: "0xbad" });
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/pre-funded/);
    expect(methods).toEqual(["devnet_getPredeployedAccounts"]);
  });

  it("a published funder address with another key (a key of value)", async () => {
    const { provider, methods } = funder(LOCAL, LOCAL_NODE, { key: "0x1234" });
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/pre-funded/);
    expect(methods).toEqual(["devnet_getPredeployedAccounts"]);
  });

  it("mainnet's chain id", async () => {
    const { provider, methods } = funder(LOCAL, { ...LOCAL_NODE, chainId: SN_MAIN });
    expect(await refusal(provider.provide("0x1", "0x2"))).toMatch(/mainnet/);
    expect(methods.some((m) => SENDING.test(m))).toBe(false);
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
