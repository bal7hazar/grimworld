import {
  type AccountProvider,
  type BurnerChain,
  type ChainConfig,
  type Funder,
  type KeyStorage,
  LOCAL_ACCOUNT_CLASS,
  type NodeFunderConfig,
  createBurnerProvider,
  createNodeFunder,
  createStarknetChain,
} from "../account";
import { type Reader, type Rpc, SimulationError, createReader, createRpc } from "../preview";
import type { Credit } from "./credit";
import { CONTRACT_NAMES, type Network, SEPOLIA } from "./networks";
import { type ChainRefusal, keylessEndpoint } from "./params";
import { BURNER_FUNDS, type Build, FUNDER_INDEX } from "./setup";

/**
 * The chain mode's target (CLI-11 §2.2, §2.3): the deployment the development server serves, the
 * node it lives on, and the one refusal every build carries, `assertTestChain`.
 *
 * This is the only file of `chain/` that builds the burner's chain and funder (`network.test.ts`
 * holds it). It hands them out guarded: the chain's `send` and the funder's `provide` await
 * `assertTestChain` first, and the account provider is built on those only, so every execution of
 * the mode, the setup's and the batch's, goes through the check.
 */

/** `SN_SEPOLIA`, which starknet-devnet 0.10 reports too: the only chain id accepted. */
export const SN_SEPOLIA = 0x534e5f5345504f4c4941n;
/** `SN_MAIN`: refused by name. */
export const SN_MAIN = 0x534e5f4d41494en;

/** The chain mode was refused: the reason only, never a value read from the URL or the node. */
export class ChainRefused extends Error {
  constructor(readonly reason: ChainRefusal) {
    super(`chain mode refused: ${reason}`);
    this.name = "ChainRefused";
  }
}

/** The four contracts of `scripts/devnet_deploy.py`'s JSON. */
export interface Contracts {
  readonly registry: string;
  readonly tx_hash_fate: string;
  readonly hub: string;
  readonly instances: string;
}

/** What the mode reads of the deployment: its node, its chain, its contracts and its build. */
export interface Deployment {
  readonly nodeUrl: string;
  readonly chainId: bigint;
  readonly contracts: Contracts;
  /** SEED-02's build (`--build full`), which the burner's adventurer is given (CLI-11d3). */
  readonly build?: Build;
}

const HEX = /^0x[0-9a-fA-F]{1,64}$/;
/** A chain id as `starknet_chainId` answers it, or as `devnet_deploy.py` writes it (`SN_SEPOLIA`). */
const NAME = /^[\x20-\x7e]{1,31}$/;

function chainIdOf(value: unknown): bigint | undefined {
  if (typeof value !== "string") return undefined;
  if (HEX.test(value)) return BigInt(value);
  if (!NAME.test(value)) return undefined;
  let felt = 0n;
  for (const char of value) felt = (felt << 8n) | BigInt(char.charCodeAt(0));
  return felt;
}

/** A whole number below `2 ** bits`. */
const below = (value: unknown, bits: number): value is number =>
  typeof value === "number" && Number.isInteger(value) && value >= 0 && value < 2 ** bits;

/**
 * The `build` key's ids when it is a full build: eight skill ids (u16) and at most four belt lanes
 * (an item, u32, and a count, u8). An empty build, or another shape, is no build.
 */
function buildOf(value: unknown): Build | undefined {
  if (typeof value !== "object" || value === null) return undefined;
  const { mode, bar, belt } = value as Record<string, unknown>;
  if (mode !== "full" || !Array.isArray(bar) || bar.length !== 8) return undefined;
  if (!bar.every((skill) => below(skill, 16)) || !bar.some((skill) => skill !== 0)) {
    return undefined;
  }
  if (!Array.isArray(belt) || belt.length > 4) return undefined;
  const lanes = belt.map((lane: unknown) => {
    const { item, count } = (lane ?? {}) as Record<string, unknown>;
    return below(item, 32) && below(count, 8) ? { item, count } : undefined;
  });
  if (lanes.some((lane) => lane === undefined)) return undefined;
  return { bar: bar as number[], belt: lanes as Build["belt"] };
}

/**
 * The deployment's shape, or undefined: `node_url` a string, `chain_id` a chain id, and the four
 * addresses of `contracts`, each a hex string; `build` when it is a full build. Nothing else of the
 * body is kept.
 */
export function parseDeployment(body: unknown): Deployment | undefined {
  if (typeof body !== "object" || body === null) return undefined;
  const { node_url, chain_id, contracts, build } = body as Record<string, unknown>;
  const chainId = chainIdOf(chain_id);
  if (typeof node_url !== "string" || chainId === undefined) return undefined;
  if (typeof contracts !== "object" || contracts === null) return undefined;
  const c = contracts as Record<string, unknown>;
  const names = ["registry", "tx_hash_fate", "hub", "instances"] as const;
  if (!names.every((name) => typeof c[name] === "string" && HEX.test(c[name]))) return undefined;
  const full = buildOf(build);
  return {
    ...(full ? { build: full } : {}),
    nodeUrl: node_url,
    chainId,
    contracts: {
      registry: c.registry as string,
      tx_hash_fate: c.tx_hash_fate as string,
      hub: c.hub as string,
      instances: c.instances as string,
    },
  };
}

