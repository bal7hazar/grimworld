import { describe, expect, it } from "vitest";
import { INSTANCE_ID, playedTrace, revertedTrace, view } from "./fixtures";
import { Outcome, Stop, TraceError, extractOutcome, panicReason } from "./trace";
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
