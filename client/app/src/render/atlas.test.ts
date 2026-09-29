import { describe, expect, it } from "vitest";
import { SYNTHETIC_INDEX, syntheticSheet } from "../test/syntheticAtlas";
import { loadAtlas } from "./atlas";
import { readSpritesIndex } from "./sprites";

describe("loadAtlas", () => {
  it("builds the library from sprites.json and the pages PixiJS parses", async () => {
    const sheet = await syntheticSheet();
    const asked: string[] = [];
    const library = await loadAtlas("/art/", {
      fetchJson: async (url) => (asked.push(url), SYNTHETIC_INDEX),
      loadSheet: async (url) => (asked.push(url), sheet),
    });
    expect(asked).toEqual(["/art/sprites.json", "/art/atlas-0.json"]);
    const runt = library?.get("runt");
    expect(runt?.animations.idle?.textures).toHaveLength(4);
    expect(runt?.animations.move?.fps).toBe(12);
    expect(runt?.scale).toBe(1);
    expect(runt?.animations.idle?.textures[0]?.defaultAnchor?.y).toBeCloseTo(0.9);
    expect(sheet.textureSource.scaleMode).toBe("nearest");
  });

  it("reads a scale from sprites.json when it has one", async () => {
    const sheet = await syntheticSheet();
    const index = {
      ...SYNTHETIC_INDEX,
      sprites: { runt: { ...SYNTHETIC_INDEX.sprites.runt!, scale: 0.75 } },
    };
    const library = await loadAtlas("/art/", {
      fetchJson: async () => index,
      loadSheet: async () => sheet,
    });
    expect(library?.get("runt")?.scale).toBe(0.75);
  });

  it("is null without the atlas: shapes are drawn", async () => {
    const none = { loadSheet: async () => Promise.reject(new Error("not reached")) };
    expect(await loadAtlas("/art/", { ...none, fetchJson: async () => null })).toBeNull();
    expect(await loadAtlas("/art/", { ...none, fetchJson: async () => "<html>" })).toBeNull();
    expect(
      await loadAtlas("/art/", { ...none, fetchJson: () => Promise.reject(new Error("offline")) }),
    ).toBeNull();
  });

  it("refuses what is not an index", () => {
    expect(readSpritesIndex({ pages: [], sprites: { runt: { page: "0" } } })).toBeNull();
    expect(readSpritesIndex(SYNTHETIC_INDEX)).not.toBeNull();
  });
});