/**
 * The development server's `/deployment.json` (`src/dev/serveDeployment.ts`). Anything but a 200
 * whose body parses as a deployment is "no deployment": a 404, a network error, and the site's
 * `index.html`, which its server answers with a 200 for any unknown path.
 */
export async function fetchDeployment(
  fetchImpl: typeof fetch = globalThis.fetch.bind(globalThis),
  url = "/deployment.json",
): Promise<Deployment> {
  let deployment: Deployment | undefined;
  try {
    const response = await fetchImpl(url, { headers: { accept: "application/json" } });
    if (response.status === 200) deployment = parseDeployment(JSON.parse(await response.text()));
  } catch {
    deployment = undefined;
  }
  if (deployment === undefined) throw new ChainRefused("no deployment");
  return deployment;
}

/** The node's chain id, as a number. */
async function chainIdAt(rpc: Rpc): Promise<bigint> {
  const id = await rpc("starknet_chainId", []);
  if (typeof id !== "string" || !HEX.test(id)) throw new TypeError("starknet_chainId: not a felt");
  return BigInt(id);
}

/** The node's pre-funded accounts (`devnet_getPredeployedAccounts`), refused when it has none. */
async function predeployed(rpc: Rpc): Promise<{ address: string; private_key: string }[]> {
  let accounts: unknown;
  try {
    accounts = await rpc("devnet_getPredeployedAccounts", {});
  } catch (error) {
    // The node answered, and does not know the method: not the local node
    if (error instanceof SimulationError) throw new ChainRefused("not a test chain");
    throw error;
  }
  if (!Array.isArray(accounts)) throw new ChainRefused("not a test chain");
  return accounts as { address: string; private_key: string }[];
}

/**
 * The one refusal (§2.3): the node's chain id must be `SN_SEPOLIA` (`SN_MAIN` is refused by name,
 * any other id too), and in part 1 the node must answer `devnet_getPredeployedAccounts`, a method of
 * the local node only. Its own two probes are the only requests made before it. No build flag lifts
 * it.
 */
export async function assertTestChain(rpc: Rpc): Promise<void> {
  await assertTestChainId(rpc);
  await predeployed(rpc);
}

/** The chain id half of `assertTestChain`: `SN_SEPOLIA` only, `SN_MAIN` refused by name. */
async function assertTestChainId(rpc: Rpc): Promise<bigint> {
  const id = await chainIdAt(rpc);
  if (id === SN_MAIN) throw new ChainRefused("not a test chain");
  if (id !== SN_SEPOLIA) throw new ChainRefused("not a test chain");
  return id;
}

/** A chain whose `send` awaits the check first. */
export function guardChain(chain: BurnerChain, assertChain: () => Promise<void>): BurnerChain {
  return {
    binding: () => chain.binding(),
    newKey: () => chain.newKey(),
    derive: (privateKey) => chain.derive(privateKey),
    isDeployed: (address) => chain.isDeployed(address),
    async send(privateKey, address, calls) {
      await assertChain();
      return chain.send(privateKey, address, calls);
    },
    status: (id) => chain.status(id),
  };
}

/** A funder whose `provide` awaits the check first. */
export function guardFunder(funder: Funder, assertChain: () => Promise<void>): Funder {
  return {
    async provide(publicKey, address) {
      await assertChain();
      return funder.provide(publicKey, address);
    },
  };
}

/** The mode on its node: reads, the guarded account provider, and the check for any later send. */
export interface Opened {
  readonly deployment: Deployment;
  readonly rpc: Rpc;
  readonly reader: Reader;
  readonly provider: AccountProvider;
  readonly assertChain: () => Promise<void>;
  /** The burner's credit (CLI-11d3), when the deployment has a build. */
  readonly credit?: Credit;
}

export interface OpenOptions {
  /** Every request to the node goes through it. */
  fetch?: typeof fetch;
  /** The burner's storage; `localStorage` by default. */
  storage?: KeyStorage;
  /** The burner's chain and funder (tests fake them; the real ones by default). */
  makeChain?: (config: ChainConfig) => BurnerChain;
  makeFunder?: (config: NodeFunderConfig) => Funder;
  /**
   * The development server's credit (CLI-11d3): once it says the devnet was left mid-credit,
   * the check refuses every send and funding.
   */
  credit?: Credit;
}

