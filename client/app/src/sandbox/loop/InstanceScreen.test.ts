import { describe, expect, it } from "vitest";
import type { CombatView } from "../../combat/controller";
import { combatFixture } from "../../combat/fixture";
import type { Intent } from "../../input/intent";
import type { KeyLike } from "../../input/keys";
import { handArmedTap, trapsTab } from "./InstanceScreen";

const key = (code: string, more: Partial<KeyLike> = {}): KeyLike => ({
  code,
  key: code,
  shiftKey: false,
  ctrlKey: false,
  metaKey: false,
  altKey: false,
  repeat: false,
  isComposing: false,
  ...more,
});

/** The I-5 confirmation's Tab trap (review t-0095 of #344, note 2). */
describe("trapsTab", () => {
  it("keeps Tab and Shift+Tab inside the confirmation", () => {
    expect(trapsTab(key("Tab"))).toBe(true);
    expect(trapsTab(key("Tab", { shiftKey: true }))).toBe(true);
  });

  it("leaves Tab with Ctrl, Meta or Alt to the browser and the system", () => {
    for (const mod of ["ctrlKey", "metaKey", "altKey"] as const) {
      expect(trapsTab(key("Tab", { [mod]: true })), mod).toBe(false);
      expect(trapsTab(key("Tab", { [mod]: true, shiftKey: true })), mod).toBe(false);
    }
  });

  it("does nothing for another key", () => {
    expect(trapsTab(key("Enter"))).toBe(false);
    expect(trapsTab(key("KeyT"))).toBe(false);
  });
});

/** The armed tap's routing (review t-0263 of #482, note 3). */
describe("handArmedTap", () => {
  const state = combatFixture();
  const goblin = state.goblins.find((g) => g.alive);
  if (!goblin) throw new Error("the fixture has a living goblin");
  const tap: Intent = { kind: "tile", tile: goblin.tile };
  const stub = (addressing: "tile" | "foe") => {
    const calls: string[] = [];
    const view = {
      state,
      armed: { kind: "skill", slot: 0 },
      aim: { addressing },
    } as unknown as CombatView;
    return {
      calls,
      controller: {
        view: () => view,
        tile: () => (calls.push("tile"), true),
        actor: () => (calls.push("actor"), true),
      },
    };
  };

  it("gives an occupied tile to the controller's tile for a TILE aim", () => {
    const { calls, controller } = stub("tile");
    expect(handArmedTap(controller, tap)).toBeNull();
    expect(calls).toEqual(["tile"]);
  });

  it("gives an occupied tile to the controller's actor for another aim", () => {
    const { calls, controller } = stub("foe");
    expect(handArmedTap(controller, tap)).toBeNull();
    expect(calls).toEqual(["actor"]);
  });

  it("leaves the intent to the map when nothing is armed", () => {
    const { calls, controller } = stub("tile");
    const idle = { view: () => ({ state, armed: null, aim: null }) as unknown as CombatView };
    expect(handArmedTap({ ...controller, ...idle }, tap)).toBe(tap);
    expect(handArmedTap(undefined, tap)).toBe(tap);
    expect(calls).toEqual([]);
  });
});
