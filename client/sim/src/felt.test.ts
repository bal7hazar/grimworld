import { describe, expect, it } from "vitest";
import {
  CairoPanic,
  P,
  add,
  div,
  fromFelt,
  i16,
  i32,
  narrow,
  readShortString,
  shortString,
  sub,
  toFelt,
  u16,
  u8,
} from "./felt";

describe("felt", () => {
  it("is Starknet's prime", () => {
    expect(P).toBe(0x800000000000011000000000000000000000000000000000000000000000001n);
  });

  it("decodes a negative integer from P − |v| and back", () => {
    expect(fromFelt(i16, P - 1n)).toBe(-1n);
    expect(fromFelt(i16, P - 32768n)).toBe(-32768n);
    expect(toFelt(i16, -5n)).toBe(P - 5n);
    expect(fromFelt(u8, 255n)).toBe(255n);
  });

  it("refuses a felt outside the type", () => {
    expect(() => fromFelt(i16, P - 32769n)).toThrow(RangeError);
    expect(() => fromFelt(u8, 256n)).toThrow(RangeError);
    expect(() => fromFelt(u16, P - 1n)).toThrow(RangeError);
  });

  it("panics on overflow as Cairo does", () => {
    expect(() => add(u8, 200n, 56n)).toThrow(new CairoPanic("u8_add Overflow"));
    expect(() => sub(u16, 0n, 1n)).toThrow(new CairoPanic("u16_sub Overflow"));
    expect(() => narrow(u8, 256n)).toThrow(new CairoPanic("Option::unwrap failed."));
  });

  it("divides truncating toward zero", () => {
    expect(div(i32, -7n, 2n)).toBe(-3n);
    expect(div(i32, 7n, -2n)).toBe(-3n);
    expect(() => div(i32, 1n, 0n)).toThrow(new CairoPanic("Division by 0"));
  });

  it("reads and writes short strings", () => {
    expect(shortString("window: facing")).toBe(0x77696e646f773a20666163696e67n);
    expect(readShortString(0x77696e646f773a20666163696e67n)).toBe("window: facing");
    expect(readShortString(1n)).toBeUndefined();
  });
});
