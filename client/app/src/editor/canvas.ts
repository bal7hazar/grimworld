import type { Application } from "pixi.js";
import {
  HEX_RADIUS,
  type Point,
  ROW_HEIGHT,
  TILE_WIDTH,
  type Viewport,
  fitScale,
  pixelToTile,
  screenToTile,
  screenToWorld,
  tileToPixel,
} from "../input/coords";
import { WHEEL_NOTCH } from "../input/gestures";
import { loadAtlas } from "../render/atlas";
import { createPixiSurface } from "../render/pixiSurface";
import { DEFAULT_ZOOM, Renderer, type ZoomSettings } from "../render/renderer";
import { browserHost } from "../render/scheduler";
import type { Tile, ViewState } from "../render/view";
import type { SandboxWorld } from "../sandbox/world";
import { CHUNK, type TileBox } from "./model";
import { type OverlayScene, drawOverlays, visibleRange } from "./overlay";
import { holds, viewWindow } from "./view";
import { WalkMode } from "./walk";

/** What the canvas tells the editor: pointer strokes, the hovered hex, the brush wheel. */
export interface CanvasEvents {
  /** A stroke starts: the left button (or the right, `erase`), `alt` for Pick, `shift` adds. */
  strokeStart(
    tile: Tile,
    how: { readonly erase: boolean; readonly alt: boolean; readonly shift: boolean },
  ): void;
  /** The hexes the pointer crossed since the last call, in order. */
  strokeMove(tiles: readonly Tile[]): void;
  strokeEnd(): void;
  hover(tile: Tile | null): void;
  /** Shift + wheel: the brush's size. */
  brush(by: 1 | -1): void;
  /** Something changed on screen: the camera, the zoom, the atlas. */
  changed(): void;
}

export type AtlasState = "loading" | "loaded" | "none" | "failed";

/** The scale at which `tiles` columns and rows fit the viewport, with half a hex of margin. */
export function fitMapScale(viewport: Viewport, columns: number, rows: number): number {
  const width = (columns + 1) * TILE_WIDTH;
  const height = (rows - 1) * ROW_HEIGHT + 2 * HEX_RADIUS + TILE_WIDTH;
  return Math.min(viewport.width / width, viewport.height / height);
}

/** The tiles across at which `columns × rows` tiles fit the viewport. */
function acrossFor(viewport: Viewport, columns: number, rows: number): number {
  const wanted = fitMapScale(viewport, columns, rows);
  let across = 4;
  while (fitScale(viewport, across) > wanted && across < 4000) across += 1;
  return across;
}

/** How far out the zoom goes at least (D-216): a full zone of 15 × 15 chunks and a chunk around it. */
export const ZOOM_OUT_TILES = 17 * CHUNK;

/**
 * The zoom of a map (§3, Zoom): as the game's `DEFAULT_ZOOM`, the default (where `0` goes) the
 * painted hexes, and `minAcross` raised so that they and a full zone's room around them fit.
 */
export function mapZoom(viewport: Viewport, columns: number, rows: number): ZoomSettings {
  const across = acrossFor(viewport, columns, rows);
  const room = acrossFor(
    viewport,
    Math.max(columns, ZOOM_OUT_TILES),
    Math.max(rows, ZOOM_OUT_TILES),
  );
  return {
    ...DEFAULT_ZOOM,
    defaultAcross: across,
    minAcross: Math.max(DEFAULT_ZOOM.minAcross, across, room),
  };
}

/**
 * The chunks a frame may bake that can wait (CLI-09g, `RendererOptions.bakesPerFrame`): a zoom that
 * changes the bakes' resolution rebakes the whole window's chunks over the next frames, not in one.
 */
export const BAKES_PER_FRAME = 2;

/**
 * How many times sharper than the zoom wants the chunks' textures may stay (CLI-09g,
 * `RendererOptions.keepSharper`): a zoom out to half the scale rebakes nothing.
 */
export const KEEP_SHARPER = 2;

