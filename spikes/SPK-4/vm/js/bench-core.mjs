// Option (b), measured the same way in a Node worker and in a browser worker: the WebAssembly
// runner (spikes/SPK-4/vm/runner, the web bindings of wasm-bindgen) runs the Scarb executables of
// spikes/SPK-4/exec, which `scarb execute` ran to make the vectors.
//
// 1. `step` (one action per call, as the client would run it) on every vector: outcome compared,
//    time per call, Cairo steps.
// 2. `batch` (the executable the vectors were printed by) with the generator's very arguments:
//    its prints and panics compared, i.e. the same artifact and input as `scarb execute`.
// 3. Optionally, a sample of vectors that `scarb execute` ran through `step` itself
//    (vm/scarb_sample.py): outputs and step counts compared.

const BATCH = 500;

const hex = (x) => "0x" + BigInt(x).toString(16);

function sameFelts(a, b) {
  return a.length === b.length && a.every((x, i) => BigInt(x) === BigInt(b[i]));
}

function percentile(sorted, p) {
  return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length * p) / 100))];
}

const serialise = (c) => [c.length, ...c].map(hex).join(",");

export async function bench({ init, Runner, wasmBytes, stepJson, batchJson, vectorsText, sampleText, now }) {
  const r = {};
  // Cold start, with the boundaries of the mirror's replay (ts/replay.ts): the files are read and
  // the first vector parsed before the clock starts; then initialise (instantiate the wasm), load
  // the executable (parse it into a Program), serialise the first input (hex to the argument
  // string), execute it once (the run and the decoding of its JSON outcome).
  const lines = vectorsText.split("\n").filter((l) => l.length > 0);
  if (lines.length === 0) throw new Error("no vector");
  const firstVector = JSON.parse(lines[0]);
  const t0 = now();
  const wasm = await init({ module_or_path: wasmBytes });
  const t1 = now();
  const step = new Runner(stepJson);
  const t2 = now();
  const firstArgs = serialise(firstVector.case);
  const t3 = now();
  JSON.parse(step.run(firstArgs));
  const t4 = now();
  r.wasm_bytes = wasmBytes.byteLength;
  r.cold = {
    init_ms: +(t1 - t0).toFixed(3),
    load_executable_ms: +(t2 - t1).toFixed(3),
    serialise_first_input_ms: +(t3 - t2).toFixed(3),
    first_execution_ms: +(t4 - t3).toFixed(3),
  };
  r.bytecode_felts = step.bytecodeLen();
  const vectors = lines.map((l) => JSON.parse(l));
  const args = vectors.map((v) => serialise(v.case));
  const run = (i) => JSON.parse(step.run(args[i]));

  // 1. Every vector through `step`.
  let divergences = 0;
  let steps = 0;
  let maxSteps = 0;
  const byOp = {};
  const shown = [];
  const outcomes = [];
  for (let i = 0; i < vectors.length; i++) {
    const v = vectors[i];
    const o = run(i);
    outcomes.push(o);
    // `step` returns an Array<felt252>: its length, then the felts.
    const ok = o.ok ? sameFelts(o.ok.slice(1), v.ok ?? [null]) && v.ok !== undefined : false;
    const panic = o.panic ? v.panic !== undefined && sameFelts(o.panic, v.panic) : false;
    if (!(ok || panic)) {
      divergences++;
      if (shown.length < 10) shown.push({ id: v.id, got: o, want: v });
    }
    steps += o.steps;
    maxSteps = Math.max(maxSteps, o.steps);
    if (o.ok && (v.case[0] === "0x0" || v.case[0] === "0x1")) {
      const k = v.case[0] === "0x0" ? "damage" : "goblin_step";
      const b = (byOp[k] ??= { n: 0, sum: 0, max: 0 });
      b.n++;
      b.sum += o.steps;
      b.max = Math.max(b.max, o.steps);
    }
  }
  const stepsByOp = {};
  for (const [k, b] of Object.entries(byOp)) stepsByOp[k] = { ok_runs: b.n, mean: +(b.sum / b.n).toFixed(1), max: b.max };
  r.step = {
    vectors: vectors.length,
    divergences,
    shown,
    mean_steps: +(steps / vectors.length).toFixed(1),
    max_steps: maxSteps,
    steps_by_op: stepsByOp,
  };

  // Timing: three passes, per-call times of the median pass.
  const passes = [];
  for (let p = 0; p < 3; p++) {
    const times = new Float64Array(vectors.length);
    const s = now();
    for (let i = 0; i < vectors.length; i++) {
      const a = now();
      step.run(args[i]);
      times[i] = now() - a;
    }
    passes.push({ total: now() - s, times: Array.from(times).sort((x, y) => x - y) });
  }
  passes.sort((a, b) => a.total - b.total);
  const mid = passes[1];
  r.timing = {
    replay_ms: +mid.total.toFixed(1),
    per_call_us_mean: +((mid.total * 1000) / vectors.length).toFixed(1),
    per_call_us_p50: +(percentile(mid.times, 50) * 1000).toFixed(1),
    per_call_us_p95: +(percentile(mid.times, 95) * 1000).toFixed(1),
    per_call_us_max: +(mid.times[mid.times.length - 1] * 1000).toFixed(1),
    by_op_us_mean: {},
  };
  for (const op of ["0x0", "0x1"]) {
    const idx = vectors.map((v, i) => (v.case[0] === op && v.ok ? i : -1)).filter((i) => i >= 0);
    if (idx.length === 0) continue;
    const s = now();
    for (const i of idx) step.run(args[i]);
    r.timing.by_op_us_mean[op === "0x0" ? "damage" : "goblin_step"] = +(((now() - s) * 1000) / idx.length).toFixed(1);
  }

  // 2. `batch`, with the generator's arguments.
  const batch = new Runner(batchJson);
  let i = 0;
  let runs = 0;
  let batchDivergences = 0;
  const tb = now();
  while (i < vectors.length) {
    const cases = vectors.slice(i, i + BATCH).map((v) => v.case);
    const flat = cases.flatMap((c) => [c.length, ...c]);
    const o = JSON.parse(batch.run([flat.length, ...flat].map(hex).join(",")));
    runs++;
    const printed = o.prints
      .map((p) => p.trim())
      .filter((p) => p.startsWith("r "))
      .map((p) => {
        const body = p.slice(3, -1).trim();
        return body ? body.split(",").map((x) => BigInt(x.trim())) : [];
      });
    for (let k = 0; k < printed.length; k++) {
      const v = vectors[i + k];
      if (!v.ok || !sameFelts(printed[k], v.ok)) batchDivergences++;
    }
    i += printed.length;
    if (o.panic) {
      const v = vectors[i];
      if (!v.panic || !sameFelts(o.panic, v.panic)) batchDivergences++;
      i++;
    } else if (printed.length !== cases.length) {
      batchDivergences += cases.length - printed.length;
      i += cases.length - printed.length;
    }
  }
  r.batch = { runs, divergences: batchDivergences, ms: +(now() - tb).toFixed(1) };

  // 3. The sample `scarb execute` ran through `step`: every sampled id must be among the vectors.
  const byId = new Map(vectors.map((v, k) => [v.id, k]));
  if (sampleText) {
    const sample = sampleText
      .split("\n")
      .filter((l) => l.length > 0)
      .map((l) => JSON.parse(l));
    let differs = 0;
    let missing = 0;
    let stepsCompared = 0;
    const stepDelta = new Set();
    for (const s of sample) {
      const k = byId.get(s.id);
      if (k === undefined) {
        missing++;
        continue;
      }
      const o = outcomes[k];
      const same = s.ok ? o.ok && sameFelts(o.ok, s.ok) : o.panic && sameFelts(o.panic, s.panic);
      if (!same) differs++;
      // Steps exist for successful runs only: scarb prints no resources for a panic.
      if (s.steps !== undefined && o.ok) {
        stepsCompared++;
        stepDelta.add(s.steps - o.steps);
      }
    }
    r.scarb_sample = {
      cases: sample.length,
      missing,
      differs,
      successful_runs_steps_compared: stepsCompared,
      steps_scarb_minus_wasm: [...stepDelta],
    };
  }
  r.wasm_memory_bytes = wasm.memory.buffer.byteLength;

  // The verdict: anything short of full agreement and full verification is a failure.
  const failures = [];
  if (r.step.divergences) failures.push(`${r.step.divergences} divergence(s) through step`);
  if (r.batch.divergences) failures.push(`${r.batch.divergences} divergence(s) through batch`);
  if (!r.scarb_sample) failures.push("no scarb sample: verification incomplete");
  else {
    if (r.scarb_sample.differs) failures.push(`${r.scarb_sample.differs} sampled case(s) differ from scarb execute`);
    if (r.scarb_sample.missing) failures.push(`${r.scarb_sample.missing} sampled id(s) absent from the vectors`);
    if (r.scarb_sample.cases === 0) failures.push("empty scarb sample: verification incomplete");
  }
  r.failures = failures;
  return r;
}
