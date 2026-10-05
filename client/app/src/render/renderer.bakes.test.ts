import type { Rectangle, Sprite } from "pixi.js";
import { describe, expect, it } from "vitest";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { DEFAULT_ZOOM, Renderer, type RendererOptions } from "./renderer";
import type { ViewState, ViewTile } from "./view";

/** A view of `side` × `side` floor tiles from (0, 0): (side / 15)² chunks, written by hand. */
function floor(side: number): ViewState {
  const tiles: ViewTile[] = [];
  for (let y = 0; y < side; y++) for (let x = 0; x < side; x++) tiles.push({ x, y, kind: "floor" });
  return {
    tiles,
    actors: [],
    adventurerId: -1,
    sight: tiles,
    arcs: null,
    path: [],
    dropped: [],
    selectedTile: null,
  };
}

type Chunk = { sprite: Sprite; frame: Rectangle; resolution: number };
const chunksOf = (renderer: Renderer) => [...(renderer["chunks"] as Map<string, Chunk>).values()];

function setUp(options: RendererOptions = {}) {
  const host = new FakeHost(1000 / 60);
  const surface = new FakeSurface();
  // Out to 200 across: the zooms below are not clamped.
  const zoom = { ...DEFAULT_ZOOM, minAcross: 200 };
  const renderer = new Renderer(surface, host, { idle: false, water: "still", zoom, ...options });
  renderer.resize({ width: 375, height: 812 });
  renderer.setView(floor(60));
  return { host, surface, renderer };
}

/** Until the next display frame has run. */
function frame(host: FakeHost): void {
  const frames = host.frames;
  while (host.frames === frames) host.run(1);
}

describe("the chunks' bakes spread over frames (CLI-09g)", () => {
  it("by default a zoom step bakes every chunk again in one frame, as before", () => {
    const { host, surface, renderer } = setUp();
    host.run(100);
    const count = chunksOf(renderer).length;
    expect(count).toBe(16);
    const before = surface.bakes.length;
    renderer.zoomAt(2, { x: 187, y: 406 });
    frame(host);
    expect(surface.bakes.length - before).toBe(count);
  });

  it("bakesPerFrame: the chunks on the screen at once, the others a few a frame, until all are", () => {
    const { host, surface, renderer } = setUp({ bakesPerFrame: 2 });
    frame(host);
    const rect = renderer["viewRect"]() as Rectangle;
    const on = chunksOf(renderer).filter((c) => c.frame.intersects(rect));
    expect(on.length).toBeGreaterThan(0);
    expect(on.length).toBeLessThan(16);
    // The first frame bakes every chunk on the screen, and two of the others.
    expect(surface.bakes.length).toBe(on.length + 2);
    host.run(1000);
    expect(surface.bakes.length).toBe(16);
    expect(chunksOf(renderer).every((c) => c.sprite.texture.source.width > 1)).toBe(true);
    // Nothing left: the scheduler sleeps.
    expect(host.quiet()).toBe(true);

    // A zoom step: two chunks a frame, those on the screen first, nearest the centre first.
    renderer.zoomAt(2, { x: 187, y: 406 });
    // At the zoom's resolution (`bakeResolution`, capped by the texture size).
    const atZoom = (c: Chunk) => c.resolution === renderer["bakeResolution"](c.frame);
    frame(host);
    expect(surface.bakes.length).toBe(18);
    const sharp = chunksOf(renderer).filter(atZoom);
    expect(sharp.length).toBe(2);
    const centre = renderer.cameraState().camera.centre;
    const distance = (c: Chunk) =>
      Math.hypot(
        c.frame.x + c.frame.width / 2 - centre.x,
        c.frame.y + c.frame.height / 2 - centre.y,
      );
    const inView = renderer["viewRect"]() as Rectangle;
    const order = chunksOf(renderer).sort(
      (a, b) =>
        Number(b.frame.intersects(inView)) - Number(a.frame.intersects(inView)) ||
        distance(a) - distance(b),
    );
    expect(new Set(sharp)).toEqual(new Set(order.slice(0, 2)));
    host.run(1000);
    expect(surface.bakes.length).toBe(32);
    expect(chunksOf(renderer).every(atZoom)).toBe(true);
    expect(host.quiet()).toBe(true);
  });

  it("bakesPerFrame: a chunk on the screen whose tiles changed is baked at once", () => {
    const { host, surface, renderer } = setUp({ bakesPerFrame: 1 });
    host.run(1000);
    const before = surface.bakes.length;
    const view = floor(60);
    // Tile (0, 0), at the camera's centre, becomes a wall.
    renderer.setView({
      ...view,
      tiles: view.tiles.map((t) => (t.x === 0 && t.y === 0 ? { ...t, kind: "wall" } : t)),
    });
    frame(host);
    expect(surface.bakes.length - before).toBe(1);
  });

  it("keepSharper: a zoom out within it bakes nothing; past it, or a zoom in, bakes again", () => {
    const { host, surface, renderer } = setUp({ keepSharper: 2 });
    host.run(100);
    const mid = { x: 187, y: 406 };
    let before = surface.bakes.length;
    renderer.zoomAt(1 / 1.9, mid);
    host.run(100);
    expect(surface.bakes.length).toBe(before);
    renderer.zoomAt(1 / 1.9, mid);
    host.run(100);
    expect(surface.bakes.length - before).toBe(16);
    before = surface.bakes.length;
    renderer.zoomAt(1.5, mid);
    host.run(100);
    expect(surface.bakes.length - before).toBe(16);
  });

  it("rescaleAfterMs: while the zoom goes on nothing is baked again; once still, it is", () => {
    const { host, surface, renderer } = setUp({ rescaleAfterMs: 200 });
    host.run(100);
    const before = surface.bakes.length;
    const mid = { x: 187, y: 406 };
    for (let i = 0; i < 6; i++) {
      renderer.zoomAt(1.2, mid);
      host.run(50);
    }
    expect(surface.bakes.length).toBe(before);
    host.run(250);
    expect(surface.bakes.length - before).toBe(16);
    expect(host.quiet()).toBe(true);
  });
});
