import { describe, expect, it } from "vitest";

/**
 * CLI-03j: text follows the system's text size, so no font size or line height of the client is in
 * `px` (design/11 *Accessibility*), and no rule sets the root's size. Sizes that must not scale
 * would be listed in ALLOWED; none is today (the canvas draws no text; the 44 px heights and the
 * art's lengths are layout, not text).
 */
const css = import.meta.glob<string>("../**/*.css", {
  query: "?raw",
  import: "default",
  eager: true,
});
const code = import.meta.glob<string>("../**/*.{ts,tsx}", {
  query: "?raw",
  import: "default",
  eager: true,
});

const ALLOWED: string[] = [];

/** A `font` shorthand, `font-size`, `fontSize`, `line-height` or `lineHeight` whose value has px. */
const CSS_RULE = /(?:^|[\s;{])(font|font-size|line-height)\s*:\s*([^;}]*)/g;
const STYLE_OBJECT = /\b(font|fontSize|lineHeight)\s*:\s*("[^"]*"|'[^']*'|`[^`]*`|\d+(?:\.\d+)?)/g;

function pxText(files: Record<string, string>, pattern: RegExp, valueIndex: number): string[] {
  const found: string[] = [];
  for (const [file, text] of Object.entries(files)) {
    if (file.endsWith(".test.ts") || file.endsWith(".test.tsx")) continue;
    for (const m of text.matchAll(pattern)) {
      const value = m[valueIndex] ?? "";
      const bare = /^\d+(?:\.\d+)?$/.test(value); // a number in a style object is px, but a
      const unitlessLineHeight = m[1] === "lineHeight" && bare; // line height number is a ratio
      if ((/\d\s*px\b/.test(value) || (bare && !unitlessLineHeight)) && !ALLOWED.includes(file)) {
        found.push(`${file}: ${m[0].trim()}`);
      }
    }
  }
  return found;
}

describe("text sizes", () => {
  it("no font size or line height in a stylesheet is in px", () => {
    expect(Object.keys(css).length).toBeGreaterThan(0);
    expect(pxText(css, CSS_RULE, 2)).toEqual([]);
  });

  it("no font size or line height in a style object or inline style is in px", () => {
    expect(pxText(code, STYLE_OBJECT, 2)).toEqual([]);
  });

  it("no rule sets the size of the root", () => {
    for (const text of Object.values(css)) {
      expect(text).not.toMatch(/(?:html|:root)\s*{[^}]*font(?:-size)?\s*:/);
    }
    for (const [file, text] of Object.entries(code)) {
      if (file.includes(".test.")) continue;
      expect(text).not.toMatch(/documentElement\.style\.font/);
    }
  });
});
