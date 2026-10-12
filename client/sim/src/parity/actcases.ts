// TEST SCAFFOLDING (CLI-02g-E, review t-0209): what the action class (`action.ts`'s `actClass`)
// must hold that `act.jsonl` cannot show, as cases the unit tests run (`action.test.ts`) and the
// mutation check runs against its mutants (`mutants.test.ts`), one list for both. The port runs a
// carrier on the whole world, where `Delegate` runs it on a sub-world picked by the carrier's first
// entry: a carrier whose entries mix a `TILE` target with an entity one, or a carrier addressing
// `SELF` (its first entry) with a `TILE` entry later, may differ there, so it is not mirrored
// (`NotMirrored`, `action.ts`'s `mixed`); the shapes `mixed` keeps (`SELF` with `FOE`, `TILE` first
// with `SELF` later, `FOE` with `ALLY`) run and land as the class does (review t-0211). No table
// holds such a carrier. Since R-44 (D-271, D-276) most of the refused shapes, and the kept `SELF`
// before `FOE`, are not legal content (the cases say so); `[TILE, SELF]`, `[FOE, SELF]` and
// `[FOE, ALLY]` are. Never exported by `src/index.ts`.

import { type Entry, kind, pack, unpack } from "../effect";
import { target } from "../executor";
import { NotMirrored } from "../segment";
import type { ActCall } from "../segment/classes";
import {
  type Action,
  Felts,
  readAction,
  readBoard,
  readContent,
  readGround,
  readWords,
} from "../segment/serde";
import { actClass } from "../action";
import { crippled as goblinCrippled, set_place } from "../segment/goblin";
import { crippled, sheets as indexed } from "../segment/words";
import { world, words } from "../segment/world";
import { readTable } from "./table";

/** The class's call of `act.jsonl`'s row `id` (an `act` row), its content row 0's. */
export function call(id: number): ActCall {
  const rows = readTable("act.jsonl");
  const head = new Felts(rows[0]!.ok!);
  const content = readContent(head);
  head.end();
  const read = new Felts(rows[id]!.case);
  const words = readWords(read);
  const board = readBoard(read);
  const ground = readGround(read);
  const action = readAction(read);
  read.end();
  return { words, content, board, ground, action };
}

/** Row 70: the fire spell (skill 61, bar slot 0) on goblin 8, the member on (7, 7). */
const ROW = 70;
const FIRE = 61;

const DAMAGE: Entry = {
  ...unpack(0n),
  kind: kind.DAMAGE,
  param: 3,
  v0: 40,
  v12: 40,
  shape: 1,
  filter: 0,
};
/** `shape::DISC_1`: the centre and its 6 neighbours. */
const DISC_1 = 3;
/** `filter::ALLIES`. */
const ALLIES = 1;

/** Crippled, 3 ticks, on its set (`CONDITION`'s `param` the condition, its value the duration). */
const CONDITION: Entry = { ...unpack(0n), kind: kind.CONDITION, param: 4, v0: 3, v12: 3, shape: 1 };

/**
 * Row 70 with the fire spell made instant (it carries now), of range 20 (tile 8, `(8, 0)`, is in
 * reach of the member), its entries `entries`, and the action `action`.
 */
function spell(entries: readonly Entry[], action: Action): ActCall {
  const c = call(ROW);
  const [entry1, entry2, entry3] = [0, 1, 2].map((k) => {
    const e = entries[k];
    return e === undefined ? 0n : pack(e);
  });
  const skills = c.content.skills.map((sheet) =>
    sheet.id === FIRE
      ? { ...sheet, activation: 0, range: 20, entry1: entry1!, entry2: entry2!, entry3: entry3! }
      : sheet,
  );
  return { ...c, content: { ...c.content, skills }, action };
}

/** `c` with goblin 8 moved next to the member, East of it on (8, 7) (window position 113). */
function adjacent(c: ActCall): ActCall {
  const loaded = world(c.words, indexed(c.content));
  const goblin = loaded.goblins.find((g) => g.entity === 8)!;
  set_place(goblin, 8, 7, 0);
  return { ...c, words: words(loaded) };
}

/** What the result reads of goblin 8 and the member: hit, Crippled, after the call at `clock`. */
function outcome(c: ActCall): { ticks: number; hit: boolean; goblin: boolean; member: boolean } {
  const out = actClass(c);
  if (!("ticks" in out.outcome)) throw new Error(`refused ${JSON.stringify(out.outcome)}`);
  const before = world(c.words, indexed(c.content));
  const after = world(out.words, indexed(c.content));
  const g = (w: typeof after) => w.goblins.find((goblin) => goblin.entity === 8)!;
  const clock = c.words.clock;
  return {
    ticks: out.outcome.ticks,
    hit: g(after).health < g(before).health,
    goblin: goblinCrippled(g(after)) > clock,
    member: crippled(after.members[0]!) > clock,
  };
}

/** Throws unless the call runs with `expected`. */
function lands(c: ActCall, expected: ReturnType<typeof outcome>): void {
  const got = outcome(c);
  if (JSON.stringify(got) !== JSON.stringify(expected)) {
    throw new Error(`got ${JSON.stringify(got)}, expected ${JSON.stringify(expected)}`);
  }
}

/** Whether the class refuses to mirror the call (`NotMirrored`); any other result is not. */
function unmirrored(c: ActCall): boolean {
  try {
    actClass(c);
  } catch (error) {
    if (error instanceof NotMirrored) return true;
    throw error;
  }
  return false;
}

