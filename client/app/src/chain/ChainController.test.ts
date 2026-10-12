import { describe, expect, it } from "vitest";
import type { PlayAction } from "../preview/actions";
import type { MirrorState } from "../preview/mirror";
import type { MirrorResult } from "../preview/reconcile";
import { recordedBefore } from "../preview/recorded-goblins";
import { decodeInstanceView } from "../preview/view";
import type { Tile } from "../render/view";
import { planPath, tileToward } from "../sandbox/wiring";
import { kindAt } from "../sandbox/world";
import type { Batch } from "./batch";
import { createChainController, notes } from "./ChainController";
import type { ChainState } from "./send";
import type { Phase, Stages, StagesState } from "./stages";

/** The state recorded on starknet-devnet: the adventurer on (0, 7) facing East, a goblin on (12, 1). */
function recordedChain(): ChainState {
  const mirror: MirrorState = {
    view: decodeInstanceView(recordedBefore.view.map(BigInt)),
    member: recordedBefore.member,
    region: recordedBefore.region.map((c) => ({
      chunk: c.chunk,
      kind: c.kind as 0 | 1 | 2,
      terrain: BigInt(c.terrain),
      features: BigInt(c.features),
      goblins: [],
    })),
  };
  return {
    target: { instances: "0x1", instanceId: 1n, adventurerId: 1, sequence: 0, version: 1 },
    mirror,
  };
}

/** A fake `Stages`: what the controller puts in is what it records; it holds the room the rule gives. */
function fakeStages(initial: ChainState = recordedChain()) {
  let planned: Batch = [];
  const state = (): StagesState => ({
    phase,
    chain: initial,
    planned,
    mirror,
    simulation: undefined,
    sent: undefined,
    line,
  });
  let line: string | undefined;
  const listeners = new Set<(state: StagesState) => void>();
  let phase: Phase = "ready";
  let mirror: MirrorResult | undefined;
  const sent: number[] = [];
  const installed: ChainState[] = [];
  const stages: Stages = {
    get: state,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    input(actions, options) {
      if (phase !== "ready" || actions.length === 0 || planned.length >= 10) return false;
      planned = [
        ...planned,
        ...actions.slice(0, 10 - planned.length).map((action) => ({
          action,
          path: options?.path ?? false,
        })),
      ];
      return true;
    },
    send() {
      sent.push(planned.length);
      return phase === "ready" && planned.length > 0;
    },
    install(chain) {
      installed.push(chain);
      initial = chain;
      planned = [];
      phase = "ready";
      return true;
    },
  };
  return {
    stages,
    sent,
    installed,
    actions: (): PlayAction[] => planned.map((p) => p.action),
    paths: (): boolean[] => planned.map((p) => p.path),
    setPhase: (next: Phase) => {
      phase = next;
    },
    /** The stages' line changes, as it does when a send ends. */
    setLine: (next: string | undefined) => {
      line = next;
      for (const listener of listeners) listener(state());
    },
    setMirror: (next: MirrorResult | undefined) => {
      mirror = next;
    },
  };
}

/** A fake over a chain state whose view holds a goblin on the tile of `world`'s goblin. */
function fakeWith(world: { actors: readonly { side: string; id: number; tile: Tile }[] }): Stages {
  const chain = recordedChain();
  const goblin = world.actors.find((a) => a.side === "goblin")!;
  const view = chain.mirror.view;
  const kept = view.goblins[0]!;
  const state = (kept.state & ~0xffffn) | (BigInt(goblin.tile.y) << 8n) | BigInt(goblin.tile.x);
  const moved = {
    ...chain,
    mirror: {
      ...chain.mirror,
      view: { ...view, goblins: [{ ...kept, entity: goblin.id, state }] },
    },
  };
  return fakeStages(moved).stages;
}

function setup(enter: () => Promise<ChainState> = async () => recordedChain()) {
  const fake = fakeStages();
  const controller = createChainController({ stages: fake.stages, enter });
  return { fake, controller };
}

