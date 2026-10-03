// The lot's measurements (CLI-02a AC-6), run on demand and never by `pnpm test`:
// `pnpm --filter @grimworld/sim bench`. Each figure is the median of repeated runs, printed for the
// report; none is asserted or committed as a threshold (pins on Linux only, D-140).
//
// Poseidon: `poseidonHashMany` of `@scure/starknet` on three felts, the shape of `fate::domain`'s
// input, and `fate::derive` itself, its argument checks included (CLI-02b).

import { poseidonHashMany } from "@scure/starknet";
import { describe, it } from "vitest";
import { ENTRY, derive, domain } from "../src/fate";
import { P } from "../src/felt";
import { replay } from "../src/parity/replay";
import { readTable } from "../src/parity/table";
import { TABLES } from "../src/parity/tables";

const median = (values: number[]): number => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)]!;
};

/** The median over `runs` of the time of one call of `body`, in microseconds, `batch` calls a run. */
function time(runs: number, batch: number, body: (i: number) => void): number {
  for (let i = 0; i < batch; i++) body(i);
  const samples: number[] = [];
  for (let run = 0; run < runs; run++) {
    const start = performance.now();
    for (let i = 0; i < batch; i++) body(i);
    samples.push(((performance.now() - start) * 1000) / batch);
  }
  return median(samples);
}

describe("measurements", () => {
  it("Poseidon on three felts", { timeout: 300_000 }, () => {
    // Inputs vary per call so that nothing is cached; felts near P included
    const inputs = Array.from({ length: 64 }, (_, i) => [
      BigInt(i),
      P - 1n - BigInt(i),
      0x1234567890abcdefn * BigInt(i + 1),
    ]);
    let sink = 0n;
    const cold = performance.now();
    sink ^= poseidonHashMany([1n, 2n, 3n]);
    const first = (performance.now() - cold) * 1000;
    const perCall = time(31, 500, (i) => {
      sink ^= poseidonHashMany(inputs[i % inputs.length]!);
    });
    console.log(
      `poseidonHashMany(3 felts): median ${perCall.toFixed(2)} µs a call (31 runs × 500 calls, ` +
        `after a warm-up of 500); first call ${first.toFixed(0)} µs; sink ${sink & 1n}`,
    );
  });

  it("fate::derive", { timeout: 300_000 }, () => {
    // Words vary per call and the index walks the u32 range, so that nothing is cached
    const words = Array.from({ length: 64 }, (_, i) => P - 1n - 0x9e3779b97f4a7c15n * BigInt(i));
    const dom = domain(1n, 0n, ENTRY);
    let sink = 0n;
    const cold = performance.now();
    sink ^= derive(0n, dom, 0);
    const first = (performance.now() - cold) * 1000;
    const perCall = time(31, 500, (i) => {
      sink ^= derive(words[i % words.length]!, dom, (i * 2654435761) % 2 ** 32);
    });
    console.log(
      `derive: median ${perCall.toFixed(2)} µs a call (31 runs × 500 calls, after a warm-up of ` +
        `500); first call ${first.toFixed(0)} µs; sink ${sink & 1n}`,
    );
  });

  for (const entry of TABLES) {
    it(`replay of ${entry.file}`, () => {
      const vectors = readTable(entry.file);
      const read = time(11, 1, () => readTable(entry.file));
      const run = time(11, 1, () => replay(entry, vectors));
      console.log(
        `${entry.file}: ${vectors.length} cases; read and parse median ${(read / 1000).toFixed(2)} ms, ` +
          `replay median ${(run / 1000).toFixed(2)} ms (${(run / vectors.length).toFixed(2)} µs a case), 11 runs`,
      );
    });
  }
});
