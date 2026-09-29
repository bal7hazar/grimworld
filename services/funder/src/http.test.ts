import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";
import { PATH, clientOf, createFunderServer, createLogger } from "./http.ts";
import { Secret } from "./secret.ts";
import type { FundingService, Outcome } from "./service.ts";

const servers: { close(): void }[] = [];

afterEach(() => {
  for (const server of servers.splice(0)) server.close();
});

async function serve(outcome: Outcome, trustProxy = false) {
  const calls: { request: unknown; client: string }[] = [];
  const logged: string[] = [];
  const service: FundingService = {
    async fund(request, client) {
      calls.push({ request, client });
      return outcome;
    },
  };
  const server = createFunderServer({
    service,
    trustProxy,
    origin: "https://play.example",
    log: (event, fields) => logged.push(JSON.stringify({ event, ...fields })),
  });
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return { base, calls, logged };
}

const PROVIDED: Outcome = {
  kind: "provided",
  address: "0xa1",
  status: "succeeded",
  transaction: "0x71",
  repeated: false,
};

function post(url: string, body: string, headers: Record<string, string> = {}) {
  return fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body,
  });
}

describe("the endpoint", () => {
  it.each<[Outcome, number, object]>([
    [PROVIDED, 200, { address: "0xa1", status: "succeeded", transaction: "0x71", repeated: false }],
    [
      { ...PROVIDED, status: "pending", repeated: true } as Outcome,
      202,
      { address: "0xa1", status: "pending", transaction: "0x71", repeated: true },
    ],
    [{ kind: "invalid" }, 400, { error: "invalid" }],
    [{ kind: "refused" }, 403, { error: "refused" }],
    [{ kind: "limited" }, 429, { error: "limited" }],
    [{ kind: "exhausted" }, 503, { error: "exhausted" }],
    [{ kind: "unavailable" }, 503, { error: "unavailable" }],
    [
      { kind: "failed", address: "0xa1", transaction: "0x71" },
      502,
      { error: "failed", address: "0xa1", transaction: "0x71" },
    ],
  ])("answers %j with %i", async (outcome, code, body) => {
    const { base, calls } = await serve(outcome);
    const response = await post(`${base}${PATH}`, '{"publicKey":"0x1"}');
    expect(response.status).toBe(code);
    expect(await response.json()).toEqual(body);
    expect(response.headers.get("access-control-allow-origin")).toBe("https://play.example");
    expect(calls).toEqual([{ request: { publicKey: "0x1" }, client: "127.0.0.1" }]);
  });

  it("refuses other paths, other methods, bodies that are not JSON or too long", async () => {
    const { base, calls } = await serve(PROVIDED);
    expect((await post(`${base}/v1/other`, "{}")).status).toBe(404);
    expect((await fetch(`${base}${PATH}`)).status).toBe(405);
    expect((await post(`${base}${PATH}`, "not json")).status).toBe(400);
    expect((await post(`${base}${PATH}`, JSON.stringify({ pad: "x".repeat(2000) }))).status).toBe(
      413,
    );
    expect(calls).toEqual([]);
  });

  it("answers the browser's preflight", async () => {
    const { base } = await serve(PROVIDED);
    const response = await fetch(`${base}${PATH}`, { method: "OPTIONS" });
    expect(response.status).toBe(204);
    expect(response.headers.get("access-control-allow-methods")).toBe("POST, OPTIONS");
  });

  it("ignores X-Forwarded-For unless told to trust a proxy, then reads its last hop", async () => {
    const plain = await serve(PROVIDED);
    await post(`${plain.base}${PATH}`, "{}", { "x-forwarded-for": "1.2.3.4" });
    expect(plain.calls[0]!.client).toBe("127.0.0.1");
    const proxied = await serve(PROVIDED, true);
    await post(`${proxied.base}${PATH}`, "{}", { "x-forwarded-for": "9.9.9.9, 1.2.3.4" });
    expect(proxied.calls[0]!.client).toBe("1.2.3.4");
  });
});

describe("the client of a request", () => {
  it.each([
    ["1.2.3.4", "1.2.3.4"],
    ["::ffff:1.2.3.4", "1.2.3.4"],
    ["2001:db8:1:2:aaaa:bbbb:cccc:dddd", "2001:db8:1:2::/64"],
    ["2001:db8:1:2::1", "2001:db8:1:2::/64"],
    ["2001:db8::1", "2001:db8:0:0::/64"],
    ["::1", "0:0:0:0::/64"],
  ])("%s is %s", (address, client) => {
    expect(clientOf(address)).toBe(client);
  });
});

describe("the log", () => {
  it("removes every form of the key from a line, whatever put it there", () => {
    const key = "0x71d7bb07b9a64f6f78ac4c816aff4da9";
    const lines: string[] = [];
    const log = createLogger((line) => lines.push(line), new Secret(key).forms());
    log("test", {
      a: key,
      b: key.slice(2).toUpperCase(),
      c: BigInt(key).toString(10),
      d: `0x${key.slice(2).padStart(64, "0")}`,
    });
    expect(lines).toHaveLength(1);
    const line = lines[0]!.toLowerCase();
    expect(line).not.toContain(key.slice(2));
    expect(line).not.toContain(BigInt(key).toString(10));
    expect(line.split("[secret]").length - 1).toBe(4);
  });
});
