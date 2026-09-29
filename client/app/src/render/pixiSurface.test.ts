import { Ticker } from "pixi.js";
import { describe, expect, it } from "vitest";
import { gpuMaxTextureSize, stopPixiTickers, surfaceResolution } from "./pixiSurface";

describe("the PixiJS surface", () => {
  it("renders at an integer resolution, rounded down, capped at 2", () => {
    expect([0, 1, 1.25, 1.5, 1.99, 2, 2.625, 3, NaN].map(surfaceResolution)).toEqual([
      1, 1, 1, 1, 1, 2, 2, 2, 1,
    ]);
  });

  it("reads the GPU's texture limit from the renderer", () => {
    const gl = { MAX_TEXTURE_SIZE: 0x0d33, getParameter: () => 16384 };
    expect(gpuMaxTextureSize({ gl })).toBe(16384);
    const gpu = { device: { limits: { maxTextureDimension2D: 8192 } } };
    expect(gpuMaxTextureSize({ gpu })).toBe(8192);
    expect(gpuMaxTextureSize({})).toBe(2048);
  });

  it("keeps PixiJS's own tickers from starting when a system joins them", () => {
    stopPixiTickers();
    const listener = () => {};
    // In Node there is no requestAnimationFrame: a ticker that started would throw here.
    Ticker.system.add(listener);
    Ticker.shared.add(listener);
    expect(Ticker.system.started).toBe(false);
    expect(Ticker.shared.started).toBe(false);
    Ticker.system.remove(listener);
    Ticker.shared.remove(listener);
  });
});
