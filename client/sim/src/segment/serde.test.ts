// The codecs of `segment/serde.ts` on `segment2.jsonl`'s own felts (CLI-02g-A): every row's case
// and outcome decoded and encoded again, felt for felt, and each member's load and store.

import { describe, expect, it } from "vitest";
import { readTable } from "../parity/table";
import {
  Felts,
  readAction,
  readArea,
  readCall,
  readContent,
  readDone,
  readGround,
  readWords,
  writeAction,
  writeArea,
  writeCall,
  writeContent,
  writeDone,
  writeGround,
  writeWords,
} from "./serde";
import { load as loadGoblin, store as storeGoblin } from "./goblin";
import { load, sheets, store } from "./words";

const TABLE = readTable("segment2.jsonl");
const CONTENT = readContent(new Felts(TABLE[0]!.ok!));

describe("the segment2 codecs", () => {
  it("round-trips the table's content (row 0, 263 felts)", () => {
    const read = new Felts(TABLE[0]!.ok!);
    const content = readContent(read);
    read.end();
    expect(TABLE[0]!.ok!.length).toBe(263);
    expect(writeContent(content)).toEqual(TABLE[0]!.ok);
  });

  for (const vector of TABLE.slice(1)) {
    it(`round-trips row ${vector.id} (${vector.fn}): its case and its outcome`, () => {
      const read = new Felts(vector.case);
      const words = readWords(read);
      const area = readArea(read);
      const level = read.u8();
      const ground = readGround(read);
      const [owed, weight] = [read.u8(), read.u8()];
      const actions = read.span(() => readAction(read));
      const calls = read.span(() => readCall(read));
      read.end();
      expect([
        ...writeWords(words),
        ...writeArea(area),
        BigInt(level),
        ...writeGround(ground),
        BigInt(owed),
        BigInt(weight),
        BigInt(actions.length),
        ...actions.flatMap(writeAction),
        BigInt(calls.length),
        ...calls.flatMap(writeCall),
      ]).toEqual(vector.case);
      const out = new Felts(vector.ok!);
      const after = readWords(out);
      const left = readGround(out);
      const done = readDone(out);
      out.end();
      expect([...writeWords(after), ...writeGround(left), ...writeDone(done)]).toEqual(vector.ok);
      // A member's and a goblin's load and store leave its words as they are: in the case, in the
      // words after and in every recorded call
      const index = sheets(CONTENT);
      const everywhere = [words, after, ...calls.map((call) => call.words)];
      for (const each of everywhere) {
        for (const member of each.members) expect(store(load(member, index))).toEqual(member);
        for (const goblin of each.goblins) {
          expect(storeGoblin(loadGoblin(goblin, index))).toEqual(goblin);
        }
      }
    });
  }
});
