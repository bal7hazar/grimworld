import { keylessEndpoint } from "../chain/params.js";

/**
 * The development server's `/sepolia.json` handler (used by `vite.config.ts` only, never by the
 * app; CLI-11e1): the Sepolia endpoint `?chain=sepolia` plays on, as `{ "node_url": … }`. It is
 * `GRIMWORLD_SEPOLIA_RPC` when set, else `DEFAULT_SEPOLIA_RPC`; either must be a keyless https
 * URL (no user information, no query string), or nothing is served (404). The site's build serves
 * no such path, and the app's bundle holds no node URL: the default lives here, node-side.
 */

/**
 * PublicNode's Sepolia endpoint: keyless and https, spec 0.10.3, the four recorded classes at
 * their addresses, and `starknet_traceTransaction` served (`probe-sepolia.mjs`, 2026-10-14; see
 * the README's Sepolia section for the endpoints tried).
 */
export const DEFAULT_SEPOLIA_RPC = "https://starknet-sepolia-rpc.publicnode.com";

export type SepoliaResponse =
  { readonly status: 200; readonly body: string } | { readonly status: 404 };

/** `setting` is `GRIMWORLD_SEPOLIA_RPC`'s value, or undefined when it is not set. */
export function sepoliaEndpoint(setting: string | undefined): string | undefined {
  return keylessEndpoint(setting === undefined || setting === "" ? DEFAULT_SEPOLIA_RPC : setting);
}

export function serveSepolia(setting: string | undefined): SepoliaResponse {
  const nodeUrl = sepoliaEndpoint(setting);
  if (nodeUrl === undefined) return { status: 404 };
  return { status: 200, body: JSON.stringify({ node_url: nodeUrl }) };
}
