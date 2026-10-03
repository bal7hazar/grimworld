import { type CSSProperties, useCallback, useEffect, useRef, useState } from "react";
import { Button, Icon, IconButton, Panel, Ribbon } from "../../chrome/Chrome";
import { targetIntent } from "../../input/hubTaps";
import type { Intent, LoopIntent } from "../../input/intent";
import { type HubView, targetLabel } from "../../render/hubView";
import { browserHost } from "../../render/scheduler";
import type { Tile } from "../../render/view";
import type { SandboxController } from "../controller";
import { hubWorld } from "../fixtures/hubWorld";
import { readParams } from "../params";
import { RoomSandbox } from "../Sandbox";
import type { WalkInfo } from "../session";
import { HubDoors } from "./hubDoors";
import { ui } from "./styles";

/**
 * A hub (design/11 *Hubs*), lived like an exploration zone (CLI-03f, D-196, D-202): its name and
 * the gold at the top, the zone's map in the middle (`RoomSandbox` on `hubWorld`: the same camera,
 * zoom, pathfinding, step and rendering), the services below. A tap on a building walks to its door
 * and opens the place (`HubDoors`); the service row opens a place at once. The adventurer starts on
 * `at`, the machine's hex, and each change is answered to the machine through `onMoved`. The
 * places' names follow the camera; they take no tap.
 */
export function HubScreen({
  view,
  inspected,
  at,
  dispatch,
  onMoved,
}: {
  view: HubView;
  inspected: number | null;
  at: Tile;
  dispatch: (intent: LoopIntent) => void;
  onMoved: (tile: Tile) => void;
}) {
  const figure = view.figures.find((f) => f.id === inspected) ?? null;
  // The room opens once on the hex the screen opened on; the walk owns the hex afterwards.
  const [world] = useState(() => hubWorld(view, at));
  const standing = useRef<Tile | null>(at);
  const send = useRef(dispatch);
  send.current = dispatch;
  const [doors] = useState(
    () =>
      new HubDoors(
        view,
        (intent) => send.current(intent),
        () => standing.current,
        browserHost(),
        // The place opens once the walk's last step is drawn: the room's step duration.
        readParams(window.location.search).stepMs,
        (line) => console.debug("[hub]", line),
      ),
  );
  useEffect(() => () => doors.destroy(), [doors]);

  const route = useCallback((intent: Intent) => doors.route(intent), [doors]);
  const moved = useCallback(
    (tile: Tile | null, walk: WalkInfo) => {
      standing.current = tile;
      if (tile) onMoved(tile);
      doors.changed(tile, walk);
    },
    [doors, onMoved],
  );

  const labels = useRef(new Map<string, HTMLElement>());
  const place = useCallback(
    (controller: SandboxController) => {
      const scale = controller.scale();
      for (const p of view.places) {
        const element = labels.current.get(p.id);
        if (!element) continue;
        const base = controller.tileOnScreen(p.at);
        element.style.transform = `translate(${base.x}px, ${base.y - p.height * scale}px) translate(-50%, -100%)`;
        element.style.visibility = "visible";
        const atlas = controller.structureFromAtlas(`place:${p.id}`);
        if (atlas === false) element.dataset.shape = "";
        else delete element.dataset.shape;
      }
    },
    [view],
  );

  return (
    <div style={ui.screen} data-screen="hub" data-hub={view.name}>
      <header style={ui.header}>
        <Ribbon colour="blue" size="big" plain={ui.title}>
          {view.name}
        </Ribbon>
        <span style={ui.gold}>
          <Icon name="gold" text="gold" /> {view.gold.toLocaleString("en-GB").replace(",", " ")}
        </span>
      </header>
      <div style={styles.map}>
        <RoomSandbox world={world} route={route} onTile={moved} onFrame={place}>
          {view.places.map((p) => (
            <Ribbon
              key={p.id}
              as="div"
              colour="yellow"
              size="small"
              ref={(element: HTMLElement | null) => {
                if (element) labels.current.set(p.id, element);
                else labels.current.delete(p.id);
              }}
              plain={styles.label}
              style={styles.labelPlace}
              data-label={p.label}
            >
              {p.label}
            </Ribbon>
          ))}
          {figure && (
            <Panel
              variant="scroll"
              plain={styles.inspect}
              style={styles.inspectPlace}
              role="dialog"
              aria-label="Adventurer"
            >
              <span>
                <b>{figure.name}</b> · {figure.profession}, level {figure.level}
              </span>
              <IconButton
                icon="close"
                label="Close"
                plain={{ ...ui.button, ...ui.quiet }}
                plainText="✕"
                onClick={() => dispatch({ kind: "back" })}
              />
            </Panel>
          )}
        </RoomSandbox>
      </div>
      <Panel
        variant="wood"
        as="nav"
        className="gw-service-row"
        plain={ui.grid}
        aria-label="Services"
      >
        {view.services.map((target) => (
          <Button
            key={targetLabel(target)}
            variant={target.kind === "gate" ? "commit" : "action"}
            plain={{ ...ui.button, ...(target.kind === "gate" ? ui.primary : {}) }}
            onClick={() => dispatch(targetIntent(target))}
          >
            {targetLabel(target)}
            {target.kind === "gate" ? " ▸" : ""}
          </Button>
        ))}
      </Panel>
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  map: { position: "relative", flex: 1, minHeight: 0, overflow: "hidden" },
  /**
   * A place's name over its building (CLI-03e §6; on a small yellow ribbon with the art, CLI-03i),
   * placed after each frame from the camera. It takes no tap: a tap on it reaches the map under it.
   */
  labelPlace: {
    position: "absolute",
    left: 0,
    top: 0,
    visibility: "hidden",
    pointerEvents: "none",
  },
  /** Its plate without the art. */
  label: {
    padding: "1px 8px",
    borderRadius: 6,
    font: "600 0.9375rem system-ui",
    lineHeight: "1.25rem",
    whiteSpace: "nowrap",
    color: "#fff",
    background: "rgba(20,20,26,0.82)",
    border: "1px solid rgba(255,255,255,0.18)",
  },
  inspectPlace: {
    position: "absolute",
    left: 8,
    right: 72,
    bottom: 16,
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
  },
  inspect: {
    padding: "4px 12px",
    borderRadius: 8,
    background: "rgba(27,27,34,0.94)",
    border: "1px solid #2a2a33",
  },
};
