import { type CSSProperties, useEffect, useState } from "react";
import { IconButton, Panel, Text } from "../../chrome/Chrome";
import { BINDINGS, type KeyScreen, bindingsOf } from "../../input/keys";
import type { Facing } from "../../render/view";
import { useKeyLayer } from "../keyScope";
import { ui } from "./styles";

/** Each direction's key, read from the one table (`BINDINGS`), not from a second list. */
function ringKeys(): Map<Facing, string> {
  const keys = new Map<Facing, string>();
  for (const binding of BINDINGS) {
    if (binding.matches.length !== 1) continue;
    const command = binding.matches[0]!.command;
    if (command?.kind === "step" && "direction" in command)
      keys.set(command.direction, binding.keys);
  }
  return keys;
}

/** A pointy-top hex's corners around (x, y), radius r. */
function hex(x: number, y: number, r: number): string {
  return Array.from({ length: 6 }, (_, i) => {
    const a = ((60 * i - 30) * Math.PI) / 180;
    return `${(x + r * Math.cos(a)).toFixed(1)},${(y + r * Math.sin(a)).toFixed(1)}`;
  }).join(" ");
}

/**
 * The direction ring: the adventurer's hex and its six around it, each with its key. Direction `d`
 * points `d × 60°` counter-clockwise from the screen's right (`render/facing.ts`).
 */
function Ring() {
  const keys = ringKeys();
  const r = 16;
  const step = r * Math.sqrt(3);
  const centre = 3 * r;
  return (
    <svg
      width={6 * r}
      height={6 * r}
      viewBox={`0 0 ${6 * r} ${6 * r}`}
      role="img"
      aria-label="The six directions and their keys"
      style={styles.ring}
    >
      <polygon points={hex(centre, centre, r - 1)} fill="#f2c94c" />
      {([0, 1, 2, 3, 4, 5] as const).map((d) => {
        const a = (d * Math.PI) / 3;
        const x = centre + step * Math.cos(a);
        const y = centre - step * Math.sin(a);
        return (
          <g key={d}>
            <polygon points={hex(x, y, r - 1)} fill="none" stroke="currentColor" />
            <text x={x} y={y + 5} textAnchor="middle" fontSize="14" fill="currentColor">
              {keys.get(d) ?? ""}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

/**
 * The key help (CLI-03k): the current screen's bindings, from the one table, the reserved ones
 * greyed as "later"; the direction ring where the map moves. `?` or `Esc` closes it; its ✕ takes
 * the focus and gives it back on closing.
 */
export function KeyHelp({ screen, onClose }: { screen: KeyScreen; onClose: () => void }) {
  const [opener] = useState(() => document.activeElement as HTMLElement | null);
  useEffect(
    () => () => {
      if (opener?.isConnected) opener.focus({ preventScroll: true });
    },
    [opener],
  );
  // `?` is toggled by the loop before this layer; `Esc` closes; the screen's keys are inert.
  useKeyLayer(screen, (command) => {
    if (command?.kind !== "escape") return false;
    onClose();
    return true;
  });
  const rows = bindingsOf(screen);
  const map = screen === "hub" || screen === "instance";
  return (
    <div style={styles.scrim}>
      <Panel
        variant="scroll"
        plain={{ ...ui.card, ...styles.plain }}
        style={styles.panel}
        role="dialog"
        aria-label="Keys"
        data-key-help={screen}
      >
        <div style={ui.row}>
          <Text tone="caption" plain={ui.label}>
            Keys
          </Text>
          <IconButton
            icon="close"
            label="Close the keys"
            plain={{ ...ui.button, ...ui.quiet }}
            plainText="✕"
            onClick={onClose}
            autoFocus
          />
        </div>
        {map && <Ring />}
        <table style={styles.table}>
          <tbody>
            {rows.map((b) => (
              <tr
                key={`${b.keys} ${b.label}`}
                data-binding={b.keys}
                style={b.reserved ? styles.reserved : undefined}
              >
                <th scope="row" style={styles.keys}>
                  {b.keys}
                </th>
                <td>
                  {b.label}
                  {b.reserved ? " (later)" : ""}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Panel>
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  scrim: {
    position: "fixed",
    inset: 0,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    padding: 16,
    background: "rgba(0,0,0,0.55)",
    zIndex: 10,
  },
  panel: { width: "min(420px, 100%)", maxHeight: "90vh", overflowY: "auto" },
  plain: { color: "#eee" },
  ring: { display: "block", margin: "4px auto 8px" },
  table: { width: "100%", borderCollapse: "collapse", lineHeight: 1.6 },
  keys: { textAlign: "left", whiteSpace: "nowrap", paddingRight: 12, fontWeight: 600 },
  reserved: { opacity: 0.5 },
};
