import { NotMirrored } from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import {
  type MirrorState,
  mirrorOf,
  segmentOf,
  unpackFeatures,
  unpackWalls,
  unportedClasses,
} from "./mirror";
import { recordedBefore, recordedPlayed } from "./recorded";
import { reconcile } from "./reconcile";
import { Stop, extractOutcome } from "./trace";
import { type RegionChunk, decodeInstanceView, encodeInstanceView } from "./view";

const LIVE = 1n << 250n;
const P128 = 1n << 128n;
const EMPTY = { skills: [], potions: [], castes: [] };
/**
 * Chunk 0's `Features` on another deployment of the same seed (the reveal draws from the
 * deployment's entropy): a pack of five goblins, template 1 at level 1, on tile 37.
 */
const PACKED = 0x400000000000000000000000000000000000000000000000e91589501000125n;

/** The state recorded on starknet-devnet before the Wait (`recorded.ts`). */
function recordedState(): MirrorState {
  return {
    view: decodeInstanceView(recordedBefore.view.map(BigInt)),
    member: recordedBefore.member,
    region: recordedBefore.region.map((c): RegionChunk => ({
      chunk: c.chunk,
      kind: c.kind as RegionChunk["kind"],
      terrain: BigInt(c.terrain),
      features: BigInt(c.features),
      goblins: [],
    })),
    content: EMPTY,
  };
}

/** `FeaturesStorePacking::pack` (contracts/logic/src/models/chunk.cairo), the inverse tested. */
function packFeatures(f: ReturnType<typeof unpackFeatures>): bigint {
  const pack = (p: (typeof f.packs)[number]) =>
    BigInt(p.tile) +
    (BigInt(p.template) << 8n) +
    (BigInt(p.level) << 24n) +
    (BigInt(p.count) << 32n) +
    (BigInt(p.offsets) << 36n) +
    (BigInt(p.alert) << 61n);
  const object = (o: (typeof f.objects)[number]) =>
    BigInt(o.tile) + (BigInt(o.kind) << 8n) + (BigInt(o.state) << 12n) + (BigInt(o.param) << 16n);
  const [p0, p1] = f.packs;
  const [o0, o1, o2] = f.objects;
  const low = pack(p0!) + (pack(p1!) << 64n);
  const high =
    object(o0!) + (object(o1!) << 32n) + (object(o2!) << 64n) + (BigInt(f.touched) << 96n);
  return low + high * P128 + LIVE;
}

describe("the records the segment reads", () => {
  it("reads the recorded location from the view: the test region's zone, 3 × 3, level 1", () => {
    const view = decodeInstanceView(recordedBefore.view.map(BigInt));
    expect([view.width, view.height, view.levelMin]).toEqual([3, 3, 1]);
  });

  it("unpacks a recorded pack, and round-trips every field of Features", () => {
    const features = unpackFeatures(PACKED);
    expect(features.packs[0]).toMatchObject({
      tile: 37,
      template: 1,
      level: 1,
      count: 5,
      alert: 0,
    });
    expect(features.packs[1]!.count).toBe(0);
    expect(packFeatures(features)).toBe(PACKED);
    const chunk0 = recordedBefore.region.find((c) => c.chunk === 0)!;
    expect(packFeatures(unpackFeatures(BigInt(chunk0.features)))).toBe(BigInt(chunk0.features));
    const every = {
      packs: [
        { tile: 224, template: 0xfffe, level: 250, count: 15, offsets: 0x1fffffe, alert: 7 },
        { tile: 1, template: 2, level: 3, count: 4, offsets: 5, alert: 6 },
      ],
      objects: [
        { tile: 9, kind: 15, state: 14, param: 0xfffd },
        { tile: 10, kind: 1, state: 2, param: 3 },
        { tile: 11, kind: 4, state: 0, param: 0x8001 },
      ],
      touched: 0xffff,
    };
    expect(unpackFeatures(packFeatures(every))).toEqual(every);
  });

  it("reads a terrain's walls without its edges or LIVE", () => {
    const walls = (1n << 224n) | 0x1234n;
    expect(unpackWalls(walls + (0xan << 225n) + LIVE)).toBe(walls);
    const chunk0 = recordedBefore.region.find((c) => c.chunk === 0)!;
    // The entry tile (105) is open
    expect((unpackWalls(BigInt(chunk0.terrain)) >> 105n) & 1n).toBe(0n);
  });
});

