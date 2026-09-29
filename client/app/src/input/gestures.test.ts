import { describe, expect, it } from "vitest";
import { type Gesture, GestureTracker, LONG_PRESS_MS, TAP_SLOP } from "./gestures";

function setup() {
  const gestures: Gesture[] = [];
  const pending = new Map<number, () => void>();
  let handle = 0;
  const tracker = new GestureTracker((g) => gestures.push(g), {
    set: (callback) => (pending.set(++handle, callback), handle),
    clear: (h) => pending.delete(h),
  });
  const elapse = () => {
    for (const [h, callback] of [...pending]) {
      pending.delete(h);
      callback();
    }
  };
  return { gestures, tracker, elapse, pending };
}

describe("gestures", () => {
  it("a tap within the slop is a tap at the first point", () => {
    const { gestures, tracker, pending } = setup();
    tracker.down(1, { x: 100, y: 100 });
    tracker.move(1, { x: 100 + TAP_SLOP - 1, y: 100 });
    tracker.up(1);
    expect(gestures).toEqual([{ kind: "tap", point: { x: 100, y: 100 } }]);
    expect(pending.size).toBe(0);
  });

  it(`a press held ${LONG_PRESS_MS} ms is a long press, and no tap follows`, () => {
    const { gestures, tracker, elapse } = setup();
    tracker.down(1, { x: 50, y: 60 });
    elapse();
    tracker.up(1);
    expect(gestures).toEqual([{ kind: "press", point: { x: 50, y: 60 } }]);
  });

  it("a right click inspects", () => {
    const { gestures, tracker } = setup();
    tracker.down(1, { x: 5, y: 6 }, 2);
    expect(gestures).toEqual([{ kind: "press", point: { x: 5, y: 6 } }]);
  });

  it("a drag pans and is no tap; the long press is cancelled", () => {
    const { gestures, tracker, pending } = setup();
    tracker.down(1, { x: 100, y: 100 });
    tracker.move(1, { x: 130, y: 100 });
    tracker.move(1, { x: 140, y: 90 });
    expect(pending.size).toBe(0);
    tracker.up(1);
    expect(gestures).toEqual([
      { kind: "pan", dx: 30, dy: 0 },
      { kind: "pan", dx: 10, dy: -10 },
    ]);
  });

  it("two fingers pinch: zoom by the ratio of spans, around their middle", () => {
    const { gestures, tracker } = setup();
    tracker.down(1, { x: 100, y: 100 });
    tracker.down(2, { x: 200, y: 100 });
    tracker.move(2, { x: 300, y: 100 });
    tracker.up(1);
    tracker.up(2);
    expect(gestures).toEqual([
      { kind: "pan", dx: 50, dy: 0 },
      { kind: "zoom", factor: 2, point: { x: 200, y: 100 } },
    ]);
  });

  it("the wheel zooms in on a scroll up and out on a scroll down", () => {
    const { gestures, tracker } = setup();
    tracker.wheel(-100, { x: 1, y: 2 });
    tracker.wheel(100, { x: 1, y: 2 });
    const [a, b] = gestures as [
      Extract<Gesture, { kind: "zoom" }>,
      Extract<Gesture, { kind: "zoom" }>,
    ];
    expect(a.factor).toBeGreaterThan(1);
    expect(b.factor).toBeCloseTo(1 / a.factor, 12);
  });
});
