import { Account, Signer, ec, hash, num } from "starknet";
import { afterEach, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import { FeeRefused, NetworkRefused, createFundingChain, feeBound } from "./chain.ts";
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

function fakeFetch(chainIds: (string | undefined)[]) {
  const methods: string[] = [];
  const fetch = async (_url: unknown, init?: { body?: unknown }) => {
    const { id, method } = JSON.parse(String(init?.body)) as { id: number; method: string };
    methods.push(method);
    const answer = (result: unknown) =>
      new Response(JSON.stringify({ jsonrpc: "2.0", id, result }));
    switch (method) {
      case "starknet_chainId": {
        const next = chainIds.length > 1 ? chainIds.shift() : chainIds[0];
        return next === undefined
          ? new Response(JSON.stringify({ jsonrpc: "2.0", id, error: { code: -1, message: "x" } }))
          : answer(next);
      }
      case "starknet_specVersion":
        return answer("0.10.0");
      default:
        return new Response(
          JSON.stringify({ jsonrpc: "2.0", id, error: { code: -32601, message: "no" } }),
        );
    }
  };
  return { fetch: fetch as unknown as typeof globalThis.fetch, methods };
}

function chainOn(chainIds: (string | undefined)[], networks = ["SN_SEPOLIA"], maxFee = 10n ** 18n) {
  const { fetch, methods } = fakeFetch(chainIds);
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
  return { chain, methods };
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
let signs: MockInstance[];

beforeEach(() => {
  execute = vi.spyOn(Account.prototype, "execute");
  estimate = vi.spyOn(Account.prototype, "estimateInvokeFee");
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

describe("the network is checked before anything is signed", () => {
  it("refuses mainnet, even when it answers as the only network configured", async () => {
    const { chain, methods } = chainOn([SN_MAIN]);
    const error = await refused(chain.fund(BURNER.publicKey, BURNER.address));
    expect(error).toBeInstanceOf(NetworkRefused);
    expect(error.message).toMatch(/mainnet/);
    expect(methods).toEqual(["starknet_chainId"]);
    expectNothingSigned();
  });

  it("refuses a network the configuration does not name", async () => {
    const { chain, methods } = chainOn([SN_SEPOLIA], ["SN_INTEGRATION"]);
    const error = await refused(chain.fund(BURNER.publicKey, BURNER.address));
    expect(error).toBeInstanceOf(NetworkRefused);
    expect(error.message).toMatch(/not configured/);
    expect(methods).toEqual(["starknet_chainId"]);
    expectNothingSigned();
  });

  it("refuses a node that does not tell its chain id", async () => {
    const { chain } = chainOn([undefined]);
    expect(await refused(chain.fund(BURNER.publicKey, BURNER.address))).toBeInstanceOf(
      NetworkRefused,
    );
    expectNothingSigned();
  });

  it("asks at every funding: a node that turns into mainnet is refused the next time", async () => {
    const { chain, methods } = chainOn([SN_SEPOLIA, SN_MAIN]);
    estimate.mockRejectedValue(new Error("stopped by the test"));
    expect((await refused(chain.fund(BURNER.publicKey, BURNER.address))).message).toBe(
      "stopped by the test",
    );
    expect(estimate).toHaveBeenCalledTimes(1);
    estimate.mockClear();
    expect(await refused(chain.fund(BURNER.publicKey, BURNER.address))).toBeInstanceOf(
      NetworkRefused,
    );
    expect(methods.filter((m) => m === "starknet_chainId")).toHaveLength(2);
    expectNothingSigned();
  });

  it("signs for the chain id it checked, with the funding key, and sends deployment and funding together", async () => {
    const { chain, methods } = chainOn([SN_SEPOLIA]);
    estimate.mockResolvedValue({ resourceBounds: BOUNDS(1n), overall_fee: 1n, unit: "FRI" });
    const used: { chainId?: string; publicKey?: string; calls?: unknown[]; tip?: unknown } = {};
    execute.mockImplementation(async function (
      this: Account,
      calls: unknown,
      details?: { tip?: unknown },
    ) {
      used.chainId = await this.provider.getChainId();
      used.publicKey = await this.signer.getPubKey();
      used.calls = calls as unknown[];
      used.tip = details?.tip;
      return { transaction_hash: "0xabc" };
    });
    expect(await chain.fund(BURNER.publicKey, BURNER.address)).toBe("0xabc");
    expect(BigInt(used.chainId!)).toBe(BigInt(SN_SEPOLIA));
    // The signer's chain id is the one checked, not asked again of the node.
    expect(methods.filter((m) => m === "starknet_chainId")).toHaveLength(1);
    expect(BigInt(used.publicKey!)).toBe(BigInt(ec.starkCurve.getStarkKey(KEY)));
    expect(used.calls).toHaveLength(2);
    expect((used.calls![1] as { entrypoint: string }).entrypoint).toBe("transfer");
    expect(used.tip).toBe(0n);
  });

  it("refuses a funding whose fee bound is above the cap, before sending", async () => {
    const { chain } = chainOn([SN_SEPOLIA], ["SN_SEPOLIA"], 1_000_000n);
    estimate.mockResolvedValue({ resourceBounds: BOUNDS(2n), overall_fee: 1n, unit: "FRI" });
    expect(await refused(chain.fund(BURNER.publicKey, BURNER.address))).toBeInstanceOf(FeeRefused);
    expect(execute).not.toHaveBeenCalled();
  });

  it("refuses an address that is not the key's before signing", async () => {
    const { chain } = chainOn([SN_SEPOLIA]);
    expect((await refused(chain.fund(BURNER.publicKey, "0x1234"))).message).toMatch(/differs/);
    expectNothingSigned();
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
