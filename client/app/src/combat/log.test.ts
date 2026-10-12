import {
  type Action,
  type Segment,
  type Words,
  actionAct,
  indexSheets,
  loadGoblin,
  loadWorld,
  segmentBoard,
  memberPlace,
  storeGoblin,
  tickTicks,
  trapTrigger,
  writeWords,
} from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import {
  CombatLog,
  type LogRecord,
  MAX_LINES,
  Prefixes,
  batchLines,
  differenceLines,
  replayAgrees,
  replayTicks,
  tickLines,
} from "./log";
import { runRecorded } from "./record";
import { DEFAULT_NAMES } from "./state";
import { contentOf, segment2Row, tickIds, tickRow } from "./vectors.testkit";

const TICK = contentOf("tick.jsonl");
const SHEETS = indexSheets(TICK);
const SEGMENT2 = contentOf("segment2.jsonl");
const CLASSES = { act: actionAct, ticks: tickTicks, trigger: trapTrigger };

const decode = (words: Words, sheets = SHEETS) => {
  const world = loadWorld(words, sheets);
  return { words, members: world.members, goblins: world.goblins };
};

/** A tick row's one call, replayed one tick at a time: its lines and records. */
function tickRowLines(id: number): { lines: string[]; records: LogRecord[] } {
  const row = tickRow(id);
  const call = { ...row, content: TICK };
  const states = replayTicks(call);
  const records: LogRecord[] = [];
  const lines: string[] = [];
  for (let k = 1; k < states.length; k++) {
    const [b, a] = [states[k - 1]!, states[k]!];
    lines.push(
      ...tickLines(
        call,
        k,
        decode(b.words),
        decode(a.words),
        b.ground,
        a.ground,
        SHEETS,
        DEFAULT_NAMES,
        (r) => records.push(r),
      ),
    );
  }
  return { lines, records };
}

/** A tick row's difference lines over its whole call. */
function tickRowDifference(id: number): string[] {
  const row = tickRow(id);
  const out = tickTicks({ ...row, content: TICK });
  return differenceLines(
    decode(row.words),
    decode(out.words),
    row.ground,
    out.ground,
    SHEETS,
    DEFAULT_NAMES,
  );
}

/**
 * A batch of 10 on RV-02's `segment2.jsonl` (the act and tick tables carry no `Area`, which a run
 * needs): row 2's state and content, whose goblin is awake, and the combat actions rows 2 to 4 play
 * on it (a skill on the goblin, a skill on self, a potion), with waits between.
 */
function batchOf10(): { base: Omit<Segment, "actions">; actions: Action[] } {
  const row = segment2Row(2);
  const base = {
    words: row.words,
    content: SEGMENT2,
    area: row.area,
    level: row.level,
    ground: row.ground,
    owed: 0,
    weight: 10,
  };
  const wait: Action = { kind: "wait" };
  const actions: Action[] = [
    segment2Row(2).actions[0]!,
    wait,
    segment2Row(3).actions[0]!,
    wait,
    segment2Row(4).actions[0]!,
    wait,
    wait,
    wait,
    wait,
    wait,
  ];
  return { base, actions };
}

function runOn(base: Omit<Segment, "actions">, actions: readonly Action[]) {
  return runRecorded({ ...base, actions: [...actions] }, CLASSES);
}

