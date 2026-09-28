// SPK-11: the local node's side of the scenarios: the pre-funded account, deploying the Market
// contract, sending its entrypoints, and devnet's own methods (abort blocks).
// Environment (exported by scripts/with-node.sh): NODE_URL, NODE_ACCOUNT_ADDRESS, NODE_ACCOUNT_PRIVATE_KEY.
import { readFileSync } from "node:fs";
import { Account, RpcProvider, type Call } from "starknet";

export const nodeUrl = process.env.NODE_URL!;
if (!nodeUrl) throw new Error("run under spikes/SPK-11/with-archive.sh (scripts/with-node.sh)");

export const provider = new RpcProvider({ nodeUrl });
export const account = new Account({
  provider,
  address: process.env.NODE_ACCOUNT_ADDRESS!,
  signer: process.env.NODE_ACCOUNT_PRIVATE_KEY!,
});

let id = 0;
export async function rpc(method: string, params: unknown = []): Promise<any> {
  const response = await fetch(nodeUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
  });
  const body = await response.json();
  if (body.error) throw new Error(`${method}: ${JSON.stringify(body.error)}`);
  return body.result;
}

export async function head(): Promise<{ number: number; hash: string }> {
  const result = await rpc("starknet_blockHashAndNumber");
  return { number: result.block_number, hash: result.block_hash };
}

/** Aborts every block from `from` to the tip (devnet only; needs the full state archive). */
export async function abortBlocks(from: number): Promise<string[]> {
  return (await rpc("devnet_abortBlocks", { starting_block_id: { block_number: from } })).aborted;
}

export async function deployMarket(): Promise<{ address: string; block: number }> {
  const target = new URL("./target/dev/", import.meta.url);
  const contract = JSON.parse(readFileSync(new URL("spk11_Market.contract_class.json", target), "utf8"));
  const casm = JSON.parse(readFileSync(new URL("spk11_Market.compiled_contract_class.json", target), "utf8"));
  const { class_hash } = await account.declareIfNot({ contract, casm }, { tip: 0n });
  const deployed = await account.deployContract({ classHash: class_hash }, { tip: 0n });
  const receipt: any = await provider.waitForTransaction(deployed.transaction_hash, { retryInterval: 20 });
  return { address: deployed.contract_address, block: receipt.block_number };
}

export type Sent = { tx: string; block: number; l2Gas: number; l1DataGas: number; events: number };

/** Sends the calls in one transaction and waits for its receipt. */
export async function send(address: string, calls: [entrypoint: string, ...calldata: (number | bigint)[]][]): Promise<Sent> {
  const payload: Call[] = calls.map(([entrypoint, ...calldata]) => ({
    contractAddress: address,
    entrypoint,
    calldata: calldata.map(String),
  }));
  const { transaction_hash } = await account.execute(payload, { tip: 0n });
  const receipt: any = await provider.waitForTransaction(transaction_hash, { retryInterval: 20 });
  if (receipt.execution_status !== "SUCCEEDED") throw new Error(`${transaction_hash}: ${receipt.revert_reason}`);
  return {
    tx: transaction_hash,
    block: receipt.block_number,
    l2Gas: Number(receipt.execution_resources.l2_gas),
    l1DataGas: Number(receipt.execution_resources.l1_data_gas),
    events: receipt.events.filter((event: any) => BigInt(event.from_address) === BigInt(address)).length,
  };
}
