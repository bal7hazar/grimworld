import { type CSSProperties, memo, useRef } from "react";
import { Bar, Icon, Panel, Portrait, useHudMode } from "../../chrome/Chrome";
import { ADVENTURER, type AdventurerSheet } from "../fixtures/hubs";
import { hudSheet, readParams } from "../params";
import { hudModel } from "./hudModel";

let shown: AdventurerSheet | null = null;

/**
 * The sheet the band shows: the fixed `ADVENTURER` (its placeholder figures until CLI-04), or the
 * figures of `?hud=low|empty` (presentation only, CLI-03l). Read once, so the band's prop never
 * changes while the page is open.
 */
export function bandSheet(): AdventurerSheet {
  shown ??= hudSheet(ADVENTURER, readParams(window.location.search).hud);
  return shown;
}

/**
 * The status band (CLI-03l *The method* §1): above the map in the instance and both hubs, on the
 * special paper, at most 72 CSS px tall at the default text size. The portrait, the health bar
 * (big, red) and the energy bar (small, blue) with their figures as text beside them, and for a
 * Vanguard the adrenaline: the sword and the count of strikes. It holds no control and takes no
 * tap. It renders only when `sheet` changes (`memo`); `data-hud-renders` counts its renders, so
 * the browser check sees none during a walk.
 */
export const Hud = memo(function Hud({ sheet }: { sheet: AdventurerSheet }) {
  const renders = useRef(0);
  renders.current += 1;
  const mode = useHudMode();
  const model = hudModel(sheet, mode);
  return (
    <Panel
      variant="dark"
      as="section"
      aria-label="Status"
      className="gw-hud"
      plain={styles.plain}
      style={styles.band}
      data-hud={mode}
      data-hud-renders={renders.current}
    >
      <Portrait profession={model.portrait.profession} size={48} label={model.portrait.label} />
      <div style={styles.meters}>
        {model.meters.map((m) => (
          <div key={m.key} style={styles.meter}>
            <div style={styles.bar}>
              <Bar
                size={m.size}
                tone={m.key}
                current={m.current}
                max={m.max}
                label={m.label}
                aria={m.aria}
              />
            </div>
            <span className="gw-hud-figure" style={styles.figure} data-figure={m.key}>
              <span aria-hidden>{m.glyph}</span> {m.text}
            </span>
          </div>
        ))}
      </div>
      {model.adrenaline && (
        <span role="img" aria-label={model.adrenaline.label} style={styles.adrenaline}>
          <span aria-hidden style={styles.sword}>
            <Icon name="sword" text="⚔" />
          </span>
          <span
            aria-hidden
            className="gw-hud-figure"
            style={styles.figure}
            data-figure="adrenaline"
          >
            {model.adrenaline.count}
          </span>
        </span>
      )}
    </Panel>
  );
});

const styles: Record<string, CSSProperties> = {
  /** Layout, in both looks: a row that never shrinks the map's sibling away, wrapping only at a large text size. */
  band: {
    display: "flex",
    flex: "none",
    flexWrap: "wrap",
    alignItems: "center",
    columnGap: 10,
    rowGap: 4,
    boxSizing: "border-box",
    minHeight: 72,
    margin: 0,
  },
  /** The look without the art: the plain header's slate, the special paper's 12 px inset. */
  plain: { padding: 12, background: "#16161c", color: "#fff" },
  meters: {
    flex: "1 1 12rem",
    minWidth: 0,
    display: "flex",
    flexDirection: "column",
    justifyContent: "center",
    gap: 4,
  },
  meter: { display: "flex", alignItems: "center", gap: 8 },
  bar: { flex: "1 1 auto", minWidth: 0, display: "flex" },
  figure: {
    flex: "none",
    whiteSpace: "nowrap",
    font: "600 0.8125rem/1rem var(--gw-display)",
    fontVariantNumeric: "tabular-nums",
    color: "#fff",
  },
  adrenaline: { flex: "none", display: "inline-flex", alignItems: "center", gap: 2 },
  sword: {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    width: 32,
    height: 32,
    fontSize: "1.25rem",
  },
};