describe("a step key and a tap on a neighbour (§4.1)", () => {
  it("a step key is one move in its direction; R then a step key is a turn", () => {
    const { fake, controller } = setup();
    expect(controller.step(3)).toBe(true);
    controller.armTurn();
    expect(controller.get().turning).toBe(true);
    expect(controller.step(1)).toBe(true);
    // Armed for one key only
    expect(controller.get().turning).toBe(false);
    controller.step(5);
    expect(fake.actions()).toEqual([
      { kind: "move", direction: 3 },
      { kind: "turn", direction: 1 },
      { kind: "move", direction: 5 },
    ]);
    expect(fake.paths()).toEqual([false, false, false]);
  });

  it("R twice cancels the turn, and Esc disarms it", () => {
    const { controller } = setup();
    controller.armTurn();
    controller.armTurn();
    expect(controller.get().turning).toBe(false);
    controller.armTurn();
    expect(controller.disarm()).toBe(true);
    expect(controller.disarm()).toBe(false);
  });

  it("Space is a wait", () => {
    const { fake, controller } = setup();
    controller.armTurn();
    expect(controller.wait()).toBe(true);
    expect(fake.actions()).toEqual([{ kind: "wait" }]);
    expect(controller.get().turning).toBe(false);
  });

  it("a tap on the floor tile next to the adventurer is one move that way, not a path step", () => {
    const { fake, controller } = setup();
    const world = controller.world();
    const here = { x: 0, y: 7 };
    const open = ([0, 1, 2, 3, 4, 5] as const).find(
      (d) => kindAt(world.terrain, tileToward(here, d)) === "floor",
    );
    expect(open).toBeDefined();
    expect(controller.tap(tileToward(here, open!))).toEqual({ kind: "moves", count: 1 });
    expect(fake.actions()).toEqual([{ kind: "move", direction: open }]);
    expect(fake.paths()).toEqual([false]);
  });
});

describe("a tap on a floor tile far away (§4.1)", () => {
  /** A floor tile the wiring finds a path of 3 steps or more to. */
  function farTile(controller: ReturnType<typeof setup>["controller"]): {
    tile: Tile;
    steps: number;
  } {
    const world = controller.world();
    for (let x = 0; x < 15; x++) {
      for (let y = 0; y < 15; y++) {
        const tile = { x, y };
        if (kindAt(world.terrain, tile) !== "floor") continue;
        if (world.actors.some((a) => a.tile.x === x && a.tile.y === y)) continue;
        const path = planPath(world, { x: 0, y: 7 }, tile);
        if (path !== null && path.length >= 3) return { tile, steps: path.length };
      }
    }
    throw new Error("no far floor tile in the recorded chunk");
  }

  it("is one move per step of the wiring's path, marked as a path, and ends on the tile", () => {
    const { fake, controller } = setup();
    const { tile, steps } = farTile(controller);
    expect(controller.tap(tile)).toEqual({ kind: "moves", count: steps });
    const moves = fake.actions();
    expect(moves).toHaveLength(steps);
    expect(moves.every((a) => a.kind === "move")).toBe(true);
    expect(fake.paths().every(Boolean)).toBe(true);
    let at: Tile = { x: 0, y: 7 };
    for (const move of moves) at = tileToward(at, (move as { direction: 0 }).direction);
    expect(at).toEqual(tile);
    // The planner follows the batch's own moves: the ghost's steps are the path's tiles
    expect(controller.ghosts().steps.at(-1)).toEqual(tile);
    expect(controller.tiles()).toEqual({ chain: { x: 0, y: 7 }, planned: tile });
  });

  it("plans the next path from where the batch's moves end", () => {
    const { fake, controller } = setup();
    const world = controller.world();
    const start = { x: 0, y: 7 };
    const first = ([0, 1, 2, 3, 4, 5] as const).find(
      (d) => kindAt(world.terrain, tileToward(start, d)) === "floor",
    )!;
    controller.step(first);
    const after = tileToward(start, first);
    expect(controller.tiles().planned).toEqual(after);
    // A floor tile two steps on from there, by the wiring's own path
    const target = ([0, 1, 2, 3, 4, 5] as const)
      .map((d) => tileToward(tileToward(after, d), d))
      .find(
        (t) =>
          kindAt(world.terrain, t) === "floor" &&
          planPath(world, after, t)?.length === 2 &&
          planPath(world, start, t)?.length !== 2,
      );
    expect(target).toBeDefined();
    controller.tap(target!);
    // The step key's move, then the two steps from where it ends (not from the chain's tile)
    expect(fake.actions()).toHaveLength(3);
    expect(controller.tiles().planned).toEqual(target);
  });

  it("is cut to the batch's room, and does nothing when the batch is full", () => {
    const { fake, controller } = setup();
    for (let i = 0; i < 9; i++) controller.wait();
    const { tile } = farTile(controller);
    expect(controller.tap(tile)).toEqual({ kind: "moves", count: expect.any(Number) });
    expect(fake.actions()).toHaveLength(10);
    expect(controller.tap(tile)).toEqual({ kind: "none" });
    expect(fake.actions()).toHaveLength(10);
    expect(controller.step(0)).toBe(false);
  });

  it("does nothing on a wall, outside the map, the adventurer's own tile or an unreachable one", () => {
    const { fake, controller } = setup();
    const world = controller.world();
    const wall = world.terrain.kinds.findIndex((k, i) => k === "wall" && i < 45 * 15);
    expect(controller.tap({ x: wall % 45, y: Math.floor(wall / 45) })).toEqual({ kind: "none" });
    expect(controller.tap({ x: -3, y: 4 })).toEqual({ kind: "none" });
    expect(controller.tap({ x: 0, y: 7 })).toEqual({ kind: "none" });
    expect(controller.tap({ x: 40, y: 40 })).toEqual({ kind: "none" });
    expect(fake.actions()).toEqual([]);
  });

  it("is refused while no input is taken, and says so", () => {
    const { fake, controller } = setup();
    fake.setPhase("sending");
    expect(controller.step(0)).toBe(false);
    expect(controller.get().note).toBe(notes.NOT_TAKEN);
    expect(controller.wait()).toBe(false);
    expect(fake.actions()).toEqual([]);
  });
});

