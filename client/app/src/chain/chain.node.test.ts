import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import type { AccountProvider, Call, ExecutionId, ExecutionStatus, KeyStorage } from "../account";
import { type Opened, openChain, parseDeployment } from "./network";
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

/** The deployment's JSON, and whether to run: always when named, the fallback only when its node answers. */
async function locate(): Promise<unknown> {
  const named = env.GRIMWORLD_DEPLOYMENT;
  if (named) return JSON.parse(readFileSync(named, "utf8"));
  if (!existsSync(FALLBACK)) return undefined;
  const json = JSON.parse(readFileSync(FALLBACK, "utf8")) as { node_url?: unknown };
  try {
    const answer = await fetch(String(json.node_url), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "starknet_chainId", params: [] }),
      signal: AbortSignal.timeout(2000),
    });
    return answer.ok ? json : undefined;
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
});
