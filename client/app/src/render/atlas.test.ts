import { describe, expect, it, vi } from "vitest";
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
    expect(
      await loadAtlas("/art/", { ...none, fetchJson: () => Promise.reject(new Error("offline")) }),
    ).toBeNull();
  });

  it("refuses what is not an index", () => {
    expect(readSpritesIndex({ pages: [], sprites: { runt: { page: "0" } } })).toHaveProperty(
      "problem",
    );
    expect(readSpritesIndex(SYNTHETIC_INDEX)).toEqual({ index: SYNTHETIC_INDEX });
  });

  const withRate = (fps: unknown, frames: unknown = 4) => ({
    ...SYNTHETIC_INDEX,
    sprites: {
      runt: {
        ...SYNTHETIC_INDEX.sprites.runt!,
        animations: { idle: { frames, fps, loop: true } },
      },
    },
  });

  it("accepts only finite frame rates within 1..30", () => {
    for (const fps of [1, 12, 15, 30])
      expect(readSpritesIndex(withRate(fps))).toHaveProperty("index");
    for (const fps of [-1, 0, 0.5, 31, Infinity, NaN, "12", null]) {
      expect(readSpritesIndex(withRate(fps)), String(fps)).toHaveProperty("problem");
    }
    for (const frames of [0, -2, 1.5, Infinity]) {
      expect(readSpritesIndex(withRate(12, frames)), String(frames)).toHaveProperty("problem");
    }
  });

  it("falls back to shapes, with an error in the console, on a bad rate", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const loadSheet = vi.fn(async () => syntheticSheet());
    for (const fps of [-1, 0, 1000]) {
      expect(
        await loadAtlas("/art/", { fetchJson: async () => withRate(fps), loadSheet }),
      ).toBeNull();
    }
    expect(loadSheet).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalledTimes(3);
    expect(String(error.mock.calls[0]?.[0])).toContain("fps -1 outside 1..30");
    error.mockRestore();
  });
});
