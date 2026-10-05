import { type Container, Rectangle, Texture, TextureSource } from "pixi.js";
import { describe, expect, it } from "vitest";
import { tileToPixel } from "../input/coords";
import { fixtureNamed } from "../sandbox/fixtures";
import { initialState, toView } from "../sandbox/wiring";
import { allExplored } from "../test/explored";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { type FoamMesh, type WaterMode, foamFrame } from "./foam";
import { FOAM_SIZE } from "./ground";
import { tileKey } from "./fog";
import { Renderer } from "./renderer";
import type { SpriteArt, SpriteLibrary } from "./sprites";
import type { ViewState } from "./view";

/** The ground's cells, and the foam's still and its loop of 16 frames on one page. */
function foamLibrary(): SpriteLibrary {
  const cell = (name: string, textures: Texture[], fps = 1): SpriteArt => ({
    name,
    role: "tile",
    cell: { w: 64, h: 64 },
    baseline: 0,
    scale: 1,
    animations: { still: { textures, fps, loop: false } },
  });
  const source = new TextureSource({ width: 16 * FOAM_SIZE, height: FOAM_SIZE });
  const loop = Array.from(
    { length: 16 },
    (_, i) => new Texture({ source, frame: new Rectangle(i * FOAM_SIZE, 0, FOAM_SIZE, FOAM_SIZE) }),
  );
  const foam = cell("foam_c", [loop[0]!]);
  return new Map([
    ["grass_c", cell("grass_c", [Texture.WHITE])],
    ["water_c", cell("water_c", [Texture.WHITE])],
    [
      "foam_c",
      {
        ...foam,
        cell: { w: FOAM_SIZE, h: FOAM_SIZE },
        animations: { ...foam.animations, loop: { textures: loop, fps: 10, loop: true } },
      },
    ],
  ]);
}

/** The zone, every tile explored; `fog: false` draws it all in colour (a view without fog). */
function zone(fog = true): ViewState {
  const view = toView(allExplored(initialState(fixtureNamed("zone"))));
  return fog ? view : { ...view, fog: undefined };
}

function mount(view: ViewState, water: WaterMode = "loop", idle = false) {
  const host = new FakeHost(1000 / 120);
  const surface = new FakeSurface();
  const renderer = new Renderer(surface, host, { idle, water, library: foamLibrary() });
  renderer.resize({ width: 375, height: 812 });
  renderer.setView(view);
  host.run(100);
  const meshes = () => [...(renderer["foamMeshes"] as Map<string, FoamMesh>).values()];
  const grey = () => [...(renderer["greyFoamMeshes"] as Map<string, FoamMesh>).values()];
  return { host, surface, renderer, meshes, grey };
}

/** Frames drawn per second over `seconds`, after a second to settle. */
function rate(host: FakeHost, surface: FakeSurface, seconds = 10): number {
  host.run(1000);
  const before = surface.renders;
  host.run(seconds * 1000);
  return (surface.renders - before) / seconds;
}

