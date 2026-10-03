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

/** The fake renderer's camera: `zoomAt` scales it as the renderer does, unclamped. */
const camera = { scale: 2, zooms: [] as { factor: number; point: { x: number; y: number } }[] };
const lookAt = vi.fn();

vi.mock("../render/renderer", () => ({
  Renderer: class {
    scheduler = { input() {} };
    resize() {}
    setLibrary = setLibrary;
    cameraState() {
      return { camera: { scale: camera.scale }, viewport: { width: 1000, height: 600 } };
    }
    zoomAt(factor: number, point: { x: number; y: number }) {
      camera.zooms.push({ factor, point });
      camera.scale *= factor;
    }
    lookAt = lookAt;
    destroy() {}
  },
}));

vi.mock("./session", async () => {
  const { fixtureNamed } = await import("./fixtures");
  const { initialState } = await import("./wiring");
  return {
    SandboxSession: class {
      state = { ...initialState(fixtureNamed("meadow")), said: "" };
      destroy() {}
    },
  };
});

import { SandboxController } from "./controller";
import { neighbour } from "./placeholders";
import { fixtureNamed } from "./fixtures";
import { WHEEL_NOTCH } from "../input/gestures";
import type { Intent } from "../input/intent";

const options = {
  fixture: "meadow",
  idle: false,
  scale: "fit",
  zoom: {},
  feet: 0,
  playOnTap: true,
  stepMs: 100,
} as unknown as Parameters<typeof SandboxController.mount>[1];

async function mounted(route?: (intent: Intent) => Intent | null) {
  const host = { clientWidth: 100, clientHeight: 100 } as HTMLElement;
  return SandboxController.mount(host, route ? { ...options, route } : options);
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

describe("SandboxController's keys (CLI-03k)", () => {
  beforeEach(() => {
    vi.stubGlobal(
      "ResizeObserver",
      class {
        observe() {}
        disconnect() {}
      },
    );
    vi.spyOn(console, "debug").mockImplementation(() => {});
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("a step hands apply exactly a tap on the adjacent hex, through the router", async () => {
    const route = vi.fn((_: Intent): Intent | null => null);
    const controller = await mounted(route);
    const start = fixtureNamed("meadow").actors[0]!.tile;
    for (const direction of [0, 1, 2, 3, 4, 5] as const) {
      route.mockClear();
      controller.step({ direction });
      expect(route).toHaveBeenCalledTimes(1);
      expect(route).toHaveBeenCalledWith({ kind: "tile", tile: neighbour(start, direction) });
    }
    controller.destroy();
  });

  it("zoomBy is one wheel notch around the map's centre; in then out restores the scale", async () => {
    const controller = await mounted();
    camera.zooms.length = 0;
    const before = camera.scale;
    controller.zoomBy(1);
    expect(camera.zooms[0]).toEqual({ factor: WHEEL_NOTCH, point: { x: 500, y: 300 } });
    expect(camera.scale).toBeGreaterThan(before);
    controller.zoomBy(-1);
    expect(camera.scale).toBeCloseTo(before, 12);
    controller.destroy();
  });

  it("lookAt eases the renderer's camera to the tile", async () => {
    const controller = await mounted();
    controller.lookAt({ x: 4, y: 5 });
    expect(lookAt).toHaveBeenCalledWith({ x: 4, y: 5 });
    controller.destroy();
  });
});
