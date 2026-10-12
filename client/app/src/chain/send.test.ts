import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AccountError, type ExecutionId, type ExecutionStatus } from "../account/types";
import type { PlayAction } from "../preview/actions";
import { INSTANCES, playedTrace, view as fixtureView } from "../preview/fixtures";
import { mirrorOf } from "../preview/mirror";
import type { BlockId, Reader } from "../preview/read";
import * as goblins from "../preview/recorded-goblins";
import { type InvokeTrace, Stop, extractOutcome } from "../preview/trace";
import { type InstanceView, type RegionChunk, decodeInstanceView } from "../preview/view";
import {
  type ChainState,
  NO_FUNDS,
  type SendDeps,
  type SentRecord,
  createSentReads,
  differences,
  readState,
  sendBatch,
} from "./send";

const WAIT: PlayAction = { kind: "wait" };
const ID = "0x7a5" as ExecutionId;
const BLOCK = "0xb10c";
const REGISTRY = "0x0456";

/** The recorded goblin world (`recorded-goblins.ts`): before the Wait, and the Wait's trace. */
const before = (): InstanceView => decodeInstanceView(goblins.recordedBefore.view.map(BigInt));
const region = (): RegionChunk[] =>
  goblins.recordedBefore.region.map((c) => ({
    chunk: c.chunk,
    kind: c.kind as RegionChunk["kind"],
    terrain: BigInt(c.terrain),
    features: BigInt(c.features),
    goblins: [],
  }));
const records = new Map(goblins.recordedRecords.map(([k, id, parts]) => [`${k}:${id}`, parts]));
const recordedId = { instanceId: before().instanceId, adventurerId: 1 };

/** A reader of the recorded world, every block it is pinned to noted. */
function recordedReader(blocks: BlockId[], at: BlockId = "pre_confirmed"): Reader {
  blocks.push(at);
  return {
    call: () => Promise.reject(new Error("no raw call expected")),
    instanceState: async () => before(),
    region: async () => region(),
    placement: async () => ({
      instanceId: recordedId.instanceId,
      member: goblins.recordedBefore.member,
      inside: true,
    }),
    contentVersion: async () => 1,
    record: async (_registry, kind, id) =>
      (records.get(`${kind}:${id}`) ?? ["0x0", "0x0"]).map(BigInt),
  };
}

async function recordedState(): Promise<ChainState> {
  return readState(recordedReader([]), {
    instances: INSTANCES,
    registry: REGISTRY,
    ...recordedId,
  });
}

/** An account sending one execution, its statuses in turn; every call noted. */
function account(statuses: ExecutionStatus[] = ["succeeded"], refusal?: unknown) {
  const events: string[] = [];
  const sent: unknown[] = [];
  return {
    events,
    sent,
    account: {
      async execute(calls: readonly unknown[]) {
        events.push("execute");
        sent.push(calls);
        if (refusal !== undefined) throw refusal;
        return ID;
      },
      async status() {
        events.push("status");
        return statuses.shift() ?? "succeeded";
      },
    },
  };
}

function deps(
  over: Partial<SendDeps> & { trace?: InvokeTrace } = {},
): SendDeps & { blocks: BlockId[]; logged: SentRecord[] } {
  const blocks: BlockId[] = [];
  const logged: SentRecord[] = [];
  const trace = over.trace ?? goblins.recordedPlayed;
  return {
    account: account().account,
    assertChain: async () => undefined,
    reads: { trace: async () => trace, blockOf: async () => BLOCK },
    readerAt: (block) => recordedReader(blocks, block),
    registry: REGISTRY,
    log: () => {
      throw new Error("no parity record expected");
    },
    sentLog: (record) => logged.push(record),
    poll: 0,
    ...over,
    blocks,
    logged,
  };
}

// No test of the sender touches the network: any fetch fails the test.
beforeEach(() => {
  vi.stubGlobal("fetch", () => {
    throw new Error("the network was touched");
  });
});
afterEach(() => {
  vi.unstubAllGlobals();
});

