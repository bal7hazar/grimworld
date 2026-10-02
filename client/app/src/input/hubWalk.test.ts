import { describe, expect, it } from "vitest";
import { HUB_VIEWS } from "../sandbox/fixtures/hubs";
import { OUTPOST, TOWN } from "../sandbox/fixtures/region";
import { FakeHost } from "../test/fakeHost";
import type { HubView, WalkedHub } from "../render/hubView";
import type { Tile } from "../render/view";
import { neighbours } from "./coords";
import { hubFit, hubTile, tileScreen } from "./hubTaps";
import {
  DEFAULT_DEPTH,
  HUB_STEP_MS,
  HubWalker,
  footprint,
  hubPath,
  hubWalkable,
  stepFacing,
  walkTaps,
} from "./hubWalk";
import type { LoopIntent } from "./intent";

const town = HUB_VIEWS.get(TOWN)!;
const outpost = HUB_VIEWS.get(OUTPOST)!;
const key = (t: Tile) => `${t.x},${t.y}`;
const adjacent = (a: Tile, b: Tile) => neighbours(a).some((n) => n.x === b.x && n.y === b.y);

/** Every tile whose centre is over the illustration, and a ring around it. */
function tilesOf(view: HubView): Tile[] {
  const tiles: Tile[] = [];
  for (let y = -2; y <= Math.ceil(view.height / 55) + 2; y++) {
    for (let x = -2; x <= Math.ceil(view.width / 64) + 2; x++) tiles.push({ x, y });
  }
  return tiles;
}

/** The zones a hub is drawn in at 375 × 812 and in the 1440 × 900 window's column (CLI-03e). */
const ZONES = [
  { width: 375, height: 599 },
  { width: 430, height: 687 },
];

describe("walkable hexes and paths (CLI-03f, AC-2)", () => {
  for (const view of HUB_VIEWS.values()) {
    describe(view.name, () => {
      const walkable = hubWalkable(view);

      it("the arrival hex is free", () => {
        expect(walkable(view.arrival)).toBe(true);
      });

      it("every place's door is walkable and reachable from the arrival hex", () => {
        for (const place of view.places) {
          expect(walkable(place.at), place.id).toBe(true);
          expect(hubPath(view, view.arrival, place.at), place.id).not.toBeNull();
        }
      });

      it("blocks the buildings' footprints (depth rows behind), props, figures, the edge", () => {
        for (const place of view.places) {
          const tiles = footprint(view, place);
          expect(tiles.some((t) => t.y === place.at.y + (place.depth ?? DEFAULT_DEPTH))).toBe(true);
          for (const t of tiles) {
            if (t.x !== place.at.x || t.y !== place.at.y) expect(walkable(t), key(t)).toBe(false);
          }
        }
        for (const decor of view.decor) {
          for (const t of footprint(view, decor)) expect(walkable(t), decor.id).toBe(false);
        }
        for (const prop of view.props) expect(walkable(prop.at), prop.id).toBe(false);
        for (const figure of view.figures) expect(walkable(figure.at), figure.name).toBe(false);
        // Off the island: the rows and columns past the illustration's edges.
        expect(walkable({ x: -1, y: 0 })).toBe(false);
        expect(walkable({ x: 0, y: -1 })).toBe(false);
      });

      it("no path enters a blocked hex, and every step is to a neighbour", () => {
        let walks = 0;
        for (const to of tilesOf(view)) {
          const path = hubPath(view, view.arrival, to);
          if (!walkable(to)) {
            expect(path, key(to)).toBeNull();
            continue;
          }
          if (!path) continue; // walkable but enclosed: no walk
          walks += 1;
          let from = view.arrival;
          for (const step of path) {
            expect(walkable(step), `${key(to)} through ${key(step)}`).toBe(true);
            expect(adjacent(from, step)).toBe(true);
            from = step;
          }
          expect(from).toEqual(to);
        }
        expect(walks).toBeGreaterThan(20);
      });

      it("every hex of every walk stays inside the zone at both sizes (AC-8)", () => {
        for (const zone of ZONES) {
          const fit = hubFit(view, zone);
          for (const to of tilesOf(view)) {
            for (const step of hubPath(view, view.arrival, to) ?? []) {
              const p = tileScreen(view, fit, step);
              expect(p.x >= 0 && p.x <= zone.width && p.y >= 0 && p.y <= zone.height).toBe(true);
            }
          }
        }
      });
    });
  }

  it("is deterministic: the town's walk from the arrival hex to the Smith's door, pinned", () => {
    const smith = town.places.find((p) => p.id === "smith")!;
    const path = hubPath(town, town.arrival, smith.at);
    expect(path).toEqual(PINNED_SMITH_PATH);
    expect(hubPath(town, town.arrival, smith.at)).toEqual(path);
  });

  it("[] when already there; null when the hex is blocked", () => {
    expect(hubPath(town, town.arrival, town.arrival)).toEqual([]);
    expect(hubPath(town, town.arrival, town.props[0]!.at)).toBeNull();
  });

  it("measures the longest walk from the arrival hex to a door, per hub", () => {
    const longest = (view: WalkedHub) =>
      Math.max(...view.places.map((p) => hubPath(view, view.arrival, p.at)!.length));
    // The figures the report gives: steps, and seconds at the default pace.
    expect([longest(town), longest(outpost)]).toEqual(LONGEST_WALKS);
    expect((longest(town) * HUB_STEP_MS) / 1000).toBeLessThan(4);
  });

  it("stepFacing is the direction of the neighbour stepped to", () => {
    for (const from of [
      { x: 4, y: 4 },
      { x: 4, y: 5 },
    ]) {
      neighbours(from).forEach((n, d) => expect(stepFacing(from, n)).toBe(d));
    }
  });
});

