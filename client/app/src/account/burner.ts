import {
  AccountError,
  type AccountHandle,
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
  readonly v: 1;
  readonly key: string;
  readonly address: string;
  /** The account was seen deployed: no need to ask the chain or the funder again. */
  readonly ready: boolean;
}

function read(storage: KeyStorage): Kept | undefined {
  const raw = storage.getItem(STORAGE_KEY);
  if (raw === null) return undefined;
  try {
    const kept = JSON.parse(raw) as Partial<Kept>;
    if (kept.v === 1 && typeof kept.key === "string" && typeof kept.address === "string") {
      return { v: 1, key: kept.key, address: kept.address, ready: kept.ready === true };
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
  let opening: Promise<AccountHandle> | undefined;
  // Executions go one after the other: a burner's executions are ordered, and two sent at once
  // would race for the same place in that order.
  let queue: Promise<unknown> = Promise.resolve();

  async function open(): Promise<AccountHandle> {
    let kept = read(storage);
    if (kept === undefined) {
      const key = chain.newKey();
      // Kept before the account exists: an interruption resumes with the same key and address,
      // and the funding is never spent twice.
      kept = { v: 1, key, address: chain.derive(key).address, ready: false };
      storage.setItem(STORAGE_KEY, JSON.stringify(kept));
    }
    if (!kept.ready) {
      if (!(await chain.isDeployed(kept.address))) {
        await funder.provide(chain.derive(kept.key).publicKey, kept.address);
      }
      kept = { ...kept, ready: true };
      storage.setItem(STORAGE_KEY, JSON.stringify(kept));
    }
    session = { key: kept.key, address: kept.address };
    return { address: kept.address };
  }

  return {
    createOrRestore() {
      if (session) return Promise.resolve({ address: session.address });
      opening ??= open()
        .catch((error: unknown) => {
          throw wrap(error);
        })
        .finally(() => {
          opening = undefined;
        });
      return opening;
    },

    execute(calls) {
      const current = session;
      if (!current) return Promise.reject(new AccountError("not-ready"));
      if (calls.length === 0) return Promise.reject(new AccountError("invalid"));
      const sent = queue.then(() => chain.send(current.key, current.address, calls));
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
      // The key stays on the device (ADR-0005 §3: losing it loses the account); only the session
      // ends.
      session = undefined;
    },
  };
}