describe("sendBatch", () => {
  it("sends the preview's two calls, and reconciles the sent outcome with the same prediction", async () => {
    const state = await recordedState();
    expect(state.mirror.content?.castes).toHaveLength(1);
    const { account: provider, sent, events } = account(["pending", "succeeded"]);
    const d = deps({ account: provider });
    const simulated = extractOutcome(goblins.recordedPlayed);
    const result = await sendBatch(
      { state, actions: [WAIT], predict: mirrorOf(state.mirror), simulated },
      d,
    );
    expect(events).toEqual(["execute", "status", "status"]);
    expect(sent).toEqual([
      [
        {
          to: INSTANCES,
          entrypoint: "play",
          calldata: [recordedId.instanceId, 1n, 0n, 1n, expect.any(BigInt)],
        },
        { to: INSTANCES, entrypoint: "instance_state", calldata: [recordedId.instanceId] },
      ],
    ]);
    expect(result).toMatchObject({
      kind: "sent",
      id: ID,
      blockHash: BLOCK,
      differs: [],
      mirror: { kind: "predicted", played: 1, stop: Stop.None },
      mismatches: [],
    });
    expect(d.logged).toEqual([]);
    if (result.kind !== "sent" || result.chain.kind !== "played") throw new Error("not sent");
    // The state after is the trace's view; the region and the version are read at the receipt's block
    expect(result.after.mirror.view).toEqual(result.chain.view);
    expect(result.after.target.sequence).toBe(result.chain.view.header.sequence);
    expect(result.after.target.sequence).toBe(1);
    expect(d.blocks).toEqual([{ blockHash: BLOCK }]);
  });

  it("refuses before `execute` on a fake chain id SN_MAIN: nothing is sent", async () => {
    const state = await recordedState();
    const { account: provider, events } = account();
    const result = await sendBatch(
      { state, actions: [WAIT], simulated: extractOutcome(goblins.recordedPlayed) },
      deps({
        account: provider,
        // CLI-11a's `assertTestChain` on a node reporting SN_MAIN, faked
        assertChain: async () => {
          throw new Error("chain mode refused: not a test chain (SN_MAIN)");
        },
      }),
    );
    expect(result).toEqual({
      kind: "refused",
      reason: "chain mode refused: not a test chain (SN_MAIN)",
    });
    expect(events).toEqual([]);
  });

  it("logs grimworld.sent-differs when the sent outcome differs from the simulated one", async () => {
    const state = await recordedState();
    const simulated = extractOutcome(goblins.recordedPlayed);
    if (simulated.kind !== "played") throw new Error("not played");
    // What the preview simulated: the batch played on a clock one tick behind the sent one
    const earlier = {
      ...simulated,
      batch: { ...simulated.batch, clock: simulated.batch.clock - 1 },
    };
    const d = deps();
    const result = await sendBatch(
      { state, actions: [WAIT], predict: mirrorOf(state.mirror), simulated: earlier },
      d,
    );
    expect(result).toMatchObject({ kind: "sent", differs: ["batch.clock"] });
    expect(d.logged).toEqual([
      {
        kind: "grimworld.sent-differs",
        actions: [WAIT],
        fields: ["batch.clock"],
        simulated: earlier,
        sent: simulated,
      },
    ]);
  });

  it("says 'no funds' when the provider refuses a fee the burner cannot pay", async () => {
    const state = await recordedState();
    const cause = Object.assign(new Error("Account balance is smaller than the max fee"), {
      code: 54,
    });
    const { account: provider } = account([], new AccountError("refused", { cause }));
    const result = await sendBatch(
      { state, actions: [WAIT], simulated: extractOutcome(goblins.recordedPlayed) },
      deps({ account: provider }),
    );
    expect(result).toEqual({ kind: "refused", reason: NO_FUNDS });
    const other = account([], new AccountError("unavailable")).account;
    expect(
      await sendBatch(
        { state, actions: [WAIT], simulated: extractOutcome(goblins.recordedPlayed) },
        deps({ account: other }),
      ),
    ).toEqual({ kind: "refused", reason: new AccountError("unavailable").message });
  });

  it("reports an execution that failed or never settled, and reads nothing after it", async () => {
    const state = await recordedState();
    const simulated = extractOutcome(goblins.recordedPlayed);
    for (const [statuses, status] of [
      [["pending", "failed"], "failed"],
      [["unknown", "unknown", "unknown"], "unknown"],
    ] as const) {
      const d = deps({ account: account([...statuses]).account, polls: 3 });
      expect(await sendBatch({ state, actions: [WAIT], simulated }, d)).toEqual({
        kind: "unsettled",
        id: ID,
        status,
      });
      expect(d.blocks).toEqual([]);
    }
  });

  it("reads a batch that closed the instance as its outcome, the state after its view", async () => {
    const state = await recordedState();
    const after = fixtureView(13, 4);
    const trace = playedTrace(
      { played: 1, stop: Stop.Defeated, sequence: 4, clock: 13, defeated: true, closed: 2 },
      after,
    );
    const simulated = extractOutcome(trace);
    const d = deps({ trace });
    const result = await sendBatch({ state, actions: [WAIT], simulated }, d);
    expect(result).toMatchObject({
      kind: "sent",
      differs: [],
      chain: { kind: "played", defeated: true, closed: 2, batch: { stop: Stop.Defeated } },
    });
    if (result.kind !== "sent") throw new Error("not sent");
    expect(result.after.mirror.view).toEqual(after);
    expect(result.after.target.sequence).toBe(4);
  });
});

