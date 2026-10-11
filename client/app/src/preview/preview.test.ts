import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { BatchAction } from "./actions";
import { INSTANCES, INSTANCE_ID, playedTrace, revertedTrace } from "./fixtures";
import { mirrorOf, unpackLocation } from "./mirror";
import { recordedBefore, recordedPlayed, recordedReverted } from "./recorded";
import { previewBatch, refusals } from "./preview";
import type { Simulator } from "./rpc";
import { type InvokeTrace, Stop } from "./trace";
import { type RegionChunk, decodeInstanceView } from "./view";

const target = {
  instances: INSTANCES,
  instanceId: INSTANCE_ID,
  adventurerId: 41,
  sequence: 3,
  version: 1,
};

/** A simulator answering one trace, recording the calls it was given. */
function fake(trace: Parameters<typeof playedTrace>[0] | string): Simulator & { calls: unknown[] } {
  const calls: unknown[] = [];
  return {
    calls,
    async simulate(batch) {
      calls.push(batch);
      return typeof trace === "string" ? revertedTrace(trace) : playedTrace(trace);
    },
  };
}

// No test of the preview touches the network: any fetch fails the test.
beforeEach(() => {
  vi.stubGlobal("fetch", () => {
    throw new Error("the network was touched");
  });
});
afterEach(() => {
  vi.unstubAllGlobals();
});

describe("previewBatch", () => {
  it("refuses a batch holding a Fate action before simulating it", async () => {
    const simulator = fake({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    const actions: BatchAction[] = [{ kind: "move", direction: 0 }, { kind: "loot" }];
    expect(await previewBatch({ ...target, actions }, { simulator })).toEqual({
      kind: "refused",
      reason: `loot ${refusals.FATE}`,
    });
    expect(simulator.calls).toEqual([]);
  });

  it("refuses a batch that does not encode before simulating it", async () => {
    const simulator = fake({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    const actions: BatchAction[] = Array.from({ length: 11 }, () => ({ kind: "wait" }));
    expect(await previewBatch({ ...target, actions }, { simulator })).toEqual({
      kind: "refused",
      reason: refusals.ENCODING,
    });
    expect(simulator.calls).toEqual([]);
  });

  it("simulates the two calls and returns the chain's outcome, the mirror unwired", async () => {
    const simulator = fake({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    const preview = await previewBatch({ ...target, actions: [{ kind: "wait" }] }, { simulator });
    expect(simulator.calls).toHaveLength(1);
    expect(preview).toMatchObject({
      kind: "simulated",
      chain: { kind: "played", batch: { played: 1, stop: Stop.None, clock: 13 } },
      mirror: { kind: "not-mirrored", reason: "no mirror wired" },
      mismatches: [],
    });
  });

  it("returns a reverted play's reason as its outcome, not as an exception", async () => {
    const preview = await previewBatch(
      { ...target, actions: [{ kind: "wait" }] },
      { simulator: fake("Play: not in this instance") },
    );
    expect(preview).toMatchObject({
      kind: "simulated",
      chain: { kind: "reverted", reason: "Play: not in this instance" },
      mismatches: [],
    });
  });

  it("previews a recorded devnet Wait with the mirror wired: predicted, no mismatch", async () => {
    const log = vi.fn();
    const recorded = (trace: InvokeTrace): Simulator => ({ simulate: async () => trace });
    const predict = mirrorOf({
      view: decodeInstanceView(recordedBefore.view.map(BigInt)),
      location: unpackLocation(recordedBefore.location.map(BigInt)),
      region: recordedBefore.region.map((c): RegionChunk => ({
        ...c,
        kind: c.kind as RegionChunk["kind"],
        terrain: BigInt(c.terrain),
        features: BigInt(c.features),
        goblins: [],
      })),
      content: { skills: [], potions: [], castes: [] },
    });
    const input = { ...target, instanceId: (1n << 32n) | 1n, adventurerId: 1, sequence: 0 };
    expect(
      await previewBatch(
        { ...input, actions: [{ kind: "wait" }] },
        { simulator: recorded(recordedPlayed), predict, log },
      ),
    ).toMatchObject({
      kind: "simulated",
      chain: { kind: "played", batch: { played: 1, stop: Stop.None, clock: 1 } },
      mirror: { kind: "predicted", played: 1, stop: Stop.None },
      mismatches: [],
    });
    expect(
      await previewBatch(
        { ...input, adventurerId: 2, actions: [{ kind: "wait" }] },
        { simulator: recorded(recordedReverted), predict, log },
      ),
    ).toMatchObject({ chain: { kind: "reverted", reason: "not controller" }, mismatches: [] });
    expect(log).not.toHaveBeenCalled();
  });
});
