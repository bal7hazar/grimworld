import { describe, expect, it } from "vitest";
import { CairoPanic } from "./felt";
import { MAX_BASE, level_strength, weapon_base, weapon_strength } from "./hit";

// The cases of `hit.cairo`'s own unit tests (`test_strength_weapon`, `test_strength_level`,
// `test_weapon_base`): these three helpers have no vector table.
describe("the strength and base helpers", () => {
  it("weapon_strength: 5 × rank, capped", () => {
    expect(weapon_strength(10n, 255n)).toBe(50n);
    expect(weapon_strength(10n, 40n)).toBe(40n);
    expect(weapon_strength(15n, 75n)).toBe(75n);
    expect(weapon_strength(0n, 75n)).toBe(0n);
    expect(weapon_strength(255n, 255n)).toBe(255n);
  });

  it("level_strength: 3 × level", () => {
    expect(level_strength(20n)).toBe(60n);
    expect(level_strength(255n)).toBe(765n);
  });

  it("weapon_base: the damage, / 3 below the requirement, plus the bonus", () => {
    expect(weapon_base(18n, true, 0n)).toBe(18n);
    expect(weapon_base(18n, false, 0n)).toBe(6n);
    expect(weapon_base(17n, false, 0n)).toBe(5n);
    expect(weapon_base(18n, true, 12n)).toBe(30n);
    expect(weapon_base(18n, false, 12n)).toBe(18n);
    expect(weapon_base(255n, true, 32767n)).toBe(MAX_BASE);
  });

  it("refuses an argument outside its Cairo type, which no Cairo call can pass", () => {
    expect(() => weapon_strength(256n, 255n)).toThrow(RangeError);
    expect(() => weapon_strength(10n, -1n)).toThrow(RangeError);
    expect(() => level_strength(256n)).toThrow(RangeError);
    expect(() => weapon_base(300n, true, 0n)).toThrow(RangeError);
    expect(() => weapon_base(18n, true, 65536n)).toThrow(RangeError);
    expect(() => weapon_base(18n, true, 65536n)).not.toThrow(CairoPanic);
  });
});
