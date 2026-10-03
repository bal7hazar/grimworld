import { type Container, Graphics, type Sprite, Texture } from "pixi.js";
import { describe, expect, it } from "vitest";
import { tileToPixel, worldToScreen } from "../input/coords";
import { fixtureNamed } from "../sandbox/fixtures";
import { SandboxSession } from "../sandbox/session";
import { initialState, toView } from "../sandbox/wiring";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { LIBRARY_DIRECTIONS, libraryNext } from "../test/hexxLibrary";
import { SYNTHETIC_INDEX, syntheticSheet } from "../test/syntheticAtlas";
import { WEDGE } from "./facing";
import { isRock, voidFoam } from "./ground";
import { OBSTACLES, obstacleOf } from "./obstacles";
import { BAKE_CHUNK, DEFAULT_FEET, IDLE_MAX_FPS, Renderer, STEP_MS, feetOffset } from "./renderer";
import { DIM_ALPHA, drawOverlay, drawTerrain, overlayPlan } from "./shapes";
import type { FrameStats } from "./scheduler";
import { type SpriteArt, type SpriteLibrary, libraryFrom } from "./sprites";
import type { Facing, ViewState, ViewTile } from "./view";

function setup(options: { idle: boolean; library?: SpriteLibrary | null; fixture?: string }) {
  const host = new FakeHost(1000 / 120);
  const surface = new FakeSurface();
  const renderer = new Renderer(surface, host, { idle: options.idle, library: options.library });
  renderer.resize({ width: 375, height: 812 });
  const session = new SandboxSession(fixtureNamed(options.fixture ?? "cave"), renderer, host, {
    playOnTap: true,
    stepMs: STEP_MS,
  });
  const tap = (dx: number, dy: number) => {
    const adventurer = session.state.world.actors[0]!;
    const tile = { x: adventurer.tile.x + dx, y: adventurer.tile.y + dy };
    renderer.scheduler.input();
    session.apply({ kind: "tile", tile });
  };
  return { host, surface, renderer, session, tap };
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
    dropped: [],
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
          const actors = world.children[3] as Container;
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
    expect(world.children).toHaveLength(4); // the world itself is on the stage
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
    expect(world.children).toHaveLength(4); // ground, overlay, dropped steps, actors
  });
});

describe("drawing order during a step", () => {
  it("takes the actor's z from where it is drawn, not from where it goes", () => {
    const { host, surface, tap } = setup({ idle: false, fixture: "meadow" });
    host.run(100);
    tap(0, 1);
    host.run(60);
    const actors = (surface.stage.children[0] as Container).children[3] as Container;
    for (const node of actors.children) expect(node.zIndex).toBe(node.position.y);
  });
});

interface NodeParts {
  readonly container: Container;
  readonly body: Container;
  readonly wedge: Container;
  readonly mark: Container | null;
}

const nodesOf = (renderer: Renderer) => renderer["nodes"] as Map<number, NodeParts>;

