import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { CONTRACT_NAMES, SEPOLIA } from "./networks";

/** The repository's root, from `client/app/src/chain/`. */
const root = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));

interface SepoliaRecord {
  chain_id: string;
  commit: string;
  rehearsal: boolean;
  classes: { [name: string]: string };
  contracts: { [name: string]: string };
}

const record = JSON.parse(readFileSync(root(SEPOLIA.record), "utf8")) as SepoliaRecord;

describe("networks.ts's Sepolia entry (CLI-11e1, D-154)", () => {
  it("is copied from the newest Sepolia record: a new record fails here until the entry follows", () => {
    const records = readdirSync(root("deployments/sepolia"))
      .filter((name) => name.endsWith(".json"))
      .sort();
    expect(`deployments/sepolia/${records.at(-1)}`).toBe(SEPOLIA.record);
  });

  it("names its record by the commit's date and short sha, and the record is no rehearsal", () => {
    expect(SEPOLIA.record).toMatch(/^deployments\/sepolia\/\d{4}-\d{2}-\d{2}-([0-9a-f]{7})\.json$/);
    expect(SEPOLIA.record.slice(-12, -5)).toBe(SEPOLIA.commit.slice(0, 7));
    expect(record.rehearsal).toBe(false);
  });

  it("equals the record: chain id, commit, the four addresses and their class hashes", () => {
    const fromRecord = {
      chainId: record.chain_id,
      commit: record.commit,
      record: SEPOLIA.record,
      contracts: Object.fromEntries(
        CONTRACT_NAMES.map((name) => [
          name,
          { address: record.contracts[name], classHash: record.classes[name] },
        ]),
      ),
    };
    expect(SEPOLIA).toEqual(fromRecord);
    expect(Object.keys(record.contracts).sort()).toEqual([...CONTRACT_NAMES].sort());
  });

  it("holds hex values only, and no node URL", () => {
    for (const name of CONTRACT_NAMES) {
      expect(SEPOLIA.contracts[name].address).toMatch(/^0x[0-9a-f]{1,64}$/);
      expect(SEPOLIA.contracts[name].classHash).toMatch(/^0x[0-9a-f]{1,64}$/);
    }
    expect(JSON.stringify(SEPOLIA)).not.toMatch(/https?:/);
  });
});
