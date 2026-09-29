// Serving, minimal (IDX-01a): `GET /head` and `GET /stats`. Queries and subscriptions are IDX-01b's.
// R1: in the states `loading`, `rewinding` and `halted` every answer is 503 with the state (and the
// reason), never rows. R2: every answer carries `head {number, hash, commitments}`, the served
// block it is read at (null while none is served).
import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";
import type { Header } from "./chain.ts";
import type { Indexer } from "./indexer.ts";

export const headOf = (header: Header | null | undefined) =>
  header
    ? {
        number: header.number,
        hash: header.hash,
        commitments: header.commitments,
      }
    : null;

export type Answer = { code: number; body: Record<string, unknown> };

const started = Date.now();

/** The answer to a GET of `path` (the HTTP server's, without the socket: unit-tested). */
export function answer(indexer: Indexer, path: string): Answer {
  if (path !== "/head" && path !== "/stats") {
    return { code: 404, body: { error: "not found" } };
  }
  const head = headOf(indexer.served);
  const process_ = {
    blocksApplied: indexer.blocksApplied,
    eventsApplied: indexer.eventsApplied,
    rewinds: indexer.rewinds,
    rpcCalls: { ...indexer.chain.calls },
    rssMB: Math.round(process.memoryUsage().rss / 2 ** 20),
    maxRssMB: Math.round(process.resourceUsage().maxRSS / 1024),
    uptimeMs: Date.now() - started,
  };
  if (indexer.status !== "ok" || !indexer.served) {
    const body: Record<string, unknown> = {
      status: indexer.status,
      reason: indexer.reason || undefined,
      head,
    };
    // The process's own figures, never rows.
    if (path === "/stats") Object.assign(body, process_);
    return { code: 503, body };
  }
  const served = indexer.served;
  const behind = Math.max(0, indexer.chainTip - served.number);
  if (path === "/head")
    return { code: 200, body: { status: "ok", head, behind } };
  return {
    code: 200,
    body: {
      status: "ok",
      head,
      behind,
      stored: headOf(indexer.store.tip()),
      lowest: indexer.store.lowest()?.number ?? null,
      tables: indexer.store.countsAt(served.number),
      versions: indexer.store.rows(),
      ...process_,
    },
  };
}

export function serve(indexer: Indexer): Server {
  return createServer((request: IncomingMessage, response: ServerResponse) => {
    const url = new URL(request.url ?? "/", "http://indexer");
    const { code, body } =
      request.method === "GET"
        ? answer(indexer, url.pathname)
        : { code: 405, body: { error: "GET only" } };
    response.writeHead(code, {
      "content-type": "application/json",
      "cache-control": "no-store",
    });
    response.end(JSON.stringify(body));
  });
}
