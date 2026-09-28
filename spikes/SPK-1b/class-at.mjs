// SPK-1b, read only: the class of a contract and its Sierra and compiler versions (Cairo 0 when it
// has no Sierra program). Sends nothing.
//   node spikes/SPK-1b/class-at.mjs <address>...
import { configure, rpc, versions } from "./lib.mjs";

configure();
for (const address of process.argv.slice(2)) {
  const classHash = await rpc("starknet_getClassHashAt", { block_id: "latest", contract_address: address });
  console.log(JSON.stringify({ address, classHash, ...(await versions(classHash)) }));
}