describe("differences", () => {
  it("names each differing leaf as a path", () => {
    expect(
      differences({ a: 1n, b: [1, 2], c: { d: "x" } }, { a: 1n, b: [1, 3], c: { d: "y" } }),
    ).toEqual(["b.1", "c.d"]);
    expect(differences({ kind: "played" }, { kind: "reverted", reason: "r" })).toEqual([
      "kind",
      "reason",
    ]);
    expect(differences(1n, 1n)).toEqual([]);
  });
});

describe("the reads after a send", () => {
  it("reads the trace and the receipt's block of the transaction hash", async () => {
    const trace = playedTrace({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    const requests: { method: string; params: unknown }[] = [];
    const fetch = (async (_url: string, init: { body: string }) => {
      const request = JSON.parse(init.body) as { id: number; method: string; params: unknown };
      requests.push(request);
      const result =
        request.method === "starknet_traceTransaction"
          ? trace
          : { block_hash: BLOCK, block_number: 9 };
      return { json: async () => ({ jsonrpc: "2.0", id: request.id, result }) };
    }) as unknown as typeof globalThis.fetch;
    const reads = createSentReads("http://127.0.0.1:5050", fetch);
    expect(await reads.trace(ID)).toEqual(trace);
    expect(await reads.blockOf(ID)).toBe(BLOCK);
    expect(requests).toEqual([
      expect.objectContaining({
        method: "starknet_traceTransaction",
        params: { transaction_hash: ID },
      }),
      expect.objectContaining({
        method: "starknet_getTransactionReceipt",
        params: { transaction_hash: ID },
      }),
    ]);
  });

  it("refuses a receipt that names no block (a pre-confirmed one)", async () => {
    const fetch = (async (_url: string, init: { body: string }) => {
      const { id } = JSON.parse(init.body) as { id: number };
      return { json: async () => ({ jsonrpc: "2.0", id, result: { transaction_hash: ID } }) };
    }) as unknown as typeof globalThis.fetch;
    await expect(createSentReads("http://127.0.0.1:5050", fetch).blockOf(ID)).rejects.toThrow(
      "the receipt names no block",
    );
  });
});
