import { Ticker } from "pixi.js";
import { describe, expect, it } from "vitest";
import { gpuMaxTextureSize, stopPixiTickers } from "./pixiSurface";

describe("the PixiJS surface", () => {
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
