import { describe, expect, it } from "vitest";
import { HUB_VIEWS, OUTPOST_SERVICES, TOWN_SERVICES } from "../sandbox/fixtures/hubs";
import { targetLabel } from "../render/hubView";
import { MIN_TARGET, figureIntent, figureRect, hubFit, placeRect, targetIntent } from "./hubTaps";

const VIEWPORTS = [
  { width: 375, height: 520 },
  { width: 430, height: 600 },
];

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
      it(`${view.name} on ${zone.width} × ${zone.height}: targets inside the zone, ≥ 40 pt (I-6)`, () => {
        const fit = hubFit(view, zone);
        const rects = [
          ...view.places.map((p) => placeRect(p, fit)),
          ...view.figures.map((f) => figureRect(f, fit)),
        ];
        for (const r of rects) {
          expect(r.width).toBeGreaterThanOrEqual(MIN_TARGET);
          expect(r.height).toBeGreaterThanOrEqual(MIN_TARGET);
          expect(r.left + r.width / 2).toBeGreaterThan(0);
          expect(r.left + r.width / 2).toBeLessThan(zone.width);
          expect(r.top + r.height / 2).toBeGreaterThan(0);
          expect(r.top + r.height / 2).toBeLessThan(zone.height);
        }
      });
    }
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
});
