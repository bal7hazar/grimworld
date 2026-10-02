import { type ShellBridge, onThermalChange, readDeviceState } from "./deviceState";

/**
 * One console line at start in the shell (`[shell] start {…}`), and one per `thermalChange`:
 * Capacitor forwards them to the system log, where the simulator's run is checked (CV-03, AC-5,
 * AC-6). Nothing in a browser. Until the run log of SPK-6's protocol §9 point 3 wires the device
 * state itself.
 */
export async function logShellStart(
  log: (line: string) => void = console.log,
  bridge?: ShellBridge,
): Promise<(() => void) | null> {
  const state = await readDeviceState(bridge);
  if (state === null) return null;
  log(`[shell] start ${JSON.stringify({ href: globalThis.location?.href ?? null, state })}`);
  return onThermalChange((thermal) => log(`[shell] thermalChange ${thermal}`), bridge);
}
