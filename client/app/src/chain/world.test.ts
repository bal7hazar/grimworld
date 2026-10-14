import { describe, expect, it } from "vitest";
import { unpackWalls } from "../preview/mirror";
import { recordedBefore } from "../preview/recorded-goblins";
import {
  ChunkKind,
  type InstanceView,
  type RegionChunk,
  decodeInstanceView,
} from "../preview/view";
import { initialState, toView } from "../sandbox/wiring";
import { stateOf } from "../combat/fromWords";
import { recordedBefore as noGoblins } from "../preview/recorded";
import type { MirrorState } from "../preview/mirror";
import {
  chainWorld,
  combatWorldOf,
  goblinActor,
  goblinPlace,
  memberPlace,
  objectAt,
} from "./world";

/** The state recorded on starknet-devnet before the Wait, with a goblin in view (OPS-01a's seed). */
const view = (): InstanceView => decodeInstanceView(recordedBefore.view.map(BigInt));
const region = (): RegionChunk[] =>
  recordedBefore.region.map((c) => ({
    chunk: c.chunk,
    kind: c.kind as RegionChunk["kind"],
    terrain: BigInt(c.terrain),
    features: BigInt(c.features),
    goblins: [],
  }));
const recorded = () => ({ view: view(), region: region(), member: recordedBefore.member });

describe("the words' tile and facing", () => {
  it("a member's is at bits 32–55, a goblin's at bits 0–23", () => {
    const member = (3n << 48n) | (9n << 40n) | (200n << 32n) | 0x5an;
    expect(memberPlace(member)).toEqual({ x: 200, y: 9, facing: 3 });
    const goblin = (5n << 16n) | (4n << 8n) | 17n;
    expect(goblinPlace(goblin | (1n << 24n))).toEqual({ x: 17, y: 4, facing: 5 });
    // A facing the chain never writes is drawn East rather than refused
    expect(memberPlace(7n << 48n).facing).toBe(0);
  });
});

describe("the world built from a recorded view and region (§6.2)", () => {
  it("draws the adventurer and the goblin where the view puts them", () => {
    const world = chainWorld(recorded());
    const adventurer = world.actors.find((a) => a.id === world.adventurerId);
    expect(adventurer).toMatchObject({ side: "adventurer", tile: { x: 0, y: 7 }, facing: 0 });
    // The recording: entity 8 on (12, 1), on watch (ai 1: no mark)
    const goblin = world.actors.find((a) => a.side === "goblin");
    expect(goblin).toMatchObject({ id: 8, tile: { x: 12, y: 1 }, facing: 0, mark: null });
    expect(world.actors).toHaveLength(2);
    // And so does the view the renderer gets from it
    const drawn = toView(initialState(world));
    expect(drawn.actors.find((a) => a.id === drawn.adventurerId)?.tile).toEqual({ x: 0, y: 7 });
    // The goblin is beyond the adventurer's sight (radius 6), which is the sandbox's own fog: the
    // world holds it, the map shows it once it is seen
    expect(drawn.actors.find((a) => a.id === 8)).toBeUndefined();
  });

  it("draws a goblin in sight where the view puts it", () => {
    const base = view();
    const near = {
      ...base.goblins[0]!,
      state: (base.goblins[0]!.state & ~0xffffn) | (3n << 8n) | 2n,
    };
    const world = chainWorld({ ...recorded(), view: { ...base, goblins: [near] } });
    const drawn = toView(initialState(world));
    expect(drawn.actors.find((a) => a.id === 8)?.tile).toEqual({ x: 2, y: 3 });
  });

  it("is the location's rectangle of 15-tile chunks, a chunk by its index", () => {
    const world = chainWorld(recorded());
    expect(world.terrain.width).toBe(3 * 15);
    expect(world.terrain.height).toBe(3 * 15);
    // Chunk 0, revealed: its walls say which tiles are floor
    const walls = unpackWalls(BigInt(recordedBefore.region[0]!.terrain));
    for (let ly = 0; ly < 15; ly++) {
      for (let lx = 0; lx < 15; lx++) {
        const wall = ((walls >> BigInt(ly * 15 + lx)) & 1n) === 1n;
        expect(world.terrain.kinds[ly * 45 + lx], `(${lx}, ${ly})`).toBe(wall ? "wall" : "floor");
      }
    }
    // The tile the adventurer stands on is floor
    expect(world.terrain.kinds[7 * 45 + 0]).toBe("floor");
  });

  it("draws an unrevealed chunk apart, a void chunk as wall over water", () => {
    const world = chainWorld(recorded());
    // Chunk 1 (column 1, row 0) and chunk 32 (column 2, row 2) are unrevealed
    expect(world.terrain.kinds[0 * 45 + 15]).toBe("unrevealed");
    expect(world.terrain.kinds[44 * 45 + 44]).toBe("unrevealed");
    expect(world.terrain.ground?.[0 * 45 + 15]).toBe("grass");
    // Chunk 31 (column 1, row 2) made void
    const voided = region().map((c) => (c.chunk === 31 ? { ...c, kind: ChunkKind.Void } : c));
    const withVoid = chainWorld({ ...recorded(), region: voided });
    const inVoid = 35 * 45 + 20;
    expect(withVoid.terrain.kinds[inVoid]).toBe("wall");
    expect(withVoid.terrain.ground?.[inVoid]).toBe("water");
    expect(withVoid.terrain.ground?.[7 * 45]).toBe("grass");
  });

  it("leaves out a dead goblin and marks the others by their state", () => {
    const base = view();
    const goblin = base.goblins[0]!;
    const withAi = (ai: number) => ({
      ...goblin,
      state: (goblin.state & ~(0xffn << 24n)) | (BigInt(ai) << 24n),
    });
    const marks = ["asleep", null, "alerted", "engaged", "fleeing", null];
    marks.forEach((mark, ai) => {
      expect(goblinActor(withAi(ai))?.mark, `ai ${ai}`).toBe(mark);
    });
    expect(goblinActor(withAi(6))).toBeNull();
    expect(goblinActor(withAi(7))).toBeNull();
    const dead = chainWorld({ ...recorded(), view: { ...base, goblins: [withAi(6)] } });
    expect(dead.actors.filter((a) => a.side === "goblin")).toEqual([]);
  });

  it("refuses a view that names no location", () => {
    expect(() => chainWorld({ ...recorded(), view: { ...view(), width: 0, height: 0 } })).toThrow(
      RangeError,
    );
  });
});

