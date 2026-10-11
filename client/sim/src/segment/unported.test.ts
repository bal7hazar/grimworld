// What the segment tables cannot show of the mirror (CLI-02f, CLI-02g-A): the one branch of
// `SegmentTrait::run` it does not mirror (a Move off the window's edge, D-255), that `run` does not
// change what it is given, and that the replayer of the parity tests stays out of the app's API.

import { describe, expect, it } from "vitest";
import * as sim from "../index";
import { board as origin_board, position } from "../movement";
import { LIVE } from "../packing";
import { run } from "../segment";
import type { Segment } from "../segment";
import { WIDTH, inside, neighbor } from "../window";
import type { Classes } from "./classes";

/** A 3 × 3 location, every chunk known, revealed and walkable (the table's `region`). */
const ALL = [0, 1, 2, 15, 16, 17, 30, 31, 32];
const BITS = ALL.reduce((set, chunk) => set | (1n << BigInt(chunk)), 0n);

/** The adventurer on (22, 22) at clock 40, health 400 of 480, no regeneration. */
function segment(): Segment {
  const two = (bits: number) => 1n << BigInt(bits);
  return {
    words: {
      clock: 40,
      members: [
        {
          state: LIVE + 22n * two(32) + 22n * two(40) + 400n * two(64),
          timers: LIVE + 255n,
          effects: LIVE,
          recharges: LIVE,
          stats: LIVE + 480n + 10n * two(32),
          bar: LIVE,
          kit: LIVE,
        },
      ],
      goblins: [],
      killed: [],
      defeated: false,
    },
    content: { skills: [], potions: [], castes: [] },
    area: {
      width: 3,
      height: 3,
      known: BITS,
      revealed: BITS,
      chunks: ALL.map((chunk) => [chunk, (1n << 225n) - 1n] as const),
      changed: [],
      ran: false,
    },
    level: 1,
    ground: [],
    owed: 1,
    weight: 10,
    actions: [{ kind: "move", direction: 0 }, { kind: "turn", direction: 2 }, { kind: "wait" }],
  };
}

const UNREACHED: Classes = {
  ticks: () => {
    throw new Error("a TickLibrary call");
  },
  act: () => {
    throw new Error("an ActionLibrary call");
  },
  trigger: () => {
    throw new Error("a TrapLibrary call");
  },
};

describe("the segment beyond its tables", () => {
  it("cannot reach Blocked by a missing neighbour: the adventurer stands inside the window's ring", () => {
    // Its window is around it (column 7, row 7 or 8): every direction has a neighbour, so the
    // branch's `NotMirrored` is a guard only
    for (const [x, y] of [
      [0, 0],
      [22, 22],
      [22, 23],
      [44, 44],
      [224, 224],
    ] as const) {
      const from = position(origin_board(x, y), x, y);
      expect(inside(from)).toBe(true);
      expect([from % WIDTH, Math.floor(from / WIDTH)]).toEqual([7, y % 2 === 1 ? 7 : 8]);
      for (let d = 0; d < 6; d++) expect(neighbor(from, d)).toBeDefined();
    }
  });

  it("does not change the segment it is given", () => {
    const before = segment();
    const { done } = run(before, UNREACHED);
    expect(done.played).toBe(3);
    expect(before).toEqual(segment());
  });

  it("exports the seam of the classes, not the parity tests' replayer", () => {
    expect(Object.keys(sim)).toContain("callDigest");
    expect(Object.keys(sim).filter((name) => /replay/i.test(name))).toEqual([]);
  });
});