describe("the foam animated (CLI-03o, ADR-0003's power rules)", () => {
  it("asks for 10 frames a second while foam is on the screen, through timers", () => {
    const { host, surface, meshes } = mount(zone(false));
    expect(meshes().some((m) => m.mesh.visible)).toBe(true);
    const wakeups = host.frames;
    const renders = surface.renders;
    expect(rate(host, surface)).toBe(10);
    // One display frame asked for per frame drawn: the rest slept on timers.
    expect(host.frames - wakeups).toBe(surface.renders - renders);
  });

  it("each mesh on the screen shows the clock's frame", () => {
    const { host, meshes } = mount(zone(false));
    host.run(1234);
    const tick = Math.floor((host.now() * 10) / 1000);
    for (const mesh of meshes().filter((m) => m.mesh.visible)) {
      expect(mesh.shownTick()).toBe(tick % 16);
    }
    expect(foamFrame(tick, { x: 0, y: 0 }, 16)).toBe(tick % 16);
  });

  it("none when no foam is on the screen, and again when the camera comes back", () => {
    const { host, surface, renderer, meshes } = mount(zone(false));
    renderer.pan(100_000, 0);
    host.run(500);
    expect(meshes().every((m) => !m.mesh.visible)).toBe(true);
    expect(rate(host, surface)).toBe(0);
    expect(host.quiet()).toBe(true);
    renderer.recentre();
    expect(rate(host, surface)).toBe(10);
  });

  it("none while the page is hidden", () => {
    const { host, surface } = mount(zone(false));
    host.setHidden(true);
    expect(rate(host, surface)).toBe(0);
    expect(host.quiet()).toBe(true);
    host.setHidden(false);
    expect(rate(host, surface)).toBe(10);
  });

  it("none with `?water=still`: every piece at frame 0", () => {
    const { host, surface, meshes } = mount(zone(false), "still");
    expect(rate(host, surface)).toBe(0);
    expect(host.quiet()).toBe(true);
    expect(meshes().length).toBeGreaterThan(0);
    for (const mesh of meshes()) expect(mesh.shownTick()).toBeNull();
  });

  it("none without the atlas's loop: the still alone", () => {
    const library = new Map(foamLibrary());
    const foam = library.get("foam_c")!;
    library.set("foam_c", { ...foam, animations: { still: foam.animations.still! } });
    const host = new FakeHost(1000 / 120);
    const surface = new FakeSurface();
    const renderer = new Renderer(surface, host, { idle: false, water: "loop", library });
    renderer.resize({ width: 375, height: 812 });
    renderer.setView(zone(false));
    expect(rate(host, surface)).toBe(0);
    expect(host.quiet()).toBe(true);
  });

  it("with the actors' idle animations: under the idle cap of 15 a second", () => {
    const { host, surface } = mount(zone(false), "loop", true);
    const perSecond = rate(host, surface);
    expect(perSecond).toBeGreaterThanOrEqual(12);
    expect(perSecond).toBeLessThanOrEqual(15);
  });
});

describe("the foam under fog (CLI-03n's exploration, CLI-03o)", () => {
  it("in colour only over the hexes in sight; never over a tile never seen", () => {
    // The zone as it opens: most of it never seen.
    const view = toView(initialState(fixtureNamed("zone")));
    const { meshes, grey, renderer, surface } = mount(view);
    const inSight = new Set(view.sight.map(tileKey));
    const tiles = new Set(view.tiles.map(tileKey));
    const adventurer = view.actors.find((a) => a.id === view.adventurerId)!.tile;
    const colour = meshes().flatMap((m) => m.pieces);
    expect(colour.length).toBeGreaterThan(0);
    for (const piece of colour) {
      const key = tileKey(piece.over);
      // A tile in sight, or the void near the adventurer (it has no tile: drawn in colour by sight).
      expect(inSight.has(key) || !tiles.has(key)).toBe(true);
      if (!tiles.has(key)) {
        const [a, b] = [tileToPixel(piece.over), tileToPixel(adventurer)];
        expect(Math.hypot(a.x - b.x, a.y - b.y)).toBeLessThan(7 * 64);
      }
    }
    // Over the first among the actors (over the overlay's hexes in sight).
    const world = surface.stage.children[0] as Container;
    const actors = world.children[5] as Container;
    expect(meshes()[0]!.mesh.parent?.parent).toBe(actors);
    // The grayscale twin, still, in the grey ground: under the cover, which hides the unseen.
    expect(grey().length).toBeGreaterThan(0);
    for (const mesh of grey()) {
      expect(mesh.shownTick()).toBeNull();
      expect(mesh.mesh.parent?.parent).toBe(world.children[0]);
    }
    const cover = renderer["coverTiles"] as ReadonlySet<string>;
    const hidden = view.tiles.filter((t) => t.kind === "unrevealed").map(tileKey);
    for (const piece of grey().flatMap((m) => m.pieces)) {
      const key = tileKey(piece.over);
      if (hidden.includes(key)) expect(cover.has(key)).toBe(true);
    }
  });

  it("without fog, none over a tile hidden by the cover", () => {
    const base = toView(initialState(fixtureNamed("zone")));
    const view = { ...base, fog: undefined };
    const { meshes } = mount(view);
    const hidden = new Set(
      (view.revealed ?? [])
        .filter((t) => t.kind !== "unrevealed")
        .map(tileKey)
        .filter((k) => view.tiles.some((t) => tileKey(t) === k && t.kind === "unrevealed")),
    );
    expect(hidden.size).toBeGreaterThan(0);
    for (const piece of meshes().flatMap((m) => m.pieces)) {
      expect(hidden.has(tileKey(piece.over))).toBe(false);
    }
  });
});
