import { type CSSProperties, useEffect, useRef, useState } from "react";
import type { ZoomSettings } from "../render/renderer";
import { SandboxController, type SandboxInfo } from "./controller";
import { FIXTURES } from "./fixtures";
import { ACROSS_RANGE, readAcross, readParams } from "./params";

/**
 * The rendering sandbox (CLI-03a): the map on the whole viewport, a button back to the adventurer,
 * and a debug panel. URL parameters: see `params.ts`.
 */
export function Sandbox() {
  const host = useRef<HTMLDivElement>(null);
  const [controller, setController] = useState<SandboxController | null>(null);
  const [panelOpen, setPanelOpen] = useState(() => readParams(window.location.search).panel);
  const [info, setInfo] = useState<SandboxInfo | null>(null);

  useEffect(() => {
    const element = host.current;
    if (!element) return;
    let alive = true;
    let mounted: SandboxController | null = null;
    SandboxController.mount(element, readParams(window.location.search))
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
  }, []);

  useEffect(() => {
    if (!controller) return;
    controller.listen(panelOpen ? setInfo : null);
    return () => controller.listen(null);
  }, [controller, panelOpen]);

  return (
    <div style={styles.root}>
      <div ref={host} style={styles.canvas} />
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
      {panelOpen && controller && info && <DebugPanel controller={controller} info={info} />}
    </div>
  );
}

function DebugPanel({ controller, info }: { controller: SandboxController; info: SandboxInfo }) {
  const zoom = info.zoom;
  const setZoom = (patch: Partial<ZoomSettings>) => controller.setZoom({ ...zoom, ...patch });
  return (
    <div style={styles.panel}>
      <label style={styles.row}>
        fixture{" "}
        <select value={info.fixture} onChange={(e) => controller.setFixture(e.target.value)}>
          {Object.keys(FIXTURES).map((name) => (
            <option key={name}>{name}</option>
          ))}
        </select>
      </label>
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
        <input
          type="checkbox"
          checked={info.snap}
          onChange={(e) => controller.setSnap(e.target.checked)}
        />{" "}
        integer scale (ADR-0003)
      </label>
      <div style={styles.row}>
        tile width <b>{info.zoomInfo.tileWidth.toFixed(1)}</b> CSS px (I-6: 40), tiles across{" "}
        <b>{info.zoomInfo.across.toFixed(1)}</b>
      </div>
      <div style={styles.row}>
        device px per art px <b>{info.zoomInfo.deviceScale.toFixed(3)}</b> (CSS{" "}
        {info.zoomInfo.scale.toFixed(3)})
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
      <div style={styles.row}>
        atlas: <b>{info.atlas}</b>
      </div>
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
  root: { position: "fixed", inset: 0, overflow: "hidden", background: "#0b0b0e" },
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
  row: { display: "block", margin: "4px 0" },
  note: { margin: "4px 0", color: "#aaa" },
  number: { width: 56 },
};
