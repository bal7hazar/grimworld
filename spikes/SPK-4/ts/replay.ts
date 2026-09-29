// Option (a): replays the vectors of spikes/SPK-4/vectors on the TypeScript mirror.
//
// A divergence is a case where the mirror returns other felts than the Cairo code, returns where it
// panicked, or throws where it returned. A panic with other panic data than Cairo's is counted
// apart (the brief asks for a throw; the data is a stricter check).
//
//   node spikes/SPK-4/ts/replay.ts [vectors.jsonl] [--reps 5]

import { readFileSync } from "node:fs";
import { CairoPanic, shortString } from "./cairo.ts";
import { run } from "./logic.ts";

type Vector = { id: number; case: string[]; ok?: string[]; panic?: string[] };

const args = process.argv.slice(2);
const repsAt = args.indexOf("--reps");
const reps = repsAt >= 0 ? Number(args[repsAt + 1]) : 5;
const path = args.find((a, i) => !a.startsWith("--") && i !== repsAt + 1) ??
  new URL("../vectors/vectors.jsonl", import.meta.url).pathname;

const vectors: Vector[] = readFileSync(path, "utf8")
  .split("\n")
  .filter((l) => l.length > 0)
  .map((l) => JSON.parse(l) as Vector);
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
const t0 = performance.now();
const first = outcome(cases[0]);
const firstCall = performance.now() - t0;
void first;
for (let i = 0; i < vectors.length; i++) {
  const v = vectors[i];
  const o = outcome(cases[i]);
  let diverges = false;
  let dataDiffers = false;
  if (v.ok) diverges = !("ok" in o) || !same(o.ok, v.ok);
  else if (v.panic) {
    diverges = !("panic" in o);
    dataDiffers = !diverges && "panic" in o && !same(o.panic, v.panic);
  }
  if (diverges) divergences++;
  if (dataDiffers) panicDataDiffers++;
  if ((diverges || dataDiffers) && shown.length < 20) {
    const expected = v.ok
      ? `ok ${v.ok.join(" ")}`
      : `panic ${v.panic!.map((f) => shortString(BigInt(f))).join(", ")}`;
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
      first_call_ms: +firstCall.toFixed(3),
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
