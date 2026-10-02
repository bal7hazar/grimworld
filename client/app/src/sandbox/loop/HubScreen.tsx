import {
  type CSSProperties,
  type ReactNode,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
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
import { type ScaleMode, canvasResolution } from "../../render/scaling";
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
      <Illustration view={view} scale={scale} dispatch={dispatch}>
        {/* Over the illustration's foot, so that opening it moves no tap target. */}
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
      </Illustration>
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
  children,
}: {
  view: HubView;
  scale: ScaleMode;
  dispatch: (intent: LoopIntent) => void;
  children?: ReactNode;
}) {
  const host = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState<Size | null>(null);
  const [drawn, setDrawn] = useState<{ app: Application; renderer: HubRenderer } | null>(null);
  const [atlas, setAtlas] = useState<"loading" | "loaded" | "none" | "failed">("loading");
  const renderer = drawn?.renderer ?? null;

  // The zone's size, before the first paint and on every change: the tap targets need no canvas.
  useLayoutEffect(() => {
    const element = host.current;
    if (!element) return;
    const measure = () =>
      setSize({ width: element.clientWidth || 1, height: element.clientHeight || 1 });
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const element = host.current;
    if (!element) return;
    let alive = true;
    let app: Application | null = null;
    let mounted: HubRenderer | null = null;
    createPixiSurface(element, scale)
      .then(({ app: created, surface }) => {
        app = created;
        if (!alive) return created.destroy(true);
        mounted = new HubRenderer(surface, browserHost(), {
          mode: scale,
          // For the browser check (AC-6): frames drawn, read from the page; no React render.
          onDraw: (stats) => {
            element.dataset.frames = String(stats.renders);
            element.dataset.tickers = String(pixiTickersRunning(created));
          },
        });
        setDrawn({ app: created, renderer: mounted });
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
      setDrawn(null);
      mounted?.destroy();
      app?.destroy(true);
    };
  }, [scale]);

  useEffect(() => {
    if (!drawn || !size) return;
    drawn.app.renderer.resize(size.width, size.height);
    drawn.renderer.resize(size);
  }, [drawn, size]);

  useEffect(() => {
    renderer?.setView(view);
  }, [renderer, view]);

  const resolution = canvasResolution(scale, window.devicePixelRatio);
  const fit = size ? hubFit(view, size, { mode: scale, resolution }) : null;
  return (
    <div style={styles.illustration}>
      <div ref={host} style={styles.canvas} data-atlas={atlas} />
      {fit &&
        view.places.map((place) => {
          const rect = placeRect(view, place, fit);
          const shape = atlas !== "loaded" || !renderer?.drawnFromAtlas(place);
          return (
            <button
              key={place.id}
              style={{ ...styles.place, ...rect }}
              onClick={() => dispatch(targetIntent(place.target))}
              aria-label={`${place.label} building`}
            >
              <span style={styles.label} data-shape={shape ? "" : undefined}>
                {place.label}
              </span>
            </button>
          );
        })}
      {fit &&
        view.figures.map((figure) => (
          <button
            key={figure.id}
            style={{ ...styles.figure, ...figureRect(view, figure, fit) }}
            onClick={() => dispatch(figureIntent(figure))}
            aria-label={`Adventurer ${figure.name}`}
          />
        ))}
      {children}
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
  /**
   * The place's name on a plain plate hanging under its base (CLI-03e §6): the page's body text,
   * light on a dark plate that holds on grass. It takes no tap: a tap on it reaches what is under.
   */
  label: {
    marginBottom: -24,
    padding: "1px 8px",
    borderRadius: 6,
    font: "600 15px system-ui",
    lineHeight: "20px",
    whiteSpace: "nowrap",
    color: "#fff",
    background: "rgba(20,20,26,0.82)",
    border: "1px solid rgba(255,255,255,0.18)",
    pointerEvents: "none",
  },
  figure: {
    position: "absolute",
    padding: 0,
    border: "none",
    background: "transparent",
    cursor: "pointer",
  },
  inspect: {
    position: "absolute",
    left: 8,
    right: 8,
    bottom: 8,
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
    padding: "4px 12px",
    borderRadius: 8,
    background: "rgba(27,27,34,0.94)",
    border: "1px solid #2a2a33",
  },
};
