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
  artefact?: { run: string };
  classes: { [name: string]: string };
  contracts: { [name: string]: string };
}

/**
 * The newest record: by the date in the file name, then, within a day, by the run id of its CI
 * artefact (GitHub run ids only increase, and a later deployment is built from a later artefact).
 */
function newestRecord(records: { file: string; run: string }[]): string {
  const keyed = records.map(({ file, run }) => {
    const id = /\/actions\/runs\/(\d+)$/.exec(run)?.[1];
    if (id === undefined) throw new Error(`${file}: artefact.run has no parsable run id: ${run}`);
    return { file, date: file.slice(0, 10), id: BigInt(id) };
  });
  const newer = (a: (typeof keyed)[number], b: (typeof keyed)[number]) =>
    a.date !== b.date ? a.date > b.date : a.id > b.id;
  const first = keyed[0];
  if (first === undefined) throw new Error("no Sepolia record");
  return keyed.reduce((best, r) => (newer(r, best) ? r : best), first).file;
}

const record = JSON.parse(readFileSync(root(SEPOLIA.record), "utf8")) as SepoliaRecord;

describe("networks.ts's Sepolia entry (CLI-11e1, D-154)", () => {
  it("is copied from the newest Sepolia record: a new record fails here until the entry follows", () => {
    const records = readdirSync(root("deployments/sepolia"))
      .filter((name) => name.endsWith(".json"))
      .map((file) => ({
        file,
        run:
          (JSON.parse(readFileSync(root(`deployments/sepolia/${file}`), "utf8")) as SepoliaRecord)
            .artefact?.run ?? "",
      }));
    expect(`deployments/sepolia/${newestRecord(records)}`).toBe(SEPOLIA.record);
  });

  it("orders two records of one day by their artefact's run id, not by short sha", () => {
    const run = (id: number) => `https://github.com/o/r/actions/runs/${id}`;
    const records = [
      { file: "2026-10-15-c25a426.json", run: run(38682210121) },
      { file: "2026-10-15-a1b1d16.json", run: run(38733807799) },
      { file: "2026-10-14-ffffff0.json", run: run(99999999999) },
    ];
    expect(newestRecord(records)).toBe("2026-10-15-a1b1d16.json");
    expect(() => newestRecord([{ file: "2026-10-15-0000000.json", run: "none" }])).toThrow(
      "2026-10-15-0000000.json",
    );
    expect(() => newestRecord([{ file: "2026-10-15-1111111.json", run: "" }])).toThrow(
      "2026-10-15-1111111.json",
    );
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
