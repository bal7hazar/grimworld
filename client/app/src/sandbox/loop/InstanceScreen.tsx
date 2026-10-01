import { type CSSProperties, useMemo, useState } from "react";
import type { LoopIntent } from "../../input/intent";
import type { Tile } from "../../render/view";
import { type GateRecord, locationOf } from "../fixtures/region";
import { zoneWorld } from "../fixtures/zone";
import { RoomSandbox } from "../Sandbox";
import { hubName } from "./machine";
import { ui } from "./styles";

/**
 * The instance: CLI-03a's room on the entry chunk of the gate's destination, its renderer and input
 * unchanged, with the three ways out (CLI-03c): leaving by a hub gate the adventurer stands on
 * (D-148), travelling back, and a debug defeat. Leaving and travelling back are asked twice
 * (design/11 I-5): the offer or the button, then a confirmation.
 */
export function InstanceScreen({
  location,
  entry,
  offer,
  dispatch,
  onMoved,
}: {
  location: number;
  entry: Tile;
  /** The hub gate under the adventurer, if any (the machine's `leaveOffer`). */
  offer: GateRecord | null;
  dispatch: (intent: LoopIntent) => void;
  onMoved: (tile: Tile) => void;
}) {
  const world = useMemo(() => zoneWorld(entry, locationOf(location)), [entry, location]);
  const [asking, setAsking] = useState<"leave" | "travel back" | null>(null);
  const offerOpen = offer !== null;
  return (
    <div style={ui.screen} data-screen="instance">
      <RoomSandbox world={world} onTile={(tile) => tile && onMoved(tile)}>
        <div style={styles.top}>
          {offerOpen && (
            <button
              style={{ ...ui.button, ...ui.primary }}
              onClick={() => setAsking("leave")}
              aria-label="Leave by this gate"
            >
              Gate to {hubName(offer.destination)} · Leave ▸
            </button>
          )}
        </div>
        <div style={styles.right}>
          <button style={ui.button} onClick={() => setAsking("travel back")}>
            Travel back
          </button>
          <button
            style={{ ...ui.button, ...ui.debug }}
            onClick={() => dispatch({ kind: "defeat now" })}
            title="A debug control of the sandbox: health reaches 0 now"
          >
            debug: defeat now
          </button>
        </div>
        {asking && (
          <div style={styles.scrim} role="dialog" aria-label="Confirm">
            <div style={{ ...ui.card, maxWidth: 320 }}>
              <p style={{ marginTop: 0 }}>
                {asking === "leave" && offer
                  ? `Leave the instance for ${hubName(offer.destination)}? The goblins will be back next time.`
                  : "Travel back to the last hub visited? The instance closes."}
              </p>
              <div style={ui.row}>
                <button style={{ ...ui.button, ...ui.quiet }} onClick={() => setAsking(null)}>
                  Stay
                </button>
                <button
                  style={{ ...ui.button, ...ui.primary }}
                  onClick={() => {
                    setAsking(null);
                    dispatch(asking === "leave" ? { kind: "leave" } : { kind: "travel back" });
                  }}
                >
                  {asking === "leave" ? "Leave" : "Travel back"}
                </button>
              </div>
            </div>
          </div>
        )}
      </RoomSandbox>
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
