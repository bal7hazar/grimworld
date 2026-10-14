import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it, vi } from "vitest";
import { type CreditChild, UNUSABLE, createCreditRunner } from "./credit";

// A scratch folder of the system's (removed after the tests).
const scratch = mkdtempSync(join(tmpdir(), "credit-test-"));
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

const file = (name: string, value: unknown) => {
  const path = join(scratch, name);
  writeFileSync(path, typeof value === "string" ? value : JSON.stringify(value));
  return path;
};

const deployment = {
  node_url: "http://127.0.0.1:5050",
  account: "0x64b4",
  contracts: { hub: "0x13" },
  build: { mode: "full", bar: [1, 2, 3, 4, 0, 0, 0, 0], belt: [{ item: 1, count: 2 }] },
};
const FULL = file("deployment.json", deployment);
const OUTPUT = {
  adventurer_id: 2,
  instance_id: 4294967297,
  gold: 260,
  pack: [
    { item: 1, count: 4 },
    { item: 23, count: 2 },
  ],
  instance_read_from: "Instances.placement",
};

/** A fake script: what it was started with, and its end (an exit code and its output), or none. */
function fakeScript(end?: { code: number; stdout?: string; stderr?: string }) {
  const runs: { command: string; args: readonly string[]; cwd: string }[] = [];
  const kills: string[] = [];
  const ends: ((code: number | null) => void)[] = [];
  const spawn = (command: string, args: readonly string[], cwd: string): CreditChild => {
    runs.push({ command, args, cwd });
    const out: ((chunk: unknown) => void)[] = [];
    const err: ((chunk: unknown) => void)[] = [];
    let close: (code: number | null) => void = () => undefined;
    const child: CreditChild = {
      stdout: { on: (_event, listener) => out.push(listener) },
      stderr: { on: (_event, listener) => err.push(listener) },
      on(event: "error" | "close", listener: (value: never) => void) {
        if (event === "close") close = listener as (code: number | null) => void;
        return child;
      },
      kill(signal) {
        kills.push(signal);
        queueMicrotask(() => close(null));
        return true;
      },
    };
    const finish = (code: number | null) => {
      if (end && code !== null) {
        out.forEach((listener) => listener(end.stdout ?? ""));
        err.forEach((listener) => listener(end.stderr ?? ""));
      }
      close(code);
    };
    ends.push(finish);
    if (end) queueMicrotask(() => finish(end.code));
    return child;
  };
  return { spawn, runs, kills, ends };
}

const post = (adventurer: unknown) => JSON.stringify({ adventurer });

