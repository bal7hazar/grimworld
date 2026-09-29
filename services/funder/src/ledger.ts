import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";

/**
 * What the service remembers: the funding of each key, and how many fundings each day (UTC) has
 * spent of the budget. In memory, or also in a file, so that a restart forgets neither which keys
 * were funded nor the day's spending. Public keys and addresses only: nothing secret is kept.
 */

export interface Grant {
  readonly address: string;
  /** The execution's id, once sent. */
  readonly transaction?: string;
  readonly status: "sending" | "pending" | "succeeded";
}

export interface Ledger {
  grant(publicKey: string): Grant | undefined;
  setGrant(publicKey: string, grant: Grant | undefined): void;
  spent(day: string): number;
  spend(day: string, delta: 1 | -1): void;
}

interface State {
  grants: Record<string, Grant>;
  days: Record<string, number>;
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
  };
}

function yesterday(day: string): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
}

export function memoryLedger(): Ledger {
  return ledgerOver({ grants: {}, days: {} }, () => undefined);
}

/** A ledger written to `path` after every change (a new file, then renamed over the old one). */
export function fileLedger(path: string): Ledger {
  const state: State = existsSync(path)
    ? (JSON.parse(readFileSync(path, "utf8")) as State)
    : { grants: {}, days: {} };
  state.grants ??= {};
  state.days ??= {};
  return ledgerOver(state, () => {
    writeFileSync(`${path}.next`, JSON.stringify(state));
    renameSync(`${path}.next`, path);
  });
}
