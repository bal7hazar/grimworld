import { describe, expect, it } from "vitest";
import { MAX_ACTIONS, type PlayAction } from "../preview/actions";
import { Stop } from "../preview/trace";
import { type Batch, actionsOf, add, afterPreview, afterSend, isFull, roomOf } from "./batch";

const move = (direction: number): PlayAction => ({ kind: "move", direction });
const WAIT: PlayAction = { kind: "wait" };
const step = (direction: number) => ({ action: move(direction), path: true });
const one = (action: PlayAction) => ({ action, path: false });

describe("the batch's room", () => {
  it("takes 10 actions, the encoding's bound, and an 11th waits", () => {
    let batch: Batch = [];
    for (let i = 0; i < MAX_ACTIONS; i++) batch = add(batch, [WAIT]);
    expect(batch).toHaveLength(10);
    expect(roomOf(batch)).toBe(0);
    expect(isFull(batch)).toBe(true);
    expect(add(batch, [WAIT])).toBe(batch);
  });

  it("cuts a path to the batch's room, its steps marked", () => {
    const batch = add([one(WAIT), one(WAIT), one(WAIT)], [0, 1, 2, 3, 4, 5, 0, 1].map(move), {
      path: true,
    });
    expect(batch).toHaveLength(10);
    expect(batch.slice(3)).toEqual([0, 1, 2, 3, 4, 5, 0].map(step));
  });

  it("is full when the preview stopped at the weight, whatever its length", () => {
    const batch: Batch = [one(WAIT), one(move(0))];
    expect(isFull(batch, Stop.Weight)).toBe(true);
    expect(add(batch, [WAIT], { stop: Stop.Weight })).toBe(batch);
    expect(isFull(batch, Stop.None)).toBe(false);
  });
});

describe("where a batch ends", () => {
  const batch: Batch = [one(WAIT), step(0), step(1), one({ kind: "turn", direction: 3 }), step(2)];

  it("keeps the action unplayed for the weight: it opens the next batch", () => {
    // Played 2, the third (a path's step) did not fit: it is kept, the later steps are dropped
    expect(afterSend(batch, { played: 2, stop: Stop.Weight })).toEqual({
      kind: "next",
      planned: [step(1), one({ kind: "turn", direction: 3 })],
    });
  });

  it("drops the refused action and every one after it (Stop.Invalid)", () => {
    expect(afterPreview(batch, { played: 2, stop: Stop.Invalid })).toEqual(batch.slice(0, 2));
    // Refused before its first action: nothing stays
    expect(afterPreview(batch, { played: 0, stop: Stop.Invalid })).toEqual([]);
    expect(afterSend(batch, { played: 2, stop: Stop.Invalid })).toEqual({
      kind: "next",
      planned: [],
    });
    // Any other stop leaves the preview's batch as it is
    expect(afterPreview(batch, { played: 2, stop: Stop.Weight })).toBe(batch);
  });

  it.each([Stop.Sequence, Stop.Version])(
    "keeps every action and reads again on an admission refusal (stop %i)",
    (stop) => {
      expect(afterSend(batch, { played: 0, stop })).toEqual({ kind: "reread", planned: batch });
      expect(afterPreview(batch, { played: 0, stop })).toBe(batch);
    },
  );

  it("ends the instance on a defeat or a closing", () => {
    expect(afterSend(batch, { played: 3, stop: Stop.Defeated })).toEqual({ kind: "closed" });
    expect(afterSend(batch, { played: 0, stop: Stop.Closed })).toEqual({ kind: "closed" });
    expect(afterSend(batch, { played: 5, stop: Stop.None, closed: 1 })).toEqual({
      kind: "closed",
    });
    expect(afterSend(batch, { played: 5, stop: Stop.None, defeated: true })).toEqual({
      kind: "closed",
    });
  });

  it("drops the path's steps not played after a send, and keeps the rest", () => {
    expect(afterSend(batch, { played: 5, stop: Stop.None })).toEqual({ kind: "next", planned: [] });
    expect(afterSend(batch, { played: 1, stop: Stop.None })).toEqual({
      kind: "next",
      planned: [one({ kind: "turn", direction: 3 })],
    });
    expect(actionsOf(batch)).toEqual([WAIT, move(0), move(1), { kind: "turn", direction: 3 }, move(2)]);
  });
});
