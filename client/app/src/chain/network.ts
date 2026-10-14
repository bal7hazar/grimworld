import {
  type AccountProvider,
  type BurnerChain,
  type ChainConfig,
  type ExecutionId,
  type Funder,
  type KeyStorage,
  LOCAL_ACCOUNT_CLASS,
  type NodeFunderConfig,
  createBurnerProvider,
  createNodeFunder,
  createStarknetChain,
} from "../account";
import { type Reader, type Rpc, SimulationError, createReader, createRpc } from "../preview";
import type { ChainRefusal } from "./params";
import {
  ADMIN_INDEX,
  BAR_SLOTS,
  BELT_SLOTS,
  BURNER_FUNDS,
  type Build,
  FUNDER_INDEX,
  type Kit,
  type Sender,
} from "./setup";

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

/**
 * A deployment made with `--build full` (OPS-01b, SEED-02): the build its adventurer carries, which
 * the burner's carries too (CLI-11d2), and what the devnet's gold and pack harness needs (D-280):
 * the deployment's account, the Hub's administrator, and the flattening library's class.
 */
export interface FullBuild {
  readonly build: Build;
  readonly account: string;
  readonly flatten: string;
}

/** What the mode reads of the deployment: its node, its chain and its contracts. */
export interface Deployment {
  readonly nodeUrl: string;
  readonly chainId: bigint;
  readonly contracts: Contracts;
  /** Only for a deployment built `--build full`; without it the burner's bar stays empty. */
  readonly full?: FullBuild;
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

const isCount = (value: unknown, below: number): value is number =>
  Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) < below;

/**
 * The `build` key of a `--build full` deployment: `bar` the eight skill ids by slot, `belt` up to
 * four `{item, count}`, `gold` what the harness credited; `account` and `classes.flatten_library`
 * hex strings. Null when the key says another mode (or is missing), undefined when it is malformed.
 */
function parseFull(body: Record<string, unknown>): FullBuild | null | undefined {
  const { build, account, classes } = body;
  if (typeof build !== "object" || build === null) return null;
  const { mode, bar, belt, gold } = build as Record<string, unknown>;
  if (mode !== "full") return null;
  if (!Array.isArray(bar) || bar.length !== BAR_SLOTS) return undefined;
  if (!bar.every((skill) => isCount(skill, 1 << 16))) return undefined;
  if (!Array.isArray(belt) || belt.length > BELT_SLOTS) return undefined;
  const lanes = belt.map((lane: unknown) => {
    const { item, count } = (lane ?? {}) as Record<string, unknown>;
    return isCount(item, 2 ** 32) && isCount(count, 1 << 8) && count > 0
      ? { item, count }
      : undefined;
  });
  if (lanes.some((lane) => lane === undefined) || !isCount(gold, 2 ** 53)) return undefined;
  const flatten = (classes as Record<string, unknown> | null | undefined)?.flatten_library;
  if (typeof account !== "string" || !HEX.test(account)) return undefined;
  if (typeof flatten !== "string" || !HEX.test(flatten)) return undefined;
  return {
    build: { bar, belt: lanes as Build["belt"], gold: BigInt(gold) },
    account,
    flatten,
  };
}

/**
 * The deployment's shape, or undefined: `node_url` a string, `chain_id` a chain id, and the four
 * addresses of `contracts`, each a hex string; with `build.mode` "full", the build too
 * (`parseFull`). Nothing else of the body is kept.
 */
