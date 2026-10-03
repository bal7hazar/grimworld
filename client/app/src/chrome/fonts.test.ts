import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const fonts = readFileSync(new URL("./fonts.css", import.meta.url), "utf8");
const chrome = readFileSync(new URL("./chrome.css", import.meta.url), "utf8");

describe("the display font (CLI-03m)", () => {
  it("is served by the site: woff2 files of the package, no URL outside it", () => {
    const urls = [...fonts.matchAll(/url\("([^"]+)"\)/g)].map((m) => m[1]);
    expect(urls).toHaveLength(2);
    for (const url of urls)
      expect(url).toMatch(/^@fontsource\/pixelify-sans\/files\/.*-latin-.*\.woff2$/);
    expect(fonts).not.toMatch(/https?:/);
    expect(fonts.match(/font-display: swap/g)).toHaveLength(2);
  });

  it("falls back to system-ui, and the chrome's text uses the stack, not the face", () => {
    expect(fonts).toContain('--gw-display: "Pixelify Sans", system-ui;');
    expect(chrome).not.toMatch(/font:[^;]*Pixelify/);
    expect(chrome.match(/var\(--gw-display\)/g)).toHaveLength(4);
  });
});
