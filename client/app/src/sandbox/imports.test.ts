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

  it("uses no randomness and no clock", () => {
    const text = sources["./placeholders.ts"] ?? "";
    expect(text).not.toMatch(/Math\.random|Date\.|performance\.now|crypto\./);
  });
});
