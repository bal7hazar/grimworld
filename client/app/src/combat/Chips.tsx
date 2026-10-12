import type { CSSProperties } from "react";
import { chipModel } from "../sandbox/loop/hudModel";
import type { Chip } from "./state";

/**
 * Conditions and held effects as chips (CLI-05 brief §6.1, §8's placeholder): a letter on a
 * coloured ground and its figures beside it. The letter carries the meaning and the colour repeats
 * it (design/11 *Accessibility*); each chip names itself in words for a reader. In the status band
 * (the adventurer's, conditions first, then effects) and in the target zone (a goblin's).
 */
export function Chips({ chips, label }: { chips: readonly Chip[]; label: string }) {
  if (chips.length === 0) return null;
  return (
    <ul aria-label={label} style={styles.row} data-chips="">
      {chips.map((chip, i) => {
        const model = chipModel(chip);
        return (
          <li
            key={`${chip.letter}${i}`}
            style={styles.chip}
            title={model.label}
            aria-label={model.label}
            data-chip={chip.letter}
          >
            <span aria-hidden style={{ ...styles.letter, background: groundOf(chip) }}>
              {chip.letter}
            </span>
            {model.figure && (
              <span aria-hidden style={styles.figure}>
                {model.figure}
              </span>
            )}
          </li>
        );
      })}
    </ul>
  );
}

/** Each letter's ground: the condition's colour, an effect's (§6.1); white letters on all of them. */
const GROUNDS: Readonly<Record<string, string>> = {
  B: "#9c2b2b",
  P: "#3f6b22",
  F: "#a3471a",
  C: "#6a4a8a",
  K: "#4a5566",
  R: "#2b6e48",
  "▣": "#3b5a7a",
};

const groundOf = (chip: Chip): string =>
  GROUNDS[chip.letter] ?? (chip.kind === "effect" ? "#4a4f5a" : "#5a3a3a");

const styles: Record<string, CSSProperties> = {
  row: {
    display: "flex",
    flexWrap: "wrap",
    gap: 6,
    margin: 0,
    padding: 0,
    listStyle: "none",
  },
  chip: {
    display: "inline-flex",
    alignItems: "center",
    gap: 4,
    padding: "1px 6px 1px 1px",
    borderRadius: 4,
    background: "#111",
    color: "#fff",
    font: "600 0.8125rem/1.25rem var(--gw-display)",
    fontVariantNumeric: "tabular-nums",
    whiteSpace: "nowrap",
  },
  letter: {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    minWidth: "1.25rem",
    height: "1.25rem",
    borderRadius: 3,
    fontWeight: 700,
  },
  figure: {},
};
