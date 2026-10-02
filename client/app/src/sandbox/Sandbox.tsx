import { type CSSProperties, type ReactNode, useEffect, useRef, useState } from "react";
import type { Intent } from "../input/intent";
import type { ZoomSettings } from "../render/renderer";
import { SCALE_MODES, readScaleMode } from "../render/scaling";
import type { Tile } from "../render/view";
import { SandboxController, type SandboxInfo } from "./controller";
import { FIXTURES } from "./fixtures";
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

/**
 * The rendering sandbox (CLI-03a): the map on the whole of its box, a button back to the
 * adventurer, and a debug panel. In the loop it opens on `world` (the instance, or a hub lived like
 * a zone, CLI-03f), reports where the adventurer stands and how its walk goes after every change
 * (`onTile`), and carries the loop's controls (`children`) over the map. A hub's screen also routes
 * the map's intents before the session (`route`) and places its labels after each frame drawn
 * (`onFrame`). A hub shows no walk counter: a hub has no tick.
 *
 * For the browser check: the root's `data-frames` (frames drawn), `data-tile` (where the
 * adventurer stands) and `data-walking`.
 */
export function RoomSandbox({
  world,
  onTile,
  route,
  onFrame,
  children,
}: {
  world?: SandboxWorld;
  onTile?: (tile: Tile | null, walk: WalkInfo) => void;
  route?: (intent: Intent) => Intent | null;
  onFrame?: (controller: SandboxController) => void;
  children?: ReactNode;
} = {}) {
  const root = useRef<HTMLDivElement>(null);
  const host = useRef<HTMLDivElement>(null);
  const [controller, setController] = useState<SandboxController | null>(null);
  const [panelOpen, setPanelOpen] = useState(() => readParams(window.location.search).panel);
  const [info, setInfo] = useState<SandboxInfo | null>(null);
  const [walk, setWalk] = useState<WalkInfo | null>(null);
  const tileListener = useRef(onTile);
  tileListener.current = onTile;
  const router = useRef(route);
  router.current = route;
  const frameListener = useRef(onFrame);
  frameListener.current = onFrame;
  const hub = world?.kind === "hub";

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
      }
      frameListener.current?.(controller);
    });
    return () => controller.listenToFrames(null);
  }, [controller]);

  return (
    <div ref={root} style={styles.root}>
      <div ref={host} style={styles.canvas} />
      {controller && walk && !hub && <WalkCounter controller={controller} walk={walk} />}
      <button
        style={styles.centre}
        onClick={() => controller?.recentre()}
        aria-label="Back to the adventurer"
      >
        ◎
      </button>
      <button style={styles.toggle} onClick={() => setPanelOpen((open) => !open)}>
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
  if (walk.steps === 0 && !walk.stopped) return null;
  return (
    <div style={styles.walk}>
      {walk.steps > 0 && (
        <button
          style={styles.counter}
          onClick={() => controller.cancelWalk()}
          aria-label="Cancel the planned path"
        >
          {walk.walking ? "▶" : "◌"} {walk.steps} {walk.steps === 1 ? "step" : "steps"} ·{" "}
          {walk.cost} {walk.cost === 1 ? "tick" : "ticks"} ✕
        </button>
      )}
      {walk.steps > 0 && !walk.walking && (
        <div style={styles.stopped}>tap the tile again to walk</div>
      )}
      {walk.stopped && <div style={styles.stopped}>{walk.stopped}</div>}
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
  const zoom = info.zoom;
  const setZoom = (patch: Partial<ZoomSettings>) => controller.setZoom({ ...zoom, ...patch });
  return (
    <div style={styles.panel}>
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
  centre: {
    position: "absolute",
    right: 16,
    bottom: 16,
    width: 48,
    height: 48,
    borderRadius: 24,
    fontSize: 22,
    border: "none",
    background: "rgba(255,255,255,0.85)",
  },
  toggle: {
    position: "absolute",
    left: 8,
    top: 8,
    font: "12px system-ui",
    padding: "4px 8px",
    border: "none",
    borderRadius: 4,
    background: "rgba(255,255,255,0.75)",
  },
  panel: {
    position: "absolute",
    left: 8,
    top: 36,
    width: 260,
    maxHeight: "70vh",
    overflowY: "auto",
    padding: 8,
    borderRadius: 6,
    font: "12px system-ui",
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
    font: "14px system-ui",
    pointerEvents: "none",
  },
  counter: {
    pointerEvents: "auto",
    minHeight: 44,
    padding: "0 14px",
    borderRadius: 22,
    border: "none",
    font: "14px system-ui",
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
