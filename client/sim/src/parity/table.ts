// The reader of the vector tables (D-140, SPK-4): the JSON-lines files the Cairo tests print, read
// in place in `contracts/logic/vectors/` (`check.py` holds them equal to the code in CI, so a copy
// here would only be a second pin). The only I/O of `client/sim/src`, run by the tests in Node.
//
// One line per case: `{"id", "fn"?, "case", "ok"}`, every felt in hexadecimal, a negative integer
// as `P − |v|`. A case whose call panics carries `err` (its panic data, each a felt in hexadecimal
// or a short string) instead of `ok`, or `"ok": false` when the table records the refusal without
// its data. Anything else fails loudly, naming the table and the line.

import { existsSync, readFileSync } from "node:fs";
import { P, readShortString } from "../felt";

/** One case of a table. */
export type Vector = {
  id: number;
  /** The function called, for a table of several; absent for a table of one. */
  fn?: string;
  case: bigint[];
  /** What Cairo returned; absent when the call panicked. */
  ok?: bigint[];
  /** The panic data as short strings; absent when the table does not record it. */
  err?: string[];
};

const KEYS = new Set(["id", "fn", "case", "ok", "err"]);
const HEX = /^0x[0-9a-f]+$/;

function fail(name: string, line: number, why: string): never {
  throw new Error(`vectors/${name} line ${line}: ${why}`);
}

function felts(name: string, line: number, key: string, value: unknown): bigint[] {
  if (!Array.isArray(value)) fail(name, line, `"${key}" is not an array`);
  return value.map((item: unknown) => {
    if (typeof item !== "string" || !HEX.test(item)) {
      fail(name, line, `"${key}" holds ${JSON.stringify(item)}, not a felt in hexadecimal`);
    }
    const felt = BigInt(item);
    if (felt >= P) fail(name, line, `"${key}" holds ${item}, not below P`);
    return felt;
  });
}

function panicData(name: string, line: number, value: unknown): string[] {
  if (!Array.isArray(value)) fail(name, line, `"err" is not an array`);
  return value.map((item: unknown) => {
    if (typeof item !== "string") fail(name, line, `"err" holds ${JSON.stringify(item)}`);
    if (!HEX.test(item)) return item;
    const text = readShortString(BigInt(item));
    if (text === undefined) fail(name, line, `"err" holds ${item}, not a short string`);
    return text;
  });
}

/** The cases of a table from its text: ids consecutive from 0, each line well formed. */
export function parseTable(name: string, text: string): Vector[] {
  const lines = text.split("\n");
  if (lines.at(-1) === "") lines.pop();
  if (lines.length === 0) throw new Error(`vectors/${name}: empty table`);
  return lines.map((raw, index) => {
    const line = index + 1;
    let row: unknown;
    try {
      row = JSON.parse(raw);
    } catch {
      fail(name, line, "not JSON");
    }
    if (typeof row !== "object" || row === null || Array.isArray(row)) {
      fail(name, line, "not an object");
    }
    const record = row as Record<string, unknown>;
    for (const key of Object.keys(record)) {
      if (!KEYS.has(key)) fail(name, line, `unknown key "${key}"`);
    }
    if (record.id !== index) fail(name, line, `id ${JSON.stringify(record.id)}, expected ${index}`);
    const vector: Vector = { id: index, case: felts(name, line, "case", record.case) };
    if ("fn" in record) {
      if (typeof record.fn !== "string" || record.fn === "") fail(name, line, `"fn" is not a name`);
      vector.fn = record.fn;
    }
    const panics = record.ok === false || "err" in record;
    if (panics) {
      if (record.ok !== undefined && record.ok !== false) fail(name, line, `both "ok" and "err"`);
      if ("err" in record) vector.err = panicData(name, line, record.err);
    } else if ("ok" in record) {
      vector.ok = felts(name, line, "ok", record.ok);
    } else {
      fail(name, line, `neither "ok" nor "err"`);
    }
    return vector;
  });
}

/** The folder of the tables: `contracts/logic/vectors/`, found above this file. */
function folder(): URL {
  for (let dir = new URL(".", import.meta.url); ; dir = new URL("..", dir)) {
    const vectors = new URL("contracts/logic/vectors/", dir);
    if (existsSync(vectors)) return vectors;
    if (dir.pathname === "/") throw new Error("contracts/logic/vectors/ not found");
  }
}

/** The cases of the table `name` (`window.jsonl`, …), read in place. */
export function readTable(name: string): Vector[] {
  const path = new URL(name, folder());
  if (!existsSync(path)) throw new Error(`vectors/${name}: no such table`);
  return parseTable(name, readFileSync(path, "utf8"));
}
