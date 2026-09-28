/** Placeholder of the simulation core: keeps `value` within [min, max]. No game rule lives here yet. */
export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}
