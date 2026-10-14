/**
 * The combat model's tests read track game's vector tables in place (`contracts/logic/vectors/`,
 * D-140): RV-03b's `act.jsonl`, RV-03c's `tick.jsonl` and RV-02's `segment2.jsonl`, each row's case
 * decoded with client/sim's codecs. Test support only: no screen imports it.
 */

import { readFileSync } from "node:fs";
import {
  type Action,
  type Area,
  type Call,
  type Content,
  Felts,
  type Ground,
  type SegmentBoard,
  type Words,
  readAction,
  readArea,
  readBoard,
  readCall,
  readContent,
  readGround,
  readWords,
} from "@grimworld/sim";

type Row = { id: number; fn?: string; case: string[]; ok?: string[] };

const cache = new Map<string, Row[]>();

/** The rows of a table, by id. */
export function rows(file: string): Row[] {
  let read = cache.get(file);
  if (read === undefined) {
    const url = new URL(`../../../../contracts/logic/vectors/${file}`, import.meta.url);
    read = readFileSync(url, "utf8")
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line) as Row);
    cache.set(file, read);
  }
  return read;
}

const felts = (values: readonly string[]): Felts => new Felts(values.map(BigInt));

/** A table's content: its row 0's `ok`. */
export function contentOf(file: string): Content {
  return contentAt(file, 0);
}

const contents = new Map<string, Content>();

/**
 * The content row `id` of `file` reads: the `ok` of its last `content` row at or before it
 * (client/sim's `contentRow`; `tick.jsonl` 131, RV-03d), decoded once.
 */
export function contentAt(file: string, id: number): Content {
  let at = id;
  while (rows(file)[at]!.fn !== "content") at -= 1;
  const key = `${file} ${at}`;
  let content = contents.get(key);
  if (content === undefined) {
    const read = felts(rows(file)[at]!.ok!);
    contents.set(key, (content = readContent(read)));
    read.end();
  }
  return content;
}

/** A `tick.jsonl` row: `TickLibrary::ticks`' inputs. */
export interface TickRow {
  readonly id: number;
  readonly words: Words;
  readonly board: SegmentBoard;
  readonly level: number;
  readonly ground: Ground;
  readonly n: number;
}

export function tickRow(id: number): TickRow {
  const row = rows("tick.jsonl")[id]!;
  if (row.fn !== "ticks") throw new Error(`tick.jsonl row ${id} is a ${row.fn} row`);
  const read = felts(row.case);
  const words = readWords(read);
  const board = readBoard(read);
  const level = read.u8();
  const ground = readGround(read);
  const n = read.u8();
  read.end();
  return { id, words, board, level, ground, n };
}

/** The ids of every `ticks` row of `tick.jsonl`. */
export const tickIds = (): number[] =>
  rows("tick.jsonl")
    .filter((r) => r.fn === "ticks")
    .map((r) => r.id);

/** An `act.jsonl` `act` row: `ActionLibrary::act`'s inputs. */
export interface ActRow {
  readonly id: number;
  readonly words: Words;
  readonly board: SegmentBoard;
  readonly ground: Ground;
  readonly action: Action;
}

export function actRow(id: number): ActRow {
  const row = rows("act.jsonl")[id]!;
  if (row.fn !== "act") throw new Error(`act.jsonl row ${id} is a ${row.fn} row`);
  const read = felts(row.case);
  const words = readWords(read);
  const board = readBoard(read);
  const ground = readGround(read);
  const action = readAction(read);
  read.end();
  return { id, words, board, ground, action };
}

export const actIds = (): number[] =>
  rows("act.jsonl")
    .filter((r) => r.fn === "act")
    .map((r) => r.id);

/** A `segment2.jsonl` row: a segment's inputs (the calls it recorded aside). */
export interface Segment2Row {
  readonly words: Words;
  readonly area: Area;
  readonly level: number;
  readonly ground: Ground;
  readonly owed: number;
  readonly weight: number;
  readonly actions: Action[];
  readonly calls: Call[];
}

export function segment2Row(id: number): Segment2Row {
  const read = felts(rows("segment2.jsonl")[id]!.case);
  const words = readWords(read);
  const area = readArea(read);
  const level = read.u8();
  const ground = readGround(read);
  const [owed, weight] = [read.u8(), read.u8()];
  const actions = read.span(() => readAction(read));
  const calls = read.span(() => readCall(read));
  read.end();
  return { words, area, level, ground, owed, weight, actions, calls };
}

/** A copy of words with another clock. */
export const atClock = (words: Words, clock: number): Words => ({ ...words, clock });
