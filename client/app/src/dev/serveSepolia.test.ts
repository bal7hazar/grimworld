import { describe, expect, it } from "vitest";
import { DEFAULT_SEPOLIA_RPC, serveSepolia } from "./serveSepolia";

describe("serveSepolia (CLI-11e1)", () => {
  it("serves the default endpoint without the setting", () => {
    for (const setting of [undefined, ""]) {
      expect(serveSepolia(setting)).toEqual({
        status: 200,
        body: JSON.stringify({ node_url: DEFAULT_SEPOLIA_RPC }),
      });
    }
  });

  it("serves the setting when it is a keyless https URL", () => {
    expect(serveSepolia("https://sepolia.example.org/rpc")).toEqual({
      status: 200,
      body: JSON.stringify({ node_url: "https://sepolia.example.org/rpc" }),
    });
  });

  it("serves nothing for a keyed or http setting: never the default in its place", () => {
    for (const setting of [
      "http://sepolia.example.org/rpc",
      "https://sepolia.example.org/rpc?apikey=key",
      "https://user:key@sepolia.example.org/rpc",
      "not a url",
    ]) {
      expect(serveSepolia(setting), setting).toEqual({ status: 404 });
    }
  });
});
