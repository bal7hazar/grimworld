import { readFileSync } from "node:fs";
import {
  type Call,
  Felts,
  type Ground,
  NotMirrored,
  type TriggerCall,
  actionAct,
  readAction,
  readArea,
  readCall,
  readContent,
  readGround,
  readWords,
  runSegment,
  trapTrigger,
  writeDone,
  writeGround,
  writeWords,
} from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import {
  type MirrorState,
  mirrorOf,
  nativeClasses,
  segmentOf,
  unpackFeatures,
  unpackWalls,
  unportedClasses,
} from "./mirror";
import { recordedBefore, recordedPlayed } from "./recorded";
import * as goblins from "./recorded-goblins";
import { assembleContent } from "./content";
import { type Prediction, reconcile } from "./reconcile";
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
    const { view, member, region } = recordedState();
    const state = { view, member, region };
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

  it("runs the trap and action classes natively: ticks alone stays unported", () => {
    expect(nativeClasses.trigger).toBe(trapTrigger);
    expect(nativeClasses.act).toBe(actionAct);
    expect(() => nativeClasses.ticks({} as never)).toThrow("TickLibrary::ticks");
    expect(() => nativeClasses.ticks({} as never)).toThrow(NotMirrored);
    // The action class is computed: it reads its call, it does not refuse it as unported
    expect(() => nativeClasses.act({} as never)).not.toThrow(NotMirrored);
  });

  it("predicts a Move onto a trap: the trap used, the member struck (CLI-10e)", () => {
    const state = recordedState();
    // trap.jsonl's skill 70 (0x46): a terrain trap's payload, earth damage and Poison
    const skill = {
      id: 0x46,
      kind: 9,
      energy: 0,
      profession: 0,
      adrenaline: 0,
      activation: 1,
      recharge: 10,
      regen0: 0,
      regen12: 0,
      range: 0,
      entry1: 0x1c000000000000000000012n,
      entry2: 0x140000000000028000a0701n,
      entry3: 0x14000000000000400040206n,
    };
    const content = { skills: [skill], potions: [], castes: [] };
    // The adventurer stands on tile 105 of chunk 0; terrain traps (kind 4, skill 70) on the three
    // tiles it can step to: 106 (east), 90 (north) and 120 (south)
    const trap = (tile: number) => BigInt(tile) | (4n << 8n) | (0x46n << 16n);
    const objects = (trap(106) | (trap(90) << 32n) | (trap(120) << 64n)) << 128n;
    const region = state.region.map((c) =>
      c.chunk === 0 ? { ...c, features: c.features | objects } : c,
    );
    const quiet = { ...state, content };
    const stepped = { ...quiet, region };
    expect(unpackFeatures(region.find((c) => c.chunk === 0)!.features).objects).toMatchObject([
      { tile: 106, kind: 4 },
      { tile: 90, kind: 4 },
      { tile: 120, kind: 4 },
    ]);
    const calls: TriggerCall[] = [];
    const spy = {
      ...nativeClasses,
      trigger: (call: TriggerCall) => {
        calls.push(call);
        return trapTrigger(call);
      },
    };
    const used = (ground: Ground) =>
      ground.flatMap(([, f]) => f.objects).filter((o) => o.kind === 4 && o.state === 1);
    const moves = [0, 1, 2, 3].map((direction) => [{ kind: "move" as const, direction }]);
    const reached = moves.filter((actions) => {
      calls.length = 0;
      mirrorOf(stepped, spy)(actions);
      return calls.length > 0;
    });
    expect(reached.length).toBeGreaterThan(0);
    for (const actions of reached) {
      // `Predict` is client/sim's `Ran`, whose ground `Prediction` does not list
      const without = mirrorOf(quiet)(actions) as Prediction & { ground: Ground };
      const predicted = mirrorOf(stepped)(actions) as Prediction & { ground: Ground };
      // The entered trap is used in the predicted ground, and the member's words are not those of
      // the same batch with no trap
      expect(used(predicted.ground)).toHaveLength(1);
      expect(used(without.ground)).toHaveLength(0);
      expect(predicted.words.members).not.toEqual(without.words.members);
      // The unported classes refuse it
      expect(() => mirrorOf(stepped, unportedClasses)(actions)).toThrow("TrapLibrary::trigger");
    }
  });

  it("refuses a revealed chunk around the adventurer that the region does not give", () => {
    const state = recordedState();
    expect(() => segmentOf({ ...state, region: [] })).toThrow("revealed chunk 0 not in the region");
  });
});

