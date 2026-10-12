/**
 * The chain mode's switch (CLI-11 §2.1, D-273): `?chain=<node url>`. Absent or empty, the app is the
 * sandbox. Present, the value must be an `http:` or `https:` URL with no user information, on this
 * machine (part 1: `127.0.0.1`, `localhost`, `[::1]`, as `createNodeFunder` requires). The mode reads
 * no other parameter: no key, account or address ever comes from the URL.
 *
 * A refusal names the rule broken, never the value of the parameter, so a refused
 * `?chain=http://user:pass@host` writes no credential anywhere (neither on screen nor in the
 * console). This module imports nothing of the chain: `App.tsx` reads it before the mode's dynamic
 * import.
 */

/** The rules a chain mode can break, in the words the panel and the console show. */
export type ChainRefusal =
  | "not a URL"
  | "user information"
  | "not on this machine"
  | "no deployment"
  | "deployment of another node"
  | "not a test chain";

export type ChainParam =
  | { readonly kind: "none" }
  | { readonly kind: "refused"; readonly reason: ChainRefusal }
  | { readonly kind: "chain"; readonly nodeUrl: string };

/** Hosts of the machine itself (`URL.hostname`'s spelling). */
export const LOOPBACK: ReadonlySet<string> = new Set(["127.0.0.1", "localhost", "[::1]"]);

export function readChainParam(search: string): ChainParam {
  const value = new URLSearchParams(search).get("chain");
  if (value === null || value === "") return { kind: "none" };
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

/** The panel's line for a refusal. */
export function refusalLine(reason: ChainRefusal): string {
  return `chain mode refused: ${reason}`;
}

/** The console's record of a refusal: one `grimworld.chain-refused` record, the reason only. */
export function logRefusal(reason: ChainRefusal, log: (...data: unknown[]) => void = console.warn) {
  log("grimworld.chain-refused", { line: refusalLine(reason), reason });
}
