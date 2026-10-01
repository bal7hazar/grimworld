import {
  DEFAULT_FEET,
  DEFAULT_ZOOM,
  FEET_RANGE,
  STEP_MS,
  type ZoomSettings,
} from "../render/renderer";
import { type ScaleMode, readScaleMode } from "../render/scaling";
import { HUB_NAMES } from "./fixtures/hubs";

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

/** The bounds of the entry moment's fixed wait, in ms (0: it completes at once). */
export const ENTRY_RANGE = { min: 0, max: 10_000 } as const;

/** The entry moment's fixed wait on fixed data, in ms: long enough to be seen, skippable. */
export const ENTRY_MS = 1200;

export interface SandboxParams {
  readonly fixture: string | null;
  /**
   * The hub the loop opens on (CLI-03c), a location id: `hub=town` or `hub=outpost`, `loop=1` for
   * the town; null (a room, `fixture`) otherwise.
   */
  readonly hub: number | null;
  /** The entry moment's fixed wait, in ms. */
  readonly entryMs: number;
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
 * `step=<ms>` (a step's duration, 60 to 1000). The loop (CLI-03c): `hub=town|outpost` opens it on
 * that hub, `loop=1` on the town; `entry=<ms>` the entry moment's wait (0 to 10000). An unknown
 * hub opens the room sandbox.
 */
export function readParams(search: string): SandboxParams {
  const params = new URLSearchParams(search);
  const across = readAcross(params.get("zoom"));
  const hubName = params.get("hub") ?? (params.get("loop") === "1" ? "town" : null);
  return {
    fixture: params.get("fixture"),
    hub:
      hubName !== null && Object.hasOwn(HUB_NAMES, hubName) ? (HUB_NAMES[hubName] ?? null) : null,
    entryMs: readBounded(params.get("entry"), ENTRY_RANGE) ?? ENTRY_MS,
    idle: params.get("idle") !== "0",
    panel: params.get("panel") === "1",
    scale: readScaleMode(params.get("scale")),
    zoom: across === null ? DEFAULT_ZOOM : { ...DEFAULT_ZOOM, defaultAcross: across },
    feet: readFeet(params.get("feet")) ?? DEFAULT_FEET,
    playOnTap: params.get("confirm") !== "1",
    stepMs: readBounded(params.get("step"), STEP_RANGE) ?? STEP_MS,
  };
}