describe("the prefix runs (§7.2 item 1)", () => {
  it("the last prefix's words equal the full run's, on every action of a batch of 10", () => {
    const { base, actions } = batchOf10();
    const prefixes = new Prefixes(runOn);
    for (let n = 1; n <= actions.length; n++) {
      const runs = prefixes.at(base, actions.slice(0, n));
      expect(writeWords(runs[n]!.words)).toEqual(
        writeWords(runOn(base, actions.slice(0, n)).words),
      );
    }
  });

  it("the state after action k in the full run is the end of the run on the first k actions", () => {
    const { base, actions } = batchOf10();
    const runs = new Prefixes(runOn).at(base, actions);
    const full = runs[actions.length]!;
    // Each `act` call's input words are the state before its action: the end of the prefix before it
    const combat = actions.flatMap((a, k) =>
      ["attack", "skill", "item"].includes(a.kind) ? [k] : [],
    );
    expect(full.acts.length).toBe(3);
    expect(full.ticks.length).toBeGreaterThan(3);
    full.acts.forEach((act, j) => {
      expect(writeWords(act.call.words), `act ${j}`).toEqual(writeWords(runs[combat[j]!]!.words));
    });
    // And each prefix's ticks calls are the full run's first ones
    for (let k = 0; k <= actions.length; k++) {
      runs[k]!.ticks.forEach((t, i) => {
        expect(writeWords(t.call.words)).toEqual(writeWords(full.ticks[i]!.call.words));
      });
    }
  });

  it("an input adds one run; a new base or an action removed empties the cache", () => {
    const { base, actions } = batchOf10();
    const prefixes = new Prefixes(runOn);
    prefixes.at(base, actions.slice(0, 3));
    // The owed ticks' run and one a prefix
    expect(prefixes.computed).toBe(4);
    prefixes.at(base, actions.slice(0, 4));
    expect(prefixes.computed).toBe(5);
    // A send, a reveal, a state read again: a new base, every prefix run again
    const read = { ...base };
    prefixes.at(read, actions.slice(0, 4));
    expect(prefixes.computed).toBe(10);
    // An action removed: emptied, the shorter batch run again
    prefixes.at(read, actions.slice(0, 3));
    expect(prefixes.computed).toBe(14);
    expect(prefixes.size).toBe(4);
    // An action changed
    prefixes.at(read, [...actions.slice(0, 2), { kind: "wait" }]);
    expect(prefixes.computed).toBe(18);
    // Unchanged: nothing run
    prefixes.at(read, [...actions.slice(0, 2), { kind: "wait" }]);
    expect(prefixes.computed).toBe(18);
  });
});

describe("the one-tick replay (§7.2 item 2)", () => {
  it("n chained calls of tickTicks with n = 1 give one call of n, on every row of the tick table", () => {
    let rows = 0;
    for (const id of tickIds()) {
      const row = tickRow(id);
      const call = { ...row, content: TICK };
      const states = replayTicks(call);
      expect(states).toHaveLength(row.n + 1);
      expect(replayAgrees(states[row.n]!, tickTicks(call)), `tick.jsonl row ${id}`).toBe(true);
      rows += 1;
    }
    expect(rows).toBe(120);
  });

  it("a goblin's hit, attributed with its arc", () => {
    expect(tickRowLines(64).lines).toEqual([
      "The runt struck you: 67 damage, from behind: critical",
    ]);
    // A goblin's plain weapon hit (tick cost 1) leaves no recovery and no recharge on its words
    expect(tickRowLines(57)).toEqual({
      lines: ["The runt struck you: 117 damage, from behind: critical"],
      records: [],
    });
  });

  it("the adventurer's activation resolved: its hits, and a goblin's on it apart", () => {
    expect(tickRowLines(115).lines).toEqual([
      "The runt struck you: 117 damage, from behind: critical",
      "Your Skill 40 hit the runt: 113 damage",
    ]);
  });

  it("a trap's hit, and a change step 3 explains alone is no hit", () => {
    expect(tickRowLines(113).lines).toEqual(["A trap struck the runt: 56 damage"]);
    expect(tickRowLines(10).lines).toEqual([]);
    expect(tickRowLines(36)).toEqual({ lines: [], records: [] });
  });

  it("a held Alerted goblin in reach is no striker: a trap's damage stays the trap's", () => {
    // Row 64's state (the runt in reach of the adventurer), the runt held Alerted; the adventurer
    // loses 30 health in a tick where row 113's trap is triggered
    const row = tickRow(64);
    const call = { ...row, content: TICK };
    const trapRow = tickRow(113);
    const trapAfter = tickTicks({ ...trapRow, content: TICK }).ground;
    const withRunt = (ai: number) => {
      const g = loadGoblin(row.words.goblins[0]!, SHEETS);
      g.ai = ai;
      const words = { ...row.words, goblins: [{ ...storeGoblin(g), awake: true }] };
      const before = decode(words);
      const later = decode({ ...words, clock: words.clock + 1 });
      later.members[0]!.health = before.members[0]!.health - 30;
      const records: LogRecord[] = [];
      const lines = tickLines(
        call,
        1,
        before,
        later,
        trapRow.ground,
        trapAfter,
        SHEETS,
        DEFAULT_NAMES,
        (r) => records.push(r),
      );
      return { lines, records };
    };
    const alerted = withRunt(2);
    expect(alerted.lines).toHaveLength(1);
    expect(alerted.lines[0]).toMatch(/^A trap struck you: \d+ damage$/);
    expect(alerted.records).toEqual([]);
    // The same runt Engaged, its chosen target the adventurer: it is the striker
    expect(withRunt(3).lines[0]).toMatch(/^The runt struck you: \d+ damage/);
  });

  it("replays without changing the call's words", () => {
    const row = tickRow(118);
    const call = { ...row, content: TICK };
    const felts = writeWords(call.words);
    replayTicks(call);
    expect(writeWords(call.words)).toEqual(felts);
  });

  it("two goblins striking in one tick: the joint line and the unattributed record", () => {
    const { lines, records } = tickRowLines(118);
    expect(lines).toEqual(["The first runt and the second runt struck you: 1 damage"]);
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      kind: "grimworld.log-unattributed",
      tick: 1,
      actor: 0,
      change: -1,
      goblins: [8, 9],
    });
  });
});