/**
 * Opens the mode on `nodeUrl` (`?chain=`) with `deployment`. Before any request to the game:
 * the deployment is the node's (the same `node_url`, as written, and the node's chain id), and
 * `assertTestChain` passes. The funder is the node's pre-funded account `FUNDER_INDEX`, read from
 * the node and held in memory only. Refusals are `ChainRefused`; nothing is signed before them.
 * With `options.credit`, the check also refuses a devnet left mid-credit (caveat c of
 * `devnet_deploy.py --credit-only`): "devnet left mid-credit: redeploy".
 */
export async function openChain(
  nodeUrl: string,
  deployment: Deployment,
  options: OpenOptions = {},
): Promise<Opened> {
  if (deployment.nodeUrl !== nodeUrl) throw new ChainRefused("deployment of another node");
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const rpc = createRpc(nodeUrl, fetchImpl);
  if ((await chainIdAt(rpc)) !== deployment.chainId) {
    throw new ChainRefused("deployment of another node");
  }
  const { credit } = options;
  const assertChain = async () => {
    await assertTestChain(rpc);
    await credit?.assertUsable();
  };
  await assertChain();
  const funder = (await predeployed(rpc))[FUNDER_INDEX];
  if (funder === undefined) throw new ChainRefused("not a test chain");
  const config: ChainConfig = { nodeUrl, accountClass: LOCAL_ACCOUNT_CLASS };
  const chain = (options.makeChain ?? createStarknetChain)(config);
  const funding = (options.makeFunder ?? createNodeFunder)({
    ...config,
    funderAddress: funder.address,
    funderKey: funder.private_key,
    amount: BURNER_FUNDS,
    fetch: fetchImpl,
  });
  const provider = createBurnerProvider({
    chain: guardChain(chain, assertChain),
    funder: guardFunder(funding, assertChain),
    ...(options.storage ? { storage: options.storage } : {}),
  });
  return {
    deployment,
    rpc,
    reader: createReader({ nodeUrl, fetch: fetchImpl }),
    provider,
    assertChain,
    ...(credit ? { credit } : {}),
  };
}

/** `starknet_getClassHashAt`'s answer for an address that holds no contract. */
const CONTRACT_NOT_FOUND = 20;

/**
 * The start check of a public deployment (CLI-11e1, D-154): the class hash at each of its four
 * addresses must equal the recorded one. A mismatch or a missing contract is "Sepolia contracts
 * differ from the record", the reason only; any other error of the node is thrown as it is.
 */
export async function assertRecordedClasses(rpc: Rpc, network: Network): Promise<void> {
  for (const name of CONTRACT_NAMES) {
    const { address, classHash } = network.contracts[name];
    let found: unknown;
    try {
      found = await rpc("starknet_getClassHashAt", {
        block_id: "latest",
        contract_address: address,
      });
    } catch (error) {
      if (error instanceof SimulationError && error.code === CONTRACT_NOT_FOUND) {
        throw new ChainRefused("Sepolia contracts differ from the record");
      }
      throw error;
    }
    if (typeof found !== "string" || !HEX.test(found) || BigInt(found) !== BigInt(classHash)) {
      throw new ChainRefused("Sepolia contracts differ from the record");
    }
  }
}

/**
 * The development server's `/sepolia.json` (`src/dev/serveSepolia.ts`): `{ node_url }`, a keyless
 * https endpoint. Anything else (a 404, the site's `index.html`, a keyed or http URL) is "no
 * Sepolia endpoint".
 */
export async function fetchSepoliaEndpoint(
  fetchImpl: typeof fetch = globalThis.fetch.bind(globalThis),
  url = "/sepolia.json",
): Promise<string> {
  let endpoint: string | undefined;
  try {
    const response = await fetchImpl(url, { headers: { accept: "application/json" } });
    if (response.status === 200) {
      endpoint = keylessEndpoint((JSON.parse(await response.text()) as { node_url?: unknown }).node_url);
    }
  } catch {
    endpoint = undefined;
  }
  if (endpoint === undefined) throw new ChainRefused("no Sepolia endpoint");
  return endpoint;
}

/**
 * Opens the mode on Sepolia (CLI-11e1, under the development server only): reads, never a send.
 * The chain id must be `SN_SEPOLIA` (`SN_MAIN` refused by name, as `assertTestChain` does), then
 * the recorded classes must be at their addresses. Sepolia has no pre-funded account, so the mode
 * needs FND-08's funding service, which CLI-11e2 adds: until then it stops there, before any
 * funding, with "Sepolia: funding service not configured (CLI-11e2)". No chain, funder or account
 * is built.
 */
export async function openSepolia(
  nodeUrl: string,
  options: { fetch?: typeof fetch; network?: Network } = {},
): Promise<never> {
  const network = options.network ?? SEPOLIA;
  const rpc = createRpc(nodeUrl, options.fetch ?? globalThis.fetch.bind(globalThis));
  if ((await assertTestChainId(rpc)) !== chainIdOf(network.chainId)) {
    throw new ChainRefused("deployment of another node");
  }
  await assertRecordedClasses(rpc, network);
  throw new ChainRefused("Sepolia: funding service not configured (CLI-11e2)");
}
