import { describe, expect, it } from "vitest";
import { createBurnerProvider } from "./burner";
import { LOCAL_ACCOUNT_CLASS, STRK, createNodeFunder, createStarknetChain } from "./starknet";
import { AccountError, type ExecutionStatus, type KeyStorage } from "./types";

// Against the real local node (NS-1), run through the script that starts and stops it:
//   scripts/with-node.sh pnpm --filter @grimworld/app test:node
// Without a node (the ordinary `pnpm test`), skipped.
const env = import.meta.env as Record<string, string | undefined>;
const nodeUrl = env.NODE_URL;

function memoryStorage(): KeyStorage {
  const data = new Map<string, string>();
  return {
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => void data.set(key, value),
    removeItem: (key) => void data.delete(key),
  };
}

async function settled(status: () => Promise<ExecutionStatus>): Promise<ExecutionStatus> {
  for (let i = 0; i < 200; i++) {
    const current = await status();
    if (current !== "pending") return current;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return "pending";
}

describe.skipIf(!nodeUrl)("the burner on the local node", () => {
  it("creates, executes one call, reports its status, signs out and restores", async () => {
    const config = { nodeUrl: nodeUrl!, accountClass: LOCAL_ACCOUNT_CLASS };
    const chain = createStarknetChain(config);
    const funder = createNodeFunder({
      ...config,
      funderAddress: env.NODE_ACCOUNT_ADDRESS!,
      funderKey: env.NODE_ACCOUNT_PRIVATE_KEY!,
      amount: 10n ** 19n,
      pollMs: 100,
    });
    const storage = memoryStorage();
    const provider = createBurnerProvider({ chain, funder, storage });

    const { address } = await provider.createOrRestore();
    expect(await chain.isDeployed(address)).toBe(true);

    // One call that writes: the burner approves the funder for 1 fri of STRK.
    const id = await provider.execute([
      { to: STRK, entrypoint: "approve", calldata: [env.NODE_ACCOUNT_ADDRESS!, 1n, 0n] },
    ]);
    expect(await settled(() => provider.status(id))).toBe("succeeded");

    // A call the chain refuses is reported neutrally.
    const refused = await provider
      .execute([{ to: STRK, entrypoint: "no_such_entrypoint", calldata: [] }])
      .catch((error: unknown) => error);
    expect(refused).toBeInstanceOf(AccountError);
    expect((refused as AccountError).code).toBe("refused");

    await provider.signOut();
    const out = await provider.execute([]).catch((error: unknown) => error);
    expect((out as AccountError).code).toBe("not-ready");

    // Restored from the device's storage by a new provider (a new page load): the same account,
    // and it still sends.
    const again = createBurnerProvider({ chain, funder, storage });
    expect(await again.createOrRestore()).toEqual({ address });
    const second = await again.execute([
      { to: STRK, entrypoint: "approve", calldata: [env.NODE_ACCOUNT_ADDRESS!, 2n, 0n] },
    ]);
    expect(await settled(() => again.status(second))).toBe("succeeded");
    expect(await again.status("0x1234" as never)).toBe("unknown");
  }, 120_000);
});
