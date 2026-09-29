// The browser side of vm/browser_bench.py: the same bench as the Node worker, files fetched over
// HTTP from spikes/SPK-4. The page passes `vectors` and `sample`, paths relative to spikes/SPK-4.

import init, { Runner } from "../../pkg-web/spk4_runner.js";
import { bench } from "../bench-core.mjs";

const params = new URL(self.location.href).searchParams;

const get = async (path) => {
  const r = await fetch(new URL("../../../" + path, import.meta.url));
  if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
  return r;
};

try {
  const result = await bench({
    init,
    Runner,
    wasmBytes: new Uint8Array(await (await get("vm/pkg-web/spk4_runner_bg.wasm")).arrayBuffer()),
    stepJson: await (await get("exec/target/dev/step.executable.json")).text(),
    batchJson: await (await get("exec/target/dev/batch.executable.json")).text(),
    vectorsText: await (await get(params.get("vectors"))).text(),
    sampleText: await (await get(params.get("sample"))).text(),
    now: () => performance.now(),
  });
  result.user_agent = navigator.userAgent;
  postMessage(result);
} catch (e) {
  postMessage({ error: String(e && e.stack ? e.stack : e) });
}
