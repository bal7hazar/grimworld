import {
  Account,
  CallData,
  RpcError,
  RpcProvider,
  cairo,
  defaultDeployer,
  ec,
  hash,
  num,
  type Call,
  type ResourceBoundsBN,
} from "starknet";
import { SN_MAIN } from "./config.ts";
import type { Secret } from "./secret.ts";

/**
 * The service's only door to the chain, and the only module that can send (COMMON §4): nothing it
 * exports is an account, a signer or a provider. `prepare` checks the network before it builds a
 * signer, at every funding, and the execution it signs is bound to the chain id it checked.
 *
 * Signing and handing to the node are two steps (fix loop 2): `prepare` signs and gives the
 * execution's id and its signed form, which the service keeps before `submit` hands it over. A
 * nonce therefore only ever carries that one execution: when its fate is unclear, the same signed
 * execution is handed again (`verify`, then `submit`), never another one.
 */

/** The STRK token, the same address on the local node and on Starknet's networks. */
export const STRK = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

export type FundingStatus = "pending" | "succeeded" | "failed" | "unknown";

/**
 * The funding failed before anything was handed to the node: nothing can be executed, the nonce
 * is not consumed (fix loop 1, F-2: the caps are given back only then).
 */
export class NotSent extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "NotSent";
  }
}

/** Nothing was signed or sent: the network is not one the service may send to. */
export class NetworkRefused extends NotSent {
  constructor(reason: string) {
    super(`network refused: ${reason}`);
    this.name = "NetworkRefused";
  }
}

/** Nothing was sent: the funding would cost more in fees than the configured cap. */
export class FeeRefused extends NotSent {
  constructor() {
    super("the funding's fee bound is above the cap");
    this.name = "FeeRefused";
  }
}

export interface FundingChain {
  /** The account's address for a public key, or `undefined` when it is not a key on the curve. */
  addressOf(publicKey: string): { publicKey: string; address: string } | undefined;
  isDeployed(address: string): Promise<boolean>;
  /** The funding account's nonce in the latest block: the executions it has had included. */
  nonce(): Promise<bigint>;
  /**
   * Checks the network (`NetworkRefused`), then signs, with the nonce given, the account's
   * deployment and its funding as one execution, within the fee cap (`FeeRefused`). Hands nothing
   * to the node: every failure is a `NotSent`.
   */
  prepare(publicKey: string, address: string, nonce: bigint): Promise<Signed>;
  /**
   * Hands a signed execution to the node. The request leaves during the call itself, before it
   * returns: nothing the caller awaits comes between its checks and the handing. Resolves with the
   * execution's id; a failure may or may not have reached the node.
   */
  submit(payload: string): Promise<string>;
  /**
   * Before a signed execution is handed again: refuses (`NetworkRefused`) unless the node's chain
   * id is still the one it was signed for, and still allowed.
   */
  verify(payload: string): Promise<void>;
  status(id: string): Promise<FundingStatus>;
}

/** A signed execution: its id, computed before it is handed over, and its signed form. */
export interface Signed {
  readonly transaction: string;
  /** The signed execution and the chain id it is bound to, as JSON: public, no key in it. */
  readonly payload: string;
}

export interface ChainOptions {
  rpcUrl: string;
  accountClass: string;
  funderAddress: string;
  funderKey: Secret;
  networks: readonly bigint[];
  amount: bigint;
  maxFee: bigint;
  /** Every request goes through it (tests answer them offline). */
  fetch?: typeof fetch;
}

/** The most a transaction with these bounds can be charged, with no tip. */
export function feeBound(bounds: ResourceBoundsBN): bigint {
  return (
    bounds.l1_gas.max_amount * bounds.l1_gas.max_price_per_unit +
    bounds.l2_gas.max_amount * bounds.l2_gas.max_price_per_unit +
    bounds.l1_data_gas.max_amount * bounds.l1_data_gas.max_price_per_unit
  );
}

const FELT = /^0x[0-9a-fA-F]{1,64}$/;

