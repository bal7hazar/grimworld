import { describe, expect, it } from "vitest";
import { EXP2_HIGH, EXP2_LOW, EXP2_X40, exp2 } from "./exp2";

// The exact value, from integers only: the v with (2v - 1)^40 <= 2^(680 + x) < (2v + 1)^40, that
// is round(2^16 * 2^(x/40)). Independent of the generator's own search.
function exact(x: number): bigint {
  const target = 2n ** BigInt(680 + x);
  // The largest v with (2v - 1)^40 <= target, by bisection (the power is monotonic in v).
  let lo = 0n;
  let hi = 1n << 20n;
  while (lo < hi) {
    const mid = (lo + hi + 1n) / 2n;
    if ((2n * mid - 1n) ** 40n <= target) lo = mid;
    else hi = mid - 1n;
  }
  return lo;
}

describe("exp2", () => {
  it("has one entry per x in [-160, +80]", () => {
    expect(EXP2_X40.length).toBe(EXP2_HIGH - EXP2_LOW + 1);
    expect(EXP2_X40.length).toBe(241);
  });

  it("is exact at the octaves", () => {
    expect(exp2(-160)).toBe(4096n);
    expect(exp2(-40)).toBe(32768n);
    expect(exp2(0)).toBe(65536n);
    expect(exp2(40)).toBe(131072n);
    expect(exp2(80)).toBe(262144n);
  });

  it("reads a few known entries", () => {
    expect(exp2(-159)).toBe(4168n);
    expect(exp2(1)).toBe(66682n);
    expect(exp2(-37)).toBe(34517n);
  });

  it("clamps below and above the table", () => {
    expect(exp2(-161)).toBe(exp2(-160));
    expect(exp2(-65535)).toBe(4096n);
    expect(exp2(81)).toBe(exp2(80));
    expect(exp2(65535)).toBe(262144n);
  });

  it("throws on a non-integer x instead of returning undefined", () => {
    expect(() => exp2(0.5)).toThrow(RangeError);
    expect(() => exp2(-159.5)).toThrow(RangeError);
    expect(() => exp2(NaN)).toThrow(RangeError);
    expect(() => exp2(Infinity)).toThrow(RangeError);
  });

  it("returns round(2^16 * 2^(x/40)) for every x in [-200, +120], the clamp included", () => {
    for (let x = -200; x <= 120; x++) {
      const inside = Math.min(Math.max(x, EXP2_LOW), EXP2_HIGH);
      expect(exp2(x), `x = ${x}`).toBe(exact(inside));
    }
  });
});
