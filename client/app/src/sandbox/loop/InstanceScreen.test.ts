import { describe, expect, it } from "vitest";
import type { KeyLike } from "../../input/keys";
import { trapsTab } from "./InstanceScreen";

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
