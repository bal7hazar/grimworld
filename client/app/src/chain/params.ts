/**
 * The chain mode's switch (CLI-11 §2.1, D-273): `?chain=<node url>`. Absent or empty, the app is the
 * sandbox. Present, the value must be an `http:` or `https:` URL with no user information, on this
 * machine (part 1: `127.0.0.1`, `localhost`, `[::1]`, as the local node's funder requires). The mode
 * reads no other parameter: no key, account or address ever comes from the URL.
 *
 * A refusal names the rule broken, never the value of the parameter, so a refused
 * `?chain=http://user:pass@host` writes no credential anywhere (neither on screen nor in the
 * console). This module imports nothing of the chain: `App.tsx` reads it before the mode's dynamic
 * import.
 *
 * CLI-11e1: `?chain=sepolia` names OPS-02's Sepolia deployment (`networks.ts`), and only when the
 * caller allows it: `App.tsx` passes `import.meta.env.DEV`, false in `vite build`, so on the site
 * the word is "not a URL" like any other. The endpoint is not in the URL: the development server
 * serves it (`/sepolia.json`, `src/dev/serveSepolia.ts`). The loopback rule above is unchanged for
 * every node URL given in `?chain=`.
 */

/** The rules a chain mode can break, in the words the panel and the console show. */
export type ChainRefusal =
  | "not a URL"
  | "user information"
  | "not on this machine"
  | "no deployment"
  | "deployment of another node"
  | "not a test chain"
  | "devnet left mid-credit: redeploy"
  | "no Sepolia endpoint"
  | "Sepolia contracts differ from the record"
  | "Sepolia: funding service not configured (CLI-11e2)";

export type ChainParam =
  | { readonly kind: "none" }
  | { readonly kind: "refused"; readonly reason: ChainRefusal }
  | { readonly kind: "chain"; readonly nodeUrl: string }
  | { readonly kind: "sepolia" };

export interface ChainParamOptions {
  /** `?chain=sepolia` is read as Sepolia: the development server only (`import.meta.env.DEV`). */
  readonly sepolia?: boolean;
}

/** Hosts of the machine itself (`URL.hostname`'s spelling). */
export const LOOPBACK: ReadonlySet<string> = new Set(["127.0.0.1", "localhost", "[::1]"]);

export function readChainParam(search: string, options: ChainParamOptions = {}): ChainParam {
  const value = new URLSearchParams(search).get("chain");
  if (value === null || value === "") return { kind: "none" };
  if (value === "sepolia" && options.sepolia === true) return { kind: "sepolia" };
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return { kind: "refused", reason: "not a URL" };
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return { kind: "refused", reason: "not a URL" };
  }
  // `http://@host` parses with both empty, and carries nothing: only a name or a password counts
  if (url.username !== "" || url.password !== "" || value.includes("@")) {
    return { kind: "refused", reason: "user information" };
  }
  if (!LOOPBACK.has(url.hostname)) return { kind: "refused", reason: "not on this machine" };
  return { kind: "chain", nodeUrl: value };
}

/**
 * A Sepolia endpoint as the development server serves it: an `https:` URL with no user
 * information and no query string or fragment (where a keyed endpoint carries its key), or
 * undefined. Keyless public endpoints only (D-273).
 */
export function keylessEndpoint(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return undefined;
  }
  if (url.protocol !== "https:") return undefined;
  if (url.username !== "" || url.password !== "" || value.includes("@")) return undefined;
  if (url.search !== "" || url.hash !== "" || value.includes("?") || value.includes("#")) {
    return undefined;
  }
  return value;
}

/** The panel's line for a refusal. */
export function refusalLine(reason: ChainRefusal): string {
  return `chain mode refused: ${reason}`;
}

/** The console's record of a refusal: one `grimworld.chain-refused` record, the reason only. */
export function logRefusal(reason: ChainRefusal, log: (...data: unknown[]) => void = console.warn) {
  log("grimworld.chain-refused", { line: refusalLine(reason), reason });
}
