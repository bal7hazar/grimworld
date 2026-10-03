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
    expect(Object.fromEntries(counts)).toEqual({ purpose: 8, domain: 120, derive: 90 });
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
