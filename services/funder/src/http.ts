import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { FundingService, Outcome } from "./service.ts";

/**
 * The service's one endpoint, `POST /v1/burners`, body `{ "publicKey": "0x…", "address": "0x…" }`
 * (the address is optional: when given, it must be the key's). The answer:
 * - 200 `{ address, status: "succeeded", transaction?, repeated }`: the account can send;
 * - 202 `{ address, status: "pending", transaction, repeated }`: sent, not settled yet; ask again;
 * - 400 `invalid`, 403 `refused` (the network), 429 `limited` (this client's rate),
 *   503 `exhausted` (the day's budget) or `unavailable`, 502 `failed` (the funding reverted).
 */

export const PATH = "/v1/burners";
/** A request's body is a key and an address: a kilobyte is plenty. */
const MAX_BODY = 1024;

export interface ServerOptions {
  service: FundingService;
  /** Read the client from the last `X-Forwarded-For` hop (behind a proxy of our own only). */
  trustProxy: boolean;
  /** `Access-Control-Allow-Origin`: the game's web origin. */
  origin: string;
  log: (event: string, fields: Record<string, string>) => void;
}

/**
 * Who a request comes from, for the client rate: an IPv4 address, or an IPv6 address's /64 (one
 * subscriber usually holds a whole /64, and would otherwise have 2^64 clients).
 */
export function clientOf(address: string): string {
  if (address.startsWith("::ffff:") && address.includes(".")) return address.slice(7);
  if (!address.includes(":")) return address;
  const [head = "", tail = ""] = address.split("::");
  const front = head ? head.split(":") : [];
  const back = tail ? tail.split(":") : [];
  const groups = address.includes("::")
    ? [...front, ...Array<string>(Math.max(0, 8 - front.length - back.length)).fill("0"), ...back]
    : front;
  return `${groups
    .slice(0, 4)
    .map((group) => (Number.parseInt(group, 16) || 0).toString(16))
    .join(":")}::/64`;
}

function answer(outcome: Outcome): { code: number; body: object } {
  switch (outcome.kind) {
    case "provided": {
      const { address, status, transaction, repeated } = outcome;
      return {
        code: status === "succeeded" ? 200 : 202,
        body: { address, status, ...(transaction ? { transaction } : {}), repeated },
      };
    }
    case "failed":
      return {
        code: 502,
        body: { error: "failed", address: outcome.address, transaction: outcome.transaction },
      };
    case "invalid":
      return { code: 400, body: { error: "invalid" } };
    case "refused":
      return { code: 403, body: { error: "refused" } };
    case "limited":
      return { code: 429, body: { error: "limited" } };
    case "exhausted":
      return { code: 503, body: { error: "exhausted" } };
    case "unavailable":
      return { code: 503, body: { error: "unavailable" } };
  }
}

async function readBody(request: IncomingMessage): Promise<string | undefined> {
  let size = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of request as AsyncIterable<Buffer>) {
    size += chunk.length;
    if (size > MAX_BODY) return undefined;
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

export function createFunderServer(options: ServerOptions): Server {
  const { service, log } = options;

  function reply(response: ServerResponse, code: number, body?: object) {
    response.writeHead(code, {
      "access-control-allow-origin": options.origin,
      "access-control-allow-methods": "POST, OPTIONS",
      "access-control-allow-headers": "content-type",
      "cache-control": "no-store",
      ...(body ? { "content-type": "application/json" } : {}),
    });
    response.end(body ? JSON.stringify(body) : undefined);
  }

  return createServer((request, response) => {
    void (async () => {
      const path = (request.url ?? "").split("?")[0];
      if (path !== PATH) return reply(response, 404, { error: "not-found" });
      if (request.method === "OPTIONS") return reply(response, 204);
      if (request.method !== "POST") return reply(response, 405, { error: "method" });
      const text = await readBody(request);
      if (text === undefined) return reply(response, 413, { error: "invalid" });
      let parsed: unknown;
      try {
        parsed = JSON.parse(text);
      } catch {
        return reply(response, 400, { error: "invalid" });
      }
      const forwarded = options.trustProxy
        ? String(request.headers["x-forwarded-for"] ?? "")
            .split(",")
            .pop()
            ?.trim()
        : undefined;
      const client = clientOf(forwarded || request.socket.remoteAddress || "unknown");
      const { code, body } = answer(await service.fund(parsed, client));
      log("answered", { code: String(code) });
      reply(response, code, body);
    })().catch((error: unknown) => {
      log("error", { reason: error instanceof Error ? error.name : "unknown" });
      if (!response.headersSent) reply(response, 500, { error: "unavailable" });
      else response.destroy();
    });
  });
}

/**
 * A line of JSON per event, with every form of each secret removed from the line: the events
 * carry only public values, and this is the second lock on the door.
 */
export function createLogger(
  write: (line: string) => void,
  secrets: readonly string[],
): (event: string, fields: Record<string, string>) => void {
  return (event, fields) => {
    let line = JSON.stringify({ at: new Date().toISOString(), event, ...fields });
    for (const secret of secrets) line = line.split(secret).join("[secret]");
    write(line);
  };
}
