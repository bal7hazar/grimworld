import { describe, expect, it, vi } from "vitest";
import { logRefusal, readChainParam, refusalLine } from "./params";

const search = (value: string) => `?${new URLSearchParams({ chain: value })}`;

describe("readChainParam (CLI-11 §2.1)", () => {
  it("is none without `chain`, or with it empty: the app stays the sandbox", () => {
    for (const s of ["", "?", "?panel=1", "?fixture=room&zoom=9", "?chain=", "?chain"]) {
      expect(readChainParam(s), s).toEqual({ kind: "none" });
    }
  });

  it("takes an http or https URL on this machine, as written", () => {
    for (const url of [
      "http://127.0.0.1:5050",
      "http://127.0.0.1:20431/",
      "https://localhost:5050/rpc",
      "http://[::1]:5050",
    ]) {
      expect(readChainParam(search(url)), url).toEqual({ kind: "chain", nodeUrl: url });
    }
  });

  it("refuses what is not an http URL", () => {
    for (const url of ["127.0.0.1:5050", "node", "ftp://127.0.0.1/", "javascript:alert(1)"]) {
      expect(readChainParam(search(url)), url).toEqual({ kind: "refused", reason: "not a URL" });
    }
  });

  it("refuses user information, on this machine or not", () => {
    for (const url of [
      "http://alice:s3cret@127.0.0.1:5050",
      "http://alice@localhost:5050",
      "http://:s3cret@127.0.0.1:5050",
      "http://alice:s3cret@node.example.com",
      "http://@127.0.0.1:5050",
    ]) {
      expect(readChainParam(search(url)), url).toEqual({
        kind: "refused",
        reason: "user information",
      });
    }
  });

  it("refuses a host that is not this machine (part 1)", () => {
    for (const url of [
      "http://node.example.com:5050",
      "https://starknet-sepolia.public.blastapi.io",
      "http://10.0.0.2:5050",
      "http://127.0.0.2:5050",
      "http://localhost.example.com",
    ]) {
      expect(readChainParam(search(url)), url).toEqual({
        kind: "refused",
        reason: "not on this machine",
      });
    }
  });

  it("leaves no user or password of a refused value in the line or the record (review t-0231)", () => {
    const param = readChainParam(search("http://alice:s3cret@node.example.com:5050"));
    if (param.kind !== "refused") throw new Error("not refused");
    const log = vi.fn();
    logRefusal(param.reason, log);
    expect(log).toHaveBeenCalledTimes(1);
    const [name, record] = log.mock.calls[0]!;
    expect(name).toBe("grimworld.chain-refused");
    expect(record).toEqual({ line: refusalLine(param.reason), reason: "user information" });
    const written = `${refusalLine(param.reason)} ${JSON.stringify(log.mock.calls)}`;
    for (const secret of ["alice", "s3cret", "node.example.com", "5050"]) {
      expect(written).not.toContain(secret);
    }
  });
});

describe("App.tsx", () => {
  const app = import.meta.glob<string>("../App.tsx", {
    query: "?raw",
    import: "default",
    eager: true,
  })["../App.tsx"]!;

  it("imports only the parameters of the chain mode statically, and the screen dynamically", () => {
    const staticImports = [...app.matchAll(/^import[^;]*from\s+["']([^"']+)["']/gm)].map(
      (m) => m[1],
    );
    expect(staticImports.filter((path) => path!.includes("chain"))).toEqual(["./chain/params"]);
    expect(app).toMatch(/import\(\s*["']\.\/chain\/ChainScreen["']\s*\)/);
    // Without `chain`, the sandbox as before
    expect(app).toMatch(/chain\.kind === "none"\) return <Sandbox \/>/);
  });
});
