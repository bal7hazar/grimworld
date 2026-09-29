import { describe, expect, it } from "vitest";

/**
 * AC-5: every rule of the chain the sandbox needs lives in `sandbox/placeholders.ts`, and only the
 * sandbox's wiring imports it (test files apart, which test it).
 */
const sources = import.meta.glob<string>("../**/*.{ts,tsx}", {
  query: "?raw",
  import: "default",
  eager: true,
});

const IMPORTS_PLACEHOLDERS =
  /from\s+["'][^"']*placeholders["']|import\(\s*["'][^"']*placeholders["']/;

describe("placeholders.ts", () => {
  it("is imported by the sandbox's wiring only", () => {
    const importers = Object.entries(sources)
      .filter(([path]) => !/\.test\.tsx?$/.test(path))
      .filter(([, text]) => IMPORTS_PLACEHOLDERS.test(text))
      .map(([path]) => path);
    expect(Object.keys(sources).length).toBeGreaterThan(10);
    expect(importers).toEqual(["./wiring.ts"]);
  });

  it("marks every exported function PLACEHOLDER until CLI-02", () => {
    const text = sources["./placeholders.ts"] ?? "";
    const exported = [...text.matchAll(/export function (\w+)/g)].map((m) => m[1]);
    expect(exported.length).toBeGreaterThan(0);
    for (const name of exported) {
      const before = text.slice(0, text.indexOf(`export function ${name}`));
      const doc = before.slice(before.lastIndexOf("/**"));
      expect(doc, name).toContain("PLACEHOLDER until CLI-02");
    }
  });

  it("is the only place that decides which actors are seen (design/18)", () => {
    const filtersBySight = /actors\s*\.filter\([^;]*[sS]ight/;
    const deciders = Object.entries(sources)
      .filter(([path]) => !/\.test\.tsx?$/.test(path) && path !== "./placeholders.ts")
      .filter(([, text]) => filtersBySight.test(text))
      .map(([path]) => path);
    expect(deciders).toEqual([]);
    expect(sources["./wiring.ts"]).toContain("visibleActors(");
  });

  it("is the only place that computes a path (CLI-03b, AC-4)", () => {
    const code = Object.entries(sources).filter(([path]) => !/\.test\.tsx?$/.test(path));
    expect(sources["./placeholders.ts"]).toMatch(/export function findPath\(/);
    // The finder and the step are called by the wiring only.
    const callers = code
      .filter(([path]) => path !== "./placeholders.ts")
      .filter(([, text]) => /\b(findPath|stepToward|neighbour)\(/.test(text))
      .map(([path]) => path);
    expect(callers).toEqual(["./wiring.ts"]);
    // No other file walks the hex grid: no neighbour table, no flood, no direction loop.
    const grid =
      /\bFACINGS\b|\btile\.y\s*&\s*1\b[^;]*\?\s*\{|queue\.shift\(|frontier|\bflood\b\s*=|visited\s*=/;
    const walkers = code
      .filter(([path]) => path !== "./placeholders.ts")
      .filter(([, text]) => grid.test(text))
      .map(([path]) => path);
    expect(walkers).toEqual([]);
    // No other file declares a path finder.
    const finders = code
      .filter(([path]) => path !== "./placeholders.ts")
      .filter(([, text]) => /function\s+\w*(find|search|route|flood)\w*\s*\(/i.test(text))
      .map(([path]) => path);
    expect(finders).toEqual([]);
  });

  it("the hex rules are imported by the wiring only, and copied nowhere (F-6)", () => {
    const code = Object.entries(sources).filter(
      ([path]) => !/\.test\.tsx?$/.test(path) && path !== "./placeholders.ts",
    );
    const RULES = [
      "neighbour",
      "distance",
      "findPath",
      "stepToward",
      "stopsAfterStep",
      "insideRing",
      "inWindow",
      "tilesInSight",
      "visibleActors",
      "revealInSight",
      "arcsOf",
      "facingToward",
    ];
    // An import that binds one of them, from any module.
    const importers = code
      .filter(([, text]) =>
        [...text.matchAll(/import\s*(?:type\s*)?\{([^}]*)\}\s*from/g)].some((m) =>
          (m[1] ?? "").split(",").some((name) => RULES.includes(name.trim().split(/\s+as\s+/)[0]!)),
        ),
      )
      .map(([path]) => path);
    expect(importers).toEqual(["./wiring.ts"]);
    // No other module exports one of them (a second copy of a rule).
    const exporters = code
      .filter(([, text]) =>
        RULES.some((name) => new RegExp(`export\\s+(function|const)\\s+${name}\\b`).test(text)),
      )
      .map(([path]) => path);
    expect(exporters).toEqual([]);
    // The wiring imports none of the grid's geometry: it has no use for it.
    const wiring = sources["./wiring.ts"] ?? "";
    expect(wiring).not.toMatch(/\b(neighbour|distance|inWindow|insideRing)\b/);
    // The stop conditions are the placeholder's: the wiring does not diff sight itself.
    expect(wiring).toContain("stopsAfterStep(");
    expect(wiring).not.toMatch(/\.has\(a\.id\)|=== "unrevealed" &&/);
  });

  it("uses no randomness and no clock", () => {
    const text = sources["./placeholders.ts"] ?? "";
    expect(text).not.toMatch(/Math\.random|Date\.|performance\.now|crypto\./);
  });
});
