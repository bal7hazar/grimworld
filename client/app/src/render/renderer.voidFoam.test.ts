import { Texture } from "pixi.js";
import { describe, expect, it, vi } from "vitest";
import { fixtureNamed } from "../sandbox/fixtures";
import { initialState, toView } from "../sandbox/wiring";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import * as ground from "./ground";
import { Renderer } from "./renderer";
import type { SpriteArt, SpriteLibrary } from "./sprites";
import type { ViewState } from "./view";

vi.mock("./ground", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./ground")>();
  return { ...actual, voidFoam: vi.fn(actual.voidFoam) };
});

/** The ground's cells (`grass_c`, `water_c`, `foam_c`) on a plain texture: the foam is planned. */
function groundLibrary(): SpriteLibrary {
  const cell = (name: string, side: number): SpriteArt => ({
    name,
    role: "tile",
    cell: { w: side, h: side },
    baseline: 0,
    scale: 1,
    animations: { still: { textures: [Texture.WHITE], fps: 1, loop: false } },
  });
  return new Map([
    ["grass_c", cell("grass_c", 64)],
    ["water_c", cell("water_c", 64)],
    ["foam_c", cell("foam_c", 192)],
  ]);
}

describe("the foam over the void, planned again only when the terrain changes (CLI-03h)", () => {
  it("not for a step, the same view or a new selection; once for a changed tile or void", () => {
    const voidFoam = vi.mocked(ground.voidFoam);
    const host = new FakeHost(1000 / 120);
    const renderer = new Renderer(new FakeSurface(), host, {
      idle: false,
      library: groundLibrary(),
    });
    renderer.resize({ width: 375, height: 812 });
    const view = toView(initialState(fixtureNamed("zone")));
    voidFoam.mockClear();
    renderer.setView(view);
    host.run(100);
    expect(voidFoam).toHaveBeenCalledTimes(1);
    // The same terrain: an actor's step, a selection, the same view again.
    const adventurer = view.actors.find((a) => a.id === view.adventurerId)!;
    const stepped: ViewState = {
      ...view,
      actors: view.actors.map((a) =>
        a === adventurer ? { ...a, tile: { x: a.tile.x + 1, y: a.tile.y } } : a,
      ),
      selectedTile: adventurer.tile,
    };
    renderer.setView(stepped);
    renderer.setView({ ...stepped, tiles: [...stepped.tiles] });
    host.run(1000);
    expect(voidFoam).toHaveBeenCalledTimes(1);
    // A tile's ground changes: planned again, once.
    const tiles = view.tiles.map((t, i) => (i === 0 ? { ...t, ground: "earth" as const } : t));
    renderer.setView({ ...stepped, tiles });
    expect(voidFoam).toHaveBeenCalledTimes(2);
    // The void changes: once more; the atlas changes: once more.
    renderer.setView({ ...stepped, tiles, void: "grass" });
    expect(voidFoam).toHaveBeenCalledTimes(3);
    renderer.setLibrary(groundLibrary());
    expect(voidFoam).toHaveBeenCalledTimes(4);
  });
});
