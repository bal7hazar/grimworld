import { readFileSync } from "node:fs";

/**
 * The development server's `/deployment.json` handler (used by `vite.config.ts` only, never by the
 * app; CLI-11 §2.2): the file `GRIMWORLD_DEPLOYMENT` names, which `scripts/devnet_deploy.py --out`
 * writes and which holds no key. Only the deployment's known fields are served, rebuilt from the
 * parsed file and never the file verbatim, so another file named by mistake leaks nothing else.
 * No variable, no file, or a file that does not parse: 404.
 */

export type DeploymentResponse =
  { readonly status: 200; readonly body: string } | { readonly status: 404 };

const NOT_FOUND: DeploymentResponse = { status: 404 };

/** Plain values of the deployment: a string or a whole number. */
const plain = (value: unknown): value is string | number =>
  typeof value === "string" || (typeof value === "number" && Number.isSafeInteger(value));

/** An object of strings, by name; anything else is dropped. */
function strings(value: unknown, names?: readonly string[]): Record<string, string> | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
  const out: Record<string, string> = {};
  for (const [name, item] of Object.entries(value)) {
    if ((names === undefined || names.includes(name)) && typeof item === "string") out[name] = item;
  }
  return out;
}

const CONTRACTS = ["registry", "tx_hash_fate", "hub", "instances"] as const;
const PLAIN = ["node_url", "chain_id", "commit", "account", "adventurer_id", "instance_id", "slot"];

/** The deployment's known fields, from a parsed body. */
export function knownFields(parsed: unknown): Record<string, unknown> | undefined {
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return undefined;
  const source = parsed as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const name of PLAIN) {
    const value = source[name];
    if (plain(value)) out[name] = value;
  }
  const classes = strings(source.classes);
  if (classes) out.classes = classes;
  const contracts = strings(source.contracts, CONTRACTS);
  if (contracts) out.contracts = contracts;
  return out;
}

/** `path` is `GRIMWORLD_DEPLOYMENT`'s value, or undefined when it is not set. */
export function serveDeployment(path: string | undefined): DeploymentResponse {
  if (path === undefined || path === "") return NOT_FOUND;
  let fields: Record<string, unknown> | undefined;
  try {
    fields = knownFields(JSON.parse(readFileSync(path, "utf8")));
  } catch {
    return NOT_FOUND;
  }
  if (fields === undefined) return NOT_FOUND;
  return { status: 200, body: JSON.stringify(fields) };
}
