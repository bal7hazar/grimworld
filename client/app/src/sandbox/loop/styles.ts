import type { CSSProperties } from "react";

/** The loop's screens (CLI-03c): plain, dark, every control at least 44 px (design/11 I-6). */
export const ui: Record<string, CSSProperties> = {
  screen: {
    position: "absolute",
    inset: 0,
    display: "flex",
    flexDirection: "column",
    color: "#eee",
    background: "#0b0b0e",
    font: "0.9375rem system-ui",
  },
  header: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
    minHeight: 52,
    padding: "0 12px",
    background: "#16161c",
    borderBottom: "1px solid #2a2a33",
  },
  title: { fontSize: "1.125rem", fontWeight: 600 },
  gold: { color: "#f2c94c", fontVariantNumeric: "tabular-nums" },
  body: { flex: 1, overflowY: "auto", padding: 12 },
  section: { margin: "0 0 16px" },
  label: { color: "#9a9aa6", fontSize: "0.8125rem", margin: "0 0 6px" },
  card: {
    padding: 12,
    margin: "0 0 10px",
    borderRadius: 8,
    background: "#1b1b22",
    border: "1px solid #2a2a33",
  },
  button: {
    minHeight: 44,
    minWidth: 44,
    padding: "0 14px",
    border: "none",
    borderRadius: 8,
    font: "0.9375rem system-ui",
    color: "#111",
    background: "#e9e4d4",
    cursor: "pointer",
  },
  primary: { background: "#f2c94c", fontWeight: 600 },
  quiet: { background: "transparent", color: "#eee", border: "1px solid #3a3a44" },
  debug: {
    background: "rgba(80,0,0,0.75)",
    color: "#ffb4b4",
    border: "1px dashed #ff6b6b",
    font: "0.75rem ui-monospace, monospace",
  },
  grid: {
    display: "grid",
    // Three columns at the default size (a column is at least 6.5 rem, 104 px); as the text grows
    // the columns widen with it and the row falls to two, then one, so no label is clipped.
    gridTemplateColumns: "repeat(auto-fit, minmax(6.5rem, 1fr))",
    gap: 6,
    padding: 8,
    background: "#16161c",
    borderTop: "1px solid #2a2a33",
  },
  list: { margin: 0, paddingLeft: 18, lineHeight: 1.6 },
  row: { display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8 },
  muted: { color: "#9a9aa6" },
};
