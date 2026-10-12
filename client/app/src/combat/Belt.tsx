import type { CSSProperties } from "react";
import { SlotFrame } from "../chrome/Chrome";
import { SLOT_BADGE } from "../chrome/contrast";
import { SLOT_PX, initials, usePress } from "./SkillBar";
import type { Armed, BeltSlot, BeltState, PotionLook } from "./state";

/**
 * The belt (CLI-05 brief §3): four slots in one row under the bar, `Z X C V` on desktop. A slot
 * with a potion shows its flask (§8's placeholder, drawn by code, filled by its effect, with its
 * initials) and its count in the corner; one whose count is 0 greys the flask and shows `0` (the
 * potion stays the slot's: the belt is fixed for the expedition); one with no item is a dimmed
 * frame. A tap or the key arms it like a skill; a long press or a right click inspects.
 */
export function Belt({
  belt,
  armed,
  keys,
  onSlot,
  onInspect,
}: {
  belt: readonly BeltSlot[];
  armed: Armed | null;
  keys: boolean;
  onSlot: (slot: number) => void;
  onInspect: (slot: number) => void;
}) {
  return (
    <div role="group" aria-label="Belt" style={styles.row} data-belt="">
      {belt.map((slot) => (
        <BeltItem
          key={slot.slot}
          slot={slot}
          armed={armed?.kind === "item" && armed.slot === slot.slot}
          keys={keys}
          onTap={() => onSlot(slot.slot)}
          onInspect={() => onInspect(slot.slot)}
        />
      ))}
    </div>
  );
}

/** The belt's keys by position (CLI-05b): QWERTY's `Z X C V`, AZERTY's `W X C V`. */
const KEYS = ["Z", "X", "C", "V"] as const;

/** The flask's fill by the potion's effect (§8): the pairs `contrast.ts`'s `SLOT_TEXT` checks. */
export const FLASK_FILLS: Readonly<Record<PotionLook, string>> = {
  heal: "#a8322a",
  regeneration: "#2b6e48",
  other: "#5d4f8e",
};

const STATE_WORDS: Readonly<Record<BeltState, string>> = {
  empty: "empty",
  some: "ready",
  "none-left": "none left",
  "not-now": "not now",
};

function BeltItem({
  slot,
  armed,
  keys,
  onTap,
  onInspect,
}: {
  slot: BeltSlot;
  armed: boolean;
  keys: boolean;
  onTap: () => void;
  onInspect: () => void;
}) {
  const press = usePress(onTap, onInspect);
  const key = keys ? <span style={styles.key}>{KEYS[slot.slot]}</span> : null;
  if (slot.item === null) {
    return (
      <SlotFrame
        pressed={false}
        plain={styles.plain}
        style={{ ...styles.slot, opacity: 0.35 }}
        aria-label={`Belt ${KEYS[slot.slot]}: empty`}
        data-belt-slot={slot.slot}
        data-state="empty"
        onClick={onTap}
      >
        {key}
      </SlotFrame>
    );
  }
  const name = slot.name ?? `Potion ${slot.item}`;
  const none = slot.state === "none-left";
  return (
    <SlotFrame
      pressed={armed}
      plain={{ ...styles.plain, ...(armed ? styles.plainArmed : {}) }}
      style={{
        ...styles.slot,
        ...(armed ? styles.armed : {}),
        ...(slot.state === "not-now" ? { opacity: 0.45 } : {}),
      }}
      aria-label={`Belt ${KEYS[slot.slot]}, ${name}: ${STATE_WORDS[slot.state]}, ${slot.count} left`}
      aria-pressed={armed}
      data-belt-slot={slot.slot}
      data-state={slot.state}
      {...press}
    >
      <Flask fill={FLASK_FILLS[slot.look]} text={initials(name)} greyed={none} />
      {key}
      <span aria-hidden style={styles.count} data-count={slot.count}>
        {slot.count}
      </span>
    </SlotFrame>
  );
}

/** A flask outline drawn by code, its body filled, its initials on the fill. */
function Flask({ fill, text, greyed }: { fill: string; text: string; greyed: boolean }) {
  return (
    <svg
      aria-hidden
      width={34}
      height={36}
      viewBox="0 0 34 36"
      style={greyed ? { filter: "grayscale(1)", opacity: 0.45 } : undefined}
    >
      <path
        d="M12 2h10v3h-1v7l9 13a6 6 0 0 1-5 9H9a6 6 0 0 1-5-9l9-13V5h-1z"
        fill={fill}
        stroke="#f2eadb"
        strokeWidth={2}
        strokeLinejoin="round"
      />
      <text
        x={17}
        y={28}
        textAnchor="middle"
        fill="#fff"
        style={{ font: "700 0.6875rem var(--gw-display)" }}
      >
        {text}
      </text>
    </svg>
  );
}

const BADGE = `#${SLOT_BADGE.toString(16).padStart(6, "0")}`;

const styles: Record<string, CSSProperties> = {
  row: { display: "flex", gap: 6 },
  slot: {
    position: "relative",
    flex: "none",
    width: SLOT_PX,
    height: SLOT_PX,
    boxSizing: "border-box",
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    cursor: "pointer",
    color: "#fff",
    touchAction: "manipulation",
    userSelect: "none",
  },
  plain: { padding: 0, border: "2px solid #3a3a44", borderRadius: 6, background: "#1b1b22" },
  plainArmed: { borderColor: "#f2c94c", background: "#2a2a33" },
  armed: { outline: "2px solid #f2c94c", outlineOffset: 1 },
  key: {
    position: "absolute",
    top: 1,
    left: 1,
    minWidth: 14,
    padding: "0 3px",
    borderRadius: 3,
    background: BADGE,
    font: "600 0.6875rem/0.875rem var(--gw-display)",
    color: "#fff",
  },
  count: {
    position: "absolute",
    right: 1,
    bottom: 1,
    minWidth: 14,
    padding: "0 3px",
    borderRadius: 3,
    background: BADGE,
    font: "600 0.75rem/0.9375rem var(--gw-display)",
    color: "#fff",
    textAlign: "center",
    fontVariantNumeric: "tabular-nums",
  },
};
