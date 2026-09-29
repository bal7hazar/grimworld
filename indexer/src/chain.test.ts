import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import {
  BadAnswer,
  Chain,
  RpcError,
  httpRpc,
  parseRpcUrl,
  redact,
  type BlockResult,
} from "./chain.ts";
import { FakeNode, HUB, MARKET, ev } from "./testing/fake-node.ts";

const accepted: BlockResult = {
  status: "ACCEPTED_ON_L2",
  block_hash: "0xb1",
  parent_hash: "0xb0",
  block_number: 1,
  transaction_commitment: "0x1",
  event_commitment: "0x2",
  receipt_commitment: "0x3",
  state_diff_commitment: "0x4",
};

describe("block headers", () => {
  it("identify an accepted block by hash and its four commitments", () => {
    expect(Chain.header(accepted, 1)).toEqual({
      number: 1,
      hash: "0xb1",
      parent: "0xb0",
      commitments: "0x1,0x2,0x3,0x4",
    });
  });

  it("refuse a pre-confirmed or hash-less block (never indexed)", () => {
    expect(Chain.header({ ...accepted, status: "PRE_CONFIRMED" }, 1)).toBe(
      null,
    );
    expect(Chain.header({ ...accepted, block_hash: undefined }, 1)).toBe(null);
  });

  it("refuse a block of another height than asked", () => {
    expect(() => Chain.header(accepted, 2)).toThrow(BadAnswer);
    expect(() =>
      Chain.header({ ...accepted, block_number: undefined }, 1),
    ).toThrow(/answered block undefined for block 1/);
  });

  it("refuse an accepted block without its parent or any of its commitments", () => {
    for (const key of [
      "transaction_commitment",
      "event_commitment",
      "receipt_commitment",
      "state_diff_commitment",
      "parent_hash",
    ] as const) {
      expect(() => Chain.header({ ...accepted, [key]: undefined }, 1)).toThrow(
        /identity is unknown/,
      );
      expect(() =>
        Chain.header({ ...accepted, [key]: null } as BlockResult, 1),
      ).toThrow(BadAnswer);
    }
  });

  it("reads through the node, and refuses a node that answers another height", async () => {
    const node = new FakeNode();
    node.mine();
    const chain = new Chain(node.rpc, { hub: HUB, market: MARKET });
    expect((await chain.header(1))?.number).toBe(1);
    expect(await chain.header(9)).toBe(null);
    node.tamper = (method, _params, result) =>
      method === "starknet_getBlockWithTxHashes"
        ? { ...(result as object), block_number: 0 }
        : result;
    await expect(chain.header(1)).rejects.toThrow(
      /answered block 0 for block 1/,
    );
  });

  it("refuse events reported for another block number", async () => {
    const node = new FakeNode();
    node.mine([ev.located(1, 2)]);
    const chain = new Chain(node.rpc, { hub: HUB, market: MARKET });
    const block = (await chain.header(1))!;
    node.tamper = (method, _params, result) =>
      method === "starknet_getEvents"
        ? {
            events: (result as { events: object[] }).events.map((event) => ({
              ...event,
              block_number: 7,
            })),
          }
        : result;
    await expect(chain.events(block)).rejects.toThrow(BadAnswer);
  });
});

describe("secrets in logs", () => {
  const url = "https://user:pw@rpc.example.com/v0_10/SECRETKEY?key=SECRETQUERY";

  it("redact logs no part of the URL, the host included: a label and 8 hex of its sha256 (GPT 3, fix loop 2)", () => {
    const inHost = "https://SECRETHOST.rpc.example.com/";
    const label = redact(inHost);
    expect(label).toMatch(/^rpc [0-9a-f]{8}$/);
    expect(label).toBe(
      `rpc ${createHash("sha256").update(inHost).digest("hex").slice(0, 8)}`,
    );
    for (const secret of [
      inHost,
      url,
      "http://127.0.0.1:5050",
      "not a url SECRETKEY",
      "ftp://SECRETKEY@host/",
    ]) {
      const text = redact(secret);
      expect(text).toMatch(/^rpc [0-9a-f]{8}$/);
      for (const part of ["SECRET", "example", "127.0.0.1", "5050", "http"]) {
        expect(text).not.toContain(part);
      }
    }
    // Two configurations are told apart; the same one always has the same label.
    expect(redact(url)).not.toBe(label);
    expect(redact(inHost)).toBe(label);
  });

  it("parseRpcUrl accepts http(s) only", () => {
    expect(parseRpcUrl(url)?.host).toBe("rpc.example.com");
    expect(parseRpcUrl("ftp://host/")).toBe(null);
    expect(parseRpcUrl("//[")).toBe(null);
  });

  it("an RPC error carries the method and code, never the provider's text", () => {
    const error = new RpcError("starknet_getEvents", {
      code: 24,
      message: "Block not found for https://rpc.example.com/SECRETKEY",
    });
    expect(error.message).toBe("starknet_getEvents: JSON-RPC error 24");
  });

  it("a transport error carries the method and the error code, never the URL", async () => {
    const rpc = httpRpc("http://127.0.0.1:1/SECRETKEY?key=SECRETQUERY");
    const error = await rpc("starknet_blockHashAndNumber", []).catch(
      (e: Error) => e,
    );
    expect((error as Error).message).toMatch(
      /^starknet_blockHashAndNumber: transport error /,
    );
    expect((error as Error).message).not.toMatch(/SECRET|127\.0\.0\.1/);
  });
});