describe("the difference lines (§7.1)", () => {
  it("a kill", () => {
    expect(tickRowDifference(97)).toContain("The runt is killed");
  });

  it("a condition gained and one ended", () => {
    expect(tickRowDifference(113)).toContain("The runt is crippled (2 ticks)");
    expect(tickRowDifference(10)).toEqual(["You lost 6 health", "You are no longer bleeding"]);
  });

  it("an activation started, resolved, and interrupted", () => {
    expect(tickRowDifference(59)).toContain("The runt starts Skill 24 (2 ticks)");
    expect(tickRowDifference(91)).toContain("The runt finishes Skill 24");
    // Row 91's goblin, its activation stopped before its deadline
    const row = tickRow(91);
    const g = loadGoblin(row.words.goblins[0]!, SHEETS);
    g.act_slot = 255;
    g.act_target = 0;
    g.act_deadline = 0;
    const after = { ...row.words, goblins: [storeGoblin(g)] };
    expect(
      differenceLines(
        decode(row.words),
        decode(after),
        row.ground,
        row.ground,
        SHEETS,
        DEFAULT_NAMES,
      ),
    ).toEqual(["You interrupted the runt"]);
  });

  it("a trap triggered, and the adventurer defeated", () => {
    expect(tickRowDifference(113)).toContain("A trap was triggered");
    expect(tickRowDifference(117)).toContain("You are defeated");
  });
});

describe("a batch's lines", () => {
  it("each action in words, its ticks' hits, its difference; a refusal muted", () => {
    const { base, actions } = batchOf10();
    const runs = new Prefixes(runOn).at(base, actions);
    const lines = batchLines({ ...base, board: boardOf(base), actions }, runs, {
      report: () => {},
    });
    expect(lines).toHaveLength(10);
    expect(lines[0]![0]!.text).toMatch(/^You used Skill \d+ on the /);
    expect(lines[1]![0]!.text).toBe("You waited");
    expect(lines[4]![0]!.text).toMatch(/^You drank a Potion \d+$/);
    // The goblin's activation, started during the first action's ticks and resolved in the third's
    expect(lines[0]!.map((l) => l.text)).toContain("The runt starts Skill 26 (2 ticks)");
    expect(lines[2]!.map((l) => l.text)).toContain("The runt finishes Skill 26");
    // The tenth does not fit the weight: no line
    expect(lines[9]).toEqual([]);
    expect(lines.flat().every((l) => l.status === "predicted")).toBe(true);
    // An attack on a goblin out of reach is refused: its line, muted
    const far = [{ kind: "attack", entity: 9999 } as Action];
    const refused = batchLines(
      { ...base, board: boardOf(base), actions: far },
      new Prefixes(runOn).at(base, far),
      {
        report: () => {},
      },
    );
    expect(refused).toEqual([
      [{ text: "Not a valid target.", tone: "refusal", status: "predicted" }],
    ]);
  });
});

/** The board of the window around the base's adventurer. */
function boardOf(base: Omit<Segment, "actions">) {
  const { x, y } = memberPlace(loadWorld(base.words, indexSheets(base.content)).members[0]!);
  return segmentBoard(base.area, x, y);
}

