// SPK-11: does devnet 0.10.0 give a replaced block another hash? Posts a lot, aborts its block,
// posts another lot (other calldata) at the same height, and compares the two headers.
//   spikes/SPK-11/with-archive.sh node spikes/SPK-11/probe-hash.ts
import { abortBlocks, deployMarket, rpc, send } from "./chain.ts";

const header = async (number: number) => {
  const block = await rpc("starknet_getBlockWithTxHashes", { block_id: { block_number: number } });
  const { block_hash, parent_hash, timestamp, new_root, state_diff_commitment, transaction_commitment, event_commitment, receipt_commitment, transactions } = block;
  return { block_hash, parent_hash, timestamp, new_root, state_diff_commitment, transaction_commitment, event_commitment, receipt_commitment, transactions };
};

const market = await deployMarket();
const first = await send(market.address, [["post", 7, 1, 120]]);
const before = await header(first.block);
console.log("original", JSON.stringify(before, null, 1));
await abortBlocks(first.block);
await new Promise((resolve) => setTimeout(resolve, 1500));
const second = await send(market.address, [["post", 7, 1, 999], ["locate", 1, 1]]);
const after = await header(second.block);
console.log("replacement", JSON.stringify(after, null, 1));
console.log(`same number: ${first.block === second.block}; same hash: ${before.block_hash === after.block_hash}; same transactions: ${JSON.stringify(before.transactions) === JSON.stringify(after.transactions)}`);
