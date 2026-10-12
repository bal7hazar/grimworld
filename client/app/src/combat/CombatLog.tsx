import { type CSSProperties, useLayoutEffect, useRef, useState } from "react";
import { Button, Panel, Text } from "../chrome/Chrome";
import type { LogLine } from "./log";

/**
 * The combat log (CLI-05 brief §7.3). On desktop, the right panel on the paper: the last 12 lines
 * in view, newest last, scrolling back through the rest. On a phone, the last line under the target
 * zone; a tap on it opens a drawer with every line. A predicted line is lighter, a struck one is
 * crossed out, a refusal is muted and in italics; nothing in it speaks of the chain.
 */
export function CombatLogPanel({ lines }: { lines: readonly LogLine[] }) {
  const box = useRef<HTMLOListElement>(null);
  useLayoutEffect(() => {
    const element = box.current;
    if (element) element.scrollTop = element.scrollHeight;
  }, [lines]);
  return (
    <Panel
      variant="paper"
      as="aside"
      aria-label="Combat log"
      className="gw-side"
      plain={styles.panelPlain}
      style={styles.panel}
      data-combat-log="panel"
    >
      <Text tone="caption" plain={styles.caption}>
        Log
      </Text>
      <ol ref={box} style={styles.list} aria-live="polite">
        {lines.map((line, i) => (
          <Line key={i} line={line} />
        ))}
      </ol>
    </Panel>
  );
}

/** The phone's last line, and the drawer it opens. */
export function CombatLogLine({ lines }: { lines: readonly LogLine[] }) {
  const [open, setOpen] = useState(false);
  const last = lines.at(-1);
  return (
    <>
      <button
        style={styles.last}
        onClick={() => setOpen(true)}
        aria-label={`Log: ${last?.text ?? "nothing yet"}. Open the log`}
        data-combat-log="line"
      >
        <span aria-hidden style={styles.lastText}>
          {last ? <LineText line={last} /> : " "}
        </span>
        <span aria-hidden>▴</span>
      </button>
      {open && (
        <div style={styles.drawer} role="dialog" aria-label="Combat log" data-combat-log="drawer">
          <Panel variant="paper" plain={styles.panelPlain} style={styles.drawerPanel}>
            <ol style={{ ...styles.list, maxHeight: "none" }}>
              {lines.map((line, i) => (
                <Line key={i} line={line} />
              ))}
            </ol>
            <Button variant="quiet" plain={styles.close} onClick={() => setOpen(false)}>
              Close
            </Button>
          </Panel>
        </div>
      )}
    </>
  );
}

function Line({ line }: { line: LogLine }) {
  return (
    <li style={styles.item} data-tone={line.tone} data-status={line.status}>
      <LineText line={line} />
    </li>
  );
}

function LineText({ line }: { line: LogLine }) {
  return (
    <span
      style={{
        ...(line.status === "predicted" ? styles.predicted : {}),
        ...(line.status === "struck" ? styles.struck : {}),
        ...(line.tone === "refusal" ? styles.refusal : {}),
      }}
    >
      {line.text}
    </span>
  );
}

/** The desktop panel shows this many lines, then scrolls back (§7.3). */
export const LINES_SHOWN = 12;

const LINE_REM = 1.25;

const styles: Record<string, CSSProperties> = {
  panel: { display: "flex", flexDirection: "column", minHeight: 0 },
  panelPlain: { padding: 16, background: "#16161c", color: "#eee" },
  caption: { color: "#9a9aa6", fontSize: "0.8125rem", margin: "0 0 6px" },
  list: {
    margin: 0,
    padding: 0,
    listStyle: "none",
    maxHeight: `${LINES_SHOWN * LINE_REM}rem`,
    overflowY: "auto",
    font: `0.8125rem/${LINE_REM}rem system-ui`,
  },
  item: { margin: 0 },
  predicted: { opacity: 0.72 },
  struck: { textDecoration: "line-through", opacity: 0.6 },
  refusal: { fontStyle: "italic", opacity: 0.75 },
  last: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    flex: "none",
    boxSizing: "border-box",
    width: "100%",
    minHeight: 44,
    padding: "0 12px",
    border: "none",
    borderTop: "1px solid #2a2a33",
    background: "#16161c",
    color: "#eee",
    font: "0.8125rem system-ui",
    textAlign: "left",
    cursor: "pointer",
  },
  lastText: { flex: 1, overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" },
  drawer: {
    position: "absolute",
    inset: 0,
    zIndex: 3,
    display: "flex",
    alignItems: "flex-end",
    background: "rgba(0,0,0,0.55)",
  },
  drawerPanel: { width: "100%", maxHeight: "70%", overflowY: "auto", margin: 0 },
  close: {
    marginTop: 8,
    minHeight: 44,
    padding: "0 14px",
    border: "1px solid #3a3a44",
    borderRadius: 8,
    background: "transparent",
    color: "#eee",
  },
};