/**
 * How long the zoom must be still before the chunks are baked at its resolution (CLI-09g,
 * `RendererOptions.rescaleAfterMs`): a wheel or a pinch going on bakes nothing.
 */
export const RESCALE_AFTER_MS = 200;

/**
 * The camera's moves are told to the editor (`CanvasEvents.changed`: the status bar's zoom) at most
 * once in this many ms, and once more after the last (CLI-09g): a zoom does not render the
 * editor's screen again at every frame.
 */
export const CAMERA_NOTICE_MS = 250;

/** How many overlay frame times are kept. */
const OVERLAY_SAMPLES = 600;

/** What `0` fits when nothing is painted: a 3 × 2-chunk area from `(0, 0)`. */
export const EMPTY_BOX: TileBox = { x0: 0, y0: 0, x1: 3 * CHUNK - 1, y1: 2 * CHUNK - 1 };

/** The world point at the middle of a box of tiles. */
export function mapCentre(box: TileBox): Point {
  const a = tileToPixel({ x: box.x0, y: box.y0 });
  const b = tileToPixel({ x: box.x1, y: box.y1 });
  return { x: (a.x + b.x - TILE_WIDTH / 2) / 2, y: (a.y + b.y) / 2 };
}

/** The hexes on the segment between two world points, each once, in order. */
export function hexesAlong(from: Point, to: Point): Tile[] {
  const length = Math.hypot(to.x - from.x, to.y - from.y);
  const steps = Math.max(1, Math.ceil(length / (TILE_WIDTH / 4)));
  const out: Tile[] = [];
  for (let k = 1; k <= steps; k++) {
    const t = k / steps;
    const tile = pixelToTile({ x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t });
    const last = out.at(-1);
    if (!last || last.x !== tile.x || last.y !== tile.y) out.push(tile);
  }
  return out;
}

/**
 * The editor's canvas in the browser: the game's renderer on a PixiJS surface, a 2D canvas of
 * overlays over it, and the pointer. Imperative, mounted by `EditorScreen`.
 */
export class EditorCanvas {
  atlas: AtlasState = "loading";
  private readonly cleanups: (() => void)[] = [];
  private destroyed = false;
  private scene: OverlayScene | null = null;
  private box: TileBox = EMPTY_BOX;
  /** Builds the view of the tiles around a window (`editorView`). */
  private source: ((window: TileBox) => ViewState) | null = null;
  /** The window last sent to the renderer: rebuilt when the camera leaves it. */
  private window: TileBox | null = null;
  private spaceHeld = false;
  private overlayFrame: number | null = null;
  /** `CAMERA_NOTICE_MS`: the pending notice's timer, and whether the camera moved since the last. */
  private noticeTimer: number | null = null;
  private movedSinceNotice = false;
  /** The last overlay frames' drawing times in ms (the browser check reads them). */
  readonly overlayMs: number[] = [];
  /** The editor's zoom (`mapZoom`), and whether the author zoomed by hand since `0`. */
  private zoom: ZoomSettings = DEFAULT_ZOOM;
  private zoomedByHand = false;
  /** The preview walk on this renderer (§2.8), and the camera it gives back. */
  private walk: { readonly mode: WalkMode; readonly centre: Point; readonly scale: number } | null =
    null;

  private constructor(
    private readonly app: Application,
    private readonly renderer: Renderer,
    private readonly overlay: HTMLCanvasElement,
    private readonly events: CanvasEvents,
  ) {}

  static async mount(host: HTMLElement, events: CanvasEvents): Promise<EditorCanvas> {
    const { app, surface } = await createPixiSurface(host, "continuous");
    let canvas: EditorCanvas | null = null;
    const renderer = new Renderer(surface, browserHost(), {
      idle: false,
      mode: "continuous",
      bakesPerFrame: BAKES_PER_FRAME,
      keepSharper: KEEP_SHARPER,
      rescaleAfterMs: RESCALE_AFTER_MS,
      onDraw: () => canvas?.drawOverlay(),
    });
    const overlay = document.createElement("canvas");
    overlay.dataset.overlay = "";
    Object.assign(overlay.style, {
      position: "absolute",
      inset: "0",
      width: "100%",
      height: "100%",
      touchAction: "none",
    });
    host.appendChild(overlay);
    canvas = new EditorCanvas(app, renderer, overlay, events);
    canvas.start(host);
    return canvas;
  }

