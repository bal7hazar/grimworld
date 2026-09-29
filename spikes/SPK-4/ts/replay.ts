// Option (a): replays the vectors of spikes/SPK-4/vectors on the TypeScript mirror.
//
// A divergence is a case where the mirror returns other felts than the Cairo code, returns where it
// panicked, or throws where it returned. A panic with other panic data than Cairo's is counted
// apart (the brief asks for a throw; the data is a stricter check).
//
//   node spikes/SPK-4/ts/replay.ts [vectors.jsonl] [--reps N]
//
// Exits 0 only when every vector agrees; 1 on a divergence or a panic-data difference; 2 on a
// usage error, a missing or unreadable file, or an empty one.

import { readFileSync } from "node:fs";

type Vector = { id: number; case: string[]; ok?: string[]; panic?: string[] };

function usage(message: string): never {
  console.error(`replay: ${message}\nusage: node spikes/SPK-4/ts/replay.ts [vectors.jsonl] [--reps N]`);
  process.exit(2);
}

let reps = 5;
const positional: string[] = [];
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--reps") {
    reps = Number(argv[++i]);
    if (!Number.isInteger(reps) || reps < 1) usage(`--reps needs a positive integer`);
  } else if (argv[i].startsWith("--")) usage(`unknown option ${argv[i]}`);
  else positional.push(argv[i]);
}
if (positional.length > 1) usage(`one vector file at most, got ${positional.length}`);
const path = positional[0] ?? new URL("../vectors/vectors.jsonl", import.meta.url).pathname;

let text: string;
try {
  text = readFileSync(path, "utf8");
} catch (e) {
  usage(`cannot read ${path}: ${(e as Error).message}`);
}
const lines = text.split("\n").filter((l) => l.length > 0);
if (lines.length === 0) usage(`${path} holds no vector`);

// Cold start, with the boundaries of the VM's bench (vm/js/bench-core.mjs): the files are read
// and the first vector parsed before the clock starts; then initialise (the mirror's modules; the
// VM: instantiate the wasm), load the executable (none for the mirror; the VM: parse it),
// serialise the first input (hex to bigint; the VM: hex to its argument string), execute it once.
const firstVector = JSON.parse(lines[0]) as Vector;
const c0 = performance.now();
const { CairoPanic, shortString } = await import("./cairo.ts");
const { run } = await import("./logic.ts");
const c1 = performance.now();
const firstCase = firstVector.case.map((x) => BigInt(x));
const c2 = performance.now();
try {
  run(firstCase);
} catch {
  // A panic is an outcome like another.
}
const c3 = performance.now();
const cold = {
  init_ms: +(c1 - c0).toFixed(3),
  load_executable_ms: 0,
  serialise_first_input_ms: +(c2 - c1).toFixed(3),
  first_execution_ms: +(c3 - c2).toFixed(3),
};

const vectors: Vector[] = lines.map((l) => JSON.parse(l) as Vector);
const cases = vectors.map((v) => v.case.map((x) => BigInt(x)));

type Outcome = { ok: bigint[] } | { panic: bigint[] } | { error: string };

function outcome(c: bigint[]): Outcome {
  try {
    return { ok: run(c) };
  } catch (e) {
    if (e instanceof CairoPanic) return { panic: e.data };
    return { error: String(e) };
  }
}

const same = (a: bigint[], b: string[]): boolean =>
  a.length === b.length && a.every((x, i) => x === BigInt(b[i]));

let divergences = 0;
let panicDataDiffers = 0;
const shown: string[] = [];
for (let i = 0; i < vectors.length; i++) {
  const v = vectors[i];
  const o = outcome(cases[i]);
  let diverges = false;
  let dataDiffers = false;
  if (v.ok) diverges = !("ok" in o) || !same(o.ok, v.ok);
  else if (v.panic) {
    diverges = !("panic" in o);
    dataDiffers = !diverges && "panic" in o && !same(o.panic, v.panic);
  } else diverges = true; // a vector without an expectation cannot pass
  if ("error" in o) diverges = true;
  if (diverges) divergences++;
  if (dataDiffers) panicDataDiffers++;
  if ((diverges || dataDiffers) && shown.length < 20) {
    const expected = v.ok
      ? `ok ${v.ok.join(" ")}`
      : v.panic
        ? `panic ${v.panic.map((f) => shortString(BigInt(f))).join(", ")}`
        : "no expectation";
    const got =
      "ok" in o
        ? `ok ${o.ok.map((x) => "0x" + x.toString(16)).join(" ")}`
        : "panic" in o
          ? `panic ${o.panic.map(shortString).join(", ")}`
          : `error ${o.error}`;
    shown.push(`  #${v.id} ${v.case.join(",")}\n    cairo:  ${expected}\n    mirror: ${got}`);
  }
}

// Timing: `reps` full replays after the checking pass (warm), the median.
const times: number[] = [];
for (let r = 0; r < reps; r++) {
  const s = performance.now();
  for (const c of cases) outcome(c);
  times.push(performance.now() - s);
}
times.sort((a, b) => a - b);
const median = times[Math.floor(times.length / 2)];
const panics = vectors.filter((v) => v.panic).length;

console.log(shown.join("\n"));
console.log(
  JSON.stringify(
    {
      vectors: vectors.length,
      panics,
      divergences,
      panic_data_differs: panicDataDiffers,
      file: path,
      cold,
      replay_ms_median: +median.toFixed(1),
      per_call_us: +((median * 1000) / vectors.length).toFixed(2),
      reps,
      node: process.version,
    },
    null,
    1,
  ),
);
process.exitCode = divergences + panicDataDiffers === 0 ? 0 : 1;
