import { describe, expect, it } from "vitest";
import { executeCalldata, previewCalls } from "./calls";
import { INSTANCES, INSTANCE_ID, playedTrace } from "./fixtures";
import { SimulationError, createRpcSimulator } from "./rpc";
import { Stop, TraceError } from "./trace";

type Request = { method: string; params: Record<string, unknown> };

/** A node answering offline: each method's result, or an error object. */
function node(answers: Record<string, { result?: unknown; error?: unknown }>) {
  const requests: Request[] = [];
  const fetch = (async (_url: string, init: { body: string }) => {
    const request = JSON.parse(init.body) as Request & { id: number };
    requests.push(request);
    const answer = answers[request.method] ?? { error: { code: -32601, message: "no method" } };
    return { json: async () => ({ jsonrpc: "2.0", id: request.id, ...answer }) };
  }) as unknown as typeof globalThis.fetch;
  return { fetch, requests };
}

const calls = previewCalls(
  { instances: INSTANCES, instanceId: INSTANCE_ID, adventurerId: 41, sequence: 3, version: 1 },
  [{ kind: "wait" }],
)!;

describe("createRpcSimulator", () => {
  it("simulates an unsigned v3 invoke with SKIP_VALIDATE and SKIP_FEE_CHARGE on pre_confirmed", async () => {
    const trace = playedTrace({ played: 1, stop: Stop.None, sequence: 4, clock: 13 });
    const { fetch, requests } = node({
      starknet_getNonce: { result: "0x5" },
      starknet_simulateTransactions: {
        result: [{ transaction_trace: trace, fee_estimation: {} }],
      },
    });
    const simulator = createRpcSimulator({ nodeUrl: "http://node", sender: "0xabc", fetch });
    expect(await simulator.simulate(calls)).toEqual(trace);
    expect(requests.map((r) => r.method)).toEqual([
      "starknet_getNonce",
      "starknet_simulateTransactions",
    ]);
    expect(requests[0]!.params).toEqual({ block_id: "pre_confirmed", contract_address: "0xabc" });
    const params = requests[1]!.params as {
      block_id: string;
      simulation_flags: string[];
      transactions: Record<string, unknown>[];
    };
    expect(params.block_id).toBe("pre_confirmed");
    expect(params.simulation_flags).toEqual(["SKIP_VALIDATE", "SKIP_FEE_CHARGE"]);
    expect(params.transactions[0]).toMatchObject({
      type: "INVOKE",
      version: "0x3",
      sender_address: "0xabc",
      nonce: "0x5",
      signature: [],
      calldata: executeCalldata(calls).map((felt) => `0x${felt.toString(16)}`),
    });
  });

  it("throws the node's refusal of the simulation itself", async () => {
    const { fetch } = node({
      starknet_getNonce: { result: "0x0" },
      starknet_simulateTransactions: {
        error: { code: 41, message: "Transaction execution error", data: { execution_error: "x" } },
      },
    });
    const simulator = createRpcSimulator({ nodeUrl: "http://node", sender: "0xabc", fetch });
    const failure = await simulator.simulate(calls).catch((error: unknown) => error);
    expect(failure).toBeInstanceOf(SimulationError);
    expect((failure as SimulationError).code).toBe(41);
  });

  it("refuses an answer without an invoke trace", async () => {
    const { fetch } = node({
      starknet_getNonce: { result: "0x0" },
      starknet_simulateTransactions: { result: [] },
    });
    const simulator = createRpcSimulator({ nodeUrl: "http://node", sender: "0xabc", fetch });
    await expect(simulator.simulate(calls)).rejects.toThrow(TraceError);
  });
});
