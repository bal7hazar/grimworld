import { BufferImageSource, Container, Graphics, Sprite, Spritesheet, Texture } from "pixi.js";
import { describe, expect, it } from "vitest";
import { tileToPixel } from "../input/coords";
import { figureRect, hubFit, placeRect, type Rect } from "../input/hubTaps";
import { HUB_STEP_MS, HubWalker, hubPath } from "../input/hubWalk";
import { BUILDINGS, HUB_VIEWS } from "../sandbox/fixtures/hubs";
import { TOWN } from "../sandbox/fixtures/region";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { HubRenderer, STILL } from "./hubRenderer";
import { type HubView, feetPoint, hubPoint } from "./hubView";
import { Renderer } from "./renderer";
import { type SpritesIndex, libraryFrom } from "./sprites";
import type { Facing, Tile, ViewState } from "./view";

const town = HUB_VIEWS.get(TOWN)!;

function setup(surface = new FakeSurface()) {
  const host = new FakeHost(1000 / 120);
  const renderer = new HubRenderer(surface, host);
  renderer.resize({ width: 375, height: 599 });
  renderer.setView(town);
  return { host, surface, renderer };
}

type Cell = { w: number; h: number; anchor: { x: number; y: number }; role: string; anim: string };

/**
 * A synthetic atlas page (no art): one plain frame per name, each `w` × `h` with the given anchor,
 * one animation each (`still`, or `idle` for a figure).
 */
async function library(cells: Record<string, Cell>) {
  const frames: Record<string, unknown> = {};
  const animations: Record<string, string[]> = {};
  const sprites: Record<string, SpritesIndex["sprites"][string]> = {};
  let x = 0;
  let height = 1;
  for (const [name, c] of Object.entries(cells)) {
    const key = `${name}/${c.anim}/00`;
    frames[key] = {
      frame: { x, y: 0, w: c.w, h: c.h },
      rotated: false,
      trimmed: false,
      spriteSourceSize: { x: 0, y: 0, w: c.w, h: c.h },
      sourceSize: { w: c.w, h: c.h },
      anchor: c.anchor,
    };
    animations[`${name}/${c.anim}`] = [key];
    sprites[name] = {
      role: c.role,
      page: 0,
      cell: { w: c.w, h: c.h },
      baseline: Math.round(c.anchor.y * c.h),
      animations: {
        [c.anim]: { frames: 1, fps: c.anim === STILL ? 1 : 12, loop: c.anim !== STILL },
      },
    };
    x += c.w;
    height = Math.max(height, c.h);
  }
  const json = {
    frames,
    animations,
    meta: {
      image: "atlas-0.png",
      format: "RGBA8888" as const,
      size: { w: x, h: height },
      scale: "1",
    },
  };
  const pixels = new Uint8Array(x * height * 4).fill(200);
  const source = new BufferImageSource({ resource: pixels, width: x, height });
  const sheet = new Spritesheet(new Texture({ source }), json as never);
  await sheet.parse();
  const index: SpritesIndex = { pages: [{ json: "atlas-0.json", image: "atlas-0.png" }], sprites };
  return libraryFrom(index, [sheet]);
}

const base = (role: string, w: number, h: number): Cell => ({
  w,
  h,
  anchor: { x: 0.5, y: 1 },
  role,
  anim: STILL,
});
const tile = (): Cell => ({ w: 64, h: 64, anchor: { x: 0, y: 0 }, role: "tile", anim: STILL });

/** Every still and tile the hubs name, and the three professions, at their fixture sizes. */
async function hubLibrary() {
  const cells: Record<string, Cell> = {};
  for (const [name, [w, h]] of Object.entries(BUILDINGS)) cells[name] = base("building", w, h);
  for (const view of HUB_VIEWS.values()) {
    for (const p of view.props) cells[p.sprite] = base("prop", 40, 60);
    for (const cell of ["nw", "n", "ne", "w", "c", "e", "sw", "s", "se"]) {
      cells[`${view.ground.tileset}_${cell}`] = tile();
    }
    cells[view.ground.water] = tile();
  }
  for (const p of ["vanguard", "warden", "cleric"]) {
    cells[p] = { w: 32, h: 40, anchor: { x: 0.5, y: 0.9 }, role: "profession", anim: "idle" };
  }
  return library(cells);
}

const sceneOf = (renderer: HubRenderer) => renderer.sceneRoot();
const standingOf = (renderer: HubRenderer) => sceneOf(renderer).children[1] as Container;

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
    renderer.setLibrary(await hubLibrary());
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

