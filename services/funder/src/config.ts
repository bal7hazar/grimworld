import { Secret } from "./secret.ts";

/**
 * The service's configuration, read from the environment by variable name. A value is never
 * printed: an error names the variable, not what it holds. The key is wrapped at once in a `Secret`.
 */

/** The variables the service reads. */
export const ENV = {
  rpcUrl: "FUNDER_RPC_URL",
  address: "FUNDER_ACCOUNT_ADDRESS",
  key: "FUNDER_PRIVATE_KEY",
  accountClass: "FUNDER_ACCOUNT_CLASS",
  networks: "FUNDER_NETWORKS",
  amount: "FUNDER_AMOUNT",
  maxFee: "FUNDER_MAX_FEE",
  dailyBudget: "FUNDER_DAILY_BUDGET",
  clientRate: "FUNDER_CLIENT_RATE",
  host: "FUNDER_HOST",
  port: "FUNDER_PORT",
  stateFile: "FUNDER_STATE_FILE",
  trustProxy: "FUNDER_TRUST_PROXY",
  origin: "FUNDER_ORIGIN",
} as const;

/** 1 STRK in its smallest unit (fri). */
export const STRK_UNIT = 10n ** 18n;

/** The caps' defaults; the report's threat model gives why (FND-08). */
export const DEFAULTS = {
  /** STRK given to each burner: about 50 of the burner's own executions at SPK-1b's prices. */
  amount: 2n * STRK_UNIT,
  /** The most the funding execution may cost in fees (SPK-1b measured 0.0627 STRK). */
  maxFee: STRK_UNIT / 2n,
  /** New burners funded per day (UTC), all clients together. */
  dailyBudget: 50,
  /** New burners funded per client per hour. */
  clientRate: 3,
  host: "127.0.0.1",
  port: 8787,
} as const;

/** Mainnet's chain id (`SN_MAIN`): refused in the configuration and at every send. */
export const SN_MAIN = 0x534e5f4d41494en;

export interface Config {
  readonly rpcUrl: string;
  readonly funderAddress: string;
  readonly funderKey: Secret;
  readonly accountClass: string;
  /** The chain ids the service may send to; never mainnet's. */
  readonly networks: readonly bigint[];
  readonly amount: bigint;
  readonly maxFee: bigint;
  readonly dailyBudget: number;
  readonly clientRate: number;
  readonly host: string;
  readonly port: number;
  readonly stateFile: string | undefined;
  readonly trustProxy: boolean;
  readonly origin: string;
}

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

const FELT = /^0x[0-9a-fA-F]{1,64}$/;
const NETWORK_NAME = /^[A-Z0-9_]{1,31}$/;

/** A chain id from its name (`SN_SEPOLIA`, a short string) or its hex value. */
export function chainIdOf(network: string): bigint | undefined {
  if (FELT.test(network)) return BigInt(network);
  if (NETWORK_NAME.test(network))
    return BigInt(`0x${Buffer.from(network, "ascii").toString("hex")}`);
  return undefined;
}

type Env = Readonly<Record<string, string | undefined>>;

function required(env: Env, name: string): string {
  const value = env[name]?.trim();
  if (!value) throw new ConfigError(`${name} is not set`);
  return value;
}

function felt(env: Env, name: string): string {
  const value = required(env, name);
  if (!FELT.test(value) || BigInt(value) === 0n) {
    throw new ConfigError(`${name} is not a hex number`);
  }
  return value;
}

function positive(env: Env, name: string, fallback: bigint): bigint {
  const value = env[name]?.trim();
  if (!value) return fallback;
  if (!/^[0-9]{1,40}$/.test(value) || BigInt(value) === 0n) {
    throw new ConfigError(`${name} is not a positive whole number`);
  }
  return BigInt(value);
}

function count(env: Env, name: string, fallback: number, max: number): number {
  const value = positive(env, name, BigInt(fallback));
  if (value > BigInt(max)) throw new ConfigError(`${name} is above ${max}`);
  return Number(value);
}

export function readConfig(env: Env): Config {
  const rpcUrl = required(env, ENV.rpcUrl);
  try {
    const url = new URL(rpcUrl);
    if (url.protocol !== "http:" && url.protocol !== "https:") throw new Error();
  } catch {
    throw new ConfigError(`${ENV.rpcUrl} is not an http(s) URL`);
  }
  const networks = required(env, ENV.networks)
    .split(",")
    .map((name) => name.trim())
    .filter((name) => name !== "")
    .map((name) => {
      const id = chainIdOf(name);
      if (id === undefined)
        throw new ConfigError(`${ENV.networks} holds a name that is not a network`);
      if (id === SN_MAIN)
        throw new ConfigError(`${ENV.networks} names mainnet, which is never allowed`);
      return id;
    });
  if (networks.length === 0) throw new ConfigError(`${ENV.networks} is empty`);
  const port = env[ENV.port]?.trim() ? Number(positiveOrZero(env, ENV.port)) : DEFAULTS.port;
  if (port > 65535) throw new ConfigError(`${ENV.port} is not a port`);
  const config: Config = {
    rpcUrl,
    funderAddress: felt(env, ENV.address),
    funderKey: new Secret(felt(env, ENV.key)),
    accountClass: felt(env, ENV.accountClass),
    networks: Object.freeze(networks),
    amount: positive(env, ENV.amount, DEFAULTS.amount),
    maxFee: positive(env, ENV.maxFee, DEFAULTS.maxFee),
    dailyBudget: count(env, ENV.dailyBudget, DEFAULTS.dailyBudget, 10_000),
    clientRate: count(env, ENV.clientRate, DEFAULTS.clientRate, 1_000),
    host: env[ENV.host]?.trim() || DEFAULTS.host,
    port,
    stateFile: env[ENV.stateFile]?.trim() || undefined,
    trustProxy: env[ENV.trustProxy]?.trim() === "1",
    origin: env[ENV.origin]?.trim() || "*",
  };
  return Object.freeze(config);
}

function positiveOrZero(env: Env, name: string): bigint {
  const value = env[name]!.trim();
  if (!/^[0-9]{1,5}$/.test(value)) throw new ConfigError(`${name} is not a port`);
  return BigInt(value);
}
