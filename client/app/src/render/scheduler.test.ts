import { describe, expect, it } from "vitest";
import { FrameScheduler, type FrameClient, type FrameHost } from "./scheduler";

function fakeHost() {
  let handle = 0;
  const frames = new Map<number, () => void>();
  const timers = new Map<number, () => void>();
  let time = 0;
  const host: FrameHost = {
    now: () => time,
    requestFrame: (callback) => {
      frames.set(++handle, callback);
      return handle;
    },
    cancelFrame: (h) => void frames.delete(h),
    setTimer: (callback) => {
      timers.set(++handle, callback);
      return handle;
    },
    clearTimer: (h) => void timers.delete(h),
    hidden: () => false,
    onVisibilityChange: () => () => {},
  };
  return { host, frames, timers, advance: (ms: number) => void (time += ms) };
}

function countingClient(next: number | null = null) {
  const calls = { advance: 0, draw: 0 };
  const client: FrameClient = {
    advance: () => ({ changed: false, next: (calls.advance += 1) > 0 ? next : null }),
    draw: () => void (calls.draw += 1),
  };
  return { client, calls };
}

describe("FrameScheduler after destroy", () => {
  it("requests no frame when invalidated once destroyed (late atlas promise)", () => {
    const { host, frames, timers } = fakeHost();
    const { client, calls } = countingClient();
    const scheduler = new FrameScheduler(host, client);
    scheduler.invalidate();
    expect(frames.size).toBe(1);
    const queued = [...frames.values()];
    scheduler.destroy();
    expect(frames.size).toBe(0);
    expect(() => scheduler.invalidate()).not.toThrow();
    expect(frames.size).toBe(0);
    expect(timers.size).toBe(0);
    // Even a callback the host still holds does not draw.
    for (const run of queued) run();
    expect(calls.draw).toBe(0);
  });

  it("a timer that fires after destroy requests no frame (timer path)", () => {
    const { host, frames, timers, advance } = fakeHost();
    const { client, calls } = countingClient(1000);
    const scheduler = new FrameScheduler(host, client);
    scheduler.invalidate();
    const [first] = [...frames.entries()];
    frames.delete(first![0]);
    first![1](); // draws, then sleeps on a timer for the next change
    expect(timers.size).toBe(1);
    const fire = [...timers.values()][0]!;
    const drawn = calls.draw;
    scheduler.destroy();
    advance(1000);
    fire(); // the host ran the callback anyway
    expect(frames.size).toBe(0);
    expect(timers.size).toBe(0);
    expect(calls.draw).toBe(drawn);
  });
});