describe("the feet in their tile (CLI-03b)", () => {
  const MODES = ["continuous", "snap", "sharp"] as const;

  /** A point of the world in screen CSS px, whatever the mode (sharp: through its offscreen). */
  function onScreen(surface: FakeSurface, node: Container): { x: number; y: number } {
    const top = surface.stage.children[0] as Container;
    const p = node.getGlobalPosition();
    const k = top.children.length === 4 ? 1 : top.scale.x;
    return { x: p.x * k, y: p.y * k };
  }

  for (const withAtlas of [false, true]) {
    const label = withAtlas ? "atlas" : "shapes";
    it(`the feet at the expected pixel for every facing, zoom and mode; wedge on the centre (${label})`, async () => {
      const library = withAtlas ? await syntheticLibrary() : null;
      for (const mode of MODES) {
        for (const feet of [0, DEFAULT_FEET, 0.8]) {
          for (const facing of LIBRARY_DIRECTIONS) {
            const surface = new FakeSurface(2, 2);
            const renderer = new Renderer(surface, new FakeHost(), {
              idle: false,
              library,
              mode,
              feet,
            });
            renderer.resize({ width: 375, height: 812 });
            const tile = { x: 10, y: 11 };
            renderer.setView(oneGoblin(tile.x, tile.y, facing));
            for (const across of [4, 9, 13, 25]) {
              renderer.zoomTo(across);
              renderer.pan(7, -3); // off the goblin's centre
              renderer.draw();
              const { camera, viewport } = renderer.cameraState();
              const node = nodesOf(renderer).get(2)!;
              const centre = tileToPixel(tile);
              const feetAt = { x: centre.x, y: centre.y + feetOffset(feet) };
              const expected = worldToScreen(camera, viewport, feetAt);
              const at = onScreen(surface, node.body);
              const wedge = onScreen(surface, node.wedge);
              const onCentre = worldToScreen(camera, viewport, centre);
              const what = `${mode} feet ${feet} facing ${facing} across ${across}`;
              // Sharp's offscreen is a whole number of pixels: its centre is up to half a pixel
              // off the viewport's, for the wedge as for the feet (as before CLI-03b).
              const digits = mode === "sharp" ? 0 : 6;
              expect(at.x, what).toBeCloseTo(expected.x, digits);
              expect(at.y, what).toBeCloseTo(expected.y, digits);
              expect(wedge.x, what).toBeCloseTo(onCentre.x, digits);
              expect(wedge.y, what).toBeCloseTo(onCentre.y, digits);
              // In every mode, exactly: the feet straight below the wedge, by the offset.
              expect(at.x - wedge.x, what).toBeCloseTo(0, 6);
              expect(at.y - wedge.y, what).toBeCloseTo(feetOffset(feet) * camera.scale, 6);
              // The drawing order stays by row: z is the tile's centre, not the feet.
              expect(node.container.zIndex).toBe(centre.y);
            }
            renderer.destroy();
          }
        }
      }
    });
  }

  it("the feet move body and mark together; overlay (arcs, selection) and wedge do not move", () => {
    const surface = new FakeSurface();
    const renderer = new Renderer(surface, new FakeHost(), { idle: false });
    renderer.resize({ width: 375, height: 812 });
    const base = oneGoblin(10, 10, 0);
    const view: ViewState = {
      ...base,
      arcs: {
        actorId: 2,
        front: [],
        frontSide: [],
        rearSide: [{ x: 10, y: 11 }],
        back: [{ x: 11, y: 10 }],
      },
      selectedTile: { x: 8, y: 12 },
    };
    renderer.setView(view);
    const overlay = renderer["overlay"] as Graphics;
    const node = nodesOf(renderer).get(2)!;
    const before = {
      overlay: overlay.getLocalBounds().rectangle.clone(),
      wedge: node.wedge.position.clone(),
      gap: node.mark!.position.y - node.body.position.y,
    };
    expect(renderer.feetFraction()).toBe(DEFAULT_FEET);
    expect(node.body.position.y).toBeCloseTo(feetOffset(DEFAULT_FEET), 9);
    renderer.setFeet(1);
    expect(node.body.position.y).toBe(32); // the inner radius: half a tile's width
    expect(node.mark!.position.y - node.body.position.y).toBeCloseTo(before.gap, 9);
    expect(node.wedge.position).toEqual(before.wedge);
    expect(overlay.getLocalBounds().rectangle).toEqual(before.overlay);
    renderer.setFeet(0);
    expect(node.body.position.y).toBe(0);
  });
});

