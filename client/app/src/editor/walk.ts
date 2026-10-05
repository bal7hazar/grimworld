import { screenToTile, tileToScreen } from "../input/coords";
import { type Gesture, GestureTracker, WHEEL_NOTCH } from "../input/gestures";
import type { Intent } from "../input/intent";
import type { StepKey } from "../input/keys";
import { type Renderer, STEP_MS } from "../render/renderer";
import { browserHost } from "../render/scheduler";
import type { Tile, ViewState } from "../render/view";
import { SandboxSession, type ViewSink } from "../sandbox/session";
import { stepTarget } from "../sandbox/wiring";
import type { SandboxWorld } from "../sandbox/world";

/** The pace of the preview's walk: the game's (`params.ts`'s default step). */
export const WALK_STEP_MS = STEP_MS;

/**
 * Fog off (§2.8): every tile drawn as the chain holds it. The walk stays the game's: the session
 * still explores and stops as on entering; only what the renderer is sent shows the whole map.
 */
export function unfogged(view: ViewState): ViewState {
  const { revealed, ...rest } = view;
  return { ...rest, tiles: revealed ?? view.tiles, fog: undefined };
}

/**
 * The preview walk (CLI-09b, brief §2.8) on the edit canvas's own renderer (one PixiJS application
 * a page: two share GPU state badly): the game's `SandboxSession` on the world `walkWorld` builds,
 * the game's gestures on the renderer's canvas (tap walks, a press or a right click inspects, drag
 * pans, the wheel zooms). `EditorCanvas.beginWalk` makes one and gives the camera back after it.
 */
export class WalkMode {
  private readonly cleanups: (() => void)[] = [];
  readonly session: SandboxSession;

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly renderer: Renderer,
    world: SandboxWorld,
    fog: boolean,
    onChange: () => void,
  ) {
    const sink: ViewSink = {
      setView: (view) => renderer.setView(fog ? view : unfogged(view)),
    };
    this.session = new SandboxSession(world, sink, browserHost(), {
      playOnTap: true,
      stepMs: WALK_STEP_MS,
      fog: "sight",
      onChange,
    });
    this.listen();
  }

  private listen(): void {
    const canvas = this.canvas;
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
        this.session.apply(intent);
      }
    }
  }

  /** A step key (CLI-03k): a tap on the adjacent hex that way, as the game's controller. */
  step(step: StepKey): void {
    const tile = stepTarget(this.session.state, step);
    if (!tile) return;
    this.renderer.scheduler.input();
    this.session.apply({ kind: "tile", tile });
  }

  zoomBy(by: 1 | -1): void {
    const { viewport } = this.renderer.cameraState();
    this.renderer.scheduler.input();
    this.renderer.zoomAt(by > 0 ? WHEEL_NOTCH : 1 / WHEEL_NOTCH, {
      x: viewport.width / 2,
      y: viewport.height / 2,
    });
  }

  recentre(): void {
    this.renderer.scheduler.input();
    this.renderer.recentre();
  }

  cancel(): void {
    this.session.cancel();
  }

  /** Where the walker stands, in the preview's world. */
  walkerTile(): Tile | null {
    const { world } = this.session.state;
    return world.actors.find((a) => a.id === world.adventurerId)?.tile ?? null;
  }

  /** For the browser check: where a tile of the preview's world is on the page. */
  tileOnScreen(tile: Tile): { x: number; y: number } {
    const { camera, viewport } = this.renderer.cameraState();
    const p = tileToScreen(camera, viewport, tile);
    const rect = this.canvas.getBoundingClientRect();
    return { x: rect.left + p.x, y: rect.top + p.y };
  }

  destroy(): void {
    for (const cleanup of this.cleanups.splice(0)) cleanup();
    this.session.destroy();
  }
}
