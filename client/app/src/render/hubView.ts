import { type Point, tileToPixel } from "../input/coords";
import type { ServiceId } from "../input/intent";
import type { Profession, Tile } from "./view";

/**
 * A hub's content, as data (CLI-03c, CLI-03e): its places, decor buildings, props and present
 * adventurers, each on a hex of the room's grid (`input/coords.ts`). A hub has no geometry on chain
 * (design/11 *Hubs*, D-03): no rule. Since CLI-03f a hub is lived like an exploration zone (D-196,
 * D-202): `sandbox/fixtures/hubWorld.ts` turns this data into a `SandboxWorld`, and the zone's
 * controller, session and renderer walk and draw it. The illustration's rectangle (`width`,
 * `height`, `origin`, in art pixels, `x` to the right and `y` down) only bounds the island.
 */

/** Where a place leads: a service's screen, or the Gate screen. */
export type HubTarget =
  { readonly kind: "service"; readonly service: ServiceId } | { readonly kind: "gate" };

/** A building standing on the ground, a place to walk to. */
export interface HubPlace {
  /** Unique in the hub. */
  readonly id: string;
  readonly label: string;
  readonly target: HubTarget;
  /** The building's still in the atlas (`tools/art`, role `building`); a shape without it. */
  readonly building: string;
  /** Its anchor tile, its door: the middle of its base stands on the hex's centre. */
  readonly at: Tile;
  /** Its native size in art pixels (the still's visible width, and height above its base). */
  readonly width: number;
  readonly height: number;
  /** Rows behind its base row that it stands on (CLI-03f): 1 when absent. */
  readonly depth?: number;
}

/** A building that is not a place: life around the services. Not a target, no label. */
export interface HubDecor {
  readonly id: string;
  readonly building: string;
  readonly at: Tile;
  /** Its native size, for its footprint and the shape drawn without the atlas. */
  readonly width: number;
  readonly height: number;
  /** Rows behind its base row that it stands on (CLI-03f): 1 when absent. */
  readonly depth?: number;
}

/** A tree, a bush, a rock, a stump, a sheep (`tools/art`, role `prop`): drawn at one frame. */
export interface HubProp {
  readonly id: string;
  readonly sprite: string;
  readonly at: Tile;
  readonly mirror?: boolean;
}

/** A present adventurer (design/09: listed by the indexer later); it stands still (D-194). */
export interface HubFigure {
  readonly id: number;
  readonly name: string;
  readonly profession: Profession;
  readonly level: number;
  readonly at: Tile;
  readonly facing: "left" | "right";
}

export interface HubView {
  readonly name: string;
  readonly gold: number;
  /** The illustration's rectangle, in art pixels: the island is the hexes inside it. */
  readonly width: number;
  readonly height: number;
  /** Where the centre of tile (0, 0) is in the rectangle (x grows West, y North). */
  readonly origin: Point;
  readonly places: readonly HubPlace[];
  readonly decor: readonly HubDecor[];
  readonly props: readonly HubProp[];
  readonly figures: readonly HubFigure[];
  /** The service entries under the map, in reading order; the Gate last. */
  readonly services: readonly HubTarget[];
  /** Where the player's adventurer stands on arriving in the hub (CLI-03f): beside the Gate. */
  readonly arrival: Tile;
}

/** One label per target: the building's tap and its service entry name the same screen. */
export function targetLabel(target: HubTarget): string {
  if (target.kind === "gate") return "Gate";
  return target.service[0]!.toUpperCase() + target.service.slice(1);
}

export function sameTarget(a: HubTarget, b: HubTarget): boolean {
  return a.kind === "gate" ? b.kind === "gate" : b.kind === "service" && a.service === b.service;
}

/** A tile's centre in the illustration's rectangle: the room's conversion, from the hub's origin. */
export function hubPoint(view: Pick<HubView, "origin">, tile: Tile): Point {
  const p = tileToPixel(tile);
  return { x: view.origin.x + p.x, y: view.origin.y + p.y };
}
