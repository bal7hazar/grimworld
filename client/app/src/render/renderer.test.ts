import { Container, type Rectangle, Texture, TextureSource } from "pixi.js";
import { describe, expect, it } from "vitest";
import { tileToPixel } from "../input/coords";
import { fixtureNamed } from "../sandbox/fixtures";
import { applyIntent, initialState, toView } from "../sandbox/wiring";
import { FakeHost } from "../test/fakeHost";
import { LIBRARY_DIRECTIONS, libraryNext } from "../test/hexxLibrary";
import { SYNTHETIC_INDEX, syntheticSheet } from "../test/syntheticAtlas";
import { WEDGE } from "./facing";
import { IDLE_MAX_FPS, Renderer, type Surface } from "./renderer";
import { type SpriteLibrary, libraryFrom } from "./sprites";
import type { Facing, ViewState } from "./view";

class FakeSurface implements Surface {
  readonly stage = new Container();
  readonly resolution = 2;
  readonly maxTextureSize = 4096;
  renders = 0;
  readonly bakes: number[] = [];
  render(): void {
    this.renders += 1;
  }
  bake(_target: Container, frame: Rectangle, resolution: number): Texture {
    this.bakes.push(resolution);
    return new Texture({ source: new TextureSource({ width: frame.width, height: frame.height }) });
  }
}

function setup(options: { idle: boolean; library?: SpriteLibrary | null; fixture?: string }) {
  const host = new FakeHost(1000 / 120);
  const surface = new FakeSurface();
  const renderer = new Renderer(surface, host, { idle: options.idle, library: options.library });
  renderer.resize({ width: 375, height: 812 });
  let state = initialState(fixtureNamed(options.fixture ?? "cave"));
  renderer.setView(toView(state));
  const tap = (dx: number, dy: number) => {
    const adventurer = state.world.actors[0]!;
    const tile = { x: adventurer.tile.x + dx, y: adventurer.tile.y + dy };
    state = applyIntent(state, { kind: "tile", tile });
    renderer.scheduler.input();
    renderer.setView(toView(state));
  };
  return { host, surface, renderer, tap };
}

async function syntheticLibrary(): Promise<SpriteLibrary> {
  return libraryFrom(SYNTHETIC_INDEX, [await syntheticSheet()]);
}

describe("renderer on demand (AC-2)", () => {
  it("draws once for a view, then schedules nothing", () => {
    const { host, surface } = setup({ idle: false });
    host.run(2000);
    expect(surface.renders).toBe(1);
    expect(surface.bakes).toHaveLength(1);
    expect(host.quiet()).toBe(true);
  });

  it("after an input and its animation settle, no frame is scheduled", () => {
    const { host, surface, renderer, tap } = setup({ idle: false });
    host.run(1000);
    tap(-1, 0);
    host.run(1000);
    const afterStep = surface.renders - 1;
    // The step (180 ms) and the camera's pan (260 ms) at 120 Hz: about 32 frames, then none.
    expect(afterStep).toBeGreaterThan(10);
    expect(afterStep).toBeLessThan(40);
    expect(renderer.scheduler.stats().sinceInput).toBe(afterStep);
    expect(host.quiet()).toBe(true);
    const frames = host.frames;
    host.run(10_000);
    expect(surface.renders - 1).toBe(afterStep);
    expect(host.frames).toBe(frames);
    // The terrain is not baked again for a step: only the tiles' kinds are baked.
    expect(surface.bakes).toHaveLength(1);
  });

  it("with idle animations off: zero frames between inputs", () => {
    const { host, surface, renderer } = setup({ idle: false });
    host.run(500);
    renderer.scheduler.input();
    const before = surface.renders;
    host.run(60_000);
    expect(surface.renders).toBe(before);
    expect(renderer.scheduler.stats().sinceInput).toBe(0);
    expect(host.frames + host.timersRun).toBe(1);
  });

  for (const [label, library] of [
    ["shapes", async () => null],
    ["atlas sprites", syntheticLibrary],
  ] as const) {
    it(`with idle animations on (${label}): at most ${IDLE_MAX_FPS} frames a second, one wake-up per frame`, async () => {
      const { host, surface, renderer } = setup({ idle: true, library: await library() });
      host.run(1000);
      const renders = surface.renders;
      const wakeups = host.frames;
      host.run(10_000);
      const perSecond = (surface.renders - renders) / 10;
      expect(perSecond).toBeGreaterThanOrEqual(11);
      expect(perSecond).toBeLessThanOrEqual(IDLE_MAX_FPS);
      // Every display frame asked for drew a change of an animated sprite; the rest slept on timers.
      expect(host.frames - wakeups).toBe(surface.renders - renders);
      renderer.setIdle(false);
      host.run(200);
      const off = surface.renders;
      host.run(10_000);
      expect(surface.renders).toBe(off);
      expect(host.quiet()).toBe(true);
    });
  }

  it("draws nothing while the page is hidden, and draws again when it shows", () => {
    const { host, surface, renderer, tap } = setup({ idle: true });
    host.run(1000);
    host.setHidden(true);
    const hidden = surface.renders;
    tap(-1, 0);
    renderer.pan(10, 10);
    host.run(10_000);
    expect(surface.renders).toBe(hidden);
    expect(host.quiet()).toBe(true);
    host.setHidden(false);
    host.run(1000);
    expect(surface.renders).toBeGreaterThan(hidden);
  });

  it("idle animations of a fixture of ten goblins change together: one frame per change", () => {
    const { host, surface } = setup({ idle: true, fixture: "cave" });
    host.run(1000);
    const renders = surface.renders;
    host.run(1000);
    expect(surface.renders - renders).toBe(12);
  });
});