describe("the log keeps 100 lines (§7.3)", () => {
  it("the 101st line drops the first", () => {
    const log = new CombatLog();
    const line = (k: number) => ({
      text: `line ${k}`,
      tone: "event" as const,
      status: "predicted" as const,
    });
    log.add(Array.from({ length: MAX_LINES }, (_, k) => line(k)));
    expect(log.lines).toHaveLength(100);
    expect(log.lines[0]!.text).toBe("line 0");
    log.add([line(100)]);
    expect(log.lines).toHaveLength(100);
    expect(log.lines[0]!.text).toBe("line 1");
    expect(log.lines.at(-1)!.text).toBe("line 100");
  });

  it("confirms the predicted lines, or strikes them when the chain differed", () => {
    const log = new CombatLog();
    log.add([{ text: "You waited", tone: "event", status: "predicted" }]);
    log.confirm();
    expect(log.lines[0]!.status).toBe("confirmed");
    log.add([{ text: "You waited", tone: "event", status: "predicted" }]);
    log.correct();
    expect(log.lines.map((l) => [l.text, l.status])).toEqual([
      ["You waited", "confirmed"],
      ["You waited", "struck"],
      ["The world corrected itself", "confirmed"],
    ]);
    log.clear();
    expect(log.lines).toEqual([]);
  });
});

describe("the cost of an input (§7.2), measured", () => {
  it("one input with and without the replay, on the tick table's heaviest row", () => {
    // The median of `runs` timings of `f`; one that returns a number times itself (its setup apart)
    const median = (f: () => unknown, runs = 41): number => {
      const times: number[] = [];
      for (let k = 0; k < runs; k++) {
        const t0 = performance.now();
        const own = f();
        times.push(typeof own === "number" ? own : performance.now() - t0);
      }
      return times.sort((a, b) => a - b)[Math.floor(runs / 2)]!;
    };
    // The heaviest row: the most goblins, then the most ticks (a choice by timing is noisy)
    const heaviest = tickIds()
      .map((id) => ({ id, call: { ...tickRow(id), content: TICK } }))
      .sort(
        (a, b) => b.call.words.goblins.length - a.call.words.goblins.length || b.call.n - a.call.n,
      )[0]!;
    const { call } = heaviest;
    const without = median(() => tickTicks(call));
    const withReplay = median(() => {
      const out = tickTicks(call);
      replayLinesOf(call, out);
    });
    // The batch of 10's last input: one new prefix run, and its action's lines
    const { base, actions } = batchOf10();
    const board = boardOf(base);
    const inputWithout = median(() => {
      const prefixes = new Prefixes(runOn);
      prefixes.at(base, actions.slice(0, 9));
      const t0 = performance.now();
      prefixes.at(base, actions);
      return performance.now() - t0;
    }, 11);
    const inputWith = median(() => {
      const prefixes = new Prefixes(runOn);
      prefixes.at(base, actions.slice(0, 9));
      const t0 = performance.now();
      const runs = prefixes.at(base, actions);
      batchLines({ ...base, board, actions }, runs, { from: 10, report: () => {} });
      return performance.now() - t0;
    }, 11);
    const inputNoReplay = median(() => {
      const prefixes = new Prefixes(runOn);
      prefixes.at(base, actions.slice(0, 9));
      const t0 = performance.now();
      const runs = prefixes.at(base, actions);
      batchLines({ ...base, board, actions }, runs, { from: 10, replay: false, report: () => {} });
      return performance.now() - t0;
    }, 11);
    console.info(
      `CLI-05a cost: tick.jsonl row ${heaviest.id} (n ${call.n}, ${call.words.goblins.length} goblins): ` +
        `${without.toFixed(3)} ms without the replay, ${withReplay.toFixed(3)} ms with it; ` +
        `the batch of 10's 10th input: ${inputWithout.toFixed(3)} ms its run alone, ` +
        `${inputNoReplay.toFixed(3)} ms with its lines but no replay, ${inputWith.toFixed(3)} ms with the replay`,
    );
    // Loose bounds, far above the figures measured (about 2 ms), so a regression shows (§7.2: one
    // frame is 16 ms)
    expect(withReplay).toBeLessThan(50);
    expect(inputWith).toBeLessThan(50);
  });
});

/** The replay's lines of one call and its recorded output. */
function replayLinesOf(
  call: Parameters<typeof tickTicks>[0],
  out: ReturnType<typeof tickTicks>,
): void {
  const states = replayTicks(call);
  replayAgrees(states[states.length - 1]!, out);
  for (let k = 1; k < states.length; k++) {
    const [b, a] = [states[k - 1]!, states[k]!];
    tickLines(
      call,
      k,
      decode(b.words),
      decode(a.words),
      b.ground,
      a.ground,
      SHEETS,
      DEFAULT_NAMES,
      () => {},
    );
  }
}
