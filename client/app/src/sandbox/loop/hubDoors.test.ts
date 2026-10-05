import { BufferImageSource, type Container, Graphics, Sprite, Spritesheet, Texture } from "pixi.js";
import { describe, expect, it } from "vitest";
import { tileToPixel } from "../../input/coords";
import type { LoopIntent } from "../../input/intent";
import type { HubView } from "../../render/hubView";
import { Renderer, STEP_MS, STILL } from "../../render/renderer";
import { drawTerrain } from "../../render/shapes";
import { type SpriteLibrary, type SpritesIndex, libraryFrom } from "../../render/sprites";
import type { Tile } from "../../render/view";
import { FakeHost } from "../../test/fakeHost";
import { FakeSurface } from "../../test/fakeSurface";
import { FIXTURES } from "../fixtures";
import { BUILDINGS, HUB_VIEWS } from "../fixtures/hubs";
import { HUB_ADVENTURER_ID, hubTap, hubWorld } from "../fixtures/hubWorld";
import { OUTPOST, TOWN } from "../fixtures/region";
import { findPath } from "../placeholders";
import { SandboxSession } from "../session";
import { applyIntent, initialState, toView } from "../wiring";
import { kindAt } from "../world";
import { HubDoors } from "./hubDoors";

const key = (t: Tile) => `${t.x},${t.y}`;

/**
 * A synthetic atlas (no art): one plain still per building and prop the hubs name, at the
 * buildings' native sizes, anchored at the middle of the base.
 */
async function stills(): Promise<SpriteLibrary> {
  const cells: [string, number, number][] = Object.entries(BUILDINGS).map(([n, [w, h]]) => [
    n,
    w,
    h,
  ]);
  for (const view of HUB_VIEWS.values()) {
    for (const p of view.props)
      if (!cells.some(([n]) => n === p.sprite)) cells.push([p.sprite, 40, 60]);
  }
  const frames: Record<string, unknown> = {};
  const animations: Record<string, string[]> = {};
  const sprites: Record<string, SpritesIndex["sprites"][string]> = {};
  let x = 0;
  let height = 1;
  for (const [name, w, h] of cells) {
    const frame = `${name}/${STILL}/00`;
    frames[frame] = {
      frame: { x, y: 0, w, h },
      rotated: false,
      trimmed: false,
      spriteSourceSize: { x: 0, y: 0, w, h },
      sourceSize: { w, h },
      anchor: { x: 0.5, y: 1 },
    };
    animations[`${name}/${STILL}`] = [frame];
    sprites[name] = {
      role: "building",
      page: 0,
      cell: { w, h },
      baseline: h,
      animations: { [STILL]: { frames: 1, fps: 1, loop: false } },
    };
    x += w;
    height = Math.max(height, h);
  }
  const json = {
    frames,
    animations,
    meta: { image: "atlas-0.png", format: "RGBA8888", size: { w: x, h: height }, scale: "1" },
  };
  const source = new BufferImageSource({
    resource: new Uint8Array(x * height * 4).fill(200),
    width: x,
    height,
  });
  const sheet = new Spritesheet(new Texture({ source }), json as never);
  await sheet.parse();
  const index: SpritesIndex = { pages: [{ json: "atlas-0.json", image: "atlas-0.png" }], sprites };
  return libraryFrom(index, [sheet]);
}

/** A hub on the zone's session and renderer, with the hub screen's doors, on fake timers. */
function setup(hub = TOWN, options: { at?: Tile; library?: SpriteLibrary } = {}) {
  const view: HubView = HUB_VIEWS.get(hub)!;
  const host = new FakeHost(1000 / 120);
  const surface = new FakeSurface();
  const renderer = new Renderer(surface, host, { idle: false, library: options.library ?? null });
  renderer.resize({ width: 375, height: 812 });
  const dispatched: LoopIntent[] = [];
  const logs: string[] = [];
  const doorsRef: { current: HubDoors | null } = { current: null };
  const session: SandboxSession = new SandboxSession(
    hubWorld(view, options.at ?? view.arrival),
    renderer,
    host,
    {
      playOnTap: true,
      stepMs: STEP_MS,
      onChange: () => doorsRef.current?.changed(adventurer().tile, session.walk()),
    },
  );
  const adventurer = () => session.state.world.actors.find((a) => a.id === HUB_ADVENTURER_ID)!;
  const doors = new HubDoors(
    view,
    (intent) => dispatched.push(intent),
    () => adventurer().tile,
    host,
    STEP_MS,
    (line) => logs.push(line),
  );
  doorsRef.current = doors;
  const tap = (tile: Tile, kind: "tile" | "inspect" = "tile") => {
    renderer.scheduler.input();
    const routed = doors.route({ kind, tile });
    if (routed) session.apply(routed);
  };
  const actorsLayer = () => (surface.stage.children[0] as Container).children[6] as Container;
  return {
    view,
    host,
    surface,
    renderer,
    session,
    doors,
    dispatched,
    logs,
    adventurer,
    tap,
    actorsLayer,
  };
}

