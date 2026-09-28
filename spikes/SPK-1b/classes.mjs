// SPK-1b, read only: which account classes are already declared on Sepolia, their Sierra and
// compiler versions, and whether they expose SNIP-9 (outside execution). Sends nothing.
//   node spikes/SPK-1b/classes.mjs <class hash>...
import { configure, rpcRaw, versions } from "./lib.mjs";

configure();
for (const classHash of process.argv.slice(2)) {
  const answer = await rpcRaw("starknet_getClass", { block_id: "latest", class_hash: classHash });
  if (answer.error) {
    console.log(JSON.stringify({ classHash, declared: false, error: answer.error.message }));
    continue;
  }
  const abi = typeof answer.result.abi === "string" ? JSON.parse(answer.result.abi) : answer.result.abi;
  const names = [];
  for (const item of abi) {
    if (item.type === "interface") names.push(item.name);
    if (item.type === "impl") names.push(`impl ${item.name}`);
  }
  const functions = JSON.stringify(abi).match(/"name":"(execute_from_outside(_v2)?|is_valid_outside_execution|__validate_deploy__|get_public_key|set_public_key)"/g) ?? [];
  console.log(JSON.stringify({
    classHash,
    declared: true,
    ...(await versions(classHash)),
    interfaces: names,
    functions: [...new Set(functions.map((f) => f.slice(8, -1)))],
    sierra_felts: answer.result.sierra_program?.length ?? null,
  }));
}
