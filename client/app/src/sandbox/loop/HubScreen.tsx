import { type CSSProperties, useEffect, useRef, useState } from "react";
import type { Application } from "pixi.js";
import type { LoopIntent } from "../../input/intent";
import {
  type Size,
  figureIntent,
  figureRect,
  hubFit,
  placeRect,
  targetIntent,
} from "../../input/hubTaps";
import { loadAtlas } from "../../render/atlas";
import { HubRenderer } from "../../render/hubRenderer";
import { type HubView, targetLabel } from "../../render/hubView";
import { createPixiSurface, pixiTickersRunning } from "../../render/pixiSurface";
import type { ScaleMode } from "../../render/scaling";
import { browserHost } from "../../render/scheduler";
import { ui } from "./styles";

/**
 * A hub (design/11 *Hubs*): its name and the gold at the top, the illustration in the middle, the
 * services below. Every building, service entry and present adventurer is a button whose tap is
 * an intent (`input/hubTaps.ts`); the illustration is drawn on demand by `HubRenderer`.
 */
export function HubScreen({
  view,
  inspected,
  scale,
  dispatch,
}: {
  view: HubView;
  inspected: number | null;
  scale: ScaleMode;
  dispatch: (intent: LoopIntent) => void;
}) {
  const figure = view.figures.find((f) => f.id === inspected) ?? null;
  return (
    <div style={ui.screen} data-screen="hub" data-hub={view.name}>
      <header style={ui.header}>
        <span style={ui.title}>{view.name}</span>
        <span style={ui.gold}>gold {view.gold.toLocaleString("en-GB").replace(",", " ")}</span>
      </header>
      <Illustration view={view} scale={scale} dispatch={dispatch} />
      {figure && (
        <div style={styles.inspect} role="dialog" aria-label="Adventurer">
          <span>
            <b>{figure.name}</b> · {figure.profession}, level {figure.level}
          </span>
          <button
            style={{ ...ui.button, ...ui.quiet }}
            onClick={() => dispatch({ kind: "back" })}
            aria-label="Close"
          >
            ✕
          </button>
        </div>
      )}
      <nav style={ui.grid} aria-label="Services">
        {view.services.map((target) => (
          <button
            key={targetLabel(target)}
            style={{ ...ui.button, ...(target.kind === "gate" ? ui.primary : {}) }}
            onClick={() => dispatch(targetIntent(target))}
          >
            {targetLabel(target)}
            {target.kind === "gate" ? " ▸" : ""}
          </button>
        ))}
      </nav>
    </div>
  );
}

/** The illustration: a canvas drawn by `HubRenderer`, under one button per place and figure. */
function Illustration({
  view,
  scale,
  dispatch,
}: {
  view: HubView;
  scale: ScaleMode;
  dispatch: (intent: LoopIntent) => void;
}) {
  const host = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState<Size | null>(null);
  const [renderer, setRenderer] = useState<HubRenderer | null>(null);
  const [atlas, setAtlas] = useState<"loading" | "loaded" | "none" | "failed">("loading");

  useEffect(() => {
    const element = host.current;
    if (!element) return;
    let alive = true;
    let app: Application | null = null;
    let mounted: HubRenderer | null = null;
    let observer: ResizeObserver | null = null;
    createPixiSurface(element, scale)
      .then(({ app: created, surface }) => {
        app = created;
        if (!alive) return created.destroy(true);
        mounted = new HubRenderer(surface, browserHost(), {
          // For the browser check (AC-6): frames drawn, read from the page; no React render.
          onDraw: (stats) => {
            element.dataset.frames = String(stats.renders);
            element.dataset.tickers = String(pixiTickersRunning(created));
          },
        });
        const resize = () => {
          const zone = { width: element.clientWidth || 1, height: element.clientHeight || 1 };
          created.renderer.resize(zone.width, zone.height);
          mounted?.resize(zone);
          setSize(zone);
        };
        resize();
        observer = new ResizeObserver(resize);
        observer.observe(element);
        setRenderer(mounted);
        return loadAtlas().then((library) => {
          if (!alive) return;
          setAtlas(library ? "loaded" : "none");
          if (library) mounted?.setLibrary(library);
        });
      })
      .catch((error: unknown) => {
        setAtlas("failed");
        console.error("[hub] could not start the renderer", error);
      });
    return () => {
      alive = false;
      observer?.disconnect();
      mounted?.destroy();
      app?.destroy(true);
    };
  }, [scale]);

  useEffect(() => {
    renderer?.setView(view);
  }, [renderer, view]);

  const fit = size ? hubFit(view, size) : null;
  return (
    <div style={styles.illustration}>
      <div ref={host} style={styles.canvas} data-atlas={atlas} />
      {fit &&
        view.places.map((place) => {
          const rect = placeRect(place, fit);
          const shape = atlas !== "loaded" || !renderer?.drawnFromAtlas(place);
          return (
            <button
              key={place.id}
              style={{ ...styles.place, ...rect }}
              onClick={() => dispatch(targetIntent(place.target))}
              aria-label={`${place.label} building`}
            >
              <span style={shape ? styles.shapeLabel : styles.spriteLabel}>{place.label}</span>
            </button>
          );
        })}
      {fit &&
        view.figures.map((figure) => (
          <button
            key={figure.id}
            style={{ ...styles.figure, ...figureRect(figure, fit) }}
            onClick={() => dispatch(figureIntent(figure))}
            aria-label={`Adventurer ${figure.name}`}
          />
        ))}
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  illustration: { position: "relative", flex: 1, minHeight: 0, overflow: "hidden" },
  canvas: { position: "absolute", inset: 0 },
  place: {
    position: "absolute",
    display: "flex",
    alignItems: "flex-end",
    justifyContent: "center",
    padding: 0,
    border: "none",
    background: "transparent",
    cursor: "pointer",
  },
  shapeLabel: {
    marginBottom: 2,
    padding: "1px 6px",
    borderRadius: 4,
    font: "12px system-ui",
    color: "#111",
    background: "rgba(255,255,255,0.85)",
  },
  spriteLabel: {
    marginBottom: -14,
    padding: "1px 6px",
    borderRadius: 4,
    font: "12px system-ui",
    color: "#eee",
    background: "rgba(0,0,0,0.55)",
  },
  figure: {
    position: "absolute",
    padding: 0,
    border: "none",
    background: "transparent",
    cursor: "pointer",
  },
  inspect: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
    padding: "4px 12px",
    background: "#1b1b22",
    borderTop: "1px solid #2a2a33",
  },
};
