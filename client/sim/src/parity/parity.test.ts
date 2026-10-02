import { describe, expect, it } from "vitest";
import { replay } from "./replay";
import { readTable } from "./table";
import { TABLES } from "./tables";

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
    const counts = replay(TABLES[0]!, readTable("window.jsonl"));
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
});
