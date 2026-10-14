import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { usePress } from "./SkillBar";

/** `usePress`'s event orders on a touch screen and with a mouse (review t-0263 of #482, note 2). */
describe("usePress", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.stubGlobal("window", globalThis);
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  const press = () => {
    const calls = { tap: 0, inspect: 0 };
    let handlers!: ReturnType<typeof usePress>;
    const Probe = () => {
      handlers = usePress(
        () => void calls.tap++,
        () => void calls.inspect++,
      );
      return null;
    };
    renderToStaticMarkup(<Probe />);
    const contextmenu = () =>
      handlers.onContextMenu({ preventDefault() {} } as unknown as Parameters<
        typeof handlers.onContextMenu
      >[0]);
    return { calls, h: handlers, contextmenu };
  };

  it("inspects once when contextmenu comes before the timer", () => {
    const { calls, h, contextmenu } = press();
    h.onPointerDown({ pointerType: "touch" });
    vi.advanceTimersByTime(400);
    contextmenu();
    vi.advanceTimersByTime(1000);
    h.onPointerUp();
    h.onClick();
    expect(calls).toEqual({ tap: 0, inspect: 1 });
  });

  it("inspects once when the timer comes before contextmenu", () => {
    const { calls, h, contextmenu } = press();
    h.onPointerDown({ pointerType: "touch" });
    vi.advanceTimersByTime(500);
    contextmenu();
    h.onPointerUp();
    h.onClick();
    expect(calls).toEqual({ tap: 0, inspect: 1 });
  });

  it("taps once on a short tap, with no inspect", () => {
    const { calls, h } = press();
    h.onPointerDown({ pointerType: "touch" });
    vi.advanceTimersByTime(100);
    h.onPointerUp();
    vi.advanceTimersByTime(1000);
    h.onClick();
    expect(calls).toEqual({ tap: 1, inspect: 0 });
  });

  it("drops the press when the pointer leaves or is cancelled", () => {
    for (const end of ["onPointerLeave", "onPointerCancel"] as const) {
      const { calls, h } = press();
      h.onPointerDown({ pointerType: "touch" });
      vi.advanceTimersByTime(300);
      h[end]();
      vi.advanceTimersByTime(1000);
      expect(calls, end).toEqual({ tap: 0, inspect: 0 });
    }
  });

  it("inspects on every right click and still taps after one", () => {
    const { calls, h, contextmenu } = press();
    h.onPointerDown({ pointerType: "mouse" });
    contextmenu();
    h.onPointerUp();
    contextmenu();
    h.onClick();
    expect(calls).toEqual({ tap: 1, inspect: 2 });
  });
});
