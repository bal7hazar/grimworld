import {
  DEFAULT_FEET,
  DEFAULT_ZOOM,
  FEET_RANGE,
  STEP_MS,
  type ZoomSettings,
} from "../render/renderer";
import { type ScaleMode, readScaleMode } from "../render/scaling";

/** The bounds of the default zoom, in tiles across: the debug panel's and the URL's. */
export const ACROSS_RANGE = { min: 3, max: 31 } as const;

/** The bounds of a walk's step duration, in ms. */
export const STEP_RANGE = { min: 60, max: 1000 } as const;

/** A finite number within bounds, or null (empty, not a number, out of bounds). */
function readBounded(
  value: string | number | null,
  range: { readonly min: number; readonly max: number },
): number | null {
  if (value === null || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n < range.min || n > range.max) return null;
  return n;
}

/** A number of tiles across, or null when it is not a finite number within the bounds. */
export function readAcross(value: string | number | null): number | null {
  return readBounded(value, ACROSS_RANGE);
}

/** The feet's fraction of the inner radius below the centre (0 to 1), or null. */
export function readFeet(value: string | number | null): number | null {
  return readBounded(value, FEET_RANGE);
}

export interface SandboxParams {
  readonly fixture: string | null;
  readonly idle: boolean;
  readonly panel: boolean;
  readonly scale: ScaleMode;
  readonly zoom: ZoomSettings;
  readonly feet: number;
  readonly playOnTap: boolean;
  readonly stepMs: number;
}

/**
 * The sandbox's URL parameters: `fixture`, `idle=0` (idle animations off), `panel=1` (panel open),
 * `scale=continuous|snap|sharp` (how the scale meets the screen's pixels, `render/scaling.ts`;
 * anything else is `continuous`), `zoom=<tiles across>` (the default zoom, 3 to 31; anything else
 * is ignored), `feet=<0 to 1>` (the feet below the tile's centre, a fraction of the inner radius),
 * `confirm=1` (tap twice to walk: design/11's setting; move is played on the tap by default),
 * `step=<ms>` (a step's duration, 60 to 1000).
 */
export function readParams(search: string): SandboxParams {
  const params = new URLSearchParams(search);
  const across = readAcross(params.get("zoom"));
  return {
    fixture: params.get("fixture"),
    idle: params.get("idle") !== "0",
    panel: params.get("panel") === "1",
    scale: readScaleMode(params.get("scale")),
    zoom: across === null ? DEFAULT_ZOOM : { ...DEFAULT_ZOOM, defaultAcross: across },
    feet: readFeet(params.get("feet")) ?? DEFAULT_FEET,
    playOnTap: params.get("confirm") !== "1",
    stepMs: readBounded(params.get("step"), STEP_RANGE) ?? STEP_MS,
  };
}
