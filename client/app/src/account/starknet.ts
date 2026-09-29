import {
  Account,
  CallData,
  RpcError,
  RpcProvider,
  cairo,
  defaultDeployer,
  ec,
  encode,
  hash,
  num,
  type Call as StarknetCall,
} from "starknet";
import type { BurnerChain, Funder } from "./burner";
import { AccountError, type Call, type ExecutionStatus } from "./types";

/**
 * The burner's chain, on starknet.js: the only file of the module that imports the library, and
 * nothing it exports carries one of its types (ADR-0005 §1).
 *
 * The account class is configuration: on the local node, the OpenZeppelin account the node declares
 * at start (v1.0.0, `0x05b4b537…3564`); on Sepolia, D-137's `AccountUpgradeable` v3.0.0
 * (`0x01d1777d…2381`). Both take the public key as their only constructor argument.
 */

/** The OpenZeppelin account class the local node (starknet-devnet 0.10, NS-1) declares at start. */
export const LOCAL_ACCOUNT_CLASS =
  "0x05b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564";
/** The STRK token, the same address on the local node and on Starknet's networks. */
export const STRK = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

export interface ChainConfig {
  nodeUrl: string;
  /** The class of the burner's account. */
  accountClass: string;
}

/** The address of the account of a public key: salt and only constructor argument the key. */
function addressOf(publicKey: string, accountClass: string): string {
  return num.toHex64(
    hash.calculateContractAddressFromHash(publicKey, accountClass, [publicKey], 0),
  );
}

function toStarknet(call: Call): StarknetCall {
  return {
    contractAddress: call.to,
    entrypoint: call.entrypoint,
    calldata: call.calldata.map((felt) => num.toHex(felt)),
  };
}

function isNotFound(error: unknown, type: "CONTRACT_NOT_FOUND" | "TXN_HASH_NOT_FOUND"): boolean {
  return error instanceof RpcError && error.isType(type);
}

/** An error the node answered with (a call it refuses) is `refused`; anything else, `unavailable`. */
function refusal(error: unknown): unknown {
  return error instanceof RpcError ? new AccountError("refused", { cause: error }) : error;
}

async function isDeployed(provider: RpcProvider, address: string): Promise<boolean> {
  try {
    await provider.getClassHashAt(address);
    return true;
  } catch (error) {
    if (isNotFound(error, "CONTRACT_NOT_FOUND")) return false;
    throw error;
  }
}

export function createStarknetChain(config: ChainConfig): BurnerChain {
  const provider = new RpcProvider({ nodeUrl: config.nodeUrl });
  return {
    async binding() {
      return `${num.toHex(await provider.getChainId())}/${num.toHex(config.accountClass)}`;
    },

    newKey() {
      return encode.addHexPrefix(encode.buf2hex(ec.starkCurve.utils.randomPrivateKey()));
    },

    derive(privateKey) {
      const publicKey = ec.starkCurve.getStarkKey(privateKey);
      return { publicKey, address: addressOf(publicKey, config.accountClass) };
    },

    isDeployed(address) {
      return isDeployed(provider, address);
    },

    async send(privateKey, address, calls) {
      const account = new Account({ provider, address, signer: privateKey });
      try {
        const { transaction_hash } = await account.execute(calls.map(toStarknet));
        return transaction_hash;
      } catch (error) {
        throw refusal(error);
      }
    },

    async status(id): Promise<ExecutionStatus> {
      let result;
      try {
        result = await provider.getTransactionStatus(id);
      } catch (error) {
        if (isNotFound(error, "TXN_HASH_NOT_FOUND")) return "unknown";
        throw error;
      }
      // RPC 0.9 and later have no rejected status: a refused execution is never received.
      if (result.execution_status === "REVERTED") return "failed";
      if (
        (result.finality_status === "ACCEPTED_ON_L2" ||
          result.finality_status === "ACCEPTED_ON_L1") &&
        result.execution_status === "SUCCEEDED"
      ) {
        return "succeeded";
      }
      return "pending";
    },
  };
}

export interface NodeFunderConfig extends ChainConfig {
  /** One of the local node's pre-funded accounts, and its key as the node publishes it. */
  funderAddress: string;
  funderKey: string;
  /** STRK given to each new burner, in its smallest unit (fri). */
  amount: bigint;
  /** How often to ask whether the deployment settled, in milliseconds. */
  pollMs?: number;
  /** Every request of the funder goes through it (tests observe and answer them offline). */
  fetch?: typeof fetch;
}

/** The funder refused to act: its configuration is not the local node's (FND-05, fix loop 1). */
export class LocalNodeRefused extends Error {
  constructor(reason: string) {
    super(`local node funder refused: ${reason}`);
    this.name = "LocalNodeRefused";
  }
}

