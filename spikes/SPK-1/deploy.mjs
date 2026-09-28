// SPK-1 step 1: declare and deploy SPK-2's native contracts (spikes/SPK-2/native/, unchanged,
// built by `scarb build`) on Sepolia, link them, and write their classes and addresses to
// sepolia.json. 7 transactions: 2 declares, 2 deploys, 2 links, setup_hub.
//   scripts/lock.sh scarb --manifest-path spikes/SPK-2/native/Scarb.toml build
//   node spikes/SPK-1/deploy.mjs > spikes/SPK-1/deploy-output.txt
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { hash } from "starknet";
import {
  account, accountAddress, describe, emit, makeSender, now, provider, requireSepolia, rpc, strk, strkBalance,
  versions,
} from "./lib.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TARGET = join(HERE, "..", "SPK-2", "native", "target", "dev");
const OUT = join(HERE, "sepolia.json");
if (existsSync(OUT)) {
  console.error("sepolia.json exists: the contracts are deployed; nothing is sent");
  process.exit(4);
}

/** A class declared by an earlier, interrupted run of this script: its declare transaction, from
 * the recent blocks (read only), so that its fee is counted. */
async function findDeclare(classHash) {
  const latest = (await rpc("starknet_blockNumber"));
  for (let n = latest; n > latest - 400; n -= 1) {
    const block = await rpc("starknet_getBlockWithTxs", { block_id: { block_number: n } });
    for (const t of block.transactions) {
      if (t.type === "DECLARE" && BigInt(t.class_hash) === BigInt(classHash)
          && BigInt(t.sender_address) === BigInt(accountAddress())) {
        return t.transaction_hash;
      }
    }
  }
  return null;
}

const chain = await requireSepolia();
const acc = account();
const before = await strkBalance();
emit({ step: "start", at: now(), chain, strk_balance: strk(before) });

const deployed = {};
const txs = [];
for (const name of ["Hub", "Instances"]) {
  const contract = JSON.parse(readFileSync(join(TARGET, `spk2n_${name}.contract_class.json`), "utf8"));
  const casm = JSON.parse(readFileSync(join(TARGET, `spk2n_${name}.compiled_contract_class.json`), "utf8"));
  const declare = await acc.declareIfNot({ contract, casm });
  let declareTx = declare.transaction_hash || (await findDeclare(declare.class_hash));
  if (declareTx) {
    emit({ step: `declare ${name} sent`, tx: declareTx });
    await provider.waitForTransaction(declareTx);
    const record = await describe(declareTx);
    emit({ step: `declare ${name}`, ...record });
    txs.push(record);
  }
  const classHash = declare.class_hash ?? hash.computeContractClassHash(contract);
  const deploy = await acc.deployContract({ classHash, constructorCalldata: [accountAddress()] });
  emit({ step: `deploy ${name} sent`, tx: deploy.transaction_hash });
  await provider.waitForTransaction(deploy.transaction_hash);
  const record = await describe(deploy.transaction_hash);
  emit({ step: `deploy ${name}`, ...record });
  txs.push(record);
  deployed[name] = {
    class_hash: classHash,
    compiled_class_hash_blake2s: hash.computeCompiledClassHashBlake(casm),
    ...(await versions(classHash)),
    address: deploy.contract_address,
    declare_tx: declareTx,
    deploy_tx: deploy.transaction_hash,
  };
}

const HUB = deployed.Hub.address;
const INST = deployed.Instances.address;
const { send, count } = await makeSender(acc, 3);
for (const [label, contractAddress, entrypoint, calldata] of [
  ["link hub", HUB, "set_instances", [INST]],
  ["link instances", INST, "set_hub", [HUB]],
  ["setup hub", HUB, "setup_hub", [accountAddress()]],
]) {
  txs.push(await send(label, [{ contractAddress, entrypoint, calldata }]));
}

const after = await strkBalance();
const sepolia = {
  network: "SN_SEPOLIA",
  deployed_at: now(),
  source: "spikes/SPK-2/native (unchanged), scarb build, Cairo 2.19",
  admin: "the owner's Sepolia account (address not recorded)",
  contracts: deployed,
  transactions: txs.length,
  fee_fri: txs.reduce((s, r) => s + r.fee, 0n).toString(),
};
writeFileSync(OUT, `${JSON.stringify(sepolia, null, 2)}\n`);
emit({ step: "done", at: now(), transactions: txs.length, sender_count: count(), fee_strk: strk(BigInt(sepolia.fee_fri)),
  balance_delta_strk: strk(before - after) });
