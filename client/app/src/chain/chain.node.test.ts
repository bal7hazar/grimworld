import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import type { AccountProvider, Call, ExecutionId, ExecutionStatus, KeyStorage } from "../account";
import type { PlayAction } from "../preview/actions";
import { previewBatch } from "../preview/preview";
import { type BlockId, createReader } from "../preview/read";
import { createRpc, createRpcSimulator } from "../preview/rpc";
import { Stop } from "../preview/trace";
import { type Opened, SN_MAIN, assertTestChain, openChain, parseDeployment } from "./network";
import { type ChainState, type SendDeps, createSentReads, readState, sendBatch } from "./send";
import { type Stages, createStages } from "./stages";
import { type Player, type SetupDeps, enter, restore } from "./setup";

// The chain mode's setup against the game deployed on the local node (CLI-11 §7), run with the
// preview's node test, one file after the other, from the repository root once the classes are built:
//   pnpm --filter @grimworld/app test:node:devnet
// It reads `GRIMWORLD_DEPLOYMENT`, or `.with-node/deployment.json` at the repository's root when the
// variable is unset; that file outlives its node, so it is used only while its node answers. Without
// either (the ordinary `pnpm test`), skipped.
//
// It shares the node with `preview.node.test.ts`: account 0 is the deployment's and the preview
// test's, account 1 funds the burner, the burner sends from its own; the burner's adventurer is the
// first created after the deployment's, id 2.
const env = import.meta.env as Record<string, string | undefined>;
const FALLBACK = fileURLToPath(new URL("../../../../.with-node/deployment.json", import.meta.url));

/**
 * The deployment's JSON, and whether to run: always when named; the fallback only while its own node
 * answers for it (review t-0236): the node's chain id is the file's, and the file's Hub is deployed
 * there. Any other answer, an HTTP 200 included, is another node or none: skipped.
 */
async function locate(): Promise<unknown> {
  const named = env.GRIMWORLD_DEPLOYMENT;
  if (named) return JSON.parse(readFileSync(named, "utf8"));
  if (!existsSync(FALLBACK)) return undefined;
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
  const deps = (provider: AccountProvider): SetupDeps => ({
    provider,
    reader: opened.reader,
    ...deployment.contracts,
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
    opened = await openChain(raw.node_url, deployment, { storage });
  });

  it("makes the burner a player: funded by account 1, registered, built, entered", async () => {
    const { provider, sent, ids } = recording(opened.provider);
    player = await restore(deps(provider));
    expect(sent).toEqual([["register", "create_adventurer"], ["set_build"], ["enter"]]);
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
  }, 180_000);

  it("restores the same adventurer and instance from a second provider on the same storage", async () => {
    const again = await openChain(raw.node_url, deployment, { storage });
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
    // adventurer
    await enter(deps(provider), player.adventurerId);
    expect(sent).toEqual([["travel_back"], ["set_build"], ["enter"]]);
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
    const ids = () => ({
      instances: deployment.contracts.instances,
      registry: deployment.contracts.registry,
      instanceId: player.instanceId,
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
