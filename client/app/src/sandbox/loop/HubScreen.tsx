import {
  type CSSProperties,
  type MouseEvent,
  type ReactNode,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type { Application } from "pixi.js";
import type { Intent, LoopIntent } from "../../input/intent";
import {
  type Size,
  figureIntent,
  figureRect,
  hubFit,
  hubTile,
  placeRect,
  targetIntent,
} from "../../input/hubTaps";
import { HubWalker, type WalkerState, doorAt } from "../../input/hubWalk";
import { loadAtlas } from "../../render/atlas";
import { HubRenderer } from "../../render/hubRenderer";
import { type HubPlace, type HubView, type WalkedHub, targetLabel } from "../../render/hubView";
import type { Tile } from "../../render/view";
import { ADVENTURER } from "../fixtures/hubs";
import { createPixiSurface, pixiTickersRunning } from "../../render/pixiSurface";
import { type ScaleMode, canvasResolution } from "../../render/scaling";
import { browserHost } from "../../render/scheduler";
import { ui } from "./styles";

/** What the hub's taps do with the walk (CLI-03f): the ground walks, a place walks then opens. */
interface Taps {
  /** A tap on the ground: the map's intent, answered by the hub's walk. */
  ground(intent: Intent): void;
  /** A building: walk to its door, then open it. */
  place(place: HubPlace): void;
  /** A service entry or a present adventurer: the walk ends where it stands, the intent at once. */
  now(intent: LoopIntent): void;
}

/**
 * A hub (design/11 *Hubs*): its name and the gold at the top, the illustration in the middle, the
 * services below. Every building, service entry and present adventurer is a button whose tap is
 * an intent (`input/hubTaps.ts`); the illustration is drawn on demand by `HubRenderer`. The
 * player's adventurer walks the hub (CLI-03f, `input/hubWalk.ts`): it starts on `at`, the
 * machine's hex, and each step is answered to the machine through `onStood`.
 */
export function HubScreen({
  view,
  inspected,
  at,
  scale,
  dispatch,
  onStood,
}: {
  view: WalkedHub;
  inspected: number | null;
  at: Tile;
  scale: ScaleMode;
  dispatch: (intent: LoopIntent) => void;
  onStood: (tile: Tile) => void;
}) {
  const figure = view.figures.find((f) => f.id === inspected) ?? null;
  const walker = useRef<HubWalker | null>(null);
  const [walked, setWalked] = useState<WalkerState>({ at, facing: 0, target: null });
  // The hex the screen opened on: the walker starts there once, then the walk owns it.
  const start = useRef(at);

  useEffect(() => {
    let stood = start.current;
    const created = new HubWalker(view, stood, browserHost(), {
      onChange: (state) => {
        setWalked(state);
        if (state.at.x === stood.x && state.at.y === stood.y) return;
        stood = state.at;
        start.current = state.at;
        onStood(state.at);
      },
    });
    walker.current = created;
    setWalked(created.state);
    return () => {
      created.destroy();
      walker.current = null;
    };
  }, [view, onStood]);

  const taps: Taps = {
    ground(intent) {
      if (intent.kind !== "tile") return;
      const { tile } = intent;
      const door = doorAt(view, tile);
      const open = door ? () => dispatch(targetIntent(door.target)) : undefined;
      if (!walker.current?.walkTo(tile, open)) {
        console.debug(`[hub] (${tile.x}, ${tile.y}): not walkable, nothing to do`);
      }
    },
    place(place) {
      const open = () => dispatch(targetIntent(place.target));
      if (walker.current?.walkTo(place.at, open)) return;
      console.warn(`[hub] no walk to the ${place.label}'s door: opened at once`);
      open();
    },
    now(intent) {
      walker.current?.stop();
      dispatch(intent);
    },
  };

  const drawn = useMemo<HubView>(
    () => ({ ...view, walker: { profession: ADVENTURER.profession, ...walked } }),
    [view, walked],
  );
  return (
    <div style={ui.screen} data-screen="hub" data-hub={view.name}>
      <header style={ui.header}>
        <span style={ui.title}>{view.name}</span>
        <span style={ui.gold}>gold {view.gold.toLocaleString("en-GB").replace(",", " ")}</span>
      </header>
      <Illustration view={drawn} walker={walked} scale={scale} taps={taps}>
        {/* Over the illustration's foot, so that opening it moves no tap target. */}
        {figure && (
          <div style={styles.inspect} role="dialog" aria-label="Adventurer">
            <span>
              <b>{figure.name}</b> · {figure.profession}, level {figure.level}
            </span>
            <button
              style={{ ...ui.button, ...ui.quiet }}
              onClick={() => taps.now({ kind: "back" })}
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
            onClick={() => taps.now(targetIntent(target))}
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
  walker,
  scale,
  taps,
  children,
}: {
  view: HubView;
  walker: WalkerState;
  scale: ScaleMode;
  taps: Taps;
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
  // A tap on the ground (the canvas, under the buttons): the hex drawn there.
  const ground = (event: MouseEvent<HTMLDivElement>) => {
    if (!fit) return;
    const box = event.currentTarget.getBoundingClientRect();
    const point = { x: event.clientX - box.left, y: event.clientY - box.top };
    taps.ground({ kind: "tile", tile: hubTile(view, fit, point) });
  };
  return (
    <div style={styles.illustration}>
      <div
        ref={host}
        style={styles.canvas}
        data-atlas={atlas}
        // For the browser check: where the adventurer is, whether it walks, the fit's numbers.
        data-walker={`${walker.at.x},${walker.at.y}`}
        data-walking={walker.target ? "true" : "false"}
        data-fit={fit ? `${fit.scale} ${fit.x} ${fit.y}` : undefined}
        onClick={ground}
      />
      {fit &&
        view.places.map((place) => {
          const rect = placeRect(view, place, fit);
          const shape = atlas !== "loaded" || !renderer?.drawnFromAtlas(place);
          return (
            <button
              key={place.id}
              style={{ ...styles.place, ...rect }}
              onClick={() => taps.place(place)}
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
            onClick={() => taps.now(figureIntent(figure))}
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
