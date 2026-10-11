import { describe, expect, it } from "vitest";
import { INSTANCE_ID, playedTrace, revertedTrace, view } from "./fixtures";
import { recordedBefore, recordedPlayed, recordedReverted } from "./recorded";
import {
  type FunctionInvocation,
  Outcome,
  Stop,
  TraceError,
  eventSelector,
  extractOutcome,
  panicReason,
} from "./trace";
import { decodeInstanceView, encodeInstanceView, unpackHeader } from "./view";

describe("extractOutcome", () => {
  it("decodes a successful trace: BatchPlayed, the events under play, the view after", () => {
    const after = view(14, 5);
    const outcome = extractOutcome(
      playedTrace(
        {
          played: 2,
          stop: Stop.None,
          sequence: 5,
          clock: 14,
          killed: [{ entity: 24, caste: 3, tile: 0x0102, by: 0 }],
          revealed: [16],
        },
        after,
      ),
    );
    expect(outcome).toEqual({
      kind: "played",
      batch: {
        instanceId: INSTANCE_ID,
        adventurerId: 41,
        from: 3,
        played: 2,
        stop: Stop.None,
        sequence: 5,
        clock: 14,
        version: 1,
      },
      killed: [{ entity: 24, caste: 3, tile: 0x0102, by: 0 }],
      revealed: [16],
      defeated: false,
      closed: undefined,
      view: after,
    });
  });

  it("reads a defeat and the instance's closing (an event of play's own frame)", () => {
    const outcome = extractOutcome(
      playedTrace({
        played: 1,
        stop: Stop.Defeated,
        sequence: 4,
        clock: 13,
        defeated: true,
        closed: Outcome.Defeated,
      }),
    );
    expect(outcome.kind === "played" && [outcome.defeated, outcome.closed]).toEqual([
      true,
      Outcome.Defeated,
    ]);
  });

  it("surfaces a revert's panic reason as the outcome", () => {
    const trace = revertedTrace("Instances: not controller");
    expect(extractOutcome(trace)).toEqual({
      kind: "reverted",
      reason: "Instances: not controller",
      raw: (trace.execute_invocation as { revert_reason: string }).revert_reason,
    });
  });

  it("leaves out the events of a call that reverted and was caught, and of its subtree", () => {
    const trace = playedTrace({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    const execute = trace.execute_invocation as Exclude<
      typeof trace.execute_invocation,
      { revert_reason: string }
    >;
    const [play, state] = execute.calls;
    const killed = (entity: number) => ({
      order: 90 + entity,
      keys: [`0x${eventSelector.GoblinKilled.toString(16)}`, `0x${INSTANCE_ID.toString(16)}`],
      data: [entity, 3, 7, 0].map((felt) => `0x${felt.toString(16)}`),
    });
    const caught = {
      result: [],
      is_reverted: true,
      events: [killed(30)],
      calls: [{ result: [], calls: [], events: [killed(31)] }],
    };
    const kept = { result: [], calls: [], events: [killed(32)] };
    const outcome = extractOutcome({
      execute_invocation: {
        ...execute,
        calls: [{ ...play!, calls: [...play!.calls, caught, kept] }, state!],
      },
    });
    expect(outcome.kind === "played" && outcome.killed.map((k) => k.entity)).toEqual([32]);
  });

  it("refuses a trace without BatchPlayed or with a call missing", () => {
    const trace = playedTrace({ played: 0, stop: Stop.None, sequence: 3, clock: 12 });
    const execute = trace.execute_invocation as Exclude<
      typeof trace.execute_invocation,
      { revert_reason: string }
    >;
    const [play, state] = execute.calls;
    expect(() => extractOutcome({ execute_invocation: { ...execute, calls: [play!] } })).toThrow(
      TraceError,
    );
    expect(() =>
      extractOutcome({
        execute_invocation: { ...execute, calls: [{ ...play!, calls: [] }, state!] },
      }),
    ).toThrow(/no BatchPlayed/);
  });
});

// Traces recorded on starknet-devnet (`recorded.ts`, preview.node.test.ts), beside the spec-shaped ones
describe("extractOutcome on recorded traces", () => {
  it("decodes a real Wait: BatchPlayed from PlayLibrary's frame, the view after", () => {
    const outcome = extractOutcome(recordedPlayed);
    if (outcome.kind !== "played") throw new Error("not played");
    expect(outcome.batch).toEqual({
      instanceId: (1n << 32n) | 1n,
      adventurerId: 1,
      from: 0,
      played: 1,
      stop: Stop.None,
      sequence: 1,
      clock: 1,
      version: outcome.batch.version,
    });
    expect([outcome.killed, outcome.revealed, outcome.defeated, outcome.closed]).toEqual([
      [],
      [],
      false,
      undefined,
    ]);
    expect([outcome.view.header.sequence, outcome.view.header.clock]).toEqual([1, 1]);
    // The Wait changed the header alone: the member's words are those before it
    const before = decodeInstanceView(recordedBefore.view.map(BigInt));
    expect(outcome.view.members).toEqual(before.members);
    expect(encodeInstanceView(outcome.view)).toEqual(
      (recordedPlayed.execute_invocation as FunctionInvocation).calls[1]!.result.map(BigInt),
    );
  });

  it("reads a real revert's reason out of the node's call stack", () => {
    expect(extractOutcome(recordedReverted)).toMatchObject({
      kind: "reverted",
      reason: "not controller",
    });
  });
});

describe("panicReason", () => {
  it("takes the first short string that is not a frame of the call stack", () => {
    expect(
      panicReason(
        "(0x1 ('ENTRYPOINT_FAILED'), 0x2 ('Play: bad sequence'), 0x3 ('ENTRYPOINT_FAILED'))",
      ),
    ).toBe("Play: bad sequence");
  });

  it("keeps the whole text when it quotes none", () => {
    expect(panicReason("  Out of gas \n")).toBe("Out of gas");
  });
});

describe("InstanceView", () => {
  it("round-trips through its Serde felts", () => {
    expect(decodeInstanceView(encodeInstanceView(view()))).toEqual(view());
  });

  it("decodes the goblins and the location's extent (VIEW-01, instances.cairo :136-146)", () => {
    const felts = encodeInstanceView(view());
    // ... roster (0 pages), goblins (2 × 4 felts), width, height, level_min
    expect(felts.slice(-12)).toEqual([
      2n,
      24n,
      0n,
      view().goblins[0]!.state,
      view().goblins[0]!.timers,
      25n,
      1n,
      0x30n,
      0x31n,
      3n,
      3n,
      1n,
    ]);
    expect(decodeInstanceView(felts)).toMatchObject({
      goblins: [
        { entity: 24, derived: false },
        { entity: 25, derived: true, state: 0x30n, timers: 0x31n },
      ],
      unloadable: false,
      width: 3,
      height: 3,
      levelMin: 1,
    });
  });

  it("reads the one UNLOADABLE marker as the unloadable flag, not as a goblin", () => {
    const marker = { ...view(), goblins: [], unloadable: true };
    const felts = encodeInstanceView(marker);
    expect(felts.slice(-8)).toEqual([1n, 0n, 0n, 0n, 0n, 3n, 3n, 1n]);
    expect(decodeInstanceView(felts)).toEqual(marker);
  });

  it("reads the empty list (no PlayLibrary set) and an id that answers nothing", () => {
    const empty = { ...view(), goblins: [] };
    expect(decodeInstanceView(encodeInstanceView(empty))).toEqual(empty);
    expect(decodeInstanceView(encodeInstanceView(empty))).toMatchObject({ unloadable: false });
    // The zeros `instance_state` answers for a stale id: no span has an item, the extent is 0
    const nothing = decodeInstanceView([5n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n]);
    expect(nothing).toMatchObject({
      goblins: [],
      unloadable: false,
      width: 0,
      height: 0,
      levelMin: 0,
    });
  });

  it("refuses a goblin that is not a GoblinView, and a width beyond a u8", () => {
    const felts = encodeInstanceView(view());
    expect(() =>
      decodeInstanceView(felts.map((f, i) => (i === felts.length - 6 ? 2n : f))),
    ).toThrow(RangeError);
    expect(() => decodeInstanceView([...felts.slice(0, -3), 256n, 3n, 1n])).toThrow(RangeError);
  });

  it("refuses a felt left over or missing", () => {
    const felts = encodeInstanceView(view());
    expect(() => decodeInstanceView([...felts, 0n])).toThrow(RangeError);
    expect(() => decodeInstanceView(felts.slice(0, -1))).toThrow(RangeError);
  });

  it("unpacks the header's fields, LIVE removed (HeaderStorePacking)", () => {
    const word =
      7n +
      (5n << 32n) +
      (14n << 64n) +
      (0x0203n << 96n) +
      (1n << 112n) +
      (1n << 120n) +
      ((2n +
        (3n << 8n) +
        (4n << 16n) +
        (1n << 24n) +
        (9n << 32n) +
        (8n << 40n) +
        (0x0506n << 48n)) <<
        128n) +
      (1n << 250n);
    expect(unpackHeader(word)).toEqual({
      generation: 7,
      sequence: 5,
      clock: 14,
      location: 0x0203,
      status: 1,
      members: 1,
      tasks: 2,
      revealedCount: 3,
      rosterCount: 4,
      flags: 1,
      entryChunk: 9,
      entryTile: 8,
      gate: 0x0506,
    });
  });
});
