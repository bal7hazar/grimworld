import { describe, expect, it } from "vitest";
import { FrameScheduler, type FrameClient, type FrameHost } from "./scheduler";

function fakeHost() {
  let handle = 0;
  const frames = new Map<number, () => void>();
  const host: FrameHost = {
    now: () => 0,
    requestFrame: (callback) => {
      frames.set(++handle, callback);
      return handle;
    },
    cancelFrame: (h) => void frames.delete(h),
    setTimer: () => ++handle,
    clearTimer: () => {},
    hidden: () => false,
    onVisibilityChange: () => () => {},
  };
  return { host, frames };
}

describe("FrameScheduler after destroy", () => {
  it("requests no frame when invalidated once destroyed (late atlas promise)", () => {
    const { host, frames } = fakeHost();
    let draws = 0;
    const client: FrameClient = {
      advance: () => ({ changed: false, next: null }),
      draw: () => void (draws += 1),
    };
    const scheduler = new FrameScheduler(host, client);
    scheduler.invalidate();
    expect(frames.size).toBe(1);
    scheduler.destroy();
    expect(frames.size).toBe(0);
    expect(() => scheduler.invalidate()).not.toThrow();
    expect(frames.size).toBe(0);
    expect(draws).toBe(0);
  });
});
