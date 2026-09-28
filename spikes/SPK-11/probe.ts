// SPK-11: what devnet 0.10.0 does on `devnet_abortBlocks`, over HTTP and over its WebSocket
// subscriptions. No contract needed: blocks are made with `devnet_createBlock`.
//   STATE_ARCHIVE_CAPACITY=full scripts/with-node.sh node spikes/SPK-11/probe.ts
// Environment (exported by scripts/with-node.sh): NODE_URL.
const nodeUrl = process.env.NODE_URL;
if (!nodeUrl) throw new Error("run under scripts/with-node.sh");

let id = 0;
async function rpc(method: string, params: unknown = []): Promise<any> {
  const response = await fetch(nodeUrl!, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
  });
  return response.json();
}
const show = (label: string, value: unknown) => console.log(`${label}: ${JSON.stringify(value)}`);
const head = async () => (await rpc("starknet_blockHashAndNumber")).result;

show("specVersion", (await rpc("starknet_specVersion")).result);

// WebSocket: new heads, and whatever the node says on a reorg.
const ws = new WebSocket(nodeUrl.replace(/^http/, "ws") + "/ws");
const notes: unknown[] = [];
ws.onmessage = (message) => notes.push(JSON.parse(String(message.data)));
await new Promise((resolve, reject) => {
  ws.onopen = resolve;
  ws.onerror = reject;
});
ws.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "starknet_subscribeNewHeads", params: {} }));
await new Promise((resolve) => setTimeout(resolve, 200));

for (let i = 0; i < 3; i++) await rpc("devnet_createBlock");
const before = await head();
show("head before abort", before);
const b2 = (await rpc("starknet_getBlockWithTxHashes", { block_id: { block_number: 2 } })).result;
show("block 2 before", { hash: b2.block_hash, parent: b2.parent_hash });

show("abortBlocks from 2", await rpc("devnet_abortBlocks", { starting_block_id: { block_number: 2 } }));
show("head after abort", await head());
show(
  "block 2 by old hash",
  await rpc("starknet_getBlockWithTxHashes", { block_id: { block_hash: b2.block_hash } }),
);
await rpc("devnet_createBlock");
const b2new = (await rpc("starknet_getBlockWithTxHashes", { block_id: { block_number: 2 } })).result;
show("block 2 after a new block", { hash: b2new.block_hash, parent: b2new.parent_hash });
show("head after new block", await head());
show("getEvents on the old hash", await rpc("starknet_getEvents", {
  filter: { from_block: { block_hash: b2.block_hash }, to_block: { block_hash: b2.block_hash }, chunk_size: 10 },
}));
show("getEvents pre_confirmed", await rpc("starknet_getEvents", {
  filter: { from_block: "pre_confirmed", to_block: "pre_confirmed", chunk_size: 10 },
}));

await new Promise((resolve) => setTimeout(resolve, 300));
for (const note of notes) show("ws", note);
ws.close();
