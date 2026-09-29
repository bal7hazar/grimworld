import { describe, expect, it } from "vitest";
import { assertLocal } from "./node.ts";

// Offline (run by `pnpm test`): the scenario's sending module refuses any node but this machine's.
describe("the local-node guard", () => {
  it("accepts 127.0.0.1 and localhost only", () => {
    expect(assertLocal("http://127.0.0.1:5050")).toBe("http://127.0.0.1:5050");
    expect(assertLocal("http://localhost:5050/rpc")).toBe(
      "http://localhost:5050/rpc",
    );
    for (const url of [
      "https://starknet-sepolia.public.blastapi.io/rpc/v0_10",
      "https://free-rpc.nethermind.io/sepolia-juno/",
      "http://127.0.0.2:5050",
      "http://localhost.example.com:5050",
      "http://user:pass@example.com@127.0.0.1.example.com/",
      "http://[::1]:5050",
    ]) {
      expect(() => assertLocal(url)).toThrow(/refused/);
    }
    expect(() => assertLocal(undefined)).toThrow(/NODE_URL is not set/);
  });
});
