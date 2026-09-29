/**
 * How the world's scale meets the screen's pixels (PENDING-cv-integer-scale: the owner compares
 * three modes by eye). Three numbers are involved:
 *
 * - the **world scale** `s`: CSS pixels per art pixel (the zoom);
 * - the **canvas resolution** `r`: render pixels per CSS pixel, the canvas's backing store;
 * - the **devicePixelRatio** `dpr`: the screen's pixels per CSS pixel.
 *
 * The canvas is drawn at `s × r` render pixels per art pixel, then the browser scales the whole
 * canvas by `dpr / r` to reach the screen, smoothly (the canvas is composited with bilinear
 * filtering). So an art pixel covers `s × dpr` screen pixels, and it covers a whole number of them
 * without the browser blurring it only if the canvas pixels are the screen's pixels (`r = dpr`)
 * and `s × r` is an integer. With `r = 2` on a `dpr = 3` phone (an iPhone 14), the browser
 * stretches every canvas pixel over 1.5 screen pixels: an integer counted in canvas pixels is not
 * one on the screen.
 */

export type ScaleMode = "continuous" | "snap" | "sharp";

export const SCALE_MODES: readonly ScaleMode[] = ["continuous", "snap", "sharp"];

export function readScaleMode(value: string | null): ScaleMode {
  return SCALE_MODES.find((mode) => mode === value) ?? "continuous";
}

/** The largest canvas resolution `snap` takes to match a screen (a 3× phone). */
export const SNAP_MAX_RESOLUTION = 3;

/**
 * The canvas resolution of a mode.
 *
 * - `continuous` and `sharp`: ADR-0003's rule as Resume 1 wrote it, the devicePixelRatio rounded
 *   down, capped at 2 (1 → 1, 1.5 → 1, 2 → 2, 2.625 → 2, 3 → 2).
 * - `snap`: the canvas takes the screen's own pixels when the devicePixelRatio is a whole number
 *   up to 3 (3 → 3), so that an integer of canvas pixels is an integer of screen pixels. This lifts
 *   ADR-0003's 2× cap on a 3× phone, in this mode only. On a fractional ratio (2.625) no whole
 *   canvas resolution matches the screen: the rule above applies, and the browser's resampling of
 *   the canvas is unavoidable.
 */
export function canvasResolution(mode: ScaleMode, devicePixelRatio: number): number {
  const dpr = Number.isFinite(devicePixelRatio) && devicePixelRatio > 0 ? devicePixelRatio : 1;
  if (mode === "snap" && Number.isInteger(dpr) && dpr <= SNAP_MAX_RESOLUTION) return dpr;
  return Math.min(2, Math.max(1, Math.floor(dpr)));
}

/**
 * `snap`: the world scale at which an art pixel covers a whole number `n ≥ 1` of canvas pixels
 * (screen pixels when the canvas matches the screen), `n` the nearest by ratio to what the zoom
 * asks. For the default zoom, that is the integer that fits the sight's 13 tiles closest.
 */
export function snapScale(scale: number, resolution: number): number {
  const wanted = scale * resolution;
  const low = Math.max(1, Math.floor(wanted));
  const n = wanted <= low || wanted / low <= (low + 1) / wanted ? low : low + 1;
  return n / resolution;
}

/**
 * `sharp` ("sharp bilinear"): the world is drawn nearest-neighbour at `n` canvas pixels per art
 * pixel, the next integer at or above the target `s × r`, into an offscreen texture `oversample`
 * times the viewport; that texture is drawn down to the target with linear filtering.
 */
export function sharpFactor(scale: number, resolution: number): { n: number; oversample: number } {
  const wanted = scale * resolution;
  const n = Math.max(1, Math.ceil(wanted - 1e-9));
  return { n, oversample: n / wanted };
}

export function isWhole(value: number): boolean {
  return Math.abs(value - Math.round(value)) < 1e-9;
}
