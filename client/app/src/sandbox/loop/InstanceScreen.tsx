import { type CSSProperties, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Button, Panel } from "../../chrome/Chrome";
import type { LoopIntent } from "../../input/intent";
import type { KeyCommand, KeyLike } from "../../input/keys";
import type { Tile } from "../../render/view";
import type { SandboxController } from "../controller";
import { type GateRecord, globalTile, locationOf } from "../fixtures/region";
import { zoneWorld } from "../fixtures/zone";
import { keyUi, offScreen, useKeyLayer, useScreenFocus } from "../keyScope";
import { type MapKeys, RoomSandbox } from "../Sandbox";
import { goIntent, leaveAsked, nextTarget, zoneTargets } from "./keyTargets";
import { hubName, leaveQuestion } from "./machine";
import { ui } from "./styles";

type Asking = { kind: "leave"; gate: GateRecord } | { kind: "travel back" };

/** A hub gate's anchor, as its record gives it. */
const anchorOf = (gate: GateRecord) => globalTile(gate.anchor_chunk, gate.anchor_tile);

/**
 * The instance: CLI-03a's room on the entry chunk of the gate's destination, its renderer and input
 * unchanged, with the three ways out (CLI-03c): leaving by a hub gate the adventurer stands on
 * (D-148), travelling back, and a debug defeat. Leaving and travelling back are asked twice
 * (design/11 I-5): the offer or the button, then a confirmation.
 *
 * By keys (CLI-03k): `F` / `Shift+F` select the location's hub gates (a ring on the anchor),
 * `Enter` taps the anchor, `L` is the Leave control (on an anchor only), `Esc` cancels the walk,
 * then clears the selection. The confirmation opens with Stay focused and keeps the focus inside
 * it; leaving takes `Tab` then `Enter`. No key for Travel back.
 */
export function InstanceScreen({
  location,
  entry,
  offer,
  gateHere,
  dispatch,
  onMoved,
}: {
  location: number;
  entry: Tile;
  /** The hub gate to offer on its own: on its anchor after leaving one (the machine's `leaveOffer`). */
  offer: GateRecord | null;
  /** The hub gate under the adventurer, if any, at arrival too (the machine's `gateHere`). */
  gateHere: GateRecord | null;
  dispatch: (intent: LoopIntent) => void;
  onMoved: (tile: Tile) => void;
}) {
  const world = useMemo(() => zoneWorld(entry, locationOf(location)), [entry, location]);
  const [asking, setAsking] = useState<Asking | null>(null);
  const offerOpen = offer !== null;
  const root = useScreenFocus();
  const targets = useMemo(() => zoneTargets(location, anchorOf), [location]);
  const [selected, setSelected] = useState<number | null>(null);
  const chosen = selected === null ? null : (targets[selected] ?? null);
  const chosenRef = useRef(chosen);
  chosenRef.current = chosen;
  const marker = useRef<HTMLDivElement>(null);
  const shown = useRef<SandboxController | null>(null);

  const place = useCallback((controller: SandboxController) => {
    shown.current = controller;
    const element = marker.current;
    if (!element) return;
    const target = chosenRef.current;
    if (target) {
      const at = controller.tileOnScreen(target.tile);
      element.style.transform = `translate(${at.x}px, ${at.y}px) translate(-50%, -50%)`;
      element.style.width = element.style.height = `${44 * controller.scale()}px`;
    }
    element.style.visibility = target ? "visible" : "hidden";
  }, []);
  useEffect(() => {
    if (shown.current) place(shown.current);
  }, [chosen, place]);

  const onKey = (command: KeyCommand, map: MapKeys): boolean => {
    switch (command.kind) {
      case "step":
        setSelected(null);
        return map.handle(command);
      case "cycle": {
        const next = nextTarget(targets.length, selected, command.by);
        setSelected(next);
        const target = next === null ? null : targets[next];
        if (target && map.controller && offScreen(map.controller, target.tile, root.current)) {
          map.controller.lookAt(target.tile);
        }
        return true;
      }
      case "go":
        if (!chosen || !map.controller) return false;
        map.controller.apply(goIntent(chosen.tile));
        return true;
      case "leave": {
        const ask = leaveAsked(gateHere);
        if (ask) setAsking(ask);
        return ask !== null;
      }
      case "escape":
        if (map.handle(command)) return true;
        if (selected === null) return false;
        setSelected(null);
        return true;
      default:
        return map.handle(command);
    }
  };

  return (
    <div ref={root} tabIndex={-1} style={{ ...ui.screen, ...keyUi.root }} data-screen="instance">
      <RoomSandbox
        world={world}
        onTile={(tile) => tile && onMoved(tile)}
        onFrame={place}
        onKey={onKey}
      >
        <div ref={marker} className="gw-key-marker" style={keyUi.marker} aria-hidden />
        <div style={styles.top}>
          {offerOpen && (
            <Button
              variant="action"
              plain={{ ...ui.button, ...ui.primary }}
              onClick={() => setAsking({ kind: "leave", gate: offer })}
              aria-label="Leave by this gate"
            >
              Gate to {hubName(offer.destination)} · Leave ▸
            </Button>
          )}
        </div>
        <div style={styles.right}>
          <Button
            variant="action"
            plain={{ ...ui.button, ...ui.quiet, opacity: gateHere === null ? 0.4 : 1 }}
            disabled={gateHere === null}
            onClick={() => gateHere && setAsking({ kind: "leave", gate: gateHere })}
            aria-label="Leave"
          >
            Leave
          </Button>
          <Button
            variant="action"
            plain={ui.button}
            onClick={() => setAsking({ kind: "travel back" })}
          >
            Travel back
          </Button>
          <button
            style={{ ...ui.button, ...ui.debug }}
            onClick={() => dispatch({ kind: "defeat now" })}
            title="A debug control of the sandbox: health reaches 0 now"
          >
            debug: defeat now
          </button>
        </div>
        {asking && (
          <Confirm
            asking={asking}
            stay={() => setAsking(null)}
            confirm={() => {
              setAsking(null);
              dispatch(
                asking.kind === "leave"
                  ? { kind: "leave", gate: asking.gate.id }
                  : { kind: "travel back" },
              );
            }}
          />
        )}
      </RoomSandbox>
      <span style={keyUi.hidden} aria-live="polite" data-key-live="">
        {chosen ? `Gate to ${hubName(chosen.gate.destination)} selected, Enter to go` : ""}
      </span>
    </div>
  );
}

