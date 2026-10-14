import type { CSSProperties } from "react";
import { Bar, Panel } from "../chrome/Chrome";
import { Chips } from "./ChipRow";
import type { CombatGoblin, CombatState } from "./state";

/**
 * The target zone (CLI-05 brief §6.2), between the room and the bar: the selected goblin's caste,
 * its health as a small red bar with its figures, its mark, its chips with their figures, and its
 * activation in words ("Overhead Smash — 2 ticks, on you"), or "recovering". Nothing selected, the
 * zone stays, empty, at its height, so the bar never moves under the thumb.
 */
export function TargetZone({ state, selected }: { state: CombatState; selected: number | null }) {
  const goblin = state.goblins.find((g) => g.entity === selected && g.alive) ?? null;
  return (
    <Panel
      variant="dark"
      as="section"
      aria-label="Target"
      plain={styles.plain}
      style={styles.zone}
      data-target={goblin ? goblin.entity : ""}
    >
      {goblin && <Target state={state} goblin={goblin} />}
    </Panel>
  );
}

const capital = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** "Overhead Smash — 2 ticks, on you", "Mend Kin — 1 tick, on the runt"; "recovering". */
export function activationWords(state: CombatState, goblin: CombatGoblin): string | null {
  if (goblin.recovering) return "recovering";
  const a = goblin.activation;
  if (!a) return null;
  const name = a.name ?? `Skill ${a.skill}`;
  const ticks = `${a.ticks} ${a.ticks === 1 ? "tick" : "ticks"}`;
  let on: string;
  if (a.target.tile) on = `on (${a.target.at.x}, ${a.target.at.y})`;
  else if (a.target.entity === state.adventurer.entity) on = "on you";
  else if (a.target.entity === goblin.entity) on = "on itself";
  else {
    const target = state.goblins.find((g) => g.entity === (a.target as { entity: number }).entity);
    on = `on the ${target?.casteName ?? "goblin"}`;
  }
  return `${name} — ${ticks}, ${on}`;
}

function Target({ state, goblin }: { state: CombatState; goblin: CombatGoblin }) {
  const name = capital(goblin.casteName ?? "goblin");
  const doing = activationWords(state, goblin);
  return (
    <>
      <div style={styles.line}>
        <span style={styles.name}>{name}</span>
        {goblin.mark && (
          <span style={styles.mark} data-mark={goblin.mark}>
            {goblin.mark}
          </span>
        )}
        <span style={styles.bar}>
          <Bar
            size="small"
            tone="health"
            current={goblin.health}
            max={goblin.maxHealth}
            label={`${name}'s health`}
            aria={{
              "aria-valuemin": 0,
              "aria-valuemax": goblin.maxHealth,
              "aria-valuenow": Math.min(Math.max(goblin.health, 0), goblin.maxHealth),
            }}
          />
        </span>
        <span className="gw-hud-figure" style={styles.figure}>
          {goblin.health} / {goblin.maxHealth}
        </span>
      </div>
      <div style={styles.line}>
        {doing && (
          <span style={styles.doing} data-activation="">
            {doing}
          </span>
        )}
        <Chips chips={goblin.chips} label={`${name}'s conditions`} />
      </div>
    </>
  );
}

const styles: Record<string, CSSProperties> = {
  /** About 6 % of the height (design/11): fixed, empty or not. */
  zone: {
    display: "flex",
    flexDirection: "column",
    justifyContent: "center",
    gap: 4,
    flex: "none",
    boxSizing: "border-box",
    height: 64,
    margin: 0,
    overflow: "hidden",
  },
  plain: {
    padding: "6px 12px",
    background: "#16161c",
    borderTop: "1px solid #2a2a33",
    color: "#fff",
  },
  line: { display: "flex", alignItems: "center", gap: 8, minWidth: 0 },
  name: { font: "700 0.9375rem/1.25rem var(--gw-display)", whiteSpace: "nowrap" },
  mark: { fontSize: "0.75rem", opacity: 0.85, whiteSpace: "nowrap" },
  bar: { flex: "1 1 auto", minWidth: 0, display: "flex" },
  figure: {
    flex: "none",
    font: "600 0.8125rem/1rem var(--gw-display)",
    fontVariantNumeric: "tabular-nums",
    color: "#fff",
  },
  doing: {
    fontSize: "0.8125rem",
    whiteSpace: "nowrap",
    overflow: "hidden",
    textOverflow: "ellipsis",
  },
};
