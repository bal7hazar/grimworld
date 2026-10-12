import { type CSSProperties, type MouseEvent, type ReactNode, useRef } from "react";
import { Button, Icon, Panel, SlotFrame } from "../chrome/Chrome";
import { SLOT_BADGE } from "../chrome/contrast";
import type { ActivationView, Armed, BarSlot, BeltSlot, SkillLook, SlotState } from "./state";

/**
 * The skill bar (CLI-05 brief §2): eight slots in two rows of four, `Wait` and `Turn` at the rows'
 * right. A slot shows its skill's monogram (§8's placeholder), its key on desktop, its costs (energy
 * as a figure, adrenaline as the sword and the strikes) and its one state (§2.2): an empty slot is a
 * dimmed frame; "not now" dims the whole bar but the activating slot, which fills a ring and shows
 * its ticks; the wrong weapon greys the monogram under a crossed sword; a recharge darkens it under
 * its ticks as a large figure; a cost the gauges cannot pay is red and underlined. Colour is never
 * the only carrier. The armed slot is pressed and outlined.
 *
 * A tap arms (§2.4), a long press or a right click inspects; both are the controller's.
 */
export function SkillBar({
  bar,
  armed,
  activation,
  keys,
  onSlot,
  onInspect,
  onWait,
  onTurn,
}: {
  bar: readonly BarSlot[];
  armed: Armed | null;
  /** The adventurer's activation, for the activating slot's ring. */
  activation: ActivationView | null;
  /** The keys `1`–`8` in a corner: desktop only. */
  keys: boolean;
  onSlot: (slot: number) => void;
  onInspect: (slot: number) => void;
  onWait?: () => void;
  onTurn?: () => void;
}) {
  const busy = bar.some((s) => s.state === "not-now" || s.state === "activating");
  const rows = [bar.slice(0, 4), bar.slice(4, 8)];
  return (
    <div role="group" aria-label="Skills" style={styles.bar} data-skill-bar="">
      {rows.map((row, r) => (
        <div key={r} style={styles.row}>
          {row.map((slot) => (
            <SkillSlot
              key={slot.slot}
              slot={slot}
              armed={armed?.kind === "skill" && armed.slot === slot.slot}
              dimmed={busy && slot.state !== "activating"}
              activation={slot.state === "activating" ? activation : null}
              keys={keys}
              onTap={() => onSlot(slot.slot)}
              onInspect={() => onInspect(slot.slot)}
            />
          ))}
          {r === 0 ? (
            <Button
              variant="quiet"
              plain={styles.side}
              style={styles.sidePlace}
              onClick={onWait}
              disabled={!onWait}
            >
              Wait
            </Button>
          ) : (
            <Button
              variant="quiet"
              plain={{ ...styles.side, opacity: onTurn ? 1 : 0.45 }}
              style={styles.sidePlace}
              onClick={onTurn}
              disabled={!onTurn}
              title={onTurn ? undefined : "Turn is played on chain (CLI-11); the sandbox has none"}
            >
              Turn
            </Button>
          )}
        </div>
      ))}
    </div>
  );
}

/** "Cleave" → "Cl", "Shield bash" → "SB": the monogram's two initials (§8). */
export function initials(name: string): string {
  const words = name.split(/\s+/).filter(Boolean);
  if (words.length >= 2) return (words[0]![0]! + words[1]![0]!).toUpperCase();
  const word = words[0] ?? "?";
  return word.charAt(0).toUpperCase() + word.charAt(1).toLowerCase();
}

/** The monogram's ground by skill kind (§8): the pairs `contrast.ts`'s `SLOT_TEXT` checks. */
export const MONOGRAM_GROUNDS: Readonly<Record<SkillLook, string>> = {
  attack: "#8e2f2f",
  spell: "#3b4a8c",
  stance: "#2f6b4a",
  shout: "#80531a",
  trap: "#5a4632",
  other: "#4a4f5a",
};

