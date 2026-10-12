import { describe, expect, it, vi } from "vitest";
import {
  type CombatAim,
  CombatController,
  type CombatRules,
  type CombatTarget,
  FIGHT_LINES,
  playedLine,
} from "./controller";
import { FIGHT, combatFixture } from "./fixture";
import { MAX_LINES } from "./log";
import type { Armed, CombatState } from "./state";

/** The fight's slots (fixture.ts): Cleave, Shield bash, Charge, Taunt, Second wind, three empty. */
const CLEAVE: Armed = { kind: "skill", slot: 0 };
const SHIELD_BASH: Armed = { kind: "skill", slot: 1 };
const CHARGE: Armed = { kind: "skill", slot: 2 };
const TAUNT: Armed = { kind: "skill", slot: 3 };
const SECOND_WIND: Armed = { kind: "skill", slot: 4 };
const EMPTY: Armed = { kind: "skill", slot: 5 };
const HEALING: Armed = { kind: "item", slot: 0 };
const EMPTIED: Armed = { kind: "item", slot: 2 };
const NO_ITEM: Armed = { kind: "item", slot: 3 };

/** A fixture with every slot of the bar ready, and the rules as fakes. */
function ready(): CombatState {
  const state = combatFixture();
  const bar = state.adventurer.bar.map((s) =>
    s.skill ? { ...s, state: "ready" as const, ticks: null } : s,
  );
  return { ...state, adventurer: { ...state.adventurer, bar } };
}

function fakes(
  aims: Partial<Record<string, Partial<CombatAim>>> = {},
): CombatRules & { played: [Armed, CombatTarget][] } {
  const played: [Armed, CombatTarget][] = [];
  return {
    played,
    aim: (state, armed) => {
      const slot =
        armed.kind === "skill"
          ? state.adventurer.bar[armed.slot]?.skill?.addressing
          : state.adventurer.belt[armed.slot]?.addressing;
      const self = slot === "self" ? [state.adventurer.entity] : [];
      return {
        addressing: slot ?? "self",
        reach: [],
        greyed: [],
        marked: self,
        ...aims[`${armed.kind}${armed.slot}`],
      };
    },
    play: (state, armed, target) => (played.push([armed, target]), state),
  };
}

function controller(state = ready(), rules = fakes()) {
  const c = new CombatController(state);
  c.setRules(rules);
  return c;
}

describe("arming (CLI-05 brief §2.4, §3)", () => {
  it("a tap or a key arms a ready slot; another slot arms instead", () => {
    const c = controller();
    c.slot(CHARGE);
    expect(c.view().armed).toEqual(CHARGE);
    expect(c.view().aim?.addressing).toBe("foe");
    c.slot(CLEAVE);
    expect(c.view().armed).toEqual(CLEAVE);
  });

  it("a SELF skill plays on the second tap, on the adventurer", () => {
    const rules = fakes();
    const c = controller(ready(), rules);
    c.slot(SHIELD_BASH);
    expect(rules.played).toEqual([]);
    c.slot(SHIELD_BASH);
    expect(rules.played).toEqual([[SHIELD_BASH, { tile: false, entity: 0 }]]);
    expect(c.view().armed).toBeNull();
    expect(c.view().log.at(-1)).toEqual({
      text: "You used Shield bash",
      tone: "event",
      status: "predicted",
    });
  });

  it("any other skill is disarmed by its second tap", () => {
    const rules = fakes();
    const c = controller(ready(), rules);
    c.slot(CHARGE);
    c.slot(CHARGE);
    expect(c.view().armed).toBeNull();
    expect(rules.played).toEqual([]);
  });

  it("a potion addressed to the adventurer plays on the second tap", () => {
    const rules = fakes();
    const c = controller(ready(), rules);
    c.slot(HEALING);
    c.slot(HEALING);
    expect(rules.played).toEqual([[HEALING, { tile: false, entity: 0 }]]);
    expect(c.view().log.at(-1)?.text).toBe("You drank a Healing potion");
  });

  it("an ALLY slot alone plays on the adventurer by the second tap", () => {
    const rules = fakes({ skill2: { addressing: "ally", marked: [0] } });
    const c = controller(ready(), rules);
    c.slot(CHARGE);
    c.slot(CHARGE);
    expect(rules.played).toEqual([[CHARGE, { tile: false, entity: 0 }]]);
  });

  it("a slot not ready says its line and arms nothing", () => {
    const c = controller(combatFixture());
    c.slot(SHIELD_BASH);
    expect(c.view()).toMatchObject({ armed: null, said: "Recharging: 3 ticks." });
    c.slot(SECOND_WIND);
    expect(c.view()).toMatchObject({ armed: null, said: "Not enough energy." });
    c.slot(TAUNT);
    expect(c.view().said).toBe("Not enough adrenaline.");
    c.slot(CLEAVE);
    expect(c.view().said).toBe("Needs its weapon.");
    c.slot(EMPTIED);
    expect(c.view()).toMatchObject({ armed: null, said: "None left." });
    // An armed slot stays armed when another tap is refused.
    c.slot(CHARGE);
    c.slot(SECOND_WIND);
    expect(c.view().armed).toEqual(CHARGE);
  });

  it("while activating, every slot is not now, and its own says its ticks", () => {
    const c = controller(combatFixture("activating"));
    c.slot(CLEAVE);
    expect(c.view()).toMatchObject({ armed: null, said: "You are activating a skill." });
    c.slot(CHARGE);
    expect(c.view().said).toBe("Activating: 1 tick.");
    c.slot(HEALING);
    expect(c.view().said).toBe("You are activating a skill.");
  });

  it("an empty slot does nothing and says nothing", () => {
    const listener = vi.fn();
    const c = controller();
    c.subscribe(listener);
    c.slot(EMPTY);
    c.slot(NO_ITEM);
    c.inspect(EMPTY);
    expect(listener).not.toHaveBeenCalled();
    expect(c.view()).toMatchObject({ armed: null, said: "", inspected: null });
  });
});

