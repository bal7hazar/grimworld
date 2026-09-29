/**
 * Frames on demand (ADR-0003, power budget rules): no ticker. A frame is drawn when something
 * changed, and animation frames are asked for only while something animates. Between two idle
 * animation frames the scheduler sleeps on a timer, not on the display's frame callback, so a
 * 120 Hz phone is not woken 120 times a second to draw 12. Nothing runs while the page is hidden.
 *
 * The browser is behind `FrameHost`, so that tests drive the scheduler with a fake clock.
 */

export interface FrameHost {
  now(): number;
  requestFrame(callback: () => void): number;
  cancelFrame(handle: number): void;
  setTimer(callback: () => void, ms: number): number;
  clearTimer(handle: number): void;
  hidden(): boolean;
  /** Calls back on every change of visibility; returns the unsubscription. */
  onVisibilityChange(callback: () => void): () => void;
}

export interface Advance {
  /** Something visible changed: draw. */
  readonly changed: boolean;
  /** When the next change is due (host time), or null when nothing animates. */
  readonly next: number | null;
}

export interface FrameClient {
  /** Brings the scene to `now`. */
  advance(now: number): Advance;
  draw(): void;
}

export interface FrameStats {
  /** Frames drawn since the start. */
  readonly renders: number;
  /** Frames drawn since the last input. */
  readonly sinceInput: number;
}

/** A change due sooner than this is taken on the next display frame, without a timer. */
const FRAME_SLACK_MS = 8;

export class FrameScheduler {
  private frame: number | null = null;
  private timer: number | null = null;
  private timerAt = 0;
  private dirty = false;
  private renders = 0;
  private sinceInput = 0;
  private readonly unsubscribe: () => void;

  constructor(
    private readonly host: FrameHost,
    private readonly client: FrameClient,
    private readonly onDraw: (stats: FrameStats) => void = () => {},
  ) {
    this.unsubscribe = host.onVisibilityChange(() => this.visibilityChanged());
  }

  /** Something changed that must be drawn (view, camera, size). */
  invalidate(): void {
    this.dirty = true;
    this.wakeAt(this.host.now());
  }

  /** An input arrived: the "frames since the last input" counter restarts. */
  input(): void {
    this.sinceInput = 0;
    this.onDraw(this.stats());
  }

  /** Re-reads the client's animation state (an animation was turned on or off). */
  poke(): void {
    this.wakeAt(this.host.now());
  }

  stats(): FrameStats {
    return { renders: this.renders, sinceInput: this.sinceInput };
  }

  /** True when neither a frame nor a timer is pending. */
  idle(): boolean {
    return this.frame === null && this.timer === null;
  }

  destroy(): void {
    this.cancel();
    this.unsubscribe();
  }

  private cancel(): void {
    if (this.frame !== null) this.host.cancelFrame(this.frame);
    if (this.timer !== null) this.host.clearTimer(this.timer);
    this.frame = null;
    this.timer = null;
  }

  private visibilityChanged(): void {
    if (this.host.hidden()) this.cancel();
    else this.invalidate();
  }

  private wakeAt(time: number): void {
    if (this.host.hidden()) return;
    const delay = time - this.host.now();
    if (delay <= FRAME_SLACK_MS) {
      if (this.timer !== null) this.host.clearTimer(this.timer);
      this.timer = null;
      if (this.frame === null) this.frame = this.host.requestFrame(() => this.onFrame());
      return;
    }
    if (this.frame !== null) return;
    if (this.timer !== null) {
      if (this.timerAt <= time) return;
      this.host.clearTimer(this.timer);
    }
    this.timerAt = time;
    this.timer = this.host.setTimer(() => {
      this.timer = null;
      this.wakeAt(this.host.now());
    }, delay);
  }

  private onFrame(): void {
    this.frame = null;
    if (this.host.hidden()) return;
    const now = this.host.now();
    const { changed, next } = this.client.advance(now);
    if (changed || this.dirty) {
      this.dirty = false;
      this.client.draw();
      this.renders += 1;
      this.sinceInput += 1;
      this.onDraw(this.stats());
    }
    if (next !== null) this.wakeAt(next);
  }
}

/** The browser's host: `requestAnimationFrame`, `setTimeout`, the Page Visibility API. */
export function browserHost(): FrameHost {
  return {
    now: () => performance.now(),
    requestFrame: (callback) => requestAnimationFrame(() => callback()),
    cancelFrame: (handle) => cancelAnimationFrame(handle),
    setTimer: (callback, ms) => window.setTimeout(callback, ms),
    clearTimer: (handle) => window.clearTimeout(handle),
    hidden: () => document.visibilityState === "hidden",
    onVisibilityChange: (callback) => {
      document.addEventListener("visibilitychange", callback);
      return () => document.removeEventListener("visibilitychange", callback);
    },
  };
}
