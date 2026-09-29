// The only code of the indexer package that deploys or invokes (IDX-01a, *Sending transactions, on
// the local node only*). It refuses unless the RPC URL's host is 127.0.0.1 or localhost, and it
// uses only the account that scripts/with-node.sh exports (NODE_ACCOUNT_ADDRESS,
// NODE_ACCOUNT_PRIVATE_KEY, devnet's seed-0 account). It never reads STARKNET_*. devnet's chain id
// is SN_SEPOLIA too, so the check is on the host, not on the chain id. Nothing here exports the
// account: only the deploy and send functions below.
import { readFileSync } from "node:fs";
import { Account, RpcProvider, type Call } from "starknet";

const LOCAL_HOSTS = new Set(["127.0.0.1", "localhost"]);

/** Throws unless `url` points at this machine. */
export function assertLocal(url: string | undefined): string {
  if (!url)
    throw new Error("NODE_URL is not set: run under scripts/with-node.sh");
  const { hostname } = new URL(url);
  if (!LOCAL_HOSTS.has(hostname)) {
    throw new Error(
      `refused: ${hostname} is not the local node (127.0.0.1 or localhost)`,
    );
  }
  return url;
}

export type LocalNode = {
  url: string;
  /** Declares (if needed) and deploys a contract of the emitter; its address and block. */
  deploy: (contract: string) => Promise<{ address: string; block: number }>;
  /** Sends the calls in one transaction; its block, once accepted. */
  send: (calls: Call[]) => Promise<number>;
  /** devnet_abortBlocks: removes the blocks from `from` to the tip (full state archive). */
  abortBlocks: (from: number) => Promise<string[]>;
  /** starknet_blockNumber. */
  blockNumber: () => Promise<number>;
};

const TARGET = new URL("../emitter/target/dev/", import.meta.url);

export function localNode(): LocalNode {
  const url = assertLocal(process.env.NODE_URL);
  const address = process.env.NODE_ACCOUNT_ADDRESS;
  const privateKey = process.env.NODE_ACCOUNT_PRIVATE_KEY;
  if (!address || !privateKey) {
    throw new Error(
      "NODE_ACCOUNT_ADDRESS or NODE_ACCOUNT_PRIVATE_KEY is not set",
    );
  }
  const provider = new RpcProvider({ nodeUrl: url });
  const account = new Account({ provider, address, signer: privateKey });
  let id = 0;
  const rpc = async (method: string, params: unknown): Promise<unknown> => {
    const response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
    });
    const body = (await response.json()) as {
      result?: unknown;
      error?: unknown;
    };
    if (body.error) throw new Error(`${method}: ${JSON.stringify(body.error)}`);
    return body.result;
  };
  const accepted = async (hash: string): Promise<number> => {
    const receipt = (await provider.waitForTransaction(hash, {
      retryInterval: 20,
    })) as unknown as {
      execution_status?: string;
      revert_reason?: string;
      block_number: number;
    };
    if (receipt.execution_status !== "SUCCEEDED") {
      throw new Error(`${hash} reverted: ${receipt.revert_reason}`);
    }
    return receipt.block_number;
  };
  const artifact = (file: string) =>
    JSON.parse(readFileSync(new URL(file, TARGET), "utf8"));
  return {
    url,
    async deploy(contract) {
      const name = `grimworld_indexer_emitter_${contract}`;
      const { class_hash } = await account.declareIfNot(
        {
          contract: artifact(`${name}.contract_class.json`),
          casm: artifact(`${name}.compiled_contract_class.json`),
        },
        { tip: 0n },
      );
      const deployed = await account.deployContract(
        { classHash: class_hash },
        { tip: 0n },
      );
      const block = await accepted(deployed.transaction_hash);
      return { address: deployed.contract_address, block };
    },
    async send(calls) {
      const { transaction_hash } = await account.execute(calls, { tip: 0n });
      return accepted(transaction_hash);
    },
    async abortBlocks(from) {
      const result = (await rpc("devnet_abortBlocks", {
        starting_block_id: { block_number: from },
      })) as { aborted: string[] };
      return result.aborted;
    },
    async blockNumber() {
      return (await rpc("starknet_blockNumber", [])) as number;
    },
  };
}