describe("one scale, the instance's (CLI-03e, AC-1)", () => {
  for (const view of HUB_VIEWS.values()) {
    it(`${view.name}: one factor on the scene, every piece at 1 or −1, on its hex`, async () => {
      const { renderer, host } = setup();
      renderer.setView(view);
      renderer.setLibrary(await hubLibrary());
      host.run(100);
      const fit = renderer.fit()!;
      const scene = sceneOf(renderer);
      expect(scene.scale.x).toBeCloseTo(fit.scale, 12);
      expect(scene.scale.y).toBeCloseTo(fit.scale, 12);
      expect([scene.x, scene.y]).toEqual([fit.x, fit.y]);
      const [ground, standing] = scene.children as [Sprite, Container];
      expect([ground.scale.x, ground.scale.y]).toEqual([1, 1]);
      const pieces = view.places.length + view.decor.length + view.props.length;
      expect(standing.children).toHaveLength(pieces + view.figures.length);
      for (const child of standing.children) {
        expect(child).toBeInstanceOf(Sprite); // the atlas: no shape left
        expect(Math.abs(child.scale.x)).toBe(1);
        expect(child.scale.y).toBe(1);
      }
      const at = new Set(standing.children.map((c) => `${c.x},${c.y}`));
      for (const p of [...view.places, ...view.decor, ...view.props]) {
        const b = hubPoint(view, p.at);
        expect(at.has(`${b.x},${b.y}`), p.id).toBe(true);
      }
      for (const f of view.figures) {
        const b = feetPoint(view, f.at);
        expect(at.has(`${b.x},${b.y}`), f.name).toBe(true);
      }
    });
  }

  it("an adventurer is as tall on screen in a hub as in a room, at the same factor", async () => {
    const lib = await hubLibrary();
    const { renderer: hub, host } = setup();
    hub.setLibrary(lib);
    host.run(100);
    const fit = hub.fit()!;
    const figure = standingOf(hub).children.find(
      (c) => c instanceof Sprite && c.texture === lib.get("vanguard")!.animations.idle!.textures[0],
    )!;
    const inHub = figure.getBounds().height;

    const surface = new FakeSurface();
    const room = new Renderer(surface, new FakeHost(), { idle: false, library: lib });
    room.resize({ width: 375, height: 599 });
    const view: ViewState = {
      tiles: [{ x: 0, y: 0, kind: "floor" }],
      actors: [
        {
          id: 1,
          side: "adventurer",
          profession: "vanguard",
          tile: { x: 0, y: 0 },
          facing: 0,
          mark: null,
        },
      ],
      adventurerId: 1,
      sight: [{ x: 0, y: 0 }],
      arcs: null,
      path: [],
      dropped: [],
      selectedTile: null,
    };
    room.setView(view);
    room.draw();
    const camera = room.cameraState().camera;
    const sprite = findSprite(surface.stage, lib.get("vanguard")!.animations.idle!.textures[0]!);
    const inRoom = sprite!.getBounds().height;
    // Both: the frame's native height times the factor (the sprite's own scale is 1).
    expect(inHub / fit.scale).toBeCloseTo(40, 6);
    expect(inRoom / camera.scale).toBeCloseTo(40, 6);
    room.destroy();
  });
});

function findSprite(node: Container, texture: Texture): Sprite | null {
  for (const child of node.children) {
    if (child instanceof Sprite && child.texture === texture) return child;
    const found = findSprite(child as Container, texture);
    if (found) return found;
  }
  return null;
}

describe("the ground, baked (CLI-03e, AC-4)", () => {
  it("is drawn from the tileset's cells into one texture, once per hub, atlas and size", async () => {
    const surface = new FakeSurface();
    const { renderer, host } = setup(surface);
    host.run(100);
    expect(renderer.bakes).toBe(1); // the shapes' ground, without the atlas
    host.run(10_000);
    expect(renderer.bakes).toBe(1);
    renderer.setLibrary(await hubLibrary());
    host.run(100);
    expect(renderer.bakes).toBe(2);
    renderer.resize({ width: 375, height: 599 }); // the same size: nothing to bake
    host.run(100);
    expect(renderer.bakes).toBe(2);
    renderer.resize({ width: 430, height: 687 });
    host.run(100);
    expect(renderer.bakes).toBe(3);
    renderer.setView(HUB_VIEWS.get(101)!);
    host.run(10_000);
    expect(renderer.bakes).toBe(4);
    expect(surface.bakes).toHaveLength(4);
    // What was baked: the town's or the outpost's cells, side by side, the size of the ground.
    const ground = sceneOf(renderer).children[0] as Sprite;
    expect(ground).toBeInstanceOf(Sprite);
    expect([ground.texture.width, ground.texture.height]).toEqual([576, 704]);
  });

  it("props are drawn at one frame: a still, never an animation", async () => {
    const lib = await hubLibrary();
    const { renderer, host } = setup();
    renderer.setLibrary(lib);
    host.run(100);
    const textures = new Set(
      town.props.map((p) => lib.get(p.sprite)!.animations[STILL]!.textures[0]),
    );
    const props = standingOf(renderer).children.filter(
      (c) => c instanceof Sprite && textures.has(c.texture),
    );
    expect(props).toHaveLength(town.props.length);
    for (const p of town.props)
      expect(lib.get(p.sprite)!.animations[STILL]!.textures).toHaveLength(1);
  });
});