const place = (view: HubView, id: string) => view.places.find((p) => p.id === id)!;

describe("a hub on the zone's engine (CLI-03f, AC-1)", () => {
  it("the hub's world goes through SandboxSession and the zone's Renderer", () => {
    const { host, surface, session, view, actorsLayer } = setup();
    host.run(100);
    expect(session.state.world.kind).toBe("hub");
    expect(surface.renders).toBeGreaterThanOrEqual(1);
    // The town is 1 × 2 chunks of the zone's terrain: one bake each.
    expect(surface.bakes).toHaveLength(2);
    const structures = view.places.length + view.decor.length + view.props.length;
    expect(actorsLayer().children).toHaveLength(1 + view.figures.length + structures);
    expect(host.quiet()).toBe(true);
  });
});

describe("the stand-ins a hub does not inherit (CLI-03f, AC-3)", () => {
  for (const hub of [TOWN, OUTPOST]) {
    const view = HUB_VIEWS.get(hub)!;
    const world = hubWorld(view, view.arrival);

    it(`${view.name}: every tile is in sight and every figure seen, however far`, () => {
      const v = toView(initialState(world));
      expect(v.sight).toHaveLength(v.tiles.length);
      expect(v.actors).toHaveLength(1 + view.figures.length);
      expect(v.structures).toHaveLength(view.places.length + view.decor.length + view.props.length);
    });

    it(`${view.name}: a tap on a figure, past the route, selects nothing and shows no arcs`, () => {
      for (const figure of view.figures) {
        const s = applyIntent(initialState(world), { kind: "tile", tile: figure.at });
        expect(s.selectedActorId).toBeNull();
        expect(toView(s).arcs).toBeNull();
        expect(s.path).toEqual([]);
      }
    });
  }

  it("a walk across the town fires no stop", () => {
    const { host, session, adventurer, view, tap } = setup();
    const far = place(view, "guild").at;
    tap(far);
    host.run(14 * STEP_MS + 1000);
    expect(adventurer().tile).toEqual(far);
    expect(session.walk()).toEqual({ steps: 0, cost: 0, walking: false, stopped: "" });
  });

  it("a tap on a figure inspects it, through the hub screen; a long press likewise", () => {
    const { dispatched, session, view, tap } = setup();
    const figure = view.figures[0]!;
    tap(figure.at);
    tap(figure.at, "inspect");
    expect(dispatched).toEqual([
      { kind: "inspect adventurer", adventurer: figure.id },
      { kind: "inspect adventurer", adventurer: figure.id },
    ]);
    expect(session.state.selectedActorId).toBeNull();
  });
});

describe("the window stays a zone's (CLI-03f §4, the project manager's condition)", () => {
  it("every zone fixture's tap path is the bounded finder's, tile for tile", () => {
    let compared = 0;
    for (const world of Object.values(FIXTURES)) {
      expect(world.kind ?? "zone").toBe("zone");
      const state = initialState(world);
      const { terrain, actors } = state.world;
      const me = actors.find((a) => a.id === world.adventurerId)!;
      for (let y = 0; y < terrain.height; y++) {
        for (let x = 0; x < terrain.width; x++) {
          const tile = { x, y };
          if (kindAt(terrain, tile) !== "floor") continue;
          const planned = applyIntent(state, { kind: "tile", tile }, { playOnTap: false }).path;
          const bounded = findPath(terrain, actors, me.tile, tile) ?? [];
          expect(planned, `${world.name} ${key(tile)}`).toEqual(bounded);
          compared += 1;
        }
      }
    }
    expect(compared).toBeGreaterThan(100);
  });

  it("the same town as a zone keeps the window: the Guild's door is out of reach", () => {
    const view = HUB_VIEWS.get(TOWN)!;
    const guild = place(view, "guild").at;
    const asZone = { ...hubWorld(view, view.arrival), kind: "zone" as const };
    const asHub = hubWorld(view, view.arrival);
    expect(applyIntent(initialState(asZone), { kind: "tile", tile: guild }).path).toEqual([]);
    expect(applyIntent(initialState(asHub), { kind: "tile", tile: guild }).path).toHaveLength(14);
  });
});

