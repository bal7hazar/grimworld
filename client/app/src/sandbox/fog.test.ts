import { type Container, Graphics, type Sprite, Texture } from "pixi.js";
import { describe, expect, it } from "vitest";
import { explore, tileKey } from "../render/fog";
import { Renderer, STEP_MS, dimmed, greyOf } from "../render/renderer";
import type { Tile } from "../render/view";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { fixtureNamed } from "./fixtures";
import { HUB_VIEWS } from "./fixtures/hubs";
import { hubWorld } from "./fixtures/hubWorld";
import { TOWN } from "./fixtures/region";
import { tilesInSight } from "./placeholders";
import { SandboxSession } from "./session";
import { type SandboxState, applyIntent, initialState, toView, walkStep } from "./wiring";

/** Walks the planned path to its end (or its stop), step by step. */
function walk(state: SandboxState, to: Tile): SandboxState[] {
  let next = applyIntent(state, { kind: "tile", tile: to });
  const states = [next];
  while (next.walking) {
    next = walkStep(next);
    states.push(next);
  }
  return states;
}

const heroOf = (state: SandboxState) =>
  state.world.actors.find((a) => a.id === state.world.adventurerId)!;
const sightOf = (state: SandboxState) => tilesInSight(state.world.terrain, heroOf(state).tile);

describe("the explored set of an instance (CLI-03n, AC-1)", () => {
  it("opens on the tiles in sight", () => {
    const state = initialState(fixtureNamed("meadow"));
    expect([...state.explored].sort()).toEqual(sightOf(state).map(tileKey).sort());
  });

  it("grows with sight on every step, and never forgets", () => {
    const start = initialState(fixtureNamed("meadow"));
    const hero = heroOf(start).tile;
    let before = start.explored;
    for (const state of walk(start, { x: hero.x - 4, y: hero.y }).slice(1)) {
      for (const key of before) expect(state.explored.has(key)).toBe(true);
      for (const tile of sightOf(state)) expect(state.explored.has(tileKey(tile))).toBe(true);
      before = state.explored;
    }
    expect(before.size).toBeGreaterThan(start.explored.size);
  });

  it("starts again with a new instance (the session's new world), and with a reload", () => {
    const host = new FakeHost(1000 / 120);
    const sink = { setView: () => {} };
    const session = new SandboxSession(fixtureNamed("meadow"), sink, host, {
      playOnTap: true,
      stepMs: STEP_MS,
    });
    const opened = session.state.explored;
    const hero = heroOf(session.state).tile;
    session.apply({ kind: "tile", tile: { x: hero.x - 4, y: hero.y } });
    host.run(2000);
    expect(session.state.explored.size).toBeGreaterThan(opened.size);
    session.setWorld(fixtureNamed("meadow"));
    expect([...session.state.explored].sort()).toEqual([...opened].sort());
  });

  it("a hub explores nothing and hides nothing: every tile drawn, no fog", () => {
    const view = HUB_VIEWS.get(TOWN)!;
    const state = initialState(hubWorld(view, view.arrival));
    expect(state.explored.size).toBe(0);
    const drawn = toView(state);
    expect(drawn.fog).toBeUndefined();
    expect(drawn.tiles.filter((t) => t.kind === "unrevealed")).toHaveLength(0);
    expect(drawn.actors).toHaveLength(state.world.actors.length);
  });
});

describe("what the view draws (CLI-03n, AC-1)", () => {
  it("hides every revealed tile never in sight; the explored ones as the chain holds them", () => {
    const state = initialState(fixtureNamed("meadow"));
    const view = toView(state);
    const { terrain } = state.world;
    let hiddenRevealed = 0;
    for (const tile of view.tiles) {
      const chain = terrain.kinds[tile.y * terrain.width + tile.x];
      if (state.explored.has(tileKey(tile))) expect(tile.kind).toBe(chain);
      else {
        expect(tile.kind).toBe("unrevealed");
        if (chain !== "unrevealed") hiddenRevealed += 1;
      }
    }
    // The meadow is revealed whole: most of it is hidden at the start.
    expect(hiddenRevealed).toBeGreaterThan(0);
    expect(view.fog).toEqual({ sightRadius: 6 });
  });

  it("`full` keeps the hidden tiles hidden and drops the grayscale only", () => {
    const state = initialState(fixtureNamed("meadow"));
    const full = toView(state, "full");
    expect(full.fog).toBeUndefined();
    expect(full.tiles).toEqual(toView(state).tiles);
  });

  it("draws a goblin on an explored tile beyond sight, in the state held; it cannot be selected", () => {
    const opened = initialState(fixtureNamed("meadow"));
    const sight = new Set(sightOf(opened).map(tileKey));
    const goblin = opened.world.actors.find(
      (a) => a.side === "goblin" && !sight.has(tileKey(a.tile)),
    )!;
    expect(goblin).toBeDefined();
    expect(toView(opened).actors.some((a) => a.id === goblin.id)).toBe(false);
    // Its tile was seen once (an earlier sight), not now.
    const state = { ...opened, explored: explore(opened.explored, [goblin.tile]) };
    const drawn = toView(state).actors.find((a) => a.id === goblin.id);
    expect(drawn).toEqual(goblin);
    // Targeting is unchanged: a tap on it does not select it.
    const tapped = applyIntent(state, { kind: "tile", tile: goblin.tile });
    expect(tapped.selectedActorId).toBeNull();
    expect(tapped.said).not.toMatch(/select/);
  });

  it("after a walk away, the goblins seen stay drawn beyond sight", () => {
    const start = initialState(fixtureNamed("cave"));
    const { terrain } = start.world;
    const goblins = start.world.actors.filter((a) => a.side === "goblin");
    // The cave's ten goblins are all in sight at the start: the first walk that leaves some out.
    let checked = 0;
    for (let i = terrain.kinds.length - 1; i >= 0 && checked === 0; i--) {
      if (terrain.kinds[i] !== "floor") continue;
      const last = walk(start, { x: i % terrain.width, y: Math.floor(i / terrain.width) }).at(-1)!;
      const sight = new Set(sightOf(last).map(tileKey));
      const beyond = goblins.filter((g) => !sight.has(tileKey(g.tile)));
      if (beyond.length === 0) continue;
      const drawn = new Map(toView(last).actors.map((a) => [a.id, a]));
      // Drawn, in the state the client holds (the sandbox's goblins do not move).
      for (const g of beyond) expect(drawn.get(g.id)).toEqual(g);
      checked = beyond.length;
    }
    expect(checked).toBeGreaterThan(0);
  });
});

