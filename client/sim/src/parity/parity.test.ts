import { describe, expect, it } from "vitest";
import { Felts, readAction, readArea, readCall, readGround, readWords } from "../segment/serde";
import { replay } from "./replay";
import { readTable } from "./table";
import { TABLES, native } from "./tables";

const table = (file: string) => TABLES.find((entry) => entry.file === file)!;

describe("parity with the Cairo code", () => {
  for (const entry of TABLES) {
    it(`replays every case of ${entry.file} with no divergence`, () => {
      const vectors = readTable(entry.file);
      const counts = replay(entry, vectors);
      expect(vectors.length).toBeGreaterThanOrEqual(entry.floor);
      expect([...counts.values()].reduce((a, b) => a + b, 0)).toBe(vectors.length);
    });
  }

  it("covers every fn of window.jsonl with its count", () => {
    const counts = replay(table("window.jsonl"), readTable("window.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({
      sight: 349,
      reach: 349,
      arc: 258,
      facing: 258,
      front: 72,
      distance: 724,
      shape: 55,
    });
  });

  it("covers every fn of fate.jsonl with its count", () => {
    const counts = replay(table("fate.jsonl"), readTable("fate.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({ purpose: 9, domain: 128, derive: 90 });
  });

  it("covers every fn of movement.jsonl with its count", () => {
    const counts = replay(table("movement.jsonl"), readTable("movement.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({
      origin: 13,
      move: 48,
      ticks: 7,
      flood: 23,
      awake: 3,
    });
  });

  it("covers every fn of reveal.jsonl with its count", () => {
    const counts = replay(table("reveal.jsonl"), readTable("reveal.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({
      word: 18,
      feed: 15,
      base: 12,
      sight: 14,
      member: 115,
      reveal: 40,
    });
  });

  it("covers every fn of batch.jsonl with its count", () => {
    const counts = replay(table("batch.jsonl"), readTable("batch.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({ records: 14, owed: 8, reveal: 6 });
  });

  it("covers every fn of segment.jsonl with its count", () => {
    const counts = replay(table("segment.jsonl"), readTable("segment.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({
      fold: 6,
      reveal: 6,
      cost: 12,
      ran: 4,
      fits: 5,
      halt: 14,
    });
  });

  it("covers every fn of segment2.jsonl with its count", () => {
    const counts = replay(table("segment2.jsonl"), readTable("segment2.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({
      content: 1,
      combat: 12,
      ticks: 4,
      fits: 7,
      defeated: 3,
      trap: 4,
      occupied: 2,
      companions: 3,
      regeneration: 3,
      movement: 2,
      turn: 2,
      follow: 2,
    });
  });

  it("covers every fn of body.jsonl with its count", () => {
    const counts = replay(table("body.jsonl"), readTable("body.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({
      content: 1,
      health: 2,
      max_health: 2,
      is_member: 2,
      place: 2,
      alive: 9,
      knocked: 6,
      asleep: 3,
      halves: 4,
      armor_vs: 22,
      infliction: 2,
      enchant_percent: 2,
      slots: 2,
      effect: 5,
      wound: 10,
      heal: 13,
      energize: 14,
      struck: 16,
      landed: 15,
      halved: 3,
      inflict: 50,
      cure: 19,
      hold: 25,
      spend: 7,
      line: 36,
      value: 3,
      duration: 16,
      class: 26,
      pack: 5,
      unpack: 5,
    });
  });

  it("covers every fn of trap.jsonl with its count", () => {
    const counts = replay(table("trap.jsonl"), readTable("trap.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({ content: 1, trigger: 52, free: 10 });
  });

  it("computes segment2.jsonl's trap calls natively, each equal to its recording", () => {
    // The rows that record a `TrapLibrary::trigger` call, from their spans of calls
    const vectors = readTable("segment2.jsonl");
    const recorded = vectors.flatMap((vector) => {
      if (vector.fn === "content") return [];
      const read = new Felts(vector.case);
      readWords(read);
      readArea(read);
      read.u8();
      readGround(read);
      read.u8();
      read.u8();
      read.span(() => readAction(read));
      const calls = read.span(() => readCall(read));
      read.end();
      return calls.filter((call) => call.kind === "trigger").map(() => vector.id);
    });
    expect(recorded).toEqual([26, 28, 43]);
    const before = native.triggers;
    replay(table("segment2.jsonl"), vectors);
    expect(native.triggers - before).toBe(recorded.length);
  });

  it("covers every fn of act.jsonl with its count", () => {
    const counts = replay(table("act.jsonl"), readTable("act.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({ content: 1, act: 175, defence: 19, offence: 28 });
  });

  it("computes segment2.jsonl's act calls natively, each equal to its recording", () => {
    // The rows that record an `ActionLibrary::act` call, from their spans of calls
    const vectors = readTable("segment2.jsonl");
    const recorded = vectors.flatMap((vector) => {
      if (vector.fn === "content") return [];
      const read = new Felts(vector.case);
      readWords(read);
      readArea(read);
      read.u8();
      readGround(read);
      read.u8();
      read.u8();
      read.span(() => readAction(read));
      const calls = read.span(() => readCall(read));
      read.end();
      return calls.filter((call) => call.kind === "act").map(() => vector.id);
    });
    expect(recorded).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 44]);
    const before = native.acts;
    replay(table("segment2.jsonl"), vectors);
    expect(native.acts - before).toBe(recorded.length);
  });

  it("covers every fn of packing.jsonl with its count", () => {
    const counts = replay(table("packing.jsonl"), readTable("packing.jsonl"));
    expect(Object.fromEntries(counts)).toEqual({
      split: 14,
      limbs: 8,
      join: 56,
      peel: 70,
      fits: 30,
      field: 56,
      byte_at: 28,
      u16_at: 28,
      u32_at: 28,
      low_field: 35,
      pack_lanes32: 26,
      unpack_lanes32: 28,
      pack_lanes16: 35,
      unpack_lanes16: 37,
      pack_counter: 8,
      unpack_counter: 9,
      pack_bitmap: 13,
      unpack_bitmap: 11,
    });
  });
});
