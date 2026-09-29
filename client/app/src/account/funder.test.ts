import { describe, expect, it } from "vitest";
import { createFunder, createServiceFunder } from "./funder";
import { LOCAL_ACCOUNT_CLASS } from "./starknet";
import { AccountError } from "./types";

// FND-08: the client's funder on a public network asks the funding service, holds no key, and
// reports every failure with the module's neutral errors. Offline: a fake `fetch` answers.

const URL = "https://funding.example/v1/burners";
const KEY = "0x41139a5a644069a945359cab5329f35b2024d76190f8b3724572156d2da69c3";
const ADDRESS = "0x0123";

/** Words of the chain that must never reach a player (design/11, D-100). */
const CHAIN_WORDS =
  /transaction|fee|wallet|sign|token|chain|block|gas|strk|starknet|account|deploy|fund|key/i;

function fakeFetch(answers: { status: number; body?: unknown }[]) {
  const requests: { url: string; init: RequestInit }[] = [];
  const fetch = async (url: unknown, init?: RequestInit) => {
    requests.push({ url: String(url), init: init ?? {} });
    const next = answers.length > 1 ? answers.shift()! : answers[0]!;
    return new Response(next.body === undefined ? "oops" : JSON.stringify(next.body), {
      status: next.status,
    });
  };
  return { fetch: fetch as unknown as typeof globalThis.fetch, requests };
}

async function failure(promise: Promise<unknown>): Promise<AccountError> {
  const error = await promise.then(
    () => undefined,
    (e: unknown) => e,
  );
  expect(error).toBeInstanceOf(AccountError);
  expect((error as Error).message).not.toMatch(CHAIN_WORDS);
  return error as AccountError;
}

describe("the service funder", () => {
  it("sends the public key and the address, nothing else, and resolves once funded", async () => {
    const { fetch, requests } = fakeFetch([
      { status: 200, body: { address: "0x123", status: "succeeded", repeated: false } },
    ]);
    await createServiceFunder({ url: URL, fetch }).provide(KEY, ADDRESS);
    expect(requests).toHaveLength(1);
    expect(requests[0]!.url).toBe(URL);
    expect(requests[0]!.init.method).toBe("POST");
    expect(JSON.parse(String(requests[0]!.init.body))).toEqual({
      publicKey: KEY,
      address: ADDRESS,
    });
  });

  it("asks again while the funding is pending, then resolves", async () => {
    const { fetch, requests } = fakeFetch([
      { status: 202, body: { address: ADDRESS, status: "pending" } },
      { status: 202, body: { address: ADDRESS, status: "pending" } },
      { status: 200, body: { address: ADDRESS, status: "succeeded", repeated: true } },
    ]);
    await createServiceFunder({ url: URL, fetch, retryMs: 1 }).provide(KEY, ADDRESS);
    expect(requests).toHaveLength(3);
  });

  it("gives up, unavailable, when it stays pending", async () => {
    const { fetch, requests } = fakeFetch([
      { status: 202, body: { address: ADDRESS, status: "pending" } },
    ]);
    const funder = createServiceFunder({ url: URL, fetch, retryMs: 1, attempts: 3 });
    expect((await failure(funder.provide(KEY, ADDRESS))).code).toBe("unavailable");
    expect(requests).toHaveLength(3);
  });

  it.each([
    [400, { error: "invalid" }, "invalid"],
    [403, { error: "refused" }, "refused"],
    [429, { error: "limited" }, "unavailable"],
    [503, { error: "exhausted" }, "unavailable"],
    [503, { error: "unavailable" }, "unavailable"],
    [502, { error: "failed", address: ADDRESS, transaction: "0x1" }, "unavailable"],
    [500, undefined, "unavailable"],
    [200, { error: "odd" }, "unavailable"],
  ])("answers %i %j as %s, in neutral words", async (status, body, code) => {
    const { fetch } = fakeFetch([{ status, body }]);
    const error = await failure(createServiceFunder({ url: URL, fetch }).provide(KEY, ADDRESS));
    expect(error.code).toBe(code);
  });

  it("an unreachable service is unavailable", async () => {
    const fetch = (async () => {
      throw new TypeError("fetch failed");
    }) as unknown as typeof globalThis.fetch;
    const error = await failure(createServiceFunder({ url: URL, fetch }).provide(KEY, ADDRESS));
    expect(error.code).toBe("unavailable");
  });

  it("refuses an account funded at another address than the key's", async () => {
    const { fetch } = fakeFetch([{ status: 200, body: { address: "0x999", status: "succeeded" } }]);
    const error = await failure(createServiceFunder({ url: URL, fetch }).provide(KEY, ADDRESS));
    expect(error.code).toBe("refused");
  });
});

describe("the funder is chosen by configuration", () => {
  it("the service, over its URL", async () => {
    const { fetch, requests } = fakeFetch([
      { status: 200, body: { address: ADDRESS, status: "succeeded" } },
    ]);
    await createFunder({ kind: "service", url: URL, fetch }).provide(KEY, ADDRESS);
    expect(requests).toHaveLength(1);
  });

  it("the local node's, which refuses anything but the local node", async () => {
    const { fetch, requests } = fakeFetch([{ status: 200, body: {} }]);
    const funder = createFunder({
      kind: "node",
      nodeUrl: "https://starknet-sepolia.example",
      accountClass: LOCAL_ACCOUNT_CLASS,
      funderAddress: "0x1",
      funderKey: "0x2",
      amount: 1n,
      fetch,
    });
    await expect(funder.provide(KEY, ADDRESS)).rejects.toThrow(/not on this machine/);
    expect(requests).toEqual([]);
  });
});
