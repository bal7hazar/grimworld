import type { ServiceId } from "../input/intent";
import type { Profession } from "./view";

/**
 * The hub renderer's input (CLI-03c), as `view.ts` is the room's: what a hub shows, as data. Hubs
 * have no geometry (design/11 *Hubs*, D-03): an illustration with places to tap. Its coordinates
 * are those of the illustration, in its own units (art pixels at scale 1), `x` to the right and
 * `y` down; the screen fits the whole illustration in its middle zone.
 */

/** Where a place leads: a service's screen, or the Gate screen. */
export type HubTarget =
  { readonly kind: "service"; readonly service: ServiceId } | { readonly kind: "gate" };

/** A building standing on the ground, a place to tap. */
export interface HubPlace {
  /** Unique in the hub; the tap target's name in the page. */
  readonly id: string;
  readonly label: string;
  readonly target: HubTarget;
  /** The building's still in the atlas (`tools/art`, role `building`); a shape without it. */
  readonly building: string;
  /** The middle of its base, where it stands on the ground. */
  readonly x: number;
  readonly y: number;
  /** The footprint drawn: the still is scaled to `width`; a shape fills `width` × `height`. */
  readonly width: number;
  readonly height: number;
}

/** A present adventurer (design/09: listed by the indexer later), drawn as decor. */
export interface HubFigure {
  readonly id: number;
  readonly name: string;
  readonly profession: Profession;
  readonly level: number;
  /** Where its feet stand; it stands still (D-178: no movement rule). */
  readonly x: number;
  readonly y: number;
  readonly facing: "left" | "right";
}

export interface HubView {
  readonly name: string;
  readonly gold: number;
  /** The illustration's size, in its units. */
  readonly width: number;
  readonly height: number;
  /** The buildings, drawn back to front in this order. */
  readonly places: readonly HubPlace[];
  readonly figures: readonly HubFigure[];
  /** The service entries under the illustration, in reading order; the Gate last. */
  readonly services: readonly HubTarget[];
}

/** One label per target: the building's tap and its service entry name the same screen. */
export function targetLabel(target: HubTarget): string {
  if (target.kind === "gate") return "Gate";
  return target.service[0]!.toUpperCase() + target.service.slice(1);
}

export function sameTarget(a: HubTarget, b: HubTarget): boolean {
  return a.kind === "gate" ? b.kind === "gate" : b.kind === "service" && a.service === b.service;
}