/**
 * The confirmation (design/11 I-5): Stay focused on opening, `Tab` / `Shift+Tab` kept inside its
 * two buttons, `Esc` is Stay, `Enter` presses the focused button; the map's keys are inert under
 * it. On closing, the focus goes back where it was when it opened.
 */
function Confirm({
  asking,
  stay,
  confirm,
}: {
  asking: Asking;
  stay: () => void;
  confirm: () => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  // Read on the first render, before Stay takes the focus.
  const [opener] = useState(() => document.activeElement as HTMLElement | null);
  useEffect(() => {
    // Stay, the first button, takes the focus (again after a remount: the cleanup gives it back).
    box.current?.querySelector("button")?.focus();
    return () => {
      if (opener?.isConnected && !(opener as HTMLButtonElement).disabled) opener.focus();
      else (document.querySelector('[data-screen="instance"]') as HTMLElement | null)?.focus();
    };
  }, [opener]);
  useKeyLayer("instance", (command: KeyCommand | null, event: KeyLike) => {
    if (command?.kind === "escape") {
      stay();
      return true;
    }
    if (event.code !== "Tab") return false;
    const buttons = [...(box.current?.querySelectorAll("button") ?? [])];
    if (buttons.length === 0) return false;
    const at = buttons.indexOf(document.activeElement as HTMLButtonElement);
    const by = event.shiftKey ? -1 : 1;
    const next = at < 0 ? 0 : (at + by + buttons.length) % buttons.length;
    buttons[next]?.focus();
    return true;
  });
  return (
    <div ref={box} style={styles.scrim} role="dialog" aria-label="Confirm" aria-modal="true">
      <Panel variant="scroll" plain={ui.card} style={{ maxWidth: 320 }}>
        <p style={{ marginTop: 0 }}>
          {leaveQuestion(asking.kind === "leave" ? asking.gate : null)}
        </p>
        <div style={{ ...ui.row, flexWrap: "wrap" }}>
          <Button variant="quiet" plain={{ ...ui.button, ...ui.quiet }} onClick={stay}>
            Stay
          </Button>
          <Button variant="commit" plain={{ ...ui.button, ...ui.primary }} onClick={confirm}>
            {asking.kind === "leave" ? "Leave" : "Travel back"}
          </Button>
        </div>
      </Panel>
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  top: {
    position: "absolute",
    bottom: 76,
    left: "50%",
    transform: "translateX(-50%)",
    display: "flex",
    gap: 8,
  },
  right: {
    position: "absolute",
    top: 8,
    right: 8,
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-end",
    gap: 8,
  },
  scrim: {
    position: "absolute",
    inset: 0,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    padding: 16,
    background: "rgba(0,0,0,0.55)",
  },
};