describe("the ground in the bakes (CLI-03g1, AC-4)", () => {
  const zoneView = () => toView(initialState(fixtureNamed("zone")));

  function mount(view: ViewState, onDraw?: (stats: FrameStats) => void) {
    const host = new FakeHost(1000 / 120);
    const surface = new FakeSurface();
    const renderer = new Renderer(surface, host, { idle: false, onDraw });
    renderer.resize({ width: 375, height: 812 });
    renderer.setView(view);
    host.run(100);
    return { host, surface, renderer };
  }

  /** The chunks' textures, as their sizes (the ground's layer: the void's sprite apart). */
  const textures = (surface: FakeSurface) =>
    ((surface.stage.children[0] as Container).children[0] as Container).children
      .slice(1)
      .map((s) => `${(s as Sprite).texture.width}x${(s as Sprite).texture.height}`);

  it("the same number and size of textures as the view without its ground", () => {
    const view = zoneView();
    expect(view.tiles.some((t) => t.ground === "water")).toBe(true);
    const plain: ViewState = {
      ...view,
      tiles: view.tiles.map(({ x, y, kind }) => ({ x, y, kind })),
      void: undefined,
    };
    const a = mount(view);
    const b = mount(plain);
    expect(a.surface.bakes).toHaveLength(6);
    expect(textures(a.surface)).toEqual(textures(b.surface));
    expect(a.surface.bakes).toEqual(b.surface.bakes);
  });

  it("rebakes a chunk when a tile's ground changes, and nothing for the same view", () => {
    const view = zoneView();
    const { host, surface, renderer } = mount(view);
    expect(surface.bakes).toHaveLength(6);
    renderer.setView({ ...view });
    host.run(100);
    expect(surface.bakes).toHaveLength(6);
    // A grass hex in the middle of chunk (0, 0) turns to earth: that chunk only.
    const tiles = view.tiles.map((t) =>
      t.x === 7 && t.y === 7 ? { ...t, ground: "earth" as const } : t,
    );
    renderer.setView({ ...view, tiles });
    host.run(100);
    expect(surface.bakes).toHaveLength(7);
    renderer.setView({ ...view, tiles });
    host.run(100);
    expect(surface.bakes).toHaveLength(7);
  });

  it("rebakes a neighbouring chunk whose lip changes across the chunk's edge", () => {
    const view = zoneView();
    const { host, surface, renderer } = mount(view);
    // (15, 7) is the first column of chunk (1, 0): turned to water, (14, 7)'s lip in chunk (0, 0)
    // changes too.
    const tiles = view.tiles.map((t) =>
      t.x === 15 && t.y === 7 ? { ...t, kind: "wall" as const, ground: "water" as const } : t,
    );
    renderer.setView({ ...view, tiles });
    host.run(100);
    expect(surface.bakes).toHaveLength(8);
  });

  it("rebakes a neighbouring chunk whose foam changes, three steps across its edge", () => {
    // (14, 7), the last column of chunk (0, 0), is water; (15..18, 7) in chunk (1, 0) are land.
    const water = (t: ViewTile, at: readonly number[]) =>
      t.y === 7 && at.includes(t.x) ? { ...t, kind: "wall" as const, ground: "water" as const } : t;
    const base = zoneView();
    expect(
      base.tiles.filter((t) => t.y === 7 && t.x >= 14 && t.x <= 18).map((t) => t.ground),
    ).toEqual(["grass", "grass", "grass", "grass", "grass"]);
    const view = { ...base, tiles: base.tiles.map((t) => water(t, [14])) };
    const { host, surface, renderer } = mount(view);
    expect(surface.bakes).toHaveLength(6);
    // (17, 7) turns to water: (16, 7) touches water now, and its foam reaches (14, 7).
    renderer.setView({ ...view, tiles: base.tiles.map((t) => water(t, [14, 17])) });
    host.run(100);
    expect(surface.bakes).toHaveLength(8);
    // (18, 7), four steps from chunk (0, 0): its own chunk only.
    renderer.setView({ ...view, tiles: base.tiles.map((t) => water(t, [14, 17, 18])) });
    host.run(100);
    expect(surface.bakes).toHaveLength(9);
  });

  it("rebakes every chunk once when the library arrives, and draws its cells", async () => {
    const stats: FrameStats[] = [];
    const { host, surface, renderer } = mount(zoneView(), (s) => stats.push(s));
    expect(stats.at(-1)?.ground).toBe("colours");
    renderer.setLibrary(await groundLibrary());
    host.run(1000);
    // Every chunk once, and the foam over the void once per group (CLI-03g2).
    const foamGroups = voidFoamGroups(zoneView());
    expect(foamGroups).toBeGreaterThan(0);
    expect(surface.bakes).toHaveLength(12 + foamGroups);
    expect(stats.at(-1)?.ground).toBe("atlas");
    expect(stats.at(-1)?.bakeMs).not.toBeNull();
    host.run(10_000);
    expect(surface.bakes).toHaveLength(12 + foamGroups);
    expect(host.quiet()).toBe(true);
  });

  it("bakes the foam over the void with the atlas only, per group, again only when it changes", async () => {
    const view = zoneView();
    const { host, renderer, surface } = mount(view);
    const voidLayer = ((surface.stage.children[0] as Container).children[0] as Container)
      .children[0] as Container;
    const foam = voidLayer.children[4] as Container;
    expect(foam.children).toHaveLength(0);
    renderer.setLibrary(await groundLibrary());
    host.run(100);
    expect(foam.children).toHaveLength(voidFoamGroups(view));
    // Each group's texture at its frame: the pieces' box, on whole art pixels.
    for (const sprite of foam.children as Sprite[]) {
      expect(Number.isInteger(sprite.x) && Number.isInteger(sprite.y)).toBe(true);
      expect(sprite.texture).not.toBe(Texture.EMPTY);
    }
    // The same view: nothing baked again.
    const bakes = surface.bakes.length;
    renderer.setView({ ...view });
    host.run(100);
    expect(surface.bakes).toHaveLength(bakes);
    renderer.setLibrary(null);
    expect(foam.children).toHaveLength(0);
  });

  it("draws the void around the terrain, under the chunks; the background inside; none without", () => {
    const view = zoneView();
    const { renderer, surface } = mount(view);
    renderer.draw();
    const ground = (surface.stage.children[0] as Container).children[0] as Container;
    const voidLayer = ground.children[0] as Container;
    expect(voidLayer.visible).toBe(true);
    const bands = voidLayer.children as Sprite[];
    const inBand = (p: { x: number; y: number }) =>
      bands.some((b) => p.x >= b.x && p.x <= b.x + b.width && p.y >= b.y && p.y <= b.y + b.height);
    const adventurer = view.actors.find((a) => a.id === view.adventurerId)!.tile;
    // East of the terrain (x < 0), on screen: the void; four hexes inside: the background.
    expect(inBand(tileToPixel({ x: -2, y: adventurer.y }))).toBe(true);
    expect(inBand(tileToPixel({ x: 4, y: adventurer.y }))).toBe(false);
    // The bands cover the whole frame but the hole: its corners are in a band.
    const { camera, viewport } = renderer.cameraState();
    const half = { x: viewport.width / 2 / camera.scale, y: viewport.height / 2 / camera.scale };
    for (const [sx, sy] of [
      [-1, -1],
      [1, -1],
      [-1, 1],
      [1, 1],
    ] as const) {
      const corner = { x: camera.centre.x + sx * half.x, y: camera.centre.y + sy * half.y };
      if (corner.x > tileToPixel({ x: 2, y: 0 }).x) expect(inBand(corner)).toBe(true);
    }
    const cave = mount(toView(initialState(fixtureNamed("cave"))));
    const caveGround = (cave.surface.stage.children[0] as Container).children[0] as Container;
    expect(caveGround.children[0]!.visible).toBe(false);
  });
});