describe("the hub renderer's buildings (CLI-03c AC-1, CLI-03e AC-3)", () => {
  it("draws a building from the atlas at its native size when present, a shape otherwise", async () => {
    const { renderer, host } = setup();
    const castle = town.places.find((p) => p.building === "castle")!;
    const smith = town.places.find((p) => p.building === "forge")!;
    expect(renderer.drawnFromAtlas(castle)).toBe(false);
    const lib = await library({
      castle: { ...base("building", 64, 48), anchor: { x: 0.5, y: 44 / 48 } },
    });
    renderer.setLibrary(lib);
    host.run(100);
    expect(renderer.drawnFromAtlas(castle)).toBe(true);
    expect(renderer.drawnFromAtlas(smith)).toBe(false);
    const sprite = standingOf(renderer).children.find((c) => c instanceof Sprite) as Sprite;
    // Native size: no scale of its own; its base on its door's hex.
    expect([sprite.scale.x, sprite.scale.y]).toEqual([1, 1]);
    expect(sprite.anchor.y).toBeCloseTo(44 / 48);
    const b = hubPoint(town, castle.at);
    expect([sprite.x, sprite.y]).toEqual([b.x, b.y]);
  });

  it("without the atlas: every place a shape at its footprint, decor shapes, no prop", () => {
    const { renderer } = setup();
    const standing = standingOf(renderer).children;
    expect(standing).toHaveLength(town.places.length + town.decor.length + town.figures.length);
    for (const place of town.places) {
      expect(renderer.drawnFromAtlas(place)).toBe(false);
      const b = hubPoint(town, place.at);
      const shape = standing.find((c) => {
        if (!(c instanceof Graphics)) return false;
        const r = c.getLocalBounds();
        return Math.abs((r.minX + r.maxX) / 2 - b.x) < 1 && Math.abs(r.maxY - b.y) < 7;
      });
      expect(shape, place.id).toBeDefined();
      const r = shape!.getLocalBounds();
      expect(r.maxX - r.minX).toBeGreaterThanOrEqual(place.width);
      expect(r.maxY - r.minY).toBeGreaterThanOrEqual(place.height);
    }
  });

  it("fits the illustration in its zone with the taps' fit", () => {
    const { renderer } = setup();
    const scene = sceneOf(renderer);
    const fit = renderer.fit()!;
    expect(scene.scale.x).toBeCloseTo(fit.scale);
    expect([scene.x, scene.y]).toEqual([fit.x, fit.y]);
    expect(fit).toEqual(
      hubFit(town, { width: 375, height: 599 }, { mode: "continuous", resolution: 2 }),
    );
  });

  it("snap: the scene at a whole number of canvas pixels per art pixel", () => {
    const surface = new FakeSurface(2, 2);
    const renderer = new HubRenderer(surface, new FakeHost(), { mode: "snap" });
    renderer.resize({ width: 375, height: 599 });
    renderer.setView(town);
    expect(sceneOf(renderer).scale.x * surface.resolution).toBe(1);
  });

  it("sharp: the scene baked at an integer and drawn down linearly", async () => {
    const surface = new FakeSurface(2, 2);
    const host = new FakeHost();
    const renderer = new HubRenderer(surface, host, { mode: "sharp", library: await hubLibrary() });
    renderer.resize({ width: 375, height: 599 });
    renderer.setView(town);
    host.run(100);
    // The ground's bake, then the scene's, both at 2 texels per art pixel (1.07 wanted).
    expect(surface.bakes).toEqual([2, 2]);
    const shown = surface.stage.children[1] as Sprite;
    expect(shown.texture.source.scaleMode).toBe("linear");
    expect(shown.scale.x).toBeCloseTo(renderer.fit()!.scale, 12);
    // The baked root has no transform of its own: the frame is in art pixels.
    const scene = renderer.sceneRoot();
    expect([scene.scale.x, scene.scale.y, scene.x, scene.y]).toEqual([1, 1, 0, 0]);
    expect(scene.parent).toBeNull();
  });
});

