import {
  type Area,
  Illegal,
  type Words,
  actionAct,
  heal,
  held,
  indexSheets,
  loadWorld,
  memberPlace,
  runSegment,
  tickTicks,
  trapTrigger,
} from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import { conditionChip, memberChips } from "./chips";
import { atClock, contentOf, tickRow } from "./vectors.testkit";

const TICK = contentOf("tick.jsonl");
const SHEETS = indexSheets(TICK);
const CLASSES = { act: actionAct, ticks: tickTicks, trigger: trapTrigger };
const TILES = (1n << 225n) - 1n;

const chipsAt = (words: Words, clock: number) =>
  memberChips(loadWorld(atClock(words, clock), SHEETS).members[0]!, SHEETS, clock);

/** A Wait run by `runSegment` on a row's words at `clock`, its member alone in its open chunk. */
function waitAt(words: Words, clock: number): { before: number; after: number } {
  const start = atClock(words, clock);
  const member = loadWorld(start, SHEETS).members[0]!;
  const { x, y } = memberPlace(member);
  const chunk = Math.floor(y / 15) * 15 + Math.floor(x / 15);
  const area: Area = {
    width: 15,
    height: 15,
    known: 1n << BigInt(chunk),
    revealed: 1n << BigInt(chunk),
    chunks: [[chunk, TILES]],
    changed: [],
    ran: false,
  };
  const ran = runSegment(
    {
      words: start,
      content: TICK,
      area,
      level: 20,
      ground: [],
      owed: 0,
      weight: 10,
      actions: [{ kind: "wait" }],
    },
    CLASSES,
  );
  return { before: member.health, after: loadWorld(ran.words, SHEETS).members[0]!.health };
}

describe("a condition's chip (§6.1, §2.2)", () => {
  it("reads deadline − clock while held at the next tick, as held(deadline, clock + 1)", () => {
    for (const [clock, ticks] of [
      [199, 2],
      [200, 1],
      [201, null],
      [202, null],
    ] as const) {
      const chip = conditionChip(1, 201, clock);
      expect(chip?.ticks ?? null).toBe(ticks);
      expect(chip !== null).toBe(held(201, clock + 1));
    }
  });

  it("Knocked down: the chip shows exactly when actionAct refuses a skill with Knocked", () => {
    // tick.jsonl row 75: knocked down until tick 201
    const row = tickRow(75);
    for (const clock of [200, 201, 202]) {
      const shows = chipsAt(row.words, clock).some((c) => c.letter === "K");
      const out = actionAct({
        words: atClock(row.words, clock),
        content: TICK,
        board: row.board,
        ground: row.ground,
        action: { kind: "skill", slot: 0, target: { tile: false, value: 0 } },
      });
      const knocked = "illegal" in out.outcome && out.outcome.illegal === Illegal.Knocked;
      expect(shows, `clock ${clock}`).toBe(knocked);
      expect(shows).toBe(clock === 200);
    }
    expect(chipsAt(row.words, 200).find((c) => c.letter === "K")?.ticks).toBe(1);
  });

  it("Bleeding: a Wait changes the health by its pips exactly when the chip shows", () => {
    // tick.jsonl row 10: bleeding until tick 201
    const row = tickRow(10);
    for (const clock of [200, 201, 202]) {
      const m = loadWorld(atClock(row.words, clock), SHEETS).members[0]!;
      const shows = chipsAt(row.words, clock).some((c) => c.letter === "B");
      const { before, after } = waitAt(row.words, clock);
      const bleeding = heal(before, m.health_regen - 3, m.max_health);
      const plain = heal(before, m.health_regen, m.max_health);
      expect(bleeding).not.toBe(plain);
      expect(after, `clock ${clock}`).toBe(shows ? bleeding : plain);
      expect(shows).toBe(clock === 200);
    }
  });

  it("REGENERATION: a Wait changes the health by its pips exactly when the chip shows", () => {
    // tick.jsonl row 25: a REGENERATION held in slot 0 until 201
    const row = tickRow(25);
    for (const clock of [200, 201, 202]) {
      const m = loadWorld(atClock(row.words, clock), SHEETS).members[0]!;
      const chip = chipsAt(row.words, clock).find((c) => c.letter === "R");
      const { before, after } = waitAt(row.words, clock);
      const pips = m.effect_regen[0]!;
      expect(pips).not.toBe(0);
      const regenerating = heal(before, m.health_regen + pips, m.max_health);
      const plain = heal(before, m.health_regen, m.max_health);
      expect(after, `clock ${clock}`).toBe(chip ? regenerating : plain);
      expect(chip !== undefined).toBe(clock === 200);
      if (chip) expect(chip).toMatchObject({ ticks: 1, pips });
    }
  });

  it("lists conditions first, then effects in slot order", () => {
    // tick.jsonl row 31: two effects held (slots 0 and 1)
    const chips = chipsAt(tickRow(31).words, 200);
    expect(chips.map((c) => c.kind)).toEqual(["effect", "effect"]);
    expect(chips.map((c) => c.source?.potion)).toEqual([false, true]);
    const bled = chipsAt(tickRow(8).words, 200);
    expect(bled.map((c) => c.letter)).toEqual(["B", "P", "F"]);
  });
});
