import { type CSSProperties, type ReactNode, useEffect, useRef, useState } from "react";
import { Button, IconButton, useChromeMode } from "../chrome/Chrome";
import type { Intent } from "../input/intent";
import type { KeyCommand } from "../input/keys";
import type { ZoomSettings } from "../render/renderer";
import { SCALE_MODES, readScaleMode } from "../render/scaling";
import type { Tile } from "../render/view";
import { SandboxController, type SandboxInfo } from "./controller";
import { FIXTURES } from "./fixtures";
import { installKeys, useKeyLayer } from "./keyScope";
import { FEET_RANGE } from "../render/renderer";
import { Loop } from "./loop/Loop";
import { ACROSS_RANGE, readAcross, readFeet, readParams } from "./params";
import type { WalkInfo } from "./session";
import type { SandboxWorld } from "./world";

/**
 * The sandbox: a room (CLI-03a, `?fixture=`), or the loop of hubs and instances on fixed data
 * (CLI-03c, `?hub=`, `?loop=1`). URL parameters: see `params.ts`.
 */
export function Sandbox() {
  const [params] = useState(() => readParams(window.location.search));
  if (params.hub !== null) {
    return <Loop hub={params.hub} entryMs={params.entryMs} />;
  }
  return (
    <div style={styles.page}>
      <RoomSandbox />
    </div>
  );
}

/** What a screen's key handler gets of the map (CLI-03k). */
export interface MapKeys {
  /** Null while the renderer is still mounting: the screen's own keys work already. */
  readonly controller: SandboxController | null;
  /** The walk as last reported, or null before the first report. */
  readonly walk: WalkInfo | null;
  /** The map's own answer: a step, the zoom, ◎, or Esc on a planned walk. True when handled. */
  handle(command: KeyCommand): boolean;
}

/** The map's own keys: each one the tap or button it stands for. */
function mapKey(command: KeyCommand, controller: SandboxController | null, walk: WalkInfo | null) {
  if (!controller) return false;
  switch (command.kind) {
    case "step":
      controller.step(command);
      return true;
    case "zoom":
      controller.zoomBy(command.by);
      return true;
    case "recentre":
      controller.recentre();
      return true;
    case "escape":
      // The counter's action (design/11 *Desktop*, "Esc cancel").
      if (!walk || walk.steps === 0) return false;
      controller.cancelWalk();
      return true;
    default:
      return false;
  }
}

/**
 * The rendering sandbox (CLI-03a): the map on the whole of its box, a button back to the
 * adventurer, and a debug panel. In the loop it opens on `world` (the instance, or a hub lived like
 * a zone, CLI-03f), reports where the adventurer stands and how its walk goes after every change
 * (`onTile`), and carries the loop's controls (`children`) over the map. A hub's screen also routes
 * the map's intents before the session (`route`) and places its labels after each frame drawn
 * (`onFrame`). A hub shows no walk counter: a hub has no tick.
 *
 * For the browser check: the root's `data-frames` (frames drawn), `data-atlas`, `data-camera`
 * (tile (0, 0) on the canvas and the scale, after each frame), `data-tile` (where the adventurer
 * stands) and `data-walking`; CLI-03g1's `data-ground` (`atlas` when the ground is drawn from the
 * atlas's cells, `colours` otherwise) and `data-bake-ms` (the last chunk's bake, in ms).
 *
 * The keyboard (CLI-03k): the room is the map's key layer, a hub's or a zone's. A screen's
 * `onKey` sees each command first and may hand it to the map (`MapKeys.handle`); without one, the
 * map answers alone. Outside the loop (`?fixture=`) the room listens to the document itself. The
 * screen places what marks a selection among `children`, from `onFrame`.
 */
