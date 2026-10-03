import type { Application } from "pixi.js";
import { pixelToTile, screenToTile, tileToScreen } from "../input/coords";
import { type Gesture, GestureTracker, WHEEL_NOTCH } from "../input/gestures";
import type { Intent } from "../input/intent";
import type { StepKey } from "../input/keys";
import { loadAtlas } from "../render/atlas";
import { type PixiSurface, createPixiSurface, pixiTickersRunning } from "../render/pixiSurface";
import { type ScaleMode, canvasResolution } from "../render/scaling";
import { Renderer, type ZoomInfo, type ZoomSettings } from "../render/renderer";
import type { FrameStats } from "../render/scheduler";
import { browserHost } from "../render/scheduler";
import type { SpriteLibrary } from "../render/sprites";
import type { Tile } from "../render/view";
import { fixtureNamed } from "./fixtures";
import { SandboxSession, type WalkInfo } from "./session";
import { stepTarget } from "./wiring";
import type { SandboxWorld } from "./world";

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
  /** The feet below the tile's centre, a fraction of the inner radius. */
  readonly feet: number;
  /** Move is played on the tap (design/11's default); off, tap twice. */
  readonly playOnTap: boolean;
  /** Where the adventurer stands, and the tile at the camera's centre. */
  readonly adventurerTile: Tile | null;
  readonly cameraTile: Tile;
}

export interface SandboxOptions {
  readonly fixture: string | null;
  /** A world to open instead of the fixture: the instance of the loop (CLI-03c). */
  readonly world?: SandboxWorld;
  readonly idle: boolean;
  readonly scale: ScaleMode;
  readonly zoom: ZoomSettings;
  readonly feet: number;
  readonly playOnTap: boolean;
  readonly stepMs: number;
  /**
   * Applied to a map intent before the session (CLI-03f, the hub screen): another intent, or null
   * when the intent was answered outside the map. The zone passes none.
   */
  readonly route?: (intent: Intent) => Intent | null;
}

/**
 * The sandbox in the browser: a PixiJS surface, the renderer, gestures on the canvas, and the
 * wiring that turns an intent into the next view. Imperative, mounted by `Sandbox.tsx`.
 */
export class SandboxController {
  private readonly session: SandboxSession;
  private atlas: SandboxInfo["atlas"] = "loading";
  private library: SpriteLibrary | null = null;
  private idle: boolean;
  private zoom: ZoomSettings;
  private readonly cleanups: (() => void)[] = [];
  private destroyed = false;
  private listener: ((info: SandboxInfo) => void) | null = null;
  private walkListener: ((walk: WalkInfo) => void) | null = null;
  private frameListener: ((stats: FrameStats) => void) | null = null;
  private readonly route: ((intent: Intent) => Intent | null) | null;

  private constructor(
    private readonly app: Application,
    private readonly surface: PixiSurface,
    private readonly renderer: Renderer,
    options: SandboxOptions,
  ) {
    const world = options.world ?? fixtureNamed(options.fixture);
    this.session = new SandboxSession(world, renderer, browserHost(), {
      playOnTap: options.playOnTap,
      stepMs: options.stepMs,
      onChange: () => {
        // Every change, a tap's or a walk's step on its timer: what was planned and what was done.
        console.debug("[sandbox]", this.session.state.said);
        this.walkListener?.(this.session.walk());
        this.notify();
      },
    });
    this.idle = options.idle;
    this.zoom = options.zoom;
    this.route = options.route ?? null;
  }

