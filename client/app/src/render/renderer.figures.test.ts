import type { Texture } from "pixi.js";
import { describe, expect, it } from "vitest";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { SYNTHETIC_INDEX, syntheticSheet } from "../test/syntheticAtlas";
import { figureFrame, figurePhase, nextFrameAt } from "./figures";
import { IDLE_MAX_FPS, Renderer } from "./renderer";
import { type SpriteLibrary, libraryFrom } from "./sprites";
import type { Tile, ViewState, ViewStructure, ViewTile } from "./view";

/**
 * CLI-09e part 3: a structure with an animation (a pack character) loops it on the actors' idle
 * path, phased by its hex, and asks for frames only while one is on the screen, drawn in colour,
 * with the page shown and idle animations on.
 */

async function library(): Promise<SpriteLibrary> {
  return libraryFrom(SYNTHETIC_INDEX, [await syntheticSheet()]);
}

/** A character of the synthetic atlas: `runt`'s idle, 4 frames at 12 fps. */
const figure = (key: string, at: Tile): ViewStructure => ({
  key,
  kind: "figure",
  sprite: "runt",
  animation: "idle",
  at,
  width: 32,
  height: 40,
  covers: [],
});

function viewOf(structures: readonly ViewStructure[], extra: Partial<ViewState> = {}): ViewState {
  const tiles: ViewTile[] = [];
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) tiles.push({ x, y, kind: "floor" });
  return {
    tiles,
    actors: [],
    adventurerId: -1,
    sight: tiles,
    arcs: null,
    path: [],
    dropped: [],
    selectedTile: null,
    structures,
    ...extra,
  };
}

async function setup(structures: readonly ViewStructure[], idle = true) {
  const host = new FakeHost(1000 / 120);
  const surface = new FakeSurface();
  const lib = await library();
  const renderer = new Renderer(surface, host, { idle, library: lib });
  renderer.resize({ width: 1440, height: 900 });
  renderer.setView(viewOf(structures));
  renderer.lookAt({ x: 3, y: 3 });
  host.run(1000);
  const idleFrames = lib.get("runt")!.animations.idle!.textures;
  const shown = (key: string) => renderer.structureSprite(key)!.sprite.texture;
  return { host, surface, renderer, idleFrames, shown };
}

describe("a figure's frame (figures.ts)", () => {
  it("advances at the sprite's fps from its phase, and loops", () => {
    // 12 fps: frame boundaries every 83.3 ms.
    expect(figureFrame(0, 12, 0, 4)).toBe(0);
    expect(figureFrame(84, 12, 0, 4)).toBe(1);
    expect(figureFrame(250, 12, 0, 4)).toBe(3);
    expect(figureFrame(334, 12, 0, 4)).toBe(0);
    // The phase shifts every frame by as many, the boundaries stay shared.
    expect(figureFrame(0, 12, 2, 4)).toBe(2);
    expect(figureFrame(84, 12, 2, 4)).toBe(3);
    expect(figureFrame(84, 12, -3, 4)).toBe(2);
    expect(nextFrameAt(84, 12)).toBeCloseTo(166.67, 1);
    // One frame, or none: frame 0.
    expect(figureFrame(500, 12, 5, 1)).toBe(0);
  });

  it("two characters on neighbouring hexes never share a phase, for the pack's 6 to 12 frames", () => {
    // Odd-r neighbours of an even and an odd row.
    const around = (t: Tile): Tile[] => {
      const odd = t.y % 2 === 1;
      return [
        { x: t.x + 1, y: t.y },
        { x: t.x - 1, y: t.y },
        { x: t.x + (odd ? 1 : 0), y: t.y + 1 },
        { x: t.x + (odd ? 0 : -1), y: t.y + 1 },
        { x: t.x + (odd ? 1 : 0), y: t.y - 1 },
        { x: t.x + (odd ? 0 : -1), y: t.y - 1 },
      ];
    };
    for (const centre of [
      { x: 10, y: 10 },
      { x: 7, y: 3 },
      { x: -4, y: -9 },
    ]) {
      for (const n of around(centre)) {
        for (const count of [6, 7, 8, 10, 12]) {
          const d = (((figurePhase(n) - figurePhase(centre)) % count) + count) % count;
          expect(d, `${JSON.stringify(n)} by ${count}`).not.toBe(0);
        }
      }
    }
  });
});

