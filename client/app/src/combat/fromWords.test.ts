import {
  goblinCrippled,
  goblinPlace,
  indexSheets,
  loadGoblin,
  loadMember,
  memberCrippled,
  memberPlace,
} from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import { fromWords, markOf, trapsOf } from "./fromWords";
import { contentOf, tickIds, tickRow } from "./vectors.testkit";

const TICK = contentOf("tick.jsonl");
const SHEETS = indexSheets(TICK);

/** What a condition's chip must read at `clock`: `deadline − clock` while held at the next tick. */
const left = (deadline: number, clock: number): number | null =>
  clock + 1 <= deadline ? deadline - clock : null;

describe("fromWords on RV-03c's tick table (§10, CLI-05a)", () => {
  it("decodes every row's members and goblins to what client/sim's loaders give", () => {
    let goblins = 0;
    for (const id of tickIds()) {
      const row = tickRow(id);
      const clock = row.words.clock;
      const state = fromWords(row.words, TICK, row.ground, row.board);
      const m = loadMember(row.words.members[0]!, SHEETS);
      const a = state.adventurer;
      expect(a.tile, `row ${id}`).toEqual({ x: memberPlace(m).x, y: memberPlace(m).y });
      expect([a.health, a.maxHealth], `row ${id}`).toEqual([m.health, m.max_health]);
      expect(a.energy * 3, `row ${id}`).toBeLessThanOrEqual(m.energy);
      const conditions = [m.bleeding, m.poison, m.burning, memberCrippled(m), m.knocked];
      expect(
        a.chips.filter((c) => c.kind === "condition").map((c) => c.ticks),
        `row ${id}`,
      ).toEqual(conditions.map((d) => left(d, clock)).filter((t) => t !== null));
      const effects = m.effect_deadlines.filter((d, s) => m.effect_at[s] !== 0xffff && clock < d);
      expect(a.chips.filter((c) => c.kind === "effect").length, `row ${id}`).toBe(effects.length);
      const activating = m.act_slot !== 255 && m.act_deadline > clock;
      expect(a.activation?.ticks ?? null, `row ${id}`).toBe(
        activating ? m.act_deadline - clock : null,
      );
      row.words.goblins.forEach((words, k) => {
        const g = loadGoblin(words, SHEETS);
        const view = state.goblins[k]!;
        expect(view.entity).toBe(g.entity);
        expect(view.tile).toEqual({ x: goblinPlace(g).x, y: goblinPlace(g).y });
        expect([view.health, view.maxHealth], `row ${id} goblin ${g.entity}`).toEqual([
          g.health,
          g.max_health,
        ]);
        expect(view.mark).toBe(markOf(g.ai));
        const gc = [g.bleeding, g.poison, g.burning, goblinCrippled(g), g.knocked];
        expect(
          view.chips.filter((c) => c.kind === "condition").map((c) => c.ticks),
          `row ${id} goblin ${g.entity}`,
        ).toEqual(gc.map((d) => left(d, clock)).filter((t) => t !== null));
        const acting = g.act_slot <= 3 && g.act_deadline > clock;
        expect(view.activation?.ticks ?? null, `row ${id} goblin ${g.entity}`).toBe(
          acting ? g.act_deadline - clock : null,
        );
        expect(view.recovering).toBe(g.act_slot === 254 && g.act_deadline > clock);
        goblins += 1;
      });
    }
    expect(goblins).toBeGreaterThan(100);
  });

  it("a goblin activating: its skill, its ticks, its target", () => {
    // Row 91: goblin 8 activates its caste slot 0 until 201, at clock 200
    const row = tickRow(91);
    const g = fromWords(row.words, TICK, row.ground, row.board).goblins[0]!;
    expect(g.activation).toMatchObject({ slot: 0, ticks: 1 });
    expect(g.activation!.total).toBe(
      TICK.skills.find((s) => s.id === g.activation!.skill)!.activation,
    );
    // A deadline passed is read as none (row 92: its deadline is the clock)
    const lapsed = tickRow(92);
    expect(
      fromWords(lapsed.words, TICK, lapsed.ground, lapsed.board).goblins[0]!.activation,
    ).toBeNull();
  });

  it("a goblin recovering, and one knocked down", () => {
    const row = tickRow(95);
    expect(fromWords(row.words, TICK, row.ground, row.board).goblins[0]!.recovering).toBe(true);
    const over = tickRow(94);
    expect(fromWords(over.words, TICK, over.ground, over.board).goblins[0]!.recovering).toBe(false);
  });

  it("the unused traps of the ground", () => {
    // Row 113: a goblin is about to step on a trap
    const row = tickRow(113);
    const traps = trapsOf(row.ground);
    expect(traps.length).toBeGreaterThan(0);
    expect(fromWords(row.words, TICK, row.ground, row.board).traps).toEqual(traps);
  });

  it("names skills, potions and castes when given names", () => {
    const row = tickRow(91);
    const names = {
      skill: (id: number) => `S${id}`,
      potion: (id: number) => `P${id}`,
      caste: () => "runt",
    };
    const state = fromWords(row.words, TICK, row.ground, row.board, names);
    expect(state.goblins[0]!.casteName).toBe("runt");
    expect(state.goblins[0]!.activation!.name).toBe(`S${state.goblins[0]!.activation!.skill}`);
  });
});