describe("a goblin (§4.1)", () => {
  const goblin = { x: 12, y: 1 };

  it("the first tap selects it and is let through to the map, the second attacks its entity", () => {
    const { fake, controller } = setup();
    expect(controller.tap(goblin)).toEqual({ kind: "select", entity: 8 });
    expect(controller.get().selected).toBe(8);
    expect(fake.actions()).toEqual([]);
    expect(controller.tap(goblin)).toEqual({ kind: "attack", entity: 8 });
    expect(fake.actions()).toEqual([{ kind: "attack", entity: 8 }]);
    expect(controller.get().selected).toBeNull();
  });

  it("a new chain state drops the selection with the map it was on", () => {
    const { controller } = setup();
    controller.tap(goblin);
    controller.reset();
    expect(controller.get().selected).toBeNull();
    expect(controller.tap(goblin)).toEqual({ kind: "select", entity: 8 });
  });
});

describe("B and N (§4.3, §3.4)", () => {
  it("B sends the batch through the stages", () => {
    const { fake, controller } = setup();
    controller.wait();
    expect(controller.send()).toBe(true);
    expect(fake.sent).toEqual([1]);
  });

  it("N enters again only once the instance closed, then installs the state read", async () => {
    const fresh = recordedChain();
    const { fake, controller } = setup(async () => fresh);
    expect(await controller.enterAgain()).toBe(false);
    expect(controller.get().note).toBe(notes.NOT_CLOSED);
    expect(fake.installed).toEqual([]);
    fake.setPhase("closed");
    expect(await controller.enterAgain()).toBe(true);
    expect(fake.installed).toEqual([fresh]);
    expect(controller.get()).toMatchObject({ entering: false, note: undefined });
  });

  it("N runs once at a time, and a failure is a line, not a throw", async () => {
    let release: (chain: ChainState) => void = () => undefined;
    const { fake, controller } = setup(
      () => new Promise<ChainState>((resolve) => (release = resolve)),
    );
    fake.setPhase("closed");
    const first = controller.enterAgain();
    expect(controller.get().entering).toBe(true);
    expect(await controller.enterAgain()).toBe(false);
    release(recordedChain());
    expect(await first).toBe(true);

    const failing = setup(async () => {
      throw new Error("enter 0x1 failed");
    });
    failing.fake.setPhase("closed");
    expect(await failing.controller.enterAgain()).toBe(false);
    expect(failing.controller.get().note).toBe("enter failed: enter 0x1 failed");
    expect(failing.fake.installed).toEqual([]);
  });

  it("L and the Fate actions have one line in part 1", () => {
    const { controller } = setup();
    controller.unbound();
    expect(controller.get().note).toBe(notes.UNBOUND);
  });
});

describe("stage 1 on the map (§5)", () => {
  it("the batch's moves are markers, the predicted last tile and facing a ghost", () => {
    const { fake, controller } = setup();
    controller.step(0);
    controller.step(1);
    controller.wait();
    expect(controller.ghosts().steps).toEqual([
      tileToward({ x: 0, y: 7 }, 0),
      tileToward(tileToward({ x: 0, y: 7 }, 0), 1),
    ]);
    // No prediction: the markers only
    expect(controller.ghosts().end).toBeUndefined();
    const chain = fake.stages.get().chain;
    const word = chain.mirror.view.members[0]!.state;
    // The prediction puts the member on (3, 9) facing 2
    const moved = (word & ~(0xffffffn << 32n)) | (3n << 32n) | (9n << 40n) | (2n << 48n);
    fake.setMirror({
      kind: "predicted",
      played: 3,
      stop: 0,
      moved: false,
      words: {
        clock: 5,
        members: [
          { state: moved, timers: 0n, effects: 0n, recharges: 0n, stats: 0n, bar: 0n, kit: 0n },
        ],
        goblins: [],
        killed: [],
        defeated: false,
      },
    });
    expect(controller.ghosts().end).toEqual({ tile: { x: 3, y: 9 }, facing: 2 });
  });
});

