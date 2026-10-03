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

/**
 * The modules (test files apart) whose import clauses bind `name`, wherever the clause breaks its
 * lines (`[^}]` spans newlines), under any alias.
 */
function importersOf(files: [string, string][], name: string): string[] {
  return files
    .filter(([, text]) =>
      [...text.matchAll(/import\s*(?:type\s*)?\{([^}]*)\}\s*from/g)].some((m) =>
        (m[1] ?? "").split(",").some(
          (item) =>
            item
              .trim()
              .split(/\s+as\s+/)[0]!
              .replace(/^type\s+/, "") === name,
        ),
      ),
    )
    .map(([path]) => path)
    .sort();
}

describe("importersOf", () => {
  it("sees a clause split over several lines, an alias and a type marker", () => {
    const split = 'import {\n  type A,\n  hubGateAt as at,\n} from "./x";';
    expect(importersOf([["./a.ts", split]], "hubGateAt")).toEqual(["./a.ts"]);
    expect(importersOf([["./a.ts", split]], "A")).toEqual(["./a.ts"]);
    expect(importersOf([["./a.ts", 'import { hubGateAtX } from "./x";']], "hubGateAt")).toEqual([]);
  });
});

describe("placeholders.ts", () => {
  it("is imported by the sandbox's wiring and the loop's machine only", () => {
    const importers = Object.entries(sources)
      .filter(([path]) => !/\.test\.tsx?$/.test(path))
      .filter(([, text]) => IMPORTS_PLACEHOLDERS.test(text))
      .map(([path]) => path)
      .sort();
    expect(Object.keys(sources).length).toBeGreaterThan(10);
    expect(importers).toEqual(["./loop/machine.ts", "./wiring.ts"]);
  });

  it("holds the hubs' and gates' rules, imported by the loop's machine only (CLI-03c, AC-5)", () => {
    const code = Object.entries(sources).filter(
      ([path]) => !/\.test\.tsx?$/.test(path) && path !== "./placeholders.ts",
    );
    const RULES = ["hubGateAt", "entryThrough", "hubAfter"];
    for (const name of RULES) {
      expect(sources["./placeholders.ts"]).toMatch(new RegExp(`export function ${name}\\(`));
    }
    // Which modules bind each symbol, against one allow-list per symbol (CLI-03d, note 1).
    for (const name of RULES) {
      expect(importersOf(code, name), name).toEqual(["./loop/machine.ts"]);
    }
    // `sameTile` compares tiles: the placeholders and the wiring use it, `world.ts` defines it.
    // Nothing else imports it, so nothing else can compare a tile to a gate's anchor.
    const everything = Object.entries(sources).filter(([path]) => !/\.test\.tsx?$/.test(path));
    expect(importersOf(everything, "sameTile")).toEqual(["./placeholders.ts", "./wiring.ts"]);
    // The anchor and entry fields (and a gate's destination) are read by the machine (the
    // I-5 question), the screens that name a destination, and the region's records, the zone
    // fixture and the fixtures' index (the `zone` room, entered through gate 1) that define them.
    const data = ["./fixtures/region.ts", "./fixtures/zone.ts", "./fixtures/index.ts"];
    const readers = code
      .filter(([path]) => !data.includes(path))
      .filter(([, text]) => /\b(anchor|entry)_(chunk|tile)\b|\.destination\b/.test(text))
      .map(([path]) => path)
      .sort();
    expect(readers).toEqual([
      "./loop/InstanceScreen.tsx",
      "./loop/Loop.tsx",
      "./loop/machine.ts",
      "./loop/screens.tsx",
    ]);
    // The hub's view and taps, and the zone's renderer that draws a hub (CLI-03f), decide nothing:
    // they import no fixture and no sandbox.
    for (const path of [
      "../render/hubView.ts",
      "../render/renderer.ts",
      "../render/shapes.ts",
      "../input/hubTaps.ts",
    ]) {
      expect(sources[path], path).toBeDefined();
      expect(sources[path], path).not.toMatch(/from\s+["'][^"']*sandbox/);
    }
  });

  it("a hub is a world's kind read by the wiring and the room only (CLI-03f, D-202)", () => {
    const code = Object.entries(sources).filter(([path]) => !/\.test\.tsx?$/.test(path));
    const readers = code
      .filter(([, text]) => /\.kind\s*[!=]==\s*["']hub["']/.test(text))
      .map(([path]) => path)
      .sort();
    expect(readers).toEqual(["./Sandbox.tsx", "./wiring.ts"]);
    // The hub's world, its doors and its screen take nothing from the placeholders: the finder is
    // reached through the wiring, as in a zone.
    for (const path of ["./fixtures/hubWorld.ts", "./loop/hubDoors.ts", "./loop/HubScreen.tsx"]) {
      expect(sources[path], path).toBeDefined();
      expect(sources[path], path).not.toMatch(IMPORTS_PLACEHOLDERS);
    }
    // No hub symbol in the placeholders.
    expect(sources["./placeholders.ts"]).not.toMatch(/\bhubWorld\b|\bHubView\b|\bhubTap\b/);
  });

  it("the ground is presentation: no stand-in reads it, the wiring's toView alone (CLI-03g1, AC-1)", () => {
    expect(sources["./placeholders.ts"]).not.toMatch(/\bground\b|GroundKind/i);
    // In the sandbox, outside the fixtures that write it: only `toView` reads a terrain's ground.
    const readers = Object.entries(sources)
      .filter(([path]) => path.startsWith("./") && !/\.test\.tsx?$/.test(path))
      .filter(([path]) => !path.startsWith("./fixtures/"))
      .filter(([, text]) => /\.ground\b/.test(text))
      .map(([path]) => path);
    expect(readers).toEqual(["./wiring.ts"]);
    const wiring = sources["./wiring.ts"] ?? "";
    const toView = wiring.slice(wiring.indexOf("export function toView("));
    expect(wiring.match(/\.ground\b/g)).toHaveLength(1);
    expect(toView).toMatch(/terrain\.ground\?\.\[i\]/);
    // The fixtures' and the world's ground, and the renderer's, decide nothing: no placeholder.
    for (const path of ["../render/ground.ts", "./fixtures/zone.ts", "./fixtures/hubWorld.ts"]) {
      expect(sources[path], path).toBeDefined();
      expect(sources[path], path).not.toMatch(IMPORTS_PLACEHOLDERS);
    }
    expect(sources["../render/ground.ts"]).not.toMatch(/from\s+["'][^"']*sandbox/);
  });

  it("no randomness and no clock in the loop's machine and fixtures (§6.6)", () => {
    for (const path of [
      "./loop/machine.ts",
      "./fixtures/hubs.ts",
      "./fixtures/region.ts",
      "./fixtures/zone.ts",
      "./fixtures/hubWorld.ts",
      "./loop/hubDoors.ts",
    ]) {
      expect(sources[path], path).toBeDefined();
      expect(sources[path], path).not.toMatch(/Math\.random|Date\.|performance\.now|crypto\./);
    }
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
