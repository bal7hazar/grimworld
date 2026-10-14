import { describe, expect, it } from "vitest";
import { CreditFailed, type CreditRequest, createCredit, httpCreditRequest } from "./credit";
import { ChainRefused } from "./network";

/** The endpoint's answers, by method; every request is kept. */
function endpoint(answers: Partial<Record<"GET" | "POST", { status: number; body: unknown }>>) {
  const requests: [string, string | undefined][] = [];
  const request: CreditRequest = async (method, body) => {
    requests.push([method, body]);
    const answer = answers[method] ?? { status: 404, body: "" };
    const text = typeof answer.body === "string" ? answer.body : JSON.stringify(answer.body);
    return { status: answer.status, body: text };
  };
  return { request, requests };
}

describe("the burner's credit (CLI-11d3)", () => {
  it("posts the adventurer's id and nothing else", async () => {
    const { request, requests } = endpoint({ POST: { status: 200, body: { gold: 260 } } });
    await createCredit(request).credit(2);
    expect(requests).toEqual([["POST", '{"adventurer":2}']]);
  });

  it("a 409 is the unusable devnet's refusal; any other failure is CreditFailed with its line", async () => {
    const unusable = endpoint({
      POST: { status: 409, body: { error: "devnet left mid-credit: redeploy" } },
    });
    await expect(createCredit(unusable.request).credit(2)).rejects.toEqual(
      new ChainRefused("devnet left mid-credit: redeploy"),
    );
    const failed = endpoint({ POST: { status: 502, body: { error: "devnet_deploy: refused" } } });
    await expect(createCredit(failed.request).credit(2)).rejects.toEqual(
      new CreditFailed("devnet_deploy: refused"),
    );
    // The site's index.html, or no endpoint at all
    const site = endpoint({
      POST: { status: 200, body: "<html>" },
      GET: { status: 200, body: "<html>" },
    });
    await expect(createCredit(endpoint({}).request).credit(2)).rejects.toEqual(
      new CreditFailed("no credit endpoint"),
    );
    await expect(createCredit(site.request).status()).rejects.toEqual(
      new CreditFailed("no credit endpoint"),
    );
  });

  it("reads the state, and refuses once the devnet is unusable", async () => {
    const idle = endpoint({ GET: { status: 200, body: { state: "running", credits: 3 } } });
    expect(await createCredit(idle.request).status()).toEqual({ state: "running", credits: 3 });
    await expect(createCredit(idle.request).assertUsable()).resolves.toBeUndefined();
    const left = endpoint({ GET: { status: 200, body: { state: "unusable", credits: 1 } } });
    await expect(createCredit(left.request).assertUsable()).rejects.toEqual(
      new ChainRefused("devnet left mid-credit: redeploy"),
    );
    const odd = endpoint({ GET: { status: 200, body: { state: "busy", credits: 1 } } });
    await expect(createCredit(odd.request).status()).rejects.toBeInstanceOf(CreditFailed);
  });

  it("sends JSON to the development server's /devnet/credit", async () => {
    const seen: [string, RequestInit | undefined][] = [];
    const fetchImpl = (async (url: string, init?: RequestInit) => {
      seen.push([url, init]);
      return new Response('{"state":"idle","credits":0}');
    }) as unknown as typeof fetch;
    const request = httpCreditRequest(fetchImpl);
    expect(await request("GET")).toEqual({ status: 200, body: '{"state":"idle","credits":0}' });
    await request("POST", '{"adventurer":2}');
    expect(seen.map(([url, init]) => [url, init?.method, init?.body])).toEqual([
      ["/devnet/credit", "GET", undefined],
      ["/devnet/credit", "POST", '{"adventurer":2}'],
    ]);
    expect((seen[1]![1]!.headers as Record<string, string>)["content-type"]).toBe(
      "application/json",
    );
  });
});
