// The browser side of vm/browser_bench.py: the same bench as the Node worker, files fetched over
// HTTP from spikes/SPK-4.

import init, { Runner } from "../../pkg-web/spk4_runner.js";
import { bench } from "../bench-core.mjs";

const get = async (path) => {
  const r = await fetch(new URL("../../../" + path, import.meta.url));
  if (!r.ok) throw new Error(`${path}: ${r.status}`);
  return r;
};

try {
  const sample = await fetch(new URL("../../../out/scarb-sample.jsonl", import.meta.url));
  const result = await bench({
    init,
    Runner,
    wasmBytes: new Uint8Array(await (await get("vm/pkg-web/spk4_runner_bg.wasm")).arrayBuffer()),
    stepJson: await (await get("exec/target/dev/step.executable.json")).text(),
    batchJson: await (await get("exec/target/dev/batch.executable.json")).text(),
    vectorsText: await (await get("vectors/vectors.jsonl")).text(),
    sampleText: sample.ok ? await sample.text() : null,
    now: () => performance.now(),
  });
  result.user_agent = navigator.userAgent;
  postMessage(result);
} catch (e) {
  postMessage({ error: String(e && e.stack ? e.stack : e) });
}
