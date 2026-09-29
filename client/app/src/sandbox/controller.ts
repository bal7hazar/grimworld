import type { Application } from "pixi.js";
import { screenToTile } from "../input/coords";
import { type Gesture, GestureTracker } from "../input/gestures";
import type { Intent } from "../input/intent";
import { loadAtlas } from "../render/atlas";
import { type PixiSurface, createPixiSurface, pixiTickersRunning } from "../render/pixiSurface";
import { type ScaleMode, canvasResolution } from "../render/scaling";
import { Renderer, type ZoomInfo, type ZoomSettings } from "../render/renderer";
import type { FrameStats } from "../render/scheduler";
import { browserHost } from "../render/scheduler";
import type { SpriteLibrary } from "../render/sprites";
import { fixtureNamed } from "./fixtures";
import { type SandboxState, applyIntent, initialState, toView } from "./wiring";

/** What the debug panel shows. */
export interface SandboxInfo {
  readonly fixture: string;
  readonly description: string;
  readonly stats: FrameStats;
  /** The scale mode and what it gives: DPR, canvas resolution, pixels per art pixel, tiles. */
  readonly zoomInfo: ZoomInfo;
  readonly zoom: ZoomSettings;
  readonly idle: boolean;
  readonly atlas: "loading" | "loaded" | "none" | "failed";
  readonly sprites: readonly { readonly name: string; readonly scale: number }[];
  readonly said: string;
  readonly tickersRunning: boolean;
}

export interface SandboxOptions {
  readonly fixture: string | null;
  readonly idle: boolean;
  readonly scale: ScaleMode;
  readonly zoom: ZoomSettings;
}

/**
 * The sandbox in the browser: a PixiJS surface, the renderer, gestures on the canvas, and the
 * wiring that turns an intent into the next view. Imperative, mounted by `Sandbox.tsx`.
 */
export class SandboxController {
  private state: SandboxState;
  private atlas: SandboxInfo["atlas"] = "loading";
  private library: SpriteLibrary | null = null;
  private idle: boolean;
  private zoom: ZoomSettings;
  private readonly cleanups: (() => void)[] = [];
  private listener: ((info: SandboxInfo) => void) | null = null;

  private constructor(
    private readonly app: Application,
    private readonly surface: PixiSurface,
    private readonly renderer: Renderer,
    options: SandboxOptions,
  ) {
    this.state = initialState(fixtureNamed(options.fixture));
    this.idle = options.idle;
    this.zoom = options.zoom;
  }

  static async mount(host: HTMLElement, options: SandboxOptions): Promise<SandboxController> {
    const { app, surface } = await createPixiSurface(host, options.scale);
    let controller: SandboxController | null = null;
    const renderer = new Renderer(surface, browserHost(), {
      idle: options.idle,
      mode: options.scale,
      zoom: options.zoom,
      onDraw: () => controller?.notify(),
    });
    controller = new SandboxController(app, surface, renderer, options);
    controller.start(host);
    return controller;
  }

  private start(host: HTMLElement): void {
    const resize = () => {
      const width = Math.max(1, host.clientWidth);
      const height = Math.max(1, host.clientHeight);
      this.app.renderer.resize(width, height);
      this.renderer.resize({ width, height });
    };
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(host);
    this.cleanups.push(() => observer.disconnect());
    this.renderer.setView(toView(this.state));
    this.listenToGestures(this.app.canvas);
    loadAtlas()
      .then((library) => {
        this.atlas = library ? "loaded" : "none";
        this.library = library;
        if (library) this.renderer.setLibrary(library);
        else
          console.info(
            "[sandbox] no atlas at /art/: drawing shapes (build tools/art to see sprites)",
          );
        this.notify();
      })
      .catch((error: unknown) => {
        this.atlas = "failed";
        console.error("[sandbox] the atlas failed to load; drawing shapes", error);
        this.notify();
      });
  }

