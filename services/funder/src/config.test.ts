import { inspect } from "node:util";
import { describe, expect, it } from "vitest";
import { ConfigError, DEFAULTS, SN_MAIN, chainIdOf, readConfig } from "./config.ts";
import { Secret } from "./secret.ts";

const KEY = "0x71d7bb07b9a64f6f78ac4c816aff4da9";
const BASE = {
  FUNDER_RPC_URL: "http://127.0.0.1:5050",
  FUNDER_ACCOUNT_ADDRESS: "0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691",
  FUNDER_PRIVATE_KEY: KEY,
  FUNDER_ACCOUNT_CLASS: "0x01d1777db36cdd06dd62cfde77b1b6ae06412af95d57a13dc40ac77b8a702381",
  FUNDER_NETWORKS: "SN_SEPOLIA",
  FUNDER_STATE_FILE: "/var/lib/funder/ledger.json",
};

function refusal(env: Record<string, string>): string {
  try {
    readConfig(env);
  } catch (error) {
    expect(error).toBeInstanceOf(ConfigError);
    return (error as Error).message;
  }
  throw new Error("accepted");
}

describe("the configuration", () => {
  it("reads the variables by name, with the caps' defaults", () => {
    const config = readConfig(BASE);
    expect(config.networks).toEqual([chainIdOf("SN_SEPOLIA")]);
    expect(config.funderKey.reveal()).toBe(KEY);
    expect(config.amount).toBe(DEFAULTS.amount);
    expect(config.maxFee).toBe(DEFAULTS.maxFee);
    expect(config.dailyBudget).toBe(50);
    expect(config.clientRate).toBe(3);
    expect(config.host).toBe("127.0.0.1");
    expect(Object.isFrozen(config)).toBe(true);
  });

  it.each(["SN_MAIN", "SN_SEPOLIA,SN_MAIN", "0x534e5f4d41494e", "0x0534E5F4D41494E"])(
    "refuses mainnet in the networks: %s",
    (networks) => {
      expect(refusal({ ...BASE, FUNDER_NETWORKS: networks })).toMatch(/mainnet/);
    },
  );

  it("refuses a missing or empty list of networks, and names that are not networks", () => {
    expect(refusal({ ...BASE, FUNDER_NETWORKS: "" })).toMatch(/FUNDER_NETWORKS is not set/);
    expect(refusal({ ...BASE, FUNDER_NETWORKS: " , " })).toMatch(/empty/);
    expect(refusal({ ...BASE, FUNDER_NETWORKS: "sepolia" })).toMatch(/not a network/);
  });

  it("refuses caps that are not positive whole numbers", () => {
    expect(refusal({ ...BASE, FUNDER_DAILY_BUDGET: "0" })).toMatch(/FUNDER_DAILY_BUDGET/);
    expect(refusal({ ...BASE, FUNDER_CLIENT_RATE: "-1" })).toMatch(/FUNDER_CLIENT_RATE/);
    expect(refusal({ ...BASE, FUNDER_DAILY_BUDGET: "10001" })).toMatch(/above/);
    expect(refusal({ ...BASE, FUNDER_AMOUNT: "1.5" })).toMatch(/FUNDER_AMOUNT/);
    expect(refusal({ ...BASE, FUNDER_RPC_URL: "ws://x" })).toMatch(/FUNDER_RPC_URL/);
  });

  it("names the variable of a bad key, never its value", () => {
    for (const bad of ["71d7bb07b9a64f6f78ac4c816aff4da9", "0xnothex71d7bb07", "0x0"]) {
      const message = refusal({ ...BASE, FUNDER_PRIVATE_KEY: bad });
      expect(message).toBe("FUNDER_PRIVATE_KEY is not a hex number");
      expect(message).not.toContain(bad.replace(/^0x/, ""));
    }
    expect(refusal({ ...BASE, FUNDER_PRIVATE_KEY: "" })).toBe("FUNDER_PRIVATE_KEY is not set");
  });

  // Fix loop 1, F-3: without a state file a restart would forget the budget and the rates.
  it("fails closed without a state file, unless development is said explicitly", () => {
    const { FUNDER_STATE_FILE: _, ...without } = BASE;
    void _;
    expect(refusal(without)).toBe(
      "FUNDER_STATE_FILE is not set (FUNDER_EPHEMERAL=1 for development only)",
    );
    expect(refusal({ ...without, FUNDER_STATE_FILE: " " })).toMatch(/FUNDER_STATE_FILE is not set/);
    expect(refusal({ ...without, FUNDER_EPHEMERAL: "true" })).toMatch(/is not set/);
    expect(readConfig({ ...without, FUNDER_EPHEMERAL: "1" }).stateFile).toBeUndefined();
    expect(refusal({ ...BASE, FUNDER_EPHEMERAL: "1" })).toMatch(/both set/);
    expect(readConfig(BASE).stateFile).toBe("/var/lib/funder/ledger.json");
  });

  it("mainnet's chain id is SN_MAIN's", () => {
    expect(chainIdOf("SN_MAIN")).toBe(SN_MAIN);
  });
});

describe("the key as a secret", () => {
  it("prints as [secret] in every way a value becomes text", () => {
    const { funderKey } = readConfig(BASE);
    const texts = [
      `${funderKey}`,
      String(funderKey),
      JSON.stringify({ funderKey }),
      JSON.stringify(readConfig(BASE), (_, v: unknown) => (typeof v === "bigint" ? String(v) : v)),
      inspect(funderKey),
      inspect(readConfig(BASE), { depth: 5, showHidden: true }),
    ];
    for (const text of texts) {
      expect(text).not.toContain(KEY.slice(2));
      expect(text).toContain("[secret]");
    }
  });

  it("knows the forms in which it could be written, the longest first", () => {
    const forms = new Secret(KEY).forms();
    expect(forms).toContain(KEY);
    expect(forms).toContain(KEY.slice(2));
    expect(forms).toContain(KEY.slice(2).padStart(64, "0"));
    expect(forms).toContain(BigInt(KEY).toString(10));
    expect(forms).toContain(KEY.slice(2).toUpperCase());
    for (let i = 1; i < forms.length; i++) {
      expect(forms[i]!.length).toBeLessThanOrEqual(forms[i - 1]!.length);
    }
  });
});
