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
import { type OverlayScene, drawOverlays } from "./overlay";

/** What the canvas tells the editor: pointer strokes, the hovered hex, the brush wheel. */
export interface CanvasEvents {
  /** A stroke starts: the left button (or the right, `erase`), `alt` for Pick. */
  strokeStart(tile: Tile, how: { readonly erase: boolean; readonly alt: boolean }): void;
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

/**
 * The zoom of a map (§3, Zoom): as the game's `DEFAULT_ZOOM`, but `minAcross` raised so that the
 * whole map fits, and the default (where `0` goes) the whole map.
 */
export function mapZoom(viewport: Viewport, columns: number, rows: number): ZoomSettings {
  const wanted = fitMapScale(viewport, columns, rows);
  let across = 4;
  while (fitScale(viewport, across) > wanted && across < 4000) across += 1;
  return {
    ...DEFAULT_ZOOM,
    defaultAcross: across,
    minAcross: Math.max(DEFAULT_ZOOM.minAcross, across),
  };
}

/** The world point at the middle of a map of `columns × rows` tiles. */
export function mapCentre(columns: number, rows: number): Point {
  const a = tileToPixel({ x: 0, y: 0 });
  const b = tileToPixel({ x: columns - 1, y: rows - 1 });
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
  private columns = 1;
  private rows = 1;
  private spaceHeld = false;
  private overlayFrame: number | null = null;

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
      this.events.changed();
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

  /** A new map's size: the zoom fits it and the camera centres it. */
  setMapSize(columns: number, rows: number): void {
    this.columns = columns;
    this.rows = rows;
    this.fit();
  }

  setView(view: ViewState): void {
    this.renderer.setView(view);
  }

  setScene(scene: OverlayScene): void {
    this.scene = scene;
    this.scheduleOverlay();
  }

  /** `0`: the whole map, centred. */
  fit(): void {
    const { viewport } = this.renderer.cameraState();
    this.renderer.setZoomSettings(mapZoom(viewport, this.columns, this.rows));
    this.centreOn(mapCentre(this.columns, this.rows));
  }

  private centreOn(target: Point): void {
    const { camera } = this.renderer.cameraState();
    this.renderer.pan(
      (camera.centre.x - target.x) * camera.scale,
      (camera.centre.y - target.y) * camera.scale,
    );
    this.events.changed();
  }

  zoomBy(by: 1 | -1): void {
    const { viewport } = this.renderer.cameraState();
    this.renderer.zoomAt(by > 0 ? WHEEL_NOTCH : 1 / WHEEL_NOTCH, {
      x: viewport.width / 2,
      y: viewport.height / 2,
    });
    this.events.changed();
  }

  /** The arrows: a quarter of the viewport. */
  panBy(dx: number, dy: number): void {
    const { viewport } = this.renderer.cameraState();
    this.renderer.pan(-dx * viewport.width * 0.25, -dy * viewport.height * 0.25);
    this.events.changed();
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

  private scheduleOverlay(): void {
    if (this.overlayFrame !== null) return;
    this.overlayFrame = window.requestAnimationFrame(() => {
      this.overlayFrame = null;
      this.drawOverlay();
    });
  }

  private drawOverlay(): void {
    const ctx = this.overlay.getContext("2d");
    if (!ctx || !this.scene) return;
    const { camera, viewport } = this.renderer.cameraState();
    const ratio = this.overlay.width / Math.max(1, viewport.width);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    drawOverlays(ctx, camera, viewport, this.scene);
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
            this.events.changed();
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
            this.renderer.zoomAt(Math.exp(-event.deltaY * Math.log(WHEEL_NOTCH) / 100), at(event));
          }
          this.events.changed();
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
    if (this.overlayFrame !== null) window.cancelAnimationFrame(this.overlayFrame);
    for (const cleanup of this.cleanups.splice(0)) cleanup();
    this.renderer.destroy();
    this.overlay.remove();
    this.app.destroy(true);
  }
}
