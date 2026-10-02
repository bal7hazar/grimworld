import { describe, expect, it, vi } from "vitest";
import type { ShellBridge } from "./deviceState";
import { logShellStart } from "./startLog";

describe("logShellStart", () => {
  it("logs nothing in a browser", async () => {
    const log = vi.fn();
    expect(await logShellStart(log)).toBeNull();
    expect(log).not.toHaveBeenCalled();
  });

  it("logs the state at start and each thermal change in the shell", async () => {
    let emit: (event: { thermal?: unknown }) => void = () => {};
    const bridge: ShellBridge = {
      native: () => true,
      plugin: {
        read: async () => ({
          thermal: "nominal",
          battery: -1,
          charging: "unknown",
          lowPower: false,
        }),
        addListener: async (_event, handler) => {
          emit = handler;
          return { remove: async () => {} };
        },
      },
    };
    const log = vi.fn();
    const unsubscribe = await logShellStart(log, bridge);
    await Promise.resolve();
    emit({ thermal: "serious" });
    expect(log.mock.calls.map(([line]) => line)).toEqual([
      `[shell] start ${JSON.stringify({
        href: globalThis.location?.href ?? null,
        state: { thermal: "nominal", battery: null, charging: "unknown", lowPower: false },
      })}`,
      "[shell] thermalChange serious",
    ]);
    expect(unsubscribe).toBeTypeOf("function");
  });
});
