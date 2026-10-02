// How strong are the vectors? Each mutant is the mirror with one mistake a hand-written mirror
// typically makes (SPK-4's `mutants.ts`), applied as a one-line text replacement to a copy of
// `src/`; the copy replays every table and must diverge on at least one case, by its result or by
// throwing where Cairo returned. A mutant the vectors do not kill is a hole in the vectors: it is
// reported to track game, never closed by editing a table here: it is listed with `survives`
// (what the tables lack), and this test then requires it to survive, so that the day the game's
// cases kill it the mark must go.

import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { afterAll, describe, expect, it } from "vitest";

type Mutant = { name: string; file: string; from: string; to: string; survives?: string };

const MUTANTS: readonly Mutant[] = [
  {
    name: "the line's tie across rows takes the higher index",
    file: "window.ts",
    from: "for (let r = r0 - 1; r <= r0 + 2 && chosen === undefined; r++) {",
    to: "for (let r = r0 - 1; r <= r0 + 2; r++) {",
  },
  {
    name: "the line's tie on a row takes the higher column",
    file: "window.ts",
    from: "          break;",
    to: "",
  },
  {
    name: "the facing turns the other way on a tie (the line's first step)",
    file: "window.ts",
    from: "moveQ = q > s || (q === s && qNegative);",
    to: "moveQ = q > s || (q === s && !qNegative);",
  },
  {
    name: "the arc's variant order (rear-side and back swapped)",
    file: "window.ts",
    from: "export const Arc = { Front: 0, FrontSide: 1, RearSide: 2, Back: 3 } as const;",
    to: "export const Arc = { Front: 0, FrontSide: 1, RearSide: 3, Back: 2 } as const;",
  },
  {
    name: "a wall at an end of the line does not block",
    file: "window.ts",
    from: "return [from, to, ...between].every(",
    to: "return between.every(",
  },
  {
    name: "FAR returned as the true distance outside the window",
    file: "window.ts",
    from: "if (!(inside(from) && inside(to))) return FAR;",
    to: "if (!(inside(from) && inside(to))) return length(delta(from, to));",
  },
  {
    name: "the shape not clipped to the window (a row wraps into the next)",
    file: "window.ts",
    from: "Math.min(last, WIDTH - 1)",
    to: "last",
  },
  {
    name: "reach's range off by one",
    file: "window.ts",
    from: "if (length(delta(from, to)) > u8(range)) return false;",
    to: "if (length(delta(from, to)) >= u8(range)) return false;",
  },
  {
    name: "the front tile's direction table (North-East read as North-West)",
    file: "window.ts",
    from: "  [-1, 1],",
    to: "  [0, 1],",
  },
  {
    name: "a negative modifier applied as a delta truncated toward zero",
    file: "hit.ts",
    from: "const damage = (scaled * multiplier) / 100n;",
    to: "const damage = scaled + (scaled * percent) / 100n;",
  },
  {
    name: "modifiers applied in sequence instead of summed (D-140 #3)",
    file: "hit.ts",
    from: "const damage = (scaled * multiplier) / 100n;",
    to: "const damage = terms.reduce((d, t) => (d * (100n + t)) / 100n, scaled);",
  },
  {
    name: "the sum of the percents not floored at -100",
    file: "hit.ts",
    from: "const percent = sum < MIN_PERCENT ? MIN_PERCENT : sum;",
    to: "const percent = sum;",
  },
  {
    name: "armor not floored at 0",
    file: "hit.ts",
    from: "if (a <= 0n) return 0n;",
    to: "if (a <= 0n) return a;",
  },
  {
    name: "penetration not capped at 100",
    file: "hit.ts",
    from: "hit.penetration > PENETRATION_CAP ? PENETRATION_CAP : hit.penetration",
    to: "hit.penetration",
  },
  {
    name: "the hit not saturated at 65,535",
    file: "hit.ts",
    from: "return damage > MAX_DAMAGE ? MAX_DAMAGE : damage;",
    to: "return damage;",
  },
  {
    name: "a sleeping target blocks its first hit",
    file: "hit.ts",
    from: "&& front && open && !target.asleep)",
    to: "&& front && open)",
  },
  {
    name: "evasion takes ranged hits too",
    file: "hit.ts",
    from: "if (target.evade && hit.melee && open && !target.asleep)",
    to: "if (target.evade && open && !target.asleep)",
  },
  {
    name: "critical from the rear-side arc too",
    file: "hit.ts",
    from: "return hit.arc === Arc.Back ||",
    to: "return hit.arc >= Arc.RearSide ||",
  },
  {
    name: "the axe's bonus from every arc",
    file: "hit.ts",
    from: "(hit.arc === Arc.RearSide || hit.arc === Arc.Back)",
    to: "true",
  },
  {
    name: "the above-half guard holds at exactly half",
    file: "hit.ts",
    from: "if (hit.health * 2n > hit.max_health)",
    to: "if (hit.health * 2n >= hit.max_health)",
  },
  {
    name: "FX-19's halving triggers at exactly half after the hit",
    file: "hit.ts",
    from: "after * 2n < target.max_health",
    to: "after * 2n <= target.max_health",
  },
  {
    name: "a signed felt decoded as unsigned",
    file: "felt.ts",
    from: "const value = type.min < 0n && felt > P / 2n ? felt - P : felt;",
    to: "const value = felt;",
  },
  {
    name: "the table's clamp removed",
    file: "exp2.ts",
    from: "const clamped = Math.min(Math.max(x, EXP2_LOW), EXP2_HIGH);",
    to: "const clamped = x;",
  },
];

