import { describe, expect, it } from "vitest";
import { replay } from "./replay";
import { readTable } from "./table";
import { TABLES } from "./tables";

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
      combat: 11,
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