describe("taps reach places and figures only (CLI-03e, AC-6)", () => {
  const inside = (r: Rect, x: number, y: number) =>
    x >= r.left && x <= r.left + r.width && y >= r.top && y <= r.top + r.height;
  for (const view of HUB_VIEWS.values()) {
    it(`${view.name}: no tap target over a decor building or a prop`, () => {
      for (const zone of [
        { width: 375, height: 599 },
        { width: 430, height: 687 },
      ]) {
        const fit = hubFit(view, zone);
        const targets = [
          ...view.places.map((p) => placeRect(view, p, fit)),
          ...view.figures.map((f) => figureRect(view, f, fit)),
        ];
        const middles = [
          ...view.decor.map((d) => ({ id: d.id, at: hubPoint(view, d.at), up: d.height / 2 })),
          ...view.props.map((p) => ({ id: p.id, at: hubPoint(view, p.at), up: 12 })),
        ];
        for (const m of middles) {
          const x = fit.x + m.at.x * fit.scale;
          const y = fit.y + (m.at.y - m.up) * fit.scale;
          for (const r of targets) expect(inside(r, x, y), m.id).toBe(false);
        }
      }
    });

    it(`${view.name}: every place has a label`, () => {
      for (const p of view.places) expect(p.label.length, p.id).toBeGreaterThan(0);
    });
  }
});

/** The room's conversion, as the fixtures' hexes use it. */
it("the hubs' origin is the room's tile (0, 0)", () => {
  const view: Pick<HubView, "origin"> = { origin: { x: 10, y: 20 } };
  expect(hubPoint(view, { x: 0, y: 0 })).toEqual({ x: 10, y: 20 });
  const p = tileToPixel({ x: 3, y: 1 });
  expect(hubPoint(view, { x: 3, y: 1 })).toEqual({ x: 10 + p.x, y: 20 + p.y });
});

/** The hub's art with the vanguard's `move` strip (4 frames) beside its idle frame. */
async function walkLibrary() {
  const lib = await hubLibrary();
  const idle = lib.get("vanguard")!;
  const frames: Record<string, unknown> = {};
  const keys: string[] = [];
  for (let i = 0; i < 4; i++) {
    const key = `vanguard/move/0${i}`;
    keys.push(key);
    frames[key] = {
      frame: { x: i * 32, y: 0, w: 32, h: 40 },
      rotated: false,
      trimmed: false,
      spriteSourceSize: { x: 0, y: 0, w: 32, h: 40 },
      sourceSize: { w: 32, h: 40 },
      anchor: { x: 0.5, y: 0.9 },
    };
  }
  const source = new BufferImageSource({
    resource: new Uint8Array(128 * 40 * 4).fill(90),
    width: 128,
    height: 40,
  });
  const sheet = new Spritesheet(new Texture({ source }), {
    frames,
    animations: { "vanguard/move": keys },
    meta: { image: "move.png", format: "RGBA8888", size: { w: 128, h: 40 }, scale: "1" },
  } as never);
  await sheet.parse();
  const move = { textures: sheet.animations["vanguard/move"]!, fps: 12, loop: true };
  const all = new Map(lib);
  all.set("vanguard", { ...idle, animations: { ...idle.animations, move } });
  return all;
}

