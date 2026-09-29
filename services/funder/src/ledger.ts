import { randomUUID } from "node:crypto";
import { existsSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";

/**
 * What the service remembers: the funding of each key, how many fundings each day (UTC) has
 * signed, when each client's recent fundings were signed, and the funding account's nonce still
 * held by a funding. In memory, or also in a file, so that a restart forgets none of it (fix
 * loop 1, F-3). Public keys, addresses, client addresses and counts only: nothing secret is kept.
 */

export interface Grant {
  readonly address: string;
  /** The execution's id, once sent. */
  readonly transaction?: string;
  readonly status: "sending" | "pending" | "succeeded";
}

/**
 * A nonce of the funding account and the one execution signed with it, kept before that execution
 * is handed to the node (fix loop 2): no other execution is signed until the nonce is consumed,
 * and while the node does not know this one, it is handed again as it is.
 */
export interface Hold {
  /** The nonce, as a decimal string. */
  readonly nonce: string;
  readonly transaction: string;
  /** The signed execution (`Signed.payload`): public, no key in it. */
  readonly payload: string;
  /** Whose funding it is: a handing again counts against this client's rate. */
  readonly client: string;
  /** When it was last handed to the node, in milliseconds. */
  readonly at: number;
}

export interface Ledger {
  grant(publicKey: string): Grant | undefined;
  setGrant(publicKey: string, grant: Grant | undefined): void;
  spent(day: string): number;
  spend(day: string, delta: 1 | -1): void;
  /** The times of the client's fundings after `since`; older ones are forgotten. */
  times(client: string, since: number): readonly number[];
  addTime(client: string, at: number): void;
  removeTime(client: string, at: number): void;
  hold(): Hold | undefined;
  setHold(hold: Hold | undefined): void;
  /** Lets another process open the file. */
  close(): void;
}

interface State {
  grants: Record<string, Grant>;
  days: Record<string, number>;
  clients: Record<string, number[]>;
  hold?: Hold;
}

function ledgerOver(state: State, save: () => void, close: () => void): Ledger {
  return {
    close,
    grant: (publicKey) => state.grants[publicKey],
    setGrant(publicKey, grant) {
      if (grant) state.grants[publicKey] = grant;
      else delete state.grants[publicKey];
      save();
    },
    spent: (day) => state.days[day] ?? 0,
    spend(day, delta) {
      // Only today and yesterday are kept: older days can never be asked again.
      const today = state.days[day] ?? 0;
      state.days = Object.fromEntries(
        Object.entries(state.days).filter(([d]) => d >= yesterday(day)),
      );
      state.days[day] = Math.max(0, today + delta);
      save();
    },
    times(client, since) {
      // Every client's old times go at each look: the file holds the last window only.
      for (const [name, times] of Object.entries(state.clients)) {
        const kept = times.filter((t) => t > since);
        if (kept.length > 0) state.clients[name] = kept;
        else delete state.clients[name];
      }
      return state.clients[client] ?? [];
    },
    addTime(client, at) {
      state.clients[client] = [...(state.clients[client] ?? []), at];
      save();
    },
    removeTime(client, at) {
      const times = state.clients[client] ?? [];
      const index = times.indexOf(at);
      if (index >= 0) times.splice(index, 1);
      if (times.length === 0) delete state.clients[client];
      save();
    },
    hold: () => state.hold,
    setHold(hold) {
      if (hold) state.hold = hold;
      else delete state.hold;
      save();
    },
  };
}

function yesterday(day: string): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
}

function empty(): State {
  return { grants: {}, days: {}, clients: {} };
}

/** For development and tests only: a restart forgets everything (`FUNDER_EPHEMERAL=1`). */
export function memoryLedger(): Ledger {
  return ledgerOver(
    empty(),
    () => undefined,
    () => undefined,
  );
}

/** Another process holds the file: two services on one ledger could hand two executions one nonce. */
export class LedgerLocked extends Error {
  constructor(lockPath: string) {
    super(
      `the state file is locked by another service, or by one that stopped without closing it ` +
        `(${lockPath}): if no service runs on this host, remove the lock (README)`,
    );
    this.name = "LedgerLocked";
  }
}

/**
 * Takes `<path>.lock` by creating it exclusively (`O_CREAT | O_EXCL`, flag `wx`): on a local file
 * system the kernel lets exactly one creator succeed, whatever the timing, so at most one process
 * owns the ledger.
 *
 * A lock that exists is never taken over, even when the process named in it has stopped (fix
 * loop 3, F-5): a takeover is a read, a check and a removal, and another starter can take over
 * between them; there is no way to make those three one step here (Node has no `flock`). The
 * service fails closed instead: it refuses to start, and the operator removes the lock once no
 * service runs on the host (README). A service that exits normally, or on an error, removes it.
 */
function lock(path: string): () => void {
  const lockPath = `${path}.lock`;
  // The owner's mark: the process and a random token, so that a close never removes a lock this
  // process does not own (one an operator removed and another service took since).
  const mark = `${process.pid} ${randomUUID()}`;
  try {
    writeFileSync(lockPath, mark, { flag: "wx" });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "EEXIST") throw new LedgerLocked(lockPath);
    throw error;
  }
  let open = true;
  return () => {
    if (!open) return;
    open = false;
    try {
      if (readFileSync(lockPath, "utf8") === mark) unlinkSync(lockPath);
    } catch {
      // Already gone.
    }
  };
}

/**
 * A ledger written to `path` after every change (a new file, then renamed over the old one), open
 * in one process at a time (`<path>.lock`). The deployment guarantees what the code cannot see
 * (README): one host, the state file on a local disk, one state file per funding account.
 */
export function fileLedger(path: string): Ledger {
  const unlock = lock(path);
  const state: State = existsSync(path)
    ? { ...empty(), ...(JSON.parse(readFileSync(path, "utf8")) as Partial<State>) }
    : empty();
  return ledgerOver(
    state,
    () => {
      writeFileSync(`${path}.next`, JSON.stringify(state));
      renameSync(`${path}.next`, path);
    },
    unlock,
  );
}