describe("the zone's walls as the pack's obstacles (CLI-03h)", () => {
  const zoneView = () => toView(initialState(fixtureNamed("zone")));
  const key = (t: { x: number; y: number }) => `${t.x},${t.y}`;

  async function mount(library: SpriteLibrary | null, view: ViewState = zoneView()) {
    const host = new FakeHost(1000 / 120);
    const surface = new FakeSurface();
    const stats: FrameStats[] = [];
    const renderer = new Renderer(surface, host, {
      idle: false,
      library,
      onDraw: (s) => stats.push(s),
    });
    renderer.resize({ width: 375, height: 812 });
    renderer.setView(view);
    host.run(100);
    const actorsLayer = (surface.stage.children[0] as Container).children[3] as Container;
    return { host, surface, renderer, stats, actorsLayer };
  }

  it("each wall hex that drew a rock shows the still its hex chooses, as a prop in the actors' layer", async () => {
    const view = zoneView();
    const walls = view.tiles.filter((t) => isRock(t));
    expect(walls.length).toBeGreaterThan(5);
    const { renderer, stats, actorsLayer } = await mount(await obstacleLibrary(), view);
    const drawn = renderer.obstacles();
    expect([...drawn.keys()].sort()).toEqual(walls.map(key).sort());
    for (const wall of walls) {
      const { sprite, name } = drawn.get(key(wall))!;
      const choice = obstacleOf(wall, OBSTACLES)!;
      expect(name).toBe(choice.sprite);
      expect(sprite.scale.x).toBe(choice.mirror ? -1 : 1);
      expect(sprite.parent).toBe(actorsLayer);
      const base = tileToPixel(wall);
      expect([sprite.x + 0, sprite.y + 0]).toEqual([base.x + 0, base.y + 0]);
      // Sorted with the actors by its base: an actor on its row stands in front of it.
      expect(sprite.zIndex).toBeLessThan(base.y);
      expect(sprite.zIndex).toBeGreaterThan(base.y - 1);
    }
    expect(stats.at(-1)?.obstacles).toBe("atlas");
    // Unrevealed walls and walls on water show none.
    for (const t of view.tiles.filter((t) => t.kind === "wall" && !isRock(t)))
      expect(drawn.has(key(t))).toBe(false);
  });

  it("no rock in the bakes with the atlas's obstacles; the shaped rocks without them", async () => {
    const wall = [{ x: 3, y: 3, kind: "wall" as const }];
    const rocks = drawTerrain(wall).context.instructions.length;
    expect(drawTerrain(wall, new Set(), { rocks: false }).context.instructions.length).toBeLessThan(
      rocks,
    );
    const shapes = await mount(null);
    expect(shapes.renderer.obstacles().size).toBe(0);
    expect(shapes.stats.at(-1)?.obstacles).toBe("shapes");
    // Ground cells without obstacle stills: still the rocks.
    const ground = await mount(await groundLibrary());
    expect(ground.renderer.obstacles().size).toBe(0);
    expect(ground.stats.at(-1)?.obstacles).toBe("shapes");
  });

  it("dimmed beyond sight as the overlay dims the ground; bright in sight", async () => {
    const view = zoneView();
    const { renderer } = await mount(await obstacleLibrary(), view);
    const inSight = new Set(view.sight.map(key));
    const grey = Math.round(255 * (1 - DIM_ALPHA));
    let seen = 0;
    let dimmed = 0;
    for (const [k, { sprite }] of renderer.obstacles()) {
      if (inSight.has(k)) {
        expect(sprite.tint).toBe(0xffffff);
        seen += 1;
      } else {
        expect(sprite.tint).toBe((grey << 16) | (grey << 8) | grey);
        dimmed += 1;
      }
    }
    expect(seen).toBeGreaterThan(0);
    expect(dimmed).toBeGreaterThan(0);
  });

  it("follows the walls: kept for the same view, added on a reveal, dropped with the atlas", async () => {
    const view = zoneView();
    const { host, renderer } = await mount(await obstacleLibrary(), view);
    const before = new Map(renderer.obstacles());
    renderer.setView({ ...view });
    host.run(100);
    for (const [k, node] of renderer.obstacles()) expect(node.sprite).toBe(before.get(k)!.sprite);
    // An unrevealed hex revealed as a wall gets its obstacle; a wall turned floor loses it.
    const hidden = view.tiles.find((t) => t.kind === "unrevealed" && t.ground !== "water")!;
    const gone = view.tiles.find((t) => isRock(t))!;
    const tiles = view.tiles.map((t) =>
      t === hidden ? { ...t, kind: "wall" as const } : t === gone ? { ...t, kind: "floor" as const } : t,
    );
    renderer.setView({ ...view, tiles });
    host.run(100);
    expect(renderer.obstacles().has(key(hidden))).toBe(true);
    expect(renderer.obstacles().has(key(gone))).toBe(false);
    expect(renderer.obstacles().size).toBe(before.size);
    renderer.setLibrary(null);
    expect(renderer.obstacles().size).toBe(0);
  });
});

