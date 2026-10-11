// The replayer's own failures (CLI-02g-A, D-255): a replay is sound only if it checks every digest
// AND consumes every recorded call. Real `segment2.jsonl` rows, their recorded calls altered: a
// call the row lacks, a call of another kind and a recorded call left unused each fail the row.

import { describe, expect, it } from "vitest";
import { run } from "../segment";
import type { Segment } from "../segment";
import {
  Felts,
  readAction,
  readArea,
  readCall,
  readContent,
  readGround,
  readWords,
} from "../segment/serde";
import type { Call } from "../segment/serde";
import { replayer } from "./replayer";
import { readTable } from "./table";

const TABLE = readTable("segment2.jsonl");
const CONTENT = readContent(new Felts(TABLE[0]!.ok!));

/** Row `id`'s segment and its recorded calls. */
function row(id: number): { segment: Segment; calls: Call[] } {
  const read = new Felts(TABLE[id]!.case);
  const words = readWords(read);
  const area = readArea(read);
  const level = read.u8();
  const ground = readGround(read);
  const [owed, weight] = [read.u8(), read.u8()];
  const actions = read.span(() => readAction(read));
  const calls = read.span(() => readCall(read));
  read.end();
  return {
    segment: { words, content: CONTENT, area, level, ground, owed, weight, actions },
    calls,
  };
}

/** `run` on `segment` with `calls` replayed, `end` included. */
function replay(segment: Segment, calls: readonly Call[]): void {
  const classes = replayer(calls);
  run(segment, classes);
  classes.end();
}

describe("the replayer of the recorded calls", () => {
  // Row 1 (combat) makes one act call, row 15 none; `ticked` is the first row to start with a ticks call
  const [combat, quiet] = [row(1), row(15)];
  const ticked = TABLE.slice(1)
    .map((vector) => row(vector.id))
    .find(({ calls }) => calls[0]?.kind === "ticks")!;

  it("replays the rows as recorded", () => {
    expect(combat.calls.map((call) => call.kind)).toEqual(["act"]);
    expect(ticked.calls[0]!.kind).toBe("ticks");
    expect(quiet.calls).toEqual([]);
    for (const { segment, calls } of [combat, ticked, quiet]) replay(segment, calls);
  });

  it("fails a row that asks for a call the row lacks", () => {
    expect(() => replay(combat.segment, [])).toThrow(
      "call 0 (act): 0 calls recorded, run made more",
    );
  });

  it("fails a row that asks for a call of another kind", () => {
    expect(() => replay(combat.segment, [ticked.calls[0]!])).toThrow(
      "call 0 (act): Cairo made a ticks call",
    );
  });

  it("fails a row that leaves a recorded call unused", () => {
    expect(() => replay(quiet.segment, combat.calls)).toThrow(
      "call 0 (act): recorded, run did not make it",
    );
    expect(() => replay(combat.segment, [...combat.calls, ...ticked.calls])).toThrow(
      "call 1 (ticks): recorded, run did not make it",
    );
  });
});