describe("the renderer's figures (CLI-09e part 3)", () => {
  it("loop their idle at most at IDLE_MAX_FPS, each from its own phase", async () => {
    const { host, surface, renderer, idleFrames, shown } = await setup([
      figure("a", { x: 3, y: 3 }),
      figure("b", { x: 4, y: 3 }),
    ]);
    expect(renderer.structureSprite("a")!.loops).toBe(true);
    const renders = surface.renders;
    const seen = new Set<Texture>();
    let apart = 0;
    for (let i = 0; i < 100; i++) {
      host.run(10);
      seen.add(shown("a"));
      if (shown("a") !== shown("b")) apart += 1;
    }
    // A second: every frame of the loop, at 12 fps, never more than the cap.
    const perSecond = surface.renders - renders;
    expect(perSecond).toBeGreaterThanOrEqual(11);
    expect(perSecond).toBeLessThanOrEqual(IDLE_MAX_FPS);
    expect(seen).toEqual(new Set(idleFrames));
    // Side by side, never in step.
    expect(apart).toBe(100);
    // The frame shown is its phase's at the clock: the clock is past a boundary by under a frame.
    const index = idleFrames.indexOf(shown("a"));
    const phase = figurePhase({ x: 3, y: 3 });
    expect([
      figureFrame(host.time, 12, phase, 4),
      figureFrame(host.time - 1000 / 12, 12, phase, 4),
    ]).toContain(index);
  });

  it("ask for no frame with idle animations off, while the page is hidden, or off the screen", async () => {
    const { host, surface, renderer, idleFrames, shown } = await setup([
      figure("a", { x: 3, y: 3 }),
    ]);
    renderer.setIdle(false);
    host.run(200);
    expect(shown("a")).toBe(idleFrames[0]);
    let before = surface.renders;
    host.run(5000);
    expect(surface.renders).toBe(before);
    expect(host.quiet()).toBe(true);

    renderer.setIdle(true);
    host.run(500);
    host.setHidden(true);
    before = surface.renders;
    const wakeups = host.frames + host.timersRun;
    host.run(5000);
    expect(surface.renders).toBe(before);
    expect(host.frames + host.timersRun).toBe(wakeups);
    host.setHidden(false);
    host.run(500);
    expect(surface.renders).toBeGreaterThan(before);

    // Panned far away: the figure is off the screen, nothing asks for a frame.
    renderer.pan(-100_000, 0);
    host.run(500);
    before = surface.renders;
    host.run(5000);
    expect(surface.renders).toBe(before);
    expect(host.quiet()).toBe(true);
  });

  it("without the atlas: a still shape, no frame", async () => {
    const host = new FakeHost(1000 / 120);
    const surface = new FakeSurface();
    const renderer = new Renderer(surface, host, { idle: true, library: null });
    renderer.resize({ width: 1440, height: 900 });
    renderer.setView(viewOf([figure("a", { x: 3, y: 3 })]));
    host.run(1000);
    expect(renderer.structureFromAtlas("a")).toBe(false);
    const before = surface.renders;
    host.run(5000);
    expect(surface.renders).toBe(before);
  });

  it("on a hex the view hides, not drawn and still; beyond sight under fog, frame 0 in grey", async () => {
    const { host, surface, renderer, idleFrames, shown } = await setup([
      figure("a", { x: 3, y: 3 }),
    ]);
    const base = viewOf([figure("a", { x: 3, y: 3 })]);
    // An instance whose chain revealed the hex, never in sight: hidden.
    renderer.setView({
      ...base,
      tiles: base.tiles.map((t) => (t.x === 3 && t.y === 3 ? { ...t, kind: "unrevealed" } : t)),
      revealed: base.tiles,
    });
    host.run(200);
    expect(renderer.structureVisible("a")).toBe(false);
    let before = surface.renders;
    host.run(3000);
    expect(surface.renders).toBe(before);

    // Seen before, beyond sight, under fog: drawn, grey, frame 0's grey, still.
    renderer.setView({
      ...base,
      sight: base.tiles.filter((t) => t.x < 2),
      fog: { sightRadius: 6 },
    });
    host.run(200);
    expect(renderer.structureVisible("a")).toBe(true);
    expect(idleFrames).not.toContain(shown("a"));
    before = surface.renders;
    host.run(3000);
    expect(surface.renders).toBe(before);

    // Back in sight: its loop again.
    renderer.setView(base);
    host.run(1000);
    expect(idleFrames).toContain(shown("a"));
    before = surface.renders;
    host.run(1000);
    expect(surface.renders).toBeGreaterThan(before + 10);
  });

  it("a structure is built again when its look changes, not for the same view", async () => {
    const { host, renderer } = await setup([figure("a", { x: 3, y: 3 })]);
    const first = renderer.structureSprite("a")!.sprite;
    renderer.setView(viewOf([figure("a", { x: 3, y: 3 })]));
    host.run(100);
    expect(renderer.structureSprite("a")!.sprite).toBe(first);
    renderer.setView(viewOf([{ ...figure("a", { x: 3, y: 3 }), mirror: true }]));
    host.run(100);
    const again = renderer.structureSprite("a")!.sprite;
    expect(again).not.toBe(first);
    expect(again.scale.x).toBe(-1);
  });
});