  static async mount(host: HTMLElement, options: SandboxOptions): Promise<SandboxController> {
    const { app, surface } = await createPixiSurface(host, options.scale);
    let controller: SandboxController | null = null;
    const renderer = new Renderer(surface, browserHost(), {
      idle: options.idle,
      mode: options.scale,
      zoom: options.zoom,
      feet: options.feet,
      stepMs: options.stepMs,
      onDraw: (stats) => {
        controller?.frameListener?.(stats);
        controller?.notify();
      },
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
    this.listenToGestures(this.app.canvas);
    loadAtlas()
      .then((library) => {
        if (this.destroyed) return;
        this.atlas = library ? "loaded" : "none";
        this.library = library;
        if (library) this.renderer.setLibrary(library);
        else {
          console.info(
            "[sandbox] no atlas at /art/: drawing shapes (build tools/art to see sprites)",
          );
          // One frame, so that what listens to frames reads the atlas's state.
          this.renderer.scheduler.invalidate();
        }
        this.notify();
      })
      .catch((error: unknown) => {
        if (this.destroyed) return;
        this.atlas = "failed";
        console.error("[sandbox] the atlas failed to load; drawing shapes", error);
        this.renderer.scheduler.invalidate();
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

  /** The sandbox's wiring applies the intent, once routed; the renderer draws the next view. */
  apply(intent: Intent): void {
    console.debug("[sandbox]", intent.kind, `(${intent.tile.x}, ${intent.tile.y})`);
    const routed = this.route ? this.route(intent) : intent;
    if (routed) this.session.apply(routed);
  }

  /**
   * A step key (CLI-03k): exactly a tap on the adjacent hex that way, routed like one (a hub's
   * place walks to its door). Nothing when there is no adventurer.
   */
  step(step: StepKey): void {
    const tile = stepTarget(this.session.state, step);
    if (!tile) return;
    this.renderer.scheduler.input();
    this.apply({ kind: "tile", tile });
  }

  /** `+` / `−` (CLI-03k): one wheel notch in or out, around the map's centre; clamped as any zoom. */
  zoomBy(by: 1 | -1): void {
    const { viewport } = this.renderer.cameraState();
    this.renderer.scheduler.input();
    this.renderer.zoomAt(by > 0 ? WHEEL_NOTCH : 1 / WHEEL_NOTCH, {
      x: viewport.width / 2,
      y: viewport.height / 2,
    });
  }

  /** Eases the camera to a tile (a place selected by key, off the screen); `recentre` comes back. */
  lookAt(tile: Tile): void {
    this.renderer.scheduler.input();
    this.renderer.lookAt(tile);
  }

  /** A tap on the counter: the planned queue's steps not walked fade out. */
  cancelWalk(): void {
    this.renderer.scheduler.input();
    this.session.cancel();
  }

  setFixture(name: string): void {
    this.session.setWorld(fixtureNamed(name));
    this.setParam("fixture", this.session.state.world.name);
  }

  setFeet(fraction: number): void {
    this.renderer.setFeet(fraction);
    this.setParam("feet", String(fraction));
    this.notify();
  }

  setPlayOnTap(on: boolean): void {
    this.session.setPlayOnTap(on);
    this.setParam("confirm", on ? null : "1");
    this.notify();
  }

  private setParam(name: string, value: string | null): void {
    const url = new URL(window.location.href);
    if (value === null) url.searchParams.delete(name);
    else url.searchParams.set(name, value);
    window.history.replaceState(null, "", url);
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
    this.setParam("scale", mode);
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

  /** The counter of the planned queue listens always: it changes only on a tap or a step. */
  listenToWalk(listener: ((walk: WalkInfo) => void) | null): void {
    this.walkListener = listener;
    listener?.(this.session.walk());
  }

  /** Whether the atlas is loaded (the browser check reads it). */
  atlasState(): SandboxInfo["atlas"] {
    return this.atlas;
  }

  /** After every frame drawn: the page places what follows the camera (a hub's labels). */
  listenToFrames(listener: ((stats: FrameStats) => void) | null): void {
    this.frameListener = listener;
  }

  /** Where a tile's centre is on the canvas, in CSS pixels, with the camera as last drawn. */
  tileOnScreen(tile: Tile): { x: number; y: number } {
    const { camera, viewport } = this.renderer.cameraState();
    return tileToScreen(camera, viewport, tile);
  }

  /** Whether a structure is drawn from the atlas (else a shape), or null when there is none. */
  structureFromAtlas(key: string): boolean | null {
    return this.renderer.structureFromAtlas(key);
  }

  /** The canvas's CSS pixels per art pixel. */
  scale(): number {
    return this.renderer.cameraState().camera.scale;
  }

  /** The panel listens only while it is open, so that a closed panel costs nothing. */
  listen(listener: ((info: SandboxInfo) => void) | null): void {
    this.listener = listener;
    this.notify();
  }

  /** Where the adventurer stands: the loop reads it after every change (a hub gate's anchor). */
  adventurerTile(): Tile | null {
    const { world } = this.session.state;
    return world.actors.find((a) => a.id === world.adventurerId)?.tile ?? null;
  }

  info(): SandboxInfo {
    const names = new Set<string>();
    const state = this.session.state;
    for (const actor of state.world.actors) {
      names.add(actor.side === "adventurer" ? actor.profession : actor.caste);
    }
    const all = this.library ? [...this.library.keys()] : [...names];
    return {
      fixture: state.world.name,
      description: state.world.description,
      stats: this.renderer.scheduler.stats(),
      zoomInfo: this.renderer.zoomInfo(),
      zoom: this.zoom,
      idle: this.idle,
      atlas: this.atlas,
      sprites: all.map((name) => ({ name, scale: this.renderer.spriteScale(name) })),
      said: state.said,
      tickersRunning: pixiTickersRunning(this.app),
      feet: this.renderer.feetFraction(),
      playOnTap: this.session.playOnTap(),
      adventurerTile: this.adventurerTile(),
      cameraTile: pixelToTile(this.renderer.cameraState().camera.centre),
    };
  }

  destroy(): void {
    this.destroyed = true;
    for (const cleanup of this.cleanups.splice(0)) cleanup();
    this.listener = null;
    this.walkListener = null;
    this.frameListener = null;
    this.session.destroy();
    this.renderer.destroy();
    this.app.destroy(true);
  }

  private notify(): void {
    this.listener?.(this.info());
  }
}
