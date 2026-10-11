// TEST SCAFFOLDING (CLI-02g-E, review t-0209): what the action class (`action.ts`'s `actClass`)
// must hold that `act.jsonl` cannot show, as cases the unit tests run (`action.test.ts`) and the
// mutation check runs against its mutants (`mutants.test.ts`), one list for both. The port runs a
// carrier on the whole world, where `Delegate` runs it on a sub-world picked by the carrier's first
// entry: a carrier whose entries mix a `TILE` target with an entity one may differ there, so it is
// not mirrored (`NotMirrored`); no table holds such a carrier. Never exported by `src/index.ts`.

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
    name: "a FOE condition then a TILE hit, cast at goblin 8, is not mirrored (scenario B)",
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
];

/** Runs a check: fails with its name when the class does not hold it. */
export function holds(check: Check): void {
  check.run();
}