export function RoomSandbox({
  world,
  onTile,
  route,
  onFrame,
  onKey,
  children,
}: {
  world?: SandboxWorld;
  onTile?: (tile: Tile | null, walk: WalkInfo) => void;
  route?: (intent: Intent) => Intent | null;
  onFrame?: (controller: SandboxController) => void;
  onKey?: (command: KeyCommand, map: MapKeys) => boolean;
  children?: ReactNode;
} = {}) {
  const root = useRef<HTMLDivElement>(null);
  const host = useRef<HTMLDivElement>(null);
  const [controller, setController] = useState<SandboxController | null>(null);
  const [panelOpen, setPanelOpen] = useState(() => readParams(window.location.search).panel);
  const atlas = useChromeMode() === "atlas";
  const [info, setInfo] = useState<SandboxInfo | null>(null);
  const [walk, setWalk] = useState<WalkInfo | null>(null);
  const tileListener = useRef(onTile);
  tileListener.current = onTile;
  const router = useRef(route);
  router.current = route;
  const frameListener = useRef(onFrame);
  frameListener.current = onFrame;
  const hub = world?.kind === "hub";
  const lastWalk = useRef<WalkInfo | null>(null);
  const keyListener = useRef(onKey);
  keyListener.current = onKey;

  // Outside the loop, the room listens itself; in the loop, the loop does.
  useEffect(() => (world ? undefined : installKeys()), []);

  useKeyLayer(hub ? "hub" : "instance", (command) => {
    if (!command) return false;
    const map: MapKeys = {
      controller,
      walk: lastWalk.current,
      handle: (c) => mapKey(c, controller, lastWalk.current),
    };
    return keyListener.current ? keyListener.current(command, map) : map.handle(command);
  });

  useEffect(() => {
    const element = host.current;
    if (!element) return;
    let alive = true;
    let mounted: SandboxController | null = null;
    const routed = router.current
      ? { route: (intent: Intent) => (router.current ? router.current(intent) : intent) }
      : {};
    SandboxController.mount(element, { ...readParams(window.location.search), world, ...routed })
      .then((c) => {
        if (!alive) return c.destroy();
        mounted = c;
        setController(c);
      })
      .catch((error: unknown) => console.error("[sandbox] could not start the renderer", error));
    return () => {
      alive = false;
      mounted?.destroy();
    };
    // The world is the one the room opened on: a new world is a new room (the loop's key).
  }, []);

  useEffect(() => {
    if (!controller) return;
    controller.listen(panelOpen ? setInfo : null);
    return () => controller.listen(null);
  }, [controller, panelOpen]);

  useEffect(() => {
    if (!controller) return;
    controller.listenToWalk((next) => {
      lastWalk.current = next;
      setWalk(next);
      const tile = controller.adventurerTile();
      const element = root.current;
      if (element) {
        element.dataset.tile = tile ? `${tile.x},${tile.y}` : "";
        element.dataset.walking = String(next.walking);
      }
      tileListener.current?.(tile, next);
    });
    return () => controller.listenToWalk(null);
  }, [controller]);

  useEffect(() => {
    if (!controller) return;
    controller.listenToFrames((stats) => {
      if (root.current) {
        root.current.dataset.frames = String(stats.renders);
        root.current.dataset.atlas = controller.atlasState();
        // Where tile (0, 0)'s centre is on the canvas, and CSS pixels per art pixel.
        const origin = controller.tileOnScreen({ x: 0, y: 0 });
        root.current.dataset.camera = `${origin.x} ${origin.y} ${controller.scale()}`;
        // Written when they change only: a frame's callback stays as short as before.
        const data = root.current.dataset;
        const ground = stats.ground ?? "";
        const obstacles = stats.obstacles ?? "";
        const bake = stats.bakeMs == null ? "" : String(stats.bakeMs);
        if (data.ground !== ground) data.ground = ground;
        if (data.obstacles !== obstacles) data.obstacles = obstacles;
        if (data.bakeMs !== bake) data.bakeMs = bake;
      }
      frameListener.current?.(controller);
    });
    return () => controller.listenToFrames(null);
  }, [controller]);

  return (
    <div ref={root} style={styles.root}>
      <div ref={host} style={styles.canvas} />
      {controller && walk && !hub && <WalkCounter controller={controller} walk={walk} />}
      <IconButton
        glyph="◎"
        label="Back to the adventurer"
        plain={styles.centre}
        plainText="◎"
        style={styles.centrePlace}
        onClick={() => controller?.recentre()}
      />
      <button
        style={atlas ? { ...styles.toggle, ...styles.debugLook } : styles.toggle}
        onClick={() => setPanelOpen((open) => !open)}
      >
        {panelOpen ? "× debug" : "debug"}
      </button>
      {panelOpen && controller && info && (
        <DebugPanel controller={controller} info={info} fixtures={!world} />
      )}
      {children}
    </div>
  );
}

/**
 * The planned queue's counter (design/11 *The queue*), minimal until the HUD (CLI-05, CLI-08): the
 * steps left and their cost in ticks; a tap cancels. Under it, why the last walk stopped.
 */
