// How strong are the vectors? Each mutant is the mirror (logic.ts) with one mistake a hand-written
// mirror typically makes, applied as a text replacement; each must diverge from the Cairo code on
// at least one vector: by its result or by throwing where Cairo returned (or the reverse), else by
// the data of its panic. A mutant the vectors do not kill is a hole in the vectors.
//
//   node spikes/SPK-4/ts/mutants.ts

import { mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { CairoPanic } from "./cairo.ts";

type Vector = { id: number; case: string[]; ok?: string[]; panic?: string[] };
type Mutant = { name: string; from: string; to: string };

const MUTANTS: Mutant[] = [
  {
    name: "signed division floors instead of truncating",
    from: "div(i32, mul(i32, raw, modifier), 100n)",
    to: "((m) => (m < 0n && m % 100n !== 0n ? m / 100n - 1n : m / 100n))(mul(i32, raw, modifier))",
  },
  {
    name: "unsigned division rounds instead of truncating",
    from: "div(u32, mul(u32, base, factor), SHIFT)",
    to: "div(u32, mul(u32, base, factor) + SHIFT / 2n, SHIFT)",
  },
  {
    name: "u32 product not range-checked",
    from: "mul(u32, base, factor)",
    to: "(base * factor)",
  },
  {
    name: "u16 sum not range-checked",
    from: "add(u16, armor, bonus)",
    to: "(armor + bonus)",
  },
  {
    name: "armor below zero clamps instead of panicking",
    from: "sub(u16, add(u16, armor, bonus), penetration)",
    to: "((v) => (v < 0n ? 0n : v))(add(u16, armor, bonus) - penetration)",
  },
  {
    name: "result not narrowed to u16",
    from: "return narrow(u16, total);",
    to: "return total;",
  },
  {
    name: "table clamp one short at the top",
    from: "const X_HIGH = 80n;",
    to: "const X_HIGH = 79n;",
  },
  {
    name: "table computed at run time with floating point, floored",
    from: "const factor = POW2_X40[Number(x - X_LOW)];",
    to: "const factor = BigInt(Math.floor(2 ** (Number(x) / 40) * 65536)); void POW2_X40;",
  },
  {
    name: "ties broken by highest tile",
    from: "n < best)",
    to: "n > best)",
  },
  {
    name: "ties broken by neighbour order",
    from: " || (d === bestD && best !== goblin && n < best)",
    to: "",
  },
  {
    name: "felt subtraction without the modulus",
    from: "feltAdd(feltSub(occupied, 1n << goblin), 1n << best)",
    to: "occupied - (1n << goblin) + (1n << best)",
  },
  {
    name: "goblin next to the target still steps",
    from: "if (here <= 1n) return [goblin, occupied];",
    to: "if (here < 1n) return [goblin, occupied];",
  },
  {
    name: "odd and even rows swapped",
    from: "const odd = row % 2n === 1n;",
    to: "const odd = row % 2n === 0n;",
  },
  {
    name: "arguments not checked against their type",
    from: "fromFelt(u16, c[1]),",
    to: "c[1],",
  },
  {
    name: "negative i16 argument read as unsigned",
    from: "fromFelt(i16, c[6]),",
    to: "fromFelt(i32, c[6] > 2n ** 250n ? c[6] - (2n ** 251n + 17n * 2n ** 192n + 1n) : c[6]) & 0xffffn,",
  },
  {
    name: "goblin on the ring simulated (ring ignored for the goblin)",
    from: "  if (!has(WINDOW_INTERIOR, goblin)) return [goblin, occupied];\n",
    to: "",
  },
  {
    name: "ring tiles walkable (ring ignored for the step)",
    from: "  walkable &= WINDOW_INTERIOR;\n",
    to: "",
  },
  {
    name: "ring ignored entirely (an unrestricted board)",
    from: "  if (!has(WINDOW_INTERIOR, goblin)) return [goblin, occupied];\n  walkable &= WINDOW_INTERIOR;\n",
    to: "",
  },
  {
    name: "empty case not checked",
    from: '  if (c.length === 0) throw new CairoPanic(felt("exec: empty case"));\n',
    to: "",
  },
  {
    name: "tile outside the window not rejected",
    from: 'if (!(goblin < TILES && target < TILES)) throw new CairoPanic(felt("board: tile outside window"));',
    to: "void TILES;",
  },
];

const here = new URL(".", import.meta.url).pathname;
const source = readFileSync(here + "logic.ts", "utf8");
const vectors: Vector[] = readFileSync(here + "../vectors/vectors.jsonl", "utf8")
  .split("\n")
  .filter((l) => l.length > 0)
  .map((l) => JSON.parse(l) as Vector);
const cases = vectors.map((v) => v.case.map((x) => BigInt(x)));
const dir = here + "mutants-tmp/";
mkdirSync(dir, { recursive: true });

let survivors = 0;
const rows: string[] = [];
for (let m = 0; m < MUTANTS.length; m++) {
  const mutant = MUTANTS[m];
  const count = source.split(mutant.from).length - 1;
  if (count !== 1) throw new Error(`mutant "${mutant.name}": pattern found ${count} times`);
  const file = `${dir}logic-${m}.ts`;
  writeFileSync(
    file,
    source
      .replace(mutant.from, mutant.to)
      .replaceAll('"./cairo.ts"', '"../cairo.ts"')
      .replaceAll('"./table.ts"', '"../table.ts"'),
  );
  const { run } = (await import(file)) as { run: (c: bigint[]) => bigint[] };
  let killed = 0;
  let killedByData = 0;
  for (let i = 0; i < vectors.length; i++) {
    const v = vectors[i];
    let got: bigint[] | null = null;
    let data: bigint[] | null = null;
    try {
      got = run(cases[i]);
    } catch (e) {
      data = e instanceof CairoPanic ? e.data : [];
    }
    const want = v.ok ?? v.panic!;
    const same = (a: bigint[]) => a.length === want.length && a.every((x, j) => x === BigInt(want[j]));
    if (v.ok ? got === null || !same(got) : data === null) killed++;
    else if (v.panic && !same(data!)) killedByData++;
  }
  if (killed + killedByData === 0) survivors++;
  rows.push(`| ${m + 1} | ${mutant.name} | ${killed} | ${killedByData} |`);
}
rmSync(dir, { recursive: true });
console.log(
  "| # | Mutant | Vectors that catch it | Caught only by the panic data |\n|---|---|---:|---:|",
);
console.log(rows.join("\n"));
console.log(`\n${MUTANTS.length} mutants, ${MUTANTS.length - survivors} killed, ${survivors} survived`);
process.exitCode = survivors === 0 ? 0 : 1;
