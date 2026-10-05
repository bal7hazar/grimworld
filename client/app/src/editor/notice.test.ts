import { describe, expect, it } from "vitest";
import { Notice, type NoticeTimers } from "./notice";

/** Timers on a clock moved by hand. */
class Clock implements NoticeTimers {
  time = 0;
  private next = 1;
  readonly pending = new Map<number, { at: number; run: () => void }>();
  setTimeout(run: () => void, ms: number): number {
    const id = this.next++;
    this.pending.set(id, { at: this.time + ms, run });
    return id;
  }
  clearTimeout(timer: number): void {
    this.pending.delete(timer);
  }
  advance(ms: number): void {
    const end = this.time + ms;
    for (;;) {
      const due = [...this.pending]
        .filter(([, t]) => t.at <= end)
        .sort((a, b) => a[1].at - b[1].at);
      if (due.length === 0) break;
      const [id, t] = due[0]!;
      this.pending.delete(id);
      this.time = t.at;
      t.run();
    }
    this.time = end;
  }
}

function setup() {
  const clock = new Clock();
  const told: number[] = [];
  const notice = new Notice(() => told.push(clock.time), 250, clock);
  return { clock, told, notice };
}

describe("the camera's notice (CLI-09g, review t-0140)", () => {
  it("leading: the first move is told at once", () => {
    const { told, notice } = setup();
    notice.moved();
    expect(told).toEqual([0]);
    expect(notice.pending()).toBe(true);
  });

  it("trailing: moves within the time are told once, when it has passed; then it rests", () => {
    const { clock, told, notice } = setup();
    notice.moved();
    for (let t = 0; t < 10; t++) {
      clock.advance(20);
      notice.moved();
    }
    expect(told).toEqual([0]);
    clock.advance(100);
    expect(told).toEqual([0, 250]);
    // The trailing notice opens a new period: nothing moved in it, nothing more told.
    clock.advance(1000);
    expect(told).toEqual([0, 250]);
    expect(notice.pending()).toBe(false);
    // A move after the rest is told at once again.
    notice.moved();
    expect(told).toEqual([0, 250, 1300]);
  });

  it("no trailing notice without a move after the leading one", () => {
    const { clock, told, notice } = setup();
    notice.moved();
    clock.advance(1000);
    expect(told).toEqual([0]);
  });

  it("destroy clears the pending timer: no trailing notice, no later one", () => {
    const { clock, told, notice } = setup();
    notice.moved();
    notice.moved();
    notice.destroy();
    expect(clock.pending.size).toBe(0);
    expect(notice.pending()).toBe(false);
    clock.advance(1000);
    notice.moved();
    expect(told).toEqual([0]);
  });
});