/** The state recorded on a deployment whose view lists one goblin (`recorded-goblins.ts`). */
function goblinState(): Omit<MirrorState, "content"> {
  return {
    view: decodeInstanceView(goblins.recordedBefore.view.map(BigInt)),
    member: goblins.recordedBefore.member,
    region: goblins.recordedBefore.region.map((c): RegionChunk => ({
      chunk: c.chunk,
      kind: c.kind as RegionChunk["kind"],
      terrain: BigInt(c.terrain),
      features: BigInt(c.features),
      goblins: [],
    })),
  };
}
/** Its content, assembled from the records read there (CLI-10d). */
async function goblinContent() {
  const records = new Map(goblins.recordedRecords.map(([k, id, parts]) => [`${k}:${id}`, parts]));
  const { content } = await assembleContent(goblinState().view, (kind, id) =>
    Promise.resolve((records.get(`${kind}:${id}`) ?? ["0x0", "0x0"]).map(BigInt)),
  );
  return content;
}

describe("the mirror on the recorded goblin world (CLI-10d)", () => {
  const chain = extractOutcome(goblins.recordedPlayed);
  const noLog = () => {
    throw new Error("no parity record expected");
  };

  it("predicts the real Wait with the assembled content: the goblin sets compared, no mismatch", async () => {
    const state = { ...goblinState(), content: await goblinContent() };
    expect(state.content.castes).toHaveLength(1);
    const segment = segmentOf(state);
    expect(segment.words.goblins).toHaveLength(1);
    const result = reconcile(chain, [{ kind: "wait" }], mirrorOf(state), noLog);
    expect(chain.kind === "played" && chain.view.goblins).toHaveLength(1);
    expect(result.mirror).toMatchObject({ kind: "predicted", played: 1, stop: Stop.None });
    expect(result.mismatches).toEqual([]);
  });

  it("is no prediction with no content given: the goblin's caste is read first", () => {
    const predict = mirrorOf(goblinState());
    const result = reconcile(chain, [{ kind: "wait" }], predict, noLog);
    expect(result.mirror).toMatchObject({ kind: "not-mirrored" });
    expect((result.mirror as { reason: string }).reason).toMatch(
      /^not mirrored: no content given, the segment reads a sheet \(.*caste not in content/,
    );
  });

  it("logs a mirror failure where the given content lacks the goblin's caste", async () => {
    const content = { ...(await goblinContent()), castes: [] };
    const logged: unknown[] = [];
    const result = reconcile(
      chain,
      [{ kind: "wait" }],
      mirrorOf({ ...goblinState(), content }),
      (r) => logged.push(r),
    );
    expect(result.mirror).toMatchObject({ kind: "not-mirrored" });
    expect(logged).toMatchObject([{ kind: "grimworld.mirror-failure" }]);
  });
});

/** `segment2.jsonl`'s `combat` rows that call `ActionLibrary::act` (CLI-02g-E, CLI-10g). */
const SEGMENT2 = new URL("../../../../contracts/logic/vectors/segment2.jsonl", import.meta.url);
const ACT_ROWS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 44];

/** The segment of `segment2.jsonl`'s row `id`, the calls it recorded, and the recording. */
function segment2Row(id: number) {
  const rows = readFileSync(SEGMENT2, "utf8")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line) as { id: number; case: string[]; ok: string[] });
  const felts = (row: { case?: string[]; ok?: string[] }, key: "case" | "ok") =>
    new Felts((row[key] ?? []).map(BigInt));
  const head = felts(rows[0]!, "ok");
  const content = readContent(head);
  head.end();
  const read = felts(rows[id]!, "case");
  const words = readWords(read);
  const area = readArea(read);
  const level = read.u8();
  const ground = readGround(read);
  const [owed, weight] = [read.u8(), read.u8()];
  const actions = read.span(() => readAction(read));
  const calls: Call[] = read.span(() => readCall(read));
  read.end();
  return {
    segment: { words, content, area, level, ground, owed, weight, actions },
    calls,
    recorded: rows[id]!.ok.map(BigInt),
  };
}

describe("the native action class on segment2.jsonl's act rows (CLI-10g)", () => {
  it("predicts the rows whose combat needs no ticks, as the contracts recorded them", () => {
    let predicted = 0;
    for (const id of ACT_ROWS) {
      const { segment, calls, recorded } = segment2Row(id);
      expect(
        calls.some((c) => c.kind === "act"),
        `row ${id} calls act`,
      ).toBe(true);
      if (calls.some((c) => c.kind === "ticks")) continue;
      const out = runSegment(segment, nativeClasses);
      expect([
        ...writeWords(out.words),
        ...writeGround(out.ground),
        ...writeDone(out.done),
      ]).toEqual(recorded);
      predicted += 1;
    }
    // The other five (rows with ticks after the action) are the next test's
    expect(predicted).toBe(7);
  });

  it("stays not mirrored where the combat action is followed by ticks", () => {
    const withTicks = ACT_ROWS.filter((id) =>
      segment2Row(id).calls.some((c) => c.kind === "ticks"),
    );
    for (const id of withTicks) {
      expect(() => runSegment(segment2Row(id).segment, nativeClasses), `row ${id}`).toThrow(
        "TickLibrary::ticks",
      );
      expect(() => runSegment(segment2Row(id).segment, unportedClasses), `row ${id}`).toThrow(
        NotMirrored,
      );
    }
  });
});
