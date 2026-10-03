import type { Point } from "./coords";

/**
 * Pointer events to gestures (ADR-0003: touch is the reference, the mouse maps to it; ADR-0006 §5:
 * pinch and drag on a phone, wheel and drag on a desktop; design/11: long press, or right click,
 * inspects). Screen pixels in, gestures out; what a gesture means is decided elsewhere.
 */
export type Gesture =
  | { readonly kind: "tap"; readonly point: Point }
  | { readonly kind: "press"; readonly point: Point }
  | { readonly kind: "pan"; readonly dx: number; readonly dy: number }
  | { readonly kind: "zoom"; readonly factor: number; readonly point: Point };

export interface Timers {
  set(callback: () => void, ms: number): number;
  clear(handle: number): void;
}

/** A pointer that moves less than this (CSS px) between down and up is a tap. */
export const TAP_SLOP = 10;
/** Held this long without moving: a long press. */
export const LONG_PRESS_MS = 450;
/** Wheel: the zoom factor per pixel of `deltaY`. */
const WHEEL_RATE = 0.0015;
/** One wheel notch (`deltaY` 100) toward zooming in, as a factor: the keyboard's `+` (CLI-03k). */
export const WHEEL_NOTCH = Math.exp(100 * WHEEL_RATE);

const distance = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.y - b.y);
const middle = (a: Point, b: Point) => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });

export class GestureTracker {
  private readonly pointers = new Map<number, Point>();
  private start: Point = { x: 0, y: 0 };
  private dragging = false;
  private pressed = false;
  private multi = false;
  private timer: number | null = null;

  constructor(
    private readonly emit: (gesture: Gesture) => void,
    private readonly timers: Timers,
  ) {}

  /** `button` 2 is a right click: inspect at once. */
  down(id: number, point: Point, button = 0): void {
    if (button === 2) {
      this.emit({ kind: "press", point });
      return;
    }
    this.pointers.set(id, point);
    if (this.pointers.size === 1) {
      this.start = point;
      this.dragging = false;
      this.pressed = false;
      this.multi = false;
      this.timer = this.timers.set(() => {
        this.timer = null;
        if (this.dragging || this.multi) return;
        this.pressed = true;
        this.emit({ kind: "press", point: this.start });
      }, LONG_PRESS_MS);
    } else {
      this.multi = true;
      this.cancelPress();
    }
  }

  move(id: number, point: Point): void {
    const previous = this.pointers.get(id);
    if (!previous) return;
    if (this.pointers.size === 1) {
      this.pointers.set(id, point);
      if (this.pressed) return;
      if (!this.dragging && distance(point, this.start) <= TAP_SLOP) return;
      const from = this.dragging ? previous : this.start;
      this.dragging = true;
      this.cancelPress();
      this.emit({ kind: "pan", dx: point.x - from.x, dy: point.y - from.y });
      return;
    }
    const [a, b] = [...this.pointers.values()] as [Point, Point];
    const before = { centre: middle(a, b), span: distance(a, b) };
    this.pointers.set(id, point);
    const [c, d] = [...this.pointers.values()] as [Point, Point];
    const after = { centre: middle(c, d), span: distance(c, d) };
    this.emit({
      kind: "pan",
      dx: after.centre.x - before.centre.x,
      dy: after.centre.y - before.centre.y,
    });
    if (before.span > 0 && after.span > 0) {
      this.emit({ kind: "zoom", factor: after.span / before.span, point: after.centre });
    }
  }

  up(id: number): void {
    if (!this.pointers.delete(id)) return;
    if (this.pointers.size > 0) {
      // A finger of a pinch lifted: the other drags on from where it is, not from the first down.
      const [rest] = [...this.pointers.values()];
      if (rest) this.start = rest;
      this.dragging = true;
      return;
    }
    this.cancelPress();
    if (!this.dragging && !this.pressed && !this.multi)
      this.emit({ kind: "tap", point: this.start });
  }

  /** The pointer was taken away (a system gesture): no tap. */
  cancel(id: number): void {
    if (!this.pointers.delete(id)) return;
    if (this.pointers.size === 0) {
      this.cancelPress();
      this.multi = true;
    }
  }

  wheel(deltaY: number, point: Point): void {
    this.emit({ kind: "zoom", factor: Math.exp(-deltaY * WHEEL_RATE), point });
  }

  destroy(): void {
    this.cancelPress();
    this.pointers.clear();
  }

  private cancelPress(): void {
    if (this.timer !== null) this.timers.clear(this.timer);
    this.timer = null;
  }
}
