import { describe, expect, it } from "vitest";
import {
  type Point,
  type Viewport,
  fitScale,
  screenToTile,
  tileToPixel,
  worldToScreen,
} from "../input/coords";
import { DEFAULT_ZOOM, Renderer, STEP_MS } from "../render/renderer";
import type { Facing, Tile, ViewActor } from "../render/view";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { LIBRARY_DIRECTIONS, libraryNext } from "../test/hexxLibrary";
import { FIXTURES, fixtureNamed } from "./fixtures";
import { distance, findPath } from "./placeholders";
import { SandboxSession } from "./session";
import { type SandboxState, applyIntent, initialState, toView, walkStep } from "./wiring";
import { type SandboxWorld, kindAt, sameTile } from "./world";

/**
 * Resume 1 of CLI-03b: in the browser the walk was seen to leave the previewed path, and to stop
 * for a goblin "in sight" that was not on screen. These tests pin both, through the same path a
 * tap takes in the browser: a screen point, the camera, a tile, the session, the renderer.
 */

/** The owner's pane: about 800 × 658 CSS px at DPR 2; and a phone in portrait. */
const VIEWPORTS = [
  { width: 800, height: 658 },
  { width: 375, height: 812 },
] as const;

const heroOf = (state: SandboxState) =>
  state.world.actors.find((a) => a.id === state.world.adventurerId)!;

/** A location of floor, walled round (D-134), with only the adventurer. */
function field(walls: readonly Tile[] = []): SandboxWorld {
  const width = 30;
  const height = 30;
  const kinds = Array.from({ length: width * height }, (_, i) => {
    const x = i % width;
    const y = Math.floor(i / width);
    const border = x === 0 || y === 0 || x === width - 1 || y === height - 1;
    return border || walls.some((w) => w.x === x && w.y === y) ? "wall" : "floor";
  });
  const hero: ViewActor = {
    id: 1,
    side: "adventurer",
    profession: "vanguard",
    tile: { x: 14, y: 14 },
    facing: 0,
    mark: null,
  };
  return {
    name: "field",
    description: "",
    terrain: { width, height, kinds, hidden: kinds },
    actors: [hero],
    adventurerId: 1,
    path: [],
  };
}

/** Taps a tile as the browser does: its centre on screen, back to a tile through the camera. */
function tapTile(renderer: Renderer, session: SandboxSession, tile: Tile): void {
  const { camera, viewport } = renderer.cameraState();
  const point: Point = worldToScreen(camera, viewport, tileToPixel(tile));
  const tapped = screenToTile(camera, viewport, point);
  expect(tapped).toEqual(tile);
  renderer.scheduler.input();
  session.apply({ kind: "tile", tile: tapped });
}

/**
 * Previews the path to `target` (tap twice), walks it, and checks after every step that the
 * adventurer stands on the preview's next tile, that it is drawn going there, and that the camera
 * goes there too.
 */
function walkThePreview(world: SandboxWorld, target: Tile, viewport: Viewport = VIEWPORTS[0]) {
  const host = new FakeHost();
  const renderer = new Renderer(new FakeSurface(2, 2), host, { idle: false });
  renderer.resize(viewport);
  const session = new SandboxSession(world, renderer, host, { playOnTap: false, stepMs: STEP_MS });
  host.run(100);
  const start = heroOf(session.state).tile;
  tapTile(renderer, session, target);
  const preview = [...toView(session.state).path];
  const what = `from (${start.x}, ${start.y}) to (${target.x}, ${target.y})`;
  expect(preview.length, what).toBeGreaterThan(0);
  expect(preview.at(-1), what).toEqual(target);
  expect(heroOf(session.state).tile, what).toEqual(start);
  tapTile(renderer, session, target);
  const nodes = renderer["nodes"] as Map<number, { move: { to: number[] } | null }>;
  for (let k = 0; k < preview.length; k++) {
    if (k > 0) host.run(STEP_MS);
    const tile = heroOf(session.state).tile;
    const next = preview[k]!;
    expect(tile, `${what}, step ${k}`).toEqual(next);
    const pixel = tileToPixel(next);
    const tween = renderer["cameraTween"] as { to: number[] } | null;
    expect(tween?.to, `${what}, camera at step ${k}`).toEqual([pixel.x, pixel.y]);
    expect(nodes.get(1)?.move?.to, `${what}, drawn at step ${k}`).toEqual([pixel.x, pixel.y]);
    expect(session.walk().steps, what).toBe(preview.length - k - 1);
  }
  host.run(1000);
  expect(heroOf(session.state).tile, what).toEqual(target);
  expect(renderer.cameraState().camera.centre, what).toEqual(tileToPixel(target));
  expect(session.state.walking).toBe(false);
  return preview;
}

