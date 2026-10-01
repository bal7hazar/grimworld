import { BufferImageSource, Graphics, Sprite, Spritesheet, Texture } from "pixi.js";
import { describe, expect, it } from "vitest";
import { HUB_VIEWS } from "../sandbox/fixtures/hubs";
import { TOWN } from "../sandbox/fixtures/region";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { HubRenderer, STILL } from "./hubRenderer";
import { libraryFrom } from "./sprites";

const town = HUB_VIEWS.get(TOWN)!;

function setup() {
  const host = new FakeHost(1000 / 120);
  const surface = new FakeSurface();
  const renderer = new HubRenderer(surface, host);
  renderer.resize({ width: 375, height: 520 });
  renderer.setView(town);
  return { host, surface, renderer };
}

/** A synthetic atlas page with one still building, `castle` (64 × 48, base at 44): no art. */
async function stillLibrary() {
  const frames = {
    [`castle/${STILL}/00`]: {
      frame: { x: 0, y: 0, w: 64, h: 48 },
      rotated: false,
      trimmed: false,
      spriteSourceSize: { x: 0, y: 0, w: 64, h: 48 },
      sourceSize: { w: 64, h: 48 },
      anchor: { x: 0.5, y: 44 / 48 },
    },
  };
  const json = {
    frames,
    animations: { [`castle/${STILL}`]: [`castle/${STILL}/00`] },
    meta: { image: "atlas-0.png", format: "RGBA8888" as const, size: { w: 64, h: 48 }, scale: "1" },
  };
  const pixels = new Uint8Array(64 * 48 * 4).fill(200);
  const source = new BufferImageSource({ resource: pixels, width: 64, height: 48 });
  const sheet = new Spritesheet(new Texture({ source }), json);
  await sheet.parse();
  const index = {
    pages: [{ json: "atlas-0.json", image: "atlas-0.png" }],
    sprites: {
      castle: {
        role: "building",
        page: 0,
        cell: { w: 64, h: 48 },
        baseline: 44,
        animations: { [STILL]: { frames: 1, fps: 1, loop: false } },
      },
    },
  };
  return libraryFrom(index, [sheet]);
}

describe("the hub renderer on demand (CLI-03c, AC-6)", () => {
  it("draws once for a view, then nothing once input stops", () => {
    const { host, surface } = setup();
    host.run(2000);
    expect(surface.renders).toBe(1);
    expect(host.quiet()).toBe(true);
    host.run(60_000);
    expect(surface.renders).toBe(1);
    expect(host.frames + host.timersRun).toBe(1);
  });

  it("a new view, a size, an atlas: one frame each, and quiet after", async () => {
    const { host, surface, renderer } = setup();
    host.run(100);
    renderer.setView(HUB_VIEWS.get(101)!);
    host.run(100);
    renderer.resize({ width: 430, height: 600 });
    host.run(100);
    renderer.setLibrary(await stillLibrary());
    host.run(10_000);
    expect(surface.renders).toBe(4);
    expect(host.quiet()).toBe(true);
  });

  it("draws nothing while the page is hidden", () => {
    const { host, surface, renderer } = setup();
    host.setHidden(true);
    renderer.setView(town);
    host.run(1000);
    expect(surface.renders).toBe(0);
    host.setHidden(false);
    host.run(1000);
    expect(surface.renders).toBe(1);
  });
});

describe("the hub renderer's buildings (CLI-03c, AC-1)", () => {
  it("draws a building from the atlas when present, a shape otherwise", async () => {
    const { renderer, surface } = setup();
    const castle = town.places.find((p) => p.building === "castle")!;
    const smith = town.places.find((p) => p.building === "house1")!;
    expect(renderer.drawnFromAtlas(castle)).toBe(false);
    renderer.setLibrary(await stillLibrary());
    expect(renderer.drawnFromAtlas(castle)).toBe(true);
    expect(renderer.drawnFromAtlas(smith)).toBe(false);
    const scene = surface.stage.children[0]!;
    // Ground, then the buildings in the view's order, then the figures.
    expect(scene.children).toHaveLength(1 + town.places.length + town.figures.length);
    const index = town.places.indexOf(castle);
    const sprite = scene.children[1 + index] as Sprite;
    expect(sprite).toBeInstanceOf(Sprite);
    // Native size scaled to the footprint's width, its base on the place's point.
    expect(sprite.scale.x).toBeCloseTo(castle.width / 64);
    expect(sprite.anchor.y).toBeCloseTo(44 / 48);
    expect([sprite.x, sprite.y]).toEqual([castle.x, castle.y]);
    expect(scene.children[1 + town.places.indexOf(smith)]).toBeInstanceOf(Graphics);
  });

  it("fits the illustration in its zone with the taps' fit", () => {
    const { renderer, surface } = setup();
    const scene = surface.stage.children[0]!;
    const fit = renderer.fit()!;
    expect(scene.scale.x).toBeCloseTo(fit.scale);
    expect([scene.x, scene.y]).toEqual([fit.x, fit.y]);
  });
});