describe("the mirror on the recorded state", () => {
  it("builds the segment as PlayLibrary does and predicts the real Wait: no mismatch", () => {
    const state = recordedState();
    const segment = segmentOf(state);
    expect(segment.area).toMatchObject({ width: 3, height: 3, known: 0x1c0038007n, ran: false });
    expect(segment.area.chunks.map(([chunk]) => chunk)).toEqual([0]);
    expect([segment.level, segment.owed, segment.weight]).toEqual([1, 0, 10]);
    expect(segment.words).toMatchObject({ clock: 0, goblins: [], killed: [], defeated: false });
    const predict = mirrorOf(state);
    const chain = extractOutcome(recordedPlayed);
    const result = reconcile(chain, [{ kind: "wait" }], predict, () => {
      throw new Error("no parity record expected");
    });
    expect(result.mirror).toMatchObject({ kind: "predicted", played: 1, stop: Stop.None });
    expect(result.mismatches).toEqual([]);
  });

  it("stops where the view lists no goblin for the area's packs (no PlayLibrary set)", () => {
    const state = recordedState();
    const region = state.region.map((c) => (c.chunk === 0 ? { ...c, features: PACKED } : c));
    expect(() => segmentOf({ ...state, region })).toThrow(NotMirrored);
    expect(() => segmentOf({ ...state, region })).toThrow(
      "goblin 8 of chunk 0's pack not in the view (no PlayLibrary set)",
    );
  });

  it("stops on a roster the view lists no goblin for", () => {
    const state = recordedState();
    const view = { ...state.view, header: { ...state.view.header, rosterCount: 2 } };
    expect(() => segmentOf({ ...state, view })).toThrow(
      "the roster's goblins not in the view (no PlayLibrary set)",
    );
  });

  it("refuses the UNLOADABLE marker as the chain does: a goblin cannot load", () => {
    const state = recordedState();
    const view = decodeInstanceView(
      encodeInstanceView({ ...state.view, unloadable: true, goblins: [] }),
    );
    expect(view.unloadable).toBe(true);
    expect(() => segmentOf({ ...state, view })).toThrow(NotMirrored);
    expect(() => segmentOf({ ...state, view })).toThrow("a goblin cannot load");
  });

  it("takes the view's goblins as they are, derived ones included, and its location", () => {
    const state = recordedState();
    const goblins = [
      { entity: 8, derived: true, state: LIVE + 5n, timers: LIVE + 6n },
      { entity: 9, derived: false, state: LIVE + 7n, timers: LIVE + 8n },
    ];
    const view = { ...state.view, goblins, width: 5, height: 4, levelMin: 2 };
    const segment = segmentOf({ ...state, view });
    expect(segment.words.goblins).toEqual([
      { entity: 8, awake: false, state: LIVE + 5n, timers: LIVE + 6n },
      { entity: 9, awake: false, state: LIVE + 7n, timers: LIVE + 8n },
    ]);
    expect([segment.area.width, segment.area.height, segment.level]).toEqual([5, 4, 2]);
  });

  it("centres the area on the controlled member, not the first (review t-0190, note 3)", () => {
    const state = recordedState();
    const [first] = state.view.members;
    // Member 1 stands at tile (60, 0), chunk column 4: chunk 0, the only one revealed, is not around it
    const far = { ...first!, state: (first!.state & ~(0xffffn << 32n)) | (60n << 32n) };
    const view = { ...state.view, members: [first!, far] };
    expect(segmentOf({ ...state, view, member: 0 }).area.chunks.map(([c]) => c)).toEqual([0]);
    expect(segmentOf({ ...state, view, member: 1 }).area.chunks.map(([c]) => c)).toEqual([]);
    expect(() => segmentOf({ ...state, view, member: 2 })).toThrow("no member 2");
  });

  it("is no prediction where no content is given and the segment reads a sheet", () => {
    const { content: _, ...state } = recordedState();
    const goblin = { entity: 8, derived: true, state: LIVE + 5n, timers: LIVE + 6n };
    const predict = mirrorOf({ ...state, view: { ...state.view, goblins: [goblin] } });
    expect(() => predict([{ kind: "wait" }])).toThrow(NotMirrored);
    expect(() => predict([{ kind: "wait" }])).toThrow(
      "not mirrored: no content given, the segment reads a sheet",
    );
    const result = reconcile(extractOutcome(recordedPlayed), [{ kind: "wait" }], predict, () => {
      throw new Error("no parity record expected");
    });
    expect(result.mirror).toMatchObject({ kind: "not-mirrored" });
  });

  it("logs a mirror failure where the given content lacks a sheet (review t-0194 of #439)", () => {
    const state = recordedState();
    const goblin = { entity: 8, derived: true, state: LIVE + 5n, timers: LIVE + 6n };
    const predict = mirrorOf({ ...state, view: { ...state.view, goblins: [goblin] } });
    expect(() => predict([{ kind: "wait" }])).not.toThrow(NotMirrored);
    expect(() => predict([{ kind: "wait" }])).toThrow("not in content");
    const logged: unknown[] = [];
    const result = reconcile(extractOutcome(recordedPlayed), [{ kind: "wait" }], predict, (r) =>
      logged.push(r),
    );
    expect(result.mirror).toMatchObject({ kind: "not-mirrored" });
    expect(logged).toEqual([
      {
        kind: "grimworld.mirror-failure",
        actions: [{ kind: "wait" }],
        error: expect.stringContaining("not in content") as unknown,
      },
    ]);
  });

  it("answers every class behind the seam with NotMirrored", () => {
    expect(() => unportedClasses.ticks({} as never)).toThrow(NotMirrored);
    expect(() => unportedClasses.act({} as never)).toThrow(NotMirrored);
    expect(() => unportedClasses.trigger({} as never)).toThrow(NotMirrored);
  });

  it("refuses a revealed chunk around the adventurer that the region does not give", () => {
    const state = recordedState();
    expect(() => segmentOf({ ...state, region: [] })).toThrow("revealed chunk 0 not in the region");
  });
});
