import { readFileSync, writeFileSync } from "node:fs";
import { beforeAll, describe, expect, it } from "vitest";
import { LOCAL_ACCOUNT_CLASS, createStarknetChain } from "../account/starknet";
import type { Call, ExecutionStatus } from "../account/types";
import type { PlayAction } from "./actions";
import { previewCalls, selector } from "./calls";
import { CASTE, ITEM, type RecordRead, SKILL, assembleContent, trapSkills } from "./content";
import { featuresAround } from "./mirror";
import { mirrorOf } from "./mirror";
import { previewBatch } from "./preview";
import { createReader } from "./read";
import type { ParityRecord } from "./reconcile";
import { type Rpc, createRpc, createRpcSimulator } from "./rpc";
import {
  type ChainOutcome,
  type FunctionInvocation,
  type InvokeTrace,
  Stop,
  extractOutcome,
} from "./trace";
import { ChunkKind, type InstanceView, encodeInstanceView } from "./view";

// Against the game deployed on the local node (OPS-01a), run through the script that starts and
// stops the node, from the repository root, after the classes are built:
//   scripts/with-node.sh bash -c 'python3 scripts/devnet_deploy.py \
//     --out "$PWD/.with-node/deployment.json" &&
//     GRIMWORLD_DEPLOYMENT="$PWD/.with-node/deployment.json" \
//     pnpm --filter @grimworld/app test:node:preview'
// A script of its own: the burner's `test:node` restarts the node, which would drop the deployment.
// `PREVIEW_RECORD=<file>` also writes a recording there, in the form of `recorded.ts` (a quiet
// world, CLI-10c) and `recorded-goblins.ts` (a world whose view lists a goblin, CLI-10d). Without
// a deployment (the ordinary `pnpm test`), skipped.
const env = import.meta.env as Record<string, string | undefined>;
const deploymentPath = env.GRIMWORLD_DEPLOYMENT;

/** `scripts/devnet_deploy.py`'s JSON, the keys read. */
type Deployment = {
  node_url: string;
  account: string;
  contracts: { registry: string; instances: string };
  adventurer_id: number;
  instance_id: number;
};

const WAIT: PlayAction = { kind: "wait" };

async function settled(status: () => Promise<ExecutionStatus>): Promise<ExecutionStatus> {
  for (let i = 0; i < 200; i++) {
    const current = await status();
    if (current !== "pending") return current;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return "pending";
}

const median = (values: number[]): number => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[mid]! : (sorted[mid - 1]! + sorted[mid]!) / 2;
};

/** A trace cut to what `extractOutcome` reads: no calldata, no addresses, no resources. */
function trim(trace: InvokeTrace): InvokeTrace {
  const invocation = (call: FunctionInvocation): FunctionInvocation => ({
    result: call.result,
    calls: call.calls.map(invocation),
    events: call.events.map(({ order, keys, data }) => ({ order, keys, data })),
    ...(call.is_reverted === undefined ? {} : { is_reverted: call.is_reverted }),
  });
  const execute = trace.execute_invocation;
  return {
    type: "INVOKE",
    execute_invocation:
      "revert_reason" in execute ? { revert_reason: execute.revert_reason } : invocation(execute),
  };
}

