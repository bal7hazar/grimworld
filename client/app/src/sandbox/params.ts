import { DEFAULT_ZOOM, type ZoomSettings } from "../render/renderer";
import { type ScaleMode, readScaleMode } from "../render/scaling";

/** The bounds of the default zoom, in tiles across: the debug panel's and the URL's. */
export const ACROSS_RANGE = { min: 3, max: 31 } as const;

/** A number of tiles across, or null when it is not a finite number within the bounds. */
export function readAcross(value: string | number | null): number | null {
  if (value === null || value === "") return null;
  const across = Number(value);
  if (!Number.isFinite(across) || across < ACROSS_RANGE.min || across > ACROSS_RANGE.max) {
    return null;
  }
  return across;
}

export interface SandboxParams {
  readonly fixture: string | null;
  readonly idle: boolean;
  readonly panel: boolean;
  readonly scale: ScaleMode;
  readonly zoom: ZoomSettings;
}

/**
 * The sandbox's URL parameters: `fixture`, `idle=0` (idle animations off), `panel=1` (panel open),
 * `scale=continuous|snap|sharp` (how the scale meets the screen's pixels, `render/scaling.ts`;
 * anything else is `continuous`), `zoom=<tiles across>` (the default zoom, 3 to 31; anything else
 * is ignored).
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
  };
}