  private listenToGestures(canvas: HTMLCanvasElement): void {
    const tracker = new GestureTracker((gesture) => this.onGesture(gesture), {
      set: (callback, ms) => window.setTimeout(callback, ms),
      clear: (handle) => window.clearTimeout(handle),
    });
    const at = (event: PointerEvent | WheelEvent) => {
      const rect = canvas.getBoundingClientRect();
      return { x: event.clientX - rect.left, y: event.clientY - rect.top };
    };
    const listeners: [string, (event: Event) => void, AddEventListenerOptions?][] = [
      [
        "pointerdown",
        (e) => {
          const event = e as PointerEvent;
          canvas.setPointerCapture(event.pointerId);
          this.renderer.scheduler.input();
          tracker.down(event.pointerId, at(event), event.button);
        },
      ],
      ["pointermove", (e) => tracker.move((e as PointerEvent).pointerId, at(e as PointerEvent))],
      ["pointerup", (e) => tracker.up((e as PointerEvent).pointerId)],
      ["pointercancel", (e) => tracker.cancel((e as PointerEvent).pointerId)],
      [
        "wheel",
        (e) => {
          e.preventDefault();
          this.renderer.scheduler.input();
          tracker.wheel((e as WheelEvent).deltaY, at(e as WheelEvent));
        },
        { passive: false },
      ],
      ["contextmenu", (e) => e.preventDefault()],
    ];
    for (const [type, listener, options] of listeners) {
      canvas.addEventListener(type, listener, options);
      this.cleanups.push(() => canvas.removeEventListener(type, listener, options));
    }
    this.cleanups.push(() => tracker.destroy());
  }

  private onGesture(gesture: Gesture): void {
    switch (gesture.kind) {
      case "pan":
        this.renderer.pan(gesture.dx, gesture.dy);
        return;
      case "zoom":
        this.renderer.zoomAt(gesture.factor, gesture.point);
        return;
      case "tap":
      case "press": {
        const { camera, viewport } = this.renderer.cameraState();
        const tile = screenToTile(camera, viewport, gesture.point);
        const intent: Intent =
          gesture.kind === "tap" ? { kind: "tile", tile } : { kind: "inspect", tile };
        this.apply(intent);
      }
    }
  }

  /** The sandbox's wiring applies the intent; the renderer draws the next view. */
  apply(intent: Intent): void {
    this.state = applyIntent(this.state, intent);
    console.debug("[sandbox]", intent, "→", this.state.said);
    this.renderer.setView(toView(this.state));
    this.notify();
  }

  setFixture(name: string): void {
    this.state = initialState(fixtureNamed(name));
    this.renderer.setView(toView(this.state));
    const url = new URL(window.location.href);
    url.searchParams.set("fixture", this.state.world.name);
    window.history.replaceState(null, "", url);
    this.notify();
  }

  setIdle(on: boolean): void {
    this.idle = on;
    this.renderer.scheduler.input();
    this.renderer.setIdle(on);
    this.notify();
  }

  /** The scale mode: the canvas resolution first (it counts `snap`'s pixels), then the renderer. */
  setScaleMode(mode: ScaleMode): void {
    this.surface.setResolution(canvasResolution(mode, window.devicePixelRatio));
    this.renderer.scheduler.input();
    this.renderer.setMode(mode);
    const url = new URL(window.location.href);
    url.searchParams.set("scale", mode);
    window.history.replaceState(null, "", url);
    this.notify();
  }

  setZoom(zoom: ZoomSettings): void {
    this.zoom = zoom;
    this.renderer.setZoomSettings(zoom);
    this.notify();
  }

  zoomTo(across: number): void {
    this.renderer.zoomTo(across);
    this.notify();
  }

  recentre(): void {
    this.renderer.scheduler.input();
    this.renderer.recentre();
  }

  setSpriteScale(name: string, scale: number): void {
    this.renderer.setSpriteScale(name, scale);
    this.notify();
  }

  /** The panel listens only while it is open, so that a closed panel costs nothing. */
  listen(listener: ((info: SandboxInfo) => void) | null): void {
    this.listener = listener;
    this.notify();
  }

  info(): SandboxInfo {
    const names = new Set<string>();
    for (const actor of this.state.world.actors) {
      names.add(actor.side === "adventurer" ? actor.profession : actor.caste);
    }
    const all = this.library ? [...this.library.keys()] : [...names];
    return {
      fixture: this.state.world.name,
      description: this.state.world.description,
      stats: this.renderer.scheduler.stats(),
      zoomInfo: this.renderer.zoomInfo(),
      zoom: this.zoom,
      idle: this.idle,
      atlas: this.atlas,
      sprites: all.map((name) => ({ name, scale: this.renderer.spriteScale(name) })),
      said: this.state.said,
      tickersRunning: pixiTickersRunning(this.app),
    };
  }

  destroy(): void {
    for (const cleanup of this.cleanups.splice(0)) cleanup();
    this.listener = null;
    this.renderer.destroy();
    this.app.destroy(true);
  }

  private notify(): void {
    this.listener?.(this.info());
  }
}
