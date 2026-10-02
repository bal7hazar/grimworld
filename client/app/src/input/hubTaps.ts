import {
  type HubFigure,
  type HubPlace,
  type HubTarget,
  type HubView,
  feetPoint,
  hubPoint,
} from "../render/hubView";
import { type ScaleMode, snapScale } from "../render/scaling";
import type { LoopIntent } from "./intent";

/**
 * Where a hub's places are on screen, and what a tap on them means (CLI-03c). Presentation only:
 * the illustration fitted to its zone, rectangles in CSS pixels, and the intent of each target.
 * The renderer draws with the same fit, so a building's tap target covers the building drawn.
 */

export interface Size {
  readonly width: number;
  readonly height: number;
}

export interface Rect {
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;
}

/** The illustration in its zone: CSS pixels per art pixel, and where its top-left corner lands. */
export interface HubFit {
  readonly scale: number;
  readonly x: number;
  readonly y: number;
}

/** Touch targets are at least 40 points wide (design/11 I-6). */
export const MIN_TARGET = 40;

/**
 * A present adventurer's tap target's height, in art pixels: about the professions' native
 * visible heights, 67 to 88 px (`tools/art/README.md`, *Native heights*).
 */
export const FIGURE_HEIGHT = 80;

/** The scale mode and the canvas resolution the illustration is drawn with (`render/scaling.ts`). */
export interface HubScaling {
  readonly mode: ScaleMode;
  readonly resolution: number;
}

/**
 * The whole illustration, as large as fits, centred: **one** factor for the whole scene (CLI-03e).
 * `snap`, as in a room, makes an art pixel a whole number of canvas pixels: here the largest that
 * still fits (a hub is not panned), and the corner on a canvas pixel. When even one canvas pixel
 * per art pixel does not fit (a 1× screen, a phone under 352 points at 2×), the hub keeps the
 * fitted scale of `continuous`: it never overflows its zone.
 */
export function hubFit(
  view: Pick<HubView, "width" | "height">,
  zone: Size,
  scaling: HubScaling = { mode: "continuous", resolution: 1 },
): HubFit {
  let scale = Math.max(0.01, Math.min(zone.width / view.width, zone.height / view.height));
  if (scaling.mode === "snap") {
    const r = scaling.resolution;
    const n = Math.floor(scale * r + 1e-9);
    if (n >= 1) scale = snapScale(n / r, r);
    const corner = (free: number) => Math.round((free / 2) * r) / r;
    return {
      scale,
      x: corner(zone.width - view.width * scale),
      y: corner(zone.height - view.height * scale),
    };
  }
  return {
    scale,
    x: (zone.width - view.width * scale) / 2,
    y: (zone.height - view.height * scale) / 2,
  };
}

/** A rectangle at least `MIN_TARGET` on each side, grown around its centre. */
function atLeast(rect: Rect): Rect {
  const width = Math.max(MIN_TARGET, rect.width);
  const height = Math.max(MIN_TARGET, rect.height);
  return {
    left: rect.left - (width - rect.width) / 2,
    top: rect.top - (height - rect.height) / 2,
    width,
    height,
  };
}

/** The building's footprint on screen: its native size, centred on its door's hex, standing on it. */
export function placeRect(view: Pick<HubView, "origin">, place: HubPlace, fit: HubFit): Rect {
  const base = hubPoint(view, place.at);
  return atLeast({
    left: fit.x + (base.x - place.width / 2) * fit.scale,
    top: fit.y + (base.y - place.height) * fit.scale,
    width: place.width * fit.scale,
    height: place.height * fit.scale,
  });
}

/** A present adventurer's tap target, over its body, its feet where the renderer puts them. */
export function figureRect(view: Pick<HubView, "origin">, figure: HubFigure, fit: HubFit): Rect {
  const feet = feetPoint(view, figure.at);
  const height = FIGURE_HEIGHT * fit.scale;
  const width = height * 0.6;
  return atLeast({
    left: fit.x + feet.x * fit.scale - width / 2,
    top: fit.y + feet.y * fit.scale - height,
    width,
    height,
  });
}

/** Whether two rectangles share any area (touching edges do not). */
export function overlap(a: Rect, b: Rect): boolean {
  return (
    a.left < b.left + b.width &&
    b.left < a.left + a.width &&
    a.top < b.top + b.height &&
    b.top < a.top + a.height
  );
}

/** A building's tap and its service entry: the same intent, so the same screen. */
export function targetIntent(target: HubTarget): LoopIntent {
  return target.kind === "gate"
    ? { kind: "open gate screen" }
    : { kind: "open service", service: target.service };
}

export function figureIntent(figure: HubFigure): LoopIntent {
  return { kind: "inspect adventurer", adventurer: figure.id };
}