/** The groups the foam over the void is baked in: the chunks of the void's hexes it lies over. */
function voidFoamGroups(view: ViewState): number {
  const ids = voidFoam(view.tiles, view.void).map(
    (p) => `${Math.floor(p.over.x / BAKE_CHUNK)},${Math.floor(p.over.y / BAKE_CHUNK)}`,
  );
  return new Set(ids).size;
}

/** A library with the ground's cells (`grass_c`, `water_c`, `foam_c`) on a plain-colour texture. */
async function groundLibrary(): Promise<SpriteLibrary> {
  const base = await syntheticLibrary();
  const cell = (name: string): SpriteArt => ({
    name,
    role: "tile",
    cell: { w: 64, h: 64 },
    baseline: 0,
    scale: 1,
    animations: { still: { textures: [Texture.WHITE], fps: 1, loop: false } },
  });
  return new Map([
    ...base,
    ["grass_c", cell("grass_c")],
    ["water_c", cell("water_c")],
    ["foam_c", { ...cell("foam_c"), cell: { w: 192, h: 192 } }],
  ]);
}

/** The ground's cells and every obstacle still (`OBSTACLES`), each on its own plain texture. */
async function obstacleLibrary(): Promise<SpriteLibrary> {
  const base = await groundLibrary();
  const still = (name: string): SpriteArt => ({
    name,
    role: "prop",
    cell: { w: 64, h: 64 },
    baseline: 60,
    scale: 1,
    animations: {
      still: {
        textures: [new Texture({ source: Texture.WHITE.source, defaultAnchor: { x: 0.5, y: 1 } })],
        fps: 1,
        loop: false,
      },
    },
  });
  return new Map([...base, ...OBSTACLES.map((o) => [o.sprite, still(o.sprite)] as const)]);
}