describe("the dev server's /devnet/credit (CLI-11d3)", () => {
  it("runs the credit-only mode for the adventurer, and answers its known fields", async () => {
    const script = fakeScript({ code: 0, stdout: JSON.stringify(OUTPUT) });
    const runner = createCreditRunner({ deploymentPath: FULL, root: "/repo", spawn: script.spawn });
    const answer = await runner.request("POST", "application/json", post(2));
    expect(answer.status).toBe(200);
    expect(JSON.parse(answer.body)).toEqual({
      adventurer_id: 2,
      instance_id: 4294967297,
      gold: 260,
      pack: OUTPUT.pack,
    });
    expect(script.runs).toEqual([
      {
        command: "python3",
        args: [
          "/repo/scripts/devnet_deploy.py",
          "--credit-only",
          "--deployment",
          FULL,
          "--adventurer",
          "2",
        ],
        cwd: "/repo",
      },
    ]);
    expect(runner.state()).toEqual({ state: "idle", credits: 1 });
  });

  it("takes the adventurer's id only: any other body is 400, and nothing runs", async () => {
    const script = fakeScript({ code: 0, stdout: JSON.stringify(OUTPUT) });
    const runner = createCreditRunner({ deploymentPath: FULL, root: "/repo", spawn: script.spawn });
    for (const body of [
      "",
      "2",
      "[2]",
      post(0),
      post(-1),
      post(1.5),
      post("2"),
      post(2 ** 32),
      JSON.stringify({ adventurer: 2, key: "0xk" }),
      JSON.stringify({ adventurer: 2, deployment: "/etc/passwd" }),
    ]) {
      expect((await runner.request("POST", "application/json", body)).status, body).toBe(400);
    }
    // A form or a text body, which another origin may send without a preflight
    expect((await runner.request("POST", "text/plain", post(2))).status).toBe(400);
    expect((await runner.request("POST", undefined, post(2))).status).toBe(400);
    expect((await runner.request("PUT", "application/json", post(2))).status).toBe(405);
    expect(script.runs).toEqual([]);
  });

  it("refuses a deployment with no build, or whose node is not local, or none", async () => {
    const script = fakeScript({ code: 0, stdout: JSON.stringify(OUTPUT) });
    const answer = async (path: string | undefined) => {
      const runner = createCreditRunner({ deploymentPath: path, root: "/r", spawn: script.spawn });
      const { status, body } = await runner.request("POST", "application/json", post(2));
      return [status, JSON.parse(body).error];
    };
    expect(await answer(undefined)).toEqual([404, "no deployment"]);
    expect(await answer(join(scratch, "missing.json"))).toEqual([404, "no deployment"]);
    expect(await answer(file("log.txt", "Private key: 0xk"))).toEqual([404, "no deployment"]);
    const empty = { ...deployment, build: undefined };
    const noBuild = [403, "the deployment has no build"];
    expect(await answer(file("none.json", empty))).toEqual(noBuild);
    expect(
      await answer(
        file("empty.json", { ...deployment, build: { ...deployment.build, mode: "empty" } }),
      ),
    ).toEqual(noBuild);
    for (const node_url of [
      "http://localhost:5050",
      "https://127.0.0.1:5050",
      "http://10.0.0.1:5050",
    ]) {
      expect(await answer(file("remote.json", { ...deployment, node_url }))).toEqual([
        403,
        "the deployment's node is not local",
      ]);
    }
    expect(script.runs).toEqual([]);
  });

  it("a failed run is 502 with the script's last line, and the devnet stays usable", async () => {
    const script = fakeScript({
      code: 1,
      stderr: "progress\ndevnet_deploy: adventurer 2 is not inside an instance\n",
    });
    const runner = createCreditRunner({ deploymentPath: FULL, root: "/r", spawn: script.spawn });
    const answer = await runner.request("POST", "application/json", post(2));
    expect(answer.status).toBe(502);
    expect(JSON.parse(answer.body)).toEqual({
      error: "devnet_deploy: adventurer 2 is not inside an instance",
    });
    expect(runner.state()).toEqual({ state: "idle", credits: 1 });
    // An answer that is not the mode's JSON is a failure too
    const odd = fakeScript({ code: 0, stdout: '{"adventurer_id": "2"}' });
    const second = createCreditRunner({ deploymentPath: FULL, root: "/r", spawn: odd.spawn });
    expect((await second.request("POST", "application/json", post(2))).status).toBe(502);
  });

  it("caveat (c): a run past its timeout is killed, its own child only, and the devnet is unusable", async () => {
    vi.useFakeTimers();
    try {
      const script = fakeScript();
      const runner = createCreditRunner({
        deploymentPath: FULL,
        root: "/r",
        timeoutMs: 1000,
        spawn: script.spawn,
      });
      const pending = runner.request("POST", "application/json", post(2));
      await vi.advanceTimersByTimeAsync(0);
      expect(runner.state()).toEqual({ state: "running", credits: 1 });
      await vi.advanceTimersByTimeAsync(1000);
      const answer = await pending;
      expect(script.kills).toEqual(["SIGKILL"]);
      expect(answer).toEqual({ status: 409, body: JSON.stringify({ error: UNUSABLE }) });
      expect(runner.state()).toEqual({ state: "unusable", credits: 1 });
      // Every later credit is refused, and nothing runs again
      const later = await runner.request("POST", "application/json", post(2));
      expect(later.status).toBe(409);
      expect(script.runs).toHaveLength(1);
      expect(JSON.parse((await runner.request("GET", undefined, "")).body)).toEqual({
        state: "unusable",
        credits: 1,
      });
    } finally {
      vi.useRealTimers();
    }
  });

  it("caveat (b): credits run one at a time, in the order asked", async () => {
    const script = fakeScript();
    const runner = createCreditRunner({ deploymentPath: FULL, root: "/r", spawn: script.spawn });
    const first = runner.request("POST", "application/json", post(2));
    const second = runner.request("POST", "application/json", post(3));
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(script.runs.map((run) => run.args.at(-1))).toEqual(["2"]);
    expect(runner.state()).toEqual({ state: "running", credits: 1 });
    script.ends[0]!(1);
    await first;
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(script.runs.map((run) => run.args.at(-1))).toEqual(["2", "3"]);
    script.ends[1]!(1);
    await second;
    expect(runner.state()).toEqual({ state: "idle", credits: 2 });
  });
});
