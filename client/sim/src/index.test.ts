import { describe, expect, it } from "vitest";
import { clamp } from "./index";

describe("clamp", () => {
  it("keeps a value inside the range", () => {
    expect(clamp(5, 0, 10)).toBe(5);
  });

  it("brings a value back to the nearest bound", () => {
    expect(clamp(-3, 0, 10)).toBe(0);
    expect(clamp(42, 0, 10)).toBe(10);
  });
});