  private start(host: HTMLElement): void {
    const resize = () => {
      const width = Math.max(1, host.clientWidth);
      const height = Math.max(1, host.clientHeight);
      this.app.renderer.resize(width, height);
      const ratio = window.devicePixelRatio || 1;
      this.overlay.width = Math.round(width * ratio);
      this.overlay.height = Math.round(height * ratio);
      this.renderer.resize({ width, height });
      this.cameraMoved();
    };
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(host);
    this.cleanups.push(() => observer.disconnect());
    this.listen();
    loadAtlas()
      .then((library) => {
        if (this.destroyed) return;
        this.atlas = library ? "loaded" : "none";
        if (library) this.renderer.setLibrary(library);
        else this.renderer.scheduler.invalidate();
        this.events.changed();
      })
      .catch((error: unknown) => {
        if (this.destroyed) return;
        this.atlas = "failed";
        console.error("[editor] the atlas failed to load; drawing shapes", error);
        this.renderer.scheduler.invalidate();
        this.events.changed();
      });
  }

  /** The painted hexes' box (null: nothing painted), which `0` fits. */
  setPainted(box: TileBox | null): void {
    this.box = box ?? EMPTY_BOX;
  }

  /**
   * Where the view comes from (D-216): the renderer is sent only the tiles of a window around the
   * visible ones (`viewWindow`), rebuilt when the document changes (`refreshView`) or the camera
   * leaves the window.
   */
  setViewSource(source: (window: TileBox) => ViewState): void {
    this.source = source;
    this.refreshView();
  }

  /** The document changed: the window's view again. */
  refreshView(): void {
    if (!this.source || this.walk) return;
    const { camera, viewport } = this.renderer.cameraState();
    this.window = viewWindow(visibleRange(camera, viewport));
    this.renderer.setView(this.source(this.window));
  }

  /** Every camera move: a new window when the visible tiles leave the last one. */
  private cameraMoved(): void {
    if (this.walk) return;
    const { camera, viewport } = this.renderer.cameraState();
    if (!this.window || !holds(this.window, visibleRange(camera, viewport))) this.refreshView();
    this.noticeMove();
  }

  /** The camera moved: the editor is told now, or when `CAMERA_NOTICE_MS` has passed. */
  private noticeMove(): void {
    if (this.noticeTimer !== null) {
      this.movedSinceNotice = true;
      return;
    }
    this.events.changed();
    this.noticeTimer = window.setTimeout(() => {
      this.noticeTimer = null;
      if (this.destroyed || !this.movedSinceNotice) return;
      this.movedSinceNotice = false;
      this.noticeMove();
    }, CAMERA_NOTICE_MS);
  }

  setScene(scene: OverlayScene): void {
    this.scene = scene;
    this.scheduleOverlay();
  }

  /** `0`: the painted hexes, centred. */
  fit(): void {
    const { viewport } = this.renderer.cameraState();
    const { x0, y0, x1, y1 } = this.box;
    this.zoom = mapZoom(viewport, x1 - x0 + 1, y1 - y0 + 1);
    this.zoomedByHand = false;
    this.renderer.setZoomSettings(this.zoom);
    this.centreOn(mapCentre(this.box));
  }

  /** The validation's Show (§2.6): the camera on a hex, the zoom kept. */
  showTile(tile: Tile): void {
    this.centreOn(tileToPixel(tile));
  }

  private centreOn(target: Point): void {
    const { camera } = this.renderer.cameraState();
    this.renderer.pan(
      (camera.centre.x - target.x) * camera.scale,
      (camera.centre.y - target.y) * camera.scale,
    );
    this.cameraMoved();
  }

