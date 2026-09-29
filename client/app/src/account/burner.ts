import {
  AccountError,
  type AccountProvider,
  type Call,
  type ExecutionId,
  type ExecutionStatus,
  type KeyStorage,
} from "./types";

/**
 * The burner (ADR-0005 §2, stage A): a key generated on the device and kept in its storage, an
 * account deployed and funded by the game, calls signed by the key without any prompt. What a
 * burner is not (§3): a production account. Clearing the device's storage loses it.
 *
 * The logic here knows no chain library: the chain is reached through `BurnerChain` and the game's
 * funding through `Funder` (starknet.ts implements both; the unit tests use a fake chain).
 */

/** What the burner needs from the chain, for one key. */
export interface BurnerChain {
  /**
   * What the kept account is bound to: the network and the account class. An account's address
   * depends on the class, and exists only on the network that deployed it.
   */
  binding(): Promise<string>;
  /** A new private key, from a secure random source. */
  newKey(): string;
  /** The public key and the account's address for a private key (the address before deployment). */
  derive(privateKey: string): { publicKey: string; address: string };
  isDeployed(address: string): Promise<boolean>;
  /** Signs and sends the calls as one execution; resolves with its id once the node received it. */
  send(privateKey: string, address: string, calls: readonly Call[]): Promise<string>;
  status(id: string): Promise<ExecutionStatus>;
}

/**
 * The game's side of creating a burner: deploys the account of a public key and funds it (D-137:
 * the burner sends directly, the game funds it). Resolves once the account can send. Idempotent:
 * an account already deployed is not deployed again.
 */
export interface Funder {
  provide(publicKey: string, address: string): Promise<void>;
}

/** Where the burner lives in the device's storage. */
export const STORAGE_KEY = "grimworld.account";

interface Kept {
  readonly v: 2;
  readonly key: string;
  /** `BurnerChain.binding()` when the address was derived. */
  readonly binding: string;
  readonly address: string;
}

/** The kept record; a record of an earlier version keeps its key and is bound again. */
function read(
  storage: KeyStorage,
): { key: string; binding?: string; address?: string } | undefined {
  const raw = storage.getItem(STORAGE_KEY);
  if (raw === null) return undefined;
  try {
    const kept = JSON.parse(raw) as Partial<Kept>;
    if (typeof kept.key === "string") {
      return {
        key: kept.key,
        binding: typeof kept.binding === "string" ? kept.binding : undefined,
        address: typeof kept.address === "string" ? kept.address : undefined,
      };
    }
  } catch {
    // unreadable: as if nothing were kept
  }
  return undefined;
}

function wrap(error: unknown): AccountError {
  return error instanceof AccountError ? error : new AccountError("unavailable", { cause: error });
}

export interface BurnerOptions {
  chain: BurnerChain;
  funder: Funder;
  /** The device's storage; `globalThis.localStorage` by default. */
  storage?: KeyStorage;
}

export function createBurnerProvider(options: BurnerOptions): AccountProvider {
  const { chain, funder } = options;
  const storage = options.storage ?? globalThis.localStorage;
  let session: { key: string; address: string } | undefined;
  // Every sign-out starts a new generation: an open begun before it cannot open a session after it
  // (fix loop 1, F-2).
  let generation = 0;
  // The work of making the kept account usable, shared by every caller while it runs, across a
  // sign-out too: the funding is never asked twice at once.
  let preparing: Promise<Kept> | undefined;
  // Executions go one after the other: a burner's executions are ordered, and two sent at once
  // would race for the same place in that order.
  let queue: Promise<unknown> = Promise.resolve();

  function keep(kept: Kept): Kept {
    storage.setItem(STORAGE_KEY, JSON.stringify(kept));
    return kept;
  }

  /**
   * Every new session checks the account on the chain (fix loop 1, F-3): a local node that was
   * reset has lost it, and the same key is deployed and funded again. The kept record is bound to
   * the network and the class; under another binding the key is kept and its address derived again.
   */
  async function prepare(): Promise<Kept> {
    const binding = await chain.binding();
    const found = read(storage);
    // A new key is kept before its account exists: an interruption resumes with the same key.
    const key = found?.key ?? chain.newKey();
    const { publicKey, address } = chain.derive(key);
    let kept: Kept = { v: 2, key, binding, address };
    if (found?.binding !== binding || found.address !== address) kept = keep(kept);
    if (!(await chain.isDeployed(address))) await funder.provide(publicKey, address);
    return kept;
  }

  return {
    async createOrRestore() {
      if (session) return { address: session.address };
      const opened = generation;
      preparing ??= prepare().finally(() => {
        preparing = undefined;
      });
      let kept: Kept;
      try {
        kept = await preparing;
      } catch (error) {
        throw wrap(error);
      }
      // Signed out while it was being prepared: the account stays kept, no session opens.
      if (opened !== generation) throw new AccountError("not-ready");
      session ??= { key: kept.key, address: kept.address };
      return { address: session.address };
    },

    execute(calls) {
      const current = session;
      if (!current) return Promise.reject(new AccountError("not-ready"));
      if (calls.length === 0) return Promise.reject(new AccountError("invalid"));
      const sent = queue.then(() => {
        // Signed out while waiting for its turn: nothing is sent.
        if (session !== current) throw new AccountError("not-ready");
        return chain.send(current.key, current.address, calls);
      });
      queue = sent.catch(() => undefined);
      return sent.then(
        (id) => id as ExecutionId,
        (error: unknown) => {
          throw wrap(error);
        },
      );
    },

    async status(id) {
      try {
        return await chain.status(id);
      } catch (error) {
        throw wrap(error);
      }
    },

    async signOut() {
      // The key stays on the device (ADR-0005 §3: losing it loses the account); the session ends,
      // and so does any open still running.
      generation++;
      session = undefined;
    },
  };
}
