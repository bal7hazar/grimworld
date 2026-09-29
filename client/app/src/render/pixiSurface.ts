import { Application, TextureStyle, Ticker } from "pixi.js";
import type { Surface } from "./renderer";

/**
 * Device pixels per CSS pixel: an integer, rounded down, capped at 2 (ADR-0003: "an integer
 * multiple of the art resolution, capped at 2× device pixels"). A ratio of 1.5 renders at 1, 2.625
 * at 2: never more pixels than the screen has.
 */
export function surfaceResolution(devicePixelRatio: number): number {
  const ratio = Number.isFinite(devicePixelRatio) ? devicePixelRatio : 1;
  return Math.min(2, Math.max(1, Math.floor(ratio)));
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
): Promise<{ app: Application; surface: Surface }> {
  TextureStyle.defaultOptions.scaleMode = "nearest";
  const resolution = surfaceResolution(window.devicePixelRatio);
  const app = new Application();
  await app.init({
    width: Math.max(1, host.clientWidth),
    height: Math.max(1, host.clientHeight),
    resolution,
    autoDensity: true,
    antialias: false,
    roundPixels: true,
    background: 0x0b0b0e,
    autoStart: false,
    sharedTicker: false,
    eventMode: "none",
    eventFeatures: { move: false, globalMove: false, click: false, wheel: false },
  });
  app.ticker.stop();
  stopPixiTickers();
  app.canvas.style.display = "block";
  app.canvas.style.touchAction = "none";
  host.appendChild(app.canvas);
  const surface: Surface = {
    stage: app.stage,
    resolution,
    maxTextureSize: gpuMaxTextureSize(app.renderer),
    render: () => app.render(),
    bake: (target, frame, bakeResolution) =>
      app.renderer.generateTexture({ target, frame, resolution: bakeResolution, antialias: false }),
  };
  return { app, surface };
}
