import { describe, expect, it, vi } from "vitest";
import type { UiSlices } from "../render/sprites";
import {
  CHROME_ENTRIES,
  type ChromeImages,
  type ChromeLoaders,
  ChromeSession,
  type Frame,
  chromeProperties,
  loadChrome,
} from "./load";
import { cutScale } from "./scale";

/** A `sprites.json` and its `ui` page, made in the test: frames only, no image of the pack. */
function fakeAtlas() {
  const sprites: Record<string, unknown> = {
    runt: {
      role: "caste",
      page: 0,
      cell: { w: 32, h: 40 },
      baseline: 36,
      animations: { idle: { frames: 1, fps: 12, loop: true } },
    },
  };
  const frames: Record<string, { frame: Frame }> = {};
  let x = 0;
  for (const name of CHROME_ENTRIES) {
    const pressed = name.startsWith("button_") || name === "round_blue";
    const cell = { w: 40 + x / 10, h: 30 };
    const ui: UiSlices = {
      kind: name.startsWith("icon_") || name === "round_blue" ? "still" : "nine",
      fill: "stretch",
      slice: [8, 8, 8, 8],
      content: [6, 6, 6, 6],
      outset: [1, 2, 3, 4],
      ...(pressed ? { drop: 11, states: ["pressed"] as const } : {}),
    };
    const animations: Record<string, unknown> = { regular: { frames: 1, fps: 1, loop: false } };
    if (pressed) animations.pressed = { frames: 1, fps: 1, loop: false };
    sprites[name] = { role: "ui", page: 1, cell, baseline: 0, animations, ui };
    for (const state of Object.keys(animations)) {
      frames[`${name}/${state}/00`] = { frame: { x, y: 0, ...cell } };
      x += 50;
    }
  }
  const index = {
    pages: [
      { json: "atlas-0.json", image: "atlas-0.png", group: "world" },
      { json: "atlas-ui-0.json", image: "atlas-ui-0.png", group: "ui" },
    ],
    sprites,
  };
  return { index, page: { frames, meta: { image: "atlas-ui-0.png" } } };
}

function fakeLoaders(json: Record<string, unknown>) {
  let n = 0;
  const cuts: { frame: Frame; size: { w: number; h: number } }[] = [];
  const revoked: string[] = [];
  const asked: string[] = [];
  const loaders: ChromeLoaders<string> = {
    fetchJson: async (url) => (asked.push(url), json[url] ?? null),
    loadImage: async (url) => (asked.push(url), `image ${url}`),
    cut: async (_image, frame, size) => (cuts.push({ frame, size }), `blob:${++n}`),
    revoke: (url) => void revoked.push(url),
  };
  return { loaders, cuts, revoked, asked };
}

const served = () => {
  const { index, page } = fakeAtlas();
  return { "/art/sprites.json": index, "/art/atlas-ui-0.json": page };
};