/** A signed INVOKE v3 as the RPC takes it: the fields its id is computed from. */
interface SignedInvoke {
  sender_address: string;
  calldata: string[];
  version: string;
  nonce: string;
  tip: string;
  paymaster_data: string[];
  account_deployment_data: string[];
  nonce_data_availability_mode: "L1" | "L2";
  fee_data_availability_mode: "L1" | "L2";
  resource_bounds: Record<
    "l1_gas" | "l2_gas" | "l1_data_gas",
    { max_amount: string; max_price_per_unit: string }
  >;
}

interface Payload {
  chainId: string;
  transaction: string;
  invoke: SignedInvoke;
}

/** The execution's id, as the node computes it (it must answer the same, `hand` checks). */
function executionId(invoke: SignedInvoke, chainId: bigint): string {
  const bound = (b: { max_amount: string; max_price_per_unit: string }) => ({
    max_amount: BigInt(b.max_amount),
    max_price_per_unit: BigInt(b.max_price_per_unit),
  });
  const mode = (m: "L1" | "L2") => (m === "L1" ? 0 : 1);
  return num.toHex(
    hash.calculateInvokeTransactionHash({
      senderAddress: invoke.sender_address,
      version: invoke.version,
      compiledCalldata: invoke.calldata,
      chainId: num.toHex(chainId),
      nonce: invoke.nonce,
      accountDeploymentData: invoke.account_deployment_data,
      nonceDataAvailabilityMode: mode(invoke.nonce_data_availability_mode),
      feeDataAvailabilityMode: mode(invoke.fee_data_availability_mode),
      resourceBounds: {
        l1_gas: bound(invoke.resource_bounds.l1_gas),
        l2_gas: bound(invoke.resource_bounds.l2_gas),
        l1_data_gas: bound(invoke.resource_bounds.l1_data_gas),
      },
      tip: invoke.tip,
      paymasterData: invoke.paymaster_data,
    } as never),
  );
}

/** The RPC's error for an execution the node already has. */
const DUPLICATE_TX = 59;

