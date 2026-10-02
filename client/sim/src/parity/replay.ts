// The replay of a table against the mirror: each case calls the mirror's function for its `fn`
// and compares the whole `ok` array, or the panic for a case that panics. Every mismatch, an
// unknown `fn`, a count under the table's floor, fails with the case's id.

import { CairoPanic } from "../felt";
import type { Vector } from "./table";

/** A function of the mirror on the felts of a case, returning the felts of its `ok`. */
export type Mirror = (args: readonly bigint[]) => readonly bigint[];

/** One table and the mirror that replays it: adding a table is one entry of `TABLES`. */
export type Entry = {
  file: string;
  /** The fewest cases the table may hold: a table that loses cases fails. */
  floor: number;
  /** The mirror by `fn`; `""` for a table whose lines have no `fn`. */
  fns: Readonly<Record<string, Mirror>>;
};

const hex = (felts: readonly bigint[]): string => `[${felts.map((f) => `0x${f.toString(16)}`)}]`;

/** Replays every case; returns the count of each `fn` (`""` for none). */
export function replay(entry: Entry, vectors: readonly Vector[]): Map<string, number> {
  if (vectors.length < entry.floor) {
    throw new Error(
      `vectors/${entry.file}: ${vectors.length} cases, under the floor ${entry.floor}`,
    );
  }
  const counts = new Map<string, number>();
  for (const vector of vectors) {
    const name = vector.fn ?? "";
    const where = `vectors/${entry.file} id ${vector.id}${vector.fn ? ` (${vector.fn})` : ""}`;
    const mirror = Object.hasOwn(entry.fns, name) ? entry.fns[name] : undefined;
    if (mirror === undefined) throw new Error(`${where}: unknown fn "${name}"`);
    counts.set(name, (counts.get(name) ?? 0) + 1);
    let got: readonly bigint[];
    try {
      got = mirror(vector.case);
    } catch (error) {
      if (vector.ok !== undefined) {
        throw new Error(`${where}: threw where Cairo returned ${hex(vector.ok)}: ${error}`, {
          cause: error,
        });
      }
      if (!(error instanceof CairoPanic)) {
        throw new Error(`${where}: threw ${error}, not a Cairo panic`, { cause: error });
      }
      if (vector.err !== undefined && error.data.join("\n") !== vector.err.join("\n")) {
        throw new Error(`${where}: panicked with [${error.data}], Cairo with [${vector.err}]`, {
          cause: error,
        });
      }
      continue;
    }
    if (vector.ok === undefined) {
      throw new Error(`${where}: returned ${hex(got)} where Cairo panicked`);
    }
    if (got.length !== vector.ok.length || got.some((felt, i) => felt !== vector.ok![i])) {
      throw new Error(
        `${where}: case ${hex(vector.case)}: got ${hex(got)}, Cairo ${hex(vector.ok)}`,
      );
    }
  }
  return counts;
}