function WalkCounter({ controller, walk }: { controller: SandboxController; walk: WalkInfo }) {
  const atlas = useChromeMode() === "atlas";
  if (walk.steps === 0 && !walk.stopped) return null;
  const tag = atlas ? undefined : styles.stopped;
  return (
    <div style={styles.walk}>
      {walk.steps > 0 && (
        <Button
          variant="quiet"
          plain={styles.counter}
          style={{ pointerEvents: "auto" }}
          onClick={() => controller.cancelWalk()}
          aria-label="Cancel the planned path"
        >
          {walk.walking ? "▶" : "◌"} {walk.steps} {walk.steps === 1 ? "step" : "steps"} ·{" "}
          {walk.cost} {walk.cost === 1 ? "tick" : "ticks"} ✕
        </Button>
      )}
      {walk.steps > 0 && !walk.walking && (
        <div className="gw-tag" style={tag}>
          tap the tile again to walk
        </div>
      )}
      {walk.stopped && (
        <div className="gw-tag" style={tag}>
          {walk.stopped}
        </div>
      )}
    </div>
  );
}

function DebugPanel({
  controller,
  info,
  fixtures,
}: {
  controller: SandboxController;
  info: SandboxInfo;
  /** The fixture can be changed (not in the loop's instance, whose world is the gate's). */
  fixtures: boolean;
}) {
  const atlas = useChromeMode() === "atlas";
  const zoom = info.zoom;
  const setZoom = (patch: Partial<ZoomSettings>) => controller.setZoom({ ...zoom, ...patch });
  return (
    <div style={atlas ? { ...styles.panel, ...styles.debugFrame } : styles.panel}>
      {fixtures && (
        <label style={styles.row}>
          fixture{" "}
          <select value={info.fixture} onChange={(e) => controller.setFixture(e.target.value)}>
            {Object.keys(FIXTURES).map((name) => (
              <option key={name}>{name}</option>
            ))}
          </select>
        </label>
      )}
      <div style={styles.note}>{info.description}</div>
      <label style={styles.row}>
        default zoom: tiles across{" "}
        <input
          type="number"
          min={ACROSS_RANGE.min}
          max={ACROSS_RANGE.max}
          step={1}
          value={zoom.defaultAcross}
          onChange={(e) => {
            const across = readAcross(e.target.value);
            if (across !== null) setZoom({ defaultAcross: across });
          }}
          style={styles.number}
        />
      </label>
      <div style={styles.row}>
        <button onClick={() => controller.zoomTo(zoom.defaultAcross)}>
          {zoom.defaultAcross} (default)
        </button>{" "}
        <button onClick={() => controller.zoomTo(zoom.closeAcross)}>
          {zoom.closeAcross} (close)
        </button>
      </div>
      <label style={styles.row}>
        scale{" "}
        <select
          value={info.zoomInfo.mode}
          onChange={(e) => controller.setScaleMode(readScaleMode(e.target.value))}
        >
          {SCALE_MODES.map((mode) => (
            <option key={mode}>{mode}</option>
          ))}
        </select>
      </label>
      <div style={styles.row}>
        devicePixelRatio <b>{info.zoomInfo.devicePixelRatio}</b>, canvas resolution{" "}
        <b>{info.zoomInfo.resolution}</b>
      </div>
      <div style={styles.row}>
        device px per art px <b>{info.zoomInfo.deviceScale.toFixed(2)}</b> (
        {info.zoomInfo.integer ? "integer" : "not an integer"}; canvas{" "}
        {info.zoomInfo.canvasScale.toFixed(2)})
      </div>
      {info.zoomInfo.offscreen && (
        <div style={styles.row}>
          offscreen: <b>{info.zoomInfo.offscreen.n}</b> canvas px per art px,{" "}
          {info.zoomInfo.offscreen.width} × {info.zoomInfo.offscreen.height} texels drawn (
          <b>{info.zoomInfo.offscreen.cost.toFixed(2)}×</b> the canvas), allocated{" "}
          {info.zoomInfo.offscreen.allocatedWidth} × {info.zoomInfo.offscreen.allocatedHeight} (
          {info.zoomInfo.offscreen.allocatedCost.toFixed(2)}×)
        </div>
      )}
      {info.zoomInfo.sharpFallback && (
        <div style={styles.row}>
          <b>sharp falls back</b>: its offscreen does not fit the GPU&apos;s texture limit; drawn
          directly, as continuous
        </div>
      )}
      <div style={styles.row}>
        tile width <b>{info.zoomInfo.tileWidth.toFixed(1)}</b> CSS pt (I-6: 40), tiles across{" "}
        <b>{info.zoomInfo.across.toFixed(1)}</b>
      </div>
      <label style={styles.row}>
        <input
          type="checkbox"
          checked={info.idle}
          onChange={(e) => controller.setIdle(e.target.checked)}
        />{" "}
        idle animations
      </label>
      <div style={styles.row}>
        frames drawn <b>{info.stats.renders}</b>, since last input <b>{info.stats.sinceInput}</b>
      </div>
      <div style={styles.row}>
        PixiJS tickers running: <b>{info.tickersRunning ? "YES (a loop!)" : "none"}</b>
      </div>
      <label style={styles.row}>
        <input
          type="checkbox"
          checked={info.playOnTap}
          onChange={(e) => controller.setPlayOnTap(e.target.checked)}
        />{" "}
        move played on the tap (off: tap twice)
      </label>
      <div style={styles.row}>
        adventurer at{" "}
        <b>{info.adventurerTile ? `(${info.adventurerTile.x}, ${info.adventurerTile.y})` : "—"}</b>,
        camera on ({info.cameraTile.x}, {info.cameraTile.y})
      </div>
      <div style={styles.row}>
        atlas: <b>{info.atlas}</b>
      </div>
      <label style={styles.row}>
        feet below the centre (× inner radius){" "}
        <input
          type="number"
          min={FEET_RANGE.min}
          max={FEET_RANGE.max}
          step={0.05}
          value={info.feet}
          onChange={(e) => {
            const feet = readFeet(e.target.value);
            if (feet !== null) controller.setFeet(feet);
          }}
          style={styles.number}
        />
      </label>
      {info.sprites.map((sprite) => (
        <label key={sprite.name} style={styles.row}>
          {sprite.name}{" "}
          <input
            type="number"
            min={0.1}
            max={4}
            step={0.05}
            value={sprite.scale}
            onChange={(e) => {
              const scale = Number(e.target.value);
              if (Number.isFinite(scale) && scale >= 0.1 && scale <= 4) {
                controller.setSpriteScale(sprite.name, scale);
              }
            }}
            style={styles.number}
          />
        </label>
      ))}
      <div style={styles.note}>{info.said || "tap a tile; long press or right click inspects"}</div>
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  page: { position: "fixed", inset: 0 },
  root: { position: "absolute", inset: 0, overflow: "hidden", background: "#0b0b0e" },
  canvas: { position: "absolute", inset: 0, touchAction: "none" },
  centrePlace: { position: "absolute", right: 16, bottom: 16 },
  centre: {
    width: 48,
    height: 48,
    borderRadius: 24,
    fontSize: "1.375rem",
    border: "none",
    background: "rgba(255,255,255,0.85)",
  },
  /** The debug toggle: today's look, at least 44 px tall (design/11 I-6; CLI-03i). */
  toggle: {
    position: "absolute",
    left: 8,
    top: 8,
    minHeight: 44,
    font: "0.75rem system-ui",
    padding: "4px 8px",
    border: "none",
    borderRadius: 4,
    background: "rgba(255,255,255,0.75)",
  },
  /**
   * With the pack's chrome, the debug controls say they are not game controls: red, dashed, never
   * the pack's look (CLI-03i *What stays plain*).
   */
  debugLook: {
    background: "rgba(80,0,0,0.75)",
    color: "#ffb4b4",
    border: "1px dashed #ff6b6b",
    font: "0.75rem ui-monospace, monospace",
  },
  debugFrame: { border: "1px dashed #ff6b6b" },
  panel: {
    position: "absolute",
    left: 8,
    top: 60,
    width: 260,
    maxHeight: "70vh",
    overflowY: "auto",
    padding: 8,
    borderRadius: 6,
    font: "0.75rem system-ui",
    color: "#eee",
    background: "rgba(0,0,0,0.78)",
  },
  walk: {
    position: "absolute",
    left: "50%",
    bottom: 16,
    transform: "translateX(-50%)",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 4,
    font: "0.875rem system-ui",
    pointerEvents: "none",
  },
  counter: {
    pointerEvents: "auto",
    minHeight: 44,
    padding: "0 14px",
    borderRadius: 22,
    border: "none",
    font: "0.875rem system-ui",
    background: "rgba(255,255,255,0.88)",
  },
  stopped: {
    padding: "2px 8px",
    borderRadius: 4,
    color: "#eee",
    background: "rgba(0,0,0,0.6)",
  },
  row: { display: "block", margin: "4px 0" },
  note: { margin: "4px 0", color: "#aaa" },
  number: { width: 56 },
};
