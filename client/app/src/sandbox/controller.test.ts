import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { SpriteLibrary } from "../render/sprites";

const setLibrary = vi.fn();
let atlas: { resolve: (l: SpriteLibrary | null) => void; reject: (e: unknown) => void };

vi.mock("../render/atlas", () => ({
  loadAtlas: () =>
    new Promise<SpriteLibrary | null>((resolve, reject) => {
      atlas = { resolve, reject };
    }),
}));

vi.mock("../render/pixiSurface", () => ({
  pixiTickersRunning: () => false,
  createPixiSurface: async () => ({
    app: {
      canvas: { addEventListener() {}, removeEventListener() {} },
      renderer: { resize() {} },
      destroy() {},
    },
    surface: {},
  }),
}));

vi.mock("../render/renderer", () => ({
  Renderer: class {
    scheduler = { input() {} };
    resize() {}
    setLibrary = setLibrary;
    destroy() {}
  },
}));

vi.mock("./session", () => ({
  SandboxSession: class {
    state = { said: "" };
    destroy() {}
  },
}));

import { SandboxController } from "./controller";

const options = {
  fixture: "meadow",
  idle: false,
  scale: "fit",
  zoom: {},
  feet: 0,
  playOnTap: true,
  stepMs: 100,
} as unknown as Parameters<typeof SandboxController.mount>[1];

async function mounted() {
  const host = { clientWidth: 100, clientHeight: 100 } as HTMLElement;
  return SandboxController.mount(host, options);
}

describe("SandboxController destroyed before the atlas settles", () => {
  beforeEach(() => {
    setLibrary.mockClear();
    vi.stubGlobal(
      "ResizeObserver",
      class {
        observe() {}
        disconnect() {}
      },
    );
    vi.spyOn(console, "error").mockImplementation(() => {});
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("does not hand the library to the destroyed renderer", async () => {
    const controller = await mounted();
    controller.destroy();
    atlas.resolve({} as SpriteLibrary);
    await new Promise((r) => setTimeout(r, 0));
    expect(setLibrary).not.toHaveBeenCalled();
  });

  it("does nothing when the atlas fails after destroy", async () => {
    const controller = await mounted();
    controller.destroy();
    atlas.reject(new Error("offline"));
    await new Promise((r) => setTimeout(r, 0));
    expect(console.error).not.toHaveBeenCalled();
  });
});
