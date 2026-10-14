import { Illegal, ORIGIN, memberPlace } from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import { readWorld } from "../combat/fromWords";
import type { LogLine } from "../combat/log";
import { actRow, contentOf } from "../combat/vectors.testkit";
import type { PlayAction } from "../preview/actions";
import type { MirrorState } from "../preview/mirror";
import type { MirrorResult } from "../preview/reconcile";
import { recordedBefore } from "../preview/recorded-goblins";
import { decodeInstanceView } from "../preview/view";
import type { Tile } from "../render/view";
import { planPath, tileToward } from "../sandbox/wiring";
import { kindAt } from "../sandbox/world";
import type { Batch } from "./batch";
import { type ControllerDeps, createChainController, notes, slotAction } from "./ChainController";
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
    sent: result,
    line,
  });
  let line: string | undefined;
  const listeners = new Set<(state: StagesState) => void>();
  let phase: Phase = "ready";
  let mirror: MirrorResult | undefined;
  let result: StagesState["sent"];
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
      for (const listener of listeners) listener(state());
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
    /** The batch planned replaced, as a dropped or cut batch does. */
    setPlanned: (next: Batch) => {
      planned = next;
      for (const listener of listeners) listener(state());
    },
    /** A send settled: the stages' `sent` changes, as it does before the batch is dropped. */
    setSent: (next: StagesState["sent"]) => {
      result = next;
      for (const listener of listeners) listener(state());
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

  it("a floor tap and a wall tap tell the map nothing", () => {
    const { controller } = setup();
    expect(controller.mapTap({ x: 40, y: 40 })).toBeNull();
    expect(controller.mapTap({ x: 0, y: 7 })).toBeNull();
  });

  it("a refused attack deselects the goblin on the map, in step with the controller", () => {
    const { fake, controller } = setup();
    // A full batch: the fake's input returns false
    for (let i = 0; i < 10; i++) controller.wait();
    expect(fake.actions()).toHaveLength(10);
    expect(controller.mapTap(goblin)).toEqual({ kind: "tile", tile: goblin });
    expect(controller.get().selected).toBe(8);
    // The second tap is refused: the controller clears, and the map is told to deselect
    expect(controller.mapTap(goblin)).toEqual({ kind: "tile", tile: goblin });
    expect(controller.get().selected).toBeNull();
    expect(fake.actions()).toHaveLength(10);
    // The third tap selects on both
    expect(controller.mapTap(goblin)).toEqual({ kind: "tile", tile: goblin });
    expect(controller.get().selected).toBe(8);
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

// ---- The combat screen on chain (CLI-11d).

const ACT = contentOf("act.jsonl");
/** `act.jsonl` rows as the combat world: the adventurer on (7, 7), eight ready skills (slot 0 a FOE attack). */
const worldOf = (id: number) => {
  const row = actRow(id);
  return readWorld(row.words, ACT, row.ground, row.board);
};

/** A chain controller whose combat world is a vector row's, its mirror's run given. */
function combatSetup(row: number, deps: Partial<ControllerDeps> = {}) {
  const fake = fakeStages();
  const world = worldOf(row);
  const controller = createChainController({
    stages: fake.stages,
    enter: async () => recordedChain(),
    combatWorld: () => world,
    ...deps,
  });
  return { fake, controller, combat: controller.combat };
}

/** A mirror run that stops at the last action it is given, refused for `illegal`. */
const refusing =
  (illegal: number): ControllerDeps["run"] =>
  () =>
  (actions) =>
    ({
      words: { clock: 0, members: [], goblins: [], killed: [], defeated: false },
      done: { played: actions.length - 1, reveal: false, illegal, heavy: false, undo: false },
    }) as ReturnType<ReturnType<NonNullable<ControllerDeps["run"]>>>;

describe("a slot as an action (CLI-05 brief §4.1, §4.4)", () => {
  it("a skill is a skill action on an entity or a tile, a potion an item action on an entity", () => {
    expect(slotAction({ kind: "skill", slot: 2 }, { tile: false, entity: 8 })).toEqual({
      kind: "skill",
      slot: 2,
      target: { tile: false, value: 8 },
    });
    expect(slotAction({ kind: "skill", slot: 3 }, { tile: true, at: { x: 9, y: 4 } })).toEqual({
      kind: "skill",
      slot: 3,
      target: { tile: true, value: 9 + 256 * 4 },
    });
    expect(slotAction({ kind: "item", slot: 1 }, { tile: false, entity: 0 })).toEqual({
      kind: "item",
      slot: 1,
      entity: 0,
    });
    // `Item` carries an entity only
    expect(
      slotAction({ kind: "item", slot: 0 }, { tile: true, at: { x: 1, y: 1 } }),
    ).toBeUndefined();
  });

  it("has no combat view where the state holds no content", () => {
    const fake = fakeStages();
    const controller = createChainController({
      stages: fake.stages,
      enter: async () => recordedChain(),
    });
    expect(controller.combat.snapshot().view).toBeNull();
    controller.combat.slot({ kind: "skill", slot: 0 });
    expect(fake.actions()).toEqual([]);
  });

  it("a key or tap on a self skill arms it, and again plays it on the adventurer", () => {
    const { fake, combat } = combatSetup(48);
    combat.slot({ kind: "skill", slot: 3 });
    expect(combat.snapshot().view?.armed).toEqual({ kind: "skill", slot: 3 });
    expect(fake.actions()).toEqual([]);
    combat.slot({ kind: "skill", slot: 3 });
    expect(fake.actions()).toEqual([{ kind: "skill", slot: 3, target: { tile: false, value: 0 } }]);
    // The view is made again on the batch: nothing is armed
    expect(combat.snapshot().view?.armed).toBeNull();
  });

  it("a FOE skill is armed, then played on the goblin tapped", () => {
    const { fake, combat } = combatSetup(48);
    combat.slot({ kind: "skill", slot: 0 });
    expect(combat.snapshot().view?.aim).toMatchObject({ addressing: "foe", marked: [8] });
    expect(combat.actor(8)).toBe(true);
    expect(fake.actions()).toEqual([{ kind: "skill", slot: 0, target: { tile: false, value: 8 } }]);
  });

  it("F cycles the targets and Enter plays on the one reached", () => {
    const { fake, combat } = combatSetup(48);
    combat.slot({ kind: "skill", slot: 0 });
    expect(combat.cycle(1)).toBe(true);
    expect(combat.go()).toBe(true);
    expect(fake.actions()).toEqual([{ kind: "skill", slot: 0, target: { tile: false, value: 8 } }]);
  });

  it("a belt slot is a potion: armed, then drunk on the adventurer", () => {
    const { fake, combat } = combatSetup(153);
    combat.slot({ kind: "item", slot: 1 });
    expect(combat.snapshot().view?.armed).toEqual({ kind: "item", slot: 1 });
    combat.slot({ kind: "item", slot: 1 });
    expect(fake.actions()).toEqual([{ kind: "item", slot: 1, entity: 0 }]);
  });

  it("Esc disarms, and the bar shows the state after the batch", () => {
    const { combat } = combatSetup(48);
    combat.slot({ kind: "skill", slot: 0 });
    expect(combat.escape()).toBe(true);
    expect(combat.snapshot().view?.armed).toBeNull();
    expect(combat.escape()).toBe(false);
    expect(combat.snapshot().view?.state.adventurer.bar).toHaveLength(8);
  });
});

describe("aiming at the location's edge (CLI-05g)", () => {
  it("a TILE skill armed at the spawn tile (0, 7) aims, and throws nothing", () => {
    // Row 88's world with the adventurer put at (0, 7), seven columns and nine rows into the
    // window: the off-board tiles are skipped by `aiming`, so the controller needs no guard
    const row = actRow(88);
    const board = { ...row.board, x: ORIGIN - 7, y: ORIGIN - 2 };
    const world = readWorld(row.words, ACT, row.ground, board);
    const member = world.world.members[0]!;
    const was = memberPlace(member);
    member.words = {
      ...member.words,
      state: member.words.state + BigInt(-was.x + 256 * (7 - was.y)) * 2n ** 32n,
    };
    const warned: unknown[][] = [];
    const warn = console.warn;
    console.warn = (...args: unknown[]) => void warned.push(args);
    try {
      const { combat } = combatSetup(88, { combatWorld: () => world });
      expect(() => combat.slot({ kind: "skill", slot: 0 })).not.toThrow();
      expect(combat.snapshot().view?.armed).toEqual({ kind: "skill", slot: 0 });
      expect(combat.snapshot().view?.aim).toMatchObject({ addressing: "tile" });
      expect(warned).toEqual([]);
    } finally {
      console.warn = warn;
    }
  });
});

describe("what is refused before the batch (§4.4)", () => {
  it("a skill on recharge says its ticks and arms nothing", () => {
    const { fake, combat } = combatSetup(57);
    combat.slot({ kind: "skill", slot: 0 });
    expect(combat.snapshot().view?.armed).toBeNull();
    expect(combat.snapshot().view?.said).toBe("Recharging: 1 tick.");
    expect(fake.actions()).toEqual([]);
  });

  it("a potion with none left says so and arms nothing", () => {
    const { fake, combat } = combatSetup(48);
    combat.slot({ kind: "item", slot: 0 });
    expect(combat.snapshot().view?.armed).toBeNull();
    expect(combat.snapshot().view?.said).toBe("None left.");
    expect(fake.actions()).toEqual([]);
  });

  it("a target that is no foe is not a valid target, the batch unchanged and the slot armed", () => {
    const { fake, combat } = combatSetup(48);
    combat.slot({ kind: "skill", slot: 0 });
    expect(combat.actor(77)).toBe(true);
    expect(combat.snapshot().view?.said).toBe("Not a valid target.");
    expect(combat.snapshot().view?.armed).toEqual({ kind: "skill", slot: 0 });
    expect(fake.actions()).toEqual([]);
  });

  const CASES: readonly [string, number, string][] = [
    ["Reach", Illegal.Reach, "Out of reach."],
    ["Energy", Illegal.Energy, "Not enough energy."],
    ["Adrenaline", Illegal.Adrenaline, "Not enough adrenaline."],
    ["Belt", Illegal.Belt, "None left."],
    ["Trap", Illegal.Trap, "A trap cannot go there."],
    ["Instant", Illegal.Instant, "Only one instant skill between two ticks."],
    ["Knocked", Illegal.Knocked, "You are knocked down."],
  ];
  for (const [name, illegal, line] of CASES) {
    it(`the mirror's ${name} is "${line}": the action is not added, the slot stays armed`, () => {
      const { fake, controller, combat } = combatSetup(48, { run: refusing(illegal) });
      controller.wait();
      combat.slot({ kind: "skill", slot: 0 });
      combat.actor(8);
      expect(fake.actions()).toEqual([{ kind: "wait" }]);
      expect(controller.get().note).toBe(line);
      expect(combat.snapshot().view?.armed).toEqual({ kind: "skill", slot: 0 });
      // The refusal is in the log, in its own tone and status
      expect(combat.snapshot().log.at(-1)).toEqual({
        text: line,
        tone: "refusal",
        status: "refused",
      });
      // Armed again, the tap that plays it is refused again with the batch still unchanged
      combat.actor(8);
      expect(fake.actions()).toEqual([{ kind: "wait" }]);
    });
  }

  it("a refusal of a recharge says its ticks", () => {
    const { controller, combat } = combatSetup(57, { run: refusing(Illegal.Recharging) });
    // Slot 0 recharges (1 tick); slot 1 is ready and the mirror refuses it for a recharge too
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    expect(controller.get().note).toBe("Recharging.");
  });

  it("an Illegal a tap cannot reach is a parity record and a plain line, nothing added", () => {
    const warned: unknown[][] = [];
    const warn = console.warn;
    console.warn = (...args: unknown[]) => void warned.push(args);
    try {
      const { fake, controller, combat } = combatSetup(48, { run: refusing(Illegal.Turned) });
      combat.slot({ kind: "skill", slot: 1 });
      combat.slot({ kind: "skill", slot: 1 });
      expect(fake.actions()).toEqual([]);
      expect(controller.get().note).toBe(notes.NOT_AVAILABLE);
      expect(warned[0]?.[0]).toBe("grimworld.parity");
    } finally {
      console.warn = warn;
    }
  });

  it("where the mirror cannot say, the action is added and the simulation decides", () => {
    const { fake, combat } = combatSetup(48, {
      run: () => () => {
        throw Object.assign(new Error("a Move revealed a chunk"), { name: "NotMirrored" });
      },
    });
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    expect(fake.actions()).toEqual([{ kind: "skill", slot: 1, target: { tile: false, value: 0 } }]);
  });

  it("a full batch refuses the action and leaves the slot armed", () => {
    const { fake, controller, combat } = combatSetup(48);
    for (let i = 0; i < 10; i++) controller.wait();
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    expect(fake.actions()).toHaveLength(10);
    expect(combat.snapshot().view?.armed).toEqual({ kind: "skill", slot: 1 });
  });
});

describe("interactions are not available (§4.4)", () => {
  /** The recorded chunk 0 with a non-trap object (kind 2) on tile (1, 7), local tile 106. */
  function withObject(): ChainState {
    const chain = recordedChain();
    const object = (106n | (2n << 8n)) << 128n;
    const region = chain.mirror.region.map((c) =>
      c.chunk === 0 ? { ...c, features: c.features | object } : c,
    );
    return { ...chain, mirror: { ...chain.mirror, region } };
  }

  it("a tap on a gate, a chest or a lever says so and adds no interact", () => {
    const fake = fakeStages(withObject());
    const controller = createChainController({
      stages: fake.stages,
      enter: async () => recordedChain(),
    });
    expect(controller.tap({ x: 1, y: 7 })).toEqual({ kind: "none" });
    expect(controller.get().note).toBe("Not available yet.");
    expect(fake.actions()).toEqual([]);
  });
});

describe("the log from the mirror (§7.2)", () => {
  const A: LogLine = { text: "You used Strike on the runt", tone: "event", status: "predicted" };
  const B: LogLine = { text: "The runt lost 8 health", tone: "event", status: "predicted" };
  const lines = (_: unknown, actions: readonly unknown[]) => (actions.length === 0 ? [] : [[A, B]]);
  const played = (mismatches: unknown[]) =>
    ({
      simulated: {} as never,
      result: {
        kind: "sent",
        id: "0x1",
        blockHash: "0x2",
        differs: [],
        after: {} as never,
        chain: { kind: "played", batch: { played: 1, stop: 0 } },
        mirror: { kind: "predicted", played: 1, stop: 0 },
        mismatches,
      },
    }) as unknown as StagesState["sent"];

  it("shows the planned actions' lines as predicted", () => {
    const { combat } = combatSetup(48, { lines });
    expect(combat.snapshot().log).toEqual([]);
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    expect(combat.snapshot().log).toEqual([A, B]);
  });

  it("confirms them once the sent batch equals the prediction", () => {
    const { fake, combat } = combatSetup(48, { lines });
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    fake.setSent(played([]));
    expect(combat.snapshot().log).toEqual([
      { ...A, status: "confirmed" },
      { ...B, status: "confirmed" },
    ]);
  });

  it("strikes them and says the world corrected itself when the chain differs", () => {
    const { fake, combat } = combatSetup(48, { lines });
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    fake.setSent(played([{ field: "members[0].state", chain: 1n, mirror: 2n }]));
    expect(combat.snapshot().log).toEqual([
      { ...A, status: "struck" },
      { ...B, status: "struck" },
      { text: "The world corrected itself", tone: "event", status: "confirmed" },
    ]);
  });

  it("says nothing of a sent batch the mirror did not predict", () => {
    const { fake, combat } = combatSetup(48, { lines });
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    const sent = played([]) as unknown as { result: { mirror: unknown } };
    sent.result.mirror = { kind: "not-mirrored", reason: "a reveal" };
    fake.setSent(sent as unknown as StagesState["sent"]);
    expect(combat.snapshot().log).toEqual([A, B]);
  });

  it("clears a refusal on entering again, after a send the mirror did not predict (review t-0012)", async () => {
    const W: LogLine = { text: "You waited", tone: "event", status: "predicted" };
    const { fake, controller, combat } = combatSetup(57, {
      lines: (_, actions) => actions.map(() => [W]),
      run: refusing(Illegal.Recharging),
    });
    controller.wait();
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    // Sent, and settled with no prediction (NotMirrored): nothing settles, the refusal stays
    const sent = played([]) as unknown as { result: { mirror: unknown } };
    sent.result.mirror = { kind: "not-mirrored", reason: "a reveal" };
    fake.setSent(sent as unknown as StagesState["sent"]);
    expect(combat.snapshot().log).toEqual([
      W,
      { text: "Recharging.", tone: "refusal", status: "refused" },
    ]);
    // The instance closes, and N enters again: the new instance's log is empty
    fake.setPhase("closed");
    expect(await controller.enterAgain()).toBe(true);
    expect(combat.snapshot().log).toEqual([]);
  });

  it("keeps a refusal in input order, and a send neither confirms nor strikes it (review t-0008)", () => {
    const W: LogLine = { text: "You waited", tone: "event", status: "predicted" };
    const R: LogLine = { text: "Recharging.", tone: "refusal", status: "refused" };
    const { fake, controller, combat } = combatSetup(57, {
      lines: (_, actions) => actions.map(() => [W]),
      run: refusing(Illegal.Recharging),
    });
    // A Wait planned, a recharging slot tapped (refused), a Wait again
    controller.wait();
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    expect(controller.get().note).toBe("Recharging.");
    controller.wait();
    expect(fake.actions()).toEqual([{ kind: "wait" }, { kind: "wait" }]);
    expect(combat.snapshot().log).toEqual([W, R, W]);
    // Sent with a mismatch: the Waits are struck, the refusal is left as it was
    fake.setSent(played([{ field: "members[0].state", chain: 1n, mirror: 2n }]));
    expect(combat.snapshot().log).toEqual([
      { ...W, status: "struck" },
      R,
      { ...W, status: "struck" },
      { text: "The world corrected itself", tone: "event", status: "confirmed" },
    ]);
    // And a later confirmed send leaves it too
    controller.wait();
    fake.setSent(played([]));
    expect(combat.snapshot().log.filter((l) => l.tone === "refusal")).toEqual([R]);
  });

  it("keeps a refusal after the batch it followed is dropped", () => {
    const W: LogLine = { text: "You waited", tone: "event", status: "predicted" };
    const { fake, controller, combat } = combatSetup(57, {
      lines: (_, actions) => actions.map(() => [W]),
      run: refusing(Illegal.Recharging),
    });
    controller.wait();
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    fake.setPlanned([]);
    expect(combat.snapshot().log).toEqual([
      { text: "Recharging.", tone: "refusal", status: "refused" },
    ]);
    controller.wait();
    expect(combat.snapshot().log.map((l) => l.tone)).toEqual(["refusal", "event"]);
  });

  it("keeps the last 100 lines", () => {
    const many = Array.from({ length: 120 }, (_, i) => ({ ...A, text: `line ${i}` }));
    const { combat } = combatSetup(48, {
      lines: (_, actions) => (actions.length === 0 ? [] : [many]),
    });
    combat.slot({ kind: "skill", slot: 1 });
    combat.slot({ kind: "skill", slot: 1 });
    const log = combat.snapshot().log;
    expect(log).toHaveLength(100);
    expect(log.at(-1)?.text).toBe("line 119");
  });
});