export function createFundingChain(options: ChainOptions): FundingChain {
  // Copied once: the network checked, the class deployed and the account signing stay those of
  // creation, whatever happens to the caller's object.
  const config = Object.freeze({
    rpcUrl: String(options.rpcUrl),
    accountClass: String(options.accountClass),
    funderAddress: String(options.funderAddress),
    funderKey: options.funderKey,
    networks: Object.freeze([...options.networks]),
    amount: BigInt(options.amount),
    maxFee: BigInt(options.maxFee),
    fetch: options.fetch ?? globalThis.fetch.bind(globalThis),
  });
  const reader = new RpcProvider({ nodeUrl: config.rpcUrl, baseFetch: config.fetch });

  /** The chain id, asked at every send: the provider's own copy is cached. */
  async function chainId(): Promise<bigint> {
    const response = await config.fetch(config.rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "starknet_chainId", params: [] }),
    });
    const body = (await response.json()) as { result?: unknown };
    if (typeof body.result !== "string" || !FELT.test(body.result)) {
      throw new NetworkRefused("the node does not tell its chain id");
    }
    return BigInt(body.result);
  }

  /** The node's chain id, refused unless configured and not mainnet. */
  async function allowedChainId(): Promise<bigint> {
    const id = await chainId();
    if (id === SN_MAIN) throw new NetworkRefused("the chain is mainnet");
    if (!config.networks.includes(id)) throw new NetworkRefused("the chain is not configured");
    return id;
  }

  /**
   * Hands the signed execution to the node: the request is made during this call, synchronously,
   * and the answer checked after. The node's id must be the one computed before.
   */
  function hand(payload: Payload): Promise<string> {
    const request = config.fetch(config.rpcUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "starknet_addInvokeTransaction",
        params: { invoke_transaction: payload.invoke },
      }),
    });
    return request.then(async (response) => {
      const body = (await response.json()) as {
        result?: { transaction_hash?: string };
        error?: { code?: number };
      };
      if (body.error) {
        if (body.error.code === DUPLICATE_TX) return payload.transaction;
        throw new Error(`the node refused the execution (${String(body.error.code)})`);
      }
      const id = body.result?.transaction_hash;
      if (!id || BigInt(id) !== BigInt(payload.transaction)) {
        throw new Error("the node's execution id differs from the one computed");
      }
      return payload.transaction;
    });
  }

  /** Everything before the execution reaches the node: the network, the calls, the fee's cap. */
  async function prepare(publicKey: string, address: string, nonce: bigint): Promise<Signed> {
    const id = await allowedChainId();
    // The signer exists only once the network is known, and signs for that chain id only: the
    // same execution is invalid on any other network.
    const provider = new RpcProvider({
      nodeUrl: config.rpcUrl,
      baseFetch: config.fetch,
      chainId: num.toHex(id) as never,
    });
    const funder = new Account({
      provider,
      address: config.funderAddress,
      signer: config.funderKey.reveal(),
    });
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
      throw new NotSent("the deployer's address differs from the derived one");
    }
    // The deployment and the transfer are one execution: when the account exists already, the
    // deployment fails and the transfer with it, so a key is never funded twice on the chain.
    const calls: Call[] = [
      ...deploy.calls,
      {
        contractAddress: STRK,
        entrypoint: "transfer",
        calldata: CallData.compile({ recipient: address, amount: cairo.uint256(config.amount) }),
      },
    ];
    const estimate = await funder.estimateInvokeFee(calls, { nonce, tip: 0n });
    if (feeBound(estimate.resourceBounds) > config.maxFee) throw new FeeRefused();
    // Signed here, handed over later by `submit`: nothing reaches the node in this function.
    const invoke = (await funder.getSignedTransaction(calls, {
      nonce,
      resourceBounds: estimate.resourceBounds,
      tip: 0n,
    })) as unknown as SignedInvoke;
    if (BigInt(invoke.nonce) !== nonce) throw new NotSent("the signed nonce is not the one held");
    const transaction = executionId(invoke, id);
    return {
      transaction,
      payload: JSON.stringify({ chainId: num.toHex(id), transaction, invoke } satisfies Payload),
    };
  }

  return {
    addressOf(input) {
      if (!FELT.test(input)) return undefined;
      const key = BigInt(input);
      if (key === 0n || key >= 2n ** 251n) return undefined;
      const publicKey = num.toHex64(key);
      try {
        // A stark key is a point's x coordinate: a value with no point is no one's key.
        ec.starkCurve.ProjectivePoint.fromHex(`02${publicKey.slice(2)}`);
      } catch {
        return undefined;
      }
      const address = num.toHex64(
        hash.calculateContractAddressFromHash(publicKey, config.accountClass, [publicKey], 0),
      );
      return { publicKey, address };
    },

    async isDeployed(address) {
      try {
        await reader.getClassHashAt(address);
        return true;
      } catch (error) {
        if (error instanceof RpcError && error.isType("CONTRACT_NOT_FOUND")) return false;
        throw error;
      }
    },

    async nonce() {
      return num.toBigInt(await reader.getNonceForAddress(config.funderAddress, "latest"));
    },

    async prepare(publicKey, address, nonce) {
      try {
        return await prepare(publicKey, address, nonce);
      } catch (error) {
        throw error instanceof NotSent
          ? error
          : new NotSent("the funding was not prepared", { cause: error });
      }
    },

    submit(payload) {
      return hand(JSON.parse(payload) as Payload);
    },

    async verify(payload) {
      const parsed = JSON.parse(payload) as Payload;
      // Checked again before every handing: the signature is bound to its chain id anyway.
      if ((await allowedChainId()) !== BigInt(parsed.chainId)) {
        throw new NetworkRefused("the chain is not the one the execution was signed for");
      }
    },

    async status(id) {
      let result;
      try {
        result = await reader.getTransactionStatus(id);
      } catch (error) {
        if (error instanceof RpcError && error.isType("TXN_HASH_NOT_FOUND")) return "unknown";
        throw error;
      }
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