describe("loadChrome", () => {
  it("cuts every element of the ui page, never a world page", async () => {
    const { loaders, cuts, asked } = fakeLoaders(served());
    const images = await loadChrome("/art/", 2, loaders);
    expect(images).not.toBeNull();
    expect([...images!.entries.keys()]).toEqual([...CHROME_ENTRIES]);
    expect(asked).toEqual(["/art/sprites.json", "/art/atlas-ui-0.json", "/art/atlas-ui-0.png"]);
    const pressed = CHROME_ENTRIES.filter((n) => n.startsWith("button_") || n === "round_blue");
    expect(cuts).toHaveLength(CHROME_ENTRIES.length + pressed.length);
    expect(images!.entries.get("button_blue")!.urls.pressed).toMatch(/^blob:/);
    expect(images!.entries.get("paper")!.urls.pressed).toBeUndefined();
  });

  for (const dpr of [1, 1.25, 1.5, 2, 2.625, 3]) {
    it(`at ${dpr}×, each cut image is its frame × cutScale (AC-4)`, async () => {
      const { loaders, cuts } = fakeLoaders(served());
      await loadChrome("/art/", dpr, loaders);
      for (const { frame, size } of cuts) {
        expect(size).toEqual({
          w: Math.round(frame.w * cutScale(dpr)),
          h: Math.round(frame.h * cutScale(dpr)),
        });
      }
    });
  }

  it("is null without the art, without a ui page, or with an element missing", async () => {
    expect(await loadChrome("/art/", 1, fakeLoaders({}).loaders)).toBeNull();
    const { index, page } = fakeAtlas();
    const worldOnly = {
      pages: [index.pages[0]],
      sprites: { runt: index.sprites.runt },
    };
    expect(
      await loadChrome("/art/", 1, fakeLoaders({ "/art/sprites.json": worldOnly }).loaders),
    ).toBeNull();
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const lacking = { ...index, sprites: { ...index.sprites, wood: undefined } };
    const json = {
      "/art/sprites.json": JSON.parse(JSON.stringify(lacking)),
      "/art/atlas-ui-0.json": page,
    };
    expect(await loadChrome("/art/", 1, fakeLoaders(json).loaders)).toBeNull();
    expect(String(warn.mock.calls[0]?.[0])).toContain("lacks wood");
    warn.mockRestore();
  });

  it("revokes what it cut when a frame is not its element's cell", async () => {
    const json = served();
    const page = json["/art/atlas-ui-0.json"] as { frames: Record<string, { frame: Frame }> };
    page.frames["wood/regular/00"] = { frame: { x: 0, y: 0, w: 1, h: 1 } };
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const { loaders, cuts, revoked } = fakeLoaders(json);
    expect(await loadChrome("/art/", 2, loaders)).toBeNull();
    expect(cuts.length).toBeGreaterThan(0);
    expect(revoked).toHaveLength(cuts.length);
    error.mockRestore();
  });
});

describe("ChromeSession", () => {
  it("re-cuts on a ratio change and revokes the replaced URLs (AC-4)", async () => {
    const { loaders, revoked } = fakeLoaders(served());
    const applied: (ChromeImages | null)[] = [];
    const session = new ChromeSession((images) => applied.push(images), loaders, "/art/");
    await session.show(1);
    const first = applied[0]!;
    expect(first.dpr).toBe(1);
    expect(revoked).toEqual([]);
    await session.show(2);
    expect(applied[1]!.dpr).toBe(2);
    expect(revoked).toEqual(first.urls);
    session.destroy();
    expect(revoked).toEqual([...first.urls, ...applied[1]!.urls]);
  });

  it("revokes a load overtaken by a newer one, unseen", async () => {
    const { loaders, revoked } = fakeLoaders(served());
    const applied: (ChromeImages | null)[] = [];
    const session = new ChromeSession((images) => applied.push(images), loaders, "/art/");
    const slow = session.show(1);
    const fast = session.show(3);
    await Promise.all([slow, fast]);
    expect(applied.map((images) => images?.dpr)).toEqual([3]);
    expect(revoked.length).toBe(applied[0]!.urls.length);
    session.destroy();
  });
});

describe("chromeProperties", () => {
  it("publishes each element's image, slices, widths, padding and drop", async () => {
    const images = (await loadChrome("/art/", 2, fakeLoaders(served()).loaders))!;
    const css = chromeProperties(images);
    expect(css["--gw-px"]).toBe("0.5px");
    expect(css["--gw-button-blue"]).toMatch(/^url\("blob:\d+"\)$/);
    expect(css["--gw-button-blue-pressed"]).toMatch(/^url\("blob:\d+"\)$/);
    expect(css["--gw-button-blue-slice"]).toBe("8 8 8 8");
    expect(css["--gw-button-blue-width"]).toBe("4px 4px 4px 4px");
    expect(css["--gw-button-blue-pad"]).toBe("3px 3px 3px 3px");
    expect(css["--gw-button-blue-drop"]).toBe("5.5px");
    expect(css["--gw-button-blue-min-h"]).toBe("8px");
    expect(css["--gw-paper-pressed"]).toBeUndefined();
  });
});
