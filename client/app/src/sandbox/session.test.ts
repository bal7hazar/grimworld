import type { Container } from "pixi.js";
import { describe, expect, it } from "vitest";
import { tileToPixel } from "../input/coords";
import { FADE_MS, Renderer, STEP_MS } from "../render/renderer";
import type { Tile, ViewActor } from "../render/view";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { fixtureNamed } from "./fixtures";
import { distance } from "./placeholders";
import { SandboxSession } from "./session";
import { applyIntent, initialState, toView, walkStep } from "./wiring";
import type { SandboxWorld } from "./world";

function setup(world: SandboxWorld | string, playOnTap = true) {
  const host = new FakeHost(1000 / 120);
  const surface = new FakeSurface();
  const renderer = new Renderer(surface, host, { idle: false });
  renderer.resize({ width: 375, height: 812 });
  const session = new SandboxSession(
    typeof world === "string" ? fixtureNamed(world) : world,
    renderer,
    host,
    { playOnTap, stepMs: STEP_MS },
  );
  const adventurer = () => session.state.world.actors.find((a) => a.side === "adventurer")!;
  const tap = (tile: Tile) => {
    renderer.scheduler.input();
    session.apply({ kind: "tile", tile });
  };
  const drawnAt = () => {
    const actors = (surface.stage.children[0] as Container).children[3] as Container;
    const target = tileToPixel(adventurer().tile);
    return actors.children.some(
      (c) => Math.abs(c.position.x - target.x) < 1e-9 && Math.abs(c.position.y - target.y) < 1e-9,
    );
  };
  return { host, surface, renderer, session, adventurer, tap, drawnAt };
}

