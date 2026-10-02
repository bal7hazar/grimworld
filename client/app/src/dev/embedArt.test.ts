import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { artFiles, embedArt, embedArtWanted } from "./embedArt";

// A scratch folder of the system's (removed after the tests): no image of the pack, plain text.
const scratch = mkdtempSync(join(tmpdir(), "embed-art-test-"));
const root = join(scratch, "out");
const outside = join(scratch, "outside");

function atlas(dir: string, pages: unknown): void {
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "sprites.json"), JSON.stringify({ pages, sprites: {} }));
}

beforeAll(() => {
  atlas(root, [{ json: "atlas-0.json", image: "atlas-0.png" }]);
  writeFileSync(join(root, "atlas-0.json"), "{}");
  writeFileSync(join(root, "atlas-0.png"), "not a real png");
  writeFileSync(join(root, "preview.html"), "<p>not copied</p>");
  writeFileSync(join(root, "report.json"), "{}");
  mkdirSync(outside);
  writeFileSync(join(outside, "secret.png"), "secret");
});

afterAll(() => rmSync(scratch, { recursive: true, force: true }));

describe("embedArtWanted (GRIMWORLD_EMBED_ART)", () => {
  it("is off without the variable: CI's dist/ has no art/", () => {
    expect(embedArtWanted({})).toBe(false);
    expect(embedArtWanted({ CI: "true" })).toBe(false);
    expect(embedArtWanted({ GRIMWORLD_EMBED_ART: "0" })).toBe(false);
    expect(embedArtWanted({ GRIMWORLD_EMBED_ART: "" })).toBe(false);
  });

  it("is on with GRIMWORLD_EMBED_ART=1", () => {
    expect(embedArtWanted({ GRIMWORLD_EMBED_ART: "1" })).toBe(true);
  });

  it("refuses when CI is set", () => {
    expect(() => embedArtWanted({ GRIMWORLD_EMBED_ART: "1", CI: "1" })).toThrow(/CI/);
  });
});

describe("artFiles and embedArt", () => {
  it("copies sprites.json and the pages it names, nothing else", () => {
    expect(artFiles(root).sort()).toEqual(["atlas-0.json", "atlas-0.png", "sprites.json"]);
    const target = join(scratch, "dist-art");
    embedArt(root, target);
    expect(readdirSync(target).sort()).toEqual(["atlas-0.json", "atlas-0.png", "sprites.json"]);
  });

  it("refuses an atlas that is not built", () => {
    expect(() => artFiles(join(scratch, "missing"))).toThrow(/not built/);
  });

  it("refuses a page outside the root, by path or by link", () => {
    const byPath = join(scratch, "by-path");
    atlas(byPath, [{ json: "../outside/secret.json" }]);
    expect(() => artFiles(byPath)).toThrow(/outside|missing/);

    const byLink = join(scratch, "by-link");
    atlas(byLink, [{ json: "atlas-0.json", image: "atlas-0.png" }]);
    writeFileSync(join(byLink, "atlas-0.json"), "{}");
    symlinkSync(join(outside, "secret.png"), join(byLink, "atlas-0.png"));
    expect(() => artFiles(byLink)).toThrow(/outside/);
    const target = join(scratch, "dist-link");
    expect(() => embedArt(byLink, target)).toThrow();
    expect(existsSync(target)).toBe(false);
  });

  it("refuses other types, missing pages and malformed indexes", () => {
    const html = join(scratch, "html");
    atlas(html, [{ json: "page.html" }]);
    writeFileSync(join(html, "page.html"), "x");
    expect(() => artFiles(html)).toThrow(/\.json or \.png/);

    const missing = join(scratch, "missing-page");
    atlas(missing, [{ json: "atlas-9.json" }]);
    expect(() => artFiles(missing)).toThrow(/missing/);

    const noPages = join(scratch, "no-pages");
    atlas(noPages, null);
    expect(() => artFiles(noPages)).toThrow(/no pages/);

    const broken = join(scratch, "broken");
    mkdirSync(broken);
    writeFileSync(join(broken, "sprites.json"), "{");
    expect(() => artFiles(broken)).toThrow(/unreadable/);
  });
});