describe("taps and doors (CLI-03f, AC-5)", () => {
  it("a tap on a floor hex walks there, one step per STEP_MS, facing each step, the camera following", () => {
    const { host, renderer, adventurer, tap, dispatched } = setup();
    const target = { x: 6, y: 3 };
    tap(target);
    const tiles = [adventurer().tile];
    for (
      let i = 0;
      (i < 20 && adventurer().tile.x !== target.x) || adventurer().tile.y !== target.y;
      i++
    ) {
      host.run(STEP_MS);
      tiles.push(adventurer().tile);
    }
    expect(adventurer().tile).toEqual(target);
    expect(tiles.length).toBeGreaterThan(2);
    host.run(1000);
    expect(renderer.cameraState().camera.centre).toEqual(tileToPixel(target));
    expect(dispatched).toEqual([]);
    expect(host.quiet()).toBe(true);
  });

  for (const [hub, id] of [
    [TOWN, "smith"],
    [OUTPOST, "trainer"],
    [TOWN, "gate"],
  ] as const) {
    it(`${HUB_VIEWS.get(hub)!.name}: a tap on the ${id}'s building walks to its door, then opens it once`, () => {
      const { host, adventurer, tap, view, dispatched } = setup(hub);
      const p = place(view, id);
      // Tap the building's top hex, not its door.
      tap({ x: p.at.x, y: p.at.y + 1 });
      // Not on the tap: once the last step is drawn, at the earliest one step later.
      expect(dispatched).toEqual([]);
      host.run(30 * STEP_MS);
      expect(adventurer().tile).toEqual(p.at);
      expect(dispatched).toEqual([
        p.target.kind === "gate"
          ? { kind: "open gate screen" }
          : { kind: "open service", service: p.target.service },
      ]);
      host.run(5000);
      expect(dispatched).toHaveLength(1);
    });
  }

  it("standing on the door, a tap on the building opens at once", () => {
    const view = HUB_VIEWS.get(TOWN)!;
    const smith = place(view, "smith");
    const { tap, dispatched, session } = setup(TOWN, { at: smith.at });
    tap(smith.at);
    expect(dispatched).toEqual([{ kind: "open service", service: "smith" }]);
    expect(session.walk().steps).toBe(0);
  });

  it("a walk passing over a door opens nothing", () => {
    const view = HUB_VIEWS.get(TOWN)!;
    const world = hubWorld(view, view.arrival);
    const doors = new Set(view.places.map((p) => key(p.at)));
    let target: Tile | null = null;
    for (let y = 0; y < world.terrain.height && !target; y++) {
      for (let x = 0; x < world.terrain.width && !target; x++) {
        const t = { x, y };
        if (kindAt(world.terrain, t) !== "floor" || hubTap(view, t).kind !== "ground") continue;
        const path = findPath(world.terrain, world.actors, view.arrival, t, false);
        if (path?.slice(0, -1).some((s) => doors.has(key(s)))) target = t;
      }
    }
    expect(target).not.toBeNull();
    const { host, tap, adventurer, dispatched } = setup();
    tap(target!);
    host.run(40 * STEP_MS);
    expect(adventurer().tile).toEqual(target);
    expect(dispatched).toEqual([]);
  });

  it("a tap on a decor building or a prop does nothing but a log line", () => {
    const { host, tap, view, dispatched, logs, session } = setup();
    tap(view.decor[0]!.at);
    tap(view.props[0]!.at);
    host.run(2000);
    expect(dispatched).toEqual([]);
    expect(session.walk().steps).toBe(0);
    expect(logs).toEqual([
      `decor ${view.decor[0]!.id}: no target`,
      `prop ${view.props[0]!.id}: no target`,
    ]);
  });

  it("a new tap retargets: the place first walked to does not open", () => {
    const { host, tap, view, dispatched, adventurer } = setup();
    tap(place(view, "guild").at);
    host.run(3 * STEP_MS);
    tap({ x: 6, y: 3 });
    host.run(40 * STEP_MS);
    expect(adventurer().tile).toEqual({ x: 6, y: 3 });
    expect(dispatched).toEqual([]);
  });

  it("the walk pauses while hidden and resumes after, then opens the place", () => {
    const { host, tap, view, dispatched, adventurer } = setup();
    const smith = place(view, "smith");
    tap(smith.at);
    host.run(2 * STEP_MS);
    const paused = adventurer().tile;
    host.setHidden(true);
    host.run(10_000);
    expect(adventurer().tile).toEqual(paused);
    expect(dispatched).toEqual([]);
    host.setHidden(false);
    host.run(40 * STEP_MS);
    expect(adventurer().tile).toEqual(smith.at);
    expect(dispatched).toEqual([{ kind: "open service", service: "smith" }]);
  });
});

