import type { HubFigure, HubPlace, HubTarget, HubView } from "../render/hubView";
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

/** The illustration in its zone: CSS pixels per unit, and where its top-left corner lands. */
export interface HubFit {
  readonly scale: number;
  readonly x: number;
  readonly y: number;
}

/** Touch targets are at least 40 points wide (design/11 I-6). */
export const MIN_TARGET = 40;

/** A figure's height, in illustration units, for its tap target. */
export const FIGURE_HEIGHT = 34;

/** The whole illustration, as large as fits, centred. */
export function hubFit(view: Pick<HubView, "width" | "height">, zone: Size): HubFit {
  const scale = Math.max(0.01, Math.min(zone.width / view.width, zone.height / view.height));
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

/** The building's footprint on screen: centred on its base point, standing on it. */
export function placeRect(place: HubPlace, fit: HubFit): Rect {
  return atLeast({
    left: fit.x + (place.x - place.width / 2) * fit.scale,
    top: fit.y + (place.y - place.height) * fit.scale,
    width: place.width * fit.scale,
    height: place.height * fit.scale,
  });
}

/** A present adventurer's tap target, over its body. */
export function figureRect(figure: HubFigure, fit: HubFit): Rect {
  const height = FIGURE_HEIGHT * fit.scale;
  const width = height * 0.6;
  return atLeast({
    left: fit.x + figure.x * fit.scale - width / 2,
    top: fit.y + figure.y * fit.scale - height,
    width,
    height,
  });
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
