import { describe, expect, it } from "vitest";
import { targetIntent } from "../../input/hubTaps";
import type { Intent, LoopIntent } from "../../input/intent";
import type { HubView } from "../../render/hubView";
import { HUB_VIEWS } from "../fixtures/hubs";
import { GATE_KIND, OUTPOST, TOWN, ZONE, globalTile, locationOf } from "../fixtures/region";
import { HubDoors } from "./hubDoors";
import {
  goIntent,
  hubTargets,
  leaveAsked,
  nextTarget,
  serviceIntent,
  zoneTargets,
} from "./keyTargets";

const town = HUB_VIEWS.get(TOWN)!;
const outpost = HUB_VIEWS.get(OUTPOST)!;

/** A hub's doors, recording what they dispatch; the adventurer stands on `standing`. */
function doors(view: HubView, standing = view.arrival) {
  const sent: LoopIntent[] = [];
  const timers = { setTimer: () => 1, clearTimer: () => {} };
  return {
    doors: new HubDoors(
      view,
      (i) => sent.push(i),
      () => standing,
      timers,
      0,
    ),
    sent,
  };
}

describe("hubTargets", () => {
  it.each([
    ["town", town],
    ["outpost", outpost],
  ])("follows the %s's service row", (_, view) => {
    const places = hubTargets(view);
    expect(places.map((p) => p.target)).toEqual(view.services);
    expect(places.length).toBeGreaterThan(1);
  });
});

describe("zoneTargets", () => {
  it("lists the fixture zone's hub gates, lowest id first, one on the zone's entry", () => {
    const anchor = (g: { anchor_chunk: number; anchor_tile: number }) =>
      globalTile(g.anchor_chunk, g.anchor_tile);
    const targets = zoneTargets(ZONE, anchor);
    expect(targets.length).toBeGreaterThan(0);
    expect(targets.every((t) => t.gate.source === ZONE && t.gate.kind === GATE_KIND.hub)).toBe(
      true,
    );
    expect(targets.map((t) => t.gate.id)).toEqual(
      [...targets.map((t) => t.gate.id)].sort((a, b) => a - b),
    );
    const zone = locationOf(ZONE)!;
    const entry = globalTile(zone.entry_chunk, zone.entry_tile);
    expect(targets.some((t) => t.tile.x === entry.x && t.tile.y === entry.y)).toBe(true);
    expect(zoneTargets(999, anchor)).toEqual([]);
  });
});

describe("nextTarget", () => {
  it("wraps both ways, starts at either end, handles 0 and 1 targets", () => {
    expect(nextTarget(0, null, 1)).toBeNull();
    expect(nextTarget(0, null, -1)).toBeNull();
    expect(nextTarget(1, null, 1)).toBe(0);
    expect(nextTarget(1, 0, 1)).toBe(0);
    expect(nextTarget(1, 0, -1)).toBe(0);
    expect(nextTarget(4, null, 1)).toBe(0);
    expect(nextTarget(4, null, -1)).toBe(3);
    expect(nextTarget(4, 3, 1)).toBe(0);
    expect(nextTarget(4, 0, -1)).toBe(3);
    expect(nextTarget(4, 1, 1)).toBe(2);
    expect(nextTarget(4, 9, 1)).toBe(0);
  });
});

describe("keys send the taps' intents (AC-3)", () => {
  it("Enter on a selected place is a tap on its door: the doors answer it alike", () => {
    for (const view of [town, outpost]) {
      for (const place of hubTargets(view)) {
        const tap: Intent = { kind: "tile", tile: place.at };
        expect(goIntent(place.at)).toEqual(tap);
        const byKey = doors(view);
        const byTap = doors(view);
        expect(byKey.doors.route(goIntent(place.at))).toEqual(byTap.doors.route(tap));
        expect(byKey.doors.goingTo()).toBe(byTap.doors.goingTo());
        // On its door already: both open it at once.
        const onDoorKey = doors(view, place.at);
        const onDoorTap = doors(view, place.at);
        expect(onDoorKey.doors.route(goIntent(place.at))).toBeNull();
        onDoorTap.doors.route(tap);
        expect(onDoorKey.sent).toEqual(onDoorTap.sent);
        expect(onDoorKey.sent).toEqual([targetIntent(place.target)]);
      }
    }
  });

  it("1–9 send the service row's own intent; past the row, nothing", () => {
    for (const view of [town, outpost]) {
      view.services.forEach((target, i) => {
        expect(serviceIntent(view, i)).toEqual(targetIntent(target));
      });
      expect(serviceIntent(view, view.services.length)).toBeNull();
      expect(serviceIntent(view, 8 + view.services.length)).toBeNull();
    }
  });

  it("L off an anchor opens nothing; on one, the Leave control's question", () => {
    expect(leaveAsked(null)).toBeNull();
    const anchor = (g: { anchor_chunk: number; anchor_tile: number }) =>
      globalTile(g.anchor_chunk, g.anchor_tile);
    const gate = zoneTargets(ZONE, anchor)[0]!.gate;
    expect(leaveAsked(gate)).toEqual({ kind: "leave", gate });
  });
});
