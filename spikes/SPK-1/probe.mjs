// SPK-1, read only (no transaction): the network, the account's class and balance, the prices.
//   node spikes/SPK-1/probe.mjs > spikes/SPK-1/probe-output.txt
import { accountAddress, emit, now, provider, requireSepolia, rpc, strk, strkBalance, versions } from "./lib.mjs";

const chain = await requireSepolia();
const spec = await rpc("starknet_specVersion");
const classHash = await rpc("starknet_getClassHashAt", { block_id: "latest", contract_address: accountAddress() });
const block = await rpc("starknet_getBlockWithTxHashes", ["latest"]);
const tip = await provider.getEstimateTip("latest", { maxBlocks: 20 });
emit({
  read_at: now(),
  chain,
  spec,
  starknet_version: block.starknet_version,
  block_number: block.block_number,
  l2_gas_fri: BigInt(block.l2_gas_price.price_in_fri),
  l1_data_gas_fri: BigInt(block.l1_data_gas_price.price_in_fri),
  l1_gas_fri: BigInt(block.l1_gas_price.price_in_fri),
  account_class_hash: classHash,
  account_class: await versions(classHash),
  strk_balance: strk(await strkBalance()),
  tip: { recommended: tip.recommendedTip, median: tip.medianTip, p90: tip.p90Tip },
});