describe("the walk of a planned path (design/02, design/11)", () => {
  it("plays N steps one by one, each drawn as it is played, then stops scheduling", () => {
    const { host, session, adventurer, tap, drawnAt, renderer } = setup("meadow");
    host.run(100);
    const start = adventurer().tile;
    const target = { x: start.x - 5, y: start.y };
    tap(target);
    // The first step is played on the tap.
    expect(adventurer().tile).toEqual({ x: start.x - 1, y: start.y });
    expect(session.walk()).toEqual({ steps: 4, cost: 4, walking: true, stopped: "" });
    const tiles = [adventurer().tile];
    for (let k = 2; k <= 5; k++) {
      host.run(STEP_MS / 2);
      expect(adventurer().tile).toEqual(tiles.at(-1)); // not before its time
      expect(drawnAt()).toBe(false); // the step animates
      host.run(STEP_MS / 2);
      tiles.push(adventurer().tile);
      expect(adventurer().tile).toEqual({ x: start.x - k, y: start.y });
      expect(session.walk().steps).toBe(5 - k);
    }
    host.run(1000);
    expect(drawnAt()).toBe(true);
    expect(session.walk()).toEqual({ steps: 0, cost: 0, walking: false, stopped: "" });
    expect(session.state.said).toContain("arrived");
    // The camera followed: it is centred on the adventurer.
    expect(renderer.cameraState().camera.centre).toEqual(tileToPixel(target));
    expect(host.quiet()).toBe(true);
  });

  it("with tap twice: the first tap previews the path and its cost, the second walks it", () => {
    const { host, session, adventurer, tap } = setup("meadow", false);
    const start = adventurer().tile;
    const target = { x: start.x - 3, y: start.y };
    tap(target);
    expect(adventurer().tile).toEqual(start);
    expect(session.walk()).toEqual({ steps: 3, cost: 3, walking: false, stopped: "" });
    expect(toView(session.state).path).toHaveLength(3);
    expect(toView(session.state).selectedTile).toEqual(target);
    host.run(5000);
    expect(adventurer().tile).toEqual(start);
    tap(target);
    host.run(5000);
    expect(adventurer().tile).toEqual(target);
  });

  it("a tap on the counter cancels: the steps not walked fade out, nothing more is played", () => {
    const { host, surface, session, adventurer, renderer } = setup("meadow");
    const start = adventurer().tile;
    session.apply({ kind: "tile", tile: { x: start.x - 6, y: start.y } });
    host.run(STEP_MS * 1.5);
    expect(adventurer().tile).toEqual({ x: start.x - 2, y: start.y });
    renderer.scheduler.input();
    session.cancel();
    expect(session.walk()).toEqual({ steps: 0, cost: 0, walking: false, stopped: "" });
    expect(session.state.dropped).toHaveLength(4);
    const fading = (surface.stage.children[0] as Container).children[2] as Container;
    expect(fading.alpha).toBe(1);
    host.run(FADE_MS / 2);
    expect(fading.alpha).toBeGreaterThan(0);
    expect(fading.alpha).toBeLessThan(1);
    host.run(10_000);
    expect(adventurer().tile).toEqual({ x: start.x - 2, y: start.y });
    expect(host.quiet()).toBe(true);
  });

  it("stops when a goblin enters sight, the rest fading, with the reason in one line", () => {
    const { host, session, adventurer, tap } = setup("meadow", false);
    const start = adventurer().tile;
    const seen = () => new Set(toView(session.state).actors.map((a) => a.id));
    const before = seen();
    const target = { x: start.x, y: start.y + 6 };
    tap(target);
    const planned = session.state.path.length;
    tap(target);
    host.run(5000);
    const { stopped, dropped } = session.state;
    expect(stopped).toMatch(
      /^an? (runt|skirmisher|slinger|shaman|hobgoblin)( and an? \w+)* came into sight$/,
    );
    const entered = [...seen()].filter((id) => !before.has(id));
    expect(entered.length).toBeGreaterThan(0);
    expect(adventurer().tile).not.toEqual({ x: start.x, y: start.y + 6 });
    expect(dropped.length).toBeGreaterThan(0);
    expect(session.state.path).toEqual([]);
    // Walked and dropped, the whole plan.
    expect(distance(start, adventurer().tile) + dropped.length).toBe(planned);
    expect(session.walk()).toMatchObject({ steps: 0, walking: false, stopped });
    expect(host.quiet()).toBe(true);
  });

  it("stops when a chunk is revealed, after the step that revealed it", () => {
    const { host, session, adventurer } = setup("edge");
    const start = adventurer().tile;
    session.apply({ kind: "tile", tile: { x: start.x + 4, y: start.y } });
    expect(session.state.stopped).toBe("a chunk was revealed");
    expect(adventurer().tile).toEqual({ x: start.x + 1, y: start.y });
    expect(session.state.dropped).toEqual([
      { x: start.x + 2, y: start.y },
      { x: start.x + 3, y: start.y },
      { x: start.x + 4, y: start.y },
    ]);
    host.run(5000);
    expect(adventurer().tile).toEqual({ x: start.x + 1, y: start.y });
    expect(host.quiet()).toBe(true);
  });

  for (const blocker of ["a goblin", "a wall"] as const) {
    it(`stops before an invalid next step (${blocker} on it)`, () => {
      const hero = fixtureNamed("meadow").actors.find((a) => a.side === "adventurer")!;
      const blocked = { x: hero.tile.x - 3, y: hero.tile.y };
      let state = applyIntent(initialState(fixtureNamed("meadow")), {
        kind: "tile",
        tile: { x: hero.tile.x - 5, y: hero.tile.y },
      });
      expect(state.path[2]).toEqual(blocked);
      state = walkStep(state);
      // The world changes under the plan (goblins do not act in the sandbox: by hand).
      const { world } = state;
      const runt = { id: 99, side: "goblin", caste: "runt", tile: blocked, facing: 0, mark: null };
      const kinds = world.terrain.kinds.map((k, i) =>
        i === blocked.y * world.terrain.width + blocked.x ? ("wall" as const) : k,
      );
      state = {
        ...state,
        world:
          blocker === "a goblin"
            ? { ...world, actors: [...world.actors, runt as ViewActor] }
            : { ...world, terrain: { ...world.terrain, kinds } },
      };
      state = walkStep(walkStep(state));
      const adventurer = state.world.actors.find((a) => a.side === "adventurer")!;
      expect(adventurer.tile).toEqual({ x: hero.tile.x - 2, y: hero.tile.y });
      expect(state.stopped).toBe(
        blocker === "a goblin" ? "a runt stands in the way" : "the way is blocked",
      );
      expect(state.walking).toBe(false);
      expect(state.dropped).toHaveLength(3);
      expect(state.dropped[0]).toEqual(blocked);
    });
  }

  it("on demand: nothing is drawn once the walk has ended (AC-5)", () => {
    for (const [fixture, dx] of [
      ["meadow", -6],
      ["edge", 4],
    ] as const) {
      const { host, surface, session, adventurer } = setup(fixture);
      host.run(100);
      const start = adventurer().tile;
      session.apply({ kind: "tile", tile: { x: start.x + dx, y: start.y } });
      host.run(STEP_MS * 7 + FADE_MS + 1000);
      expect(session.walk().walking).toBe(false);
      const renders = surface.renders;
      const wakeups = host.frames + host.timersRun;
      expect(host.quiet()).toBe(true);
      host.run(60_000);
      expect(surface.renders).toBe(renders);
      expect(host.frames + host.timersRun).toBe(wakeups);
    }
  });
});
