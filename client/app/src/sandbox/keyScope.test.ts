import { describe, expect, it, vi } from "vitest";
import type { KeyCommand, KeyLike } from "../input/keys";
import { KeyScope, ignoredTarget } from "./keyScope";

const press = (code: string, key = ""): KeyLike => ({
  code,
  key,
  shiftKey: false,
  ctrlKey: false,
  metaKey: false,
  altKey: false,
  repeat: false,
  isComposing: false,
});

describe("KeyScope", () => {
  it("gives the key to the top layer only, read with its screen; pops on close", () => {
    const scope = new KeyScope();
    const seen: string[] = [];
    const layer = (name: string, screen: "hub" | "instance", handled = true) => ({
      screen,
      handle: (command: KeyCommand | null) => {
        seen.push(`${name}:${command?.kind ?? "none"}`);
        return handled && command !== null;
      },
    });
    expect(scope.press(press("KeyQ"))).toBe(false);
    const closeScreen = scope.push(layer("screen", "hub"));
    expect(scope.press(press("Digit1"))).toBe(true);
    const closeDialog = scope.push(layer("dialog", "instance"));
    // The dialog is on top: the hub's digit is read with the instance's bindings (reserved: none).
    expect(scope.press(press("Digit1"))).toBe(false);
    expect(scope.press(press("Escape"))).toBe(true);
    closeDialog();
    expect(scope.press(press("Digit1"))).toBe(true);
    expect(seen).toEqual(["screen:service", "dialog:none", "dialog:escape", "screen:service"]);
    closeScreen();
    expect(scope.top()).toBeNull();
  });

  it("closing a layer under the top keeps the top", () => {
    const scope = new KeyScope();
    const a = { screen: "hub" as const, handle: vi.fn(() => true) };
    const b = { screen: "hub" as const, handle: vi.fn(() => true) };
    const closeA = scope.push(a);
    scope.push(b);
    closeA();
    expect(scope.top()).toBe(b);
    closeA();
    expect(scope.top()).toBe(b);
  });
});

describe("ignoredTarget", () => {
  it("leaves every key to text fields, lists and editable elements", () => {
    for (const tagName of ["INPUT", "TEXTAREA", "SELECT", "input"]) {
      expect(ignoredTarget({ tagName }, press("KeyQ"))).toBe(true);
      expect(ignoredTarget({ tagName }, press("Escape"))).toBe(true);
    }
    expect(ignoredTarget({ tagName: "DIV", isContentEditable: true }, press("KeyQ"))).toBe(true);
  });

  it("leaves Enter to a button or a link; other keys on them are the map's", () => {
    for (const tagName of ["BUTTON", "A"]) {
      expect(ignoredTarget({ tagName }, press("Enter"))).toBe(true);
      expect(ignoredTarget({ tagName }, press("NumpadEnter"))).toBe(true);
      expect(ignoredTarget({ tagName }, press("KeyQ"))).toBe(false);
      expect(ignoredTarget({ tagName }, press("Escape"))).toBe(false);
    }
    expect(ignoredTarget({ tagName: "DIV" }, press("Enter"))).toBe(false);
    expect(ignoredTarget({ tagName: "BODY" }, press("KeyQ"))).toBe(false);
    expect(ignoredTarget(null, press("KeyQ"))).toBe(false);
  });
});
