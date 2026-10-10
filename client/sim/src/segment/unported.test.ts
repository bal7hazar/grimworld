// The branches of `SegmentTrait::run` that `segment.jsonl` has no case for: the mirror throws
// `NotMirrored` where `run` reaches one, never a guess (CLI-02f).

import { describe, expect, it } from "vitest";
import { board as origin_board, position } from "../movement";
import { NotMirrored, run, unported } from "../segment";
import type { Action, Area, World } from "../segment";
import { WIDTH, inside, neighbor } from "../window";

/** A 3 × 3 location, every chunk known, revealed and walkable (the table's `region`). */
const AREA: Area = (() => {
  const all = [0, 1, 2, 15, 16, 17, 30, 31, 32];
  const bits = all.reduce((set, chunk) => set | (1n << BigInt(chunk)), 0n);
  return {
    width: 3,
    height: 3,
    known: bits,
    revealed: bits,
    chunks: all.map((chunk) => [chunk, (1n << 225n) - 1n] as const),
    changed: [],
    ran: false,
  };
})();

/** The adventurer on (22, 22) at clock 40, as the table's fixture. */
function world(change: Partial<World> = {}): World {
  return {
    clock: 40,
    adventurer: {
      x: 22,
      y: 22,
      facing: 0,
      status: 0,
      health: 400,
      crippled: 0,
      knocked: 0,
      flags: 0,
      movement: false,
    },
    goblins: [],
    calm: true,
    defeated: false,
    armed: [],
    ...change,
  };
}

const WAIT: Action = { kind: "wait" };
const WEST: Action = { kind: "move", direction: 0 };
const notMirrored = (branch: string) => new NotMirrored(branch);

describe("the branches the segment table does not cover", () => {
  it("throws on a world already defeated, at the loop's check", () => {
    expect(() => run(world({ defeated: true }), AREA, [WAIT], 0, 10)).toThrow(
      notMirrored(unported.DEFEATED),
    );
  });

  it("throws on a tick with the adventurer down (the tick that defeats)", () => {
    const down = world();
    down.adventurer.health = 0;
    expect(() => run(down, AREA, [], 1, 10)).toThrow(notMirrored(unported.DEFEATED));
  });

  it("throws on the combat arm, its Heavy with it", () => {
    for (const kind of ["attack", "skill", "item"] as const) {
      expect(() => run(world(), AREA, [{ kind }], 0, 10)).toThrow(notMirrored(unported.COMBAT));
      expect(() => run(world(), AREA, [{ kind }], 0, 0)).toThrow(notMirrored(unported.COMBAT));
    }
  });

  it("throws on ticks through TickLibrary: a goblin in the window, or a world not calm", () => {
    const goblin = { x: 25, y: 22 };
    expect(() => run(world({ goblins: [goblin] }), AREA, [WAIT], 0, 10)).toThrow(
      notMirrored(unported.TICK_LIBRARY),
    );
    expect(() => run(world({ goblins: [goblin] }), AREA, [], 2, 10)).toThrow(
      notMirrored(unported.TICK_LIBRARY),
    );
    expect(() => run(world({ calm: false }), AREA, [WAIT], 0, 10)).toThrow(
      notMirrored(unported.TICK_LIBRARY),
    );
  });

  it("throws on an armed trap on the tile entered", () => {
    expect(() => run(world({ armed: [{ x: 21, y: 22 }] }), AREA, [WEST], 0, 10)).toThrow(
      notMirrored(unported.TRAP),
    );
  });

  it("throws on Blocked by a tile a goblin occupies", () => {
    expect(() => run(world({ goblins: [{ x: 21, y: 22 }] }), AREA, [WEST], 0, 10)).toThrow(
      notMirrored(unported.OCCUPIED),
    );
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

  it("throws on a Move with a MOVEMENT effect held", () => {
    const held = world();
    held.adventurer.movement = true;
    expect(() => run(held, AREA, [WEST], 0, 10)).toThrow(notMirrored(unported.MOVEMENT));
  });

  it("leaves fits' goblin arm unreached: a goblin outside the window changes nothing", () => {
    // `fits` counts a goblin whose words changed; only the branches above change one. A goblin
    // outside the window is frozen on the fast path: the segment is the one without it.
    const far = { x: 44, y: 44 };
    const alone = run(world(), AREA, [WAIT, WEST, WAIT], 0, 10);
    const beside = run(world({ goblins: [far] }), AREA, [WAIT, WEST, WAIT], 0, 10);
    expect(beside.done).toEqual(alone.done);
    expect(beside.world.adventurer).toEqual(alone.world.adventurer);
  });

  it("does not change the world it is given", () => {
    const before = world();
    run(before, AREA, [WEST, { kind: "turn", direction: 2 }], 1, 10);
    expect(before).toEqual(world());
  });
});
