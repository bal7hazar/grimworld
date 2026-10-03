import { targetIntent } from "../../input/hubTaps";
import type { Intent, LoopIntent } from "../../input/intent";
import { type HubPlace, type HubView, sameTarget } from "../../render/hubView";
import type { Tile } from "../../render/view";
import { GATES, GATE_KIND, type GateRecord } from "../fixtures/region";

/**
 * What `F` / `Shift+F` select (CLI-03k): a hub's places, or a zone's hub gates. Pure listings of
 * fixed data, presentation only: which gate the adventurer may leave by stays the machine's rule.
 */

/** A hub's places in the order of its service row, so that `F`, `1`–`9` and the row agree. */
export function hubTargets(view: HubView): HubPlace[] {
  return view.services.flatMap((target) => {
    const place = view.places.find((p) => sameTarget(p.target, target));
    return place ? [place] : [];
  });
}

export interface ZoneTarget {
  readonly gate: GateRecord;
  readonly tile: Tile;
}

/**
 * A location's hub gates, lowest id first, revealed or not, each on its anchor's hex. The anchor
 * is read by the caller (`anchorOf`), the instance's screen, which already reads gate records.
 */
export function zoneTargets(location: number, anchorOf: (gate: GateRecord) => Tile): ZoneTarget[] {
  return GATES.filter((g) => g.source === location && g.kind === GATE_KIND.hub)
    .sort((a, b) => a.id - b.id)
    .map((gate) => ({ gate, tile: anchorOf(gate) }));
}

/**
 * The target after `current` by `by`, wrapping; with none selected, the first (or the last, going
 * back); null when there is nothing to select.
 */
export function nextTarget(count: number, current: number | null, by: 1 | -1): number | null {
  if (count <= 0) return null;
  if (current === null || current < 0 || current >= count) return by > 0 ? 0 : count - 1;
  return (current + by + count) % count;
}

/** Enter on a selected place: the same map intent as a tap on its door. */
export function goIntent(tile: Tile): Intent {
  return { kind: "tile", tile };
}

/** `1`–`9` in a hub: the service row's own intent for its `index`-th button, or none. */
export function serviceIntent(view: HubView, index: number): LoopIntent | null {
  const target = view.services[index];
  return target ? targetIntent(target) : null;
}

/** `L` in a zone: the Leave control's question, only on a hub gate's anchor (D-148). */
export function leaveAsked(
  gateHere: GateRecord | null,
): { kind: "leave"; gate: GateRecord } | null {
  return gateHere ? { kind: "leave", gate: gateHere } : null;
}