describe.skipIf(!deploymentPath)("the batch preview on the local node", () => {
  let deployment: Deployment;
  let rpc: Rpc;
  let key: string;
  let keys: bigint[];
  let version: number;
  const reader = () => createReader({ nodeUrl: deployment.node_url });
  const simulator = () =>
    createRpcSimulator({ nodeUrl: deployment.node_url, sender: deployment.account });
  const target = async (adventurerId = deployment.adventurer_id) => ({
    instances: deployment.contracts.instances,
    instanceId: BigInt(deployment.instance_id),
    adventurerId,
    sequence: (await reader().instanceState(deployment.contracts.instances, instanceId())).header
      .sequence,
    version,
  });
  const instanceId = () => BigInt(deployment.instance_id);
  const recorded: Record<string, InvokeTrace> = {};
  /** The mirror's inputs before the Wait, as felts: the view, the controlled member, the region. */
  let mirrored = "";
  let inputs: { view: string[]; member: number; region: unknown[] } | undefined;
  /** The Registry records read, `[kind, id, parts]`: the content's, and the seed's sheets. */
  const records = new Map<string, [number, number, string[]]>();
  /** `Registry.record`, each answer kept for `recorded.ts`. */
  const recording =
    (registry: string): RecordRead =>
    async (kind, id) => {
      const parts = await reader().record(registry, kind, id);
      records.set(`${kind}:${id}`, [kind, id, parts.map((p) => `0x${p.toString(16)}`)]);
      return parts;
    };
  /** Whether the view before the Wait listed goblins, and the content's size. */
  let listed = 0;
  let sheets = "";
  /** What the deployment's entropy drew, observed before the Wait. */
  let world = { quiet: false };
  /**
   * No goblin in the roster nor in the window, none unloadable: a Wait plays 1 and stops on
   * nothing.
   */
  const quiet = (view: InstanceView) => ({
    quiet: view.goblins.length === 0 && view.header.rosterCount === 0 && !view.unloadable,
  });

  beforeAll(async () => {
    deployment = JSON.parse(readFileSync(deploymentPath!, "utf8")) as Deployment;
    rpc = createRpc(deployment.node_url, globalThis.fetch.bind(globalThis));
    // The deployer's key, from the node that publishes it (never printed)
    const accounts = (await rpc("devnet_getPredeployedAccounts", {})) as {
      address: string;
      private_key: string;
    }[];
    keys = accounts.map((a) => BigInt(a.private_key));
    const own = accounts.find((a) => BigInt(a.address) === BigInt(deployment.account));
    if (own === undefined) throw new Error("the deployment's account is not a predeployed one");
    key = own.private_key;
    version = await reader().contentVersion(deployment.contracts.registry);
  });

  it("previews a Wait, then sends it: the real result equals the preview (D-257)", async () => {
    const read = reader();
    const before = await read.instanceState(deployment.contracts.instances, instanceId());
    // The location's extent is the view's (VIEW-01); the member the adventurer controls is the
    // chain's (`placement`, play.cairo :187-188), the area's centre
    const { member } = await read.placement(
      deployment.contracts.instances,
      deployment.adventurer_id,
    );
    const region = await read.region(deployment.contracts.instances, instanceId());
    // Every chunk not void lies in the location's extent (`chunk_kind`)
    const used = region.filter((c) => c.kind !== ChunkKind.Void);
    expect(used.length).toBeGreaterThan(0);
    expect([before.width, before.height, before.levelMin]).not.toEqual([0, 0, 0]);
    for (const { chunk } of used) {
      expect([chunk % 15 < before.width, Math.floor(chunk / 15) < before.height]).toEqual([
        true,
        true,
      ]);
    }
    const hex = (felt: bigint) => `0x${felt.toString(16)}`;
    inputs = {
      view: encodeInstanceView(before).map(hex),
      member,
      region: used.map((c) => ({ ...c, terrain: hex(c.terrain), features: hex(c.features) })),
    };
    world = quiet(before);
    const parity: ParityRecord[] = [];
    const input = { ...(await target()), actions: [WAIT] };
    // The content as `PlayLibrary` assembles it (CLI-10d): the deployed adventurer has an empty
    // build and no belt, so it holds the castes of the goblins listed and their skills
    const ground = featuresAround({ view: before, member, region });
    const { content, calls } = await assembleContent(
      before,
      recording(deployment.contracts.registry),
      ground,
    );
    // The terrain traps' skills (FIX-02b): when the world holds an unused one around the member,
    // its skill is in the content; when it holds none (the usual draw), nothing is forced
    const trapIds = trapSkills(ground);
    for (const id of trapIds) expect(content.skills.map((sheet) => sheet.id)).toContain(id);
    console.info(
      trapIds.length > 0
        ? `terrain traps: skills ${trapIds.join(", ")} in the content`
        : "terrain traps: none around the member in this world, no skill asserted",
    );
    listed = before.goblins.length;
    sheets =
      `content ${content.skills.length} skills, ${content.potions.length} potions, ` +
      `${content.castes.length} castes in ${calls} records`;
    const predict = mirrorOf({ view: before, member, region, content });
    const sim = simulator();
    let simulated: InvokeTrace | undefined;
    const preview = await previewBatch(input, {
      simulator: {
        async simulate(calls) {
          simulated = await sim.simulate(calls);
          return simulated;
        },
      },
      predict,
      log: (record) => parity.push(record),
    });
    expect(preview.kind).toBe("simulated");
    if (preview.kind !== "simulated" || preview.chain.kind !== "played") throw new Error("no play");
    // What a Wait does depends on the world this deployment's entropy drew: with no goblin in the
    // window it plays 1, stops on nothing and moves the clock; with goblins around the member it
    // may stop earlier or kill it. The strict assertion holds on the quiet world only (review
    // t-0190, note 2); the chain's result is checked against the real send below either way.
    if (world.quiet) {
      expect(preview.chain.batch).toMatchObject({ played: 1, stop: Stop.None, clock: 1 });
    } else {
      expect(preview.chain.batch.played).toBeLessThanOrEqual(1);
    }
    // Where the mirror predicts, no mismatch (the goblin sets too); where it does not, the reason
    expect(preview.mismatches).toEqual([]);
    expect(parity).toEqual([]);
    // One line a run saying which it was (review t-0190, note 1), the reason as it is
    mirrored = preview.mirror.kind === "predicted" ? "predicted" : preview.mirror.reason;
    console.info(
      `mirror: ${mirrored} (world: ${world.quiet ? "quiet" : "goblins"}, ${before.goblins.length} listed, ` +
        `member ${member}, ${before.width}x${before.height}; ${sheets})`,
    );
    // With the content assembled, no sheet is missing: a gap would be a mirror failure (above)
    // or, without content, `NotMirrored` naming it
    expect(mirrored).not.toMatch(/not in content/);
    // The account's `__execute__` makes exactly the preview's two calls (review t-0186)
    const execute = simulated!.execute_invocation as FunctionInvocation;
    expect(execute.calls.map((c) => BigInt(c.entry_point_selector!))).toEqual([
      selector.play,
      selector.instance_state,
    ]);
    recorded.played = trim(simulated!);

    // The same two calls, signed and sent
    const chain = createStarknetChain({
      nodeUrl: deployment.node_url,
      accountClass: LOCAL_ACCOUNT_CLASS,
    });
    const hash = await chain.send(key, deployment.account, previewCalls(input, [WAIT])!);
    expect(await settled(() => chain.status(hash))).toBe("succeeded");
    const real = extractOutcome(
      (await rpc("starknet_traceTransaction", { transaction_hash: hash })) as InvokeTrace,
    );
    expect(real).toEqual(preview.chain);
    // And the state a read sees afterwards
    expect(await read.instanceState(deployment.contracts.instances, instanceId())).toEqual(
      preview.chain.view,
    );
  }, 120_000);

  it("surfaces a reverted batch with the chain's own reason, and the real send is refused", async () => {
    // Adventurer 1,000,000 does not exist (no test creates it; the chain mode's node test creates
    // adventurer 2): the admission's controller check panics
    const input = { ...(await target(1_000_000)), actions: [WAIT] };
    const sim = simulator();
    let simulated: InvokeTrace | undefined;
    const preview = await previewBatch(input, {
      simulator: {
        async simulate(calls) {
          simulated = await sim.simulate(calls);
          return simulated;
        },
      },
    });
    expect(preview).toMatchObject({
      kind: "simulated",
      chain: { kind: "reverted", reason: "not controller" },
      mismatches: [],
    });
    recorded.reverted = trim(simulated!);
    const chain = createStarknetChain({
      nodeUrl: deployment.node_url,
      accountClass: LOCAL_ACCOUNT_CLASS,
    });
    const refused = await chain
      .send(key, deployment.account, previewCalls(input, [WAIT])!)
      .catch((error: unknown) => error);
    expect(refused).toMatchObject({ code: "refused" });
    expect(String((refused as Error).cause)).toContain("not controller");
  }, 60_000);

  it("simulates under zero-price bounds, and under no bound at all (review t-0184, note 6)", async () => {
    const input = await target();
    const calls = previewCalls(input, [WAIT])!;
    // The default: every price 0, the L2 amount 2^40 (test 1 already ran under it)
    expect(extractOutcome(await simulator().simulate(calls))).toMatchObject({ kind: "played" });
    // Every amount 0 too: under SKIP_FEE_CHARGE the node neither charges nor bounds by them
    const zero = { maxAmount: 0n, maxPricePerUnit: 0n };
    const unbounded = createRpcSimulator({
      nodeUrl: deployment.node_url,
      sender: deployment.account,
      bounds: { l1Gas: zero, l2Gas: zero, l1DataGas: zero },
    });
    expect(extractOutcome(await unbounded.simulate(calls))).toMatchObject({
      kind: "played",
      batch: { played: 1, stop: Stop.None },
    });
  }, 60_000);

  it("reads an admission refusal as a played outcome that ran nothing", async () => {
    const input = { ...(await target()), actions: [WAIT] };
    const preview = await previewBatch(
      { ...input, sequence: input.sequence + 5 },
      { simulator: simulator() },
    );
    expect(preview).toMatchObject({
      chain: { kind: "played", batch: { played: 0, stop: Stop.Sequence } },
      mirror: { kind: "not-mirrored" },
    });
  }, 60_000);

  it("cannot tell an illegal first action from an undecodable batch (review t-0186)", async () => {
    const input = await target();
    const sim = simulator();
    // A Move off the location from the entry tile (column 0: one direction at least leads off
    // it, whatever the deployment's entropy revealed); a count of 0 does not decode. Whether a
    // direction is illegal depends on the world this deployment drew: when none is, the
    // comparison has no illegal outcome to hold the undecodable one to, and says so (review
    // t-0190, note 2).
    let illegal: ChainOutcome | undefined;
    let calls: Call[] = [];
    for (let direction = 0; direction < 6 && illegal === undefined; direction++) {
      calls = previewCalls(input, [{ kind: "move", direction }])!;
      const outcome = extractOutcome(await sim.simulate(calls));
      if (outcome.kind === "played" && outcome.batch.stop === Stop.Invalid) illegal = outcome;
    }
    const [play, state] = calls;
    const undecodable = extractOutcome(
      await sim.simulate([{ ...play!, calldata: [...play!.calldata.slice(0, 4), 0n] }, state!]),
    );
    expect(undecodable).toMatchObject({ kind: "played", batch: { played: 0, stop: Stop.Invalid } });
    if (illegal === undefined) {
      console.info("illegal first move: none of the 6 directions is illegal in this world");
    } else {
      expect(illegal).toMatchObject({ kind: "played", batch: { played: 0, stop: Stop.Invalid } });
      expect(undecodable).toEqual(illegal);
    }
  }, 60_000);

  it("times the simulation: 10 runs of a Wait and of the heaviest 10-action batch", async () => {
    const input = await target();
    const sim = simulator();
    const batches: [string, PlayAction[]][] = [
      ["1 wait", [WAIT]],
      ["10 waits", Array.from({ length: 10 }, () => WAIT)],
      ["10 moves (3)", Array.from({ length: 10 }, () => ({ kind: "move", direction: 3 }))],
      ["10 moves (4)", Array.from({ length: 10 }, () => ({ kind: "move", direction: 4 }))],
      [
        "10 moves (3, 4)",
        Array.from({ length: 10 }, (_, i) => ({ kind: "move", direction: i % 2 === 0 ? 3 : 4 })),
      ],
    ];
    for (const [name, actions] of batches) {
      const calls = previewCalls(input, actions)!;
      const times: number[] = [];
      let trace: InvokeTrace | undefined;
      for (let run = 0; run < 10; run++) {
        const start = performance.now();
        trace = await sim.simulate(calls);
        times.push(performance.now() - start);
      }
      const outcome = extractOutcome(trace!);
      const gas = (trace as { execution_resources?: { l2_gas?: number } }).execution_resources
        ?.l2_gas;
      console.info(
        `latency ${name}: median ${median(times).toFixed(1)} ms, max ${Math.max(...times).toFixed(1)} ms,` +
          ` l2_gas ${gas}, ${outcome.kind === "played" ? `played ${outcome.batch.played} stop ${outcome.batch.stop} revealed ${outcome.revealed.length}` : outcome.reason}`,
      );
    }
  }, 120_000);

  it("times the content's batch read: 10 assemblies (CLI-10d)", async () => {
    const read = reader();
    const view = await read.instanceState(deployment.contracts.instances, instanceId());
    const registry = deployment.contracts.registry;
    const { member } = await read.placement(
      deployment.contracts.instances,
      deployment.adventurer_id,
    );
    const ground = featuresAround({
      view,
      member,
      region: await read.region(deployment.contracts.instances, instanceId()),
    });
    const times: number[] = [];
    let calls = 0;
    for (let run = 0; run < 10; run++) {
      const start = performance.now();
      ({ calls } = await assembleContent(
        view,
        (kind, id) => read.record(registry, kind, id),
        ground,
      ));
      times.push(performance.now() - start);
    }
    console.info(
      `content read: ${calls} Registry.record calls (${view.goblins.length} goblins listed), ` +
        `median ${median(times).toFixed(1)} ms, max ${Math.max(...times).toFixed(1)} ms`,
    );
    // The seed's sheets (contracts/seed/test-region.json: castes 1-3, skill 1; devnet_deploy.py's
    // potion 1), kept for the decoders' unit test whatever the world drew
    const seed = recording(registry);
    for (const id of [1, 2, 3]) await seed(CASTE, id);
    await seed(SKILL, 1);
    await seed(ITEM, 1);
  }, 60_000);

  it("writes the recorded traces when asked, with no key in them", () => {
    expect(Object.keys(recorded).sort()).toEqual(["played", "reverted"]);
    expect(inputs).toBeDefined();
    const text = JSON.stringify({ recorded, inputs, records: [...records.values()] });
    for (const k of keys) {
      expect(text.toLowerCase()).not.toContain(k.toString(16));
      expect(text).not.toContain(k.toString());
    }
    const out = env.PREVIEW_RECORD;
    if (out === undefined) return;
    writeFileSync(
      out,
      [
        "// Recorded by preview.node.test.ts (PREVIEW_RECORD) on starknet-devnet, OPS-01a's deployment:",
        "// a Wait of adventurer 1 at sequence 0, and the same batch for adventurer 1,000,000, which reverts.",
        `// The world is the deployment's (its entropy), goblins listed: ${listed}; the mirror on it: ${mirrored}.`,
        "// Trimmed to what extractOutcome reads; no key (the test checks). Do not edit by hand.",
        'import type { InvokeTrace } from "./trace";',
        "",
        `export const recordedPlayed: InvokeTrace = ${JSON.stringify(recorded.played, null, 2)};`,
        "",
        `export const recordedReverted: InvokeTrace = ${JSON.stringify(recorded.reverted, null, 2)};`,
        "",
        "/** The mirror's inputs before the Wait: the view's felts, the controlled member, the chunks not void. */",
        `export const recordedBefore = ${JSON.stringify(inputs, null, 2)};`,
        "",
        "/** The Registry records read (`[kind, id, parts]`): the content's before the Wait, the seed's sheets. */",
        `export const recordedRecords: [number, number, string[]][] = ${JSON.stringify(
          [...records.values()].sort(([k1, i1], [k2, i2]) => k1 - k2 || i1 - i2),
          null,
          2,
        )};`,
        "",
      ].join("\n"),
    );
  });
});