describe("the walker (CLI-03f)", () => {
  const walker = (at: Tile, target: Tile | null = null, facing: Facing = 0): HubView => ({
    ...town,
    walker: { profession: "vanguard", at, facing, target },
  });
  /** The walker's node: the standing layer's one plain container, its body inside. */
  const walkerOf = (renderer: HubRenderer) => {
    const node = standingOf(renderer).children.find((c) => c.constructor === Container)!;
    return { node, body: node.children[0] as Sprite };
  };

  it("stands on the arrival hex, as tall as a room's adventurer at the same factor (AC-1)", async () => {
    const lib = await hubLibrary();
    const { renderer, host } = setup();
    renderer.setLibrary(lib);
    renderer.setView(walker(town.arrival));
    host.run(100);
    const fit = renderer.fit()!;
    const feet = feetPoint(town, town.arrival);
    const { node, body } = walkerOf(renderer);
    expect([node.x, node.y]).toEqual([feet.x, feet.y]);
    expect(body).toBeInstanceOf(Sprite);
    expect(body.texture).toBe(lib.get("vanguard")!.animations.idle!.textures[0]);
    expect(body.getBounds().height / fit.scale).toBeCloseTo(40, 6);
    // Every present figure still stands where it stood, and the scene has one more piece.
    const pieces = town.places.length + town.decor.length + town.props.length;
    expect(standingOf(renderer).children).toHaveLength(pieces + town.figures.length + 1);
  });

  it("a walk draws frames while it steps, none after, and never bakes the ground (AC-7, AC-8)", async () => {
    const lib = await walkLibrary();
    const surface = new FakeSurface();
    const { renderer, host } = setup(surface);
    renderer.setLibrary(lib);
    renderer.setView(walker(town.arrival));
    host.run(1000);
    const bakes = renderer.bakes;
    const ground = (sceneOf(renderer).children[0] as Sprite).texture;
    const fit = renderer.fit();
    const before = surface.renders;
    const hubWalker = new HubWalker(town, town.arrival, host, {
      onChange: (s) => renderer.setView(walker(s.at, s.target, s.facing)),
    });
    const to = town.places.find((p) => p.id === "smith")!.at;
    const steps = hubPath(town, town.arrival, to)!.length;
    hubWalker.walkTo(to);
    host.run(HUB_STEP_MS / 2);
    expect(renderer.stepping()).toBe(true);
    // A move frame is shown mid-step.
    const moving = new Set(lib.get("vanguard")!.animations.move!.textures);
    expect(moving.has(walkerOf(renderer).body.texture)).toBe(true);
    host.run(HUB_STEP_MS * (steps + 2));
    const drawn = surface.renders - before;
    // About one frame per display refresh while stepping (120 Hz here): many, and bounded.
    expect(drawn).toBeGreaterThan(steps * 10);
    expect(drawn).toBeLessThan(((steps + 2) * HUB_STEP_MS * 120) / 1000 + 10);
    expect(renderer.stepping()).toBe(false);
    expect(host.quiet()).toBe(true);
    const after = surface.renders;
    host.run(60_000);
    expect(surface.renders).toBe(after);
    // The walker stands at its idle frame on the door; the ground was baked zero times.
    const feet = feetPoint(town, to);
    const { node, body } = walkerOf(renderer);
    expect([node.x, node.y]).toEqual([feet.x, feet.y]);
    expect(body.texture).toBe(lib.get("vanguard")!.animations.idle!.textures[0]);
    expect(renderer.bakes).toBe(bakes);
    expect((sceneOf(renderer).children[0] as Sprite).texture).toBe(ground);
    expect(renderer.fit()).toEqual(fit);
    hubWalker.destroy();
  });

  it("faces the way it steps: West mirrored, East not", async () => {
    const lib = await hubLibrary();
    const { renderer, host } = setup();
    renderer.setLibrary(lib);
    renderer.setView(walker(town.arrival, null, 3));
    host.run(100);
    expect(walkerOf(renderer).body.scale.x).toBeLessThan(0);
    renderer.setView(walker(town.arrival, null, 0));
    host.run(100);
    expect(walkerOf(renderer).body.scale.x).toBeGreaterThan(0);
  });

  it("marks the walk's target faintly, under everything that stands", () => {
    const { renderer, host } = setup();
    renderer.setView(walker(town.arrival, { x: 5, y: 3 }));
    host.run(100);
    const marker = standingOf(renderer).children[0]!;
    expect(marker).toBeInstanceOf(Graphics);
    expect(marker.zIndex).toBe(-Infinity);
    const count = standingOf(renderer).children.length;
    renderer.setView(walker(town.arrival));
    host.run(100);
    expect(standingOf(renderer).children).toHaveLength(count - 1);
  });

  it("is sorted with the standing layer: behind a building whose base is in front", () => {
    const { renderer, host } = setup();
    const smith = town.places.find((p) => p.id === "smith")!;
    // The hex behind the Smith's door (a depth row is blocked, but the view draws any hex).
    renderer.setView(walker({ x: smith.at.x, y: smith.at.y + 1 }));
    host.run(100);
    const children = standingOf(renderer).children;
    const base = hubPoint(town, smith.at);
    const building = children.findIndex(
      (c) => c instanceof Graphics && Math.abs(c.getLocalBounds().maxY - base.y) < 7,
    );
    const walkerAt = children.findIndex(
      (c) => c.zIndex === feetPoint(town, { ...smith.at, y: smith.at.y + 1 }).y,
    );
    expect(building).toBeGreaterThan(-1);
    expect(walkerAt).toBeGreaterThan(-1);
    expect(walkerAt).toBeLessThan(building);
  });
});
