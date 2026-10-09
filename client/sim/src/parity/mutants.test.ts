// How strong are the vectors? Each mutant is the mirror with one mistake a hand-written mirror
// typically makes (SPK-4's `mutants.ts`), applied as a one-line text replacement to a copy of
// `src/`; the copy replays every table and must diverge on at least one case, by its result or by
// throwing where Cairo returned. A mutant the vectors do not kill is a hole in the vectors: it is
// reported to track game, never closed by editing a table here: it is listed with `survives`
// (what the tables lack), and this test then requires it to survive, so that the day the game's
// cases kill it the mark must go.

import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

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
    name: "the window's origin row ignores the adventurer's row parity",
    file: "movement.ts",
    from: "const movedY = y + odd + 7;",
    to: "const movedY = y + 7;",
  },
  {
    name: "the window's origin off by one column",
    file: "movement.ts",
    from: "const moved = x + 8;",
    to: "const moved = x + 7;",
  },
  {
    name: "Crippled's deadline exclusive",
    file: "movement.ts",
    from: "return t0 <= crippled && !movement ? CRIPPLED_MOVE_TICKS : 1;",
    to: "return t0 < crippled && !movement ? CRIPPLED_MOVE_TICKS : 1;",
  },
  {
    name: "a MOVEMENT effect does not lift Crippled",
    file: "movement.ts",
    from: "return t0 <= crippled && !movement ? CRIPPLED_MOVE_TICKS : 1;",
    to: "return t0 <= crippled ? CRIPPLED_MOVE_TICKS : 1;",
  },
  {
    name: "the flood one layer past its cap",
    file: "movement.ts",
    from: "for (let count = depth - 1; ; count--) {",
    to: "for (let count = depth; ; count--) {",
    survives:
      "no flood walker stands at path distance 15 or 16 from the source (the corridor's walkers are at 12 to 13, or beyond the cap)",
  },
  {
    name: "a walker on the last layer at the cap gets a step (D-25)",
    file: "movement.ts",
    from: "if (k === flood.layers.length - 1 && capped(flood) && !source(flood, position)) return undefined;",
    to: "",
    survives:
      "no flood walker touches only the last layer at the cap (one at distance 16: step 255, distance 16)",
  },
  {
    name: "the flood's step takes the highest index on a tie",
    file: "movement.ts",
    from: "return tiles(set & -set)[0]!;",
    to: "return tiles(set).at(-1)!;",
    survives:
      "no flood walker has two neighbours in its least layer (the corridor leaves one candidate each)",
  },
  {
    name: "the flood's distance is the neighbours' layer, not plus one",
    file: "movement.ts",
    from: "return found === undefined ? undefined : found[0] + 1;",
    to: "return found === undefined ? undefined : found[0];",
  },
  {
    name: "the flood walks the window's ring",
    file: "movement.ts",
    from: "let free = grid & INTERIOR & ~obstacles & ~bit(from);",
    to: "let free = grid & ~obstacles & ~bit(from);",
    survives: "the flood's grid has no open tile on the window's ring",
  },
  {
    name: "the awake set's ties by the highest entity",
    file: "movement.ts",
    from: "distances[i]! * 0x10000 + goblin.entity",
    to: "distances[i]! * 0x10000 + (0xffff - goblin.entity)",
  },
  {
    name: "a sleeping goblin joins the awake set",
    file: "movement.ts",
    from: "goblin.alive && !goblin.asleep ?",
    to: "goblin.alive ?",
  },
  {
    name: "an awake set of 9",
    file: "movement.ts",
    from: "export const MAX_AWAKE = 8;",
    to: "export const MAX_AWAKE = 9;",
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
    name: "a wrong domain separator (ENTRY's short string)",
    file: "fate.ts",
    from: 'export const ENTRY = shortString("fate:entry");',
    to: 'export const ENTRY = shortString("fate-entry");',
  },
  {
    name: "domain's argument order (counter and purpose swapped)",
    file: "fate.ts",
    from: "[feltArg(subject), feltArg(counter), feltArg(purpose)]",
    to: "[feltArg(subject), feltArg(purpose), feltArg(counter)]",
  },
  {
    name: "derive's argument order (word and domain swapped)",
    file: "fate.ts",
    from: "[feltArg(word), feltArg(domain), arg(u32, BigInt(index))]",
    to: "[feltArg(domain), feltArg(word), arg(u32, BigInt(index))]",
  },
  {
    name: "derive drops its index (one value per domain)",
    file: "fate.ts",
    from: "[feltArg(word), feltArg(domain), arg(u32, BigInt(index))]",
    to: "[feltArg(word), feltArg(domain)]",
  },
  {
    name: "split's boundary off by one (a high limb of exactly LIVE kept)",
    file: "packing.ts",
    from: "return high < LIVE_HIGH ? [low, high] : [low, high - LIVE_HIGH];",
    to: "return high <= LIVE_HIGH ? [low, high] : [low, high - LIVE_HIGH];",
  },
  {
    name: "limbs' subtraction not wrapped modulo P",
    file: "packing.ts",
    from: "return wide((((feltArg(word) - LIVE) % P) + P) % P);",
    to: "return wide(feltArg(word) - LIVE);",
  },
  {
    name: "join accepts a high limb of exactly 2^122",
    file: "packing.ts",
    from: "if (arg(u128, high) >= LIVE_HIGH) panic(errors.HIGH);",
    to: "if (arg(u128, high) > LIVE_HIGH) panic(errors.HIGH);",
  },
  {
    name: "peel returns the quotient as the field",
    file: "packing.ts",
    from: "return [arg(u128, rest) % size, rest / size];",
    to: "return [arg(u128, rest) / size, rest % size];",
  },
  {
    name: "fits accepts a value equal to its size",
    file: "packing.ts",
    from: "if (!(arg(u128, value) < arg(u128, size))) panic(message);",
    to: "if (!(arg(u128, value) <= arg(u128, size))) panic(message);",
  },
  {
    name: "field reads the size before the shift",
    file: "packing.ts",
    from: "return (limb / toNonZero(shift)) % toNonZero(size);",
    to: "return (limb % toNonZero(size)) / toNonZero(shift);",
  },
  {
    name: "a lane width of 15 bits when packing Lanes16",
    file: "packing.ts",
    from: "if (i < 8) low += lane * P16 ** BigInt(i);",
    to: "if (i < 8) low += lane * 2n ** (15n * BigInt(i));",
  },
  {
    name: "Lanes16's high limb starting at lane 7",
    file: "packing.ts",
    from: "if (i < 8) low += lane * P16 ** BigInt(i);\n    else high += lane * P16 ** BigInt(i - 8);",
    to: "if (i < 7) low += lane * P16 ** BigInt(i);\n    else high += lane * P16 ** BigInt(i - 7);",
  },
  {
    name: "Lanes32's lane 3 not packed",
    file: "packing.ts",
    from: "const low = a + b * P32 + c * P32 ** 2n + d * P32 ** 3n;",
    to: "const low = a + b * P32 + c * P32 ** 2n + 0n * d;",
  },
  {
    name: "the Bitmap's limbs in the wrong order",
    file: "packing.ts",
    from: "return { bits: low + high * TWO_POW_128 };",
    to: "return { bits: high + low * TWO_POW_128 };",
  },
  {
    name: "the Bitmap's guard at bit 251 instead of 250",
    file: "packing.ts",
    from: "if (high >= LIVE_HIGH) panic(errors.BITMAP);",
    to: "if (high >= 2n * LIVE_HIGH) panic(errors.BITMAP);",
  },
  {
    name: "a Counter overflow not refused (unpack reads the low limb unchecked)",
    file: "packing.ts",
    from: "return { value: narrow(u64, low) };",
    to: "return { value: low };",
    survives:
      "no unpack_counter word has a low limb above u64::MAX (the table records no panic data, so such a row needs an `err` field)",
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

  // A run that was interrupted or killed leaves its copies behind: start from none.
  beforeAll(() => {
    rmSync(COPIES, { recursive: true, force: true });
  });

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