/** A slot's state in words, for its accessible name. */
const STATE_WORDS: Readonly<Record<SlotState, string>> = {
  empty: "empty",
  "not-now": "not now",
  activating: "activating",
  unavailable: "not available",
  "wrong-weapon": "needs its weapon",
  recharging: "recharging",
  "short-adrenaline": "not enough adrenaline",
  "short-energy": "not enough energy",
  ready: "ready",
};

/** A long press on a touch screen: held this long, the slot is inspected instead of tapped. */
const PRESS_MS = 500;

/**
 * A tap, a long press (on touch, `PRESS_MS`) and a right click on a slot: the press inspects and
 * swallows the tap that ends it.
 */
export function usePress(onTap: () => void, onInspect: () => void) {
  const timer = useRef<number | undefined>(undefined);
  const pressed = useRef(false);
  const stop = () => window.clearTimeout(timer.current);
  // A touch raises `pointerleave` after `pointerup` and before `click`: only a pointer that left or
  // was cancelled while still down drops the press, so the click that ends a press stays swallowed.
  const up = useRef(false);
  const leave = () => {
    stop();
    if (!up.current) pressed.current = false;
  };
  // A touch long press already fired `onInspect`; the `contextmenu` it also raises must not repeat it.
  const touched = useRef(false);
  return {
    onClick: () => {
      if (pressed.current) pressed.current = false;
      else onTap();
    },
    onContextMenu: (event: MouseEvent) => {
      event.preventDefault();
      if (!(touched.current && pressed.current)) onInspect();
    },
    onPointerDown: (event: { pointerType: string }) => {
      up.current = false;
      touched.current = event.pointerType === "touch";
      if (!touched.current) return;
      pressed.current = false;
      timer.current = window.setTimeout(() => {
        pressed.current = true;
        onInspect();
      }, PRESS_MS);
    },
    onPointerUp: () => {
      up.current = true;
      stop();
    },
    onPointerLeave: leave,
    onPointerCancel: leave,
  };
}

function SkillSlot({
  slot,
  armed,
  dimmed,
  activation,
  keys,
  onTap,
  onInspect,
}: {
  slot: BarSlot;
  armed: boolean;
  dimmed: boolean;
  activation: ActivationView | null;
  keys: boolean;
  onTap: () => void;
  onInspect: () => void;
}) {
  const press = usePress(onTap, onInspect);
  const { skill, state } = slot;
  const key = keys ? <span style={styles.key}>{slot.slot + 1}</span> : null;
  if (!skill) {
    return (
      <SlotFrame
        pressed={false}
        plain={styles.plain}
        style={{ ...styles.slot, opacity: 0.35 }}
        aria-label={`Skill ${slot.slot + 1}: empty`}
        data-slot={slot.slot}
        data-state="empty"
        onClick={onTap}
      >
        {key}
      </SlotFrame>
    );
  }
  const name = skill.name ?? `Skill ${skill.id}`;
  const greyed = state === "wrong-weapon" || state === "unavailable";
  const dark = state === "recharging" || state === "activating";
  const ticks = slot.ticks ?? 0;
  const spent = activation ? (activation.total - activation.ticks) / activation.total : 0;
  const words = [
    `Skill ${slot.slot + 1}, ${name}: ${STATE_WORDS[state]}`,
    state === "recharging" || state === "activating" ? `${ticks} ticks` : "",
    skill.energy > 0 ? `${skill.energy} energy` : "",
    skill.strikes > 0 ? `${skill.strikes} strikes of adrenaline` : "",
  ].filter(Boolean);
  return (
    <SlotFrame
      pressed={armed}
      plain={{ ...styles.plain, ...(armed ? styles.plainArmed : {}) }}
      style={{
        ...styles.slot,
        ...(armed ? styles.armed : {}),
        ...(dimmed ? { opacity: 0.45 } : {}),
      }}
      aria-label={words.join(", ")}
      aria-pressed={armed}
      data-slot={slot.slot}
      data-state={state}
      {...press}
    >
      <span
        aria-hidden
        style={{
          ...styles.monogram,
          background: MONOGRAM_GROUNDS[skill.look],
          ...(greyed ? { filter: "grayscale(1)", opacity: 0.6 } : {}),
          ...(dark ? { filter: "brightness(0.35)" } : {}),
        }}
      >
        {initials(name)}
      </span>
      {key}
      <span aria-hidden style={styles.costs}>
        {skill.energy > 0 && (
          <span
            style={{
              ...styles.badge,
              color: "#5fb8c4",
              ...(state === "short-energy" ? styles.short : {}),
            }}
            data-cost="energy"
          >
            {skill.energy}
          </span>
        )}
        {skill.strikes > 0 && (
          <span
            style={{ ...styles.badge, ...(state === "short-adrenaline" ? styles.short : {}) }}
            data-cost="adrenaline"
          >
            <Icon name="sword" text="⚔" />
            {skill.strikes}
          </span>
        )}
      </span>
      {state === "wrong-weapon" && (
        <span aria-hidden style={styles.crossed}>
          <span style={styles.crossedSword}>
            <Icon name="sword" text="⚔" />
          </span>
          <span style={styles.cross} />
        </span>
      )}
      {state === "recharging" && (
        <span aria-hidden style={styles.ticks} data-ticks={ticks}>
          {ticks}
        </span>
      )}
      {activation && (
        <>
          <span
            aria-hidden
            style={{
              ...styles.ring,
              background: `conic-gradient(#f2c94c ${spent * 360}deg, rgba(242,201,76,0.25) 0)`,
            }}
          />
          <span aria-hidden style={styles.ticks} data-ticks={ticks}>
            {ticks}
          </span>
        </>
      )}
    </SlotFrame>
  );
}

