import type { Container, Rectangle, Sprite, Texture } from "pixi.js";
import { describe, expect, it } from "vitest";
import { fixtureNamed } from "../sandbox/fixtures";
import { initialState, toView } from "../sandbox/wiring";
import { allExplored } from "../test/explored";
import { FakeHost } from "../test/fakeHost";
import { FakeSurface } from "../test/fakeSurface";
import { Renderer } from "./renderer";

/** A surface that keeps every texture it baked, to see which were destroyed. */
class CountingSurface extends FakeSurface {
  readonly baked: Texture[] = [];

  override bake(target: Container, frame: Rectangle, resolution: number, grey = false): Texture {
    const texture = super.bake(target, frame, resolution, grey);
    this.baked.push(texture);
    return texture;
  }
}

/** The textures the renderer still draws: its chunks' bakes and twins, its grey stills. */
function held(renderer: Renderer): Set<Texture> {
  const chunks = renderer["chunks"] as Map<string, { sprite: Sprite; grey: Sprite }>;
  const greys = renderer["greyTextures"] as Map<Texture, Texture>;
  const textures = new Set<Texture>(greys.values());
  for (const { sprite, grey } of chunks.values()) {
    for (const t of [sprite.texture, grey.texture]) if (t.source.width > 1) textures.add(t);
  }
  return textures;
}

describe("the bakes' textures, given back (CLI-03n follow-up, review t-0120's minor 2)", () => {
  it("every texture baked is held or destroyed, across a reveal, a zoom step and destroy()", () => {
    const host = new FakeHost(1000 / 120);
    const surface = new CountingSurface();
    const renderer = new Renderer(surface, host, { idle: false, water: "still" });
    renderer.resize({ width: 375, height: 812 });
    const balanced = (label: string) => {
      const live = surface.baked.filter((t) => !t.destroyed);
      const kept = held(renderer);
      expect(new Set(live), label).toEqual(kept);
    };
    const start = initialState(fixtureNamed("zone"));
    renderer.setView(toView(start));
    host.run(100);
    const first = surface.baked.length;
    expect(first).toBeGreaterThan(0);
    balanced("opened");
    // A reveal: every tile seen at once; the chunks whose coast was hidden are baked again.
    renderer.setView(toView(allExplored(start)));
    host.run(100);
    expect(surface.baked.length).toBeGreaterThan(first);
    balanced("revealed");
    // A zoom step: a new bake resolution, every chunk again.
    const before = surface.baked.length;
    renderer.zoomAt(2, { x: 187, y: 406 });
    host.run(100);
    expect(surface.baked.length).toBeGreaterThan(before);
    balanced("zoomed");
    renderer.destroy();
    expect(surface.baked.filter((t) => !t.destroyed)).toEqual([]);
  });
});