describe("the walk follows the previewed path (Resume 1, bug 1)", () => {
  for (const start of [
    { x: 14, y: 14 },
    { x: 14, y: 15 },
  ]) {
    // One test per direction: each walk is real CPU work (about 0.1 s alone), and a test that
    // sweeps all six would use the whole default budget when the machine is loaded.
    for (const d of LIBRARY_DIRECTIONS) {
      it(`in direction ${d}, 3 tiles, from a row of parity ${start.y & 1}`, () => {
        const base = field();
        const world = {
          ...base,
          actors: base.actors.map((a) => ({ ...a, tile: start })),
        };
        let target = start;
        for (let k = 0; k < 3; k++) target = libraryNext(target, d as Facing);
        const preview = walkThePreview(world, target);
        // A straight line: each step in the direction tapped (the library's neighbour).
        let at = start;
        for (const tile of preview) {
          expect(tile, `direction ${d}`).toEqual(libraryNext(at, d as Facing));
          at = tile;
        }
      });
    }
  }

  it("from the meadow's start, 3 tiles south-east (down-right on screen), as the owner tapped", () => {
    const world = fixtureNamed("meadow");
    const start = heroOf(initialState(world)).tile;
    let target = start;
    for (let k = 0; k < 3; k++) target = libraryNext(target, 5);
    const preview = walkThePreview(world, target);
    // Down-right on screen: each step's centre lower (world y down) and to the right.
    let at = tileToPixel(start);
    for (const tile of preview) {
      const p = tileToPixel(tile);
      expect(p.y).toBeGreaterThan(at.y);
      expect(p.x).toBeGreaterThan(at.x);
      at = p;
    }
  });

  for (const viewport of VIEWPORTS) {
    it(`around a wall, viewport ${viewport.width} × ${viewport.height}`, () => {
      const wall = [10, 11, 12, 13, 14, 15, 16, 17].map((y) => ({ x: 16, y }));
      const world = field(wall);
      const preview = walkThePreview(world, { x: 18, y: 14 }, viewport);
      expect(preview.length).toBeGreaterThan(distance({ x: 14, y: 14 }, { x: 18, y: 14 }));
      expect(preview.some((t) => wall.some((w) => sameTile(w, t)))).toBe(false);
    });
  }

  // The detours are found when the file is collected (cheap: no renderer), and each one is its
  // own test, so a walk's cost is not added to the next one's.
  const cave = fixtureNamed("cave");
  const caveState = initialState(cave);
  const caveStart = heroOf(caveState).tile;
  const detours: Tile[] = [];
  for (let y = 0; y < cave.terrain.height; y++) {
    for (let x = 0; x < cave.terrain.width; x++) {
      const tile = { x, y };
      const path = findPath(caveState.world.terrain, caveState.world.actors, caveStart, tile);
      if (!path || path.length < 4 || path.length > 6) continue;
      if (path.length === distance(caveStart, tile)) continue;
      detours.push(tile);
    }
  }

  it("the cave has detours of 4 to 6 steps from the start", () => {
    expect(detours.length).toBeGreaterThan(3);
  });

  for (const tile of detours) {
    it(`around the cave's walls: the detour to (${tile.x}, ${tile.y})`, () => {
      walkThePreview(cave, tile);
    });
  }
});

