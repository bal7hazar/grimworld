import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { AA, CHROME_TEXT, INK, WHITE, contrast } from "./contrast";

/**
 * AC-5: each component's text against its element's centre colour, as `tools/art/build.py`
 * measured it (`report.json`, `ui.<entry>.centre`, the build of 2026-10-03), copied as numbers.
 */
const css = readFileSync(new URL("./chrome.css", import.meta.url), "utf8");

const CENTRES: Readonly<Record<string, Readonly<Record<string, number>>>> = {
  paper: { regular: 0xeee1c6 },
  paper_dark: { regular: 0x525b66 },
  scroll: { regular: 0xdcdca5 },
  wood: { regular: 0x9b6253 },
  button_blue: { regular: 0x41919d, pressed: 0x4a6982 },
  button_red: { regular: 0xf65555, pressed: 0xba4954 },
  ribbon_big_blue: { regular: 0x41919d },
  ribbon_big_red: { regular: 0xbe6e61 },
  ribbon_small_yellow: { regular: 0xbbb552 },
  round_blue: { regular: 0x41919d, pressed: 0x4a6982 },
};

describe("contrast", () => {
  it("measures WCAG's ratios", () => {
    expect(contrast(WHITE, 0x000000)).toBeCloseTo(21, 5);
    expect(contrast(INK, INK)).toBe(1);
    // The brief's table (The method §5).
    expect(contrast(INK, 0xeee1c6)).toBeCloseTo(14.59, 1);
    expect(contrast(WHITE, 0x41919d)).toBeCloseTo(3.64, 1);
    expect(contrast(WHITE, 0xf65555)).toBeCloseTo(3.31, 1);
    expect(contrast(0xf2c94c, 0x525b66)).toBeLessThan(AA.body);
  });

  it("every component's text meets AA on its element, in every state", () => {
    for (const text of CHROME_TEXT) {
      for (const state of text.states) {
        const surface = CENTRES[text.entry]?.[state];
        expect(surface, `${text.entry}/${state}`).toBeDefined();
        const ratio = contrast(text.colour, surface!);
        expect(ratio, `${text.component} (${state})`).toBeGreaterThanOrEqual(
          text.large ? AA.large : AA.body,
        );
      }
    }
  });

  it("the stylesheet sets the colours the table checks", () => {
    const rule = (selector: string) => {
      const at = css.indexOf(`${selector} {`);
      expect(at, selector).toBeGreaterThanOrEqual(0);
      return css.slice(at, css.indexOf("}", at));
    };
    const hex = (rgb: number) => `#${rgb === WHITE ? "fff" : "111"}`;
    const colour = (selector: string) => /\bcolor:\s*(#[0-9a-f]{3,6})/.exec(rule(selector))?.[1];
    const pairs: [string, string][] = [
      ['[data-chrome="atlas"] .gw-button', "Button action"],
      ['[data-chrome="atlas"] .gw-button-quiet', "Button quiet"],
      ['[data-chrome="atlas"] .gw-icon-button', "IconButton"],
      ['[data-chrome="atlas"] .gw-panel', "Panel paper"],
      ['[data-chrome="atlas"] .gw-panel-dark', "Panel dark"],
      ['[data-chrome="atlas"] .gw-ribbon-big', "Ribbon big blue"],
      ['[data-chrome="atlas"] .gw-ribbon-yellow', "Ribbon small yellow"],
    ];
    for (const [selector, component] of pairs) {
      const text = CHROME_TEXT.find((t) => t.component === component)!;
      expect(colour(selector), component).toBe(hex(text.colour));
    }
    // Captions and muted lines on the art.
    const text = (selector: string) => /\bcolor:\s*(#[0-9a-f]{3,6})/.exec(rule(selector))?.[1];
    const on = (component: string) => CHROME_TEXT.find((t) => t.component === component)!.colour;
    const six = (rgb: number) => `#${rgb.toString(16).padStart(6, "0")}`;
    expect(text('[data-chrome="atlas"] .gw-panel-scroll .gw-text-muted')).toBe(
      six(on("Text on scroll")),
    );
    expect(text('[data-chrome="atlas"] .gw-panel-dark .gw-text-muted')).toBe(
      six(on("Text on dark paper")),
    );
    expect(six(on("Text on paper"))).toBe(six(on("Text on scroll")));
    // Large text: bold and at least 18.67 px (1.166875 rem at the default size) wherever the table says large.
    expect(rule('[data-chrome="atlas"] .gw-button')).toContain("700 1.166875rem");
    expect(rule('[data-chrome="atlas"] .gw-ribbon-big')).toContain("700 1.166875rem");
  });
});