describe("the renderer's fog layers (CLI-03n)", () => {
  function mount(state: SandboxState, fog: "sight" | "full" = "sight") {
    const host = new FakeHost(1000 / 120);
    const surface = new FakeSurface();
    const renderer = new Renderer(surface, host, { idle: false });
    renderer.resize({ width: 375, height: 812 });
    renderer.setView(toView(state, fog));
    host.run(100);
    const world = surface.stage.children[0] as Container;
    const [grey, mask, ground] = world.children as [Container, Graphics, Container];
    return { host, surface, renderer, grey, mask, ground };
  }

  it("with fog: the grey twin under the ground, the ground masked to sight; one grey bake a chunk", () => {
    const { host, surface, renderer, grey, mask, ground } = mount(
      initialState(fixtureNamed("meadow")),
    );
    expect(grey.visible).toBe(true);
    expect(mask).toBeInstanceOf(Graphics);
    expect(ground.mask).toBe(mask);
    // The twins wait for the next frame drawn: not in the one that baked the colour.
    expect(surface.greyBakes).toHaveLength(0);
    renderer.scheduler.invalidate();
    host.run(100);
    expect(surface.greyBakes).toHaveLength(surface.bakes.length);
    // The mask holds the sight's hexes (and the void's within the radius: none, the meadow has none).
    expect(mask.context.instructions.length).toBeGreaterThan(0);
  });

  it("without fog (a hub, `full`): no twin, no mask, no grey bake", () => {
    const view = HUB_VIEWS.get(TOWN)!;
    for (const [state, fog] of [
      [initialState(hubWorld(view, view.arrival)), "sight"],
      [initialState(fixtureNamed("meadow")), "full"],
    ] as const) {
      const { surface, grey, ground } = mount(state, fog);
      expect(grey.visible).toBe(false);
      expect(ground.mask ?? null).toBeNull();
      expect(surface.greyBakes).toHaveLength(0);
    }
  });

  it("the mask is drawn again for a step, not for a view whose sight is the same", () => {
    const start = initialState(fixtureNamed("meadow"));
    const { renderer, mask } = mount(start);
    const drawn = () => mask.context.instructions.length;
    const before = mask.context;
    renderer.setView(toView({ ...start, said: "the same sight" }));
    expect(mask.context).toBe(before);
    const hero = heroOf(start).tile;
    const [, stepped] = walk(start, { x: hero.x - 1, y: hero.y });
    renderer.setView(toView(stepped!));
    expect(drawn()).toBeGreaterThan(0);
    expect(renderer["sightKey"]).toContain(tileKey(heroOf(stepped!).tile));
  });

  it("the void beyond the terrain: its grey twin is the void's grey, dimmed; in sight, colour", () => {
    const zone = initialState(fixtureNamed("zone"));
    const { grey, mask } = mount(zone);
    const bands = grey.children[0] as Container;
    expect(bands.visible).toBe(true);
    for (const band of bands.children as Sprite[]) {
      expect(band.texture).toBe(Texture.WHITE);
      expect(band.tint).toBe(dimmed(greyOf(0x3f8f8d)));
    }
    // The zone opens by its edge: the mask reaches past its tiles, onto the void.
    const masked = mask.context.instructions.length;
    expect(masked).toBeGreaterThan(0);
  });

  it("greyOf gives R = G = B, with the bakes' weights", () => {
    for (const colour of [0x3f8f8d, 0x5d7a3e, 0xff0000, 0x00ff00, 0x0000ff]) {
      const g = greyOf(colour);
      expect((g >> 16) & 0xff).toBe(g & 0xff);
      expect((g >> 8) & 0xff).toBe(g & 0xff);
    }
    expect(greyOf(0xff0000)).toBe(0x4d4d4d); // 0.3 × 255 = 76.5 → 77
  });
});
