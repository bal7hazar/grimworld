import type { PluginListenerHandle } from "@capacitor/core";
import { describe, expect, it, vi } from "vitest";
import {
  type DeviceStatePlugin,
  type ShellBridge,
  onThermalChange,
  readDeviceState,
  toDeviceState,
} from "./deviceState";

function mockBridge(native: boolean, answer: Record<string, unknown> = {}) {
  const handlers: ((event: { thermal?: unknown }) => void)[] = [];
  const remove = vi.fn(async () => {});
  const plugin: DeviceStatePlugin = {
    read: vi.fn(async () => answer),
    addListener: vi.fn(async (_event, handler) => {
      handlers.push(handler);
      return { remove } satisfies PluginListenerHandle;
    }),
  };
  const bridge: ShellBridge = { native: () => native, plugin };
  return { bridge, plugin, handlers, remove };
}

describe("readDeviceState", () => {
  it("is null in a browser, without calling the plugin", async () => {
    const { bridge, plugin } = mockBridge(false);
    expect(await readDeviceState(bridge)).toBeNull();
    // The default bridge: vitest runs outside the native shell.
    expect(await readDeviceState()).toBeNull();
    expect(plugin.read).not.toHaveBeenCalled();
  });

  it("maps the plugin's answer in the shell", async () => {
    const answer = { thermal: "fair", battery: 0.85, charging: "charging", lowPower: false };
    const { bridge } = mockBridge(true, answer);
    expect(await readDeviceState(bridge)).toEqual(answer);
  });
});

describe("toDeviceState", () => {
  it("accepts the four thermal states and the four charging states", () => {
    for (const thermal of ["nominal", "fair", "serious", "critical"]) {
      for (const charging of ["unplugged", "charging", "full", "unknown"]) {
        const raw = { thermal, battery: 0.5, charging, lowPower: true };
        expect(toDeviceState(raw)).toEqual(raw);
      }
    }
  });

  it("gives null for an unknown battery level (UIDevice's -1)", () => {
    for (const battery of [-1, 1.5, Number.NaN, null, undefined, "0.5"]) {
      const raw = { thermal: "nominal", battery, charging: "unknown", lowPower: false };
      expect(toDeviceState(raw)?.battery, String(battery)).toBeNull();
    }
    const edges = [0, 1].map(
      (battery) =>
        toDeviceState({ thermal: "nominal", battery, charging: "full", lowPower: false })?.battery,
    );
    expect(edges).toEqual([0, 1]);
  });

  it("reads an unknown charging state as unknown", () => {
    const raw = { thermal: "nominal", battery: 1, charging: "solar", lowPower: false };
    expect(toDeviceState(raw)?.charging).toBe("unknown");
  });

  it("refuses an answer that is not a device state", () => {
    expect(toDeviceState({})).toBeNull();
    expect(toDeviceState({ thermal: "hot", lowPower: false })).toBeNull();
    expect(toDeviceState({ thermal: "nominal", lowPower: "no" })).toBeNull();
  });
});

describe("onThermalChange", () => {
  it("does nothing in a browser", () => {
    const { bridge, plugin } = mockBridge(false);
    const unsubscribe = onThermalChange(() => {}, bridge);
    expect(plugin.addListener).not.toHaveBeenCalled();
    expect(() => unsubscribe()).not.toThrow();
  });

  it("forwards the plugin's thermalChange events until unsubscribed", async () => {
    const { bridge, plugin, handlers, remove } = mockBridge(true);
    const seen: string[] = [];
    const unsubscribe = onThermalChange((thermal) => seen.push(thermal), bridge);
    expect(plugin.addListener).toHaveBeenCalledWith("thermalChange", expect.any(Function));
    await Promise.resolve();
    const emit = handlers[0]!;
    emit({ thermal: "serious" });
    emit({ thermal: "bogus" });
    emit({ thermal: "critical" });
    unsubscribe();
    unsubscribe();
    emit({ thermal: "nominal" });
    await vi.waitFor(() => expect(remove).toHaveBeenCalledTimes(1));
    expect(seen).toEqual(["serious", "critical"]);
  });
});
