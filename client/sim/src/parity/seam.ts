// TEST SCAFFOLDING (CLI-02g-C): what `run` keeps at the seam of the classes (`segment/classes.ts`)
// when ActionLibrary refuses an action, as cases the unit tests run (`segment/unported.test.ts`)
// and the mutation check runs against its copies of `src/` (`mutants.test.ts`), so that one list
// of cases decides both. A refusal, Heavy or Illegal, leaves the words and the ground as they were
// (D-259), whatever the call returned and even if the class mutated its inputs in place: `run`
// passes it copies. `segment2.jsonl` records the Heavy case (row 44); no row records an Illegal
// refusal whose call changed the ground, nor a class that mutates its inputs. Never exported by
// `src/index.ts`.

import { LIVE } from "../packing";
import { run } from "../segment";
import type { Segment } from "../segment";
import type { ActCall, Classes } from "../segment/classes";
import { type Ground, Illegal, type Outcome } from "../segment/serde";

/** A 3 × 3 location, every chunk known, revealed and walkable (the table's `region`). */
const ALL = [0, 1, 2, 15, 16, 17, 30, 31, 32];
const BITS = ALL.reduce((set, chunk) => set | (1n << BigInt(chunk)), 0n);

/** Chunk 16's features, empty, or with a trap placed on tile 112. */
function chunk16(placed: boolean): Ground[number] {
  const empty = { tile: 0, kind: 0, state: 0, param: 0 };
  return [
    16,
    {
      packs: [0, 1].map(() => ({ tile: 0, template: 0, level: 0, count: 0, offsets: 0, alert: 0 })),
      objects: [placed ? { tile: 112, kind: 9, state: 0, param: 0 } : empty, empty, { ...empty }],
      touched: 0,
    },
  ];
}

/** The adventurer on (22, 22) at clock 40, health 400 of 480, no regeneration; a Move, a Turn, a Wait. */
export function segment(): Segment {
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

/** Classes a segment must not call. */
export const UNREACHED: Classes = {
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

/**
 * Classes whose `act` gives `outcome`, the words unchanged, and the ground with a trap placed on
 * tile 112 (`changes`), returned new or (`mutates`) written into the call's own ground and words.
 */
export function acting(outcome: Outcome, changes: boolean, mutates = false): Classes {
  return {
    ...UNREACHED,
    act: (call: ActCall) => {
      if (!changes) return { words: call.words, ground: call.ground, outcome };
      if (!mutates) return { words: call.words, ground: [chunk16(true)], outcome };
      call.ground.length = 0;
      call.ground.push(chunk16(true));
      call.words.members[0]!.state += 1n;
      call.words.killed.push(8);
      return { words: call.words, ground: call.ground, outcome };
    },
  };
}

/** One check: its name and its case, which throws when `run` does not hold it. */
export type Check = { name: string; run: () => void };

const text = (value: unknown): string =>
  JSON.stringify(value, (_, v) => (typeof v === "bigint" ? `${v}n` : v));

function expectSame(name: string, got: unknown, want: unknown): void {
  if (text(got) !== text(want)) throw new Error(`${name}: got ${text(got)}, want ${text(want)}`);
}

/** An instant trap skill on tile 112 with no weight left, the ground holding chunk 16 empty. */
function refusing(): Segment {
  return {
    ...segment(),
    ground: [chunk16(false)],
    owed: 0,
    weight: 0,
    actions: [{ kind: "skill", slot: 0, target: { tile: true, value: 112 } }],
  };
}

/** `run` refuses the action and keeps the words and the ground it was given, untouched. */
function keeps(name: string, outcome: Outcome, mutates: boolean): Check {
  return {
    name,
    run: () => {
      const given = refusing();
      const out = run(given, acting(outcome, true, mutates));
      const done = "illegal" in outcome ? out.done.illegal : out.done.heavy;
      expectSame(`${name}: refused`, done, "illegal" in outcome ? outcome.illegal : true);
      expectSame(`${name}: the ground`, out.ground, refusing().ground);
      expectSame(`${name}: the words`, out.words, refusing().words);
      expectSame(`${name}: the segment given`, given, refusing());
    },
  };
}

export const CHECKS: readonly Check[] = [
  keeps(
    "a Heavy refusal whose call changed the ground keeps the input ground",
    { ticks: 0 },
    false,
  ),
  keeps(
    "an Illegal refusal whose call changed the ground keeps the input ground",
    { illegal: Illegal.Target },
    false,
  ),
  keeps("a class that mutates its inputs cannot change a Heavy refusal's", { ticks: 0 }, true),
  keeps(
    "a class that mutates its inputs cannot change an Illegal refusal's",
    { illegal: Illegal.Target },
    true,
  ),
  {
    name: "a kept result takes the call's ground",
    run: () => {
      const out = run({ ...refusing(), weight: 1 }, acting({ ticks: 0 }, true));
      expectSame("played", out.done.played, 1);
      expectSame("the ground", out.ground, [chunk16(true)]);
    },
  },
];

/** Runs a check: fails with its name when `run` does not hold it. */
export function holds(check: Check): void {
  check.run();
}
