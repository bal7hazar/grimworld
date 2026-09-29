// Option (b) in a Node worker thread (the shape a client worker has).
//
//   node spikes/SPK-4/vm/js/node-bench.mjs
//
// Needs the web bindings in spikes/SPK-4/vm/pkg-web (vm/build.sh) and the executables of
// spikes/SPK-4/exec built by Scarb.

import { Worker, isMainThread, parentPort } from "node:worker_threads";
import { readFileSync, existsSync } from "node:fs";

const spike = new URL("../../", import.meta.url);
const at = (p) => new URL(p, spike);

if (isMainThread) {
  const worker = new Worker(new URL(import.meta.url));
  const result = await new Promise((resolve, reject) => {
    worker.on("message", resolve);
    worker.on("error", reject);
  });
  await worker.terminate();
  result.node = process.version;
  result.process_max_rss_mb = +(process.resourceUsage().maxRSS / 1024).toFixed(1);
  console.log(JSON.stringify(result, null, 1));
  process.exitCode = result.step.divergences + result.batch.divergences + (result.scarb_sample?.differs ?? 0) === 0 ? 0 : 1;
} else {
  const { default: init, Runner } = await import(at("vm/pkg-web/spk4_runner.js").href);
  const { bench } = await import(new URL("./bench-core.mjs", import.meta.url).href);
  const sample = at("out/scarb-sample.jsonl");
  const result = await bench({
    init,
    Runner,
    wasmBytes: readFileSync(at("vm/pkg-web/spk4_runner_bg.wasm")),
    stepJson: readFileSync(at("exec/target/dev/step.executable.json"), "utf8"),
    batchJson: readFileSync(at("exec/target/dev/batch.executable.json"), "utf8"),
    vectorsText: readFileSync(at("vectors/vectors.jsonl"), "utf8"),
    sampleText: existsSync(sample) ? readFileSync(sample, "utf8") : null,
    now: () => performance.now(),
  });
  parentPort.postMessage(result);
}