export function parseDeployment(body: unknown): Deployment | undefined {
  if (typeof body !== "object" || body === null) return undefined;
  const { node_url, chain_id, contracts } = body as Record<string, unknown>;
  const chainId = chainIdOf(chain_id);
  if (typeof node_url !== "string" || chainId === undefined) return undefined;
  if (typeof contracts !== "object" || contracts === null) return undefined;
  const c = contracts as Record<string, unknown>;
  const names = ["registry", "tx_hash_fate", "hub", "instances"] as const;
  if (!names.every((name) => typeof c[name] === "string" && HEX.test(c[name]))) return undefined;
  const full = parseFull(body as Record<string, unknown>);
  if (full === undefined) return undefined;
  return {
    nodeUrl: node_url,
    chainId,
    contracts: {
      registry: c.registry as string,
      tx_hash_fate: c.tx_hash_fate as string,
      hub: c.hub as string,
      instances: c.instances as string,
    },
    ...(full === null ? {} : { full }),
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
  const id = await chainIdAt(rpc);
  if (id === SN_MAIN) throw new ChainRefused("not a test chain");
  if (id !== SN_SEPOLIA) throw new ChainRefused("not a test chain");
  await predeployed(rpc);
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
  /** With a `--build full` deployment only: the burner's build and the devnet's harness. */
  readonly kit?: Kit;
}

/** `sn_keccak("instances")`: the Hub's plain storage variable `instances`, held by the test. */
export const INSTANCES_KEY = 0x36df9d06808417dd5418f1affa340f30b2c975d7bae1d6ce5bcd85c10200d99n;

/**
 * The devnet's harness (D-280, CLI-11d2): the node's account `ADMIN_INDEX`, which must be the
 * deployment's own account (the Hub's administrator), sends through the guarded chain, so every
 * one of its executions awaits `assertTestChain` first. Its key is read from the node as the
 * funder's is, held in this closure only.
 */
function harness(
  full: FullBuild,
  deployment: Deployment,
  admin: { address: string; private_key: string },
  chain: BurnerChain,
  rpc: Rpc,
): Kit {
  if (BigInt(admin.address) !== BigInt(full.account)) {
    throw new ChainRefused("deployment of another node");
  }
  const sender: Sender = {
    address: admin.address,
    execute: async (calls) =>
      (await chain.send(admin.private_key, admin.address, calls)) as ExecutionId,
    status: (id) => chain.status(id),
  };
  return {
    build: full.build,
    admin: sender,
    fate: deployment.contracts.tx_hash_fate,
    flatten: full.flatten,
    async hubInstances() {
      const word = await rpc("starknet_getStorageAt", {
        contract_address: deployment.contracts.hub,
        key: `0x${INSTANCES_KEY.toString(16)}`,
        block_id: "latest",
      });
      if (typeof word !== "string" || !HEX.test(word)) throw new TypeError("not a felt");
      return BigInt(word);
    },
  };
}

export interface OpenOptions {
  /** Every request to the node goes through it. */
  fetch?: typeof fetch;
  /** The burner's storage; `localStorage` by default. */
  storage?: KeyStorage;
  /** The burner's chain and funder (tests fake them; the real ones by default). */
  makeChain?: (config: ChainConfig) => BurnerChain;
  makeFunder?: (config: NodeFunderConfig) => Funder;
}

/**
 * Opens the mode on `nodeUrl` (`?chain=`) with `deployment`. Before any request to the game:
 * the deployment is the node's (the same `node_url`, as written, and the node's chain id), and
 * `assertTestChain` passes. The funder is the node's pre-funded account `FUNDER_INDEX`, read from
 * the node and held in memory only. With a `--build full` deployment, the kit too (`harness`):
 * the node's account `ADMIN_INDEX`, the same way. Refusals are `ChainRefused`; nothing is signed
 * before them.
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
  const assertChain = () => assertTestChain(rpc);
  await assertChain();
  const accounts = await predeployed(rpc);
  const funder = accounts[FUNDER_INDEX];
  const admin = accounts[ADMIN_INDEX];
  if (funder === undefined || admin === undefined) throw new ChainRefused("not a test chain");
  const config: ChainConfig = { nodeUrl, accountClass: LOCAL_ACCOUNT_CLASS };
  const chain = (options.makeChain ?? createStarknetChain)(config);
  const { full } = deployment;
  const kit = full && harness(full, deployment, admin, guardChain(chain, assertChain), rpc);
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
    ...(kit ? { kit } : {}),
  };
}
