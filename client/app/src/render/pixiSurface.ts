import { Application, ColorMatrixFilter, TextureStyle, Ticker } from "pixi.js";
import { BACKGROUND, type Surface } from "./renderer";
import { type ScaleMode, canvasResolution } from "./scaling";

/** The surface in the browser: its canvas resolution follows the scale mode. */
export interface PixiSurface extends Surface {
  setResolution(resolution: number): void;
}

/** The largest texture side: WebGL's `MAX_TEXTURE_SIZE`, or WebGPU's `maxTextureDimension2D`. */
export function gpuMaxTextureSize(renderer: unknown): number {
  const r = renderer as {
    gl?: WebGLRenderingContext;
    gpu?: { device?: { limits?: { maxTextureDimension2D?: number } } };
  };
  const size = r.gl
    ? Number(r.gl.getParameter(r.gl.MAX_TEXTURE_SIZE))
    : r.gpu?.device?.limits?.maxTextureDimension2D;
  // WebGL guarantees 2048 at least (WebGL 2), WebGPU 8192.
  return typeof size === "number" && Number.isFinite(size) && size >= 2048 ? size : 2048;
}

/**
 * PixiJS 8 runs two tickers of its own even with `autoStart: false`: `Ticker.system`, which the
 * renderer's `SchedulerSystem` (texture collection) and the event system's hover checks join at
 * init, and which **starts itself on the first listener**; and `Ticker.shared`. Either is a
 * permanent `requestAnimationFrame` loop. Both are stopped, and kept from starting again: nothing
 * is drawn or woken but by the renderer's scheduler. Textures are destroyed by hand instead of
 * being collected.
 */
export function stopPixiTickers(): void {
  for (const ticker of [Ticker.system, Ticker.shared]) {
    ticker.autoStart = false;
    ticker.stop();
  }
}

/** True when any PixiJS ticker runs: shown by the debug panel, false by construction. */
export function pixiTickersRunning(app: Application): boolean {
  return Ticker.system.started || Ticker.shared.started || app.ticker.started;
}

/** A PixiJS application as the renderer's surface, in `host`, with pixel art scaled nearest. */
export async function createPixiSurface(
  host: HTMLElement,
  mode: ScaleMode,
): Promise<{ app: Application; surface: PixiSurface }> {
  TextureStyle.defaultOptions.scaleMode = "nearest";
  const resolution = canvasResolution(mode, window.devicePixelRatio);
  const app = new Application();
  await app.init({
    width: Math.max(1, host.clientWidth),
    height: Math.max(1, host.clientHeight),
    resolution,
    autoDensity: true,
    antialias: false,
    roundPixels: true,
    background: BACKGROUND,
    autoStart: false,
    sharedTicker: false,
    eventMode: "none",
    eventFeatures: { move: false, globalMove: false, click: false, wheel: false },
  });
  app.ticker.stop();
  stopPixiTickers();
  // The bakes' grayscale (CLI-03n): made on the first grey bake, at the bake's own resolution.
  let grey: ColorMatrixFilter | null = null;
  app.canvas.style.display = "block";
  app.canvas.style.touchAction = "none";
  host.appendChild(app.canvas);
  const surface: PixiSurface = {
    stage: app.stage,
    get resolution() {
      return app.renderer.resolution;
    },
    get devicePixelRatio() {
      return window.devicePixelRatio || 1;
    },
    maxTextureSize: gpuMaxTextureSize(app.renderer),
    render: () => app.render(),
    bake: (target, frame, bakeResolution, greyed) => {
      const generate = () =>
        app.renderer.generateTexture({ target, frame, resolution: bakeResolution, antialias: false });
      if (!greyed) return generate();
      if (!grey) {
        grey = new ColorMatrixFilter({ resolution: "inherit", antialias: "off" });
        grey.desaturate();
      }
      const filters = target.filters;
      target.filters = [grey];
      try {
        return generate();
      } finally {
        target.filters = filters ? [...filters] : null;
      }
    },
    // A Texture target's frame is the pass's viewport (PixiJS RenderTargetSystem.bind): only the
    // frame is drawn. No clear: a WebGL clear is not limited by the viewport; the container paints
    // its own backdrop over the frame.
    renderTo: (container, target) => app.renderer.render({ container, target, clear: false }),
    setResolution: (value) =>
      app.renderer.resize(app.renderer.screen.width, app.renderer.screen.height, value),
  };
  return { app, surface };
}