/**
 * A slot's inspection (§2.4): name, kind, costs, activation, recharge, range and what it takes, in
 * words; a potion's name, count and what it takes. Closed by its button, `Esc` or the same press.
 */
export function Inspection({ slot, onClose }: { slot: BarSlot | BeltSlot; onClose: () => void }) {
  const rows: [string, ReactNode][] = [];
  let title: string;
  if ("skill" in slot) {
    const skill = slot.skill!;
    title = skill.name ?? `Skill ${skill.id}`;
    rows.push(["Kind", skill.look]);
    rows.push(["Energy", String(skill.energy)]);
    if (skill.strikes > 0) rows.push(["Adrenaline", `${skill.strikes} strikes`]);
    rows.push(["Activation", skill.activation === 0 ? "instant" : `${skill.activation} ticks`]);
    rows.push(["Recharge", skill.recharge === 0 ? "none" : `${skill.recharge} ticks`]);
    rows.push(["Range", skill.range === 0 ? "yourself" : `${skill.range} tiles`]);
    rows.push(["Takes", TAKES[skill.addressing]]);
  } else {
    title = slot.name ?? `Potion ${slot.item}`;
    rows.push(["Left", String(slot.count)]);
    rows.push(["Costs", "1 tick"]);
    if (slot.addressing) rows.push(["Takes", TAKES[slot.addressing]]);
  }
  return (
    <Panel
      variant="scroll"
      plain={styles.inspectPlain}
      style={styles.inspect}
      role="dialog"
      aria-label={`${title}: inspection`}
      data-inspection=""
    >
      <div style={styles.inspectTitle}>{title}</div>
      <dl style={styles.list}>
        {rows.map(([term, value]) => (
          <div key={term} style={styles.listRow}>
            <dt style={styles.term}>{term}</dt>
            <dd style={styles.value}>{value}</dd>
          </div>
        ))}
      </dl>
      <Button variant="quiet" plain={styles.side} onClick={onClose}>
        Close
      </Button>
    </Panel>
  );
}

const TAKES = {
  self: "you",
  foe: "a goblin in reach",
  ally: "an ally in reach (you, alone)",
  tile: "a tile in reach",
} as const;

/** The slot's side, at least 44 CSS px (I-6) with the frame. */
export const SLOT_PX = 52;

