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

/**
 * A size given through a variable or an expression (`fontSize: size`, `{ lineHeight }`) cannot be
 * judged from the source, so each such site is listed here as `file: text` and answers for its
 * value being relative (rem, em, a ratio). None exists today. Canvas text (`new Text`, `ctx.font`)
 * is left out on purpose: the canvas draws no text; add a guard with the first canvas label.
 */
const VARIABLE_SITES: string[] = [];
const STYLE_VARIABLE =
  /\b(fontSize|lineHeight)\s*(?::\s*([A-Za-z_$][\w$.]*(?:\([^)]*\))?)\s*)?(?=[,}])/g;

/** A `font` shorthand, `font-size`, `fontSize`, `line-height` or `lineHeight` whose value has px. */
const CSS_RULE = /(?:^|[\s;{])(font|font-size|line-height)\s*:\s*([^;}]*)/g;
const STYLE_OBJECT = /\b(font|fontSize|lineHeight)\s*:\s*("[^"]*"|'[^']*'|`[^`]*`|\d+(?:\.\d+)?)/g;

function pxText(files: Record<string, string>, pattern: RegExp, valueIndex: number): string[] {
  const found: string[] = [];
  for (const [file, text] of Object.entries(files)) {
    if (file.endsWith(".test.ts") || file.endsWith(".test.tsx")) continue;
    for (const m of text.matchAll(pattern)) {
      const value = (m[valueIndex] ?? "").trim();
      const bare = /^\d+(?:\.\d+)?$/.test(value); // a number in a style object is px, but a
      const unitlessLineHeight = /^(?:lineHeight|line-height)$/.test(m[1] ?? "") && bare; // line height number is a ratio, in a stylesheet too
      if ((/\d\s*px\b/.test(value) || (bare && !unitlessLineHeight)) && !ALLOWED.includes(file)) {
        found.push(`${file}: ${m[0].trim()}`);
      }
    }
  }
  return found;
}

/** The sites where a font size or line height is a variable, not a literal, other than the listed. */
function variableSites(files: Record<string, string>): string[] {
  const found: string[] = [];
  for (const [file, text] of Object.entries(files)) {
    if (file.includes(".test.")) continue;
    for (const m of text.matchAll(STYLE_VARIABLE)) {
      const site = `${file}: ${m[0].trim()}`;
      if (!VARIABLE_SITES.includes(site)) found.push(site);
    }
  }
  return found;
}

describe("the guard's own cases", () => {
  it("accepts a unitless line height in a stylesheet and a style object, flags px", () => {
    const sheet = (rule: string) => ({ "a.css": `.x { ${rule} }` });
    expect(pxText(sheet("line-height: 1.5;"), CSS_RULE, 2)).toEqual([]);
    expect(pxText(sheet("line-height: 1.5"), CSS_RULE, 2)).toEqual([]);
    expect(pxText(sheet("line-height: 24px;"), CSS_RULE, 2)).toHaveLength(1);
    expect(pxText(sheet("font-size: 14px;"), CSS_RULE, 2)).toHaveLength(1);
    expect(pxText(sheet("font-size: 0.875rem;"), CSS_RULE, 2)).toEqual([]);
    const obj = (style: string) => ({ "a.ts": `const s = { ${style} };` });
    expect(pxText(obj("lineHeight: 1.5"), STYLE_OBJECT, 2)).toEqual([]);
    expect(pxText(obj("fontSize: 14"), STYLE_OBJECT, 2)).toHaveLength(1);
  });

  it("finds a size given through a variable", () => {
    const sites = variableSites({
      "a.ts":
        "const a = { fontSize: size, color };\nconst b = { lineHeight };\nconst c = { fontSize: sizeOf(x) };",
      "b.ts": 'const d = { fontSize: "1rem", lineHeight: 1.5 };',
    });
    expect(sites).toHaveLength(3);
  });
});

describe("text sizes", () => {
  it("no font size or line height in a stylesheet is in px", () => {
    expect(Object.keys(css).length).toBeGreaterThan(0);
    expect(pxText(css, CSS_RULE, 2)).toEqual([]);
  });

  it("no font size or line height in a style object or inline style is in px", () => {
    expect(pxText(code, STYLE_OBJECT, 2)).toEqual([]);
  });

  it("every font size or line height given through a variable is listed", () => {
    expect(variableSites(code)).toEqual([]);
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
