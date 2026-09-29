import { type Container, Graphics, type Sprite } from "pixi.js";
import { describe, expect, it } from "vitest";
import { tileToPixel } from "../input/coords";
import { fixtureNamed } from "../sandbox/fixtures";
import { applyIntent, initialState, toView } from "../sandbox/wiring";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { LIBRARY_DIRECTIONS, libraryNext } from "../test/hexxLibrary";
import { SYNTHETIC_INDEX, syntheticSheet } from "../test/syntheticAtlas";
import { WEDGE } from "./facing";
import { IDLE_MAX_FPS, Renderer } from "./renderer";
import { drawOverlay, overlayPlan } from "./shapes";
import { type SpriteLibrary, libraryFrom } from "./sprites";
import type { Facing, ViewState } from "./view";

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
    // The cave is 2 × 1 chunks: one texture each.
    expect(surface.bakes).toHaveLength(2);
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
    expect(surface.bakes).toHaveLength(2);
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
      tiles.push({ x: tx, y: ty, kind: "floor" as const });
    }
  }
  return {
    tiles,
    actors: [
      {
        id: 1,
        side: "adventurer",
        profession: "vanguard",
        tile: { x, y: y - 2 },
        facing: 0,
        mark: null,
      },
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

describe("the terrain, baked chunk by chunk", () => {
  it("rebakes only the chunk whose tile changed kind", () => {
    const { host, surface, renderer } = setup({ idle: false, fixture: "cave" });
    host.run(100);
    expect(surface.bakes).toHaveLength(2);
    const view = toView(initialState(fixtureNamed("cave")));
    const tiles = view.tiles.map((t) =>
      t.x === 3 && t.y === 3
        ? { ...t, kind: t.kind === "wall" ? ("floor" as const) : ("wall" as const) }
        : t,
    );
    renderer.setView({ ...view, tiles });
    host.run(100);
    expect(surface.bakes).toHaveLength(3);
    // The same view again: nothing to bake.
    renderer.setView({ ...view, tiles });
    host.run(100);
    expect(surface.bakes).toHaveLength(3);
  });

  it("caps a chunk's texture by the GPU's limit", () => {
    const surface = new FakeSurface();
    surface.maxTextureSize = 2048;
    const renderer = new Renderer(surface, new FakeHost(), { idle: false });
    renderer.resize({ width: 375, height: 812 });
    renderer.zoomAt(100, { x: 0, y: 0 });
    renderer.setView(toView(initialState(fixtureNamed("cave"))));
    renderer.draw();
    // A chunk is about 1000 art px wide: at most about 2 texture pixels per art pixel.
    expect(Math.max(...surface.bakes)).toBeLessThanOrEqual(2048 / 990);
  });
});

describe("the overlay", () => {
  it("dims the tiles seen before, rings the rear-side, crosses the back", () => {
    const base = oneGoblin(10, 10, 0);
    const view: ViewState = {
      ...base,
      sight: base.tiles.filter((t) => t.y >= 10),
      arcs: {
        actorId: 2,
        front: [{ x: 9, y: 10 }],
        frontSide: [],
        rearSide: [
          { x: 10, y: 11 },
          { x: 10, y: 9 },
        ],
        back: [{ x: 11, y: 10 }],
      },
      selectedTile: { x: 8, y: 12 },
    };
    const plan = overlayPlan(view);
    expect(plan.dimmed).toEqual(base.tiles.filter((t) => t.y < 10));
    expect(plan.rings).toEqual(view.arcs?.rearSide);
    expect(plan.crosses).toEqual(view.arcs?.back);
    const g = new Graphics();
    drawOverlay(g, view);
    const actions = g.context.instructions.map((i) => i.action);
    // Fills: 10 dimmed, 2 rear-side tints, 1 back tint. Strokes: 2 rings, 1 cross, the selection.
    expect(actions.filter((a) => a === "fill")).toHaveLength(13);
    expect(actions.filter((a) => a === "stroke")).toHaveLength(4);
    // No arcs, nothing selected, all in sight: an empty overlay.
    drawOverlay(g, { ...base, sight: base.tiles });
    expect(g.context.instructions).toHaveLength(0);
  });
});

describe("sharp bilinear (the offscreen pass)", () => {
  function sharp(options: { width?: number; height?: number; limit?: number } = {}) {
    const host = new FakeHost();
    const surface = new FakeSurface(2, 2);
    if (options.limit) surface.maxTextureSize = options.limit;
    const renderer = new Renderer(surface, host, { idle: false, mode: "sharp" });
    renderer.resize({ width: options.width ?? 375, height: options.height ?? 812 });
    renderer.setView(toView(initialState(fixtureNamed("cave"))));
    host.run(100);
    return { host, surface, renderer };
  }

  const shown = (surface: FakeSurface) => (surface.stage.children[0] as Sprite).texture;

  it("draws the world into a linear texture at the next integer scale, then down to the target", () => {
    const { surface, renderer } = sharp();
    const texture = renderer.offscreenTexture();
    expect(texture).not.toBeNull();
    // 13 across on 375: 0.4507 CSS px per art px, 0.901 canvas px; n = 1, oversampled × 1.109,
    // allocated in the bucket × 1.25.
    const oversample = 832 / 750; // 1 / (2 × 375 / 832)
    expect(texture!.source.scaleMode).toBe("linear");
    expect(texture!.source.resolution).toBe(2);
    expect(texture!.width).toBe(Math.ceil(375 * 1.25));
    expect(texture!.height).toBe(Math.ceil(812 * 1.25));
    // The frame draws into, and the screen shows, the part it needs.
    const view = shown(surface);
    expect(view.source).toBe(texture!.source);
    expect(view.frame.width).toBe(Math.ceil(375 * oversample));
    expect(view.frame.height).toBe(Math.ceil(812 * oversample));
    expect(renderer.zoomInfo()).toMatchObject({
      mode: "sharp",
      sharpFallback: false,
      offscreen: {
        n: 1,
        width: 2 * Math.ceil(375 * oversample),
        allocatedWidth: 2 * Math.ceil(375 * 1.25),
        cost: expect.closeTo(oversample ** 2, 2),
      },
      across: expect.closeTo(13, 9),
    });
    // The world is the pass's root; the stage holds only the sprite that draws the texture down.
    expect(surface.stage.children).toHaveLength(1);
    // FakeSurface.renderTo throws unless the world is a root (no parent).
    expect(surface.passes).toEqual([view]);
    // Inside the pass an art pixel is exactly n = 1 texel: world scale × oversample × resolution.
    expect(surface.stage.children[0]!.scale.x).toBeCloseTo(1 / oversample, 9);
  });

  it("one pass per frame drawn, none when nothing is drawn; a new texture past its bucket", () => {
    const { host, surface, renderer } = sharp();
    const first = renderer.offscreenTexture()!;
    host.run(5000);
    expect(surface.passes).toHaveLength(surface.renders);
    renderer.pan(5, 0);
    host.run(100);
    expect(renderer.offscreenTexture()).toBe(first); // same size: kept
    renderer.zoomAt(1.3, { x: 187, y: 406 }); // n = 2, oversample 1.70: past the × 1.25 bucket
    host.run(100);
    const zoomed = renderer.offscreenTexture()!;
    expect(zoomed).not.toBe(first);
    expect(first.destroyed).toBe(true);
    renderer.resize({ width: 800, height: 1200 });
    host.run(100);
    expect(renderer.offscreenTexture()).not.toBe(zoomed);
    expect(zoomed.destroyed).toBe(true);
    expect(surface.passes).toHaveLength(surface.renders);
    expect(host.quiet()).toBe(true);
  });

  it("after a zoom that reuses a larger bucket, the pass fills what the figure counts", () => {
    const { host, surface, renderer } = sharp();
    // Out: oversample 1.39, bucket × 1.5 (563 × 1218 CSS px). Back in: oversample 1.11, whose
    // bucket (× 1.25) is smaller, but the × 1.5 texture is kept (within two buckets).
    renderer.zoomAt(0.8, { x: 187.5, y: 406 });
    host.run(100);
    const large = renderer.offscreenTexture()!;
    renderer.zoomAt(1.25, { x: 187.5, y: 406 });
    host.run(100);
    expect(renderer.offscreenTexture()).toBe(large);
    const info = renderer.zoomInfo().offscreen!;
    const allocated = large.source.pixelWidth * large.source.pixelHeight;
    expect(info.allocatedWidth * info.allocatedHeight).toBe(allocated);
    // The pass targets the view of the needed part: it fills exactly the figure's texels…
    const target = surface.passes.at(-1)!;
    expect(target.source).toBe(large.source);
    expect(surface.filled.at(-1)).toBe(info.width * info.height);
    // …which is less than the reused texture holds.
    expect(info.width * info.height).toBeLessThan(allocated * 0.7);
    // The cost figure is that fill against the canvas's pixels.
    expect(info.cost).toBeCloseTo((info.width * info.height) / (750 * 1624), 9);
    // The pass's root paints its backdrop over exactly that part, not the whole texture.
    const root = renderer["passRoot"] as Container;
    const backdrop = root.children[0]!.getLocalBounds();
    expect([backdrop.width * 2, backdrop.height * 2]).toEqual([info.width, info.height]);
  });

  it("a pinch of 60 frames allocates a few textures, not one per frame", () => {
    const { host, renderer } = sharp();
    const allocated = new Set([renderer.offscreenTexture()]);
    // Out, then back in, one wheel step per frame: the needed size changes at every frame.
    for (const factor of [...Array(30).fill(0.985), ...Array(30).fill(1 / 0.985)]) {
      renderer.zoomAt(factor, { x: 187, y: 406 });
      host.run(1000 / 60);
      allocated.add(renderer.offscreenTexture());
    }
    expect(allocated.size).toBeLessThanOrEqual(6);
  });

  it("falls back to drawing directly when the offscreen does not fit the GPU's limit", () => {
    // 1440 × 900 at resolution 2: even × 1 is 2880 × 1800 texels, over a limit of 2048.
    const { surface, renderer } = sharp({ width: 1440, height: 900, limit: 2048 });
    expect(renderer.offscreenTexture()).toBeNull();
    expect(surface.passes).toHaveLength(0);
    expect(surface.renders).toBe(1);
    const world = surface.stage.children[0] as Container;
    expect(world.children).toHaveLength(3); // the world itself is on the stage
    expect(renderer.zoomInfo()).toMatchObject({
      mode: "sharp",
      sharpFallback: true,
      offscreen: null,
    });
    // The same window with a GPU that takes it: the offscreen pass comes back.
    surface.maxTextureSize = 4096;
    renderer.pan(1, 0);
    renderer.draw();
    expect(renderer.offscreenTexture()?.source.pixelWidth).toBeLessThanOrEqual(4096);
    expect(renderer.zoomInfo().sharpFallback).toBe(false);
  });

  it("gives the texture back as soon as it leaves sharp, even with no frame (page hidden)", () => {
    const { host, surface, renderer } = sharp();
    const texture = renderer.offscreenTexture()!;
    host.setHidden(true);
    const renders = surface.renders;
    renderer.setMode("continuous");
    expect(renderer.offscreenTexture()).toBeNull();
    expect(texture.destroyed).toBe(true);
    host.run(1000);
    expect(surface.renders).toBe(renders); // no frame was needed for it
    const world = surface.stage.children[0] as Container;
    expect(world.children).toHaveLength(3); // ground, overlay, actors
  });
});

describe("drawing order during a step", () => {
  it("takes the actor's z from where it is drawn, not from where it goes", () => {
    const { host, surface, tap } = setup({ idle: false, fixture: "meadow" });
    host.run(100);
    tap(0, 1);
    host.run(60);
    const actors = (surface.stage.children[0] as Container).children[2] as Container;
    for (const node of actors.children) expect(node.zIndex).toBe(node.position.y);
  });
});
