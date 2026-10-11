// What the segment tables cannot show of the mirror (CLI-02f, CLI-02g-A): the branches of
// `SegmentTrait::run` it does not mirror (a Move off the window's edge, D-255; a Heavy refusal whose
// call changed the ground, game's fix pending), that `run` does not change what it is given, and
// that the replayer of the parity tests stays out of the app's API.

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import * as sim from "../index";
import { board as origin_board, position } from "../movement";
import { LIVE } from "../packing";
import { NotMirrored, run, unported } from "../segment";
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

/** Classes whose `act` returns `ticks`, the words unchanged, the ground with a placed trap if `changes`. */
function acting(ticks: number, changes: boolean): Classes {
  return {
    ...UNREACHED,
    act: (call) => ({
      words: call.words,
      ground: changes
        ? [
            [
              16,
              {
                packs: [0, 1].map(() => ({
                  tile: 0,
                  template: 0,
                  level: 0,
                  count: 0,
                  offsets: 0,
                  alert: 0,
                })),
                objects: [
                  { tile: 112, kind: 9, state: 0, param: 0 },
                  ...[0, 1].map(() => ({ tile: 0, kind: 0, state: 0, param: 0 })),
                ],
                touched: 0,
              },
            ],
          ]
        : call.ground,
      outcome: { ticks },
    }),
  };
}

describe("the segment beyond its tables", () => {
  it("throws on a combat action refused as Heavy whose call changed the ground", () => {
    // An instant trap skill (0 ticks) with no weight left: `run` keeps the placed trap, a bug
    const heavy: Segment = {
      ...segment(),
      owed: 0,
      weight: 0,
      actions: [{ kind: "skill", slot: 0, target: { tile: true, value: 112 } }],
    };
    expect(() => run(heavy, acting(0, true))).toThrow(new NotMirrored(unported.HEAVY_GROUND));
    // The ground unchanged, restoring and keeping agree: the refusal is mirrored
    expect(run(heavy, acting(0, false)).done.heavy).toBe(true);
    // Run within the weight, the changed ground is kept
    const ran = run({ ...heavy, weight: 1 }, acting(0, true));
    expect([ran.done.played, ran.ground.length]).toEqual([1, 1]);
  });

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

  it("reaches nothing under src/parity/ from index.ts, by any import (a static scan)", () => {
    // A name check misses a replayer re-exported as `callDigest`: scan what the entry point imports,
    // and what those import, for a module under `parity/` (the `import ... from`, `export ... from`
    // and bare `import "..."` forms; a dynamic `import()` is refused outright)
    const root = new URL("../", import.meta.url);
    const seen = new Set<string>();
    const queue = ["index.ts"];
    while (queue.length > 0) {
      const file = queue.pop()!;
      if (seen.has(file)) continue;
      seen.add(file);
      const text = readFileSync(new URL(file, root), "utf8");
      expect(text, `${file} imports dynamically`).not.toMatch(/\bimport\s*\(/);
      for (const [, specifier] of text.matchAll(/(?:from|import)\s+["']([^"']+)["']/g)) {
        // A package (`@scure/starknet`) is not a module of `parity/`
        if (!specifier!.startsWith(".")) continue;
        const target = new URL(`${specifier}.ts`, new URL(file, root));
        queue.push(target.pathname.slice(root.pathname.length));
      }
    }
    expect(seen.has("segment/classes.ts")).toBe(true);
    expect([...seen].filter((file) => file.startsWith("parity/"))).toEqual([]);
  });
});