describe("targets (§4.1)", () => {
  const foes = { skill2: { marked: [FIGHT.runt, FIGHT.hobgoblin] } };

  it("a tap on a marked goblin plays on it", () => {
    const rules = fakes(foes);
    const c = controller(ready(), rules);
    c.slot(CHARGE);
    expect(c.actor(FIGHT.hobgoblin)).toBe(true);
    expect(rules.played).toEqual([[CHARGE, { tile: false, entity: FIGHT.hobgoblin }]]);
    expect(c.view().log.at(-1)?.text).toBe("You used Charge on the hobgoblin");
  });

  it("a goblin out of reach, or not a valid target, says why and stays armed", () => {
    const rules = fakes(foes);
    const c = controller(ready(), rules);
    c.slot(CHARGE);
    expect(c.actor(FIGHT.skirmisher)).toBe(true);
    expect(c.view()).toMatchObject({ armed: CHARGE, said: "Out of reach." });
    expect(c.actor(0)).toBe(true);
    expect(c.view().said).toBe("Not a valid target.");
    expect(rules.played).toEqual([]);
  });

  it("taps go to the map when nothing is armed", () => {
    const c = controller();
    expect(c.actor(FIGHT.runt)).toBe(false);
    expect(c.tile({ x: 1, y: 1 })).toBe(false);
  });

  it("a tap on a tile with no actor disarms a skill not aimed at a tile", () => {
    const c = controller(ready(), fakes(foes));
    c.slot(CHARGE);
    expect(c.tile({ x: 20, y: 7 })).toBe(true);
    expect(c.view().armed).toBeNull();
  });

  it("a TILE skill previews on the first tap and plays on the second on the same tile", () => {
    const reach = [
      { x: 22, y: 7 },
      { x: 21, y: 7 },
    ];
    const rules = fakes({ skill2: { addressing: "tile", reach } });
    const c = controller(ready(), rules);
    c.slot(CHARGE);
    c.tile({ x: 22, y: 7 });
    expect(c.view().preview).toEqual({ x: 22, y: 7 });
    c.tile({ x: 21, y: 7 });
    expect(c.view().preview).toEqual({ x: 21, y: 7 });
    expect(rules.played).toEqual([]);
    c.tile({ x: 21, y: 7 });
    expect(rules.played).toEqual([[CHARGE, { tile: true, at: { x: 21, y: 7 } }]]);
    expect(c.view().log.at(-1)?.text).toBe("You used Charge on (21, 7)");
  });

  it("a TILE skill previews a tile where a goblin stands, and plays on the second tap", () => {
    const state = ready();
    const at = state.goblins[0]!.tile;
    const rules = fakes({ skill2: { addressing: "tile", reach: [at] } });
    const c = controller(state, rules);
    c.slot(CHARGE);
    expect(c.tile(at)).toBe(true);
    expect(c.view()).toMatchObject({ preview: at, said: "", armed: CHARGE });
    c.tile(at);
    expect(rules.played).toEqual([[CHARGE, { tile: true, at }]]);
  });

  it("a TILE skill previews the adventurer's own tile when it is in reach", () => {
    const state = ready();
    const at = state.adventurer.tile;
    const c = controller(state, fakes({ skill2: { addressing: "tile", reach: [at] } }));
    c.slot(CHARGE);
    c.tile(at);
    expect(c.view()).toMatchObject({ preview: at, said: "" });
  });

  it("a TILE skill out of reach says so and previews nothing", () => {
    const c = controller(ready(), fakes({ skill2: { addressing: "tile", reach: [] } }));
    c.slot(CHARGE);
    c.tile({ x: 2, y: 2 });
    expect(c.view()).toMatchObject({ preview: null, said: "Out of reach.", armed: CHARGE });
  });

  it("F cycles the marked targets nearest first, Shift+F back, Enter plays", () => {
    const rules = fakes(foes);
    const c = controller(ready(), rules);
    expect(c.cycle(1)).toBe(false);
    expect(c.go()).toBe(false);
    c.slot(CHARGE);
    expect(c.go()).toBe(false);
    c.cycle(1);
    expect(c.view().focus).toBe(FIGHT.runt);
    c.cycle(1);
    expect(c.view().focus).toBe(FIGHT.hobgoblin);
    c.cycle(1);
    expect(c.view().focus).toBe(FIGHT.runt);
    c.cycle(-1);
    expect(c.view().focus).toBe(FIGHT.hobgoblin);
    expect(c.go()).toBe(true);
    expect(rules.played).toEqual([[CHARGE, { tile: false, entity: FIGHT.hobgoblin }]]);
    expect(c.view().focus).toBeNull();
  });

  it("Shift+F first goes to the farthest", () => {
    const c = controller(ready(), fakes(foes));
    c.slot(CHARGE);
    c.cycle(-1);
    expect(c.view().focus).toBe(FIGHT.hobgoblin);
  });
});