/** A view with one goblin, alone on a meadow of floor. */
function oneGoblin(x: number, y: number, facing: Facing): ViewState {
  const tiles = [];
  for (let ty = y - 2; ty <= y + 2; ty++) {
    for (let tx = x - 2; tx <= x + 2; tx++) {
      tiles.push({ x: tx, y: ty, kind: "floor" as const, seen: "now" as const });
    }
  }
  return {
    tiles,
    actors: [
      { id: 1, side: "adventurer", profession: "vanguard", tile: { x, y: y - 2 }, facing: 0, mark: null },
      { id: 2, side: "goblin", caste: "runt", tile: { x, y }, facing, mark: "alerted" },
    ],
    adventurerId: 1,
    sight: [],
    arcs: null,
    path: [],
    selectedTile: null,
  };
}

describe("the six facings (AC-4), against the library's Direction numbering", () => {
  for (const withAtlas of [false, true]) {
    it(`wedge toward the library's neighbour, sprite mirrored West-ward (${withAtlas ? "atlas" : "shapes"})`, async () => {
      for (const y of [10, 11]) {
        for (const facing of LIBRARY_DIRECTIONS) {
          const surface = new FakeSurface();
          const renderer = new Renderer(surface, new FakeHost(), {
            idle: false,
            library: withAtlas ? await syntheticLibrary() : null,
          });
          const tile = { x: 10, y };
          renderer.setView(oneGoblin(10, y, facing));
          const world = surface.stage.children[0] as Container;
          const actors = world.children[2] as Container;
          const node = actors.children.find(
            (c) => c.position.x === tileToPixel(tile).x && c.position.y === tileToPixel(tile).y,
          ) as Container;
          const [wedge, body] = node.children as [Container, Container];
          // The wedge's tip, in world pixels, lies on the ray to the front tile's centre.
          const [tipX = 0, tipY = 0] = WEDGE;
          const cos = Math.cos(wedge.rotation);
          const sin = Math.sin(wedge.rotation);
          const tip = {
            x: node.position.x + tipX * cos - tipY * sin,
            y: node.position.y + tipX * sin + tipY * cos,
          };
          const front = tileToPixel(libraryNext(tile, facing));
          const toTip = Math.atan2(tip.y - node.position.y, tip.x - node.position.x);
          const toFront = Math.atan2(front.y - node.position.y, front.x - node.position.x);
          expect(Math.abs(Math.sin(toTip - toFront)), `facing ${facing}`).toBeLessThan(1e-9);
          expect(Math.cos(toTip - toFront)).toBeGreaterThan(0);
          // The sprite faces right unless the front tile is to the left (design/10 Facing).
          const left = front.x < node.position.x;
          expect(body.scale.x < 0, `facing ${facing}`).toBe(left);
          expect(left).toBe(facing === 2 || facing === 3 || facing === 4);
          renderer.destroy();
        }
      }
    });
  }
});
