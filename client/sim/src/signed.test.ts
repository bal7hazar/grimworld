// `signed.ts` against the edges of `helpers/signed.cairo`: the two's complement of an `i8` and an
// `i16`, each value's bits and back, and the panic of bits wider than the type.

import { describe, expect, it } from "vitest";
import { CairoPanic } from "./felt";
import { bits16, bits8, from16, from8 } from "./signed";

describe("SignedTrait", () => {
  it("writes an i8 in 8 bits", () => {
    expect([0, 1, 127, -1, -128].map(bits8)).toEqual([0n, 1n, 127n, 255n, 128n]);
  });

  it("writes an i16 in 16 bits", () => {
    expect([0, 1, 32767, -1, -32768].map(bits16)).toEqual([0n, 1n, 32767n, 65535n, 32768n]);
  });

  it("round-trips every i8 and every i16", () => {
    for (let v = -128; v <= 127; v++) expect(from8(bits8(v))).toBe(v);
    for (let v = -32768; v <= 32767; v++) expect(from16(bits16(v))).toBe(v);
  });

  it("reads the bits at and past the sign", () => {
    expect([from8(0x7fn), from8(0x80n), from8(0xffn)]).toEqual([127, -128, -1]);
    expect([from16(0x7fffn), from16(0x8000n), from16(0xffffn)]).toEqual([32767, -32768, -1]);
  });

  it("panics on bits wider than the type, as the failed try_into", () => {
    // 0x180 − 0x100 = 128 is not an i8; 0x18000 − 0x10000 = 32768 is not an i16
    expect(() => from8(0x180n)).toThrow(CairoPanic);
    expect(() => from16(0x18000n)).toThrow(CairoPanic);
    try {
      from8(0x180n);
    } catch (error) {
      expect((error as CairoPanic).data).toEqual(["Option::unwrap failed."]);
    }
  });

  it("refuses a value outside the type: a bug of the caller, not a Cairo panic", () => {
    expect(() => bits8(128)).toThrow(RangeError);
    expect(() => bits16(-32769)).toThrow(RangeError);
  });
});
