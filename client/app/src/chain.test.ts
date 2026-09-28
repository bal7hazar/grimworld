import { describe, expect, it } from "vitest";
import { createProvider } from "./chain";

describe("createProvider", () => {
  it("builds a starknet.js provider without touching the network", () => {
    const provider = createProvider("http://127.0.0.1:5050/rpc");
    expect(provider.channel.nodeUrl).toBe("http://127.0.0.1:5050/rpc");
  });
});
