import { describe, expect, it } from "vitest";
import type { Facing } from "../render/view";
import {
  BINDINGS,
  type KeyLike,
  type KeyScreen,
  bindingsOf,
  keyCommand,
  verticalDirection,
} from "./keys";

const press = (code: string, more: Partial<KeyLike> = {}): KeyLike => ({
  code,
  key: code.replace(/^Key/, "").toLowerCase(),
  shiftKey: false,
  ctrlKey: false,
  metaKey: false,
  altKey: false,
  repeat: false,
  isComposing: false,
  ...more,
});

const SCREENS: readonly KeyScreen[] = ["hub", "instance", "service", "gate", "entry", "report"];
const OFF_MAP: readonly KeyScreen[] = ["service", "gate", "entry", "report"];

/** Every key event the table binds, one per match. */
const EVERY_MATCH = BINDINGS.flatMap((b) =>
  b.matches.map((m) =>
    m.key !== undefined
      ? press("Unidentified", { key: m.key })
      : press(m.code!, { shiftKey: m.shift ?? false }),
  ),
);

describe("the direction ring (§2)", () => {
  const RING: [string, Facing][] = [
    ["KeyQ", 3],
    ["KeyW", 2],
    ["KeyE", 1],
    ["KeyD", 0],
    ["KeyS", 5],
    ["KeyA", 4],
  ];

  it.each(RING)("%s steps toward %i in a hub and a zone, nowhere else", (code, direction) => {
    for (const screen of ["hub", "instance"] as const) {
      expect(keyCommand(press(code), screen)).toEqual({ kind: "step", direction });
    }
    for (const screen of OFF_MAP) expect(keyCommand(press(code), screen)).toBeNull();
  });

  it("is read by physical key: AZERTY's A (code KeyQ) is West", () => {
    expect(keyCommand(press("KeyQ", { key: "a" }), "instance")).toEqual({
      kind: "step",
      direction: 3,
    });
  });

  it("arrows: ← West, → East, ↑ ↓ the facing side's upper and lower hex", () => {
    expect(keyCommand(press("ArrowLeft"), "hub")).toEqual({ kind: "step", direction: 3 });
    expect(keyCommand(press("ArrowRight"), "hub")).toEqual({ kind: "step", direction: 0 });
    expect(keyCommand(press("ArrowUp"), "instance")).toEqual({ kind: "step", vertical: "up" });
    expect(keyCommand(press("ArrowDown"), "instance")).toEqual({ kind: "step", vertical: "down" });
  });

  it("↑ / ↓ resolve on the side faced", () => {
    for (const f of [0, 1, 5] as const) {
      expect(verticalDirection(f, "up")).toBe(1);
      expect(verticalDirection(f, "down")).toBe(5);
    }
    for (const f of [2, 3, 4] as const) {
      expect(verticalDirection(f, "up")).toBe(2);
      expect(verticalDirection(f, "down")).toBe(4);
    }
  });
});

describe("the guards", () => {
  it("with Ctrl, Meta or Alt, every binding is the browser's", () => {
    expect(EVERY_MATCH.length).toBeGreaterThan(30);
    for (const event of EVERY_MATCH) {
      for (const modifier of ["ctrlKey", "metaKey", "altKey"] as const) {
        for (const screen of SCREENS) {
          expect(keyCommand({ ...event, [modifier]: true }, screen)).toBeNull();
        }
      }
    }
  });

  it("an auto-repeat or a composition is nothing", () => {
    for (const event of EVERY_MATCH) {
      for (const screen of SCREENS) {
        expect(keyCommand({ ...event, repeat: true }, screen)).toBeNull();
        expect(keyCommand({ ...event, isComposing: true }, screen)).toBeNull();
      }
    }
  });

  it("Shift: F cycles back; with any other bound letter, nothing", () => {
    expect(keyCommand(press("KeyF", { shiftKey: true }), "hub")).toEqual({ kind: "cycle", by: -1 });
    expect(keyCommand(press("KeyF"), "hub")).toEqual({ kind: "cycle", by: 1 });
    for (const code of ["KeyQ", "KeyW", "KeyE", "KeyA", "KeyS", "KeyD", "KeyL"]) {
      for (const screen of SCREENS) {
        expect(keyCommand(press(code, { shiftKey: true }), screen)).toBeNull();
      }
    }
  });

  it("no binding uses Tab", () => {
    for (const binding of BINDINGS) {
      for (const match of binding.matches) {
        expect(match.code).not.toBe("Tab");
        expect(match.key).not.toBe("Tab");
      }
    }
    for (const screen of SCREENS) expect(keyCommand(press("Tab"), screen)).toBeNull();
  });
});

