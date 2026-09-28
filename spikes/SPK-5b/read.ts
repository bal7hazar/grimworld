// SPK-5b: calls the view of the Mark contract and decodes its `Marked` event from the receipt,
// with starknet.js, typing both from the ABI of the compiled class.
//   node spikes/SPK-5b/read.ts <contract address> <invoke transaction hash> <expected value>
// Environment (exported by scripts/with-node.sh): NODE_URL.
import { readFileSync } from "node:fs";
import { Contract, RpcProvider } from "starknet";

const [address, txHash, expectedText] = process.argv.slice(2);
const nodeUrl = process.env.NODE_URL;
if (!address || !txHash || !expectedText || !nodeUrl) {
  console.error("usage: NODE_URL=… node read.ts <address> <transaction hash> <expected value>");
  process.exit(2);
}
const expected = BigInt(expectedText);

const classPath = new URL("./target/dev/spk5b_Mark.contract_class.json", import.meta.url);
const { abi } = JSON.parse(readFileSync(classPath, "utf8"));

const provider = new RpcProvider({ nodeUrl });
const contract = new Contract({ abi, address, providerOrAccount: provider });

const value = BigInt(await contract.get());
console.log(`get() = ${value}`);

const receipt = await provider.waitForTransaction(txHash);
const events = contract.parseEvents(receipt);
console.log("parsed events:", JSON.stringify(events, (_, v) => (typeof v === "bigint" ? `0x${v.toString(16)}` : v)));

// Each parsed event is { transaction_hash, block_hash, block_number, "<event path>": { fields } }.
const marked = events.flatMap((event) =>
  Object.entries(event)
    .filter(([name]) => name.endsWith("::Marked"))
    .map(([, fields]) => fields as { owner: bigint; value: bigint }),
);
const ok = value === expected && marked.length === 1 && BigInt(marked[0].value) === expected;
console.log(ok ? "ok" : "MISMATCH");
process.exit(ok ? 0 : 1);
