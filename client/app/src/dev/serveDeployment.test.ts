import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { serveDeployment } from "./serveDeployment";

// A scratch folder of the system's (removed after the tests).
const scratch = mkdtempSync(join(tmpdir(), "deployment-test-"));
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

const file = (name: string, text: string) => {
  const path = join(scratch, name);
  writeFileSync(path, text);
  return path;
};

const deployment = {
  node_url: "http://127.0.0.1:5050",
  chain_id: "SN_SEPOLIA",
  commit: "4832cef",
  account: "0x64b4",
  classes: { registry: "0x1", hub: "0x2" },
  contracts: { registry: "0x11", tx_hash_fate: "0x12", hub: "0x13", instances: "0x14" },
  adventurer_id: 1,
  instance_id: 4294967297,
  slot: 1,
};

describe("serveDeployment (the dev server's /deployment.json, CLI-11 §2.2)", () => {
  it("serves the deployment's known fields", () => {
    const answer = serveDeployment(file("deployment.json", JSON.stringify(deployment, null, 2)));
    expect(answer.status).toBe(200);
    expect(answer.status === 200 && JSON.parse(answer.body)).toEqual(deployment);
  });

  it("rebuilds the body: any other field, or a field of another type, is dropped", () => {
    const leaky = {
      ...deployment,
      private_key: "0xk",
      account: { address: "0x64b4", private_key: "0xk" },
      classes: { hub: "0x2", key: { private_key: "0xk" } },
      contracts: { ...deployment.contracts, deployer_key: "0xk" },
      slot: 1.5,
    };
    const answer = serveDeployment(file("leaky.json", JSON.stringify(leaky)));
    if (answer.status !== 200) throw new Error("not served");
    expect(answer.body).not.toContain("0xk");
    expect(JSON.parse(answer.body)).toEqual({
      node_url: deployment.node_url,
      chain_id: deployment.chain_id,
      commit: deployment.commit,
      classes: { hub: "0x2" },
      contracts: deployment.contracts,
      adventurer_id: 1,
      instance_id: 4294967297,
    });
  });

  it("serves the build's ids only: mode, bar and belt (CLI-11d3)", () => {
    const build = {
      mode: "full",
      bar: [1, 2, 3, 4, 0, 0, 0, 0],
      belt: [
        { item: 1, count: 2 },
        { item: 23, count: 1 },
      ],
    };
    const full = {
      ...deployment,
      build: {
        ...build,
        belt: [
          { item: 1, count: 2, key: "0xk" },
          { item: 23, count: 1 },
        ],
        pack: [{ item: 1, count: 4 }],
        gold: 260,
        skills: { instant_attack: 1 },
        account: "0xk",
      },
    };
    const answer = serveDeployment(file("full.json", JSON.stringify(full)));
    if (answer.status !== 200) throw new Error("not served");
    expect(answer.body).not.toContain("0xk");
    expect(JSON.parse(answer.body)).toEqual({ ...deployment, build });
    // A build of another shape is dropped whole
    for (const bad of [
      { ...build, bar: ["1"] },
      { ...build, belt: [{ item: 1 }] },
      [build],
      null,
    ]) {
      const shaped = serveDeployment(
        file("bad.json", JSON.stringify({ ...deployment, build: bad })),
      );
      expect(shaped.status === 200 && JSON.parse(shaped.body)).toEqual(deployment);
    }
  });

  it("is 404 without the variable, without the file, or for a file that is not a JSON object", () => {
    expect(serveDeployment(undefined)).toEqual({ status: 404 });
    expect(serveDeployment("")).toEqual({ status: 404 });
    expect(serveDeployment(join(scratch, "missing.json"))).toEqual({ status: 404 });
    expect(serveDeployment(scratch)).toEqual({ status: 404 });
    // A node log named by mistake: not JSON, nothing of it served
    expect(serveDeployment(file("node.log", "Private key: 0xk\n"))).toEqual({ status: 404 });
    expect(serveDeployment(file("list.json", "[1, 2]"))).toEqual({ status: 404 });
    expect(serveDeployment(file("null.json", "null"))).toEqual({ status: 404 });
  });
});
