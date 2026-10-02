import { describe, expect, it } from "vitest";
import { HUB_VIEWS, OUTPOST_SERVICES, TOWN_SERVICES } from "../sandbox/fixtures/hubs";
import { targetLabel } from "../render/hubView";
import { canvasResolution } from "../render/scaling";
import {
  MIN_TARGET,
  type Rect,
  figureIntent,
  figureRect,
  hubFit,
  overlap,
  placeRect,
  targetIntent,
} from "./hubTaps";

/**
 * The illustration's zone (CLI-03e): on a 375 × 812 phone, the screen less the header (52) and the
 * service rows (3 × 44 + gaps and padding); on a 1440 × 900 desktop, the 430-wide portrait column.
 * The CLI-03c sizes are kept.
 */
const VIEWPORTS = [
  { width: 375, height: 599 },
  { width: 430, height: 687 },
  { width: 375, height: 520 },
  { width: 430, height: 600 },
  // A 320-point phone (fix loop 1 of #307): snap at 1× and 2× falls back to the fitted scale.
  { width: 320, height: 520 },
];
const SCALINGS = [
  { mode: "continuous", resolution: canvasResolution("continuous", 2) },
  { mode: "snap", resolution: canvasResolution("snap", 1) },
  { mode: "snap", resolution: canvasResolution("snap", 2) },
  { mode: "sharp", resolution: canvasResolution("sharp", 3) },
] as const;
// Not `snap` on a 3× phone: a whole number of canvas pixels per art pixel that fits 375 points is
// 1, a third of a point per art pixel (tested below), and the targets grow over each other.

describe("hub taps (CLI-03c, AC-5): every tap yields an intent, never a result", () => {
  for (const [hub, view] of HUB_VIEWS) {
    it(`${view.name}: a building and its service entry yield the same intent`, () => {
      for (const target of view.services) {
        const place = view.places.find(
          (p) => targetLabel(p.target) === targetLabel(target) && p.target.kind === target.kind,
        );
        expect(place, `${hub}: a building for ${targetLabel(target)}`).toBeDefined();
        expect(targetIntent(place!.target)).toEqual(targetIntent(target));
      }
      expect(view.places).toHaveLength(view.services.length);
    });

    it(`${view.name}: the intents name the service, the Gate screen, the adventurer`, () => {
      for (const target of view.services) {
        expect(targetIntent(target)).toEqual(
          target.kind === "gate"
            ? { kind: "open gate screen" }
            : { kind: "open service", service: target.service },
        );
      }
      for (const figure of view.figures) {
        expect(figureIntent(figure)).toEqual({ kind: "inspect adventurer", adventurer: figure.id });
      }
    });

    for (const zone of VIEWPORTS) {
      for (const scaling of SCALINGS) {
        const what = `${zone.width} × ${zone.height} ${scaling.mode} @${scaling.resolution}`;
        it(`${view.name} on ${what}: targets inside the zone, ≥ 40 pt (I-6), none overlap`, () => {
          const fit = hubFit(view, zone, scaling);
          const rects: [string, Rect][] = [
            ...view.places.map((p): [string, Rect] => [p.id, placeRect(view, p, fit)]),
            ...view.figures.map((f): [string, Rect] => [f.name, figureRect(view, f, fit)]),
          ];
          for (const [, r] of rects) {
            expect(r.width).toBeGreaterThanOrEqual(MIN_TARGET);
            expect(r.height).toBeGreaterThanOrEqual(MIN_TARGET);
            expect(r.left + r.width / 2).toBeGreaterThan(0);
            expect(r.left + r.width / 2).toBeLessThan(zone.width);
            expect(r.top + r.height / 2).toBeGreaterThan(0);
            expect(r.top + r.height / 2).toBeLessThan(zone.height);
          }
          for (const [i, [a, ra]] of rects.entries()) {
            for (const [b, rb] of rects.slice(i + 1)) {
              expect(overlap(ra, rb), `${a} and ${b} overlap`).toBe(false);
            }
          }
        });
      }
    }

    it(`${view.name}: a building's target is its native size at the fit, on its door's hex`, () => {
      const fit = hubFit(view, { width: 375, height: 599 });
      for (const place of view.places) {
        const r = placeRect(view, place, fit);
        // At 375 points every building is wider and taller than 40 points: no growth.
        expect(r.width).toBeCloseTo(place.width * fit.scale, 9);
        expect(r.height).toBeCloseTo(place.height * fit.scale, 9);
      }
    });
  }

  it("the outpost shows fewer services than the town: one constant", () => {
    expect(TOWN_SERVICES).toHaveLength(8);
    expect(OUTPOST_SERVICES.length).toBeLessThan(TOWN_SERVICES.length);
    for (const s of OUTPOST_SERVICES) expect(TOWN_SERVICES).toContain(s);
  });

  it("fits the whole illustration, centred", () => {
    const fit = hubFit({ width: 360, height: 300 }, { width: 375, height: 520 });
    expect(fit.scale).toBeCloseTo(375 / 360);
    expect(fit.x).toBeCloseTo(0);
    expect(fit.y).toBeCloseTo((520 - 300 * fit.scale) / 2);
  });

  it("the town at 375 points: about half a point per art pixel (CLI-03e §1)", () => {
    const town = [...HUB_VIEWS.values()][0]!;
    const fit = hubFit(town, { width: 375, height: 599 });
    expect(fit.scale).toBeCloseTo(375 / town.width, 9); // fitted by width
    expect(fit.scale).toBeGreaterThan(0.5);
    expect(fit.scale).toBeLessThan(0.55);
  });

  it("snap: a whole number of canvas pixels per art pixel, the largest that fits", () => {
    const view = { width: 704, height: 960 };
    const zone = { width: 375, height: 599 };
    const two = hubFit(view, zone, { mode: "snap", resolution: 2 });
    expect(two.scale).toBe(0.5); // one device pixel per art pixel at a ratio of 2
    expect(Number.isInteger(two.x * 2) && Number.isInteger(two.y * 2)).toBe(true);
    const three = hubFit(view, zone, { mode: "snap", resolution: 3 });
    expect(three.scale).toBeCloseTo(1 / 3, 12); // 1.6 canvas px wanted; 2 would not fit: 1
    const desktop = hubFit(view, { width: 430, height: 687 }, { mode: "snap", resolution: 2 });
    expect(desktop.scale).toBe(0.5);
    const wide = hubFit(view, { width: 1500, height: 2000 }, { mode: "snap", resolution: 2 });
    expect(wide.scale).toBe(2); // 4 canvas px per art pixel
  });

  it("snap never overflows: below one canvas pixel per art pixel, the fitted scale", () => {
    const view = { width: 704, height: 960 };
    for (const [zone, r] of [
      [{ width: 430, height: 687 }, 1],
      [{ width: 375, height: 599 }, 1],
      [{ width: 320, height: 520 }, 2],
    ] as const) {
      const fit = hubFit(view, zone, { mode: "snap", resolution: r });
      expect(fit.scale).toBeCloseTo(hubFit(view, zone).scale, 12);
      expect(fit.x).toBeGreaterThanOrEqual(0);
      expect(fit.y).toBeGreaterThanOrEqual(0);
      expect(view.width * fit.scale).toBeLessThanOrEqual(zone.width);
    }
  });
});
