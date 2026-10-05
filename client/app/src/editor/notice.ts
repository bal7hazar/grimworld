/**
 * The camera's notice to the editor (CLI-09g, `CAMERA_NOTICE_MS`), apart from the canvas so that a
 * test drives it with a fake clock: the first move is told at once (leading), the moves within the
 * next `ms` are told once when it has passed (trailing), and `destroy` clears the pending timer.
 */
export interface NoticeTimers {
  setTimeout(run: () => void, ms: number): number;
  clearTimeout(timer: number): void;
}

export class Notice {
  private timer: number | null = null;
  private movedSince = false;
  private destroyed = false;

  constructor(
    private readonly tell: () => void,
    private readonly ms: number,
    private readonly timers: NoticeTimers,
  ) {}

  /** The camera moved: told now, or when the pending notice's time has passed. */
  moved(): void {
    if (this.destroyed) return;
    if (this.timer !== null) {
      this.movedSince = true;
      return;
    }
    this.tell();
    this.timer = this.timers.setTimeout(() => {
      this.timer = null;
      if (this.destroyed || !this.movedSince) return;
      this.movedSince = false;
      this.moved();
    }, this.ms);
  }

  /** Whether a notice's timer is pending: for tests. */
  pending(): boolean {
    return this.timer !== null;
  }

  destroy(): void {
    this.destroyed = true;
    if (this.timer !== null) this.timers.clearTimeout(this.timer);
    this.timer = null;
  }
}
