import {
  type CSSProperties,
  type ReactNode,
  useCallback,
  useEffect,
  useReducer,
  useState,
} from "react";
import type { ScaleMode } from "../../render/scaling";
import { HUB_VIEWS } from "../fixtures/hubs";
import { gateOf } from "../fixtures/region";
import { EntryScreen, GateScreen, ReportScreen, ServiceScreen, SheetSummary } from "./screens";
import { HubScreen } from "./HubScreen";
import { InstanceScreen } from "./InstanceScreen";
import {
  type LoopEvent,
  type LoopState,
  hubName,
  hubState,
  leaveOffer,
  locationName,
  step,
} from "./machine";
import { ui } from "./styles";

/** Narrower than this, the phone layout (design/11 *Desktop*). */
export const DESKTOP_MIN_WIDTH = 700;

/** The portrait column's width on a desktop window. */
const COLUMN_WIDTH = 430;

interface LoopModel {
  readonly state: LoopState;
  /** The last lines of what happened, newest last: the desktop's right panel. */
  readonly log: readonly string[];
  /** Instances entered: each is a new room (D-05: a new instance, goblins back). */
  readonly entries: number;
}

function reduce(model: LoopModel, event: LoopEvent): LoopModel {
  const state = step(model.state, event);
  if (state === model.state) return model;
  const entered = state.screen.kind === "instance" && model.state.screen.kind !== "instance";
  const quiet = event.kind === "moved";
  return {
    state,
    log: quiet ? model.log : [...model.log.slice(-40), state.said],
    entries: model.entries + (entered ? 1 : 0),
  };
}

/**
 * The loop on fixed data (CLI-03c): a hub, its services and Gate screen, the entry moment, the
 * instance, the closing report, and back to a hub. Taps become intents; the machine
 * (`machine.ts`) and the fixed data answer them.
 */
export function Loop({ hub, entryMs, scale }: { hub: number; entryMs: number; scale: ScaleMode }) {
  const [model, dispatch] = useReducer(reduce, hub, (h) => ({
    state: hubState(h),
    log: [hubState(h).said],
    entries: 0,
  }));
  const desktop = useWindowWidth() >= DESKTOP_MIN_WIDTH;
  const entryDrawn = useCallback(() => dispatch({ kind: "entry drawn" }), []);
  const moved = useCallback(
    (tile: { x: number; y: number }) => dispatch({ kind: "moved", tile }),
    [],
  );
  const { screen } = model.state;
  // Logged once a line is in the log (not in the reducer, which React may run twice).
  useEffect(() => {
    console.debug("[loop]", model.state.screen.kind, "·", model.log.at(-1));
  }, [model.log, model.state.screen.kind]);

  let content: ReactNode;
  switch (screen.kind) {
    case "hub": {
      const view = HUB_VIEWS.get(screen.hub);
      content = view && (
        <HubScreen view={view} inspected={screen.inspected} scale={scale} dispatch={dispatch} />
      );
      break;
    }
    case "service":
      content = <ServiceScreen hub={screen.hub} service={screen.service} dispatch={dispatch} />;
      break;
    case "gate":
      content = <GateScreen hub={screen.hub} dispatch={dispatch} />;
      break;
    case "entry": {
      const gate = gateOf(screen.gate);
      content = (
        <EntryScreen
          destination={gate ? locationName(gate.destination) : "?"}
          entryMs={entryMs}
          dispatch={dispatch}
          answer={entryDrawn}
        />
      );
      break;
    }
    case "instance":
      content = (
        <InstanceScreen
          key={model.entries}
          location={screen.location}
          entry={screen.entry}
          offer={leaveOffer(model.state)}
          dispatch={dispatch}
          onMoved={moved}
        />
      );
      break;
    case "report":
      content = (
        <ReportScreen
          outcome={screen.outcome}
          how={screen.how}
          hub={screen.hub}
          dispatch={dispatch}
        />
      );
      break;
  }

  if (!desktop) {
    return (
      <div style={styles.page} data-layout="phone">
        {content}
      </div>
    );
  }
  return (
    <div style={{ ...styles.page, ...styles.desktop }} data-layout="desktop">
      <aside style={styles.panel} aria-label="Character sheet and build">
        <SheetSummary />
        <div style={ui.label}>Last hub visited</div>
        <div>{hubName(model.state.lastHub)}</div>
      </aside>
      <main style={styles.column}>{content}</main>
      <aside style={styles.panel} aria-label="Log">
        <div style={ui.label}>Log</div>
        {model.log.map((line, i) => (
          <div key={i} style={{ ...ui.muted, fontSize: 13, margin: "2px 0" }}>
            {line}
          </div>
        ))}
      </aside>
    </div>
  );
}

function useWindowWidth(): number {
  const [width, setWidth] = useState(() => window.innerWidth);
  useEffect(() => {
    const resize = () => setWidth(window.innerWidth);
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);
  return width;
}

const styles: Record<string, CSSProperties> = {
  page: {
    position: "fixed",
    inset: 0,
    background: "#0b0b0e",
    color: "#eee",
    font: "15px system-ui",
  },
  desktop: { display: "flex", justifyContent: "center" },
  column: {
    position: "relative",
    flex: `0 1 ${COLUMN_WIDTH}px`,
    height: "100%",
    borderLeft: "1px solid #2a2a33",
    borderRight: "1px solid #2a2a33",
  },
  panel: { flex: "0 1 280px", padding: 16, overflowY: "auto" },
};
