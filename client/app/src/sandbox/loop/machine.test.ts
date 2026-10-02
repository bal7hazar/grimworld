import { describe, expect, it } from "vitest";
import type { LoopIntent } from "../../input/intent";
import { OUTPOST, TOWN, globalTile } from "../fixtures/region";
import {
  type LoopEvent,
  type LoopState,
  gateHere,
  gatesFrom,
  hubState,
  leaveOffer,
  leaveQuestion,
  step,
} from "./machine";

function run(state: LoopState, ...events: LoopEvent[]): LoopState {
  return events.reduce(step, state);
}

/** Into the zone through the hub's first gate, the entry drawn. */
function enter(hub: number): LoopState {
  const gate = gatesFrom(hub)[0]!;
  return run(
    hubState(hub),
    { kind: "open gate screen" },
    { kind: "enter gate", gate: gate.id },
    {
      kind: "entry drawn",
    },
  );
}

describe("the loop's screens (CLI-03c)", () => {
  it("hub → service → back, hub → Gate screen → back", () => {
    let s = run(hubState(TOWN), { kind: "open service", service: "smith" });
    expect(s.screen).toEqual({ kind: "service", hub: TOWN, service: "smith" });
    s = step(s, { kind: "back" });
    expect(s.screen).toEqual({ kind: "hub", hub: TOWN, inspected: null });
    s = run(s, { kind: "open gate screen" });
    expect(s.screen).toEqual({ kind: "gate", hub: TOWN });
    expect(step(s, { kind: "back" }).screen.kind).toBe("hub");
  });

  it("inspects a present adventurer of this hub only", () => {
    const s = step(hubState(TOWN), { kind: "inspect adventurer", adventurer: 12 });
    expect(s.screen).toEqual({ kind: "hub", hub: TOWN, inspected: 12 });
    expect(s.said).toBe("inspect Tobin, vanguard level 3");
    expect(step(hubState(TOWN), { kind: "inspect adventurer", adventurer: 21 }).screen).toEqual(
      hubState(TOWN).screen,
    );
    expect(step(s, { kind: "back" }).screen).toEqual(hubState(TOWN).screen);
  });

  it("the Gate screen lists the hub's gates from the fixed data", () => {
    expect(gatesFrom(TOWN).map((g) => [g.id, g.destination])).toEqual([[1, 2]]);
    expect(gatesFrom(OUTPOST).map((g) => [g.id, g.destination])).toEqual([[101, 2]]);
  });

  it("enter gate: the entry moment, then the instance on the gate's entry tile", () => {
    let s = run(hubState(TOWN), { kind: "open gate screen" }, { kind: "enter gate", gate: 1 });
    expect(s.screen).toEqual({ kind: "entry", hub: TOWN, gate: 1 });
    // A gate of another hub is not entered from here.
    expect(
      step(run(hubState(TOWN), { kind: "open gate screen" }), { kind: "enter gate", gate: 101 })
        .screen.kind,
    ).toBe("gate");
    s = step(s, { kind: "entry drawn" });
    expect(s.screen).toMatchObject({
      kind: "instance",
      location: 2,
      gate: 1,
      entry: { x: 0, y: 7 },
    });
    // Skipping the wait answers the same.
    const skipped = run(
      hubState(TOWN),
      { kind: "open gate screen" },
      { kind: "enter gate", gate: 1 },
      { kind: "skip entry" },
    );
    expect(skipped.screen).toEqual(s.screen);
  });

  it("(a) leave on a hub gate's anchor: returned, report, that gate's hub", () => {
    let s = enter(OUTPOST);
    // The outpost's gate puts the adventurer on gate 102's anchor: no offer on arrival.
    expect(gateHere(s)?.id).toBe(102);
    expect(leaveOffer(s)).toBeNull();
    s = step(s, { kind: "moved", tile: { x: 39, y: 7 } });
    expect(leaveOffer(s)).toBeNull();
    expect(gateHere(s)).toBeNull();
    expect(step(s, { kind: "leave" }).screen.kind).toBe("instance");
    // Walk to the town's gate anchor (gate 2, chunk 0, tile 105): it leads to the town.
    s = step(s, { kind: "moved", tile: globalTile(0, 105) });
    expect(leaveOffer(s)?.id).toBe(2);
    s = step(s, { kind: "leave" });
    expect(s.screen).toEqual({ kind: "report", outcome: "returned", how: "gate", hub: TOWN });
    s = step(s, { kind: "close report" });
    expect(s.screen).toEqual({ kind: "hub", hub: TOWN, inspected: null });
    expect(s.lastHub).toBe(TOWN);
  });

  it("arrival on a gate's anchor: no automatic offer; stepping off and back on brings it", () => {
    let s = enter(OUTPOST);
    expect(s.screen).toMatchObject({ kind: "instance", left: false });
    expect(leaveOffer(s)).toBeNull();
    expect(gateHere(s)?.id).toBe(102);
    // The explicit Leave reaches the report (the confirmation path) at arrival.
    const left = step(s, { kind: "leave" });
    expect(left.screen).toEqual({ kind: "report", outcome: "returned", how: "gate", hub: OUTPOST });
    // The room reporting the entry tile again changes nothing.
    if (s.screen.kind !== "instance") throw new Error("not in the instance");
    const entryTile = s.screen.tile;
    s = step(s, { kind: "moved", tile: entryTile });
    expect(leaveOffer(s)).toBeNull();
    const arrival = entryTile;
    s = step(s, { kind: "moved", tile: { x: 39, y: 7 } });
    expect(leaveOffer(s)).toBeNull();
    // Back onto the arrival anchor (gate 102): the offer comes.
    s = step(s, { kind: "moved", tile: arrival });
    expect(leaveOffer(s)?.id).toBe(102);
    const anchor = globalTile(0, 105);
    s = step(s, { kind: "moved", tile: anchor });
    expect(leaveOffer(s)?.id).toBe(2);
  });

  it("off an anchor leave is ignored; back on it, the offer and the leave are taken", () => {
    let s = step(enter(TOWN), { kind: "moved", tile: { x: 39, y: 7 } });
    expect(gateHere(s)).toBeNull();
    expect(step(s, { kind: "leave" }).screen.kind).toBe("instance");
    s = step(s, { kind: "moved", tile: globalTile(0, 105) });
    expect(leaveOffer(s)?.id).toBe(2);
  });

  it("the I-5 question names the destination at arrival, and travel back otherwise", () => {
    const s = enter(OUTPOST);
    expect(leaveQuestion(gateHere(s))).toBe(
      "Leave the instance for Outpost B? The goblins will be back next time.",
    );
    expect(leaveQuestion(null)).toMatch(/^Travel back to the last hub visited/);
  });

  it("(b) travel back: returned, the last hub visited", () => {
    let s = step(enter(OUTPOST), { kind: "travel back" });
    expect(s.screen).toEqual({
      kind: "report",
      outcome: "returned",
      how: "travel back",
      hub: OUTPOST,
    });
    s = step(s, { kind: "close report" });
    expect(s.screen).toEqual(hubState(OUTPOST).screen);
  });

  it("(c) defeat: defeated, the last hub visited", () => {
    const s = step(enter(TOWN), { kind: "defeat now" });
    expect(s.screen).toEqual({ kind: "report", outcome: "defeated", how: "defeat", hub: TOWN });
    expect(step(s, { kind: "close report" }).screen).toEqual(hubState(TOWN).screen);
  });

  it("an intent the screen does not take changes only the log line", () => {
    const intents: LoopIntent[] = [
      { kind: "leave" },
      { kind: "travel back" },
      { kind: "close report" },
      { kind: "defeat now" },
      { kind: "skip entry" },
      { kind: "enter gate", gate: 1 },
    ];
    for (const intent of intents) {
      const s = step(hubState(TOWN), intent);
      expect(s.screen, intent.kind).toEqual(hubState(TOWN).screen);
      expect(s.said, intent.kind).toContain("nothing to do");
    }
    const report = step(enter(TOWN), { kind: "defeat now" });
    expect(step(report, { kind: "open gate screen" }).screen).toEqual(report.screen);
  });
});