  zoomBy(by: 1 | -1): void {
    const { viewport } = this.renderer.cameraState();
    this.zoomedByHand = true;
    this.renderer.zoomAt(by > 0 ? WHEEL_NOTCH : 1 / WHEEL_NOTCH, {
      x: viewport.width / 2,
      y: viewport.height / 2,
    });
    this.cameraMoved();
  }

  /** The arrows: a quarter of the viewport. */
  panBy(dx: number, dy: number): void {
    const { viewport } = this.renderer.cameraState();
    this.renderer.pan(-dx * viewport.width * 0.25, -dy * viewport.height * 0.25);
    this.cameraMoved();
  }

  /** Space held: a left drag pans. */
  setSpace(held: boolean): void {
    this.spaceHeld = held;
    this.overlay.style.cursor = held ? "grab" : "crosshair";
  }

  /** Hex columns across the viewport, as the status bar shows the zoom. */
  across(): number {
    return this.renderer.zoomInfo().across;
  }

  tileAt(point: Point): Tile {
    const { camera, viewport } = this.renderer.cameraState();
    return screenToTile(camera, viewport, point);
  }

  /** For the browser check: where a hex's centre is on the page. */
  tileOnScreen(tile: Tile): Point {
    const { camera, viewport } = this.renderer.cameraState();
    const p = tileToPixel(tile);
    const rect = this.overlay.getBoundingClientRect();
    return {
      x: rect.left + (p.x - camera.centre.x) * camera.scale + viewport.width / 2,
      y: rect.top + (p.y - camera.centre.y) * camera.scale + viewport.height / 2,
    };
  }

  /**
   * The preview walk (§2.8): the game's world and session on this renderer, at the game's zoom,
   * the overlays hidden and the editor's pointer off. `endWalk` gives the camera back.
   */
  beginWalk(world: SandboxWorld, fog: boolean, onChange: () => void): WalkMode {
    this.endWalk();
    const { camera } = this.renderer.cameraState();
    this.overlay.style.display = "none";
    this.renderer.setZoomSettings(DEFAULT_ZOOM);
    const mode = new WalkMode(this.app.canvas, this.renderer, world, fog, onChange);
    this.walk = { mode, centre: camera.centre, scale: camera.scale };
    return mode;
  }

  /**
   * The walk ends: the editor's view again, its zoom and its camera as they were (a scale the
   * author chose by hand is kept; the fitted zoom follows the viewport, as before the walk).
   */
  endWalk(): void {
    const walk = this.walk;
    if (!walk) return;
    walk.mode.destroy();
    this.walk = null;
    this.overlay.style.display = "";
    this.renderer.setZoomSettings(this.zoom);
    if (this.zoomedByHand) {
      const { camera, viewport } = this.renderer.cameraState();
      this.renderer.zoomAt(walk.scale / camera.scale, {
        x: viewport.width / 2,
        y: viewport.height / 2,
      });
    }
    this.centreOn(walk.centre);
    this.refreshView();
    this.scheduleOverlay();
  }

  private scheduleOverlay(): void {
    if (this.overlayFrame !== null) return;
    this.overlayFrame = window.requestAnimationFrame(() => {
      this.overlayFrame = null;
      this.drawOverlay();
    });
  }

  private drawOverlay(): void {
    const ctx = this.overlay.getContext("2d");
    if (!ctx || !this.scene || this.walk) return;
    const { camera, viewport } = this.renderer.cameraState();
    const ratio = this.overlay.width / Math.max(1, viewport.width);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    const start = performance.now();
    drawOverlays(ctx, camera, viewport, this.scene);
    this.overlayMs.push(performance.now() - start);
    if (this.overlayMs.length > OVERLAY_SAMPLES) this.overlayMs.shift();
  }

