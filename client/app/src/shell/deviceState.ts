import { Capacitor, type PluginListenerHandle, registerPlugin } from "@capacitor/core";

/**
 * The device state SPK-6's run log records (protocol §9 point 9, R-3, R-4, §1.2): the thermal
 * state, the battery and Low Power Mode, read natively by the iOS shell's `DeviceState` plugin
 * (`ios/App/App/DeviceStatePlugin.swift`). `null` outside the shell (a browser). No polling: a
 * timer that wakes the page would distort the idle row (R-5); read at start and stop, and on
 * `thermalChange`.
 */

export type ThermalState = "nominal" | "fair" | "serious" | "critical";

export interface DeviceState {
  readonly thermal: ThermalState;
  readonly battery: number | null; // 0–1
  readonly charging: "unplugged" | "charging" | "full" | "unknown";
  readonly lowPower: boolean;
}

/** The native plugin, as the Swift side answers (the same names). */
export interface DeviceStatePlugin {
  read(): Promise<Record<string, unknown>>;
  addListener(
    event: "thermalChange",
    handler: (event: { thermal?: unknown }) => void,
  ): Promise<PluginListenerHandle>;
}

/** What the functions below reach: the plugin, and whether the page runs in the native shell. */
export interface ShellBridge {
  readonly native: () => boolean;
  readonly plugin: DeviceStatePlugin;
}

const nativeBridge: ShellBridge = {
  native: () => Capacitor.isNativePlatform(),
  plugin: registerPlugin<DeviceStatePlugin>("DeviceState"),
};

const THERMAL: readonly ThermalState[] = ["nominal", "fair", "serious", "critical"];
const CHARGING: readonly DeviceState["charging"][] = ["unplugged", "charging", "full", "unknown"];

const thermalOf = (value: unknown): ThermalState | null =>
  THERMAL.find((state) => state === value) ?? null;

/** The plugin's answer, checked; null when it is not a device state. */
export function toDeviceState(raw: Record<string, unknown>): DeviceState | null {
  const thermal = thermalOf(raw.thermal);
  if (thermal === null || typeof raw.lowPower !== "boolean") return null;
  // UIDevice answers -1 when the level is unknown (the simulator).
  const battery =
    typeof raw.battery === "number" && raw.battery >= 0 && raw.battery <= 1 ? raw.battery : null;
  const charging = CHARGING.find((state) => state === raw.charging) ?? "unknown";
  return { thermal, battery, charging, lowPower: raw.lowPower };
}

/**
 * The device state, or null outside the native shell. Rejects when the native read fails: the
 * caller handles the rejection (`main.tsx` logs it).
 */
export async function readDeviceState(
  bridge: ShellBridge = nativeBridge,
): Promise<DeviceState | null> {
  if (!bridge.native()) return null;
  return toDeviceState(await bridge.plugin.read());
}

/** Calls `handler` on each change of the thermal state; returns the unsubscribe. */
export function onThermalChange(
  handler: (thermal: ThermalState) => void,
  bridge: ShellBridge = nativeBridge,
): () => void {
  if (!bridge.native()) return () => {};
  let removed = false;
  const handle = bridge.plugin.addListener("thermalChange", (event) => {
    const thermal = thermalOf(event.thermal);
    if (!removed && thermal !== null) handler(thermal);
  });
  return () => {
    if (removed) return;
    removed = true;
    void handle.then((h) => h.remove());
  };
}