/** One check: its name and its case, which throws when the class does not hold it. */
export type Check = { name: string; run: () => void };

const onTile = (value: number): Action => ({
  kind: "skill",
  slot: 0,
  target: { tile: true, value },
});
const onEntity = (value: number): Action => ({
  kind: "skill",
  slot: 0,
  target: { tile: false, value },
});

export const CHECKS: readonly Check[] = [
  {
    // Not legal content (R-44, D-271): `assert_carrier` refuses a TILE entry beside a FOE one
    name: "a TILE hit then a FOE condition, cast at tile 8, is not mirrored (scenario A)",
    run: () => {
      const tile = { ...DAMAGE, target: target.TILE };
      const foe = { ...CONDITION, target: target.FOE };
      if (!unmirrored(spell([tile, foe], onTile(8)))) {
        throw new Error("the mixed carrier ran on the whole world");
      }
    },
  },
  {
    // Not legal content (R-44, D-271): `assert_carrier` refuses a TILE entry beside an ALLY one
    name: "a TILE hit then an ALLY condition, cast at tile 8, is not mirrored (ALLY is an entity set)",
    run: () => {
      const tile = { ...DAMAGE, target: target.TILE };
      const ally = { ...CONDITION, target: target.ALLY, filter: ALLIES };
      if (!unmirrored(spell([tile, ally], onTile(8)))) {
        throw new Error("the TILE then ALLY carrier ran on the whole world");
      }
    },
  },
  {
    // Not legal content (R-44): `assert_carrier` puts a hit first (`HIT_NOT_FIRST`) and refuses a
    // TILE entry beside a FOE one (D-271); the guard holds anyway
    name: "a FOE condition then a TILE hit, cast at goblin 8, is not mirrored (scenario B, an illegal order)",
    run: () => {
      const foe = { ...CONDITION, target: target.FOE };
      const tile = { ...DAMAGE, target: target.TILE };
      if (!unmirrored(spell([foe, tile], onEntity(8)))) {
        throw new Error("the mixed carrier ran on the whole world");
      }
    },
  },
  {
    name: "a FOE hit and a FOE condition, cast at goblin 8, still runs and lands",
    run: () => {
      const c = spell(
        [
          { ...DAMAGE, target: target.FOE },
          { ...CONDITION, target: target.FOE },
        ],
        onEntity(8),
      );
      const out = actClass(c);
      if (!("ticks" in out.outcome) || out.outcome.ticks !== 0) {
        throw new Error(`the same-kind carrier gave ${JSON.stringify(out.outcome)}`);
      }
      const before = c.words.goblins.map((goblin) => goblin.state);
      if (out.words.goblins.every((goblin, i) => goblin.state === before[i])) {
        throw new Error("the same-kind carrier changed no goblin");
      }
    },
  },
  {
    // Not legal content (R-44, D-276): `assert_carrier` refuses a SELF entry before an addressed one
    name: "a SELF hit then a TILE condition, cast on itself, is not mirrored (SELF first, TILE later)",
    run: () => {
      const self = { ...DAMAGE, target: target.SELF };
      const tile = { ...CONDITION, target: target.TILE };
      if (!unmirrored(spell([self, tile], onEntity(0)))) {
        throw new Error("the SELF-first carrier with a TILE entry ran on the whole world");
      }
    },
  },
  {
    // Not legal content (R-44, D-276): `assert_carrier` refuses a SELF entry before a FOE one; the
    // guard keeps it (`false`) all the same, and the class runs it as the sub-world would
    name: "a SELF disc hit then a FOE condition, cast on itself, runs: goblin 8 hit, no one Crippled",
    run: () => {
      // The address is the member's own id (`aim`): the FOE set is the member, whom FOES does not take
      const self = { ...DAMAGE, target: target.SELF, shape: DISC_1 };
      const foe = { ...CONDITION, target: target.FOE };
      lands(adjacent(spell([self, foe], onEntity(0))), {
        ticks: 0,
        hit: true,
        goblin: false,
        member: false,
      });
    },
  },
  {
    // Legal content (R-44): SELF after the addressed entry
    name: "a TILE disc hit then a SELF condition, cast at goblin 8's tile, runs: goblin 8 hit, the member Crippled",
    run: () => {
      const tile = { ...DAMAGE, target: target.TILE, shape: DISC_1 };
      const self = { ...CONDITION, target: target.SELF, filter: ALLIES };
      lands(adjacent(spell([tile, self], onTile(8 + 256 * 7))), {
        ticks: 0,
        hit: true,
        goblin: false,
        member: true,
      });
    },
  },
  {
    // Legal content (R-44): FOE and ALLY are both entity sets
    name: "a FOE hit then an ALLY condition, cast at goblin 8, runs: goblin 8 hit, no one Crippled",
    run: () => {
      // The ALLY set centres on goblin 8, whom ALLIES does not take from a member's carrier
      const foe = { ...DAMAGE, target: target.FOE };
      const ally = { ...CONDITION, target: target.ALLY, filter: ALLIES };
      lands(adjacent(spell([foe, ally], onEntity(8))), {
        ticks: 0,
        hit: true,
        goblin: false,
        member: false,
      });
    },
  },
];

/** Runs a check: fails with its name when the class does not hold it. */
export function holds(check: Check): void {
  check.run();
}