/** Whether a tile's centre is on screen, the camera on the adventurer at the default zoom. */
function onScreenAtDefaultZoom(
  viewport: { width: number; height: number },
  hero: Tile,
  tile: Tile,
): boolean {
  const camera = {
    centre: tileToPixel(hero),
    scale: fitScale(viewport, DEFAULT_ZOOM.defaultAcross),
  };
  const p = worldToScreen(camera, viewport, tileToPixel(tile));
  return p.x >= 0 && p.y >= 0 && p.x <= viewport.width && p.y <= viewport.height;
}

describe("a stop for sight names goblins drawn after the step (Resume 1, bug 2)", () => {
  // The sweep over a fixture's floor is real CPU work (0.2 to 0.4 s alone), so each fixture is
  // cut into bands of rows, one test per band: no test is long enough to meet the default budget
  // on a loaded machine.
  const BANDS = 4;
  for (const name of Object.keys(FIXTURES)) {
    for (let band = 0; band < BANDS; band++) {
      it(`every walk of the ${name} fixture, rows ${band + 1}/${BANDS}: the named goblins entered visibleActors at that step, on screen`, () => {
        const world = fixtureNamed(name);
        const rows = Math.ceil(world.terrain.height / BANDS);
        for (let y = band * rows; y < Math.min((band + 1) * rows, world.terrain.height); y++) {
          for (let x = 0; x < world.terrain.width; x++) {
            if (kindAt(world.terrain, { x, y }) !== "floor") continue;
            let state = applyIntent(initialState(world), { kind: "tile", tile: { x, y } });
            while (state.walking) {
              const before = new Set(toView(state).actors.map((a) => a.id));
              state = walkStep(state);
              if (!/came into sight/.test(state.stopped)) continue;
              const hero = heroOf(state).tile;
              // The renderer's input after the step: the same visibleActors.
              const drawn = toView(state).actors;
              const entered = drawn.filter((a) => a.side === "goblin" && !before.has(a.id));
              const what = `${name} to (${x}, ${y}), at (${hero.x}, ${hero.y}): ${state.stopped}`;
              expect(entered.length, what).toBeGreaterThan(0);
              for (const goblin of entered) {
                expect(goblin.side === "goblin" && state.stopped, what).toContain(
                  goblin.side === "goblin" ? goblin.caste : "",
                );
                expect(distance(hero, goblin.tile), what).toBeLessThanOrEqual(6);
                for (const viewport of VIEWPORTS) {
                  expect(onScreenAtDefaultZoom(viewport, hero, goblin.tile), what).toBe(true);
                }
              }
              // Every caste named is one of those that entered.
              const named = state.stopped.match(/\b(runt|skirmisher|slinger|shaman|hobgoblin)\b/g);
              const castes = new Set<string>(
                entered.map((a) => (a.side === "goblin" ? a.caste : "")),
              );
              for (const caste of named ?? []) expect(castes.has(caste), what).toBe(true);
            }
          }
        }
      });
    }
  }

  it("the sweep is not vacuous: the meadow has more than 20 stops for sight", () => {
    const world = fixtureNamed("meadow");
    let stops = 0;
    for (let y = 0; y < world.terrain.height; y++) {
      for (let x = 0; x < world.terrain.width; x++) {
        if (kindAt(world.terrain, { x, y }) !== "floor") continue;
        let state = applyIntent(initialState(world), { kind: "tile", tile: { x, y } });
        while (state.walking) {
          state = walkStep(state);
          if (/came into sight/.test(state.stopped)) stops++;
        }
      }
    }
    expect(stops).toBeGreaterThan(20);
  });
});
