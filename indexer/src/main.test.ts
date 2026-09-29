import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { Store } from "./store.ts";

// The CLI's refusals: each exits 2 before any call to a node (the process is spawned; no network).
const MAIN = fileURLToPath(new URL("./main.ts", import.meta.url));
const dir = mkdtempSync(
  join(fileURLToPath(new URL("..", import.meta.url)), ".tmp-"),
);
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const base = ["--hub", "0x1111", "--market", "0x2222", "--from", "5"];

function cli(args: string[], url = "http://127.0.0.1:1") {
  const result = spawnSync(process.execPath, [MAIN, ...args], {
    env: { INDEXER_RPC_URL: url },
    encoding: "utf8",
    timeout: 20_000,
  });
  return { code: result.status, output: `${result.stdout}${result.stderr}` };
}

describe("the CLI refuses, and says why", () => {
  it("an RPC URL that is not http(s), without printing it (Opus 3)", () => {
    for (const url of [
      "ftp://user:SECRETKEY@rpc.example.com/",
      "not a url SECRETKEY",
      "//[SECRETKEY",
    ]) {
      const { code, output } = cli(
        ["run", ...base, "--db", join(dir, "a.sqlite")],
        url,
      );
      expect(code).toBe(2);
      expect(output).toContain("the RPC URL is not an http(s) URL (not shown)");
      expect(output).not.toContain("SECRETKEY");
    }
  });

  it("--batch 0 and --poll 0 (Opus 5)", () => {
    for (const option of ["--batch", "--poll"]) {
      const { code, output } = cli([
        "run",
        ...base,
        "--db",
        join(dir, "b.sqlite"),
        option,
        "0",
      ]);
      expect(code).toBe(2);
      expect(output).toContain(
        `${option} must be a whole number of at least 1`,
      );
    }
  });

  it("--lot-count and --trade-count of 2^64 or not a whole number (Opus 6)", () => {
    for (const option of ["--lot-count", "--trade-count"]) {
      for (const value of ["18446744073709551616", "1e3", "-1"]) {
        const { code, output } = cli([
          "run",
          ...base,
          "--db",
          join(dir, "c.sqlite"),
          `${option}=${value}`,
        ]);
        expect(code).toBe(2);
        expect(output).toContain(`${option} must be a whole number below 2^64`);
      }
    }
  });

  it("rebuild --from another block than the database was built from, and keeps the database (Opus 7)", () => {
    const db = join(dir, "d.sqlite");
    const store = new Store(db);
    store.open({
      hub: "0x1111",
      market: "0x2222",
      from: 5,
      lotCount: 0n,
      tradeCount: 0n,
    });
    store.close();
    const { code, output } = cli([
      "rebuild",
      "--hub",
      "0x1111",
      "--market",
      "0x2222",
      "--from",
      "9",
      "--db",
      db,
    ]);
    expect(code).toBe(2);
    expect(output).toContain(
      "this database was built from block 5, the contracts' deployment",
    );
    const again = new Store(db);
    expect(again.config()?.from).toBe(5);
    again.close();
  });
});
