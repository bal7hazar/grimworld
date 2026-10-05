import { type HudEntryName, PORTRAITS } from "../../chrome/load";
import type { Profession } from "../../render/view";
import type { AdventurerSheet } from "../fixtures/hubs";

/**
 * What the status band draws (CLI-03l *The method* §1), from the sheet alone: no rule, nothing
 * computed but text. Pure, so it is tested without a DOM (the client adds no DOM test dependency).
 * CLI-04 replaces the sheet's placeholder figures with the actor's state; the band follows.
 */

export interface HudMeter {
  readonly key: "health" | "energy";
  /** The meter's accessible name. */
  readonly label: string;
  /** Text, in the figures' colour: the pack has no heart or lightning icon. */
  readonly glyph: string;
  readonly size: "big" | "small";
  readonly current: number;
  readonly max: number;
  /** The visible figures, `current / max`. */
  readonly text: string;
  readonly aria: {
    readonly "aria-valuemin": number;
    readonly "aria-valuemax": number;
    readonly "aria-valuenow": number;
  };
}

export interface HudModel {
  readonly portrait: {
    readonly profession: Profession;
    /** The pack's avatar entry, or `plain` (the Arcanist, or no HUD art): the lettered disc. */
    readonly entry: HudEntryName | "plain";
    readonly label: string;
  };
  readonly meters: readonly [HudMeter, HudMeter];
  /** The count of strikes, or null for a profession without adrenaline. */
  readonly adrenaline: { readonly count: number; readonly label: string } | null;
}

const PROFESSION: Readonly<Record<Profession, string>> = {
  vanguard: "Vanguard",
  warden: "Warden",
  cleric: "Cleric",
  arcanist: "Arcanist",
};

/** "Wren, Vanguard level 4": who a portrait shows. */
export function portraitLabel(sheet: {
  readonly name: string;
  readonly profession: Profession;
  readonly level: number;
}): string {
  return `${sheet.name}, ${PROFESSION[sheet.profession]} level ${sheet.level}`;
}

function meter(
  key: HudMeter["key"],
  label: string,
  glyph: string,
  size: HudMeter["size"],
  gauge: AdventurerSheet["health"],
): HudMeter {
  const now = Math.min(Math.max(gauge.current, 0), gauge.max);
  return {
    key,
    label,
    glyph,
    size,
    current: gauge.current,
    max: gauge.max,
    text: `${gauge.current} / ${gauge.max}`,
    aria: { "aria-valuemin": 0, "aria-valuemax": gauge.max, "aria-valuenow": now },
  };
}

/** The band's content for `sheet`, with the HUD's art (`atlas`) or without it (`plain`). */
export function hudModel(sheet: AdventurerSheet, mode: "atlas" | "plain"): HudModel {
  const entry = PORTRAITS[sheet.profession];
  return {
    portrait: {
      profession: sheet.profession,
      entry: mode === "atlas" && entry !== null ? entry : "plain",
      label: portraitLabel(sheet),
    },
    meters: [
      meter("health", "Health", "♥", "big", sheet.health),
      meter("energy", "Energy", "⚡", "small", sheet.energy),
    ],
    adrenaline:
      sheet.adrenaline === null
        ? null
        : {
            count: sheet.adrenaline,
            label: `Adrenaline: ${sheet.adrenaline} ${sheet.adrenaline === 1 ? "strike" : "strikes"}`,
          },
  };
}