  private listen(): void {
    const canvas = this.overlay;
    canvas.style.cursor = "crosshair";
    const at = (event: MouseEvent): Point => {
      const rect = canvas.getBoundingClientRect();
      return { x: event.clientX - rect.left, y: event.clientY - rect.top };
    };
    let drag: { kind: "pan" | "stroke"; last: Point; id: number } | null = null;
    const world = (p: Point) => {
      const { camera, viewport } = this.renderer.cameraState();
      return screenToWorld(camera, viewport, p);
    };
    const listeners: [string, (event: Event) => void, AddEventListenerOptions?][] = [
      [
        "pointerdown",
        (e) => {
          const event = e as PointerEvent;
          if (drag) return;
          canvas.setPointerCapture(event.pointerId);
          this.renderer.scheduler.input();
          const point = at(event);
          const pan = event.button === 1 || (event.button === 0 && this.spaceHeld);
          if (pan) {
            drag = { kind: "pan", last: point, id: event.pointerId };
            canvas.style.cursor = "grabbing";
            return;
          }
          if (event.button !== 0 && event.button !== 2) return;
          drag = { kind: "stroke", last: point, id: event.pointerId };
          this.events.strokeStart(this.tileAt(point), {
            erase: event.button === 2,
            alt: event.altKey,
            shift: event.shiftKey,
          });
        },
      ],
      [
        "pointermove",
        (e) => {
          const event = e as PointerEvent;
          const point = at(event);
          this.events.hover(this.tileAt(point));
          if (!drag || drag.id !== event.pointerId) return;
          if (drag.kind === "pan") {
            this.renderer.pan(point.x - drag.last.x, point.y - drag.last.y);
            this.cameraMoved();
          } else {
            const tiles = hexesAlong(world(drag.last), world(point));
            if (tiles.length > 0) this.events.strokeMove(tiles);
          }
          drag.last = point;
        },
      ],
      [
        "pointerup",
        (e) => {
          const event = e as PointerEvent;
          if (!drag || drag.id !== event.pointerId) return;
          if (drag.kind === "stroke") this.events.strokeEnd();
          drag = null;
          this.setSpace(this.spaceHeld);
        },
      ],
      [
        "pointercancel",
        (e) => {
          const event = e as PointerEvent;
          if (!drag || drag.id !== event.pointerId) return;
          if (drag.kind === "stroke") this.events.strokeEnd();
          drag = null;
        },
      ],
      ["pointerleave", () => this.events.hover(null)],
      [
        "wheel",
        (e) => {
          const event = e as WheelEvent;
          event.preventDefault();
          this.renderer.scheduler.input();
          if (event.shiftKey) {
            const delta = event.deltaY || event.deltaX;
            if (delta !== 0) this.events.brush(delta > 0 ? -1 : 1);
            return;
          }
          // A trackpad's two-finger scroll pans (it moves sideways too); a pinch (Ctrl) or a
          // wheel zooms at the pointer, as the game's wheel.
          if (!event.ctrlKey && event.deltaX !== 0) {
            this.renderer.pan(-event.deltaX, -event.deltaY);
          } else {
            this.zoomedByHand = true;
            this.renderer.zoomAt(
              Math.exp((-event.deltaY * Math.log(WHEEL_NOTCH)) / 100),
              at(event),
            );
          }
          this.cameraMoved();
        },
        { passive: false },
      ],
      // The browser's context menu is suppressed on the canvas only (§3).
      ["contextmenu", (e) => e.preventDefault()],
      // The middle button's autoscroll.
      ["mousedown", (e) => (e as MouseEvent).button === 1 && e.preventDefault()],
    ];
    for (const [type, listener, options] of listeners) {
      canvas.addEventListener(type, listener, options);
      this.cleanups.push(() => canvas.removeEventListener(type, listener, options));
    }
  }

  destroy(): void {
    this.destroyed = true;
    this.walk?.mode.destroy();
    this.walk = null;
    if (this.overlayFrame !== null) window.cancelAnimationFrame(this.overlayFrame);
    if (this.noticeTimer !== null) window.clearTimeout(this.noticeTimer);
    for (const cleanup of this.cleanups.splice(0)) cleanup();
    this.renderer.destroy();
    this.overlay.remove();
    this.app.destroy(true);
  }
}
