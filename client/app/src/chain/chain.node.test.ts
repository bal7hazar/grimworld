import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import type { AccountProvider, Call, ExecutionId, ExecutionStatus, KeyStorage } from "../account";
import { NAMES } from "../combat/names";
import type { PlayAction } from "../preview/actions";
import { previewBatch } from "../preview/preview";
import { type BlockId, createReader } from "../preview/read";
import { createRpc, createRpcSimulator } from "../preview/rpc";
import { Stop } from "../preview/trace";
import { type Opened, SN_MAIN, assertTestChain, openChain, parseDeployment } from "./network";
import { type ChainState, type SendDeps, createSentReads, readState, sendBatch } from "./send";
import { createCreditRunner } from "../dev/credit";
import { createChainController } from "./ChainController";
import { createCredit } from "./credit";
import { type Stages, createStages } from "./stages";
import { type Player, type SetupDeps, builtWith, enter, restore } from "./setup";

// The chain mode's setup against the game deployed on the local node (CLI-11 §7), run with the
// preview's node test, one file after the other, from the repository root once the classes are built:
//   pnpm --filter @grimworld/app test:node:devnet
// It reads `GRIMWORLD_DEPLOYMENT`, or `.with-node/deployment.json` at the repository's root when the
// variable is unset; that file outlives its node, so it is used only while its node answers. Without
// either (the ordinary `pnpm test`), skipped.
//
// It shares the node with `preview.node.test.ts`: account 0 is the deployment's and the preview
// test's, account 1 funds the burner, the burner sends from its own; the burner's adventurer is the
// first created after the deployment's, id 2. With a `--build full` deployment (CLI-11d3) the burner
// is built with its build: the credit is the development server's runner (`src/dev/credit.ts`, game's
// `devnet_deploy.py --credit-only`, account 0's calls node-side), reached here without HTTP.
const env = import.meta.env as Record<string, string | undefined>;
const ROOT = fileURLToPath(new URL("../../../../", import.meta.url));
const FALLBACK = fileURLToPath(new URL("../../../../.with-node/deployment.json", import.meta.url));

/**
 * The deployment's JSON, and whether to run: always when named; the fallback only while its own node
 * answers for it (review t-0236): the node's chain id is the file's, and the file's Hub is deployed
 * there. Any other answer, an HTTP 200 included, is another node or none: skipped.
 */
let deploymentPath: string | undefined;
async function locate(): Promise<unknown> {
  const named = env.GRIMWORLD_DEPLOYMENT;
  if (named) {
    deploymentPath = named;
    return JSON.parse(readFileSync(named, "utf8"));
  }
  if (!existsSync(FALLBACK)) return undefined;
  deploymentPath = FALLBACK;
  const json: unknown = JSON.parse(readFileSync(FALLBACK, "utf8"));
  const deployment = parseDeployment(json);
  if (deployment === undefined) return undefined;
  const timed: typeof fetch = (url, init) =>
    fetch(url, { ...init, signal: AbortSignal.timeout(2000) });
  const rpc = createRpc(deployment.nodeUrl, timed);
  try {
    const chainId = await rpc("starknet_chainId", []);
    if (typeof chainId !== "string" || BigInt(chainId) !== deployment.chainId) return undefined;
    const hub = await rpc("starknet_getClassHashAt", {
      block_id: "latest",
      contract_address: deployment.contracts.hub,
    });
    return typeof hub === "string" && BigInt(hub) !== 0n ? json : undefined;
  } catch {
    return undefined;
  }
}

const found = await locate();

function memoryStorage(): KeyStorage {
  const data = new Map<string, string>();
  return {
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => void data.set(key, value),
    removeItem: (key) => void data.delete(key),
  };
}

