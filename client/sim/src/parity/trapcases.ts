// TEST SCAFFOLDING (CLI-02g-D): what the trap class (`trap.ts`'s `triggerClass`) must hold that
// `trap.jsonl` cannot show, as cases the unit tests run (`trap.test.ts`) and the mutation check
// runs against its mutants (`mutants.test.ts`), one list for both. Both goblins of the
// table are Hobs of one caste, so a port that reads another goblin's caste than the placer's
// passes every row (track game's known gap, until RV-03c's row with distinct castes); and no row
// shows that the class leaves its inputs as they were. Never exported by `src/index.ts`.

import type { TriggerCall } from "../segment/classes";
import {
  Felts,
  readBoard,
  readContent,
  readGround,
  readWords,
  writeGround,
  writeWords,
} from "../segment/serde";
import { triggerClass } from "../trap";
import { contentRow, readTable } from "./table";

/** The class's call of `trap.jsonl`'s row `id` (a `trigger` row), its latest `content` row's. */
export function call(id: number): TriggerCall {
  const rows = readTable("trap.jsonl");
  const head = new Felts(rows[contentRow(rows, id)]!.ok!);
  const content = readContent(head);
  head.end();
  const read = new Felts(rows[id]!.case);
  const words = readWords(read);
  const board = readBoard(read);
  const ground = readGround(read);
  const [entrant, position, level] = [read.u16(), read.u8(), read.u8()];
  read.end();
  return { words, content, board, ground, entrant, position, level };
}

/**
 * Goblin `k` of the call's words moved to caste 2 (`GoblinState` 64–79: caste 1 + 1), and caste 2
 * given rank 5 (the table's two castes are both of rank 12).
 */
function caste2(c: TriggerCall, k: number): TriggerCall {
  const goblins = c.words.goblins.map((goblin, i) =>
    i === k ? { ...goblin, state: goblin.state + (1n << 64n) } : goblin,
  );
  const castes = c.content.castes.map((caste) => (caste.id === 2 ? { ...caste, rank: 5 } : caste));
  return { ...c, content: { ...c.content, castes }, words: { ...c.words, goblins } };
}

/** What a call changes of the members and the ground, and whether it triggered. */
function effect(c: TriggerCall): string {
  const out = triggerClass(c);
  const members = writeWords({ ...out.words, goblins: [] });
  return [...members, ...writeGround(out.ground), out.triggered].join(",");
}

/** One check: its name and its case, which throws when the class does not hold it. */
export type Check = { name: string; run: () => void };

/** Row 24: goblin 45's trap (caste slot 2), goblin 44 its index 0, both of caste 1. */
const ROW = 24;

/** Goblin `k` of the call's words five levels up (`GoblinState` 80–87; the table's are 10). */
function higher(c: TriggerCall, k: number): TriggerCall {
  const goblins = c.words.goblins.map((goblin, i) =>
    i === k ? { ...goblin, state: goblin.state + 5n * (1n << 80n) } : goblin,
  );
  return { ...c, words: { ...c.words, goblins } };
}

export const CHECKS: readonly Check[] = [
  {
    name: "the source is the placer's: another goblin's caste, kit, rank and level change nothing",
    run: () => {
      if (effect(higher(caste2(call(ROW), 0), 0)) !== effect(call(ROW))) {
        throw new Error("goblin 44's caste or level changed the trap of goblin 45");
      }
    },
  },
  {
    name: "the source is the placer's: its own level changes the hit",
    run: () => {
      if (effect(higher(call(ROW), 1)) === effect(call(ROW))) {
        throw new Error("goblin 45's level did not change its trap");
      }
    },
  },
  {
    name: "the source is the placer's caste: its own caste changes the payload",
    run: () => {
      // Caste 2's slot 2 is skill 30, not Hob's trap skill 26
      if (effect(caste2(call(ROW), 1)) === effect(call(ROW))) {
        throw new Error("goblin 45's caste did not change its trap");
      }
    },
  },
  {
    name: "the class leaves its inputs as they were",
    run: () => {
      for (const id of [8, 24, 30]) {
        const given = call(id);
        const before = [...writeWords(given.words), ...writeGround(given.ground)].join(",");
        triggerClass(given);
        const after = [...writeWords(given.words), ...writeGround(given.ground)].join(",");
        if (after !== before) throw new Error(`row ${id}: the call's words or ground changed`);
      }
    },
  },
];

/** Runs a check: fails with its name when the class does not hold it. */
export function holds(check: Check): void {
  check.run();
}