describe("the goblin's selection on the map (review t-0239, finding 1)", () => {
  const goblin = { x: 12, y: 1 };

  it("four taps in a row: the map's selection and the controller's stay in step", () => {
    const { fake, controller } = setup();
    // 1: select, the map hears it (its arcs)
    expect(controller.mapTap(goblin)).toEqual({ kind: "tile", tile: goblin });
    expect(controller.get().selected).toBe(8);
    // 2: attack, the map hears it to deselect
    expect(controller.mapTap(goblin)).toEqual({ kind: "tile", tile: goblin });
    expect(controller.get().selected).toBeNull();
    expect(fake.actions()).toEqual([{ kind: "attack", entity: 8 }]);
    // 3: select again, the map selects again; 4: attack again
    expect(controller.mapTap(goblin)).toEqual({ kind: "tile", tile: goblin });
    expect(controller.get().selected).toBe(8);
    expect(controller.mapTap(goblin)).toEqual({ kind: "tile", tile: goblin });
    expect(fake.actions()).toEqual([
      { kind: "attack", entity: 8 },
      { kind: "attack", entity: 8 },
    ]);
  });

  it("a floor tap, a wall tap and a refused attack tell the map nothing", () => {
    const { controller } = setup();
    expect(controller.mapTap({ x: 40, y: 40 })).toBeNull();
    expect(controller.mapTap({ x: 0, y: 7 })).toBeNull();
  });

  it("never lets the map turn the drawn adventurer toward an adjacent goblin", () => {
    const { controller } = setup();
    const world = controller.world();
    // Put a goblin on the tile next to the adventurer, off its facing (East, the chain's)
    const here = { x: 0, y: 7 };
    const side = ([1, 2, 3, 4, 5] as const).find(
      (d) => kindAt(world.terrain, tileToward(here, d)) === "floor",
    )!;
    const next = tileToward(here, side);
    const adjacent = {
      ...world,
      actors: [
        ...world.actors.filter((a) => a.side === "adventurer"),
        {
          id: 9,
          side: "goblin" as const,
          caste: "runt" as const,
          tile: next,
          facing: 0 as const,
          mark: null,
        },
      ],
    };
    const close = createChainController({
      stages: fakeWith(adjacent),
      enter: async () => recordedChain(),
    });
    expect(close.mapTap(next)).toBeNull();
    // The controller still selects it, so the next tap attacks
    expect(close.get().selected).toBe(9);
    expect(close.mapTap(next)).toBeNull();
  });

  it("ignores a goblin tap while no input is taken", () => {
    const { fake, controller } = setup();
    fake.setPhase("sending");
    expect(controller.tap({ x: 12, y: 1 })).toEqual({ kind: "none" });
    expect(controller.get().selected).toBeNull();
  });
});

describe("the arrows' side (note 6)", () => {
  it("follows the last planned move or turn, else the chain's facing", () => {
    const { controller } = setup();
    expect(controller.facing()).toBe(0);
    controller.armTurn();
    controller.step(4);
    expect(controller.facing()).toBe(4);
    controller.step(2);
    expect(controller.facing()).toBe(2);
    controller.wait();
    expect(controller.facing()).toBe(2);
  });
});

describe("the panel's line (review t-0239, findings 2 and 4)", () => {
  it("a guard refusal on N shows the guard's own line", async () => {
    const refusal = Object.assign(new Error("chain mode refused: not a test chain"), {
      name: "ChainRefused",
    });
    const wrapped = Object.assign(new Error("The game cannot be reached right now."), {
      cause: refusal,
    });
    const { fake, controller } = setup(async () => {
      throw wrapped;
    });
    fake.setPhase("closed");
    expect(await controller.enterAgain()).toBe(false);
    expect(controller.get().note).toBe("chain mode refused: not a test chain");
  });

  it("an old note does not hide the stages' line: B clears it, and so does a new line", () => {
    const { fake, controller } = setup();
    controller.wait();
    fake.setPhase("sending");
    controller.wait();
    expect(controller.get().note).toBe(notes.NOT_TAKEN);
    // The send ends unread: the stages' line replaces the note
    fake.setLine("sent, result unreadable");
    expect(controller.get().note).toBeUndefined();
    // And a note from a tap that found no path is gone once B is pressed
    fake.setPhase("ready");
    controller.tap({ x: 40, y: 40 });
    controller.unbound();
    expect(controller.get().note).toBe(notes.UNBOUND);
    controller.send();
    expect(controller.get().note).toBeUndefined();
  });
});
