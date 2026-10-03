import type { Insets, UiSlices } from "../render/sprites";

/**
 * The chrome's one scale (CLI-03i *The method* §3): CSS px per art px, at every pixel ratio, so a
 * control has the same size on every screen. The client scales the pixels itself, nearest-neighbour,
 * to `CHROME_SCALE × devicePixelRatio` device px per art px, and the stylesheet lays every cut image
 * out at one image pixel per device pixel: the browser never resamples it.
 */
export const CHROME_SCALE = 0.5;

/** Device px per art px at a pixel ratio: what the cut scales the art by. */
export function cutScale(dpr: number): number {
  return CHROME_SCALE * dpr;
}

/** A length in art px as whole device px (the cut's pixels), never below 0. */
export function toDevicePx(artPx: number, dpr: number): number {
  return Math.max(0, Math.round(artPx * cutScale(dpr)));
}

/** A length in art px as CSS px landing on whole device px. */
export function toCssPx(artPx: number, dpr: number): number {
  return toDevicePx(artPx, dpr) / dpr;
}

/** What the stylesheet needs of one element at one pixel ratio. */
export interface SliceLengths {
  /** The cut image's size in device px (= image px): the frame × `cutScale`, rounded. */
  readonly image: { readonly w: number; readonly h: number };
  /** The image's size in CSS px: one image px per device px. */
  readonly size: { readonly w: number; readonly h: number };
  /** `border-image-slice`, in image px (whole numbers). */
  readonly slice: Insets;
  /** `border-image-width`, in CSS px: the slices at one image px per device px. */
  readonly width: Insets;
  /** Where text sits, in CSS px on whole device px: the element's padding. */
  readonly content: Insets;
  /** How far the label moves down when pressed, in CSS px on whole device px (0 without art). */
  readonly drop: number;
}

const map4 = (inset: Insets, f: (v: number) => number): Insets => [
  f(inset[0]),
  f(inset[1]),
  f(inset[2]),
  f(inset[3]),
];

/** The lengths of an element of `cell` art px (its frame) at a pixel ratio. */
export function sliceLengths(
  ui: UiSlices,
  cell: { readonly w: number; readonly h: number },
  dpr: number,
): SliceLengths {
  const image = {
    w: Math.max(1, toDevicePx(cell.w, dpr)),
    h: Math.max(1, toDevicePx(cell.h, dpr)),
  };
  const slice = map4(ui.slice, (v) => toDevicePx(v, dpr));
  return {
    image,
    size: { w: image.w / dpr, h: image.h / dpr },
    slice,
    width: map4(slice, (v) => v / dpr),
    content: map4(ui.content, (v) => toCssPx(v, dpr)),
    drop: toCssPx(ui.drop ?? 0, dpr),
  };
}