describe("the combat world and the objects of a state (CLI-11d)", () => {
  /** The recording without goblins (`recorded.ts`): the adventurer on (0, 7). */
  const recordedState = (): MirrorState => ({
    view: decodeInstanceView(noGoblins.view.map(BigInt)),
    member: noGoblins.member,
    region: noGoblins.region.map((c) => ({
      chunk: c.chunk,
      kind: c.kind as RegionChunk["kind"],
      terrain: BigInt(c.terrain),
      features: BigInt(c.features),
      goblins: [],
    })),
  });
  const EMPTY = { skills: [], potions: [], castes: [] };

  it("is none where the state holds no content, or the adventurer is not member 0", () => {
    expect(combatWorldOf(recordedState())).toBeUndefined();
    expect(combatWorldOf({ ...recordedState(), content: EMPTY, member: 1 })).toBeUndefined();
  });

  it("reads the adventurer's tile and an empty bar and belt from the state's words", () => {
    const world = combatWorldOf({ ...recordedState(), content: EMPTY });
    expect(world).toBeDefined();
    const state = stateOf(world!);
    expect(state.adventurer.tile).toEqual({ x: 0, y: 7 });
    expect(state.adventurer.bar).toHaveLength(8);
    expect(state.adventurer.bar.every((slot) => slot.state === "empty")).toBe(true);
    expect(state.goblins).toEqual([]);
  });

  it("reads the words after the batch when a prediction is given", () => {
    const before = recordedState();
    const chain = combatWorldOf({ ...before, content: EMPTY })!;
    const member = chain.world.members[0]!;
    expect(member.health).toBeGreaterThan(0);
    const words = {
      clock: before.view.header.clock + 3,
      members: before.view.members.map((m) => ({ ...m })),
      goblins: [],
      killed: [],
      defeated: false,
    };
    const after = combatWorldOf({ ...before, content: EMPTY }, { words, ground: [] });
    expect(after?.world.clock).toBe(before.view.header.clock + 3);
  });

  it("finds an object that is no trap on a tile of a revealed chunk", () => {
    const { region } = recordedState();
    expect(objectAt(region, { x: 1, y: 7 })).toBe(false);
    const object = (kind: bigint) => (106n | (kind << 8n)) << 128n;
    const placed = (kind: bigint) =>
      region.map((c) => (c.chunk === 0 ? { ...c, features: c.features | object(kind) } : c));
    // Tile 106 of chunk 0 is (1, 7): a gate, a chest or a lever (any kind that is no trap)
    expect(objectAt(placed(2n), { x: 1, y: 7 })).toBe(true);
    expect(objectAt(placed(2n), { x: 2, y: 7 })).toBe(false);
    // A trap is not an interaction: terrain trap 4, placed trap 9
    expect(objectAt(placed(4n), { x: 1, y: 7 })).toBe(false);
    expect(objectAt(placed(9n), { x: 1, y: 7 })).toBe(false);
    // A chunk the region does not give
    expect(objectAt([], { x: 1, y: 7 })).toBe(false);
  });
});
