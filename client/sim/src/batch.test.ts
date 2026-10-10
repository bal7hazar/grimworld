import { describe, expect, it } from "vitest";
import { admit, revealed } from "./batch";
import { CairoPanic } from "./felt";

describe("admit", () => {
  it("does not compute the u32 sum of records when ran is false (Cairo's short-circuit)", () => {
    expect(admit(0xffffffff, 1, 0, 1, false, 5)).toBe(4);
  });

  it("panics on the u32 sum when ran is true", () => {
    expect(() => admit(0xffffffff, 1, 0, 1, true, 5)).toThrow(new CairoPanic("u32_add Overflow"));
  });

  it("panics on the u8 sum of ticks and first records whatever ran is", () => {
    expect(() => admit(0, 0, 200, 56, false, 5)).toThrow(new CairoPanic("u8_add Overflow"));
  });
});

describe("revealed", () => {
  it("weighs 2 a chunk, floored at 0", () => {
    expect(revealed(10, 3)).toBe(4);
    expect(revealed(5, 3)).toBe(0);
  });

  it("narrows the chunks to u8 before the product: 128..=255 overflow the u8 product", () => {
    expect(revealed(10, 127)).toBe(0);
    expect(() => revealed(10, 128)).toThrow(new CairoPanic("u8_mul Overflow"));
    expect(() => revealed(10, 255)).toThrow(new CairoPanic("u8_mul Overflow"));
    expect(() => revealed(10, 256)).toThrow(new CairoPanic("Option::unwrap failed."));
  });
});
