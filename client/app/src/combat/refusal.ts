/**
 * What is refused before the batch, in words the player reads (CLI-05 brief §4.4; I-3: nothing about
 * the chain). The line of an `Illegal` the mirror stops a skill or item action on, the line a tap on
 * a slot that is not ready says (§2.4), and the line of an interaction, which main does not offer.
 */

import { Illegal } from "@grimworld/sim";
import type { BarSlot, BeltSlot } from "./state";

/** A tap on a gate, a chest or a lever: `interact` is refused by the mirror and the contract alike. */
export const NOT_AVAILABLE_YET = "Not available yet.";

const plural = (n: number, word: string): string => `${n} ${word}${n === 1 ? "" : "s"}`;

/**
 * The line of a refusal before the batch; null for `Empty` (an empty slot is never armed) and for
 * the refusals a skill or item tap never reaches (`Clock`, `Absent`, `Turned`, `Blocked`), which are
 * logged as a parity record instead. `ticks` is a recharge's ticks left.
 */
export function refusalLine(illegal: number, ticks?: number): string | null {
  switch (illegal) {
    case Illegal.Knocked:
      return "You are knocked down.";
    case Illegal.Instant:
      return "Only one instant skill between two ticks.";
    case Illegal.Belt:
      return "None left.";
    case Illegal.Kind:
      return "Needs its weapon.";
    case Illegal.Recharging:
      return ticks === undefined ? "Recharging." : `Recharging: ${plural(ticks, "tick")}.`;
    case Illegal.Energy:
      return "Not enough energy.";
    case Illegal.Adrenaline:
      return "Not enough adrenaline.";
    case Illegal.Target:
      return "Not a valid target.";
    case Illegal.Reach:
      return "Out of reach.";
    case Illegal.Trap:
      return "A trap cannot go there.";
    default:
      return null;
  }
}

/** The refusals a skill or item tap cannot reach: seen, they are a parity record (§4.4). */
export const UNREACHABLE: readonly number[] = [
  Illegal.Clock,
  Illegal.Absent,
  Illegal.Turned,
  Illegal.Blocked,
];

/** The one line a tap on a bar slot that is not ready says (§2.4); null for a ready or empty slot. */
export function slotLine(slot: BarSlot, knocked: boolean): string | null {
  switch (slot.state) {
    case "not-now":
      return knocked ? refusalLine(Illegal.Knocked) : "You are activating a skill.";
    case "activating":
      return `Activating: ${plural(slot.ticks ?? 0, "tick")}.`;
    case "unavailable":
      return "Not available.";
    case "wrong-weapon":
      return refusalLine(Illegal.Kind);
    case "recharging":
      return refusalLine(Illegal.Recharging, slot.ticks ?? undefined);
    case "short-adrenaline":
      return refusalLine(Illegal.Adrenaline);
    case "short-energy":
      return refusalLine(Illegal.Energy);
    default:
      return null;
  }
}

/** The line a tap on a belt slot that cannot be used says; null when it can, or holds no item. */
export function beltLine(slot: BeltSlot, knocked: boolean): string | null {
  if (slot.state === "none-left") return refusalLine(Illegal.Belt);
  if (slot.state === "not-now") {
    return knocked ? refusalLine(Illegal.Knocked) : "You are activating a skill.";
  }
  return null;
}