describe("ground taps (CLI-03f, AC-3)", () => {
  it("a tap's point maps to the hex drawn there, at both sizes", () => {
    for (const view of HUB_VIEWS.values()) {
      const walkable = hubWalkable(view);
      for (const zone of ZONES) {
        const fit = hubFit(view, zone);
        for (const tile of tilesOf(view).filter(walkable)) {
          const c = tileScreen(view, fit, tile);
          expect(hubTile(view, fit, c)).toEqual(tile);
          // A few points off the centre, inside the hex (its inner radius is 32 art px).
          const r = 20 * fit.scale;
          for (const [dx, dy] of [
            [r, 0],
            [-r, 0],
            [0, r],
            [0, -r],
          ] as const) {
            expect(hubTile(view, fit, { x: c.x + dx, y: c.y + dy })).toEqual(tile);
          }
        }
      }
    }
  });

  it("measures a hex across its flats at 375 × 812", () => {
    const fit = hubFit(town, ZONES[0]!);
    expect(Math.round(64 * fit.scale * 10) / 10).toBe(TOWN_HEX_POINTS);
  });

  it("walks to a free hex one step per HUB_STEP_MS, facing each step's way", () => {
    const host = new FakeHost();
    const states: { at: Tile; facing: number }[] = [];
    const walker = new HubWalker(town, town.arrival, host, {
      onChange: (s) => states.push({ at: s.at, facing: s.facing }),
    });
    const to = { x: 5, y: 3 };
    const path = hubPath(town, town.arrival, to)!;
    let arrived = 0;
    expect(walker.walkTo(to, () => (arrived += 1))).toBe(true);
    // The first step on the tap.
    expect(walker.state.at).toEqual(path[0]);
    for (let i = 1; i < path.length; i++) {
      host.run(HUB_STEP_MS - 1);
      expect(walker.state.at).toEqual(path[i - 1]);
      host.run(1);
      expect(walker.state.at).toEqual(path[i]);
    }
    expect(arrived).toBe(0);
    host.run(HUB_STEP_MS);
    expect(arrived).toBe(1);
    expect(walker.walking()).toBe(false);
    expect(host.quiet()).toBe(true);
    let from = town.arrival;
    const stepped = states.filter((s, i) => i === 0 || key(s.at) !== key(states[i - 1]!.at));
    for (const s of stepped.slice(1)) {
      expect(s.facing).toBe(stepFacing(from, s.at));
      from = s.at;
    }
  });

  it("a tap during a walk retargets after the step in progress", () => {
    const host = new FakeHost();
    const walker = new HubWalker(town, town.arrival, host);
    walker.walkTo({ x: 5, y: 3 });
    host.run(HUB_STEP_MS / 2);
    const stepping = walker.state.at;
    const to = { x: 7, y: 0 };
    expect(walker.walkTo(to)).toBe(true);
    // Nothing moves before the step in progress ends.
    expect(walker.state.at).toEqual(stepping);
    const path = hubPath(town, stepping, to)!;
    host.run(HUB_STEP_MS / 2);
    expect(walker.state.at).toEqual(path[0]);
    host.run(HUB_STEP_MS * (path.length + 1));
    expect(walker.state.at).toEqual(to);
    expect(host.quiet()).toBe(true);
  });

  it("a tap on a blocked hex or off the island does nothing but a log line", () => {
    const host = new FakeHost();
    const walker = new HubWalker(town, town.arrival, host);
    const lines: string[] = [];
    const sent: LoopIntent[] = [];
    const taps = walkTaps(
      town,
      () => walker,
      (i) => sent.push(i),
      (l) => lines.push(l),
    );
    taps.ground({ kind: "tile", tile: town.props[0]!.at });
    taps.ground({ kind: "tile", tile: { x: -3, y: 0 } });
    expect(lines).toHaveLength(2);
    expect(sent).toEqual([]);
    expect(walker.walking()).toBe(false);
    expect(walker.state.at).toEqual(town.arrival);
    expect(host.quiet()).toBe(true);
  });

  it("pauses while the page is hidden and resumes after", () => {
    const host = new FakeHost();
    const walker = new HubWalker(town, town.arrival, host);
    walker.walkTo({ x: 5, y: 3 });
    host.run(HUB_STEP_MS);
    const at = walker.state.at;
    host.setHidden(true);
    host.run(10_000);
    expect(walker.state.at).toEqual(at);
    expect(host.quiet()).toBe(true);
    host.setHidden(false);
    host.run(HUB_STEP_MS);
    expect(walker.state.at).not.toEqual(at);
    host.run(10_000);
    expect(walker.state.at).toEqual({ x: 5, y: 3 });
  });

  it("arriving schedules nothing and opens nothing", () => {
    const host = new FakeHost();
    const sent: LoopIntent[] = [];
    const walker = new HubWalker(town, town.arrival, host);
    walkTaps(
      town,
      () => walker,
      (i) => sent.push(i),
    );
    host.run(10_000);
    expect(host.quiet()).toBe(true);
    expect(sent).toEqual([]);
  });
});

