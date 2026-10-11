import { hash } from "starknet";
import { describe, expect, it } from "vitest";
import { encodeBatch } from "./actions";
import { executeCalldata, previewCalls, selector } from "./calls";
import { eventSelector } from "./trace";

const target = {
  instances: "0x0123",
  instanceId: (7n << 32n) | 3n,
  adventurerId: 41,
  sequence: 3,
  version: 2,
};

describe("selectors", () => {
  it("are sn_keccak of the entrypoint and event names", () => {
    for (const [name, value] of Object.entries({ ...selector, ...eventSelector })) {
      expect(BigInt(hash.getSelectorFromName(name)), name).toBe(value);
    }
  });
});

describe("previewCalls", () => {
  it("is play with the packed batch, then instance_state of the same instance", () => {
    const actions = [{ kind: "move", direction: 1 } as const, { kind: "wait" } as const];
    expect(previewCalls(target, actions)).toEqual([
      {
        to: "0x0123",
        entrypoint: "play",
        calldata: [target.instanceId, 41n, 3n, 2n, encodeBatch(actions)],
      },
      { to: "0x0123", entrypoint: "instance_state", calldata: [target.instanceId] },
    ]);
    // 2 actions, Move North-East (1 × 8) at bit 4, Wait (2) at bit 28
    expect(encodeBatch(actions)).toBe(2n + 8n * 0x10n + 2n * 0x10000000n);
  });

  it("is undefined for a batch that does not encode", () => {
    expect(previewCalls(target, [])).toBeUndefined();
    expect(previewCalls(target, [{ kind: "move", direction: 6 }])).toBeUndefined();
  });
});

describe("executeCalldata", () => {
  it("is a Cairo 1 account's multicall: count, then to, selector, length, calldata", () => {
    const calls = previewCalls(target, [{ kind: "wait" }])!;
    expect(executeCalldata(calls)).toEqual([
      2n,
      0x123n,
      selector.play,
      5n,
      target.instanceId,
      41n,
      3n,
      2n,
      1n + 2n * 0x10n,
      0x123n,
      selector.instance_state,
      1n,
      target.instanceId,
    ]);
  });

  it("refuses an entrypoint it has no selector for", () => {
    expect(() => executeCalldata([{ to: "0x1", entrypoint: "loot", calldata: [] }])).toThrow(
      /loot/,
    );
  });
});
