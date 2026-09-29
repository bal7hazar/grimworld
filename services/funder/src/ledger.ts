import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";

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

/** A nonce of the funding account that a funding used: no other funding signs until it is consumed. */
export interface Hold {
  /** The nonce, as a decimal string. */
  readonly nonce: string;
  readonly transaction?: string;
  /** When the funding was signed, in milliseconds. */
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
}

interface State {
  grants: Record<string, Grant>;
  days: Record<string, number>;
  clients: Record<string, number[]>;
  hold?: Hold;
}

function ledgerOver(state: State, save: () => void): Ledger {
  return {
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
  return ledgerOver(empty(), () => undefined);
}

/**
 * A ledger written to `path` after every change (a new file, then renamed over the old one). One
 * service at a time per file and per funding account: nothing coordinates two processes.
 */
export function fileLedger(path: string): Ledger {
  const state: State = existsSync(path)
    ? { ...empty(), ...(JSON.parse(readFileSync(path, "utf8")) as Partial<State>) }
    : empty();
  return ledgerOver(state, () => {
    writeFileSync(`${path}.next`, JSON.stringify(state));
    renameSync(`${path}.next`, path);
  });
}
