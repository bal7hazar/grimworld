import {
  actionAct,
  runSegment,
  tickTicks,
  trapTrigger,
  writeDone,
  writeGround,
  writeWords,
} from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import { recording, runRecorded } from "./record";
import { contentOf, segment2Row } from "./vectors.testkit";

const CLASSES = { act: actionAct, ticks: tickTicks, trigger: trapTrigger };
const CONTENT = contentOf("segment2.jsonl");

describe("the recording wrapper of the classes (§7.2)", () => {
  it("keeps each ticks call's input and output and each act call, in order, the run unchanged", () => {
    // segment2.jsonl row 2: a skill (one act call) then a wait, with ticks after each
    const row = segment2Row(2);
    const segment = { ...row, content: CONTENT };
    const plain = runSegment(segment, CLASSES);
    const recorded = runRecorded(segment, CLASSES);
    const felts = (r: typeof plain) => [
      ...writeWords(r.words),
      ...writeGround(r.ground),
      ...writeDone(r.done),
    ];
    expect(felts(recorded)).toEqual(felts(plain));
    expect(recorded.acts.map((a) => a.call.action)).toEqual([row.actions[0]]);
    // As many ticks calls as the row recorded
    expect(recorded.ticks.length).toBe(row.calls.filter((c) => c.kind === "ticks").length);
    for (const { call, out } of recorded.ticks) {
      expect(writeWords(tickTicks(call).words)).toEqual(writeWords(out.words));
    }
  });

  it("passes the results through: the wrapped class's own", () => {
    const rec = recording(CLASSES);
    const row = segment2Row(12);
    runSegment({ ...row, content: CONTENT }, rec.classes);
    expect(rec.ticks).toHaveLength(2);
    expect(rec.acts).toHaveLength(0);
  });
});