describe("the Gate and arriving (CLI-03f, AC-7)", () => {
  it("arriving opens nothing and starts no walk", () => {
    const { host, dispatched, session } = setup();
    host.run(5000);
    expect(dispatched).toEqual([]);
    expect(session.walk().steps).toBe(0);
  });

  it("back from the Gate screen, on its door, nothing reopens", () => {
    const view = HUB_VIEWS.get(TOWN)!;
    const gate = place(view, "gate");
    const { host, dispatched, adventurer } = setup(TOWN, { at: gate.at });
    host.run(5000);
    expect(adventurer().tile).toEqual(gate.at);
    expect(dispatched).toEqual([]);
  });
});

describe("structures drawn by the zone's renderer (CLI-03f, AC-6)", () => {
  it("from the atlas's stills at native size, the base on its hex's centre", async () => {
    const library = await stills();
    const { host, view, actorsLayer } = setup(TOWN, { library });
    host.run(100);
    const sprites = actorsLayer()
      .children.filter((c) => c.children[0] instanceof Sprite && c.children.length === 1)
      .map((c) => ({ c, s: c.children[0] as Sprite }));
    expect(sprites).toHaveLength(view.places.length + view.decor.length + view.props.length);
    const castle = place(view, "guild");
    const base = tileToPixel(castle.at);
    const drawn = sprites.find(({ c }) => c.position.x === base.x && c.position.y === base.y)!;
    expect([drawn.s.texture.width, drawn.s.texture.height]).toEqual(BUILDINGS.castle);
    expect(drawn.s.scale.x).toBe(1);
  });

  it("as shapes without the atlas", () => {
    const { host, view, actorsLayer } = setup();
    host.run(100);
    const shapes = actorsLayer().children.filter(
      (c) => c.children.length === 1 && c.children[0] instanceof Graphics,
    );
    expect(shapes).toHaveLength(view.places.length + view.decor.length + view.props.length);
  });

  it("sort with the actors by the y of their base: a figure behind a building is under it", () => {
    const view = HUB_VIEWS.get(TOWN)!;
    const smith = place(view, "smith");
    // Two rows behind the forge's door, on the way up to the castle: floor, behind the forge.
    const behind = { x: 4, y: 9 };
    expect(kindAt(hubWorld(view, behind).terrain, behind)).toBe("floor");
    const { host, actorsLayer } = setup(TOWN, { at: behind });
    host.run(100);
    const layer = actorsLayer();
    const at = (tile: Tile) =>
      layer.children.find(
        (c) => c.position.x === tileToPixel(tile).x && c.position.y === tileToPixel(tile).y,
      )!;
    expect(at(behind).zIndex).toBeLessThan(at(smith.at).zIndex);
    // Ilse (8, 11) stands in front of the castle's door row (12): she covers it.
    const ilse = view.figures.find((f) => f.name === "Ilse")!;
    expect(at(ilse.at).zIndex).toBeGreaterThan(at(place(view, "guild").at).zIndex);
    // On a building's own row, an actor stands in front of it (its feet are below the centre).
    const onRow = setup(TOWN, { at: smith.at });
    onRow.host.run(100);
    const row = onRow
      .actorsLayer()
      .children.filter(
        (c) => c.position.x === tileToPixel(smith.at).x && c.position.y === tileToPixel(smith.at).y,
      );
    expect(row).toHaveLength(2);
    const [building, actor] = [...row].sort((a, b) => a.zIndex - b.zIndex);
    expect(building!.children[0]).toBeInstanceOf(Graphics);
    expect(actor!.children.length).toBeGreaterThan(1); // the wedge and the body
  });

  it("a wall under a structure draws no rock; a zone's terrain draws as before", () => {
    const wall = [{ x: 3, y: 3, kind: "wall" as const }];
    const plain = drawTerrain(wall).context.instructions.length;
    const covered = drawTerrain(wall, new Set(["3,3"])).context.instructions.length;
    expect(covered).toBeLessThan(plain);
    expect(drawTerrain(wall, new Set(["4,4"])).context.instructions.length).toBe(plain);
  });

  it("drawing stays on demand: no frame once a walk ends, no ticker left", () => {
    const { host, surface, tap } = setup();
    host.run(100);
    tap({ x: 6, y: 3 });
    host.run(5000);
    const renders = surface.renders;
    host.run(5000);
    expect(surface.renders).toBe(renders);
    expect(host.quiet()).toBe(true);
  });
});