const styles: Record<string, CSSProperties> = {
  bar: { display: "flex", flexDirection: "column", gap: 6 },
  row: { display: "flex", gap: 6, alignItems: "stretch" },
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
  /** Without the art: a bordered square in the chrome's colours. */
  plain: {
    padding: 0,
    border: "2px solid #3a3a44",
    borderRadius: 6,
    background: "#1b1b22",
  },
  plainArmed: { borderColor: "#f2c94c", background: "#2a2a33" },
  armed: { outline: "2px solid #f2c94c", outlineOffset: 1 },
  monogram: {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    width: 32,
    height: 32,
    borderRadius: 4,
    // Not the pixel display font: its "Ch" reads "Oh" and its "SB" reads "3", the digit badge's face
    font: "700 1rem/1 system-ui, sans-serif",
    letterSpacing: "0.02em",
    color: "#fff",
  },
  key: {
    position: "absolute",
    top: 1,
    left: 1,
    minWidth: 14,
    padding: "0 3px",
    borderRadius: 3,
    background: `#${SLOT_BADGE.toString(16).padStart(6, "0")}`,
    font: "600 0.6875rem/0.875rem var(--gw-display)",
    color: "#fff",
  },
  costs: {
    position: "absolute",
    right: 1,
    bottom: 1,
    display: "flex",
    gap: 2,
  },
  badge: {
    display: "inline-flex",
    alignItems: "center",
    height: 14,
    padding: "0 3px",
    borderRadius: 3,
    background: `#${SLOT_BADGE.toString(16).padStart(6, "0")}`,
    font: "600 0.6875rem/0.875rem var(--gw-display)",
    color: "#fff",
    fontVariantNumeric: "tabular-nums",
    overflow: "hidden",
  },
  short: {
    color: "#ff6b6b",
    textDecoration: "underline",
    textDecorationThickness: 2,
    textUnderlineOffset: 1,
  },
  crossed: {
    position: "absolute",
    top: 1,
    right: 1,
    width: 18,
    height: 18,
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 3,
    background: `#${SLOT_BADGE.toString(16).padStart(6, "0")}`,
    overflow: "hidden",
    fontSize: "0.75rem",
  },
  crossedSword: { display: "inline-flex", transform: "scale(0.5)" },
  cross: {
    position: "absolute",
    left: -2,
    right: -2,
    top: "50%",
    height: 2,
    background: "#ff6b6b",
    transform: "rotate(-45deg)",
  },
  ticks: {
    position: "absolute",
    inset: 0,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    // Gold, in the pixel face, over the darkened monogram (its own face is a plain sans): a counter
    // apart from the initials that sit under it
    font: "700 1.5rem/1 var(--gw-display)",
    color: "#f2c94c",
    textShadow: "0 0 3px #000, 0 0 2px #000, 0 1px 0 #000",
    fontVariantNumeric: "tabular-nums",
  },
  ring: {
    position: "absolute",
    inset: 2,
    borderRadius: "50%",
    WebkitMask: "radial-gradient(circle, transparent 58%, #000 60%)",
    mask: "radial-gradient(circle, transparent 58%, #000 60%)",
  },
  side: {
    minHeight: 44,
    minWidth: 56,
    padding: "0 10px",
    border: "1px solid #3a3a44",
    borderRadius: 8,
    font: "0.875rem var(--gw-display)",
    color: "#eee",
    background: "transparent",
    cursor: "pointer",
  },
  sidePlace: { flex: "none", height: SLOT_PX, marginLeft: 4 },
  inspect: {
    position: "absolute",
    left: 8,
    right: 8,
    bottom: 8,
    zIndex: 2,
    maxWidth: 360,
    margin: "0 auto",
  },
  inspectPlain: {
    padding: 12,
    borderRadius: 8,
    background: "#1b1b22",
    border: "1px solid #3a3a44",
    color: "#eee",
  },
  inspectTitle: { font: "700 1.125rem var(--gw-display)", marginBottom: 6 },
  list: { margin: "0 0 8px", display: "grid", gap: 2 },
  listRow: { display: "flex", gap: 8 },
  term: { minWidth: 88, opacity: 0.75 },
  value: { margin: 0 },
};