describe("Esc (§4.1's order)", () => {
  it("closes an inspection, then disarms, then leaves the key to the map", () => {
    const c = controller();
    c.slot(CHARGE);
    c.inspect(SHIELD_BASH);
    expect(c.view().inspected).toEqual(SHIELD_BASH);
    expect(c.escape()).toBe(true);
    expect(c.view()).toMatchObject({ inspected: null, armed: CHARGE });
    expect(c.escape()).toBe(true);
    expect(c.view().armed).toBeNull();
    expect(c.escape()).toBe(false);
  });

  it("an inspection of the same slot again closes it; arming closes it", () => {
    const c = controller();
    c.inspect(CHARGE);
    c.inspect(CHARGE);
    expect(c.view().inspected).toBeNull();
    c.inspect(CHARGE);
    c.slot(CLEAVE);
    expect(c.view().inspected).toBeNull();
  });
});

describe("the controller's state", () => {
  it("takes the rules late: an armed slot gets its aim once they come", () => {
    const c = new CombatController(ready());
    c.slot(CHARGE);
    expect(c.view().aim).toBeNull();
    c.setRules(fakes());
    expect(c.view().aim?.addressing).toBe("foe");
  });

  it("follows the adventurer's tile, and its aim with it", () => {
    const aim = vi.fn(fakes().aim);
    const c = controller(ready(), { ...fakes(), aim });
    c.slot(CHARGE);
    c.moved({ x: 22, y: 7 });
    expect(c.view().state.adventurer.tile).toEqual({ x: 22, y: 7 });
    expect(aim.mock.lastCall?.[0].adventurer.tile).toEqual({ x: 22, y: 7 });
  });

  it("keeps the last 100 lines of the log (§7.3)", () => {
    const lines = Array.from({ length: MAX_LINES }, (_, i) => ({
      text: `line ${i}`,
      tone: "event" as const,
      status: "confirmed" as const,
    }));
    const c = controller(ready());
    const full = new CombatController(ready(), lines);
    full.setRules(fakes());
    full.note("You waited");
    expect(full.view().log).toHaveLength(MAX_LINES);
    expect(full.view().log[0]?.text).toBe("line 1");
    expect(full.view().log.at(-1)?.text).toBe("You waited");
    expect(c.view().log).toEqual([]);
  });

  it("the fight's fixed lines show each tone (§9)", () => {
    expect(FIGHT_LINES.some((l) => l.status === "confirmed")).toBe(true);
    expect(FIGHT_LINES.some((l) => l.status === "predicted")).toBe(true);
    expect(FIGHT_LINES.at(-1)?.tone).toBe("refusal");
  });

  it("names the played line by the target's caste", () => {
    const state = combatFixture();
    expect(playedLine(state, CHARGE, { tile: false, entity: FIGHT.shaman })).toBe(
      "You used Charge on the shaman",
    );
    expect(playedLine(state, HEALING, { tile: false, entity: FIGHT.runt })).toBe(
      "You threw a Healing potion on the runt",
    );
  });
});
