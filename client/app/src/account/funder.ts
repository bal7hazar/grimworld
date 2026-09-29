import type { Funder } from "./burner";
import { createNodeFunder, type NodeFunderConfig } from "./starknet";
import { AccountError, type AccountErrorCode } from "./types";

/**
 * The game's funder on a public network (FND-08): the funding service deploys and funds the
 * burner's account, and holds the funding key; the client holds none and signs nothing here. It
 * asks the service over HTTP and knows no chain library.
 */

export interface ServiceFunderConfig {
  /** The service's endpoint, `…/v1/burners`. */
  url: string;
  /** How many times to ask while the service answers that the funding is not settled yet. */
  attempts?: number;
  /** The wait between two of them, in milliseconds. */
  retryMs?: number;
  /** Every request goes through it (tests answer them offline). */
  fetch?: typeof fetch;
}

/** How the service's answers read to the game: neutral codes (design/11), never its words. */
function codeOf(status: number): AccountErrorCode {
  if (status === 400) return "invalid";
  if (status === 403) return "refused";
  return "unavailable";
}

function sameFelt(a: unknown, b: string): boolean {
  try {
    return typeof a === "string" && BigInt(a) === BigInt(b);
  } catch {
    return false;
  }
}

export function createServiceFunder(options: ServiceFunderConfig): Funder {
  const config = Object.freeze({
    url: String(options.url),
    attempts: Number(options.attempts ?? 15),
    retryMs: Number(options.retryMs ?? 2000),
    fetch: options.fetch ?? globalThis.fetch.bind(globalThis),
  });
  return {
    async provide(publicKey, address) {
      for (let attempt = 1; ; attempt++) {
        let response: Response;
        let body: { address?: unknown; status?: unknown } | undefined;
        try {
          response = await config.fetch(config.url, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ publicKey, address }),
          });
          body = (await response.json().catch(() => undefined)) as typeof body;
        } catch (error) {
          throw new AccountError("unavailable", { cause: error });
        }
        const settled = response.status === 200 && body?.status === "succeeded";
        const pending = response.status === 202 && body?.status === "pending";
        if ((settled || pending) && !sameFelt(body?.address, address)) {
          // The service funded another account than the one this key derives: never use it.
          throw new AccountError("refused", { cause: new Error("the funded address differs") });
        }
        if (settled) return;
        if (pending && attempt < config.attempts) {
          await new Promise((resolve) => setTimeout(resolve, config.retryMs));
          continue;
        }
        throw new AccountError(pending ? "unavailable" : codeOf(response.status), {
          cause: new Error(`the funding service answered ${response.status}`),
        });
      }
    },
  };
}

/**
 * Which funder the game uses, by configuration: the local node's development funder, or the
 * funding service on a public network.
 */
export type FunderConfig =
  ({ kind: "node" } & NodeFunderConfig) | ({ kind: "service" } & ServiceFunderConfig);

export function createFunder(config: FunderConfig): Funder {
  switch (config.kind) {
    case "node":
      return createNodeFunder(config);
    case "service":
      return createServiceFunder(config);
  }
}
