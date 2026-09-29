import type { FrameHost } from "../render/scheduler";

/**
 * A fake browser for the scheduler: a clock moved by hand, a display that refreshes every
 * `period` ms, timers, and a visibility switch. It counts every wake-up it hands out.
 */
export class FakeHost implements FrameHost {
  time = 0;
  /** Display frame callbacks run (whether or not they drew). */
  frames = 0;
  /** Timer callbacks run. */
  timersRun = 0;
  private isHidden = false;
  private nextHandle = 1;
  private readonly frameCallbacks = new Map<number, () => void>();
  private readonly timers = new Map<number, { at: number; callback: () => void }>();
  private readonly visibility = new Set<() => void>();

  constructor(private readonly period = 1000 / 120) {}

  now(): number {
    return this.time;
  }

  requestFrame(callback: () => void): number {
    const handle = this.nextHandle++;
    this.frameCallbacks.set(handle, callback);
    return handle;
  }

  cancelFrame(handle: number): void {
    this.frameCallbacks.delete(handle);
  }

  setTimer(callback: () => void, ms: number): number {
    const handle = this.nextHandle++;
    this.timers.set(handle, { at: this.time + ms, callback });
    return handle;
  }

  clearTimer(handle: number): void {
    this.timers.delete(handle);
  }

  hidden(): boolean {
    return this.isHidden;
  }

  onVisibilityChange(callback: () => void): () => void {
    this.visibility.add(callback);
    return () => this.visibility.delete(callback);
  }

  setHidden(hidden: boolean): void {
    this.isHidden = hidden;
    for (const callback of this.visibility) callback();
  }

  /** Nothing is pending: no frame asked for, no timer set. */
  quiet(): boolean {
    return this.frameCallbacks.size === 0 && this.timers.size === 0;
  }

  /** Runs frames and timers in time order until `ms` have passed. */
  run(ms: number): void {
    const end = this.time + ms;
    for (;;) {
      const vsync =
        this.frameCallbacks.size > 0
          ? (Math.floor(this.time / this.period + 1e-9) + 1) * this.period
          : Infinity;
      let timer: [number, { at: number; callback: () => void }] | null = null;
      for (const entry of this.timers) if (!timer || entry[1].at < timer[1].at) timer = entry;
      const at = Math.min(vsync, timer ? timer[1].at : Infinity);
      if (at > end) break;
      this.time = at;
      if (timer && timer[1].at <= vsync) {
        this.timers.delete(timer[0]);
        this.timersRun += 1;
        timer[1].callback();
      } else {
        const callbacks = [...this.frameCallbacks.values()];
        this.frameCallbacks.clear();
        this.frames += 1;
        for (const callback of callbacks) callback();
      }
    }
    this.time = end;
  }
}
