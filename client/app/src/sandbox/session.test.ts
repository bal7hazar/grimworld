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
    const actors = (surface.stage.children[0] as Container).children[5] as Container;
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
    expect(session.walk()).toEqual({
      steps: 0,
      cost: 0,
      walking: false,
      stopped: "walk cancelled",
    });
    expect(session.state.dropped).toHaveLength(4);
    const fading = (surface.stage.children[0] as Container).children[4] as Container;
    expect(fading.alpha).toBe(1);
    host.run(FADE_MS / 2);
    expect(fading.alpha).toBeGreaterThan(0);
    expect(fading.alpha).toBeLessThan(1);
    host.run(10_000);
    expect(adventurer().tile).toEqual({ x: start.x - 2, y: start.y });
    expect(host.quiet()).toBe(true);
  });

  it("a tap on the map that ends a walk says so; one that starts another walk does not", () => {
    const { host, session, adventurer, tap } = setup("meadow");
    const start = adventurer().tile;
    tap({ x: start.x - 6, y: start.y });
    host.run(STEP_MS);
    tap({ x: -1, y: -1 }); // outside the location (a tile never seen does nothing, CLI-03n)
    expect(session.walk()).toMatchObject({ steps: 0, walking: false, stopped: "walk cancelled" });
    tap({ x: start.x - 6, y: start.y });
    host.run(STEP_MS / 2);
    tap({ x: start.x - 6, y: start.y - 1 }); // another floor tile: the new walk replaces the old
    expect(session.walk()).toMatchObject({ walking: true, stopped: "" });
    expect(session.walk().steps).toBeGreaterThan(0);
    host.run(5000);
    expect(host.quiet()).toBe(true);
  });

  it("an inspect during a walk plays no step and keeps the walk's pace (F-1)", () => {
    const { host, session, adventurer } = setup("meadow");
    const start = adventurer().tile;
    session.apply({ kind: "tile", tile: { x: start.x - 6, y: start.y } });
    // Steps due at 0, 180, 360, … ms; inspects every 50 ms, on the adventurer and elsewhere.
    const seen: { at: number; x: number }[] = [];
    let last = adventurer().tile.x;
    for (let t = 0; t < STEP_MS * 6; t += 10) {
      if (t % 50 === 0) {
        const tile = t % 100 === 0 ? adventurer().tile : { x: start.x, y: start.y + 3 };
        session.apply({ kind: "inspect", tile });
        expect(session.state.said).toContain("inspect");
      }
      host.run(10);
      if (adventurer().tile.x !== last) {
        last = adventurer().tile.x;
        seen.push({ at: host.time, x: last });
      }
    }
    expect(seen.map((s) => s.at)).toEqual([180, 360, 540, 720, 900]);
    expect(seen.map((s) => s.x)).toEqual([2, 3, 4, 5, 6].map((k) => start.x - k));
    expect(session.walk().walking).toBe(false);
  });

  it("no step is played while the page is hidden; the walk resumes when it shows", () => {
    const { host, session, adventurer, surface } = setup("meadow");
    const start = adventurer().tile;
    session.apply({ kind: "tile", tile: { x: start.x - 6, y: start.y } });
    host.run(STEP_MS * 1.5); // two steps played
    expect(adventurer().tile).toEqual({ x: start.x - 2, y: start.y });
    host.setHidden(true);
    const renders = surface.renders;
    host.run(60_000);
    expect(adventurer().tile).toEqual({ x: start.x - 2, y: start.y });
    expect(session.stepScheduled()).toBe(false);
    expect(host.quiet()).toBe(true);
    expect(surface.renders).toBe(renders);
    expect(session.walk()).toMatchObject({ steps: 4, walking: true, stopped: "" });
    // Shown: the next step one step's duration later, then the rest at the same pace.
    host.setHidden(false);
    host.run(STEP_MS - 1);
    expect(adventurer().tile).toEqual({ x: start.x - 2, y: start.y });
    host.run(1);
    expect(adventurer().tile).toEqual({ x: start.x - 3, y: start.y });
    host.run(STEP_MS * 3);
    expect(adventurer().tile).toEqual({ x: start.x - 6, y: start.y });
    host.run(5000);
    expect(session.walk().walking).toBe(false);
    expect(host.quiet()).toBe(true);
  });

  it("with idle animations on (D-151): after a walk and its fade, only the idle cadence remains", () => {
    const host = new FakeHost(1000 / 120);
    const surface = new FakeSurface();
    const renderer = new Renderer(surface, host, { idle: true });
    renderer.resize({ width: 375, height: 812 });
    const session = new SandboxSession(fixtureNamed("edge"), renderer, host, {
      playOnTap: true,
      stepMs: STEP_MS,
    });
    host.run(1000);
    const cadence = () => {
      const renders = surface.renders;
      const wakeups = host.frames + host.timersRun;
      host.run(10_000);
      return {
        renders: surface.renders - renders,
        wakeups: host.frames + host.timersRun - wakeups,
      };
    };
    const before = cadence();
    const start = session.state.world.actors[0]!.tile;
    session.apply({ kind: "tile", tile: { x: start.x + 4, y: start.y } }); // stops: a reveal
    expect(session.state.stopped).toBe("a chunk was revealed");
    host.run(STEP_MS + FADE_MS + 1000);
    expect(session.stepScheduled()).toBe(false);
    const after = cadence();
    // The same idle frames as before the walk (12 a second here), and the same wake-ups.
    expect(after.renders).toBe(before.renders);
    expect(after.wakeups).toBe(before.wakeups);
    expect(after.renders / 10).toBeLessThanOrEqual(15);
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
