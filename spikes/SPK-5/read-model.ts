// SPK-5: reads back, through dojo.js, the `spk5-Marker` model that the `mark` system wrote and
// that Torii indexed. Run with Node (type stripping): `node spikes/SPK-5/read-model.ts <value>`.
// Environment (exported by scripts/with-katana.sh --torii): TORII_GRPC_URL, DOJO_WORLD_ADDRESS.
//
// Uses @dojoengine/grpc directly, not @dojoengine/sdk/node: the SDK's Node entry imports
// @dojoengine/torii-wasm@1.8.2, whose `node.mjs` requires a file the package does not ship
// (see docs/research/SPK-5-toolchain.md).
import { ToriiGrpcClient } from "@dojoengine/grpc";

const expected = Number(process.argv[2]);
const toriiUrl = process.env.TORII_GRPC_URL;
const worldAddress = process.env.DOJO_WORLD_ADDRESS;
if (!toriiUrl || !worldAddress || Number.isNaN(expected)) {
  console.error("usage: TORII_GRPC_URL=… DOJO_WORLD_ADDRESS=… node read-model.ts <expected value>");
  process.exit(2);
}

const client = new ToriiGrpcClient({ toriiUrl, worldAddress });

type Field = { value: string | number };
type Marker = { owner: Field; value: Field };

// Torii indexes a block a moment after it is mined: poll for up to 30 s.
let marker: Marker | undefined;
for (let attempt = 0; attempt < 60 && marker === undefined; attempt++) {
  const entities = await client.getAllEntities(100);
  const entity = entities.items.find((item) => "spk5-Marker" in item.models);
  marker = entity?.models["spk5-Marker"] as unknown as Marker | undefined;
  if (marker === undefined) await new Promise((resolve) => setTimeout(resolve, 500));
}

if (marker === undefined) {
  console.error("spk5-Marker not found in Torii after 30 s");
  process.exit(1);
}
console.log(`spk5-Marker { owner: ${marker.owner.value}, value: ${marker.value.value} }`);
process.exit(Number(marker.value.value) === expected ? 0 : 1);