/** Hosts of the machine itself: the only endpoints the development funder talks to. */
const LOOPBACK = new Set(["127.0.0.1", "localhost", "[::1]"]);
const SN_MAIN = "0x534e5f4d41494e";

/**
 * Checks, before anything is signed or sent, that the funder is the local node's (fix loop 1, F-1):
 * 1. the endpoint is on this machine (loopback): a public endpoint is refused before any request;
 * 2. the node answers `devnet_getPredeployedAccounts`, a method of the local node only (a public
 *    node does not have it), and **publishes the funder's address with the same private key**;
 * 3. its chain id is not mainnet's.
 * The chain id alone cannot tell the local node from Sepolia (the node reports `SN_SEPOLIA`), and a
 * loopback address alone can be a tunnel to a public node. Check 2 is the one configuration cannot
 * pass: configuration only supplies an endpoint, an address and a key, and the funder signs only
 * with a key the node itself publishes to anyone who asks. Such a key holds nothing of value on any
 * network; a key of value is never published by a node. Getting past it takes a program written to
 * impersonate the local node, not a setting.
 */
async function assertLocalNode(config: NodeFunderConfig, fetchImpl: typeof fetch): Promise<void> {
  let url: URL;
  try {
    url = new URL(config.nodeUrl);
  } catch {
    throw new LocalNodeRefused("the endpoint is not a URL");
  }
  if ((url.protocol !== "http:" && url.protocol !== "https:") || !LOOPBACK.has(url.hostname)) {
    throw new LocalNodeRefused("the endpoint is not on this machine");
  }
  const rpc = async (method: string, params: unknown): Promise<unknown> => {
    const response = await fetchImpl(config.nodeUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    const body = (await response.json()) as { result?: unknown; error?: unknown };
    if (body.error !== undefined || body.result === undefined) {
      throw new LocalNodeRefused(`the node does not answer ${method}`);
    }
    return body.result;
  };
  const accounts = await rpc("devnet_getPredeployedAccounts", {});
  const published =
    Array.isArray(accounts) &&
    accounts.some((entry: { address?: unknown; private_key?: unknown }) => {
      try {
        return (
          num.toBigInt(String(entry.address)) === num.toBigInt(config.funderAddress) &&
          num.toBigInt(String(entry.private_key)) === num.toBigInt(config.funderKey)
        );
      } catch {
        return false;
      }
    });
  if (!published) {
    throw new LocalNodeRefused("the funder is not a pre-funded account the node publishes");
  }
  const chainId = await rpc("starknet_chainId", []);
  if (num.toBigInt(String(chainId)) === num.toBigInt(SN_MAIN)) {
    throw new LocalNodeRefused("the chain is mainnet");
  }
}

/**
 * The game's funder in development: a pre-funded account of the local node deploys the burner's
 * account through the universal deployer and sends it STRK, in one execution (D-137: the game
 * funds, the burner sends directly). It refuses anything but the local node (`assertLocalNode`,
 * at every `provide`, before any signature). Funding on a public network is a service of the game
 * behind the same `Funder`, never this.
 */
export function createNodeFunder(config: NodeFunderConfig): Funder {
  const fetchImpl = config.fetch ?? globalThis.fetch.bind(globalThis);
  const provider = new RpcProvider({ nodeUrl: config.nodeUrl, baseFetch: fetchImpl });
  return {
    async provide(publicKey, address) {
      await assertLocalNode(config, fetchImpl);
      // The signer exists only once the node is known to be the local one.
      const funder = new Account({
        provider,
        address: config.funderAddress,
        signer: config.funderKey,
      });
      if (await isDeployed(provider, address)) return;
      const deploy = defaultDeployer.buildDeployerCall(
        {
          classHash: config.accountClass,
          salt: publicKey,
          unique: false,
          constructorCalldata: [publicKey],
        },
        config.funderAddress,
      );
      if (num.toBigInt(deploy.addresses[0] ?? 0) !== num.toBigInt(address)) {
        throw new Error("the deployer's address differs from the derived one");
      }
      const fund: StarknetCall = {
        contractAddress: STRK,
        entrypoint: "transfer",
        calldata: CallData.compile({ recipient: address, amount: cairo.uint256(config.amount) }),
      };
      const { transaction_hash } = await funder.execute([...deploy.calls, fund]);
      const receipt = await provider.waitForTransaction(transaction_hash, {
        retryInterval: config.pollMs ?? 250,
      });
      if (!receipt.isSuccess()) throw new Error("the funding execution did not succeed");
    },
  };
}
