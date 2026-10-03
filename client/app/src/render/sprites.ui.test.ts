import { describe, expect, it } from "vitest";
import { SYNTHETIC_INDEX, syntheticSheet } from "../test/syntheticAtlas";
import { loadAtlas } from "./atlas";
import { type SpritesIndex, readSpritesIndex } from "./sprites";

/** CLI-03i: the interface's elements in `sprites.json`, on a page of their own (AC-3). */

const BUTTON = {
  role: "ui",
  page: 1,
  cell: { w: 164, h: 160 },
  baseline: 0,
  animations: {
    regular: { frames: 1, fps: 1, loop: false },
    pressed: { frames: 1, fps: 1, loop: false },
  },
  ui: {
    kind: "nine",
    fill: "stretch",
    slice: [34, 20, 20, 18],
    content: [16, 24, 32, 24],
    outset: [17, 14, 15, 14],
    drop: 11,
    states: ["pressed"],
  },
};

const WITH_UI = {
  pages: [
    { ...SYNTHETIC_INDEX.pages[0]!, group: "world" },
    { json: "atlas-ui-0.json", image: "atlas-ui-0.png", group: "ui" },
  ],
  sprites: { ...SYNTHETIC_INDEX.sprites, button_blue: BUTTON },
};

const withButton = (patch: Record<string, unknown>, ui: Record<string, unknown> = {}) => ({
  ...WITH_UI,
  sprites: {
    ...WITH_UI.sprites,
    button_blue: { ...BUTTON, ...patch, ui: { ...BUTTON.ui, ...ui } },
  },
});

describe("sprites.json with interface elements", () => {
  it("accepts a ui entry on a ui page, and pages with a group", () => {
    expect(readSpritesIndex(WITH_UI)).toEqual({ index: WITH_UI });
    // A page without a group is the map's, as before CLI-03i.
    expect(readSpritesIndex(SYNTHETIC_INDEX)).toHaveProperty("index");
  });

  it("refuses each malformed field", () => {
    const bad: [string, unknown][] = [
      ["group", { ...WITH_UI, pages: [WITH_UI.pages[0], { ...WITH_UI.pages[1], group: "hud" }] }],
      ["kind", withButton({}, { kind: "five" })],
      ["fill", withButton({}, { fill: "tile" })],
      ["slice not 4", withButton({}, { slice: [1, 2, 3] })],
      ["slice negative", withButton({}, { slice: [-1, 2, 3, 4] })],
      ["slice fraction", withButton({}, { slice: [1.5, 2, 3, 4] })],
      ["slice outside", withButton({}, { slice: [100, 20, 61, 18] })],
      ["content outside", withButton({}, { content: [0, 100, 0, 65] })],
      ["outset", withButton({}, { outset: [0, 0, "1", 0] })],
      ["drop without state", withButton({}, { states: [] })],
      ["state without drop", withButton({}, { drop: undefined })],
      ["drop negative", withButton({}, { drop: -1 })],
      ["unknown state", withButton({}, { states: ["hover"] })],
      [
        "state without its frame",
        withButton({ animations: { regular: BUTTON.animations.regular } }),
      ],
      ["ui on a world page", withButton({ page: 0 })],
      [
        "ui role without ui",
        { ...WITH_UI, sprites: { button_blue: { ...BUTTON, ui: undefined } } },
      ],
      [
        "a map sprite on a ui page",
        { ...WITH_UI, sprites: { runt: { ...SYNTHETIC_INDEX.sprites.runt!, page: 1 } } },
      ],
    ];
    for (const [what, json] of bad) {
      expect(readSpritesIndex(json), what).toHaveProperty("problem");
    }
  });
});

describe("loadAtlas with a ui page", () => {
  it("never loads a ui page: the map's library has the map's sprites only", async () => {
    const sheet = await syntheticSheet();
    const asked: string[] = [];
    const library = await loadAtlas("/art/", {
      fetchJson: async (url) => (asked.push(url), WITH_UI as unknown as SpritesIndex),
      loadSheet: async (url) => (asked.push(url), sheet),
    });
    expect(asked).toEqual(["/art/sprites.json", "/art/atlas-0.json"]);
    expect(library?.has("runt")).toBe(true);
    expect(library?.has("button_blue")).toBe(false);
  });
});
