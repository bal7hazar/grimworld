import { NotMirrored } from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import {
  type MirrorState,
  mirrorOf,
  segmentOf,
  unpackFeatures,
  unpackLocation,
  unpackWalls,
  unportedClasses,
} from "./mirror";
import { recordedBefore, recordedPlayed } from "./recorded";
import { reconcile } from "./reconcile";
import { Stop, extractOutcome } from "./trace";
import { type RegionChunk, decodeInstanceView } from "./view";

const LIVE = 1n << 250n;
const P128 = 1n << 128n;
const EMPTY = { skills: [], potions: [], castes: [] };

/** The state recorded on starknet-devnet before the Wait (`recorded.ts`). */
function recordedState(): MirrorState {
  return {
    view: decodeInstanceView(recordedBefore.view.map(BigInt)),
    location: unpackLocation(recordedBefore.location.map(BigInt)),
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
  it("unpacks the recorded location: the test region's zone, 3 × 3, level 1", () => {
    expect(unpackLocation(recordedBefore.location.map(BigInt))).toEqual({
      width: 3,
      height: 3,
      levelMin: 1,
    });
  });

  it("unpacks the recorded chunk 0's pack, and round-trips every field of Features", () => {
    const chunk0 = recordedBefore.region.find((c) => c.chunk === 0)!;
    const features = unpackFeatures(BigInt(chunk0.features));
    expect(features.packs[0]).toMatchObject({ template: 1, level: 1, count: 5, alert: 0 });
    expect(packFeatures(features)).toBe(BigInt(chunk0.features));
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
  it("builds the segment as PlayLibrary does, and stops where the view lacks the goblins", () => {
    const state = recordedState();
    expect(() => segmentOf(state)).toThrow(NotMirrored);
    expect(() => segmentOf(state)).toThrow("goblin 8 of chunk 0's pack not in the view");
  });

  it("predicts a Wait on the fast path once the pack is left out (the wiring, not a parity claim)", () => {
    const state = recordedState();
    const region = state.region.map((c) =>
      // The pack's 64 bits cleared, the objects kept
      c.chunk === 0 ? { ...c, features: c.features - (c.features % (1n << 128n)) } : c,
    );
    const quiet = { ...state, region };
    const segment = segmentOf(quiet);
    expect(segment.area).toMatchObject({ width: 3, height: 3, known: 0x1c0038007n, ran: false });
    expect(segment.area.chunks.map(([chunk]) => chunk)).toEqual([0]);
    expect([segment.level, segment.owed, segment.weight]).toEqual([1, 0, 10]);
    const predict = mirrorOf(quiet);
    const chain = extractOutcome(recordedPlayed);
    const result = reconcile(chain, [{ kind: "wait" }], predict, () => {
      throw new Error("no parity record expected");
    });
    expect(result.mirror).toMatchObject({ kind: "predicted", played: 1, stop: Stop.None });
    expect(result.mismatches).toEqual([]);
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
