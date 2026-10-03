import {
  type CSSProperties,
  type ReactNode,
  useCallback,
  useEffect,
  useReducer,
  useState,
} from "react";
import { ChromeProvider, Panel, Text } from "../../chrome/Chrome";
import { HUB_VIEWS } from "../fixtures/hubs";
import { gateOf } from "../fixtures/region";
import { EntryScreen, GateScreen, ReportScreen, ServiceScreen, SheetSummary } from "./screens";
import { HubScreen } from "./HubScreen";
import { InstanceScreen } from "./InstanceScreen";
import {
  type LoopEvent,
  type LoopState,
  gateHere,
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
export function Loop({ hub, entryMs }: { hub: number; entryMs: number }) {
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
        <HubScreen
          view={view}
          inspected={screen.inspected}
          at={screen.at}
          dispatch={dispatch}
          onMoved={moved}
        />
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
          gateHere={gateHere(model.state)}
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
      <ChromeProvider style={styles.page} data-layout="phone">
        {content}
      </ChromeProvider>
    );
  }
  return (
    <ChromeProvider style={{ ...styles.page, ...styles.desktop }} data-layout="desktop">
      <Panel
        variant="dark"
        as="aside"
        className="gw-side"
        plain={styles.panel}
        style={styles.panelPlace}
        aria-label="Character sheet and build"
      >
        <SheetSummary />
        <Text tone="caption" plain={ui.label}>
          Last hub visited
        </Text>
        <div>{hubName(model.state.lastHub)}</div>
      </Panel>
      <main style={styles.column}>{content}</main>
      <Panel
        variant="dark"
        as="aside"
        className="gw-side"
        plain={styles.panel}
        style={styles.panelPlace}
        aria-label="Log"
      >
        <Text tone="caption" plain={ui.label}>
          Log
        </Text>
        {model.log.map((line, i) => (
          <Text
            key={i}
            tone="muted"
            plain={{ ...ui.muted, fontSize: "0.8125rem", margin: "2px 0" }}
          >
            {line}
          </Text>
        ))}
      </Panel>
    </ChromeProvider>
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
    font: "0.9375rem system-ui",
  },
  desktop: { display: "flex", justifyContent: "center" },
  column: {
    position: "relative",
    flex: `0 1 ${COLUMN_WIDTH}px`,
    height: "100%",
    borderLeft: "1px solid #2a2a33",
    borderRight: "1px solid #2a2a33",
  },
  panelPlace: { flex: "0 1 280px", overflowY: "auto" },
  panel: { padding: 16 },
};
