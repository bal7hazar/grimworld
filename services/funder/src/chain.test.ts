import { Account, Signer, ec, hash, num } from "starknet";
import { afterEach, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import { FeeRefused, NetworkRefused, NotSent, createFundingChain, feeBound } from "./chain.ts";
import { chainIdOf } from "./config.ts";
import { Secret } from "./secret.ts";

// AC-3: mainnet and any network the configuration does not name are refused before anything is
// signed. Offline: every request goes through a fake `fetch`, and spies on the library's signer
// and on `Account` show directly that no refused path reaches a signature or an execution.

const FUNDER = "0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691";
const KEY = "0x71d7bb07b9a64f6f78ac4c816aff4da9";
const CLASS = "0x05b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564";
const SN_SEPOLIA = "0x534e5f5345504f4c4941";
const SN_MAIN = "0x534e5f4d41494e";
const URL = "http://127.0.0.1:5050";

interface Node {
  chainIds: (string | undefined)[];
  /** The answer to `starknet_addInvokeTransaction`: an id, or an error code. */
  invoke?: { id: string } | { code: number };
}

function fakeFetch(node: Node) {
  const methods: string[] = [];
  const invoked: unknown[] = [];
  const fetch = (_url: unknown, init?: { body?: unknown }) => {
    const { id, method, params } = JSON.parse(String(init?.body)) as {
      id: number;
      method: string;
      params: { invoke_transaction?: unknown };
    };
    // Recorded when the request is made, before any answer.
    methods.push(method);
    if (method === "starknet_addInvokeTransaction") invoked.push(params.invoke_transaction);
    const answer = (result: unknown) =>
      new Response(JSON.stringify({ jsonrpc: "2.0", id, result }));
    const error = (code: number) =>
      new Response(JSON.stringify({ jsonrpc: "2.0", id, error: { code, message: "x" } }));
    switch (method) {
      case "starknet_chainId": {
        const next = node.chainIds.length > 1 ? node.chainIds.shift() : node.chainIds[0];
        return Promise.resolve(next === undefined ? error(-1) : answer(next));
      }
      case "starknet_specVersion":
        return Promise.resolve(answer("0.10.0"));
      case "starknet_addInvokeTransaction": {
        const reply = node.invoke ?? { code: -1 };
        return Promise.resolve(
          "id" in reply ? answer({ transaction_hash: reply.id }) : error(reply.code),
        );
      }
      default:
        return Promise.resolve(error(-32601));
    }
  };
  return { fetch: fetch as unknown as typeof globalThis.fetch, methods, invoked };
}

function chainOn(chainIds: (string | undefined)[], networks = ["SN_SEPOLIA"], maxFee = 10n ** 18n) {
  const node: Node = { chainIds };
  const { fetch, methods, invoked } = fakeFetch(node);
  const chain = createFundingChain({
    rpcUrl: URL,
    accountClass: CLASS,
    funderAddress: FUNDER,
    funderKey: new Secret(KEY),
    networks: networks.map((n) => chainIdOf(n)!),
    amount: 1n,
    maxFee,
    fetch,
  });
  return { chain, methods, invoked, node };
}

const BURNER = (() => {
  const publicKey = ec.starkCurve.getStarkKey("0x5eed");
  return {
    publicKey,
    address: num.toHex64(hash.calculateContractAddressFromHash(publicKey, CLASS, [publicKey], 0)),
  };
})();

let execute: MockInstance;
let estimate: MockInstance;
let signed: MockInstance;
let signs: MockInstance[];

beforeEach(() => {
  execute = vi.spyOn(Account.prototype, "execute");
  estimate = vi.spyOn(Account.prototype, "estimateInvokeFee");
  signed = vi.spyOn(Account.prototype, "getSignedTransaction");
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

function expectNothingSigned() {
  expect(execute).not.toHaveBeenCalled();
  expect(estimate).not.toHaveBeenCalled();
  expect(signed).not.toHaveBeenCalled();
  for (const sign of signs) expect(sign).not.toHaveBeenCalled();
}

async function refused(promise: Promise<unknown>): Promise<Error> {
  const error = await promise.then(
    () => undefined,
    (e: unknown) => e,
  );
  expect(error).toBeInstanceOf(Error);
  return error as Error;
}

const BOUNDS = (price: bigint) => ({
  l1_gas: { max_amount: 0n, max_price_per_unit: price },
  l2_gas: { max_amount: 1_000_000n, max_price_per_unit: price },
  l1_data_gas: { max_amount: 1_000n, max_price_per_unit: price },
});

/** A signed INVOKE v3 as the library returns it, for the nonce given. */
function invokeOf(nonce: bigint) {
  const bound = { max_amount: "0x10", max_price_per_unit: "0x1" };
  return {
    type: "INVOKE",
    sender_address: FUNDER,
    calldata: ["0x1", "0x2"],
    version: "0x3",
    signature: ["0x5", "0x6"],
    nonce: num.toHex(nonce),
    tip: "0x0",
    paymaster_data: [],
    account_deployment_data: [],
    nonce_data_availability_mode: "L1",
    fee_data_availability_mode: "L1",
    resource_bounds: { l1_gas: bound, l2_gas: bound, l1_data_gas: bound },
  };
}

describe("the network is checked before anything is signed", () => {
  it("refuses mainnet, even when it answers as the only network configured", async () => {
    const { chain, methods } = chainOn([SN_MAIN]);
    const error = await refused(chain.prepare(BURNER.publicKey, BURNER.address, 7n));
    expect(error).toBeInstanceOf(NetworkRefused);
    expect(error.message).toMatch(/mainnet/);
    expect(methods).toEqual(["starknet_chainId"]);
    expectNothingSigned();
  });

  it("refuses a network the configuration does not name", async () => {
    const { chain, methods } = chainOn([SN_SEPOLIA], ["SN_INTEGRATION"]);
    const error = await refused(chain.prepare(BURNER.publicKey, BURNER.address, 7n));
    expect(error).toBeInstanceOf(NetworkRefused);
    expect(error.message).toMatch(/not configured/);
    expect(methods).toEqual(["starknet_chainId"]);
    expectNothingSigned();
  });

  it("refuses a node that does not tell its chain id", async () => {
    const { chain } = chainOn([undefined]);
    expect(await refused(chain.prepare(BURNER.publicKey, BURNER.address, 7n))).toBeInstanceOf(
      NetworkRefused,
    );
    expectNothingSigned();
  });

  it("asks at every funding: a node that turns into mainnet is refused the next time", async () => {
    const { chain, methods } = chainOn([SN_SEPOLIA, SN_MAIN]);
    estimate.mockRejectedValue(new Error("stopped by the test"));
    const stopped = await refused(chain.prepare(BURNER.publicKey, BURNER.address, 7n));
    expect((stopped.cause as Error).message).toBe("stopped by the test");
    expect(estimate).toHaveBeenCalledTimes(1);
    estimate.mockClear();
    expect(await refused(chain.prepare(BURNER.publicKey, BURNER.address, 7n))).toBeInstanceOf(
      NetworkRefused,
    );
    expect(methods.filter((m) => m === "starknet_chainId")).toHaveLength(2);
    expectNothingSigned();
  });

  it("signs for the chain id it checked, with the funding key, deployment and funding together, and hands nothing", async () => {
    const { chain, methods } = chainOn([SN_SEPOLIA]);
    estimate.mockResolvedValue({ resourceBounds: BOUNDS(1n), overall_fee: 1n, unit: "FRI" });
    const used: {
      chainId?: string;
      publicKey?: string;
      calls?: unknown[];
      details?: { tip?: unknown; nonce?: unknown; resourceBounds?: unknown };
    } = {};
    signed.mockImplementation(async function (
      this: Account,
      calls: unknown,
      details?: { tip?: unknown; nonce?: unknown },
    ) {
      used.chainId = await this.provider.getChainId();
      used.publicKey = await this.signer.getPubKey();
      used.calls = calls as unknown[];
      used.details = details;
      return invokeOf(7n);
    });
    const result = await chain.prepare(BURNER.publicKey, BURNER.address, 7n);
    expect(BigInt(used.chainId!)).toBe(BigInt(SN_SEPOLIA));
    // The signer's chain id is the one checked, not asked again of the node.
    expect(methods.filter((m) => m === "starknet_chainId")).toHaveLength(1);
    expect(BigInt(used.publicKey!)).toBe(BigInt(ec.starkCurve.getStarkKey(KEY)));
    expect(used.calls).toHaveLength(2);
    expect((used.calls![1] as { entrypoint: string }).entrypoint).toBe("transfer");
    // The nonce held by the service, for the estimate and the signature; the bounds estimated.
    expect(used.details).toMatchObject({ tip: 0n, nonce: 7n, resourceBounds: BOUNDS(1n) });
    expect(estimate.mock.calls[0]![1]).toMatchObject({ nonce: 7n });
    // Fix loop 2: nothing was handed to the node, and the id is known before it is.
    expect(execute).not.toHaveBeenCalled();
    expect(methods).not.toContain("starknet_addInvokeTransaction");
    expect(result.transaction).toMatch(/^0x[0-9a-f]+$/);
    expect(JSON.parse(result.payload)).toMatchObject({
      chainId: SN_SEPOLIA,
      transaction: result.transaction,
      invoke: { nonce: "0x7" },
    });
    // No key in what the service keeps.
    expect(result.payload.toLowerCase()).not.toContain(KEY.slice(2));
  });

  it("every failure of the preparation is NotSent", async () => {
    const { chain } = chainOn([SN_SEPOLIA]);
    estimate.mockRejectedValueOnce(new Error("estimate failed"));
    expect(await refused(chain.prepare(BURNER.publicKey, BURNER.address, 7n))).toBeInstanceOf(
      NotSent,
    );
    estimate.mockResolvedValue({ resourceBounds: BOUNDS(1n), overall_fee: 1n, unit: "FRI" });
    signed.mockRejectedValueOnce(new Error("signing failed"));
    expect(await refused(chain.prepare(BURNER.publicKey, BURNER.address, 7n))).toBeInstanceOf(
      NotSent,
    );
    // A signature for another nonce than the one held is never kept.
    signed.mockResolvedValueOnce(invokeOf(8n));
    const other = await refused(chain.prepare(BURNER.publicKey, BURNER.address, 7n));
    expect(other).toBeInstanceOf(NotSent);
    expect(other.message).toMatch(/nonce/);
  });

  it("refuses a funding whose fee bound is above the cap, before signing", async () => {
    const { chain } = chainOn([SN_SEPOLIA], ["SN_SEPOLIA"], 1_000_000n);
    estimate.mockResolvedValue({ resourceBounds: BOUNDS(2n), overall_fee: 1n, unit: "FRI" });
    expect(await refused(chain.prepare(BURNER.publicKey, BURNER.address, 7n))).toBeInstanceOf(
      FeeRefused,
    );
    expect(signed).not.toHaveBeenCalled();
  });

  it("refuses an address that is not the key's before signing", async () => {
    const { chain } = chainOn([SN_SEPOLIA]);
    const error = await refused(chain.prepare(BURNER.publicKey, "0x1234", 7n));
    expect(error).toBeInstanceOf(NotSent);
    expect(error.message).toMatch(/differs/);
    expectNothingSigned();
  });
});

// Fix loop 2: handing a signed execution to the node.
describe("a signed execution handed to the node", () => {
  async function prepared(chainIds: string[] = [SN_SEPOLIA]) {
    const on = chainOn(chainIds);
    estimate.mockResolvedValue({ resourceBounds: BOUNDS(1n), overall_fee: 1n, unit: "FRI" });
    signed.mockResolvedValue(invokeOf(7n));
    const result = await on.chain.prepare(BURNER.publicKey, BURNER.address, 7n);
    return { ...on, ...result };
  }

  it("is requested during the call itself, before it returns", async () => {
    const { chain, methods, invoked, payload, transaction, node } = await prepared();
    node.invoke = { id: transaction };
    const handed = chain.submit(payload);
    // No await yet: the request has already been made.
    expect(methods.at(-1)).toBe("starknet_addInvokeTransaction");
    expect(invoked).toEqual([invokeOf(7n)]);
    expect(await handed).toBe(transaction);
  });

  it("is refused when the node's id differs from the one computed", async () => {
    const { chain, payload, node } = await prepared();
    node.invoke = { id: "0x1234" };
    expect((await refused(chain.submit(payload))).message).toMatch(/differs/);
  });

  it("the same execution handed again: the node's duplicate answer is its id", async () => {
    const { chain, payload, transaction, node } = await prepared();
    node.invoke = { code: 59 };
    expect(await chain.submit(payload)).toBe(transaction);
    node.invoke = { code: 55 };
    expect((await refused(chain.submit(payload))).message).toMatch(/refused/);
  });

  it("is handed again only while the node is on the network it was signed for", async () => {
    const { chain, payload } = await prepared([SN_SEPOLIA, SN_SEPOLIA, SN_MAIN]);
    await chain.verify(payload);
    expect(await refused(chain.verify(payload))).toBeInstanceOf(NetworkRefused);
  });
});

describe("a public key", () => {
  it("gives the address the client derives", () => {
    const { chain } = chainOn([SN_SEPOLIA]);
    expect(chain.addressOf(BURNER.publicKey)).toEqual({
      publicKey: num.toHex64(BURNER.publicKey),
      address: BURNER.address,
    });
  });

  it.each([
    "",
    "5eed",
    "0x",
    "0x0",
    `0x${(2n ** 251n).toString(16)}`,
    "0x5",
    `0x${"f".repeat(65)}`,
  ])("is refused when it is not a key on the curve: %s", (input) => {
    const { chain } = chainOn([SN_SEPOLIA]);
    expect(chain.addressOf(input)).toBeUndefined();
  });
});

describe("the fee bound", () => {
  it("is the sum of each resource's most amount times its most price", () => {
    expect(feeBound(BOUNDS(3n))).toBe(3n * 1_001_000n);
  });
});