const SRC = new URL("../", import.meta.url);
const COPIES = new URL("../.mutants/", SRC);
// The copies sit beside `src/`, not in it; `.mutants` is filtered all the same, so that copies left
// by a killed run could never be copied again if they ever moved under `src/`.
const SOURCES = readdirSync(SRC, { recursive: true }).filter(
  (path) => path.endsWith(".ts") && !path.endsWith(".test.ts") && !path.startsWith(".mutants"),
);

type Parity = {
  replay: typeof import("./replay").replay;
  readTable: typeof import("./table").readTable;
  TABLES: typeof import("./tables").TABLES;
};

/** A copy of `src/` with the mutant's one replacement, in `.mutants/<index>/`. */
async function copy(mutant: Mutant, index: number): Promise<Parity> {
  const text = readFileSync(new URL(mutant.file, SRC), "utf8");
  expect(text.split(mutant.from).length - 1, `"${mutant.from}" once in ${mutant.file}`).toBe(1);
  const root = new URL(`${index}/`, COPIES);
  for (const path of SOURCES) {
    const target = new URL(path, root);
    mkdirSync(new URL(".", target), { recursive: true });
    const source =
      path === mutant.file
        ? text.replace(mutant.from, mutant.to)
        : readFileSync(new URL(path, SRC), "utf8");
    writeFileSync(target, source);
  }
  const load = (name: string) => import(/* @vite-ignore */ new URL(`parity/${name}.ts`, root).href);
  const [replay, table, tables] = await Promise.all([
    load("replay"),
    load("table"),
    load("tables"),
  ]);
  return { replay: replay.replay, readTable: table.readTable, TABLES: tables.TABLES };
}

/** The first divergence the vectors find, or `undefined` when the mutant survives. */
function killer(parity: Parity): string | undefined {
  for (const entry of parity.TABLES) {
    try {
      parity.replay(entry, parity.readTable(entry.file));
    } catch (error) {
      return (error as Error).message.split(": case")[0]!.split(": threw")[0];
    }
  }
  return undefined;
}

describe("the mutation check", () => {
  const results: string[] = [];

  afterAll(() => {
    rmSync(COPIES, { recursive: true, force: true });
    console.log(["| # | Mutant | Killed by |", "|---|---|---|", ...results].join("\n"));
  });

  it("has at least 12 mutants", () => {
    expect(MUTANTS.length).toBeGreaterThanOrEqual(12);
  });

  it("kills at least 12 of them", () => {
    expect(MUTANTS.filter((mutant) => mutant.survives === undefined).length).toBeGreaterThanOrEqual(
      12,
    );
  });

  MUTANTS.forEach((mutant, index) => {
    const known = mutant.survives;
    it(`${known === undefined ? "kills" : "a known survivor"}: ${mutant.name}`, async () => {
      const found = killer(await copy(mutant, index));
      results.push(`| ${index + 1} | ${mutant.name} | ${found ?? `**survives**: ${known}`} |`);
      if (known === undefined) {
        expect(found, `${mutant.name} survived the vectors`).toBeDefined();
      } else {
        expect(found, `${mutant.name} is now killed: remove its \`survives\``).toBeUndefined();
      }
    });
  });
});
