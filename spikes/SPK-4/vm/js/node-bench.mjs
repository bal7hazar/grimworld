// Option (b) in a Node worker thread (the shape a client worker has).
//
//   node spikes/SPK-4/vm/js/node-bench.mjs [--vectors FILE] [--sample FILE]
//
// Defaults: spikes/SPK-4/vectors/vectors.jsonl and spikes/SPK-4/vectors/scarb-sample.jsonl.
// Exits 0 only when every check agrees and the verification is complete (bench-core's verdict);
// 1 otherwise, including a worker error; 2 on a usage error or a missing file.
// Needs the web bindings in spikes/SPK-4/vm/pkg-web (vm/build.sh) and the executables of
// spikes/SPK-4/exec built by Scarb.

import { Worker, isMainThread, parentPort, workerData } from "node:worker_threads";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

const spike = new URL("../../", import.meta.url);
const at = (p) => new URL(p, spike);

if (isMainThread) {
  const opts = {
    vectors: at("vectors/vectors.jsonl").pathname,
    sample: at("vectors/scarb-sample.jsonl").pathname,
  };
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i].replace(/^--/, "");
    if (!(key in opts) || argv[i + 1] === undefined) {
      console.error(`node-bench: usage: [--vectors FILE] [--sample FILE], got ${argv[i]}`);
      process.exit(2);
    }
    opts[key] = resolve(argv[++i]);
  }
  for (const [k, p] of Object.entries(opts)) {
    if (!existsSync(p)) {
      console.error(`node-bench: --${k} ${p} does not exist`);
      process.exit(2);
    }
  }
  const worker = new Worker(new URL(import.meta.url), { workerData: opts });
  let result;
  try {
    result = await new Promise((ok, fail) => {
      worker.on("message", ok);
      worker.on("error", fail);
      worker.on("exit", (code) => fail(new Error(`worker exited with ${code} before a result`)));
    });
  } catch (e) {
    console.error(`node-bench: FAIL: ${e.stack ?? e}`);
    process.exit(1);
  }
  await worker.terminate();
  result.vectors_file = opts.vectors;
  result.sample_file = opts.sample;
  result.node = process.version;
  result.process_max_rss_mb = +(process.resourceUsage().maxRSS / 1024).toFixed(1);
  console.log(JSON.stringify(result, null, 1));
  if (result.failures.length > 0) {
    console.error(`node-bench: FAIL: ${result.failures.join("; ")}`);
    process.exitCode = 1;
  }
} else {
  const { default: init, Runner } = await import(at("vm/pkg-web/spk4_runner.js").href);
  const { bench } = await import(new URL("./bench-core.mjs", import.meta.url).href);
  const result = await bench({
    init,
    Runner,
    wasmBytes: readFileSync(at("vm/pkg-web/spk4_runner_bg.wasm")),
    stepJson: readFileSync(at("exec/target/dev/step.executable.json"), "utf8"),
    batchJson: readFileSync(at("exec/target/dev/batch.executable.json"), "utf8"),
    vectorsText: readFileSync(workerData.vectors, "utf8"),
    sampleText: readFileSync(workerData.sample, "utf8"),
    now: () => performance.now(),
  });
  parentPort.postMessage(result);
}
