import { describe, expect, it } from "vitest";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { Renderer, type ZoomInfo } from "./renderer";
import {
  type ScaleMode,
  canvasResolution,
  isWhole,
  readScaleMode,
  sharpFactor,
  snapScale,
} from "./scaling";

describe("canvas resolution", () => {
  it("continuous and sharp: devicePixelRatio rounded down, capped at 2", () => {
    for (const mode of ["continuous", "sharp"] as const) {
      expect(
        [0, 1, 1.25, 1.5, 1.99, 2, 2.625, 3, 4, NaN].map((d) => canvasResolution(mode, d)),
      ).toEqual([1, 1, 1, 1, 1, 2, 2, 2, 2, 1]);
    }
  });

  it("snap: the screen's own pixels when the ratio is whole, up to 3", () => {
    expect([1, 1.5, 2, 2.625, 3, 4].map((d) => canvasResolution("snap", d))).toEqual([
      1, 1, 2, 2, 3, 2,
    ]);
  });

  it("reads the mode, continuous by default", () => {
    expect(readScaleMode("sharp")).toBe("sharp");
    expect(readScaleMode("snap")).toBe("snap");
    for (const value of [null, "", "SNAP", "1"]) expect(readScaleMode(value)).toBe("continuous");
  });
});

describe("snap and sharp", () => {
  it("snap: the whole number of canvas pixels nearest by ratio, at least 1", () => {
    expect(snapScale(0.4507, 2)).toBe(0.5); // 0.90 → 1
    expect(snapScale(0.4507, 3)).toBeCloseTo(1 / 3, 12); // 1.35 → 1
    expect(snapScale(0.2, 2)).toBe(0.5); // 0.4 → 1, never a fraction
    expect(snapScale(1.2179, 2)).toBe(1); // 2.44 → 2
    expect(snapScale(1.3, 2)).toBe(1.5); // 2.6 → 3
  });

  it("sharp: the next integer at or above, and the oversampling", () => {
    expect(sharpFactor(0.4507, 2)).toEqual({ n: 1, oversample: 1 / 0.9014 });
    expect(sharpFactor(1.2179, 2).n).toBe(3);
    expect(sharpFactor(1, 2)).toEqual({ n: 2, oversample: 1 });
  });
});

/** The figures of the report: the default zoom (13 across) on three screens, in each mode. */
function figures(mode: ScaleMode, width: number, height: number, dpr: number): ZoomInfo {
  const surface = new FakeSurface(canvasResolution(mode, dpr), dpr);
  const renderer = new Renderer(surface, new FakeHost(), { idle: false, mode });
  renderer.resize({ width, height });
  return renderer.zoomInfo();
}

describe("the three modes at the default zoom (REPORT, Resume 2)", () => {
  const round = (info: ZoomInfo) => ({
    resolution: info.resolution,
    deviceScale: Number(info.deviceScale.toFixed(2)),
    integer: info.integer,
    tileWidth: Number(info.tileWidth.toFixed(2)),
    across: Number(info.across.toFixed(2)),
    offscreen: info.offscreen,
  });

  it("375 × 812 at DPR 2", () => {
    expect(round(figures("continuous", 375, 812, 2))).toEqual({
      resolution: 2,
      deviceScale: 0.9,
      integer: false,
      tileWidth: 28.85,
      across: 13,
      offscreen: null,
    });
    expect(round(figures("snap", 375, 812, 2))).toEqual({
      resolution: 2,
      deviceScale: 1,
      integer: true,
      tileWidth: 32,
      across: 11.72,
      offscreen: null,
    });
    expect(round(figures("sharp", 375, 812, 2))).toEqual({
      resolution: 2,
      deviceScale: 0.9,
      integer: false,
      tileWidth: 28.85,
      across: 13,
      offscreen: { n: 1, width: 832, height: 1802 },
    });
  });

  it("375 × 812 at DPR 3 (an iPhone 14)", () => {
    expect(round(figures("continuous", 375, 812, 3))).toMatchObject({
      resolution: 2,
      deviceScale: 1.35,
      integer: false,
      tileWidth: 28.85,
      across: 13,
    });
    expect(round(figures("snap", 375, 812, 3))).toMatchObject({
      resolution: 3,
      deviceScale: 1,
      integer: true,
      tileWidth: 21.33,
      across: 17.58,
    });
    expect(round(figures("sharp", 375, 812, 3))).toEqual({
      resolution: 2,
      deviceScale: 1.35,
      integer: false,
      tileWidth: 28.85,
      across: 13,
      offscreen: { n: 1, width: 832, height: 1802 },
    });
  });

  it("1440 × 900 desktop at DPR 2 (the sight fits the height)", () => {
    expect(round(figures("continuous", 1440, 900, 2))).toMatchObject({
      deviceScale: 2.44,
      integer: false,
      tileWidth: 77.94,
      across: 18.48,
    });
    expect(round(figures("snap", 1440, 900, 2))).toMatchObject({
      deviceScale: 2,
      integer: true,
      tileWidth: 64,
      across: 22.5,
    });
    expect(round(figures("sharp", 1440, 900, 2))).toEqual({
      resolution: 2,
      deviceScale: 2.44,
      integer: false,
      tileWidth: 77.94,
      across: 18.48,
      offscreen: { n: 3, width: 3548, height: 2218 },
    });
  });

  it("isWhole", () => {
    expect([1, 2.0000000001, 1.5, 0.5].map(isWhole)).toEqual([true, true, false, false]);
  });
});