describe("buildings walk, then open (CLI-03f, AC-4, AC-5)", () => {
  function setup(view = town) {
    const host = new FakeHost();
    const walker = new HubWalker(view, view.arrival, host);
    const sent: LoopIntent[] = [];
    const taps = walkTaps(
      view,
      () => walker,
      (i) => sent.push(i),
    );
    return { host, walker, sent, taps };
  }

  for (const [view, id] of [
    [town, "smith"],
    [outpost, "trainer"],
  ] as const) {
    it(`${view.name}: a tap on the ${id} walks to its door, then opens it once`, () => {
      const { host, walker, sent, taps } = setup(view);
      const place = view.places.find((p) => p.id === id)!;
      const steps = hubPath(view, view.arrival, place.at)!.length;
      taps.place(place);
      host.run(HUB_STEP_MS * steps - 1);
      expect(sent).toEqual([]);
      host.run(1);
      expect(sent).toEqual([{ kind: "open service", service: id }]);
      expect(walker.state.at).toEqual(place.at);
      host.run(10_000);
      expect(sent).toHaveLength(1);
    });
  }

  it("standing on the door, a tap opens at once", () => {
    const smith = town.places.find((p) => p.id === "smith")!;
    const host = new FakeHost();
    const walker = new HubWalker(town, smith.at, host);
    const sent: LoopIntent[] = [];
    walkTaps(
      town,
      () => walker,
      (i) => sent.push(i),
    ).place(smith);
    expect(sent).toEqual([{ kind: "open service", service: "smith" }]);
    expect(host.quiet()).toBe(true);
  });

  it("a ground tap on a door's hex opens it at the walk's end, as the building's tap", () => {
    const { host, sent, taps } = setup();
    const smith = town.places.find((p) => p.id === "smith")!;
    taps.ground({ kind: "tile", tile: smith.at });
    host.run(10_000);
    expect(sent).toEqual([{ kind: "open service", service: "smith" }]);
  });

  it("a walk passing over a door opens nothing", () => {
    // The first ground hex, in reading order, whose walk from the arrival hex crosses a door.
    const doors = new Set(town.places.map((p) => key(p.at)));
    let crossing: Tile | null = null;
    for (const to of tilesOf(town)) {
      if (doors.has(key(to))) continue;
      const path = hubPath(town, town.arrival, to);
      if (path?.slice(0, -1).some((t) => doors.has(key(t)))) {
        crossing = to;
        break;
      }
    }
    expect(crossing).not.toBeNull();
    const { host, sent, taps } = setup();
    taps.ground({ kind: "tile", tile: crossing! });
    host.run(10_000);
    expect(sent).toEqual([]);
  });

  it("the service row opens at once and ends a walk in progress", () => {
    const { host, walker, sent, taps } = setup();
    taps.ground({ kind: "tile", tile: { x: 5, y: 3 } });
    host.run(HUB_STEP_MS);
    const at = walker.state.at;
    taps.now({ kind: "open service", service: "vault" });
    expect(sent).toEqual([{ kind: "open service", service: "vault" }]);
    expect(walker.walking()).toBe(false);
    host.run(10_000);
    expect(walker.state.at).toEqual(at);
    expect(host.quiet()).toBe(true);
  });

  it("a walk ending on the Gate's door opens the Gate screen", () => {
    const { host, sent, taps } = setup();
    const gate = town.places.find((p) => p.target.kind === "gate")!;
    taps.place(gate);
    host.run(10_000);
    expect(sent).toEqual([{ kind: "open gate screen" }]);
  });

  it("a tap on a figure is inspected at once, and ends the walk", () => {
    const { walker, sent, taps } = setup();
    walker.walkTo({ x: 5, y: 3 });
    taps.now({ kind: "inspect adventurer", adventurer: 12 });
    expect(sent).toEqual([{ kind: "inspect adventurer", adventurer: 12 }]);
    expect(walker.walking()).toBe(false);
  });
});

/** The town's arrival hex to the Smith's door: along the road, then up the drawn path. */
const PINNED_SMITH_PATH: Tile[] = [
  { x: 3, y: 0 },
  { x: 4, y: 0 },
  { x: 4, y: 1 },
  { x: 5, y: 2 },
  { x: 4, y: 3 },
  { x: 4, y: 4 },
  { x: 4, y: 5 },
  { x: 5, y: 6 },
  { x: 5, y: 7 },
];
/** The longest walk from the arrival hex to a door, town and outpost, in steps (measured). */
const LONGEST_WALKS = [16, 7];
/** A hex across its flats in the town's zone at 375 × 812, in points (measured). */
const TOWN_HEX_POINTS = 34.1;