/** A provider that records the entrypoints of each execution it sends, and their ids. */
function recording(provider: AccountProvider) {
  const sent: string[][] = [];
  const ids: ExecutionId[] = [];
  const wrapped: AccountProvider = {
    createOrRestore: () => provider.createOrRestore(),
    async execute(calls) {
      sent.push(calls.map((c) => c.entrypoint));
      const id = await provider.execute(calls);
      ids.push(id);
      return id;
    },
    status: (id) => provider.status(id),
    signOut: () => provider.signOut(),
  };
  return { provider: wrapped, sent, ids };
}

async function settled(status: () => Promise<ExecutionStatus>): Promise<ExecutionStatus> {
  for (let i = 0; i < 200; i++) {
    const current = await status();
    if (current !== "pending") return current;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return "pending";
}

describe.skipIf(found === undefined)("the chain mode's setup on the local node", () => {
  const deployment = parseDeployment(found)!;
  const raw = found as { adventurer_id: number; node_url: string };
  const storage = memoryStorage();
  let opened: Opened;
  let player: Player;
  /** What each execution of the burner cost, in fri (§3.3: does 100 STRK last a session?). */
  const fees: [string, bigint][] = [];
  const { build } = deployment;
  const runner = createCreditRunner({ deploymentPath, root: ROOT });
  const credit = createCredit((method, body) =>
    runner.request("127.0.0.1", method, "application/json", body ?? ""),
  );
  const deps = (provider: AccountProvider): SetupDeps => ({
    provider,
    reader: opened.reader,
    ...deployment.contracts,
    ...(build ? { build, credit } : {}),
    pollMs: 100,
  });
  const cost = async (sent: string[][], ids: ExecutionId[]) => {
    for (const [i, id] of ids.entries()) {
      const receipt = (await opened.rpc("starknet_getTransactionReceipt", {
        transaction_hash: id,
      })) as { actual_fee: { amount: string; unit: string } };
      expect(receipt.actual_fee.unit).toBe("FRI");
      fees.push([sent[i]!.join("+"), BigInt(receipt.actual_fee.amount)]);
    }
  };

  beforeAll(async () => {
    expect(deployment).toBeDefined();
    opened = await openChain(raw.node_url, deployment, { storage, ...(build ? { credit } : {}) });
  });

  it("makes the burner a player: funded by account 1, registered, built, entered", async () => {
    const { provider, sent, ids } = recording(opened.provider);
    player = await restore(deps(provider));
    expect(sent).toEqual([
      ["register", "create_adventurer"],
      ["set_build"],
      ["enter"],
      // With the build: credited inside, then left, the skills bought and the build set, entered again
      ...(build
        ? [
            [
              "leave",
              ...build.bar.filter((skill) => skill !== 0).map(() => "buy_skill"),
              "set_build",
            ],
            ["enter"],
          ]
        : []),
    ]);
    if (build) {
      expect(runner.state()).toEqual({ state: "idle", credits: 1 });
      expect(await builtWith(deps(provider), player.adventurerId, build)).toBe(true);
    }
    expect(player.adventurerId).not.toBe(raw.adventurer_id);
    expect(player.adventurerId).toBe(2);
    expect(BigInt(player.address)).not.toBe(0n);
    const placement = await opened.reader.placement(
      deployment.contracts.instances,
      player.adventurerId,
    );
    expect(placement).toEqual({
      instanceId: player.instanceId,
      member: player.member,
      inside: true,
    });
    await cost(sent, ids);
  }, 300_000);

  it.skipIf(build === undefined)(
    "the burner carries the deployment's build: its bar and belt through the controller",
    async () => {
      const state = await readState(opened.reader, {
        instances: deployment.contracts.instances,
        registry: deployment.contracts.registry,
        instanceId: player.instanceId,
        adventurerId: player.adventurerId,
      });
      const stages = createStages(state, {
        simulator: createRpcSimulator({ nodeUrl: raw.node_url, sender: player.address }),
        send: () => Promise.reject(new Error("nothing is sent here")),
        load: () => Promise.reject(new Error("nothing is read again here")),
      });
      const controller = createChainController({
        stages,
        enter: () => Promise.reject(new Error("no")),
      });
      const view = controller.combat.snapshot().view;
      expect(view, "the combat view needs the state's content").not.toBeNull();
      const { bar, belt } = view!.state.adventurer;
      expect(bar.filter((slot) => slot.skill !== null).map((slot) => slot.skill!.id)).toEqual(
        build!.bar.filter((id) => id !== 0),
      );
      expect(
        belt.filter((slot) => slot.item !== null).map((slot) => [slot.item, slot.count]),
      ).toEqual(build!.belt.map(({ item, count }) => [item, count]));
      console.info(
        `burner built: bar ${JSON.stringify(bar.map((slot) => slot.skill?.id ?? 0))}, ` +
          `belt ${JSON.stringify(belt.map((slot) => [slot.item, slot.count]))}`,
      );
    },
    60_000,
  );

  it("restores the same adventurer and instance from a second provider on the same storage", async () => {
    const again = await openChain(raw.node_url, deployment, {
      storage,
      ...(build ? { credit } : {}),
    });
    const { provider, sent } = recording(again.provider);
    const restored = await restore({ ...deps(provider), reader: again.reader });
    expect(restored).toEqual(player);
    expect(sent).toEqual([]);
  }, 60_000);

  it("enters the same adventurer again after travel_back closes the instance", async () => {
    const { provider, sent, ids } = recording(opened.provider);
    const { instances } = deployment.contracts;
    const before = await opened.reader.instanceState(instances, player.instanceId);
    // Travelling back is sent alone (design/02), by the burner, at the current sequence
    const back: Call = {
      to: instances,
      entrypoint: "travel_back",
      calldata: [player.instanceId, BigInt(player.adventurerId), BigInt(before.header.sequence)],
    };
    const id = await provider.execute([back]);
    expect(await settled(() => provider.status(id))).toBe("succeeded");
    expect((await opened.reader.placement(instances, player.adventurerId)).inside, "closed").toBe(
      false,
    );
    // The re-entry: set_build then enter, no travel (the start hub is gate 1's source), no new
    // adventurer; with the build, the build itself (the closing put the unused belt back in the
    // pack), no credit and no skill bought again
    await enter(deps(provider), player.adventurerId);
    expect(sent).toEqual([["travel_back"], ["set_build"], ["enter"]]);
    if (build) {
      expect(runner.state().credits).toBe(1);
      expect(await builtWith(deps(provider), player.adventurerId, build)).toBe(true);
    }
    const placement = await opened.reader.placement(instances, player.adventurerId);
    expect(placement.inside).toBe(true);
    expect(placement.instanceId).not.toBe(player.instanceId);
    const restored = await restore(deps(provider));
    expect(restored).toMatchObject({
      adventurerId: player.adventurerId,
      instanceId: placement.instanceId,
    });
    expect(sent).toHaveLength(3);
    await cost(sent, ids);
    const total = fees.reduce((sum, [, fee]) => sum + fee, 0n);
    console.info(
      `burner fees: ${fees.map(([what, fee]) => `${what} ${fee}`).join(", ")}; ` +
        `total ${total} fri of 10^20 funded`,
    );
  }, 180_000);

  // CLI-11b: the batch and its preview on the burner's adventurer, sent through the guarded provider
  // and CLI-11a's own check (§2.3), in the instance it entered again above
  describe("the batch sent", () => {
    const parity: unknown[] = [];
    const sentLog: unknown[] = [];
    /** The instance the adventurer stands in now: the one it entered again above, not `player`'s. */
    let instanceId: bigint;
    beforeAll(async () => {
      const placement = await opened.reader.placement(
        deployment.contracts.instances,
        player.adventurerId,
      );
      expect(placement.inside).toBe(true);
      instanceId = placement.instanceId;
    });
    const ids = () => ({
      instances: deployment.contracts.instances,
      registry: deployment.contracts.registry,
      instanceId,
      adventurerId: player.adventurerId,
    });
    const load = () => readState(opened.reader, ids());
    const sendDeps = (): SendDeps => ({
      account: opened.provider,
      assertChain: opened.assertChain,
      reads: createSentReads(raw.node_url),
      readerAt: (block: BlockId) => createReader({ nodeUrl: raw.node_url, block }),
      registry: deployment.contracts.registry,
      log: (record) => parity.push(record),
      sentLog: (record) => sentLog.push(record),
    });
    const stagesOn = (state: ChainState): Stages =>
      createStages(state, {
        simulator: createRpcSimulator({ nodeUrl: raw.node_url, sender: player.address }),
        send: (input) => sendBatch(input, sendDeps()),
        load,
        log: (record) => parity.push(record),
      });
    /** `B` on the batch planned; resolves once its result is in (or nothing was left to send). */
    async function sendPlanned(model: Stages) {
      model.send();
      for (let i = 0; i < 1200; i++) {
        const now = model.get();
        if (now.phase === "closed") throw new Error(`the instance closed: ${now.line}`);
        if (now.phase !== "sending" && now.phase !== "reading" && now.sent !== undefined) return;
        if (
          now.phase === "ready" &&
          now.simulation?.status === "answered" &&
          now.sent === undefined
        ) {
          // The preview dropped a refused action and the rest: `B` again on what is left
          if (now.planned.length === 0) return;
          model.send();
        }
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      throw new Error("the batch did not settle");
    }
    /** The sent batch equals its simulation, and the state after is the one a read sees. */
    async function sentEqualsPreview(model: Stages) {
      const { sent } = model.get();
      if (sent?.result.kind !== "sent" || sent.simulated.kind !== "simulated") {
        throw new Error(`not sent: ${JSON.stringify(sent?.result.kind)} ${model.get().line}`);
      }
      expect(sent.result.chain).toEqual(sent.simulated.chain);
      expect(sent.result.differs).toEqual([]);
      expect(sent.result.mismatches).toEqual([]);
      const read = await load();
      expect(sent.result.after.mirror.view).toEqual(read.mirror.view);
      expect(sent.result.after.mirror.region).toEqual(read.mirror.region);
      expect(sent.result.after.target).toEqual(read.target);
      expect(model.get().chain.target.sequence).toBe(read.target.sequence);
      return sent.result;
    }

    it("previews a Wait, sends it, and the sent outcome equals the simulated one", async () => {
      const model = stagesOn(await load());
      model.input([{ kind: "wait" }]);
      await sendPlanned(model);
      const result = await sentEqualsPreview(model);
      console.info(
        `chain batch: Wait, mirror ${result.mirror.kind === "predicted" ? "predicted" : result.mirror.reason}`,
      );
    }, 120_000);

    it("previews a short Move batch, sends it, and the sent outcome equals the simulated one", async () => {
      // A direction the chain lets the adventurer step in, from the preview alone (nothing sent)
      const state = await load();
      const simulator = createRpcSimulator({ nodeUrl: raw.node_url, sender: player.address });
      let open: number | undefined;
      for (let direction = 0; direction < 6 && open === undefined; direction++) {
        const preview = await previewBatch(
          { ...state.target, actions: [{ kind: "move", direction }] },
          { simulator },
        );
        if (
          preview.kind === "simulated" &&
          preview.chain.kind === "played" &&
          preview.chain.batch.played === 1 &&
          preview.chain.batch.stop === Stop.None
        ) {
          open = direction;
        }
      }
      if (open === undefined) {
        console.info("chain batch: no direction open around the burner's adventurer, no Move sent");
        return;
      }
      // There, and back: the stages count where it stops
      const moves: PlayAction[] = [
        { kind: "move", direction: open },
        { kind: "move", direction: (open + 3) % 6 },
      ];
      const model = stagesOn(state);
      model.input(moves, { path: true });
      await sendPlanned(model);
      const result = await sentEqualsPreview(model);
      expect(result.chain.kind === "played" && result.chain.batch.played).toBeGreaterThanOrEqual(1);
      console.info(
        `chain batch: Move ${open} and back, played ${result.chain.kind === "played" ? result.chain.batch.played : "-"}, ` +
          `mirror ${result.mirror.kind === "predicted" ? "predicted" : result.mirror.reason}`,
      );
      expect(parity).toEqual([]);
      expect(sentLog).toEqual([]);
    }, 180_000);

    it("refuses before execute when the node reports SN_MAIN, through the real check and the guarded provider", async () => {
      const state = await load();
      const preview = await previewBatch(
        { ...state.target, actions: [{ kind: "wait" }] },
        { simulator: createRpcSimulator({ nodeUrl: raw.node_url, sender: player.address }) },
      );
      if (preview.kind !== "simulated") throw new Error("refused");
      // The same node, its chain id answered as SN_MAIN from now on
      let mainnet = false;
      const lying: typeof fetch = async (url, init) => {
        const body = JSON.parse(String(init?.body)) as { id: number; method: string };
        if (mainnet && body.method === "starknet_chainId") {
          return new Response(
            JSON.stringify({ jsonrpc: "2.0", id: body.id, result: `0x${SN_MAIN.toString(16)}` }),
          );
        }
        return fetch(url, init);
      };
      const executed: string[] = [];
      const counting = (account: SendDeps["account"]): SendDeps["account"] => ({
        execute: (calls) => {
          executed.push(calls.map((c) => c.entrypoint).join("+"));
          return account.execute(calls);
        },
        status: (id) => account.status(id),
      });
      // The injected check alone: CLI-11a's `assertTestChain` on the lying node
      mainnet = true;
      const injected = await sendBatch(
        { state, actions: [{ kind: "wait" }], simulated: preview.chain },
        {
          ...sendDeps(),
          account: counting(opened.provider),
          assertChain: () => assertTestChain(createRpc(raw.node_url, lying)),
        },
      );
      expect(injected).toEqual({ kind: "refused", reason: "chain mode refused: not a test chain" });
      expect(executed).toEqual([]);
      // The guarded provider alone, the injected check passing: refused inside `execute`, before
      // anything is signed, and read as the guard's refusal (review t-0236, note 3)
      mainnet = false;
      const guarded = await openChain(raw.node_url, deployment, { storage, fetch: lying });
      await guarded.provider.createOrRestore();
      mainnet = true;
      const before = await load();
      const inside = await sendBatch(
        { state, actions: [{ kind: "wait" }], simulated: preview.chain },
        { ...sendDeps(), account: guarded.provider, assertChain: async () => undefined },
      );
      expect(inside).toEqual({ kind: "refused", reason: "chain mode refused: not a test chain" });
      // Nothing played
      expect((await load()).target.sequence).toBe(before.target.sequence);
    }, 120_000);
  });
});

// CLI-11d: skills and belt items on the deployment's own adventurer, built `--build full` (SEED-02:
// four skills on the bar, a belt of healing ×2 and a REGENERATION potion), adventurer
// `adventurer_id`, which account 0 owns (the burner carries the same build since CLI-11d3, above).
// Only simulated, never sent: the world is drawn again on every deployment (entropy), so no entity,
// tile or goblin count is assumed; the targets come from the state read back.
type FullBuild = {
  mode: string;
  bar: number[];
  belt: { item: number; count: number }[];
};
const fullBuild = (found as { build?: FullBuild } | undefined)?.build;

describe.skipIf(found === undefined || fullBuild?.mode !== "full")(
  "the skills and belt items of the full build, previewed on the local node",
  () => {
    const deployment = parseDeployment(found)!;
    const raw = found as {
      adventurer_id: number;
      instance_id: number;
      node_url: string;
      account: string;
    };
    const full = fullBuild!;
    const reader = () => createReader({ nodeUrl: raw.node_url });
    const ids = () => ({
      instances: deployment.contracts.instances,
      registry: deployment.contracts.registry,
      instanceId: BigInt(raw.instance_id),
      adventurerId: raw.adventurer_id,
    });
    const load = () => readState(reader(), ids());
    const parity: unknown[] = [];

    /** A controller on the deployment's adventurer; its sends are never made. */
    async function controllerOn() {
      const stages = createStages(await load(), {
        simulator: createRpcSimulator({ nodeUrl: raw.node_url, sender: raw.account }),
        send: () => Promise.reject(new Error("the full build is only previewed here")),
        load,
        log: (record) => parity.push(record),
        debounce: 20,
      });
      return {
        stages,
        controller: createChainController({ stages, enter: () => Promise.reject(new Error("no")) }),
      };
    }
    /** The simulation of the batch planned, once it answered. */
    async function answered(stages: Stages) {
      for (let i = 0; i < 400; i++) {
        const { simulation } = stages.get();
        if (simulation?.status === "answered") return simulation.preview;
        if (simulation?.status === "error") throw new Error(simulation.error);
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      throw new Error("the simulation did not answer");
    }

    it("names every skill and item of the build key from the seed's table", () => {
      for (const skill of full.bar.filter((id) => id !== 0)) {
        expect(NAMES.skill(skill), `skill ${skill}`).not.toMatch(/^Skill \d+$/);
      }
      for (const { item } of full.belt) {
        expect(NAMES.potion(item), `item ${item}`).not.toMatch(/^Item \d+$/);
      }
    });

    it("puts the four skills on the bar and the two potions on the belt, from the mirror", async () => {
      const { controller } = await controllerOn();
      const view = controller.combat.snapshot().view;
      expect(view, "the combat view needs the state's content").not.toBeNull();
      const { bar, belt } = view!.state.adventurer;
      const on = bar.filter((slot) => slot.skill !== null);
      expect(on.map((slot) => slot.skill!.id)).toEqual(full.bar.filter((id) => id !== 0));
      expect(on.map((slot) => slot.skill!.name)).toEqual(
        on.map((slot) => NAMES.skill(slot.skill!.id)),
      );
      expect(
        belt.filter((slot) => slot.item !== null).map((slot) => [slot.item, slot.count]),
      ).toEqual(full.belt.map(({ item, count }) => [item, count]));
    }, 120_000);

    it("plays a potion: the item action is simulated, played and equal to the mirror", async () => {
      const { stages, controller } = await controllerOn();
      const regeneration = controller.combat
        .snapshot()
        .view!.state.adventurer.belt.find((slot) => slot.item === 23)!;
      controller.combat.slot({ kind: "item", slot: regeneration.slot });
      controller.combat.slot({ kind: "item", slot: regeneration.slot });
      expect(stages.get().planned.map((p) => p.action)).toEqual([
        { kind: "item", slot: regeneration.slot, entity: 0 },
      ]);
      const preview = await answered(stages);
      if (preview.kind !== "simulated" || preview.chain.kind !== "played") {
        throw new Error(`not played: ${JSON.stringify(preview)}`);
      }
      expect(preview.chain.batch).toMatchObject({ played: 1, stop: Stop.None });
      expect(preview.mirror.kind).toBe("predicted");
      expect(preview.mismatches).toEqual([]);
      // The belt shows the state after the batch: none left of it
      const after = controller.combat.snapshot().view!.state.adventurer.belt[regeneration.slot]!;
      expect(after.state).toBe("none-left");
      controller.combat.slot({ kind: "item", slot: regeneration.slot });
      expect(controller.combat.snapshot().view?.said).toBe("None left.");
    }, 120_000);

    it("plays a skill on the adventurer, then refuses it on recharge, the batch unchanged", async () => {
      const { stages, controller } = await controllerOn();
      const wind = controller.combat
        .snapshot()
        .view!.state.adventurer.bar.find((slot) => slot.skill?.id === 2)!;
      controller.combat.slot({ kind: "skill", slot: wind.slot });
      controller.combat.slot({ kind: "skill", slot: wind.slot });
      expect(stages.get().planned.map((p) => p.action)).toEqual([
        { kind: "skill", slot: wind.slot, target: { tile: false, value: 0 } },
      ]);
      const preview = await answered(stages);
      if (preview.kind !== "simulated" || preview.chain.kind !== "played") {
        throw new Error(`not played: ${JSON.stringify(preview)}`);
      }
      expect(preview.chain.batch).toMatchObject({ played: 1, stop: Stop.None });
      expect(preview.mismatches).toEqual([]);
      // The same skill again: it recharges in the state after the batch, and the batch is unchanged
      controller.combat.slot({ kind: "skill", slot: wind.slot });
      expect(controller.combat.snapshot().view?.said).toMatch(/^Recharging: \d+ ticks?\.$/);
      expect(controller.combat.snapshot().view?.armed).toBeNull();
      expect(stages.get().planned).toHaveLength(1);
      expect(parity).toEqual([]);
    }, 120_000);

    it("plays the REGENERATION skill, and arms the trap without throwing", async () => {
      const { stages, controller } = await controllerOn();
      const bar = controller.combat.snapshot().view!.state.adventurer.bar;
      const mending = bar.find((slot) => slot.skill?.id === 4)!;
      const snare = bar.find((slot) => slot.skill?.id === 3)!;
      // The trap's reach is `aiming`'s: near the location's edge it has none (see ChainController)
      expect(() => controller.combat.slot({ kind: "skill", slot: snare.slot })).not.toThrow();
      controller.combat.escape();
      controller.combat.slot({ kind: "skill", slot: mending.slot });
      controller.combat.slot({ kind: "skill", slot: mending.slot });
      const preview = await answered(stages);
      if (preview.kind !== "simulated" || preview.chain.kind !== "played") {
        throw new Error(`not played: ${JSON.stringify(preview)}`);
      }
      expect(preview.chain.batch).toMatchObject({ played: 1, stop: Stop.None });
      expect(preview.mismatches).toEqual([]);
    }, 120_000);

    it("refuses a strike before the batch: no adrenaline at the start, or out of reach", async () => {
      const { stages, controller } = await controllerOn();
      const start = controller.combat.snapshot().view!;
      const strike = start.state.adventurer.bar.find((slot) => slot.skill?.id === 1)!;
      controller.combat.slot({ kind: "skill", slot: strike.slot });
      // Read after arming: the snapshot is replaced at each change
      const armed = controller.combat.snapshot().view!;
      if (strike.state !== "ready") {
        expect(armed.said).toMatch(
          /^(Not enough adrenaline|Not enough energy|Needs its weapon)\.$/,
        );
        expect(armed.armed).toBeNull();
        console.info(
          `full build: the strike is not ready at the start (${strike.state}), ` +
            "so the out-of-reach refusal is not exercised in this world",
        );
      } else {
        const far = armed.state.goblins.find(
          (g) => g.alive && !armed.aim?.marked.includes(g.entity),
        );
        if (far === undefined) {
          console.info(
            "full build: no living goblin outside the strike's reach in this world, the reach refusal is skipped",
          );
        } else {
          controller.combat.actor(far.entity);
          expect(controller.combat.snapshot().view?.said).toBe("Out of reach.");
          expect(controller.combat.snapshot().view?.armed).toEqual({
            kind: "skill",
            slot: strike.slot,
          });
        }
      }
      expect(stages.get().planned).toEqual([]);
    }, 120_000);
  },
);
