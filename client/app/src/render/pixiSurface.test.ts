import { Ticker } from "pixi.js";
import { describe, expect, it } from "vitest";
import { stopPixiTickers, surfaceResolution } from "./pixiSurface";

describe("the PixiJS surface", () => {
  it("renders at an integer resolution, capped at 2", () => {
    expect([0, 1, 1.25, 1.5, 2, 2.625, 3].map(surfaceResolution)).toEqual([1, 1, 1, 2, 2, 2, 2]);
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
