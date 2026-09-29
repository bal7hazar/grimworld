/**
 * The account provider (ADR-0005 §1): the game's only way to act as a player. Four operations,
 * and types of our own: no type of a vendor's library leaves this module, so that the burner of
 * the MVP can be replaced (a Controller, an account of our own, a paymaster in the path) without
 * touching the game. Nothing here says who pays for an execution (D-137): a provider may send
 * directly or route through a paymaster, and the game does not know.
 */

/** One call to a contract of the game: its address, the entrypoint's name, the calldata as felts. */
export interface Call {
  readonly to: string;
  readonly entrypoint: string;
  readonly calldata: readonly (string | bigint | number)[];
}

/** The player's account once created or restored: the address the contracts see as the caller. */
export interface AccountHandle {
  readonly address: string;
}

/** What `execute` returns, to ask `status` about. Opaque to the game. */
export type ExecutionId = string & { readonly __brand: "ExecutionId" };

/**
 * Where an execution stands:
 * - `pending`: sent, not settled yet (it may already show in a pre-confirmed state);
 * - `succeeded`: settled, and it ran;
 * - `failed`: it ran and failed, every effect undone (a call refused before it is sent rejects
 *   `execute` instead);
 * - `unknown`: the network does not know it (never received, or dropped).
 */
export type ExecutionStatus = "pending" | "succeeded" | "failed" | "unknown";

export interface AccountProvider {
  /** Restores the account kept on this device, or creates one. Idempotent. */
  createOrRestore(): Promise<AccountHandle>;
  /** Sends the calls as one execution, without any prompt. Needs `createOrRestore` first. */
  execute(calls: readonly Call[]): Promise<ExecutionId>;
  status(id: ExecutionId): Promise<ExecutionStatus>;
  /** Ends the session: `execute` refuses until `createOrRestore` again. */
  signOut(): Promise<void>;
}

/**
 * Why an operation failed. The messages are neutral (design/11, D-100): a player may one day read
 * them, so they carry no word of the chain.
 */
export type AccountErrorCode = "not-ready" | "unavailable" | "refused" | "invalid";

const MESSAGES: Record<AccountErrorCode, string> = {
  "not-ready": "No player is connected.",
  unavailable: "The game cannot be reached right now. Please try again shortly.",
  refused: "That action was not accepted.",
  invalid: "That action is not possible.",
};

export class AccountError extends Error {
  readonly code: AccountErrorCode;

  constructor(code: AccountErrorCode, options?: { cause?: unknown }) {
    super(MESSAGES[code], options);
    this.name = "AccountError";
    this.code = code;
  }
}

/** The device's storage for the key: the subset of Web Storage used, so `localStorage` fits. */
export interface KeyStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}
