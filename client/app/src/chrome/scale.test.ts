import { describe, expect, it } from "vitest";
import type { UiSlices } from "../render/sprites";
import {
  CHROME_SCALE,
  cutScale,
  fillWidth,
  portraitCut,
  sliceLengths,
  toCssPx,
  toDevicePx,
} from "./scale";

const BUTTON: UiSlices = {
  kind: "nine",
  fill: "stretch",
  slice: [34, 20, 20, 18],
  content: [16, 24, 32, 24],
  outset: [17, 14, 15, 14],
  drop: 11,
  states: ["pressed"],
};
const CELL = { w: 164, h: 160 };
const RATIOS = [1, 1.25, 1.5, 2, 2.625, 3];

describe("the chrome's scale (AC-4)", () => {
  it("is half a CSS px per art px, scaled to device px by the ratio", () => {
    expect(CHROME_SCALE).toBe(0.5);
    expect(RATIOS.map(cutScale)).toEqual([0.5, 0.625, 0.75, 1, 1.3125, 1.5]);
    expect(toDevicePx(11, 2)).toBe(11);
    expect(toDevicePx(11, 1)).toBe(6);
    expect(toCssPx(11, 3)).toBeCloseTo(17 / 3, 10);
  });

  for (const dpr of RATIOS) {
    it(`at ${dpr}×: whole device px, one image px per device px`, () => {
      const l = sliceLengths(BUTTON, CELL, dpr);
      const whole = (v: number) => Number.isInteger(Math.round(v * 1e9) / 1e9);
      // The cut image: the frame × cutScale, rounded to whole device px.
      expect(l.image).toEqual({
        w: Math.round(CELL.w * cutScale(dpr)),
        h: Math.round(CELL.h * cutScale(dpr)),
      });
      expect(l.size.w * dpr).toBeCloseTo(l.image.w, 9);
      for (let i = 0; i < 4; i++) {
        expect(Number.isInteger(l.slice[i])).toBe(true);
        // border-image-width (CSS px) × dpr = the slice in image px: 1 image px = 1 device px.
        expect(l.width[i]! * dpr).toBeCloseTo(l.slice[i]!, 9);
        expect(whole(l.content[i]! * dpr)).toBe(true);
        expect(Math.abs(l.slice[i]! - BUTTON.slice[i]! * cutScale(dpr))).toBeLessThanOrEqual(0.5);
      }
      expect(whole(l.drop * dpr)).toBe(true);
      expect(Math.abs(l.drop - 11 * CHROME_SCALE)).toBeLessThanOrEqual(0.5 / dpr + 1e-9);
    });
  }

  it("keeps a still at its frame's size and a drop of 0 without a pressed state", () => {
    const still: UiSlices = {
      kind: "still",
      fill: "stretch",
      slice: [0, 0, 0, 0],
      content: [0, 0, 0, 0],
      outset: [0, 0, 0, 0],
    };
    const l = sliceLengths(still, { w: 55, h: 52 }, 2);
    expect(l.image).toEqual({ w: 55, h: 52 });
    expect(l.size).toEqual({ w: 27.5, h: 26 });
    expect(l.drop).toBe(0);
  });
});

describe("a bar's fill (CLI-03l AC-4)", () => {
  for (const dpr of [1, 1.5, 2, 3]) {
    it(`at ${dpr}×: whole device px, nothing at 0, the trough exactly at max`, () => {
      const track = Math.round(150 * dpr);
      const max = 160;
      const cases: [number, number][] = [
        [0, 0],
        [1, Math.round(track / max)],
        [80, Math.round(track / 2)],
        [159, Math.round((track * 159) / max)],
        [160, track],
        [400, track],
        [-5, 0],
      ];
      for (const [current, want] of cases) {
        const got = fillWidth(track, current, max);
        expect(got, `${current} / ${max}`).toBe(want);
        expect(Number.isInteger(got)).toBe(true);
        expect(got).toBeGreaterThanOrEqual(0);
        expect(got).toBeLessThanOrEqual(track);
      }
    });
  }

  it("draws nothing for a bar of no maximum or no trough", () => {
    expect(fillWidth(200, 5, 0)).toBe(0);
    expect(fillWidth(200, 0, 0)).toBe(0);
    expect(fillWidth(0, 20, 20)).toBe(0);
    expect(fillWidth(200, Number.NaN, 20)).toBe(0);
  });
});

describe("a portrait's cut (CLI-03l AC-3)", () => {
  const ART = { w: 197, h: 182 };
  for (const dpr of [1, 1.5, 2, 3]) {
    for (const size of [40, 48, 96]) {
      it(`${size} CSS px at ${dpr}×: the longer side at whole device px, smoothed below 1:1`, () => {
        const { devicePx, smooth } = portraitCut(ART, size, dpr);
        expect(devicePx.w).toBe(Math.round(size * dpr));
        expect(devicePx.h).toBe(Math.round((ART.h * Math.round(size * dpr)) / ART.w));
        expect(smooth).toBe(Math.round(size * dpr) < ART.w);
      });
    }
  }

  it("is nearest-neighbour at or above one device px per art px", () => {
    expect(portraitCut({ w: 40, h: 50 }, 48, 1)).toEqual({
      devicePx: { w: 38, h: 48 },
      smooth: true,
    });
    expect(portraitCut({ w: 40, h: 48 }, 48, 1)).toEqual({
      devicePx: { w: 40, h: 48 },
      smooth: false,
    });
    expect(portraitCut({ w: 40, h: 48 }, 96, 3).smooth).toBe(false);
  });
});
