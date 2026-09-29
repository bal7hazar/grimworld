// Serving, minimal (IDX-01a): `GET /head` and `GET /stats`. Queries and subscriptions are IDX-01b's.
// R1: in the states `loading`, `rewinding` and `halted` every answer is 503 with the state (and the
// reason), never rows. R2: every answer, errors included, carries `head {number, hash,
// commitments}`, the served block it is read at (null while none is served). Nothing a client sends
// stops the process: a target that is not a path is 400, an exception while answering is 500.
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

/** An error answer: the error, the state and the served head. */
function refusal(indexer: Indexer, code: number, error: string): Answer {
  return {
    code,
    body: { error, status: indexer.status, head: headOf(indexer.served) },
  };
}

/** The answer to a GET of `path` (the HTTP server's, without the socket: unit-tested). */
export function answer(indexer: Indexer, path: string): Answer {
  if (path !== "/head" && path !== "/stats") {
    return refusal(indexer, 404, "not found");
  }
  const head = headOf(indexer.served);
  const process_ = {
    blocksApplied: indexer.blocksApplied,
    eventsApplied: indexer.eventsApplied,
    rewindCount: indexer.rewindCount,
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

/** The answer to a request: 405 unless GET, 400 for a target that is not a path, 500 on a throw. */
export function respond(
  indexer: Indexer,
  method: string | undefined,
  target: string | undefined,
): Answer {
  try {
    if (method !== "GET") return refusal(indexer, 405, "GET only");
    const raw = target ?? "/";
    if (!raw.startsWith("/") || !URL.canParse(raw, "http://indexer")) {
      return refusal(indexer, 400, "bad request");
    }
    return answer(indexer, new URL(raw, "http://indexer").pathname);
  } catch {
    return refusal(indexer, 500, "internal error");
  }
}

export function serve(indexer: Indexer): Server {
  return createServer((request: IncomingMessage, response: ServerResponse) => {
    let result: Answer;
    try {
      result = respond(indexer, request.method, request.url);
    } catch {
      result = { code: 500, body: { error: "internal error", head: null } };
    }
    response.writeHead(result.code, {
      "content-type": "application/json",
      "cache-control": "no-store",
    });
    response.end(JSON.stringify(result.body));
  });
}
