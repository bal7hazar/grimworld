import { describe, expect, it } from "vitest";
import { blockId, createReader } from "./read";

const REGISTRY = "0x0456";

describe("createReader's block (CLI-11b)", () => {
  it("sends `{ block_hash }` for a hash, and a tag as it is", async () => {
    const blocks: unknown[] = [];
    const fetch = (async (_url: string, init: { body: string }) => {
      const request = JSON.parse(init.body) as { id: number; params: { block_id: unknown } };
      blocks.push(request.params.block_id);
      return { json: async () => ({ jsonrpc: "2.0", id: request.id, result: ["0x3"] }) };
    }) as unknown as typeof globalThis.fetch;
    const nodeUrl = "http://127.0.0.1:5050";
    expect(
      await createReader({ nodeUrl, block: { blockHash: "0x0B10C" }, fetch }).contentVersion(
        REGISTRY,
      ),
    ).toBe(3);
    await createReader({ nodeUrl, fetch }).contentVersion(REGISTRY);
    await createReader({ nodeUrl, block: "latest", fetch }).contentVersion(REGISTRY);
    expect(blocks).toEqual([{ block_hash: "0xb10c" }, "pre_confirmed", "latest"]);
    expect(blockId({ blockHash: "0x00ff" })).toEqual({ block_hash: "0xff" });
  });
});
