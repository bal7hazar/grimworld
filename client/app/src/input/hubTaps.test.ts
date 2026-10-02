import { describe, expect, it } from "vitest";
import { HUB_VIEWS, OUTPOST_SERVICES, TOWN_SERVICES } from "../sandbox/fixtures/hubs";
import { targetLabel } from "../render/hubView";
import { figureIntent, targetIntent } from "./hubTaps";

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
  }

  it("the outpost shows fewer services than the town: one constant", () => {
    expect(TOWN_SERVICES).toHaveLength(8);
    expect(OUTPOST_SERVICES.length).toBeLessThan(TOWN_SERVICES.length);
    for (const s of OUTPOST_SERVICES) expect(TOWN_SERVICES).toContain(s);
  });
});