describe("the screens' keys", () => {
  it("1–9 open the services in a hub only, by digit row and numpad", () => {
    for (let n = 1; n <= 9; n++) {
      for (const code of [`Digit${n}`, `Numpad${n}`]) {
        expect(keyCommand(press(code), "hub")).toEqual({ kind: "service", index: n - 1 });
        for (const screen of SCREENS.filter((s) => s !== "hub")) {
          expect(keyCommand(press(code), screen)).toBeNull();
        }
      }
    }
  });

  it("L leaves on an instance only", () => {
    expect(keyCommand(press("KeyL"), "instance")).toEqual({ kind: "leave" });
    for (const screen of SCREENS.filter((s) => s !== "instance")) {
      expect(keyCommand(press("KeyL"), screen)).toBeNull();
    }
  });

  it("? opens the help everywhere, read by character whatever the code", () => {
    for (const screen of SCREENS) {
      for (const code of ["Slash", "Comma", "Minus"]) {
        expect(keyCommand(press(code, { key: "?", shiftKey: true }), screen)).toEqual({
          kind: "help",
        });
      }
    }
  });

  it("Esc everywhere; Enter, 0, + and − on the map only", () => {
    for (const screen of SCREENS) {
      expect(keyCommand(press("Escape"), screen)).toEqual({ kind: "escape" });
    }
    for (const screen of OFF_MAP) {
      expect(keyCommand(press("Enter"), screen)).toBeNull();
      expect(keyCommand(press("Digit0"), screen)).toBeNull();
      expect(keyCommand(press("Equal", { key: "+" }), screen)).toBeNull();
    }
    expect(keyCommand(press("Enter"), "hub")).toEqual({ kind: "go" });
    expect(keyCommand(press("NumpadEnter"), "instance")).toEqual({ kind: "go" });
  });

  it("+, = and NumpadAdd zoom in; - and NumpadSubtract out; 0 recentres", () => {
    const zoomIn = { kind: "zoom", by: 1 };
    const zoomOut = { kind: "zoom", by: -1 };
    expect(keyCommand(press("Equal", { key: "+", shiftKey: true }), "hub")).toEqual(zoomIn);
    expect(keyCommand(press("Equal", { key: "=" }), "hub")).toEqual(zoomIn);
    expect(keyCommand(press("NumpadAdd", { key: "+" }), "instance")).toEqual(zoomIn);
    expect(keyCommand(press("Minus", { key: "-" }), "hub")).toEqual(zoomOut);
    expect(keyCommand(press("NumpadSubtract", { key: "Subtract" }), "instance")).toEqual(zoomOut);
    expect(keyCommand(press("Digit0"), "hub")).toEqual({ kind: "recentre" });
    expect(keyCommand(press("Numpad0"), "instance")).toEqual({ kind: "recentre" });
  });

  it("the combat keys are reserved: nothing on an instance, listed as reserved", () => {
    const reserved = [
      ...[1, 2, 3, 4, 5, 6, 7, 8].map((n) => `Digit${n}`),
      "KeyZ",
      "KeyX",
      "KeyC",
      "KeyV",
      "Space",
      "KeyR",
    ];
    for (const code of reserved) {
      expect(keyCommand(press(code), "instance")).toBeNull();
      const listed = BINDINGS.find(
        (b) =>
          b.reserved && b.screens.includes("instance") && b.matches.some((m) => m.code === code),
      );
      expect(listed, code).toBeDefined();
      expect(listed!.matches.every((m) => m.command === null)).toBe(true);
    }
  });

  it("every bound key has one meaning per screen", () => {
    for (const screen of SCREENS) {
      const seen = new Set<string>();
      for (const binding of BINDINGS.filter((b) => b.screens.includes(screen))) {
        for (const m of binding.matches) {
          const id = m.key !== undefined ? `key:${m.key}` : `code:${m.code}:${m.shift ?? false}`;
          expect(seen.has(id), `${screen} ${id}`).toBe(false);
          seen.add(id);
        }
      }
    }
  });

  it("the help lists a screen's bindings, the reserved ones last", () => {
    const instance = bindingsOf("instance");
    const firstReserved = instance.findIndex((b) => b.reserved);
    expect(firstReserved).toBeGreaterThan(0);
    expect(instance.slice(firstReserved).every((b) => b.reserved)).toBe(true);
    expect(bindingsOf("service").map((b) => b.keys)).toEqual(["Esc", "?"]);
    expect(bindingsOf("hub").some((b) => b.reserved)).toBe(false);
  });
});
