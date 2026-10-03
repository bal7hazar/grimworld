import { describe, expect, it, vi } from "vitest";
import type { UiSlices } from "../render/sprites";
import {
  CHROME_ENTRIES,
  HUD_ENTRIES,
  PORTRAIT_SIZES,
  type ChromeImages,
  type ChromeLoaders,
  ChromeSession,
  type Frame,
  chromeProperties,
  loadChrome,
} from "./load";
import { cutScale, portraitCut } from "./scale";

/** A `sprites.json` and its `ui` page, made in the test: frames only, no image of the pack. */
function fakeAtlas(names: readonly string[] = CHROME_ENTRIES) {
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
  for (const name of names) {
    const pressed = name.startsWith("button_") || name === "round_blue";
    const cell = name.startsWith("portrait_") ? { w: 197, h: 182 } : { w: 40 + x / 10, h: 30 };
    const ui: UiSlices = {
      kind: /^(icon_|portrait_|cursor_|bar_.*_fill)/.test(name) || name === "round_blue"
        ? "still"
        : "nine",
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
  const cuts: { frame: Frame; size: { w: number; h: number }; smooth: boolean }[] = [];
  const revoked: string[] = [];
  const asked: string[] = [];
  const loaders: ChromeLoaders<string> = {
    fetchJson: async (url) => (asked.push(url), json[url] ?? null),
    loadImage: async (url) => (asked.push(url), `image ${url}`),
    cut: async (_image, frame, size, smooth = false) => (
      cuts.push({ frame, size, smooth }), `blob:${++n}`
    ),
    revoke: (url) => void revoked.push(url),
  };
  return { loaders, cuts, revoked, asked };
}

const served = (names: readonly string[] = CHROME_ENTRIES) => {
  const { index, page } = fakeAtlas(names);
  return { "/art/sprites.json": index, "/art/atlas-ui-0.json": page };
};
const ALL = [...CHROME_ENTRIES, ...HUD_ENTRIES];

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

describe("the HUD's images (CLI-03l AC-3)", () => {
  it("are cut with the chrome when every HUD entry is there", async () => {
    const { loaders } = fakeLoaders(served(ALL));
    const images = (await loadChrome("/art/", 2, loaders))!;
    expect([...images.entries.keys()]).toEqual([...CHROME_ENTRIES]);
    expect(images.hud).not.toBeNull();
    expect([...images.hud!.entries.keys()]).toEqual([
      "bar_big",
      "bar_big_fill",
      "bar_small",
      "bar_small_fill_energy",
      "icon_sword",
    ]);
    expect([...images.hud!.portraits.keys()]).toEqual([
      "portrait_vanguard",
      "portrait_warden",
      "portrait_cleric",
    ]);
    expect(images.hud!.cursors.arrow).toMatch(
      /^image-set\(url\("blob:\d+"\) 1x, url\("blob:\d+"\) 2x\) 0 0, auto$/,
    );
    expect(images.hud!.cursors.hand).toMatch(/\) 2 0, pointer$/);
    const css = chromeProperties(images);
    expect(css["--gw-bar-big"]).toMatch(/^url\("blob:\d+"\)$/);
    expect(css["--gw-cursor-hand"]).toBe(images.hud!.cursors.hand);
  });

  it("drops only the HUD to plain when one of its entries is missing", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { loaders, cuts } = fakeLoaders(served(ALL.filter((n) => n !== "portrait_cleric")));
    const images = await loadChrome("/art/", 1, loaders);
    expect(images).not.toBeNull();
    expect(images!.entries.size).toBe(CHROME_ENTRIES.length);
    expect(images!.hud).toBeNull();
    expect(String(warn.mock.calls[0]?.[0])).toContain("lacks portrait_cleric; plain HUD");
    expect(cuts).toHaveLength(images!.urls.length);
    expect(chromeProperties(images!)["--gw-cursor-arrow"]).toBeUndefined();
    warn.mockRestore();
  });

  it("drops both to plain when a chrome entry is missing", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { loaders } = fakeLoaders(served(ALL.filter((n) => n !== "paper")));
    expect(await loadChrome("/art/", 1, loaders)).toBeNull();
    warn.mockRestore();
  });

  it("revokes only the HUD's URLs when one of its frames fails", async () => {
    const json = served(ALL);
    const page = json["/art/atlas-ui-0.json"] as { frames: Record<string, { frame: Frame }> };
    page.frames["cursor_hand/regular/00"] = { frame: { x: 0, y: 0, w: 1, h: 1 } };
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const { loaders, cuts, revoked } = fakeLoaders(json);
    const images = (await loadChrome("/art/", 2, loaders))!;
    expect(images.hud).toBeNull();
    expect(images.urls.length + revoked.length).toBe(cuts.length);
    expect(revoked.length).toBeGreaterThan(0);
    expect(revoked.some((url) => images.urls.includes(url))).toBe(false);
    error.mockRestore();
  });

  for (const dpr of [1, 1.5, 2, 3]) {
    it(`at ${dpr}×, each portrait size is its own cut, smoothed below 1:1`, async () => {
      const { loaders, cuts } = fakeLoaders(served(ALL));
      const images = (await loadChrome("/art/", dpr, loaders))!;
      for (const [, sizes] of images.hud!.portraits) {
        expect([...sizes.keys()]).toEqual([...PORTRAIT_SIZES]);
        for (const [size, cut] of sizes) {
          const want = portraitCut({ w: 197, h: 182 }, size, dpr);
          expect({ w: cut.w, h: cut.h }).toEqual(want.devicePx);
          expect(cut.w).toBe(Math.round(size * dpr));
          const made = cuts.find((c) => `blob:${cuts.indexOf(c) + 1}` === cut.url)!;
          expect(made.smooth).toBe(Math.round(size * dpr) < 197);
        }
      }
      // Every other cut is nearest-neighbour.
      const portraitUrls = new Set(
        [...images.hud!.portraits.values()].flatMap((m) => [...m.values()].map((c) => c.url)),
      );
      cuts.forEach((c, i) => {
        if (!portraitUrls.has(`blob:${i + 1}`)) expect(c.smooth).toBe(false);
      });
    });
  }

  it("re-cuts every HUD image on a ratio change and revokes every old URL", async () => {
    const { loaders, revoked } = fakeLoaders(served(ALL));
    const applied: (ChromeImages | null)[] = [];
    const session = new ChromeSession((images) => applied.push(images), loaders, "/art/");
    await session.show(1);
    const first = applied[0]!;
    const hudUrls = [...first.hud!.portraits.values()].flatMap((m) =>
      [...m.values()].map((c) => c.url),
    );
    expect(hudUrls.every((url) => first.urls.includes(url))).toBe(true);
    await session.show(3);
    expect(revoked).toEqual(first.urls);
    expect(applied[1]!.hud!.portraits.get("portrait_vanguard")!.get(48)!.w).toBe(144);
    session.destroy();
  });
});
